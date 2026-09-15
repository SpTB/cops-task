function out = rewardHmmTransitions(ex, opts)
% rewardHmmTransitions  Reward-release density around HMM transitions.
%
% out = rewardHmmTransitions(ex, opts)
% Density is reported in releases/s after a centered smoothing window.

if nargin < 2 || isempty(opts), opts=struct(); end
defaults=struct('preSec',1.5,'postSec',3.0,'trialList',[], ...
    'useEyeTime',true,'makePlot',true,'densityWindowSec',0.20, ...
    'minStateDwellSec',0.10,'minEventSeparationSec',0.50, ...
    'hmmMethod','smoothed');
opts=localDefaults(opts,defaults);
fs=inferFs(ex); dt=1/fs;
timeSec=(-round(opts.preSec*fs):round(opts.postSec*fs))/fs;

transitionOpts=struct('preSec',opts.preSec,'postSec',opts.postSec, ...
    'trialList',opts.trialList,'useEyeTime',opts.useEyeTime, ...
    'makePlot',false,'baselineWindowSec',[], ...
    'minBaselineValidFrac',0,'minEpochValidFrac',0, ...
    'minStateDwellSec',opts.minStateDwellSec, ...
    'minEventSeparationSec',opts.minEventSeparationSec, ...
    'hmmMethod',opts.hmmMethod);
transitionOpts.posCorrected=false;
transitionOut=pupilHmmTransitions(ex,transitionOpts);
events=transitionOut.events;

rewardOpts=struct('preSec',opts.preSec,'postSec',opts.postSec, ...
    'trialList',opts.trialList,'useEyeTime',opts.useEyeTime, ...
    'makePlot',false,'baselineWindowSec',[], ...
    'minBaselineValidFrac',0,'minEpochValidFrac',0, ...
    'minRewardSeparationSec',0);
rewardOut=pupRew(ex,rewardOpts);
rewards=rewardOut.events;

binary=zeros(height(events),numel(timeSec));
for i=1:height(events)
    selected=double(rewards.trial)==double(events.trial(i));
    relative=double(rewards.rewardTimeRelSec(selected))-double(events.eventTimeSec(i));
    relative=relative(relative>=-opts.preSec & relative<=opts.postSec);
    for r=relative(:)'
        [~,index]=min(abs(timeSec-r)); binary(i,index)=binary(i,index)+1;
    end
end
windowSamples=max(1,round(opts.densityWindowSec*fs));
kernel=ones(1,windowSamples)/(windowSamples*dt);
density=conv2(binary,kernel,'same');

figureHandle=[];
if opts.makePlot
    figureHandle=localPlot(timeSec,events,density);
end
out=struct('events',events,'rewardEvents',rewards,'timeSec',timeSec, ...
    'rewardCounts',binary,'rewardDensityHz',density, ...
    'meanRewardDensityHz',mean(density,1,'omitnan'), ...
    'figure',figureHandle,'opts',opts,'meta',struct( ...
    'samplingRateHz',fs,'densityWindowSec',opts.densityWindowSec, ...
    'nTransitions',height(events),'nRewards',height(rewards)));
end

function fig=localPlot(time,events,density)
groups={{"nonTracking_to_tracking","tracking_to_nonTracking"}, ...
    {"closer_to_farther","farther_to_closer"}};
labels=string(events.eventCategory); colors=lines(4);
fig=figure('Color','w','Position',[100 50 760 920]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
colorRows={[3 4],[1 2]};
for p=1:2
    ax=nexttile; hold(ax,'on');
    for j=1:2
        name=groups{p}{j}; selected=labels==name;
        if any(selected)
            plot(ax,time,mean(density(selected,:),1,'omitnan'), ...
                'LineWidth',2,'Color',colors(colorRows{p}(j),:), ...
                'DisplayName',name);
        end
    end
    xline(ax,0,'k--','HandleVisibility','off'); grid(ax,'on');
    xlabel(ax,'Time from HMM transition (s)'); ylabel(ax,'Reward rate (releases/s)');
    legend(ax,'Location','best','Interpreter','none');
end
sgtitle('Reward-release density around HMM transitions');
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
