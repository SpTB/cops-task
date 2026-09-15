function out=fitPupilTransitionDeconvolution(trials,events,plotTime,opts)
% fitPupilTransitionDeconvolution  Joint FIR model of pupil event responses.
%
% Regresses continuous binned pupil on separate FIR kernels for HMM
% transitions, saccades, blinks, and rewards. Session-specific polynomial
% drift terms absorb slow time-on-task changes. Event kernels are ridge
% regularized; drift terms are not.
bin=double(opts.deconvBinSec);categories=["nonTracking_to_tracking", ...
    "tracking_to_nonTracking","closer_to_farther","farther_to_closer"];
correctionGroups=unique(cellfun(@(x)double(x.correctionGroup),trials),'stable');
saccadeNames="saccade_group"+string(correctionGroups(:)');
specNames=[categories,saccadeNames,"blink","reward"];
windows=repmat({double([-opts.preSec opts.postSec])},1,4);
windows=[windows,repmat({double(opts.deconvSaccadeWindowSec)},1,numel(correctionGroups)), ...
    {double(opts.deconvBlinkWindowSec)},{double(opts.deconvRewardWindowSec)}];
sessionValues=unique(cellfun(@(x)double(x.session),trials),'stable');
nDrift=numel(sessionValues)*(opts.deconvDriftOrder+1);
lagTimes=cell(size(specNames));nLag=zeros(size(specNames));
for s=1:numel(specNames)
    lagTimes{s}=(ceil(windows{s}(1)/bin):floor(windows{s}(2)/bin))*bin;
    nLag(s)=numel(lagTimes{s});
end
starts=nDrift+cumsum([1 nLag(1:end-1)]);nColumns=nDrift+sum(nLag);
allY=cell(numel(trials),1);allSession=cell(numel(trials),1);allWithin=cell(numel(trials),1);
trialBinCount=zeros(numel(trials),1);
for q=1:numel(trials)
    t=double(trials{q}.timeSec(:));
    trialBinCount(q)=max(1,numel((min(t):bin:max(t)+bin)')-1);
end
sessionTotal=zeros(size(sessionValues));sessionSeen=zeros(size(sessionValues));
for k=1:numel(sessionValues)
    belongs=cellfun(@(x)double(x.session)==sessionValues(k),trials);
    sessionTotal(k)=sum(trialBinCount(belongs));
end
rowOffset=zeros(numel(trials),1);nRows=0;
for q=1:numel(trials)
    tr=trials{q};t=double(tr.timeSec(:));y=double(tr.pupilZ(:));
    edges=(min(t):bin:max(t)+bin)';which=discretize(t,edges);
    valid=isfinite(which)&isfinite(y);
    yBin=accumarray(which(valid),y(valid),[numel(edges)-1 1],@mean,NaN);
    allY{q}=yBin;allSession{q}=repmat(double(tr.session),numel(yBin),1);
    sessionIndex=find(sessionValues==double(tr.session),1);
    denominator=max(sessionTotal(sessionIndex)-1,1);
    allWithin{q}=2*(sessionSeen(sessionIndex)+(0:numel(yBin)-1)')/denominator-1;
    sessionSeen(sessionIndex)=sessionSeen(sessionIndex)+numel(yBin);
    rowOffset(q)=nRows;nRows=nRows+numel(yBin);
end
y=vertcat(allY{:});session=vertcat(allSession{:});within=vertcat(allWithin{:});
I=cell(0,1);J=cell(0,1);V=cell(0,1);
% One intercept and polynomial drift per original session/block.
for k=1:numel(sessionValues)
    selected=find(session==sessionValues(k));
    for degree=0:opts.deconvDriftOrder
        I{end+1}=selected;J{end+1}=repmat((k-1)*(opts.deconvDriftOrder+1)+degree+1,numel(selected),1); %#ok<AGROW>
        V{end+1}=within(selected).^degree; %#ok<AGROW>
    end
end
for q=1:numel(trials)
    tr=trials{q};t0=min(tr.timeSec);nLocal=numel(allY{q});
    eventSets=cell(1,numel(specNames));
    selected=events.trial==tr.trial;
    for c=1:numel(categories)
        eventSets{c}=double(events.eventTimeSec(selected&events.eventCategory==categories(c)));
    end
    for g=1:numel(correctionGroups)
        if double(tr.correctionGroup)==correctionGroups(g)
            eventSets{4+g}=double(tr.saccadeTimes(:));
        else
            eventSets{4+g}=zeros(0,1);
        end
    end
    eventSets{5+numel(correctionGroups)}=double(tr.blinkTimes(:));
    eventSets{6+numel(correctionGroups)}=double(tr.rewardTimes(:));
    for s=1:numel(specNames)
        for eventTime=eventSets{s}(:)'
            onset=round((eventTime-t0)/bin)+1;
            rows=onset+round(lagTimes{s}/bin);
            keep=rows>=1&rows<=nLocal;rows=rows(keep)+rowOffset(q);
            cols=starts(s)+find(keep)-1;
            I{end+1}=rows(:);J{end+1}=cols(:);V{end+1}=ones(numel(rows),1); %#ok<AGROW>
        end
    end
end
X=sparse(vertcat(I{:}),vertcat(J{:}),vertcat(V{:}),nRows,nColumns);
use=isfinite(y);Xfit=X(use,:);yfit=y(use);
penalty=[zeros(nDrift,1);ones(nColumns-nDrift,1)];
beta=(Xfit'*Xfit+opts.deconvRidge*spdiags(penalty,0,nColumns,nColumns))\(Xfit'*yfit);
prediction=Xfit*beta;residual=yfit-prediction;
kernels=struct();
for s=1:numel(specNames)
    value=beta(starts(s):starts(s)+nLag(s)-1)';
    if s<=4&&~isempty(opts.baselineWindowSec)
        base=lagTimes{s}>=opts.baselineWindowSec(1)&lagTimes{s}<=opts.baselineWindowSec(2);
        if any(base),value=value-mean(value(base),'omitnan');end
    end
    kernels.(char(specNames(s)))=struct('timeSec',lagTimes{s},'value',value);
end
out=struct('schema','pupil-transition-fir-deconvolution-v1', ...
    'binSec',bin,'kernels',kernels,'categories',categories, ...
    'driftOrder',opts.deconvDriftOrder,'ridge',opts.deconvRidge, ...
    'nObservations',numel(yfit),'rmse',sqrt(mean(residual.^2)), ...
    'rSquared',1-sum(residual.^2)/sum((yfit-mean(yfit)).^2), ...
    'plotTimeSec',double(plotTime(:)'), ...
    'saccadeCorrectionGroups',correctionGroups);
end
