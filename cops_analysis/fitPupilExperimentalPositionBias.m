function model=fitPupilExperimentalPositionBias(ex,opts)
% fitPupilExperimentalPositionBias  Estimate radial pupil bias from an experiment.
%
% model=fitPupilExperimentalPositionBias(ex)
%
% Fits each eye separately after removing a robust pupil intercept within
% every trial. The remaining additive measurement bias is modeled as
% beta1*eccentricity + beta2*eccentricity^2 and is zero by definition at
% screen center. This is intentionally a radial/eccentricity correction,
% rather than the x/y surface fitted from EyeCal data.
if nargin<2||isempty(opts),opts=struct();end
opts=localDefaults(opts,struct('useEyeTime',true,'sampleStride',10, ...
    'invalidVoltageCutoff',-4.8,'outlierMad',5,'maxIterations',6, ...
    'excludeOutsideScreen',true,'screenPaddingPx',0,'makePlot',false));
rect=double(ex.setup.screenRect(:)');center=[mean(rect([1 3])),mean(rect([2 4]))];
eccAll=cell(numel(ex.Trials),1);pupilAll=cell(numel(ex.Trials),2);
for trialNo=1:numel(ex.Trials)
    T=ex.Trials(trialNo);
    if ~isfield(T,'Eye')||~isfield(T.Eye,'v')||size(T.Eye.v,1)<6,continue;end
    [x,y,~,~,gazeValid]=reconstructEyePx(ex,T,opts.useEyeTime,struct());
    n=min([numel(x),numel(y),numel(gazeValid),size(T.Eye.v,2)]);
    if isfield(T.Eye,'n')&&isscalar(T.Eye.n)&&isfinite(T.Eye.n)
        n=min(n,max(0,round(double(T.Eye.n))));
    end
    take=(1:max(1,round(opts.sampleStride)):n)';if isempty(take),continue;end
    x=double(x(take));y=double(y(take));valid=logical(gazeValid(take));
    if opts.excludeOutsideScreen
        valid=valid&x>=rect(1)-opts.screenPaddingPx&x<=rect(3)+opts.screenPaddingPx& ...
            y>=rect(2)-opts.screenPaddingPx&y<=rect(4)+opts.screenPaddingPx;
    end
    ecc=px2deg(hypot(x-center(1),y-center(2)),ex.setup);
    eccAll{trialNo}=ecc(:);
    for eye=1:2
        row=[3 6];p=double(T.Eye.v(row(eye),take))';
        use=valid(:)&isfinite(p)&p>opts.invalidVoltageCutoff;
        p(~use)=NaN;
        p=p-median(p,'omitnan'); % remove trial-wide physiological level
        pupilAll{trialNo,eye}=p;
    end
end
ecc=vertcat(eccAll{:});trialId=[];
for k=1:numel(eccAll),trialId=[trialId;repmat(k,numel(eccAll{k}),1)];end %#ok<AGROW>
right=localFit(ecc,vertcat(pupilAll{:,1}),trialId,opts);
left=localFit(ecc,vertcat(pupilAll{:,2}),trialId,opts);
model=struct('schema','pupil-experimental-eccentricity-bias-v1', ...
    'source','experimental','basis','eccentricity-quadratic', ...
    'right',right,'left',left,'opts',opts, ...
    'correctionDefinition', ...
    'raw pupil - within-trial experimental eccentricity bias');
model.figure=[];
if opts.makePlot
    model.figure=figure('Color','w');tiledlayout(1,2);
    localPanel(nexttile,ecc,vertcat(pupilAll{:,1}),right,'Right eye');
    localPanel(nexttile,ecc,vertcat(pupilAll{:,2}),left,'Left eye');
end
end
function fit=localFit(ecc,y,trialId,opts)
use=isfinite(ecc)&isfinite(y);x=ecc(use);z=y(use);ids=trialId(use);
X=[x,x.^2];keep=true(size(z));beta=zeros(2,1);
for iteration=1:opts.maxIterations
    beta=X(keep,:)\z(keep);res=z-X*beta;
    scale=1.4826*median(abs(res(keep)-median(res(keep),'omitnan')),'omitnan');
    if ~isfinite(scale)||scale<=0,break;end
    next=abs(res)<=opts.outlierMad*scale;
    if isequal(next,keep),break;end;keep=next;
end
beta=X(keep,:)\z(keep);res=z-X*beta;
scale=1.4826*median(abs(res(keep)-median(res(keep),'omitnan')),'omitnan');
fit=struct('spatialTerms',["eccentricityDeg","eccentricityDeg2"], ...
    'spatialBeta',beta,'nSamples',numel(z),'nIncluded',sum(keep), ...
    'nTrials',numel(unique(ids(keep))),'normalizationScale',scale, ...
    'rSquared',1-sum(res(keep).^2)/sum((z(keep)-mean(z(keep))).^2));
end
function localPanel(ax,ecc,y,fit,label)
good=isfinite(ecc)&isfinite(y);scatter(ax,ecc(good),y(good),4,'.', ...
    'MarkerEdgeAlpha',.08);hold(ax,'on');xx=linspace(0,max(ecc(good)),200)';
plot(ax,xx,[xx xx.^2]*fit.spatialBeta,'r','LineWidth',2);grid(ax,'on');
xlabel(ax,'Gaze eccentricity (deg)');ylabel(ax,'Within-trial pupil (raw units)');
title(ax,sprintf('%s, R^2=%.3f',label,fit.rSquared));
end
function opts=localDefaults(opts,defaults)
f=fieldnames(defaults);for k=1:numel(f),if ~isfield(opts,f{k})||isempty(opts.(f{k})),opts.(f{k})=defaults.(f{k});end,end
end
