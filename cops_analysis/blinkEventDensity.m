function out = blinkEventDensity(ex, eventSource, opts)
% blinkEventDensity  Event-locked raw pupil-channel dropout density.
%
% out = blinkEventDensity(ex, 'hmm', opts)
% out = blinkEventDensity(ex, 'reward', opts)
%
% The primary blink definition is simultaneous invalidity of both pupil
% channels. Left-, right-, and either-eye dropout traces are also returned.
% Blink status is derived before interpolation, padding, or smoothing.

if nargin < 3 || isempty(opts), opts = struct(); end
defaults = struct('preSec',1.5,'postSec',3.0,'trialList',[], ...
    'useEyeTime',true,'makePlot',true,'blinkDefinition','both', ...
    'outlierMad',6, ...
    'minStateDwellSec',0.10,'minEventSeparationSec',0.50, ...
    'minRewardSeparationSec',0.50,'hmmMethod','smoothed');
opts = localDefaults(opts, defaults);
eventSource = validatestring(char(string(eventSource)), {'hmm','reward'});
definition = validatestring(char(string(opts.blinkDefinition)), ...
    {'both','either','left','right'});
fs = inferFs(ex);
timeSec = (-round(opts.preSec*fs):round(opts.postSec*fs))/fs;

if strcmp(eventSource,'hmm')
    eventOpts = struct('preSec',opts.preSec,'postSec',opts.postSec, ...
        'trialList',opts.trialList,'useEyeTime',opts.useEyeTime, ...
        'makePlot',false,'baselineWindowSec',[], ...
        'minBaselineValidFrac',0,'minEpochValidFrac',0, ...
        'minStateDwellSec',opts.minStateDwellSec, ...
        'minEventSeparationSec',opts.minEventSeparationSec, ...
        'hmmMethod',opts.hmmMethod);
    eventOpts.posCorrected = false;
    source = pupilHmmTransitions(ex,eventOpts);
    events = source.events;
    eventTimeName = 'eventTimeSec';
else
    eventOpts = struct('preSec',opts.preSec,'postSec',opts.postSec, ...
        'trialList',opts.trialList,'useEyeTime',opts.useEyeTime, ...
        'makePlot',false,'baselineWindowSec',[], ...
        'minBaselineValidFrac',0,'minEpochValidFrac',0, ...
        'minRewardSeparationSec',opts.minRewardSeparationSec);
    source = pupRew(ex,eventOpts);
    events = source.events;
    eventTimeName = 'rewardTimeRelSec';
    if ~isempty(events)
        events.eventType = repmat("reward",height(events),1);
    end
end

nEvent = height(events); nTime = numel(timeSec);
left = nan(nEvent,nTime); right = left; both = left; either = left;
for trialNo = unique(double(events.trial(:)))'
    if ~isfinite(trialNo) || trialNo < 1 || trialNo > numel(ex.Trials), continue; end
    rows = find(double(events.trial)==trialNo);
    T = ex.Trials(trialNo);
    [~,~,tRel] = reconstructEyePx(ex,T,opts.useEyeTime,struct());
    [leftInvalid,rightInvalid] = localRawInvalid( ...
        T, source.meta.pupilCenter, source.meta.pupilScale, opts.outlierMad);
    n = min([numel(tRel),numel(leftInvalid),numel(rightInvalid)]);
    if n < 2, continue; end
    tRel = double(tRel(1:n));
    leftInvalid = double(leftInvalid(1:n));
    rightInvalid = double(rightInvalid(1:n));
    for r = rows(:)'
        query = double(events.(eventTimeName)(r)) + timeSec;
        left(r,:) = interp1(tRel,leftInvalid,query,'nearest',NaN);
        right(r,:) = interp1(tRel,rightInvalid,query,'nearest',NaN);
    end
end
both = double(left==1 & right==1); both(~isfinite(left)|~isfinite(right))=NaN;
either = double(left==1 | right==1); either(~isfinite(left)|~isfinite(right))=NaN;
traces = struct('both',both,'either',either,'left',left,'right',right);
primary = traces.(definition);

figureHandle = [];
if opts.makePlot
    figureHandle = localPlot(timeSec,events,primary,eventSource,definition);
end
out = struct('events',events,'timeSec',timeSec,'traces',traces, ...
    'blinkDensity',mean(primary,1,'omitnan'),'figure',figureHandle, ...
    'opts',opts,'meta',struct('eventSource',eventSource, ...
    'blinkDefinition',definition,'samplingRateHz',fs,'nEvents',nEvent));
end

function [leftInvalid,rightInvalid] = localRawInvalid(T,center,scale,outlierMad)
n = 0;
if isfield(T,'Eye') && isfield(T.Eye,'v'), n=size(T.Eye.v,2); end
leftInvalid=true(n,1); rightInvalid=true(n,1);
if n==0, return; end
V=double(T.Eye.v);
if size(V,1)>=3
    rightInvalid = ~(isfinite(V(3,:)') & ...
        isfinite(V(1,:)') & isfinite(V(2,:)'));
    if isfinite(center.right) && isfinite(scale.right) && scale.right>0
        rightInvalid = rightInvalid | ...
            abs(V(3,:)'-center.right)>outlierMad*scale.right;
    end
end
if size(V,1)>=6
    leftInvalid = ~(isfinite(V(6,:)') & ...
        isfinite(V(4,:)') & isfinite(V(5,:)'));
    if isfinite(center.left) && isfinite(scale.left) && scale.left>0
        leftInvalid = leftInvalid | ...
            abs(V(6,:)'-center.left)>outlierMad*scale.left;
    end
end
end

function fig = localPlot(time,events,traces,eventSource,definition)
if strcmp(eventSource,'hmm')
    labels=string(events.eventCategory);
    groups={{"nonTracking_to_tracking","tracking_to_nonTracking"}, ...
        {"closer_to_farther","farther_to_closer"}};
else
    labels=string(events.eventType);
    groups={{"reward"}};
end
fig=figure('Color','w','Position',[100 50 760 920]);
tiledlayout(numel(groups),1,'TileSpacing','compact','Padding','compact');
colors=lines(4);
for p=1:numel(groups)
    ax=nexttile; hold(ax,'on');
    colorRows={[3 4],[1 2]};
    for j=1:numel(groups{p})
        name=groups{p}{j}; selected=labels==name;
        if any(selected)
            plot(ax,time,mean(traces(selected,:),1,'omitnan'), ...
                'LineWidth',2,'Color',colors(colorRows{p}(j),:), ...
                'DisplayName',name);
        end
    end
    xline(ax,0,'k--','HandleVisibility','off'); ylim(ax,[0 1]); grid(ax,'on');
    xlabel(ax,'Time from event (s)'); ylabel(ax,'Blink probability');
    legend(ax,'Location','best','Interpreter','none');
end
sgtitle(sprintf('%s-locked blink density (%s-eye definition)',eventSource,definition));
end

function opts=localDefaults(opts,defaults)
names=fieldnames(defaults);
for i=1:numel(names)
    if ~isfield(opts,names{i}) || (isempty(opts.(names{i})) && ...
            ~strcmp(names{i},'trialList'))
        opts.(names{i})=defaults.(names{i});
    end
end
end
