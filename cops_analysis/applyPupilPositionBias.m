function [exOut, report] = applyPupilPositionBias(ex, model, opts)
% applyPupilPositionBias  Remove calibration- or experiment-estimated pupil bias.
%
% [exCorrected,report] = applyPupilPositionBias(ex,model)
%
% The correction is applied separately to Eye.v rows 3 and 6 using actual
% reconstructed gaze position. Original missing pupil values remain intact.
if nargin<3||isempty(opts),opts=struct();end
defaultCutoff=-4.8;
if isfield(model,'opts')&&isfield(model.opts,'invalidVoltageCutoff')
    defaultCutoff=model.opts.invalidVoltageCutoff;
end
opts=localDefaults(opts,struct('useEyeTime',true,'excludeOutsideScreen',true, ...
    'screenPaddingPx',0,'invalidVoltageCutoff',defaultCutoff));
exOut=ex;rect=double(ex.setup.screenRect(:)');
center=[(rect(1)+rect(3))/2,(rect(2)+rect(4))/2];
nCorrected=zeros(numel(ex.Trials),2);
for trialNo=1:numel(ex.Trials)
    T=ex.Trials(trialNo);
    if ~isfield(T,'Eye')||~isfield(T.Eye,'v')||size(T.Eye.v,1)<6,continue;end
    [x,y,~,~,gazeValid]=reconstructEyePx(ex,T,opts.useEyeTime,struct());
    n=min([size(T.Eye.v,2),numel(x),numel(y),numel(gazeValid)]);
    if isfield(T.Eye,'n')&&isscalar(T.Eye.n)&&isfinite(T.Eye.n)
        n=min(n,max(0,round(double(T.Eye.n))));
    end
    if n<1,continue;end
    x=double(x(1:n));y=double(y(1:n));valid=logical(gazeValid(1:n));
    if opts.excludeOutsideScreen
        valid=valid&x>=rect(1)-opts.screenPaddingPx&x<=rect(3)+opts.screenPaddingPx& ...
            y>=rect(2)-opts.screenPaddingPx&y<=rect(4)+opts.screenPaddingPx;
    end
    xDeg=px2deg(x-center(1),ex.setup);yDeg=px2deg(y-center(2),ex.setup);
    if isfield(model,'basis')&&strcmpi(string(model.basis),'eccentricity-quadratic')
        eccentricity=hypot(xDeg(:),yDeg(:));
        spatial=[eccentricity,eccentricity.^2];
    else
        spatial=[xDeg(:),yDeg(:),xDeg(:).^2,yDeg(:).^2,xDeg(:).*yDeg(:)];
    end
    pupilRows=[3 6];fits={model.right,model.left};
    for eye=1:2
        raw=double(exOut.Trials(trialNo).Eye.v(pupilRows(eye),1:n))';
        use=valid(:)&isfinite(raw)&raw>opts.invalidVoltageCutoff;
        correction=spatial*double(fits{eye}.spatialBeta(:));
        raw(use)=raw(use)-correction(use);
        exOut.Trials(trialNo).Eye.v(pupilRows(eye),1:n)=raw';
        nCorrected(trialNo,eye)=sum(use);
    end
end
animal="";date="";paths=strings(0,1);
if isfield(model,'animal'),animal=string(model.animal);end
if isfield(model,'date'),date=string(model.date);end
if isfield(model,'eyeCalPaths'),paths=string(model.eyeCalPaths);end
source="calibration";if isfield(model,'source'),source=string(model.source);end
exOut.pupilPositionCorrection=struct('schema',model.schema, ...
    'animal',animal,'date',date,'eyeCalPaths',paths,'source',source, ...
    'rightSpatialBeta',model.right.spatialBeta, ...
    'leftSpatialBeta',model.left.spatialBeta, ...
    'definition',model.correctionDefinition);
report=table((1:numel(ex.Trials))',nCorrected(:,1),nCorrected(:,2), ...
    'VariableNames',{'trial','nRightCorrected','nLeftCorrected'});
end
function opts=localDefaults(opts,defaults)
f=fieldnames(defaults);for i=1:numel(f),if ~isfield(opts,f{i})||isempty(opts.(f{i})),opts.(f{i})=defaults.(f{i});end,end
end
