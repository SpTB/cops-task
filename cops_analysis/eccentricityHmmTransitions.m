function out = eccentricityHmmTransitions(ex, opts)
% eccentricityHmmTransitions  Gaze eccentricity around HMM transitions.
%
% out = eccentricityHmmTransitions(ex, opts)
% Eccentricity is Euclidean gaze distance from screen center in visual deg.
% Set opts.metric='trackedTargetResidual' to plot gaze eccentricity minus
% the eccentricity of the HMM-inferred physical target.

if nargin<2 || isempty(opts),opts=struct();end
defaults=struct('preSec',1.5,'postSec',3.0,'trialList',[], ...
    'useEyeTime',true,'makePlot',true,'excludeOutsideScreen',true, ...
    'screenPaddingPx',0,'minStateDwellSec',0.10, ...
    'minEventSeparationSec',0.50,'hmmMethod','smoothed', ...
    'hmmHardThreshold',0.9,'metric','gaze');
opts=localDefaults(opts,defaults);
opts.metric=validatestring(char(string(opts.metric)), ...
    {'gaze','trackedTargetResidual'});
eventOpts=struct('preSec',opts.preSec,'postSec',opts.postSec, ...
    'trialList',opts.trialList,'useEyeTime',opts.useEyeTime, ...
    'makePlot',false,'baselineWindowSec',[], ...
    'minBaselineValidFrac',0,'minEpochValidFrac',0, ...
    'minStateDwellSec',opts.minStateDwellSec, ...
    'minEventSeparationSec',opts.minEventSeparationSec, ...
    'hmmMethod',opts.hmmMethod,'posCorrected',false);
source=pupilHmmTransitions(ex,eventOpts); events=source.events;
timeSec=source.timeSec(:)'; traces=nan(height(events),numel(timeSec));
targetTraces=nan(height(events),numel(timeSec));
residualTraces=nan(height(events),numel(timeSec));
rect=double(ex.setup.screenRect(:)');
center=[(rect(1)+rect(3))/2,(rect(2)+rect(4))/2];
for trialNo=unique(double(events.trial(:)))'
    rows=find(double(events.trial)==trialNo); T=ex.Trials(trialNo);
    [x,y,tRel,~,valid]=reconstructEyePx(ex,T,opts.useEyeTime,struct());
    [x1,y1,x2,y2,stepIdx]=mapTargetsByStep(ex,T,tRel);
    [x1,y1,x2,y2]=localCanonicalize(x1,y1,x2,y2);
    n=min([numel(x),numel(y),numel(tRel),numel(valid),numel(stepIdx), ...
        numel(x1),numel(y1),numel(x2),numel(y2)]);
    x=double(x(1:n));y=double(y(1:n));tRel=double(tRel(1:n));valid=logical(valid(1:n));
    x1=double(x1(1:n));y1=double(y1(1:n));x2=double(x2(1:n));y2=double(y2(1:n));
    stepIdx=double(stepIdx(1:n));
    if opts.excludeOutsideScreen
        valid=valid & x>=rect(1)-opts.screenPaddingPx & ...
            x<=rect(3)+opts.screenPaddingPx & y>=rect(2)-opts.screenPaddingPx & ...
            y<=rect(4)+opts.screenPaddingPx;
    end
    ecc=nan(n,1); ecc(valid)=px2deg(hypot(x(valid)-center(1),y(valid)-center(2)),ex.setup);
    assigned=nan(n,1);
    if isfield(T,'hmm')&&isfield(T.hmm,opts.hmmMethod)
        [assigned,available]=assignHmmTrackingStateCoPs( ...
            T.hmm.(opts.hmmMethod),stepIdx,opts.hmmHardThreshold);
        if ~available,assigned(:)=NaN;end
    end
    targetEcc=nan(n,1);
    select1=assigned==1&isfinite(x1)&isfinite(y1);
    select2=assigned==2&isfinite(x2)&isfinite(y2);
    targetEcc(select1)=px2deg(hypot(x1(select1)-center(1), ...
        y1(select1)-center(2)),ex.setup);
    targetEcc(select2)=px2deg(hypot(x2(select2)-center(1), ...
        y2(select2)-center(2)),ex.setup);
    residual=ecc-targetEcc;
    for r=rows(:)'
        query=double(events.eventTimeSec(r))+timeSec;
        traces(r,:)=interp1(tRel,ecc,query,'linear',NaN);
        targetTraces(r,:)=interp1(tRel,targetEcc,query,'linear',NaN);
        residualTraces(r,:)=interp1(tRel,residual,query,'linear',NaN);
    end
end
plotTraces=traces;
if strcmp(opts.metric,'trackedTargetResidual'),plotTraces=residualTraces;end
fig=[];if opts.makePlot,fig=localPlot(timeSec,events,plotTraces,opts.metric);end
out=struct('events',events,'timeSec',timeSec,'traces',traces, ...
    'trackedTargetEccentricityTraces',targetTraces, ...
    'trackedTargetResidualTraces',residualTraces, ...
    'meanEccentricityDeg',mean(traces,1,'omitnan'),'figure',fig, ...
    'opts',opts,'meta',struct('nEvents',height(events), ...
    'screenCenterPx',center,'units','deg'));
end

function fig=localPlot(time,events,traces,metric)
groups={{"nonTracking_to_tracking","tracking_to_nonTracking"}, ...
    {"closer_to_farther","farther_to_closer"}};
labels=string(events.eventCategory);colors=lines(4);
fig=figure('Color','w','Position',[100 50 760 920]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
colorRows={[3 4],[1 2]};
for p=1:2
    ax=nexttile;hold(ax,'on');
    for j=1:2
        name=groups{p}{j};selected=labels==name;
        if any(selected)
            plot(ax,time,mean(traces(selected,:),1,'omitnan'),'LineWidth',2, ...
                'Color',colors(colorRows{p}(j),:),'DisplayName',name);
        end
    end
    xline(ax,0,'k--','HandleVisibility','off');grid(ax,'on');
    xlabel(ax,'Time from HMM transition (s)');
    if strcmp(metric,'trackedTargetResidual')
        ylabel(ax,'Gaze - tracked-target eccentricity (deg)');
    else
        ylabel(ax,'Gaze distance from screen center (deg)');
    end
    legend(ax,'Location','best','Interpreter','none');
end
if strcmp(metric,'trackedTargetResidual')
    sgtitle('Radial gaze error relative to the HMM-inferred tracked target');
else
    sgtitle('Screen-centered gaze eccentricity around reward-defined HMM transitions');
end
end

function [x1,y1,x2,y2]=localCanonicalize(x1,y1,x2,y2)
first=find(isfinite(x1)&isfinite(y1)&isfinite(x2)&isfinite(y2),1);
if ~isempty(first)&&(x1(first)>x2(first)|| ...
        (x1(first)==x2(first)&&y1(first)>y2(first)))
    [x1,x2]=deal(x2,x1);[y1,y2]=deal(y2,y1);
end
end
function opts=localDefaults(opts,defaults)
f=fieldnames(defaults);for i=1:numel(f),if ~isfield(opts,f{i})|| ...
        (isempty(opts.(f{i}))&&~strcmp(f{i},'trialList')),opts.(f{i})=defaults.(f{i});end,end
end
