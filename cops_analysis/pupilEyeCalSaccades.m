function out = pupilEyeCalSaccades(animal, dateValue, opts)
% pupilEyeCalSaccades  Pupil response time-locked to EyeCal saccades.
%
% out = pupilEyeCalSaccades('ka','Aug11')
%
% Raw and EyeCal-position-corrected pupil traces are evaluated on the same
% detected saccades. The short default epoch is chosen for calibration-trial
% coverage and is intended primarily to diagnose immediate saccade-linked
% measurement effects.
%
% opts defaults:
%   preSec                0.20
%   postSec               0.40
%   baselineWindowSec    [-0.20 -0.10] ([] = no baseline subtraction)
%   minEpochValidFrac     0.80
%   blinkPaddingSec       0.05
%   smoothWindowSec       0.02
%   minEventSeparationSec 0.30
%   invalidVoltageCutoff -4.8
%   outlierMad            6
%   makePlot              true
%   calibrationOpts       options passed to fitPupilPositionBias
%   calibrationModel      optional pre-fitted position-correction model

if nargin<3||isempty(opts),opts=struct();end
opts=localDefaults(opts,struct('preSec',0.20,'postSec',0.40, ...
    'baselineWindowSec',[-0.20 -0.10],'minEpochValidFrac',0.80, ...
    'blinkPaddingSec',0.05,'smoothWindowSec',0.02, ...
    'minEventSeparationSec',0.30,'invalidVoltageCutoff',-4.8, ...
    'outlierMad',6,'makePlot',true,'calibrationOpts',struct(), ...
    'calibrationModel',[]));
localValidate(opts);
cal=opts.calibrationModel;
if isempty(cal)
    fitOpts=opts.calibrationOpts;fitOpts.makePlot=false;
    cal=fitPupilPositionBias(animal,dateValue,fitOpts);
end

eventRows=cell(0,1);rawRight=cell(0,1);rawLeft=cell(0,1);
correctedRight=cell(0,1);correctedLeft=cell(0,1);
commonTime=[];nDetected=0;nRejectedCoverage=0;nRejectedSeparation=0;
for fileNo=1:numel(cal.eyeCalPaths)
    loaded=load(cal.eyeCalPaths(fileNo),'ex');ex=loaded.ex;
    [correctedEx,~]=applyPupilPositionBias(ex,cal);
    fs=inferFs(ex);dt=1/fs;
    if isempty(commonTime)
        commonTime=(-round(opts.preSec*fs):round(opts.postSec*fs))/fs;
    end
    centers=[cal.right.fileIntercepts(cal.right.fileIds==fileNo), ...
        cal.left.fileIntercepts(cal.left.fileIds==fileNo)];
    scales=[cal.right.normalizationScale,cal.left.normalizationScale];
    for trialNo=1:numel(ex.Trials)
        T=ex.Trials(trialNo);TC=correctedEx.Trials(trialNo);
        if ~isfield(T,'Eye')||~isfield(T.Eye,'v')||size(T.Eye.v,1)<6,continue;end
        [x,y,time,~,gazeValid]=reconstructEyePx(ex,T,true,struct());
        n=min([numel(x),numel(y),numel(time),numel(gazeValid), ...
            size(T.Eye.v,2),size(TC.Eye.v,2)]);
        if isfield(T.Eye,'n')&&isscalar(T.Eye.n)&&isfinite(T.Eye.n)
            n=min(n,max(0,round(double(T.Eye.n))));
        end
        if n<3,continue;end
        x=double(x(1:n));y=double(y(1:n));time=double(time(1:n));
        gazeValid=logical(gazeValid(1:n));
        localDt=median(diff(time),'omitnan');
        if ~isfinite(localDt)||localDt<=0,localDt=dt;end
        [starts,stops,~,saccadeParams]=detectTrackingSaccadesCoPs( ...
            x,y,localDt,ex.setup,[]);
        nDetected=nDetected+numel(starts);
        if isempty(starts),continue;end
        onsetTimes=time(starts);
        raw=[double(T.Eye.v(3,1:n))',double(T.Eye.v(6,1:n))'];
        corrected=[double(TC.Eye.v(3,1:n))',double(TC.Eye.v(6,1:n))'];
        valid=repmat(gazeValid(:),1,2)&isfinite(raw)& ...
            raw>opts.invalidVoltageCutoff;
        for eye=1:2
            if isfinite(centers(eye))&&isfinite(scales(eye))&&scales(eye)>0
                valid(:,eye)=valid(:,eye)& ...
                    abs(raw(:,eye)-centers(eye))<=opts.outlierMad*scales(eye);
            end
            padding=max(0,round(opts.blinkPaddingSec/localDt));
            if padding>0
                invalid=conv(double(~valid(:,eye)),ones(2*padding+1,1),'same')>0;
                valid(invalid,eye)=false;
            end
        end
        raw(~valid)=NaN;corrected(~valid)=NaN;
        smoothFrames=max(1,round(opts.smoothWindowSec/localDt));
        if smoothFrames>1
            raw=movmean(raw,smoothFrames,1,'omitnan');
            corrected=movmean(corrected,smoothFrames,1,'omitnan');
            raw(~valid)=NaN;corrected(~valid)=NaN;
        end
        for eventNo=1:numel(starts)
            previous=Inf;next=Inf;
            if eventNo>1,previous=onsetTimes(eventNo)-onsetTimes(eventNo-1);end
            if eventNo<numel(starts),next=onsetTimes(eventNo+1)-onsetTimes(eventNo);end
            if min(previous,next)<opts.minEventSeparationSec
                nRejectedSeparation=nRejectedSeparation+1;continue
            end
            query=onsetTimes(eventNo)+commonTime;
            epochsRaw=nan(numel(commonTime),2);epochsCorrected=epochsRaw;
            for eye=1:2
                epochsRaw(:,eye)=interp1(time,raw(:,eye),query,'linear',NaN);
                epochsCorrected(:,eye)=interp1(time,corrected(:,eye),query,'linear',NaN);
            end
            coverage=mean(isfinite(epochsRaw),1);
            if all(coverage<opts.minEpochValidFrac)
                nRejectedCoverage=nRejectedCoverage+1;continue
            end
            for eye=1:2
                epochsRaw(:,eye)=epochsRaw(:,eye)/scales(eye);
                epochsCorrected(:,eye)=epochsCorrected(:,eye)/scales(eye);
                if ~isempty(opts.baselineWindowSec)
                    baseline=commonTime>=opts.baselineWindowSec(1)& ...
                        commonTime<=opts.baselineWindowSec(2);
                    epochsRaw(:,eye)=epochsRaw(:,eye)- ...
                        mean(epochsRaw(baseline,eye),'omitnan');
                    epochsCorrected(:,eye)=epochsCorrected(:,eye)- ...
                        mean(epochsCorrected(baseline,eye),'omitnan');
                end
            end
            amplitude=px2deg(hypot(x(stops(eventNo))-x(starts(eventNo)), ...
                y(stops(eventNo))-y(starts(eventNo))),ex.setup);
            direction=atan2d(y(stops(eventNo))-y(starts(eventNo)), ...
                x(stops(eventNo))-x(starts(eventNo)));
            rect=double(ex.setup.screenRect(:)');center=[mean(rect([1 3])),mean(rect([2 4]))];
            startEcc=px2deg(hypot(x(starts(eventNo))-center(1), ...
                y(starts(eventNo))-center(2)),ex.setup);
            endEcc=px2deg(hypot(x(stops(eventNo))-center(1), ...
                y(stops(eventNo))-center(2)),ex.setup);
            eventRows{end+1,1}=table(fileNo,trialNo,eventNo,onsetTimes(eventNo), ... %#ok<AGROW>
                amplitude,direction,startEcc,endEcc,coverage(1),coverage(2), ...
                saccadeParams.speedThreshDegPerSec, ...
                'VariableNames',{'file','trial','event','onsetTimeSec', ...
                'amplitudeDeg','directionDeg','startEccentricityDeg', ...
                'endEccentricityDeg','rightValidFrac','leftValidFrac', ...
                'speedThresholdDegPerSec'});
            rawRight{end+1,1}=epochsRaw(:,1)';rawLeft{end+1,1}=epochsRaw(:,2)'; %#ok<AGROW>
            correctedRight{end+1,1}=epochsCorrected(:,1)'; %#ok<AGROW>
            correctedLeft{end+1,1}=epochsCorrected(:,2)'; %#ok<AGROW>
        end
    end
end
if isempty(eventRows)
    events=table();RR=nan(0,numel(commonTime));RL=RR;CR=RR;CL=RR;
else
    events=vertcat(eventRows{:});RR=vertcat(rawRight{:});RL=vertcat(rawLeft{:});
    CR=vertcat(correctedRight{:});CL=vertcat(correctedLeft{:});
end
RB=localNanPair(RR,RL);CB=localNanPair(CR,CL);
template=struct('timeSec',commonTime, ...
    'rightRobustSd',mean(CR,1,'omitnan'), ...
    'leftRobustSd',mean(CL,1,'omitnan'), ...
    'combinedRobustSd',mean(CB,1,'omitnan'), ...
    'rightRawUnits',mean(CR,1,'omitnan')*cal.right.normalizationScale, ...
    'leftRawUnits',mean(CL,1,'omitnan')*cal.left.normalizationScale, ...
    'alignment','detected saccade onset','baselineWindowSec',opts.baselineWindowSec);
fig=[];if opts.makePlot,fig=localPlot(commonTime,RR,CR,RL,CL,RB,CB,opts);end
out=struct('events',events,'timeSec',commonTime,'raw', ...
    struct('right',RR,'left',RL,'combined',RB),'corrected', ...
    struct('right',CR,'left',CL,'combined',CB),'template',template, ...
    'calibrationModel',cal, ...
    'figure',fig,'opts',opts,'meta',struct('nDetected',nDetected, ...
    'nRetained',height(events),'nRejectedCoverage',nRejectedCoverage, ...
    'nRejectedSeparation',nRejectedSeparation, ...
    'alignment','detected saccade onset','units','calibration robust SD'));
end

function combined=localNanPair(a,b)
combined=nan(size(a));count=isfinite(a)+isfinite(b);a(~isfinite(a))=0;b(~isfinite(b))=0;
combined=(a+b)./count;combined(count==0)=NaN;
end
function fig=localPlot(time,RR,CR,RL,CL,RB,CB,opts)
fig=figure('Color','w','Position',[100 50 760 920]);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');
raw={RR,RL,RB};corrected={CR,CL,CB};names={'Right eye','Left eye','Binocular mean'};
for k=1:3
    ax=nexttile;hold(ax,'on');
    localMeanSem(ax,time,raw{k},[.45 .45 .45],'Raw');
    localMeanSem(ax,time,corrected{k},[.10 .55 .80],'Position-corrected');
    xline(ax,0,'k--','HandleVisibility','off');yline(ax,0,'k:','HandleVisibility','off');
    if ~isempty(opts.baselineWindowSec)
        yl=ylim(ax);patch(ax,opts.baselineWindowSec([1 2 2 1]), ...
            yl([1 1 2 2]),[.8 .8 .8],'FaceAlpha',.18,'EdgeColor','none', ...
            'HandleVisibility','off');
    end
    grid(ax,'on');xlabel(ax,'Time from saccade onset (s)');
    ylabel(ax,'Baseline-corrected pupil (robust SD)');title(ax,names{k});
    if k==1,legend(ax,'Location','best');end
end
sgtitle('EyeCal saccade-triggered pupil response');
end
function localMeanSem(ax,time,traces,color,label)
average=mean(traces,1,'omitnan');n=sum(isfinite(traces),1);
sem=std(traces,0,1,'omitnan')./sqrt(n);sem(n<2)=NaN;
patch(ax,[time fliplr(time)],[average-sem fliplr(average+sem)],color, ...
    'FaceAlpha',.16,'EdgeColor','none','HandleVisibility','off');
plot(ax,time,average,'Color',color,'LineWidth',2,'DisplayName', ...
    sprintf('%s (n=%d)',label,size(traces,1)));
end
function localValidate(opts)
if opts.preSec<=0||opts.postSec<=0,error('pupilEyeCalSaccades:BadEpoch', ...
        'preSec and postSec must be positive.');end
if ~isempty(opts.baselineWindowSec)&&(numel(opts.baselineWindowSec)~=2|| ...
        opts.baselineWindowSec(1)<-opts.preSec|| ...
        opts.baselineWindowSec(2)>opts.postSec|| ...
        opts.baselineWindowSec(2)<=opts.baselineWindowSec(1))
    error('pupilEyeCalSaccades:BadBaseline','Invalid baselineWindowSec.');
end
end
function opts=localDefaults(opts,defaults)
f=fieldnames(defaults);for k=1:numel(f),allowEmpty=strcmp(f{k},'baselineWindowSec'); ...
        if ~isfield(opts,f{k})||(isempty(opts.(f{k}))&&~allowEmpty),opts.(f{k})=defaults.(f{k});end,end
end
