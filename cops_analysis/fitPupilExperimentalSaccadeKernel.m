function out=fitPupilExperimentalSaccadeKernel(ex,opts)
% fitPupilExperimentalSaccadeKernel  Estimate a pupil saccade kernel from ex.
%
% out=fitPupilExperimentalSaccadeKernel(ex)
%
% The default kernel spans -0.5 to +1 s around detected saccade onset.
% Each retained epoch is baseline-subtracted before averaging. Supply a
% positionModel to estimate the kernel after eccentricity correction.
if nargin<2||isempty(opts),opts=struct();end
opts=localDefaults(opts,struct('preSec',0.5,'postSec',1.0, ...
    'baselineWindowSec',[-0.5 -0.2],'minEpochValidFrac',0.70, ...
    'blinkPaddingSec',0.05,'smoothWindowSec',0.02, ...
    'minEventSeparationSec',0,'invalidVoltageCutoff',-4.8, ...
    'useEyeTime',true,'positionModel',[],'makePlot',false));
if ~isempty(opts.positionModel),[workingEx,~]=applyPupilPositionBias(ex,opts.positionModel);
else,workingEx=ex;end
fs=inferFs(ex);timeSec=(-round(opts.preSec*fs):round(opts.postSec*fs))/fs;
sumEpoch=zeros(numel(timeSec),2);countEpoch=zeros(numel(timeSec),2);
nDetected=0;nRetained=0;
for trialNo=1:numel(ex.Trials)
    T=ex.Trials(trialNo);TC=workingEx.Trials(trialNo);
    if ~isfield(T,'Eye')||~isfield(T.Eye,'v')||size(T.Eye.v,1)<6,continue;end
    [x,y,time,~,gazeValid]=reconstructEyePx(ex,T,opts.useEyeTime,struct());
    n=min([numel(x),numel(y),numel(time),numel(gazeValid),size(TC.Eye.v,2)]);
    if isfield(T.Eye,'n')&&isscalar(T.Eye.n)&&isfinite(T.Eye.n)
        n=min(n,max(0,round(double(T.Eye.n))));
    end
    if n<3,continue;end
    x=double(x(1:n));y=double(y(1:n));time=double(time(1:n));
    validGaze=logical(gazeValid(1:n));dt=median(diff(time),'omitnan');
    if ~isfinite(dt)||dt<=0,dt=1/fs;end
    [starts,~]=detectTrackingSaccadesCoPs(x,y,dt,ex.setup,[]);
    nDetected=nDetected+numel(starts);if isempty(starts),continue;end
    onset=time(starts);pupil=[double(TC.Eye.v(3,1:n))',double(TC.Eye.v(6,1:n))'];
    valid=repmat(validGaze(:),1,2)&isfinite(pupil)&pupil>opts.invalidVoltageCutoff;
    padding=max(0,round(opts.blinkPaddingSec/dt));
    if padding>0
        for eye=1:2
            invalid=conv(double(~valid(:,eye)),ones(2*padding+1,1),'same')>0;
            valid(invalid,eye)=false;
        end
    end
    pupil(~valid)=NaN;smoothFrames=max(1,round(opts.smoothWindowSec/dt));
    if smoothFrames>1,pupil=movmean(pupil,smoothFrames,1,'omitnan');pupil(~valid)=NaN;end
    for eventNo=1:numel(onset)
        if opts.minEventSeparationSec>0
            gap=abs(onset-onset(eventNo));gap(eventNo)=Inf;
            if min(gap)<opts.minEventSeparationSec,continue;end
        end
        query=onset(eventNo)+timeSec;epoch=nan(numel(timeSec),2);
        for eye=1:2,epoch(:,eye)=interp1(time,pupil(:,eye),query,'linear',NaN);end
        if ~isempty(opts.baselineWindowSec)
            base=timeSec>=opts.baselineWindowSec(1)&timeSec<=opts.baselineWindowSec(2);
            epoch=epoch-mean(epoch(base,:),1,'omitnan');
        end
        retained=false;
        for eye=1:2
            if mean(isfinite(epoch(:,eye)))<opts.minEpochValidFrac,continue;end
            good=isfinite(epoch(:,eye));sumEpoch(good,eye)=sumEpoch(good,eye)+epoch(good,eye);
            countEpoch(good,eye)=countEpoch(good,eye)+1;retained=true;
        end
        nRetained=nRetained+retained;
    end
end
values=sumEpoch./countEpoch;values(countEpoch==0)=NaN;
template=struct('timeSec',timeSec,'rightRawUnits',values(:,1)', ...
    'leftRawUnits',values(:,2)','combinedRawUnits',mean(values,2,'omitnan')', ...
    'alignment','experimental saccade onset', ...
    'baselineWindowSec',opts.baselineWindowSec);
out=struct('schema','pupil-experimental-saccade-kernel-v1', ...
    'source','experimental','template',template,'opts',opts, ...
    'meta',struct('nDetected',nDetected,'nRetained',nRetained), ...
    'figure',[]);
if opts.makePlot
    out.figure=figure('Color','w');plot(timeSec,values,'LineWidth',2);grid on
    xline(0,'k--');yline(0,'k:');xlabel('Time from saccade onset (s)');
    ylabel('Estimated pupil artifact (raw units)');legend('Right','Left');
    title(sprintf('Experimental saccade kernel (%d retained events)',nRetained));
end
end
function opts=localDefaults(opts,defaults)
f=fieldnames(defaults);for k=1:numel(f),if ~isfield(opts,f{k})||isempty(opts.(f{k})),opts.(f{k})=defaults.(f{k});end,end
end
