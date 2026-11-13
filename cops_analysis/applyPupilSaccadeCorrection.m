function [exOut, report] = applyPupilSaccadeCorrection(ex, source, opts)
% applyPupilSaccadeCorrection  Subtract a calibration or experimental template.
%
% [exCorrected,report] = applyPupilSaccadeCorrection(ex,eyeCalSaccadeOut)
% The eye-specific additive templates are aligned to every detected saccade
% onset and summed when epochs overlap. Correction occurs in raw acquisition
% units and should precede pupil centering/scaling and event baselining.
if nargin<3||isempty(opts),opts=struct();end
opts=localDefaults(opts,struct('useEyeTime',true));
if isfield(source,'template'),template=source.template;else,template=source;end
required={'timeSec','rightRawUnits','leftRawUnits'};
if ~isstruct(template)||~all(isfield(template,required))
    error('applyPupilSaccadeCorrection:BadTemplate', ...
        'source must contain an EyeCal saccade template.');
end
templateTime=double(template.timeSec(:));
templateValues=[double(template.rightRawUnits(:)), ...
    double(template.leftRawUnits(:))];
exOut=ex;nSaccades=zeros(numel(ex.Trials),1);nCorrected=zeros(numel(ex.Trials),2);
for trialNo=1:numel(ex.Trials)
    T=ex.Trials(trialNo);
    if ~isfield(T,'Eye')||~isfield(T.Eye,'v')||size(T.Eye.v,1)<6,continue;end
    [x,y,time]=reconstructEyePx(ex,T,opts.useEyeTime,struct());
    n=min([numel(x),numel(y),numel(time),size(T.Eye.v,2)]);
    if isfield(T.Eye,'n')&&isscalar(T.Eye.n)&&isfinite(T.Eye.n)
        n=min(n,max(0,round(double(T.Eye.n))));
    end
    if n<3,continue;end
    x=double(x(1:n));y=double(y(1:n));time=double(time(1:n));
    dt=median(diff(time),'omitnan');
    [starts,~]=detectTrackingSaccadesCoPs(x,y,dt,ex.setup,[]);
    nSaccades(trialNo)=numel(starts);
    if isempty(starts),continue;end
    correction=zeros(n,2);
    for eventNo=1:numel(starts)
        relativeTime=time-time(starts(eventNo));
        for eye=1:2
            value=interp1(templateTime,templateValues(:,eye), ...
                relativeTime,'linear',NaN);
            inside=relativeTime>=templateTime(1)&relativeTime<=templateTime(end)& ...
                isfinite(value);
            correction(inside,eye)=correction(inside,eye)+value(inside);
        end
    end
    rows=[3 6];
    for eye=1:2
        raw=double(exOut.Trials(trialNo).Eye.v(rows(eye),1:n))';
        use=isfinite(raw)&isfinite(correction(:,eye));
        raw(use)=raw(use)-correction(use,eye);
        exOut.Trials(trialNo).Eye.v(rows(eye),1:n)=raw';
        nCorrected(trialNo,eye)=sum(use&correction(:,eye)~=0);
    end
end
sourceName="calibration";if isfield(source,'source'),sourceName=string(source.source);end
exOut.pupilSaccadeCorrection=struct('schema','pupil-saccade-template-v2', ...
    'source',sourceName,'template',template,'definition', ...
    'raw pupil minus summed saccade-onset templates');
report=table((1:numel(ex.Trials))',nSaccades,nCorrected(:,1),nCorrected(:,2), ...
    'VariableNames',{'trial','nSaccades','nRightCorrected','nLeftCorrected'});
end
function opts=localDefaults(opts,defaults)
f=fieldnames(defaults);for k=1:numel(f),if ~isfield(opts,f{k})||isempty(opts.(f{k})),opts.(f{k})=defaults.(f{k});end,end
end
