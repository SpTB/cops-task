function out = analyzeCoPsHardwareBenchx(trial)
% Summarize actual flip, ADC, input-poll and reward-TTL bench recordings.
cfg=trial.bench.config;
adcRate=500;
if isfield(cfg,'adcRateHz'), adcRate=cfg.adcRateHz; end
go=trial.frameState==trial.frameStateLookup.GO;
ifi=trial.displayRefreshIntervalSec;
vbl=trial.flip_info(:,1);
dt=diff(vbl);
dt=dt(go(1:end-1)&go(2:end)&isfinite(dt));
poll=trial.bench.polls;
gp=poll(poll(:,5)>0,:);
pollGap=diff(gp(:,1));
pollHz=NaN;
if size(gp,1)>1, pollHz=(size(gp,1)-1)/(gp(end,1)-gp(1,1)); end
n=min(trial.Eye.n,numel(trial.Eye.t));
adcTime=trial.Eye.t(1:n);
adcDt=diff(adcTime); adcDt=adcDt(isfinite(adcDt));
a=trial.bench.clockBefore; b=trial.bench.clockAfter;
if b(2)>a(2)
    convert=@(t) a(1)+(t-a(2))*(b(1)-a(1))/(b(2)-a(2));
else
    convert=@(t) t+a(1)-a(2);
end
dinTime=convert(trial.bench.dinTime(:));
high=bitand(uint32(trial.bench.dinData(:)),uint32(1))~=0;
rise=find(diff([false;high])==1);
fall=find(diff([false;high])==-1);
pulseStart=[]; pulseEnd=[];
for k=rise(:)'
    stop=fall(find(fall>k,1));
    if ~isempty(stop)
        pulseStart(end+1,1)=dinTime(k); %#ok<AGROW>
        pulseEnd(end+1,1)=dinTime(stop); %#ok<AGROW>
    end
end
goPulse=pulseStart>=trial.times.stimOn & pulseStart<=trial.bench.blankVbl;
width=pulseEnd(goPulse)-pulseStart(goPulse);
startGo=pulseStart(goPulse);
% A final pulse can be intentionally cut short by trial completion.
fullWidth=width(pulseEnd(goPulse)<trial.bench.blankVbl-0.015);

row=find(trial.adcChannels==cfg.photodiodeChannel,1);
delay=NaN; fraction=NaN; compared=0; mismatch=0;
if ~isempty(row) && any(go)
    sig=trial.Eye.v(row,1:n)';
    pt=convert(adcTime(:));
    marker=trial.bench.marker(:);
    firstWhite=find(go & marker>0.5,1);
    if ~isempty(firstWhite)
        first=vbl(firstWhite);
        hit=find(pt>=first-0.002 & pt<=first+0.095 & ...
            cfg.photodiodePolarity*(sig-cfg.photodiodeThresholdV)>0,1);
        if ~isempty(hit)
            delay=pt(hit)-first;
            for k=find(go & vbl>trial.times.stimOn+0.20)'
                stop=trial.bench.blankVbl;
                if k<numel(vbl), stop=vbl(k+1); end
                samples=pt>=vbl(k)+delay+0.0002 & pt<stop+delay-0.0002;
                if ~any(samples), continue; end
                actual=cfg.photodiodePolarity*(mean(sig(samples))-cfg.photodiodeThresholdV)>0;
                compared=compared+1;
                mismatch=mismatch+(actual~=logical(marker(k)));
            end
            if compared>0, fraction=1-mismatch/compared; end
        end
    end
end

stepChange=go & [true;diff(trial.frameStep)~=0];
stepVbl=vbl(stepChange & vbl>trial.times.stimOn+0.20);
stepDt=diff(stepVbl);
out=struct('version',cfg.version,'scenario',cfg.scenario,'pair',cfg.pair, ...
    'markerMode',cfg.markerMode,'rewardOutput',cfg.rewardOutput, ...
    'goReached',isfinite(trial.times.stimOn),'aborted',trial.bench.aborted, ...
    'displayHz',1/ifi,'medianFrameMs',1000*med(dt),'maxFrameMs',1000*big(dt), ...
    'skippedRefreshes',sum(max(0,round(dt/ifi)-1)), ...
    'medianTargetStepMs',1000*med(stepDt),'maxTargetStepMs',1000*big(stepDt), ...
    'pollHz',pollHz,'maxPollGapMs',1000*big(pollGap), ...
    'medianPollWorkMs',1000*med(gp(:,2)-gp(:,1)), ...
    'startToGoSec',trial.times.stimOn-trial.times.startTrial, ...
    'adcHz',1/med(adcDt),'adcMaxGapMs',1000*big(adcDt), ...
    'adcGaps',sum(adcDt>1.5/adcRate),'adcFrames',n, ...
    'adcUnderflows',sum(poll(:,9))+trial.bench.tailUnderflow, ...
    'adcOverflows',sum(poll(:,10))+trial.bench.tailOverflow, ...
    'adcStreamOverflows',big(poll(:,11)), ...
    'dinUnderflow',trial.bench.dinUnderflow, ...
    'rewardRequests',sum(isfinite(trial.times.reward)), ...
    'rewardPulsesGO',sum(goPulse),'rewardPulsesTotal',numel(pulseStart), ...
    'medianRewardWidthMs',1000*med(fullWidth),'maxRewardWidthMs',1000*big(width), ...
    'medianRewardIntervalMs',1000*med(diff(startGo)), ...
    'photodiodeOnsetDelayMs',1000*delay, ...
    'photodiodeComparedFrames',compared,'photodiodeMismatchFrames',mismatch, ...
    'photodiodeMatchFraction',fraction, ...
    'opticalFrameCheckReliable',adcRate>=10000 && compared>0, ...
    'clockConfidenceMs',1000*max(a(3),b(3)));
end

function x=med(x)
x=x(isfinite(x));
if isempty(x), x=NaN; else, x=median(x); end
end

function x=big(x)
x=x(isfinite(x));
if isempty(x), x=NaN; else, x=max(x); end
end
