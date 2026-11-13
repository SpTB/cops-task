function model = fitPupilPositionBias(animal, dateValue, opts)
% fitPupilPositionBias  Estimate gaze-position pupil bias from EyeCal files.
%
% model = fitPupilPositionBias('ka','Jul19')
% model = fitPupilPositionBias('kaki','2026.07.19',opts)
%
% The model uses one robust pupil median per calibration fixation. Separate
% quadratic x/y surfaces are fit for the two eyes, with a separate intercept
% for every EyeCal file and a shared spatial surface across files.
%
% opts:
%   dataRoot             default 'Y:\data\CoPs'
%   eyeCalPaths          explicit file(s), string/cell; default auto-discover
%   stableTailSec        final stable interval, default 0.20 s
%   endPaddingSec        omit final samples, default 0.02 s
%   minimumSamples       minimum valid samples per eye/trial, default 40
%   invalidVoltageCutoff samples at/below this are missing, default -4.8
%   outlierMad           iterative trial-level residual cutoff, default 4
%   makePlot             default true
%   plotUnits            'z' (default, calibration robust-SD units) or 'raw'
%   plotColorBy          'horizontal' (default) or 'vertical' gaze position

if nargin<3 || isempty(opts),opts=struct();end
opts=localDefaults(opts,struct('dataRoot','Y:\data\CoPs', ...
    'eyeCalPaths',[],'stableTailSec',0.20,'endPaddingSec',0.02, ...
    'minimumSamples',40,'invalidVoltageCutoff',-4.8, ...
    'outlierMad',4,'makePlot',true,'plotUnits','z', ...
    'plotColorBy','horizontal'));
opts.plotUnits=validatestring(char(string(opts.plotUnits)),{'z','raw'});
opts.plotColorBy=validatestring(char(string(opts.plotColorBy)), ...
    {'horizontal','vertical'});
[animalLong,animalShort]=localAnimal(animal);
if isempty(opts.eyeCalPaths)
    dayFolder=localDayFolder(opts.dataRoot,animalLong,dateValue);
    listing=dir(fullfile(dayFolder,'**','*.EyeCal.mat'));
    paths=string(fullfile({listing.folder},{listing.name}))';
else
    paths=string(opts.eyeCalPaths(:));
    dayFolder="";
end
if isempty(paths)
    error('fitPupilPositionBias:NoEyeCalFiles', ...
        'No *.EyeCal.mat files were found for %s %s.',animalLong,string(dateValue));
end

rows=cell(0,1); setup=[];
for fileNo=1:numel(paths)
    loaded=load(paths(fileNo),'ex');
    if ~isfield(loaded,'ex'),continue;end
    ex=loaded.ex; setup=ex.setup;
    for trialNo=1:numel(ex.Trials)
        T=ex.Trials(trialNo);
        if ~isfield(T,'Eye')||~isfield(T.Eye,'v')||size(T.Eye.v,1)<6|| ...
                ~isfield(T,'targ')||~isfield(T.targ,'Pos')||numel(T.targ.Pos)<2
            continue
        end
        n=size(T.Eye.v,2);
        if isfield(T.Eye,'n')&&isscalar(T.Eye.n)&&isfinite(T.Eye.n)
            n=min(n,max(0,round(double(T.Eye.n))));
        end
        if n<2,continue;end
        V=double(T.Eye.v(:,1:n));
        if isfield(T.Eye,'t')&&numel(T.Eye.t)>=n
            time=double(T.Eye.t(1:n));time=time-time(1);
        else
            time=(0:n-1)/inferFs(ex);
        end
        endTime=max(time(isfinite(time)),[],'omitnan');
        stable=time>=endTime-opts.endPaddingSec-opts.stableTailSec & ...
            time<=endTime-opts.endPaddingSec;
        pupil=[V(3,:)',V(6,:)'];
        eyeValid=[all(isfinite(V(1:3,:)),1)' & all(V(1:3,:)'>opts.invalidVoltageCutoff,2), ...
            all(isfinite(V(4:6,:)),1)' & all(V(4:6,:)'>opts.invalidVoltageCutoff,2)];
        value=nan(1,2);nValid=zeros(1,2);
        for eye=1:2
            use=stable(:)&eyeValid(:,eye);
            nValid(eye)=sum(use);
            if nValid(eye)>=opts.minimumSamples
                value(eye)=median(pupil(use,eye),'omitnan');
            end
        end
        if ~any(isfinite(value)),continue;end
        posPx=double(T.targ.Pos(1:2));
        posDeg=px2deg(posPx,ex.setup);
        rows{end+1,1}=table(fileNo,trialNo,posPx(1),posPx(2), ... %#ok<AGROW>
            posDeg(1),posDeg(2),hypot(posDeg(1),posDeg(2)), ...
            value(1),value(2),nValid(1),nValid(2), ...
            'VariableNames',{'file','trial','xPx','yPx','xDeg','yDeg', ...
            'eccentricityDeg','rightPupil','leftPupil','nRight','nLeft'});
    end
end
if isempty(rows),error('fitPupilPositionBias:NoValidFixations', ...
        'No usable calibration fixations remained after filtering.');end
fixations=vertcat(rows{:});
right=localFitSurface(fixations,'rightPupil',opts);
left=localFitSurface(fixations,'leftPupil',opts);
fig=[];residualFig=[];
if logical(opts.makePlot)
    [fig,residualFig]=localPlot(fixations,right,left,opts);
end
model=struct('schema','pupil-position-bias-v1','animal',animalShort, ...
    'animalLong',animalLong,'date',string(dateValue),'dayFolder',string(dayFolder), ...
    'eyeCalPaths',paths,'setup',setup,'fixations',fixations, ...
    'right',right,'left',left,'figure',fig, ...
    'residualFigure',residualFig, ...
    'figures',struct('estimatedBias',fig,'residualComparison',residualFig), ...
    'opts',opts, ...
    'correctionDefinition','raw pupil - (spatial prediction - prediction at screen center)');
end

function fit=localFitSurface(T,responseName,opts)
y=double(T.(responseName));use=isfinite(y)&isfinite(T.xDeg)&isfinite(T.yDeg);
fixationRows=find(use);
file=double(T.file(use));x=double(T.xDeg(use));z=double(T.yDeg(use));y=y(use);
files=unique(file,'stable');
if numel(unique([x z],'rows'))<6,error('fitPupilPositionBias:TooFewPositions', ...
        'At least six unique calibration positions are required.');end
F=zeros(numel(y),numel(files));
for k=1:numel(files),F(:,k)=file==files(k);end
spatial=[x,z,x.^2,z.^2,x.*z]; X=[F spatial]; keep=true(size(y));
for iteration=1:5
    beta=X(keep,:)\y(keep); residual=y-X*beta;
    center=median(residual(keep),'omitnan');
    scale=1.4826*median(abs(residual(keep)-center),'omitnan');
    if ~isfinite(scale)||scale<=0,break;end
    next=abs(residual-center)<=opts.outlierMad*scale;
    if isequal(next,keep),break;end
    keep=next;
end
beta=X(keep,:)\y(keep);predicted=X*beta;residual=y-predicted;
[uncorrectedResidual,normalizationScale]=localWithinFileCenterAndScale(y,file);
fit=struct('spatialTerms',["xDeg","yDeg","xDeg2","yDeg2","xByY"], ...
    'spatialBeta',beta(numel(files)+1:end),'fileIntercepts',beta(1:numel(files)), ...
    'fileIds',files,'nFixations',numel(y),'nIncluded',sum(keep), ...
    'fixationRows',fixationRows,'includedFixationRows',fixationRows(keep), ...
    'included',keep,'observed',y,'predicted',predicted, ...
    'uncorrectedResidual',uncorrectedResidual,'residual',residual, ...
    'normalizationScale',normalizationScale, ...
    'rSquared',1-sum(residual(keep).^2)/sum((y(keep)-mean(y(keep))).^2));
end

function [centered,scale]=localWithinFileCenterAndScale(y,file)
centered=nan(size(y));
for value=unique(file(:))'
    selected=file==value;
    centered(selected)=y(selected)-median(y(selected),'omitnan');
end
center=median(centered,'omitnan');
scale=1.4826*median(abs(centered-center),'omitnan');
if ~isfinite(scale)||scale<=0,scale=std(centered,0,'omitnan');end
if ~isfinite(scale)||scale<=0,scale=1;end
end

function [fig,residualFig]=localPlot(T,right,left,opts)
fig=figure('Color','w','Position',[100 100 1050 470]);
tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
fits={right,left};names={'Right eye','Left eye'};
spatial=[T.xDeg,T.yDeg,T.xDeg.^2,T.yDeg.^2,T.xDeg.*T.yDeg];
if strcmp(opts.plotColorBy,'vertical')
    colorValue=T.yDeg;
    colorLabel='Vertical gaze position (deg)';
else
    colorValue=T.xDeg;
    colorLabel='Horizontal gaze position (deg)';
end
for eye=1:2
    bias=spatial*fits{eye}.spatialBeta;
    if strcmp(opts.plotUnits,'z')
        bias=bias/fits{eye}.normalizationScale;
        yLabel='Estimated position bias (calibration robust SD)';
    else
        yLabel='Estimated position bias (raw acquisition units)';
    end
    ax=nexttile;scatter(ax,T.eccentricityDeg,bias,38,colorValue,'filled', ...
        'MarkerFaceAlpha',.65);yline(ax,0,'k--');grid(ax,'on');
    xlabel(ax,'Gaze eccentricity (deg)');ylabel(ax,yLabel);
    cb=colorbar(ax);cb.Label.String=colorLabel;
    title(ax,sprintf('%s (spatial model R^2=%.2f)',names{eye},fits{eye}.rSquared));
end
sgtitle('EyeCal-estimated pupil measurement bias relative to screen center');

residualFig=figure('Color','w','Position',[130 80 1050 760]);
tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
for eye=1:2
    fit=fits{eye};rows=fit.fixationRows;keep=fit.included;
    eccentricity=T.eccentricityDeg(rows(keep));
    residualColor=colorValue(rows(keep));
    before=fit.uncorrectedResidual(keep);
    after=fit.residual(keep);
    if strcmp(opts.plotUnits,'z')
        before=before/fit.normalizationScale;
        after=after/fit.normalizationScale;
        residualLabel='Pupil residual (calibration robust SD)';
    else
        residualLabel='Pupil residual (raw acquisition units)';
    end
    ax=nexttile;scatter(ax,eccentricity,before,38,residualColor,'filled', ...
        'MarkerFaceAlpha',.65);yline(ax,0,'k--');grid(ax,'on');
    xlabel(ax,'Gaze eccentricity (deg)');ylabel(ax,residualLabel);
    cb=colorbar(ax);cb.Label.String=colorLabel;
    title(ax,[names{eye} ': before spatial correction']);
    ax=nexttile;scatter(ax,eccentricity,after,38,residualColor,'filled', ...
        'MarkerFaceAlpha',.65);yline(ax,0,'k--');grid(ax,'on');
    xlabel(ax,'Gaze eccentricity (deg)');ylabel(ax,residualLabel);
    cb=colorbar(ax);cb.Label.String=colorLabel;
    title(ax,[names{eye} ': after spatial correction']);
end
sgtitle('EyeCal pupil residuals before and after position correction');
end

function folder=localDayFolder(root,animal,dateValue)
animalRoot=fullfile(char(root),animal);listing=dir(animalRoot);listing=listing([listing.isdir]);
names=string({listing.name});names=names(~ismember(names,[".",".."]))';
token=lower(regexprep(char(string(dateValue)),'[^a-zA-Z0-9]',''));
match=false(size(names));
for i=1:numel(names)
    dt=regexp(names(i),'^(\d{4})\.(\d{2})\.(\d{2})','tokens','once');
    if isempty(dt),continue;end
    fullToken=lower([dt{1} dt{2} dt{3}]);
    shortToken=lower(datestr(datetime(str2double(dt{1}),str2double(dt{2}), ...
        str2double(dt{3})),'mmmdd'));
    match(i)=strcmp(token,fullToken)||strcmp(token,shortToken);
end
candidates=names(match);
if isempty(candidates),error('fitPupilPositionBias:DayNotFound', ...
        'Could not find %s/%s under %s.',animal,string(dateValue),root);end
folder=fullfile(animalRoot,char(candidates(end)));
end

function [long,short]=localAnimal(value)
key=lower(char(string(value)));
if ismember(key,{'ka','kaki'}),long='kaki';short='ka';
elseif ismember(key,{'ly','lychee'}),long='lychee';short='ly';
else,error('fitPupilPositionBias:BadAnimal','Animal must be ka/kaki or ly/lychee.');end
end
function opts=localDefaults(opts,defaults)
f=fieldnames(defaults);for i=1:numel(f),if ~isfield(opts,f{i})||isempty(opts.(f{i})),opts.(f{i})=defaults.(f{i});end,end
end
