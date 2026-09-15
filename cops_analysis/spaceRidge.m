function out = spaceRidge(in, trialNo, opts, varargin)
% spaceRidge  Reward-centered spatial modulation of temporal tracking gain.
%
%   out = spaceRidge(ex)
%   out = spaceRidge(ex, 'bg', opts)
%   out = spaceRidge(ex, {'bg','vis'}, opts)
%
% First fits the usual temporal target-to-gaze ridge model with tempRidge().
% Then it asks whether the temporally weighted target drive is amplified or
% weakened as a function of selected-target location relative to the Gaussian
% reward center.
%
% The first implementation estimates scalar gain shared across x/y:
%   gazeAxis(t) = temporalPredictionAxis(t) + sum_bin delta(bin) * drive_bin(t)
%   gain(bin) = 1 + delta(bin)
%
% Options
%   .signalMode          (default 'velocity') forwarded to tempRidge
%   .lagWindowSec        (default [-0.5 2.5]) forwarded to tempRidge
%   .spatialBinSizeDeg   (default 2) reward-centered bin width
%   .spatialRangeDeg     (default []) [] auto, scalar R, [min max], or
%                         [xMin xMax yMin yMax]
%   .xEdgesDeg/.yEdgesDeg (default []) explicit reward-centered bin edges
%   .constrainToTexture  (default true) with automatic edges, use the
%                         rendered texture bounds relative to reward center
%   .binPositionMode     (default 'post') 'post', 'pre', or 'midpoint' for
%                         velocity-mode target-location assignment
%   .spaceLambda         (default 0.01) ridge strength for spatial deltas;
%                         [] selects by cross-validation
%   .spaceLambdaGrid     (default logspace(-6, 2, 33))
%   .cvFolds             (default 5)
%   .cvMode              (default 'trial') 'trial', 'chunk', or 'observation'
%   .cvSeed              (default 1)
%   .standardize         (default true)
%   .minSamples          (default 25)
%   .minBinSamples       (default 25)
%   .plot                (default true)
%   .newFigure           (default true)
%   .clim                (default []) color limits for gain heat maps

if nargin < 2
    trialNo = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
if ischar(opts) || (isstring(opts) && isscalar(opts))
    if ~strcmpi(char(string(opts)), 'all')
        error('spaceRidge:BadOpts', 'Third argument must be opts or the legacy string ''all''.');
    end
    if ~isempty(varargin)
        opts = varargin{1};
    else
        opts = struct();
    end
elseif ~isstruct(opts)
    error('spaceRidge:BadOpts', 'Third argument must be an opts struct.');
end
if ~localIsExStruct(in)
    error('spaceRidge:RequiresEx', ...
        'spaceRidge currently requires raw ex input so reward centers can be resolved.');
end

defaults = struct( ...
    'analysisMode', 'continuous', ...
    'signalMode', 'velocity', ...
    'lagWindowSec', [-0.5 2.5], ...
    'spatialBinSizeDeg', 2, ...
    'spatialRangeDeg', [], ...
    'xEdgesDeg', [], ...
    'yEdgesDeg', [], ...
    'constrainToTexture', true, ...
    'binPositionMode', 'post', ...
    'spaceLambda', 0.01, ...
    'spaceLambdaGrid', logspace(-6, 2, 33), ...
    'cvFolds', 5, ...
    'cvMode', 'trial', ...
    'cvSeed', 1, ...
    'standardize', true, ...
    'setup', [], ...
    'minSamples', 25, ...
    'minBinSamples', 25, ...
    'plot', true, ...
    'newFigure', true, ...
    'clim', [], ...
    'lineWidth', 1.25);
opts = localApplyDefaults(opts, defaults);
opts.analysisMode = validatestring(char(string(opts.analysisMode)), {'continuous'});
opts.signalMode = validatestring(char(string(opts.signalMode)), {'velocity', 'position'});
opts.binPositionMode = validatestring(char(string(opts.binPositionMode)), {'post', 'pre', 'midpoint'});
opts.cvMode = validatestring(char(string(opts.cvMode)), {'trial', 'chunk', 'observation'});
opts.spatialBinSizeDeg = double(localFirstScalar(opts.spatialBinSizeDeg));
if ~isfinite(opts.spatialBinSizeDeg) || opts.spatialBinSizeDeg <= 0
    error('spaceRidge:BadBinSize', 'opts.spatialBinSizeDeg must be a finite positive scalar.');
end
opts.spaceLambdaGrid = localValidateLambdaGrid(opts.spaceLambdaGrid);
opts.cvFolds = max(2, round(double(localFirstScalar(opts.cvFolds))));
opts.cvSeed = double(localFirstScalar(opts.cvSeed));
opts.standardize = logical(opts.standardize);
opts.constrainToTexture = logical(opts.constrainToTexture);
if isempty(opts.setup) && isfield(in, 'setup')
    opts.setup = in.setup;
end
opts.minSamples = max(1, round(double(localFirstScalar(opts.minSamples))));
opts.minBinSamples = max(1, round(double(localFirstScalar(opts.minBinSamples))));

tempOpts = localTempRidgeOpts(opts);
temporal = tempRidge(in, trialNo, tempOpts);
episodes = temporal.episodes;
if isempty(episodes)
    error('spaceRidge:NoEpisodes', 'tempRidge/ccg returned no usable episodes.');
end

[xEdgesDeg, yEdgesDeg] = localResolveSpatialEdges(in, episodes, opts);
xCentersDeg = localBinCenters(xEdgesDeg);
yCentersDeg = localBinCenters(yEdgesDeg);
nGroup = numel(temporal.trialGroups);
groups = cell(nGroup, 1);
for g = 1:nGroup
    if ismember('group', episodes.Properties.VariableNames)
        Eg = episodes(double(episodes.group) == g, :);
    else
        Eg = episodes;
    end
    groups{g} = localFitSpatialGroup(in, Eg, temporal.groups{g}, ...
        xEdgesDeg, yEdgesDeg, opts, g, temporal.groupLabels(g));
end

if opts.plot
    localPlotSpaceRidge(groups, xCentersDeg, yCentersDeg, opts);
end

out = struct();
out.episodes = episodes;
out.trials = temporal.trials;
out.trialGroups = temporal.trialGroups;
out.groupLabels = temporal.groupLabels;
out.groupingSpec = temporal.groupingSpec;
out.inputMode = temporal.inputMode;
out.analysisMode = char(opts.analysisMode);
out.signalMode = char(opts.signalMode);
out.xEdgesDeg = xEdgesDeg(:)';
out.yEdgesDeg = yEdgesDeg(:)';
out.xCentersDeg = xCentersDeg(:)';
out.yCentersDeg = yCentersDeg(:)';
out.spatialBinSizeDeg = opts.spatialBinSizeDeg;
out.binPositionMode = char(opts.binPositionMode);
out.groups = groups;
out.temporal = temporal;
out.opts = opts;
end


function opts = localApplyDefaults(opts, defaults)
fields = fieldnames(defaults);
for i = 1:numel(fields)
    field = fields{i};
    if ~isfield(opts, field)
        opts.(field) = defaults.(field);
    end
end
end


function tempOpts = localTempRidgeOpts(opts)
tempOpts = opts;
removeFields = {'spatialBinSizeDeg','spatialRangeDeg','xEdgesDeg','yEdgesDeg', ...
    'constrainToTexture','binPositionMode','spaceLambda','spaceLambdaGrid','minBinSamples','clim'};
tempOpts = rmfield(tempOpts, intersect(fieldnames(tempOpts), removeFields));
tempOpts.analysisMode = 'continuous';
tempOpts.rewardDirectionMode = false;
tempOpts.rewardRegionMode = false;
tempOpts.plot = false;
tempOpts.newFigure = false;
end


function [xEdgesDeg, yEdgesDeg] = localResolveSpatialEdges(ex, episodes, opts)
if ~isempty(opts.xEdgesDeg) || ~isempty(opts.yEdgesDeg)
    if isempty(opts.xEdgesDeg) || isempty(opts.yEdgesDeg)
        error('spaceRidge:BadEdges', 'Specify both opts.xEdgesDeg and opts.yEdgesDeg, or neither.');
    end
    xEdgesDeg = localValidateEdges(opts.xEdgesDeg, 'xEdgesDeg');
    yEdgesDeg = localValidateEdges(opts.yEdgesDeg, 'yEdgesDeg');
    return
end

range = localResolveSpatialRange(opts.spatialRangeDeg);
if ~isempty(range)
    xEdgesDeg = localRangeEdges(range(1), range(2), opts.spatialBinSizeDeg);
    yEdgesDeg = localRangeEdges(range(3), range(4), opts.spatialBinSizeDeg);
    return
end

if opts.constrainToTexture
    range = localRewardCenteredTextureRangeDeg(ex, episodes);
    if ~isempty(range)
        xEdgesDeg = localRangeEdges(range(1), range(2), opts.spatialBinSizeDeg);
        yEdgesDeg = localRangeEdges(range(3), range(4), opts.spatialBinSizeDeg);
        return
    end
end

[relX, relY] = localCollectRewardCenteredPositions(ex, episodes);
if isempty(relX) || isempty(relY)
    error('spaceRidge:NoSpatialSamples', 'Could not resolve finite reward-centered target positions.');
end
allRel = abs([relX(:); relY(:)]);
allRel = allRel(isfinite(allRel));
radius = max(allRel);
if ~isfinite(radius) || radius <= 0
    radius = opts.spatialBinSizeDeg;
end
radius = ceil(radius ./ opts.spatialBinSizeDeg) .* opts.spatialBinSizeDeg;
xEdgesDeg = localRangeEdges(-radius, radius, opts.spatialBinSizeDeg);
yEdgesDeg = xEdgesDeg;
if numel(xEdgesDeg) < 2
    xEdgesDeg = [-opts.spatialBinSizeDeg opts.spatialBinSizeDeg];
    yEdgesDeg = xEdgesDeg;
end
end


function edges = localValidateEdges(edges, fieldName)
edges = double(edges(:)');
if numel(edges) < 2 || any(~isfinite(edges)) || any(diff(edges) <= 0)
    error('spaceRidge:BadEdges', 'opts.%s must be a finite increasing vector.', fieldName);
end
end


function range = localResolveSpatialRange(value)
range = [];
if isempty(value)
    return
end
value = double(value(:)');
if isscalar(value)
    if ~isfinite(value) || value <= 0
        error('spaceRidge:BadRange', 'Scalar opts.spatialRangeDeg must be finite and positive.');
    end
    range = [-value value -value value];
elseif numel(value) == 2
    if any(~isfinite(value)) || value(1) >= value(2)
        error('spaceRidge:BadRange', 'Two-element opts.spatialRangeDeg must be [min max].');
    end
    range = [value value];
elseif numel(value) == 4
    if any(~isfinite(value)) || value(1) >= value(2) || value(3) >= value(4)
        error('spaceRidge:BadRange', ...
            'Four-element opts.spatialRangeDeg must be [xMin xMax yMin yMax].');
    end
    range = value;
else
    error('spaceRidge:BadRange', ...
        'opts.spatialRangeDeg must be empty, scalar, [min max], or [xMin xMax yMin yMax].');
end
end


function edges = localRangeEdges(a, b, binSize)
a = double(localFirstScalar(a));
b = double(localFirstScalar(b));
binSize = double(localFirstScalar(binSize));
lo = floor(a ./ binSize) .* binSize;
hi = ceil(b ./ binSize) .* binSize;
nStep = max(1, round((hi - lo) ./ binSize));
edges = lo + (0:nStep) .* binSize;
if numel(edges) < 2
    edges = [lo lo + binSize];
end
end


function centers = localBinCenters(edges)
centers = (edges(1:end-1) + edges(2:end)) ./ 2;
end


function range = localRewardCenteredTextureRangeDeg(ex, episodes)
range = [];
bounds = localTextureBoundsPx(ex);
if any(~isfinite([bounds.xMin bounds.xMax bounds.yMin bounds.yMax]))
    return
end
trialIds = unique(double(episodes.trial(:))', 'stable');
xMin = Inf;
xMax = -Inf;
yMin = Inf;
yMax = -Inf;
for i = 1:numel(trialIds)
    center = localRewardCenterForTrial(ex, trialIds(i));
    if any(~isfinite(center))
        continue
    end
    xRel = px2deg([bounds.xMin bounds.xMax] - center(1), ex.setup);
    yRel = px2deg([bounds.yMin bounds.yMax] - center(2), ex.setup);
    if any(~isfinite([xRel yRel]))
        continue
    end
    xMin = min(xMin, min(xRel));
    xMax = max(xMax, max(xRel));
    yMin = min(yMin, min(yRel));
    yMax = max(yMax, max(yRel));
end
if all(isfinite([xMin xMax yMin yMax])) && xMin < xMax && yMin < yMax
    range = [xMin xMax yMin yMax];
end
end


function bounds = localTextureBoundsPx(ex)
bounds = struct('xMin', NaN, 'xMax', NaN, 'yMin', NaN, 'yMax', NaN);
if ~isfield(ex, 'setup') || ~isfield(ex.setup, 'screenRect') || ...
        ~isfield(ex, 'exp') || ~isfield(ex.exp, 'CoPs') || ...
        ~isfield(ex.exp.CoPs, 'graph')
    return
end
graph = ex.exp.CoPs.graph;
if ~isfield(graph, 'texture_dims') || ~isfield(graph, 'size_mult')
    return
end
screenRect = double(ex.setup.screenRect);
textureDims = double(graph.texture_dims(:)');
sizeMult = double(localFirstScalar(graph.size_mult));
if numel(screenRect) < 4 || isempty(textureDims) || ~isfinite(sizeMult) || sizeMult <= 0
    return
end
screenW = double(localFirstScalar(screenRect(3)));
screenH = double(localFirstScalar(screenRect(4)));
texW = double(localFirstScalar(textureDims(1))) .* sizeMult;
if numel(textureDims) >= 2
    texH = double(localFirstScalar(textureDims(2))) .* sizeMult;
else
    texH = texW;
end
badTextureBounds = true;
if isscalar(screenW) && isscalar(screenH) && isscalar(texW) && isscalar(texH)
    nonFinite = [~isfinite(screenW), ~isfinite(screenH), ~isfinite(texW), ~isfinite(texH)];
    nonPositive = [texW <= 0, texH <= 0];
    badTextureBounds = any(nonFinite) || any(nonPositive);
end
if badTextureBounds
    return
end
xMin = (screenW - texW) ./ 2;
yMin = (screenH - texH) ./ 2;
bounds.xMin = xMin;
bounds.xMax = xMin + texW;
bounds.yMin = yMin;
bounds.yMax = yMin + texH;
end


function [relX, relY] = localCollectRewardCenteredPositions(ex, episodes)
relX = [];
relY = [];
for i = 1:height(episodes)
    trialNo = double(localFirstScalar(episodes.trial(i)));
    center = localRewardCenterForTrial(ex, trialNo);
    if any(~isfinite(center))
        continue
    end
    tx = double(episodes.targetX{i}(:));
    ty = double(episodes.targetY{i}(:));
    keep = isfinite(tx) & isfinite(ty);
    if ~any(keep)
        continue
    end
    relX = [relX; px2deg(tx(keep) - center(1), ex.setup)]; %#ok<AGROW>
    relY = [relY; px2deg(ty(keep) - center(2), ex.setup)]; %#ok<AGROW>
end
end


function group = localFitSpatialGroup(ex, E, temporalGroup, xEdgesDeg, yEdgesDeg, opts, groupNo, groupLabel)
group = localEmptyGroup(xEdgesDeg, yEdgesDeg);
group.group = groupNo;
group.groupLabel = string(groupLabel);
if isempty(E)
    return
end
group.trials = unique(double(E.trial(:))', 'stable');

[X, residual, response, basePred, trialId, chunkId, support] = ...
    localBuildSpatialDesign(ex, E, temporalGroup, xEdgesDeg, yEdgesDeg, opts);
group.supportMap = reshape(support, numel(yEdgesDeg)-1, numel(xEdgesDeg)-1);
keepBin = support(:) >= opts.minBinSamples;
group.nKeptBins = nnz(keepBin);
if isempty(residual) || nnz(keepBin) == 0
    return
end

fit = localFitSpatialRidge(X(:, keepBin), residual, response, basePred, trialId, chunkId, opts);
group.fit = fit;
group.nObs = fit.nObs;
group.baseR2 = fit.baseR2;
group.r2 = fit.r2;
group.cvR2 = fit.cvR2;
group.residualR2 = fit.residualR2;
group.baseResidSd = fit.baseResidSd;
group.residSd = fit.residSd;
group.cvResidSd = fit.cvResidSd;
group.baseResidSdDeg = fit.baseResidSdDeg;
group.residSdDeg = fit.residSdDeg;
group.cvResidSdDeg = fit.cvResidSdDeg;
group.lambda = fit.lambda;

delta = NaN(numel(keepBin), 1);
delta(keepBin) = fit.beta;
gain = 1 + delta;
group.delta = delta;
group.gain = gain;
group.deltaMap = reshape(delta, numel(yEdgesDeg)-1, numel(xEdgesDeg)-1);
group.gainMap = reshape(gain, numel(yEdgesDeg)-1, numel(xEdgesDeg)-1);
group.binTable = localBinTable(xEdgesDeg, yEdgesDeg, gain, delta, support(:));
end


function group = localEmptyGroup(xEdgesDeg, yEdgesDeg)
nBin = max(0, (numel(xEdgesDeg)-1) * (numel(yEdgesDeg)-1));
ny = max(0, numel(yEdgesDeg)-1);
nx = max(0, numel(xEdgesDeg)-1);
group = struct();
group.group = NaN;
group.groupLabel = "";
group.trials = [];
group.nObs = 0;
group.nKeptBins = 0;
group.baseR2 = NaN;
group.r2 = NaN;
group.cvR2 = NaN;
group.residualR2 = NaN;
group.baseResidSd = NaN;
group.residSd = NaN;
group.cvResidSd = NaN;
group.baseResidSdDeg = NaN;
group.residSdDeg = NaN;
group.cvResidSdDeg = NaN;
group.lambda = NaN;
group.gain = NaN(nBin, 1);
group.delta = NaN(nBin, 1);
group.gainMap = NaN(ny, nx);
group.deltaMap = NaN(ny, nx);
group.supportMap = NaN(ny, nx);
group.binTable = localBinTable(xEdgesDeg, yEdgesDeg, NaN(nBin, 1), NaN(nBin, 1), NaN(nBin, 1));
group.fit = localEmptyFit();
end


function [X, residual, response, basePred, trialId, chunkId, support] = ...
    localBuildSpatialDesign(ex, E, temporalGroup, xEdgesDeg, yEdgesDeg, opts)
nBin = (numel(xEdgesDeg)-1) * (numel(yEdgesDeg)-1);
XBlocks = cell(height(E) * 2, 1);
resBlocks = cell(height(E) * 2, 1);
respBlocks = cell(height(E) * 2, 1);
baseBlocks = cell(height(E) * 2, 1);
trialBlocks = cell(height(E) * 2, 1);
chunkBlocks = cell(height(E) * 2, 1);
support = zeros(nBin, 1);
nBlocks = 0;

axes = {'x', 'y'};
for i = 1:height(E)
    trialNo = double(localFirstScalar(E.trial(i)));
    center = localRewardCenterForTrial(ex, trialNo);
    if any(~isfinite(center))
        continue
    end
    targetX = double(E.targetX{i}(:));
    targetY = double(E.targetY{i}(:));
    gazeX = double(E.gazeX{i}(:));
    gazeY = double(E.gazeY{i}(:));
    dtStepSec = double(localFirstScalar(E.dtStepSec(i)));
    if ~isfinite(dtStepSec) || dtStepSec <= 0
        continue
    end
    for a = 1:numel(axes)
        axisName = axes{a};
        switch axisName
            case 'x'
                gaze = gazeX;
                target = targetX;
                temporalFit = temporalGroup.x;
            case 'y'
                gaze = gazeY;
                target = targetY;
                temporalFit = temporalGroup.y;
        end
        [Xi, ri, yi, bi, support] = localEpisodeSpatialDesign( ...
            ex, gaze, target, targetX, targetY, center, dtStepSec, temporalFit, ...
            xEdgesDeg, yEdgesDeg, opts, support);
        if isempty(ri)
            continue
        end
        nBlocks = nBlocks + 1;
        XBlocks{nBlocks} = Xi;
        resBlocks{nBlocks} = ri;
        respBlocks{nBlocks} = yi;
        baseBlocks{nBlocks} = bi;
        trialBlocks{nBlocks} = repmat(trialNo, numel(ri), 1);
        chunkBlocks{nBlocks} = repmat(i, numel(ri), 1);
    end
end

if nBlocks == 0
    X = NaN(0, nBin);
    residual = NaN(0, 1);
    response = NaN(0, 1);
    basePred = NaN(0, 1);
    trialId = NaN(0, 1);
    chunkId = NaN(0, 1);
else
    X = vertcat(XBlocks{1:nBlocks});
    residual = vertcat(resBlocks{1:nBlocks});
    response = vertcat(respBlocks{1:nBlocks});
    basePred = vertcat(baseBlocks{1:nBlocks});
    trialId = vertcat(trialBlocks{1:nBlocks});
    chunkId = vertcat(chunkBlocks{1:nBlocks});
end
end


function [X, residual, response, predBase, support] = localEpisodeSpatialDesign( ...
    ex, gaze, target, targetX, targetY, centerPx, dtStepSec, temporalFit, ...
    xEdgesDeg, yEdgesDeg, opts, support)
lagSamples = double(temporalFit.lagSamples(:)');
beta = double(temporalFit.beta(:)');
intercept = double(localFirstScalar(temporalFit.intercept));
nLag = numel(lagSamples);
nBin = (numel(xEdgesDeg)-1) * (numel(yEdgesDeg)-1);
X = NaN(0, nBin);
residual = NaN(0, 1);
response = NaN(0, 1);
predBase = NaN(0, 1);
if nLag == 0 || numel(beta) ~= nLag || any(~isfinite(beta)) || ~isfinite(intercept)
    return
end

[stimulus, responseSeries, posX, posY] = localSignalAndBinPositions( ...
    gaze, target, targetX, targetY, dtStepSec, opts);
n = min([numel(stimulus), numel(responseSeries), numel(posX), numel(posY)]);
if n < 1
    return
end
stimulus = stimulus(1:n);
responseSeries = responseSeries(1:n);
posX = posX(1:n);
posY = posY(1:n);
relX = px2deg(posX - centerPx(1), ex.setup);
relY = px2deg(posY - centerPx(2), ex.setup);
xBin = discretize(relX, xEdgesDeg);
yBin = discretize(relY, yEdgesDeg);
bin = NaN(size(xBin));
inside = isfinite(xBin) & isfinite(yBin);
bin(inside) = sub2ind([numel(yEdgesDeg)-1, numel(xEdgesDeg)-1], yBin(inside), xBin(inside));

rows = cell(n, 1);
yRows = NaN(n, 1);
baseRows = NaN(n, 1);
nRows = 0;
for t = 1:n
    src = t - lagSamples;
    inRange = src >= 1 & src <= n;
    if ~all(inRange) || ~isfinite(responseSeries(t))
        continue
    end
    src = round(src);
    stimLag = stimulus(src);
    if any(~isfinite(stimLag))
        continue
    end
    stimLag = double(stimLag(:)');
    xrow = zeros(1, nBin);
    base = intercept + sum(beta .* stimLag);
    for j = 1:nLag
        b = bin(src(j));
        if isfinite(b)
            xrow(b) = xrow(b) + beta(j) .* stimLag(j);
            support(b) = support(b) + 1;
        end
    end
    if ~any(xrow)
        continue
    end
    nRows = nRows + 1;
    rows{nRows} = xrow;
    yRows(nRows) = responseSeries(t);
    baseRows(nRows) = base;
end

if nRows == 0
    return
end
X = vertcat(rows{1:nRows});
response = yRows(1:nRows);
predBase = baseRows(1:nRows);
residual = response - predBase;
end


function [stimulus, response, posX, posY] = localSignalAndBinPositions( ...
    gaze, target, targetX, targetY, dtStepSec, opts)
gaze = double(gaze(:));
target = double(target(:));
targetX = double(targetX(:));
targetY = double(targetY(:));
switch char(string(opts.signalMode))
    case 'velocity'
        n = min([numel(gaze), numel(target), numel(targetX), numel(targetY)]);
        gaze = gaze(1:n);
        target = target(1:n);
        targetX = targetX(1:n);
        targetY = targetY(1:n);
        stimulus = diff(target) ./ dtStepSec;
        response = diff(gaze) ./ dtStepSec;
        switch char(string(opts.binPositionMode))
            case 'pre'
                posX = targetX(1:end-1);
                posY = targetY(1:end-1);
            case 'post'
                posX = targetX(2:end);
                posY = targetY(2:end);
            case 'midpoint'
                posX = (targetX(1:end-1) + targetX(2:end)) ./ 2;
                posY = (targetY(1:end-1) + targetY(2:end)) ./ 2;
        end
    case 'position'
        n = min([numel(gaze), numel(target), numel(targetX), numel(targetY)]);
        stimulus = target(1:n);
        response = gaze(1:n);
        posX = targetX(1:n);
        posY = targetY(1:n);
end
end


function fit = localFitSpatialRidge(X, residual, response, basePred, trialId, chunkId, opts)
fit = localEmptyFit();
valid = isfinite(residual(:)) & isfinite(response(:)) & isfinite(basePred(:)) & all(isfinite(X), 2);
X = double(X(valid, :));
residual = double(residual(valid));
response = double(response(valid));
basePred = double(basePred(valid));
trialId = double(trialId(valid));
chunkId = double(chunkId(valid));

fit.nObs = numel(residual);
fit.nPredictors = size(X, 2);
fit.baseR2 = localR2(response, basePred);
fit.baseResidSd = localResidualSd(response, basePred);
fit.baseResidSdDeg = localConvertSignalPxToDeg(fit.baseResidSd, opts);
if fit.nObs < opts.minSamples || fit.nPredictors == 0
    return
end

[foldId, nFolds] = localMakeFolds(fit.nObs, trialId, chunkId, opts);
lambdaGrid = localResolveFitLambdas(opts.spaceLambda, opts.spaceLambdaGrid);
cvMse = NaN(size(lambdaGrid));
if isempty(opts.spaceLambda) && nFolds >= 2
    for i = 1:numel(lambdaGrid)
        cvMse(i) = localCrossValMse(X, residual, foldId, nFolds, lambdaGrid(i), opts.standardize);
    end
    if any(isfinite(cvMse))
        [~, bestIdx] = min(cvMse);
    else
        bestIdx = ceil(numel(lambdaGrid) / 2);
    end
else
    bestIdx = 1;
end
lambda = lambdaGrid(bestIdx);

model = localFitRidgeModel(X, residual, lambda, opts.standardize);
resHat = localPredictRidgeModel(model, X);
fullHat = basePred + resHat;

fit.beta = model.beta(:);
fit.betaStd = model.betaStd(:);
fit.intercept = model.intercept;
fit.lambda = lambda;
fit.residualR2 = localR2(residual, resHat);
fit.r2 = localR2(response, fullHat);
fit.baseR2 = localR2(response, basePred);
fit.r2Gain = fit.r2 - fit.baseR2;
fit.residSd = localResidualSd(response, fullHat);
fit.residSdDeg = localConvertSignalPxToDeg(fit.residSd, opts);
fit.y = response;
fit.basePred = basePred;
fit.yHat = fullHat;
fit.residual = residual;
fit.residualHat = resHat;
fit.trial = trialId;
fit.chunk = chunkId;
fit.xMean = model.xMean;
fit.xScale = model.xScale;
fit.cvMse = cvMse;
fit.lambdaGrid = lambdaGrid;
fit.foldId = foldId;

if nFolds >= 2
    cvResHat = localCrossValPred(X, residual, foldId, nFolds, lambda, opts.standardize);
    fit.cvResidualHat = cvResHat;
    cvFullHat = basePred + cvResHat;
    fit.cvYHat = cvFullHat;
    fit.cvR2 = localR2(response(isfinite(cvFullHat)), cvFullHat(isfinite(cvFullHat)));
    fit.cvResidualR2 = localR2(residual(isfinite(cvResHat)), cvResHat(isfinite(cvResHat)));
    fit.cvResidSd = localResidualSd(response, cvFullHat);
    fit.cvResidSdDeg = localConvertSignalPxToDeg(fit.cvResidSd, opts);
end
end


function fit = localEmptyFit()
fit = struct();
fit.beta = NaN(0, 1);
fit.betaStd = NaN(0, 1);
fit.intercept = NaN;
fit.lambda = NaN;
fit.nObs = 0;
fit.nPredictors = 0;
fit.baseR2 = NaN;
fit.r2 = NaN;
fit.r2Gain = NaN;
fit.cvR2 = NaN;
fit.residualR2 = NaN;
fit.cvResidualR2 = NaN;
fit.baseResidSd = NaN;
fit.residSd = NaN;
fit.cvResidSd = NaN;
fit.baseResidSdDeg = NaN;
fit.residSdDeg = NaN;
fit.cvResidSdDeg = NaN;
fit.y = NaN(0, 1);
fit.basePred = NaN(0, 1);
fit.yHat = NaN(0, 1);
fit.cvYHat = NaN(0, 1);
fit.residual = NaN(0, 1);
fit.residualHat = NaN(0, 1);
fit.cvResidualHat = NaN(0, 1);
fit.trial = NaN(0, 1);
fit.chunk = NaN(0, 1);
fit.xMean = NaN(1, 0);
fit.xScale = NaN(1, 0);
fit.cvMse = NaN(0, 1);
fit.lambdaGrid = NaN(0, 1);
fit.foldId = NaN(0, 1);
end


function T = localBinTable(xEdgesDeg, yEdgesDeg, gain, delta, support)
xCenters = localBinCenters(xEdgesDeg);
yCenters = localBinCenters(yEdgesDeg);
[xx, yy] = meshgrid(xCenters, yCenters);
T = table(xx(:), yy(:), gain(:), delta(:), support(:), ...
    'VariableNames', {'xCenterDeg','yCenterDeg','gain','delta','nLagContrib'});
end


function localPlotSpaceRidge(groups, xCentersDeg, yCentersDeg, opts)
if opts.newFigure
    figure;
end
nGroup = numel(groups);
nCol = min(3, ceil(sqrt(nGroup)));
nRow = ceil(nGroup ./ nCol);
if nGroup > 1
    tiledlayout(nRow, nCol, 'Padding', 'compact', 'TileSpacing', 'compact');
end
for g = 1:nGroup
    if nGroup > 1
        nexttile;
    end
    imagesc(xCentersDeg, yCentersDeg, groups{g}.gainMap);
    set(gca, 'YDir', 'normal');
    axis image
    hold on
    plot(0, 0, '+', 'Color', [0 0 0], 'LineWidth', opts.lineWidth, 'MarkerSize', 8);
    hold off
    xlabel('Target X relative to reward center (deg)');
    ylabel('Target Y relative to reward center (deg)');
    titleText = sprintf('%s | gain, cvR2 %.3g', ...
        char(string(groups{g}.groupLabel)), groups{g}.cvR2);
    if isfinite(groups{g}.cvResidSdDeg)
        titleText = sprintf('%s, cvSD %.3g %s', ...
            titleText, groups{g}.cvResidSdDeg, localDegSignalUnit(opts));
    end
    title(titleText, 'Interpreter', 'none');
    colorbar;
    if ~isempty(opts.clim)
        clim(double(opts.clim(:)'));
    end
end
if nGroup > 1
    sgtitle(sprintf('spaceRidge spatial gain (%d group%s)', nGroup, localPlural(nGroup)), ...
        'Interpreter', 'none');
end
end


function model = localFitRidgeModel(X, y, lambda, standardize)
X = double(X);
y = double(y(:));
n = size(X, 1);
p = size(X, 2);

xMean = mean(X, 1);
if standardize
    xScale = std(X, 0, 1);
    xScale(~isfinite(xScale) | xScale <= eps) = 1;
else
    xScale = ones(1, p);
end
Xz = (X - xMean) ./ xScale;
yMean = mean(y);
yc = y - yMean;

lambda = max(0, double(localFirstScalar(lambda)));
if lambda == 0
    betaStd = pinv(Xz) * yc;
else
    betaStd = (Xz' * Xz + n * lambda * eye(p)) \ (Xz' * yc);
end
beta = betaStd ./ xScale(:);
intercept = yMean - xMean * beta;

model = struct();
model.beta = beta;
model.betaStd = betaStd;
model.intercept = intercept;
model.xMean = xMean;
model.xScale = xScale;
model.yMean = yMean;
model.lambda = lambda;
end


function yHat = localPredictRidgeModel(model, X)
yHat = model.intercept + double(X) * model.beta;
end


function mse = localCrossValMse(X, y, foldId, nFolds, lambda, standardize)
pred = localCrossValPred(X, y, foldId, nFolds, lambda, standardize);
valid = isfinite(pred);
if ~any(valid)
    mse = NaN;
else
    err = y(valid) - pred(valid);
    mse = mean(err .^ 2, 'omitnan');
end
end


function pred = localCrossValPred(X, y, foldId, nFolds, lambda, standardize)
pred = NaN(size(y));
for f = 1:nFolds
    test = foldId == f;
    train = ~test & isfinite(foldId);
    if nnz(test) < 1 || nnz(train) < 2
        continue
    end
    model = localFitRidgeModel(X(train, :), y(train), lambda, standardize);
    pred(test) = localPredictRidgeModel(model, X(test, :));
end
end


function [foldId, nFolds] = localMakeFolds(nObs, trialId, chunkId, opts)
nFoldsRequested = max(2, round(double(localFirstScalar(opts.cvFolds))));
switch opts.cvMode
    case 'trial'
        unitId = trialId(:);
    case 'chunk'
        unitId = chunkId(:);
    case 'observation'
        unitId = (1:nObs)';
end

if numel(unique(unitId(isfinite(unitId)))) < 2 && ~strcmp(opts.cvMode, 'observation')
    unitId = (1:nObs)';
end

unitVals = unique(unitId(isfinite(unitId)), 'stable');
nUnits = numel(unitVals);
nFolds = min(nFoldsRequested, nUnits);
foldId = NaN(nObs, 1);
if nFolds < 2
    return
end

if isfinite(opts.cvSeed)
    prevRng = rng;
    cleanupObj = onCleanup(@() rng(prevRng));
    rng(opts.cvSeed);
end
perm = randperm(nUnits);
unitFold = zeros(nUnits, 1);
unitFold(perm) = mod(0:nUnits-1, nFolds) + 1;

for i = 1:nUnits
    foldId(unitId == unitVals(i)) = unitFold(i);
end
end


function lambdaGrid = localValidateLambdaGrid(lambdaGrid)
lambdaGrid = double(lambdaGrid(:));
lambdaGrid = lambdaGrid(isfinite(lambdaGrid) & lambdaGrid >= 0);
lambdaGrid = unique(lambdaGrid, 'stable');
if isempty(lambdaGrid)
    error('spaceRidge:BadLambdaGrid', ...
        'opts.spaceLambdaGrid must contain at least one finite nonnegative value.');
end
end


function lambdaGrid = localResolveFitLambdas(lambda, lambdaGrid)
if isempty(lambda)
    lambdaGrid = localValidateLambdaGrid(lambdaGrid);
else
    lambda = double(localFirstScalar(lambda));
    if ~isfinite(lambda) || lambda < 0
        error('spaceRidge:BadLambda', 'opts.spaceLambda must be empty or a finite nonnegative scalar.');
    end
    lambdaGrid = lambda;
end
end


function r2 = localR2(y, yHat)
y = double(y(:));
yHat = double(yHat(:));
valid = isfinite(y) & isfinite(yHat);
if nnz(valid) < 2
    r2 = NaN;
    return
end
y = y(valid);
yHat = yHat(valid);
sst = sum((y - mean(y)).^2);
if sst <= eps
    r2 = NaN;
else
    r2 = 1 - sum((y - yHat).^2) ./ sst;
end
end


function sd = localResidualSd(y, yHat)
y = double(y(:));
yHat = double(yHat(:));
valid = isfinite(y) & isfinite(yHat);
if nnz(valid) < 2
    sd = NaN;
else
    sd = std(y(valid) - yHat(valid), 0);
end
end


function valueDeg = localConvertSignalPxToDeg(valuePx, opts)
valueDeg = NaN(size(valuePx));
if ~isfield(opts, 'setup') || isempty(opts.setup) || ~isfinite(valuePx)
    return
end
try
    valueDeg = px2deg(valuePx, opts.setup);
catch
    valueDeg = NaN(size(valuePx));
end
end


function center = localRewardCenterForTrial(ex, trialNo)
center = [NaN NaN];
trialNo = round(double(localFirstScalar(trialNo)));
if ~isfinite(trialNo) || trialNo < 1 || trialNo > numel(ex.Trials)
    return
end
try
    center = getGaussianCenterPx(ex, ex.Trials(trialNo));
catch
    center = [NaN NaN];
end
center = double(center(:)');
if numel(center) < 2
    center = [NaN NaN];
else
    center = center(1:2);
end
end


function value = localFirstScalar(x)
value = NaN;
if isempty(x)
    return
end
if isscalar(x) && isfinite(double(x))
    value = double(x);
else
    value = double(x(1));
end
end


function suffix = localPlural(n)
if n == 1
    suffix = '';
else
    suffix = 's';
end
end


function unit = localDegSignalUnit(opts)
switch char(string(opts.signalMode))
    case 'velocity'
        unit = 'deg/s';
    otherwise
        unit = 'deg';
end
end


function tf = localIsExStruct(in)
tf = isstruct(in) && isfield(in, 'Trials') && ~isempty(in.Trials);
end
