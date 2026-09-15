function out = gazeHeat(ex, trialNo, opts)
% gazeHeat  Plot a smoothed 2-D density map of gaze locations.
%
%   gazeHeat(ex)
%   gazeHeat(ex, [])
%   gazeHeat(ex, 1:120)
%   out = gazeHeat(ex, trialNo, opts)
%
% Defaults analyze go-state samples inside the central texture and plot
% log2(gaze/target) density in visual degrees relative to fixation/screen
% center. Set opts.targetNormalize='none' for raw gaze density.
%
% Color options:
%   opts.colorScheme = 'balance' (default), 'auto', 'redBlue', 'hot',
%       'parula', 'turbo', 'viridis', 'magma', 'density', 'gray', or 'jet'.
%   opts.colormap can also be an n x 3 RGB colormap matrix.
%
% Reward-boundary options:
%   opts.circleBound = '1sd' (default), '2sd', '3sd', or 'mult'.
%   'mult' uses opts.rewardPeakMinMultiplier; SD modes draw 1/2/3 sigma rings.

if nargin < 2 || isempty(trialNo)
    trialNo = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
elseif isstruct(trialNo)
    opts = trialNo;
    trialNo = [];
end

opts = localDefaults(opts);

if ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('gazeHeat:NoTrials', 'Input ex has no trials in ex.Trials.');
end

trialList = localResolveTrialList(ex, trialNo);
[x0, y0] = localReferenceCenterPx(ex);
[plotBoundsPx, textureBoundsPx] = localPlotBoundsPx(ex, opts);

xAll = cell(numel(trialList), 1);
yAll = cell(numel(trialList), 1);
targetXAll = cell(numel(trialList), 1);
targetYAll = cell(numel(trialList), 1);
target1XAll = cell(numel(trialList), 1);
target1YAll = cell(numel(trialList), 1);
target2XAll = cell(numel(trialList), 1);
target2YAll = cell(numel(trialList), 1);
nValid = zeros(numel(trialList), 1);
nUsed = zeros(numel(trialList), 1);
nTargetUsed = zeros(numel(trialList), 1);

for i = 1:numel(trialList)
    trialIdx = trialList(i);
    T = ex.Trials(trialIdx);
    [xPx, yPx, tRel, tAbs, valid] = reconstructEyePx(ex, T, opts.useEyeTime, opts);
    [targetX, targetY, target2X, target2Y] = mapTargetsByStep(ex, T, tRel);

    keep = valid(:);
    if opts.onlyGoState
        keep = keep & localGoMask(T, tAbs);
    end
    if ~isempty(opts.timeWindowSec)
        tw = double(opts.timeWindowSec(:)');
        if numel(tw) ~= 2 || any(~isfinite(tw)) || tw(2) < tw(1)
            error('gazeHeat:BadTimeWindow', 'opts.timeWindowSec must be [start stop].');
        end
        keep = keep & tRel(:) >= tw(1) & tRel(:) <= tw(2);
    end
    if opts.insideTextureOnly
        keep = keep & xPx(:) >= textureBoundsPx.xMin & xPx(:) <= textureBoundsPx.xMax & ...
            yPx(:) >= textureBoundsPx.yMin & yPx(:) <= textureBoundsPx.yMax;
    end
    targetKeep = keep;
    if opts.targetDensityRequiresGazeOnScreen
        targetKeep = targetKeep & localOnScreenMask(xPx, yPx, ex.setup.screenRect);
    end

    nValid(i) = sum(valid(:));
    nUsed(i) = sum(keep);
    xAll{i} = xPx(keep);
    yAll{i} = yPx(keep);
    [targetXKeep, targetYKeep] = localSelectTargetSamples( ...
        targetX(targetKeep), targetY(targetKeep), target2X(targetKeep), target2Y(targetKeep), ...
        xPx(targetKeep), yPx(targetKeep), opts.targetDensityTarget);
    targetXAll{i} = targetXKeep;
    targetYAll{i} = targetYKeep;
    target1XAll{i} = targetX(targetKeep);
    target1YAll{i} = targetY(targetKeep);
    target2XAll{i} = target2X(targetKeep);
    target2YAll{i} = target2Y(targetKeep);
    nTargetUsed(i) = sum(isfinite(targetXKeep) & isfinite(targetYKeep));
end

xPx = vertcat(xAll{:});
yPx = vertcat(yAll{:});
targetXPx = vertcat(targetXAll{:});
targetYPx = vertcat(targetYAll{:});
target1XPx = vertcat(target1XAll{:});
target1YPx = vertcat(target1YAll{:});
target2XPx = vertcat(target2XAll{:});
target2YPx = vertcat(target2YAll{:});
if isempty(xPx)
    error('gazeHeat:NoSamples', 'No valid gaze samples remained after filtering.');
end

xDeg = px2deg(xPx - x0, ex.setup);
yDeg = px2deg(yPx - y0, ex.setup);
if opts.flipY
    yDeg = -yDeg;
end
targetXDeg = px2deg(targetXPx - x0, ex.setup);
targetYDeg = px2deg(targetYPx - y0, ex.setup);
if opts.flipY
    targetYDeg = -targetYDeg;
end
target1XDeg = px2deg(target1XPx - x0, ex.setup);
target1YDeg = px2deg(target1YPx - y0, ex.setup);
target2XDeg = px2deg(target2XPx - x0, ex.setup);
target2YDeg = px2deg(target2YPx - y0, ex.setup);
if opts.flipY
    target1YDeg = -target1YDeg;
    target2YDeg = -target2YDeg;
end

boundsDeg = localBoundsDeg(plotBoundsPx, x0, y0, ex.setup, opts.flipY);
xEdges = localEdges(boundsDeg.xMin, boundsDeg.xMax, opts.binSizeDeg);
yEdges = localEdges(boundsDeg.yMin, boundsDeg.yMax, opts.binSizeDeg);
rewardPeakPxByTrial = localRewardPeakPxByTrial(ex, trialList);
rewardPeakRadiusPxByTrial = localRewardPeakRadiusPxByTrial(ex, trialList, opts);
rewardPeakPx = localUniqueRowsTol(rewardPeakPxByTrial, 1e-6);
rewardPeakDeg = localPxToPlotDeg(rewardPeakPx, x0, y0, ex.setup, opts.flipY);
rewardPeakCirclePx = localRewardPeakCircleRowsPx(rewardPeakPxByTrial, rewardPeakRadiusPxByTrial);
rewardPeakCirclePx = localUniqueRowsTol(rewardPeakCirclePx, 1e-6);
rewardPeakCircleDeg = localRewardPeakCircleDeg(rewardPeakCirclePx, x0, y0, ex.setup, opts.flipY);

counts = localHistcounts2(xDeg, yDeg, xEdges, yEdges);
targetCounts = localHistcounts2(targetXDeg, targetYDeg, xEdges, yEdges);
smoothCounts = localSmooth2(counts, opts.smoothSigmaDeg ./ opts.binSizeDeg);
smoothTargetCounts = localSmooth2(targetCounts, opts.smoothSigmaDeg ./ opts.binSizeDeg);
gazeDensity = localNormalizeDensity(smoothCounts, opts.normalize, opts.binSizeDeg);
targetDensity = localNormalizeDensity(smoothTargetCounts, opts.normalize, opts.binSizeDeg);
[density, colorbarLabel] = localTargetNormalizedMap( ...
    gazeDensity, targetDensity, opts.targetNormalize, opts.targetPseudocount);
[plotColormap, plotColorLimits, colorSchemeUsed] = localResolveColorDisplay(density, opts);

xCenters = localBinCenters(xEdges);
yCenters = localBinCenters(yEdges);

if opts.plot
    if opts.newFigure
        figure;
    end
    imagesc(xCenters, yCenters, density');
    set(gca, 'YDir', 'normal');
    axis image;
    colormap(plotColormap);
    if ~isempty(plotColorLimits)
        caxis(plotColorLimits);
    end
    cb = colorbar;
    ylabel(cb, colorbarLabel);
    xlabel('x position (deg)');
    if opts.flipY
        ylabel('y position (deg, up positive)');
    else
        ylabel('y position (deg, screen down positive)');
    end
    title(sprintf('Gaze heat: %s, n=%d gaze samples, %d trials', ...
        char(string(opts.targetNormalize)), numel(xDeg), numel(trialList)));
    if (opts.showTextureBox && ~isempty(textureBoundsPx)) || opts.showRewardPeak || opts.showRewardPeakCircle
        hold on;
    end
    if opts.showTextureBox && ~isempty(textureBoundsPx)
        textureBoundsDeg = localBoundsDeg(textureBoundsPx, x0, y0, ex.setup, opts.flipY);
        localDrawBounds(textureBoundsDeg, [1 1 1] .* 0.95);
    end
    if opts.showRewardPeakCircle
        localDrawRewardPeakCircle(rewardPeakCircleDeg, opts, boundsDeg);
    end
    if opts.showRewardPeak
        localDrawRewardPeak(rewardPeakDeg, opts);
    end
    if (opts.showTextureBox && ~isempty(textureBoundsPx)) || opts.showRewardPeak || opts.showRewardPeakCircle
        hold off;
    end
end

out = struct();
out.xDeg = xDeg;
out.yDeg = yDeg;
out.targetXDeg = targetXDeg;
out.targetYDeg = targetYDeg;
out.target1XDeg = target1XDeg;
out.target1YDeg = target1YDeg;
out.target2XDeg = target2XDeg;
out.target2YDeg = target2YDeg;
out.xEdgesDeg = xEdges;
out.yEdgesDeg = yEdges;
out.xCentersDeg = xCenters;
out.yCentersDeg = yCenters;
out.counts = counts;
out.targetCounts = targetCounts;
out.smoothCounts = smoothCounts;
out.smoothTargetCounts = smoothTargetCounts;
out.gazeDensity = gazeDensity;
out.targetDensity = targetDensity;
out.density = density;
out.colorbarLabel = colorbarLabel;
out.colorScheme = colorSchemeUsed;
out.colormap = plotColormap;
out.colorLimits = plotColorLimits;
out.trials = trialList;
out.trialSummary = table(trialList(:), nValid, nUsed, nTargetUsed, ...
    'VariableNames', {'trial','nValidSamples','nUsedSamples','nTargetSamples'});
out.opts = opts;
out.boundsDeg = boundsDeg;
out.rewardPeakPx = rewardPeakPx;
out.rewardPeakDeg = rewardPeakDeg;
out.rewardPeakPxByTrial = rewardPeakPxByTrial;
out.rewardPeakRadiusPxByTrial = rewardPeakRadiusPxByTrial;
out.rewardPeakCirclePx = rewardPeakCirclePx;
out.rewardPeakCircleDeg = rewardPeakCircleDeg;
out.rewardPeakCircleBound = opts.circleBound;
end

function opts = localDefaults(opts)
defaults = struct( ...
    'useEyeTime', true, ...
    'onlyGoState', true, ...
    'insideTextureOnly', true, ...
    'timeWindowSec', [], ...
    'binSizeDeg', 0.25, ...
    'smoothSigmaDeg', 0.5, ...
    'normalize', 'pdf', ...
    'targetNormalize', 'logRatio', ...
    'targetDensityTarget', 'all', ...
    'targetDensityRequiresGazeOnScreen', true, ...
    'targetPseudocount', 1e-6, ...
    'flipY', true, ...
    'plot', true, ...
    'newFigure', true, ...
    'showTextureBox', true, ...
    'showRewardPeak', true, ...
    'rewardPeakMarker', '+', ...
    'rewardPeakColor', [0 0 0], ...
    'rewardPeakMarkerSize', 10, ...
    'rewardPeakLineWidth', 2.25, ...
    'showRewardPeakCircle', true, ...
    'rewardPeakCircleColor', [0 0 0], ...
    'rewardPeakCircleLineStyle', ':', ...
    'rewardPeakCircleLineWidth', 1.5, ...
    'circleBound', '1sd', ...
    'rewardPeakMinMultiplier', 1.1, ...
    'rewardPeakSigmaRadius', 3, ...
    'colorScheme', 'balance', ...
    'colormap', [], ...
    'nColors', 256, ...
    'colorLimits', [], ...
    'colorLimitMode', 'auto', ...
    'colorLimitPrctile', 99);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(opts, names{i}) || isempty(opts.(names{i}))
        opts.(names{i}) = defaults.(names{i});
    end
end
opts.binSizeDeg = double(localFirstScalar(opts.binSizeDeg));
opts.smoothSigmaDeg = double(localFirstScalar(opts.smoothSigmaDeg));
if ~isfinite(opts.binSizeDeg) || opts.binSizeDeg <= 0
    error('gazeHeat:BadBinSize', 'opts.binSizeDeg must be positive.');
end
if ~isfinite(opts.smoothSigmaDeg) || opts.smoothSigmaDeg < 0
    error('gazeHeat:BadSmoothSigma', 'opts.smoothSigmaDeg must be non-negative.');
end
opts.normalize = char(string(opts.normalize));
opts.targetNormalize = validatestring(char(string(opts.targetNormalize)), ...
    {'none', 'ratio', 'logRatio', 'difference'});
if strcmp(opts.targetNormalize, 'logRatio')
    opts.targetNormalize = 'logRatio';
end
opts.targetDensityTarget = validatestring(char(string(opts.targetDensityTarget)), ...
    {'all', 'target1', 'target2', 'closest'});
opts.targetPseudocount = double(localFirstScalar(opts.targetPseudocount));
if ~isfinite(opts.targetPseudocount) || opts.targetPseudocount < 0
    error('gazeHeat:BadPseudocount', 'opts.targetPseudocount must be non-negative.');
end
opts.circleBound = localResolveCircleBound(opts.circleBound);
opts.rewardPeakMinMultiplier = double(localFirstScalar(opts.rewardPeakMinMultiplier));
if ~isfinite(opts.rewardPeakMinMultiplier) || opts.rewardPeakMinMultiplier <= 1
    error('gazeHeat:BadRewardPeakMinMultiplier', 'opts.rewardPeakMinMultiplier must be > 1.');
end
opts.rewardPeakSigmaRadius = double(localFirstScalar(opts.rewardPeakSigmaRadius));
if ~isfinite(opts.rewardPeakSigmaRadius) || opts.rewardPeakSigmaRadius <= 0
    error('gazeHeat:BadRewardPeakSigmaRadius', 'opts.rewardPeakSigmaRadius must be positive.');
end
opts.nColors = max(2, round(double(localFirstScalar(opts.nColors))));
opts.colorScheme = char(string(opts.colorScheme));
opts.colorLimitMode = validatestring(char(string(opts.colorLimitMode)), ...
    {'auto', 'none', 'symmetric', 'symmetricPrctile', 'prctile'});
opts.colorLimitPrctile = double(localFirstScalar(opts.colorLimitPrctile));
if ~isfinite(opts.colorLimitPrctile) || opts.colorLimitPrctile <= 0 || opts.colorLimitPrctile > 100
    error('gazeHeat:BadColorLimitPrctile', 'opts.colorLimitPrctile must be in (0, 100].');
end
end

function trialList = localResolveTrialList(ex, trialNo)
nTrials = numel(ex.Trials);
if isempty(trialNo) || (ischar(trialNo) && strcmpi(trialNo, 'all')) || ...
        (isstring(trialNo) && isscalar(trialNo) && strcmpi(trialNo, "all"))
    trialList = 1:nTrials;
    return
end
if islogical(trialNo)
    if numel(trialNo) ~= nTrials
        error('gazeHeat:BadTrialMask', 'Logical trialNo must match numel(ex.Trials).');
    end
    trialList = find(trialNo(:))';
    return
end
trialList = unique(double(trialNo(:)'));
trialList = trialList(isfinite(trialList) & trialList == round(trialList));
trialList = trialList(trialList >= 1 & trialList <= nTrials);
if isempty(trialList)
    error('gazeHeat:NoTrialsSelected', 'No valid trials selected.');
end
end

function keep = localGoMask(T, tAbs)
keep = true(size(tAbs(:)));
if isfield(T, 'times') && isfield(T.times, 'stimOn') && isfield(T, 'TrialEnd') && ...
        isfinite(T.times.stimOn) && isfinite(T.TrialEnd)
    keep = tAbs(:) >= T.times.stimOn & tAbs(:) <= T.TrialEnd;
end
end

function keep = localOnScreenMask(xPx, yPx, screenRect)
xPx = xPx(:);
yPx = yPx(:);
screenRect = double(screenRect(:)');
if numel(screenRect) < 4
    keep = isfinite(xPx) & isfinite(yPx);
    return
end
keep = isfinite(xPx) & isfinite(yPx) & ...
    xPx >= screenRect(1) & xPx <= screenRect(3) & ...
    yPx >= screenRect(2) & yPx <= screenRect(4);
end

function [plotBounds, textureBounds] = localPlotBoundsPx(ex, opts)
screenRect = double(ex.setup.screenRect);
plotBounds = struct('xMin', screenRect(1), 'xMax', screenRect(3), ...
    'yMin', screenRect(2), 'yMax', screenRect(4));
textureBounds = plotBounds;
if isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'graph')
    graph = ex.exp.CoPs.graph;
    if isfield(graph, 'texture_dims') && isfield(graph, 'size_mult') && ...
            ~isempty(graph.texture_dims) && ~isempty(graph.size_mult)
        texDimPx = double(graph.texture_dims(1)) * double(graph.size_mult);
        xShift = (screenRect(3) - texDimPx) / 2;
        yShift = (screenRect(4) - texDimPx) / 2;
        textureBounds = struct('xMin', xShift, 'xMax', xShift + texDimPx, ...
            'yMin', yShift, 'yMax', yShift + texDimPx);
    end
end
if opts.insideTextureOnly
    plotBounds = textureBounds;
end
end

function [x0, y0] = localReferenceCenterPx(ex)
if isfield(ex, 'fix') && isfield(ex.fix, 'PCtr') && numel(ex.fix.PCtr) >= 2 && all(isfinite(ex.fix.PCtr(1:2)))
    x0 = double(ex.fix.PCtr(1));
    y0 = double(ex.fix.PCtr(2));
    return
end
rect = double(ex.setup.screenRect);
x0 = mean(rect([1 3]));
y0 = mean(rect([2 4]));
end

function boundsDeg = localBoundsDeg(boundsPx, x0, y0, setup, flipY)
yMin = px2deg(boundsPx.yMin - y0, setup);
yMax = px2deg(boundsPx.yMax - y0, setup);
if flipY
    yVals = sort([-yMin, -yMax]);
else
    yVals = sort([yMin, yMax]);
end
boundsDeg = struct( ...
    'xMin', px2deg(boundsPx.xMin - x0, setup), ...
    'xMax', px2deg(boundsPx.xMax - x0, setup), ...
    'yMin', yVals(1), ...
    'yMax', yVals(2));
end

function edges = localEdges(a, b, binSize)
edges = a:binSize:b;
if numel(edges) < 2 || edges(end) < b
    edges(end+1) = b;
end
end

function centers = localBinCenters(edges)
centers = edges(1:end-1) + diff(edges) ./ 2;
end

function y = localSmooth2(x, sigmaBins)
if sigmaBins <= 0
    y = x;
    return
end
halfWidth = max(1, ceil(3 * sigmaBins));
g = -halfWidth:halfWidth;
k = exp(-(g .^ 2) ./ (2 * sigmaBins .^ 2));
k = k ./ sum(k);
y = conv2(conv2(double(x), k, 'same'), k', 'same');
end

function density = localNormalizeDensity(counts, mode, binSizeDeg)
mode = lower(strtrim(mode));
finiteCounts = counts(isfinite(counts));
total = sum(finiteCounts(:));
switch mode
    case {'count', 'counts'}
        density = counts;
    case {'probability', 'prob'}
        density = counts ./ max(total, eps);
    case {'pdf', 'density', 'probabilitydensity'}
        density = counts ./ max(total .* binSizeDeg .* binSizeDeg, eps);
    case {'peak', 'max'}
        density = counts ./ max(max(counts(:)), eps);
    otherwise
        error('gazeHeat:BadNormalize', ...
            'opts.normalize must be count, probability, pdf, or peak.');
end
end

function [targetX, targetY] = localSelectTargetSamples(target1X, target1Y, target2X, target2Y, gazeX, gazeY, mode)
target1X = target1X(:); target1Y = target1Y(:);
target2X = target2X(:); target2Y = target2Y(:);
gazeX = gazeX(:); gazeY = gazeY(:);
mode = lower(strtrim(mode));

switch mode
    case 'target1'
        targetX = target1X;
        targetY = target1Y;
    case 'target2'
        targetX = target2X;
        targetY = target2Y;
    case 'closest'
        d1 = hypot(gazeX - target1X, gazeY - target1Y);
        d2 = hypot(gazeX - target2X, gazeY - target2Y);
        use2 = isfinite(d2) & (~isfinite(d1) | d2 < d1);
        targetX = target1X;
        targetY = target1Y;
        targetX(use2) = target2X(use2);
        targetY(use2) = target2Y(use2);
    otherwise
        targetX = [target1X; target2X];
        targetY = [target1Y; target2Y];
end

keep = isfinite(targetX) & isfinite(targetY);
targetX = targetX(keep);
targetY = targetY(keep);
end

function counts = localHistcounts2(x, y, xEdges, yEdges)
x = x(:);
y = y(:);
keep = isfinite(x) & isfinite(y);
x = x(keep);
y = y(keep);

counts = zeros(numel(xEdges) - 1, numel(yEdges) - 1);
if isempty(x)
    return
end

if exist('histcounts2', 'file') == 2 || exist('histcounts2', 'builtin') == 5
    counts = histcounts2(x, y, xEdges, yEdges);
    return
end

[~, ~, xBin] = histcounts(x, xEdges);
[~, ~, yBin] = histcounts(y, yEdges);
valid = xBin > 0 & yBin > 0;
for i = find(valid(:))'
    counts(xBin(i), yBin(i)) = counts(xBin(i), yBin(i)) + 1;
end
end

function [map, label] = localTargetNormalizedMap(gazeDensity, targetDensity, mode, pseudocount)
mode = lower(strtrim(mode));
switch mode
    case 'none'
        map = gazeDensity;
        label = 'gaze density';
    case 'ratio'
        map = (gazeDensity + pseudocount) ./ (targetDensity + pseudocount);
        label = 'gaze / target density';
    case 'logratio'
        map = log2((gazeDensity + pseudocount) ./ (targetDensity + pseudocount));
        label = 'log2(gaze / target density)';
    case 'difference'
        map = gazeDensity - targetDensity;
        label = 'gaze density - target density';
    otherwise
        error('gazeHeat:BadTargetNormalize', ...
            'opts.targetNormalize must be none, ratio, logRatio, or difference.');
end
end

function [cmap, colorLimits, schemeUsed] = localResolveColorDisplay(map, opts)
schemeUsed = lower(strtrim(char(string(opts.colorScheme))));
if strcmp(schemeUsed, 'auto')
    switch lower(strtrim(char(string(opts.targetNormalize))))
        case {'logratio', 'difference'}
            schemeUsed = 'balance';
        otherwise
            schemeUsed = 'hot';
    end
end

if ~isempty(opts.colormap)
    cmap = localColormapFromValue(opts.colormap, opts.nColors);
    if isnumeric(opts.colormap)
        schemeUsed = 'custom';
    else
        schemeUsed = lower(strtrim(char(string(opts.colormap))));
    end
else
    cmap = localColormapByName(schemeUsed, opts.nColors);
end
colorLimits = localResolveColorLimits(map, opts);
end

function cmap = localColormapFromValue(value, nColors)
if isnumeric(value)
    cmap = double(value);
    if size(cmap, 2) ~= 3 || isempty(cmap)
        error('gazeHeat:BadColormap', 'opts.colormap must be an n x 3 RGB array or a colormap name.');
    end
    cmap = max(0, min(1, cmap));
    return
end
scheme = lower(strtrim(char(string(value))));
cmap = localColormapByName(scheme, nColors);
end

function cmap = localColormapByName(scheme, nColors)
scheme = lower(strtrim(char(string(scheme))));
switch scheme
    case {'balance', 'balanced', 'diverging', 'bluered', 'bluewhiteRed', 'bluewhitered'}
        cmap = localInterpolatedColormap([ ...
            0.08 0.19 0.55; ...
            0.26 0.57 0.78; ...
            0.96 0.96 0.96; ...
            0.88 0.42 0.31; ...
            0.55 0.08 0.11], nColors);
    case {'redblue', 'redwhiteblue'}
        cmap = flipud(localColormapByName('balance', nColors));
    case {'density', 'fire'}
        cmap = localInterpolatedColormap([ ...
            0.00 0.00 0.00; ...
            0.15 0.05 0.35; ...
            0.70 0.10 0.20; ...
            0.95 0.58 0.10; ...
            1.00 0.96 0.72], nColors);
    case 'viridis'
        cmap = localInterpolatedColormap([ ...
            0.27 0.00 0.33; ...
            0.23 0.32 0.55; ...
            0.13 0.57 0.55; ...
            0.37 0.79 0.38; ...
            0.99 0.91 0.14], nColors);
    case 'magma'
        cmap = localInterpolatedColormap([ ...
            0.00 0.00 0.02; ...
            0.19 0.07 0.35; ...
            0.55 0.16 0.51; ...
            0.91 0.36 0.28; ...
            0.99 0.99 0.75], nColors);
    case {'hot', 'parula', 'turbo', 'jet', 'gray', 'grey', 'bone', 'copper'}
        if strcmp(scheme, 'grey')
            scheme = 'gray';
        end
        cmap = localBuiltinColormap(scheme, nColors);
    otherwise
        error('gazeHeat:BadColorScheme', ...
            ['Unknown opts.colorScheme ''%s''. Use auto, balance, redBlue, hot, parula, turbo, ', ...
            'viridis, magma, density, gray, jet, bone, copper, or pass opts.colormap.'], scheme);
end
end

function cmap = localBuiltinColormap(name, nColors)
try
    cmap = feval(name, nColors);
catch
    switch lower(name)
        case 'turbo'
            cmap = localBuiltinColormap('parula', nColors);
        case 'parula'
            cmap = localBuiltinColormap('jet', nColors);
        otherwise
            cmap = hot(nColors);
    end
end
cmap = max(0, min(1, double(cmap)));
end

function cmap = localInterpolatedColormap(anchors, nColors)
anchors = double(anchors);
x = linspace(0, 1, size(anchors, 1));
xi = linspace(0, 1, nColors);
cmap = zeros(nColors, 3);
for k = 1:3
    cmap(:, k) = interp1(x, anchors(:, k), xi, 'linear');
end
cmap = max(0, min(1, cmap));
end

function colorLimits = localResolveColorLimits(map, opts)
if ~isempty(opts.colorLimits)
    colorLimits = double(opts.colorLimits(:)');
    colorLimits = colorLimits(isfinite(colorLimits));
    if numel(colorLimits) >= 2
        colorLimits = [min(colorLimits(1:2)), max(colorLimits(1:2))];
        if colorLimits(2) > colorLimits(1)
            return
        end
    end
    error('gazeHeat:BadColorLimits', 'opts.colorLimits must contain two increasing finite values.');
end

mode = lower(strtrim(char(string(opts.colorLimitMode))));
if strcmp(mode, 'auto')
    switch lower(strtrim(char(string(opts.targetNormalize))))
        case {'logratio', 'difference'}
            mode = 'symmetricprctile';
        otherwise
            mode = 'none';
    end
end

finiteVals = double(map(isfinite(map)));
if isempty(finiteVals)
    colorLimits = [];
    return
end
switch mode
    case 'none'
        colorLimits = [];
    case 'symmetric'
        lim = max(abs(finiteVals));
        colorLimits = localSymmetricLimits(lim);
    case 'symmetricprctile'
        lim = prctile(abs(finiteVals), opts.colorLimitPrctile);
        colorLimits = localSymmetricLimits(lim);
    case 'prctile'
        tail = (100 - opts.colorLimitPrctile) / 2;
        colorLimits = prctile(finiteVals, [tail, 100 - tail]);
        if colorLimits(2) <= colorLimits(1)
            colorLimits = [];
        end
    otherwise
        colorLimits = [];
end
end

function limits = localSymmetricLimits(lim)
if ~isfinite(lim) || lim <= 0
    limits = [];
else
    limits = [-lim, lim];
end
end

function localDrawBounds(bounds, color)
x = [bounds.xMin bounds.xMax bounds.xMax bounds.xMin bounds.xMin];
y = [bounds.yMin bounds.yMin bounds.yMax bounds.yMax bounds.yMin];
plot(x, y, '-', 'Color', color, 'LineWidth', 1.25);
end

function localDrawRewardPeak(rewardPeakDeg, opts)
if isempty(rewardPeakDeg)
    return
end
keep = all(isfinite(rewardPeakDeg), 2);
if ~any(keep)
    return
end
plot(rewardPeakDeg(keep, 1), rewardPeakDeg(keep, 2), ...
    char(string(opts.rewardPeakMarker)), ...
    'Color', opts.rewardPeakColor, ...
    'MarkerSize', opts.rewardPeakMarkerSize, ...
    'LineWidth', opts.rewardPeakLineWidth);
end

function localDrawRewardPeakCircle(rewardPeakCircleDeg, opts, boundsDeg)
if isempty(rewardPeakCircleDeg)
    return
end
keep = all(isfinite(rewardPeakCircleDeg), 2) & rewardPeakCircleDeg(:, 3) > 0;
if ~any(keep)
    return
end
theta = linspace(0, 2*pi, 241);
for i = find(keep(:))'
    x = rewardPeakCircleDeg(i, 1) + rewardPeakCircleDeg(i, 3) .* cos(theta);
    y = rewardPeakCircleDeg(i, 2) + rewardPeakCircleDeg(i, 3) .* sin(theta);
    if nargin >= 3 && isstruct(boundsDeg)
        inBounds = x >= boundsDeg.xMin & x <= boundsDeg.xMax & ...
            y >= boundsDeg.yMin & y <= boundsDeg.yMax;
        if ~any(inBounds)
            continue
        end
        x(~inBounds) = NaN;
        y(~inBounds) = NaN;
    end
    plot(x, y, ...
        'LineStyle', char(string(opts.rewardPeakCircleLineStyle)), ...
        'Color', opts.rewardPeakCircleColor, ...
        'LineWidth', opts.rewardPeakCircleLineWidth);
end
end

function rewardPeakPx = localRewardPeakPxByTrial(ex, trialList)
rewardPeakPx = NaN(numel(trialList), 2);
for i = 1:numel(trialList)
    trialIdx = trialList(i);
    if trialIdx < 1 || trialIdx > numel(ex.Trials)
        continue
    end
    T = ex.Trials(trialIdx);
    try
        if exist('getGaussianCenterPx', 'file') == 2
            ctr = getGaussianCenterPx(ex, T);
        else
            ctr = localGaussianCenterPxFallback(ex, T);
        end
    catch
        ctr = localGaussianCenterPxFallback(ex, T);
    end
    if numel(ctr) >= 2 && all(isfinite(ctr(1:2)))
        rewardPeakPx(i, :) = double(ctr(1:2));
    end
end
end

function radiiPx = localRewardPeakRadiusPxByTrial(ex, trialList, opts)
nRadii = localCircleBoundCount(opts.circleBound);
radiiPx = NaN(numel(trialList), nRadii);
for i = 1:numel(trialList)
    trialIdx = trialList(i);
    if trialIdx < 1 || trialIdx > numel(ex.Trials)
        continue
    end
    radii = localRewardPeakRadiiPx(ex, ex.Trials(trialIdx), opts);
    radiiPx(i, 1:min(numel(radii), nRadii)) = radii(1:min(numel(radii), nRadii));
end
end

function radiiPx = localRewardPeakRadiiPx(ex, T, opts)
radiiPx = NaN(1, localCircleBoundCount(opts.circleBound));
sigmaPx = localRewardSigmaPx(ex, T);
if ~isfinite(sigmaPx) || sigmaPx <= 0
    return
end

switch opts.circleBound
    case 'mult'
        gaussScalar = localGaussScalar(ex, T);
        minMultiplier = double(opts.rewardPeakMinMultiplier);
        sigmaRadius = double(opts.rewardPeakSigmaRadius);
        if ~isfinite(gaussScalar) || gaussScalar <= minMultiplier
            return
        end
        % Online multiplier is 1 + (gaussScalar - 1) * Gaussian(r). This
        % boundary is where that multiplier first falls to minMultiplier.
        requiredRewardFrac = (minMultiplier - 1) ./ (gaussScalar - 1);
        requiredRewardFrac = max(realmin, min(1, requiredRewardFrac));
        multRadiusPx = sigmaPx .* sqrt(-2 .* log(requiredRewardFrac));
        radiiPx = min(sigmaRadius .* sigmaPx, multRadiusPx);
    case '1sd'
        radiiPx = sigmaPx;
    case '2sd'
        radiiPx = sigmaPx .* [1, 2];
    case '3sd'
        radiiPx = sigmaPx .* [1, 2, 3];
end
end

function circleRowsPx = localRewardPeakCircleRowsPx(rewardPeakPxByTrial, rewardPeakRadiusPxByTrial)
circleRowsPx = NaN(0, 3);
if isempty(rewardPeakPxByTrial) || isempty(rewardPeakRadiusPxByTrial)
    return
end
nTrial = min(size(rewardPeakPxByTrial, 1), size(rewardPeakRadiusPxByTrial, 1));
for i = 1:nTrial
    ctr = rewardPeakPxByTrial(i, :);
    if numel(ctr) < 2 || any(~isfinite(ctr(1:2)))
        continue
    end
    radii = double(rewardPeakRadiusPxByTrial(i, :));
    radii = radii(isfinite(radii) & radii > 0);
    if isempty(radii)
        continue
    end
    circleRowsPx = [circleRowsPx; repmat(ctr(1:2), numel(radii), 1), radii(:)]; %#ok<AGROW>
end
end

function n = localCircleBoundCount(circleBound)
switch localResolveCircleBound(circleBound)
    case {'mult', '1sd'}
        n = 1;
    case '2sd'
        n = 2;
    case '3sd'
        n = 3;
    otherwise
        n = 1;
end
end

function circleBound = localResolveCircleBound(value)
if isempty(value)
    circleBound = '2sd';
    return
end
circleBound = lower(strtrim(char(string(value))));
switch circleBound
    case {'mult', 'multiplier', 'reward', 'rewardmult', 'rewardmultiplier'}
        circleBound = 'mult';
    case {'1sd', '1s', 'sd1', 'sigma1', '1sigma'}
        circleBound = '1sd';
    case {'2sd', '2s', 'sd2', 'sigma2', '2sigma'}
        circleBound = '2sd';
    case {'3sd', '3s', 'sd3', 'sigma3', '3sigma'}
        circleBound = '3sd';
    otherwise
        error('gazeHeat:BadCircleBound', ...
            'opts.circleBound must be ''mult'', ''1sd'', ''2sd'', or ''3sd''.');
end
end

function sigmaPx = localRewardSigmaPx(ex, T)
sigmaPx = NaN;
if nargin > 1 && isstruct(T)
    if isfield(T, 'gaussSigmaPx') && isfinite(localFirstScalar(T.gaussSigmaPx))
        sigmaPx = double(localFirstScalar(T.gaussSigmaPx));
        return
    end
    if isfield(T, 'gauss_sigma') && isfinite(localFirstScalar(T.gauss_sigma))
        sigmaVal = double(localFirstScalar(T.gauss_sigma));
        units = localTextField(T, {'gaussSigmaUnits', 'gauss_sigmaUnits'}, 'px');
        if ismember(lower(strtrim(units)), {'deg', 'degree', 'degrees'})
            sigmaPx = visualDegToPx(sigmaVal, ex.setup);
        else
            sigmaPx = sigmaVal;
        end
        return
    end
    if isfield(T, 'gaussSigmaDeg') && isfinite(localFirstScalar(T.gaussSigmaDeg))
        sigmaPx = visualDegToPx(double(localFirstScalar(T.gaussSigmaDeg)), ex.setup);
        return
    end
end
if ~isfield(ex, 'exp') || ~isfield(ex.exp, 'CoPs') || ~isfield(ex.exp.CoPs, 'rew')
    return
end
rew = ex.exp.CoPs.rew;
if isfield(rew, 'gauss_sigmaPx') && isfinite(localFirstScalar(rew.gauss_sigmaPx))
    sigmaPx = double(localFirstScalar(rew.gauss_sigmaPx));
    return
end
if isfield(rew, 'gauss_sigma') && isfinite(localFirstScalar(rew.gauss_sigma))
    sigmaVal = double(localFirstScalar(rew.gauss_sigma));
    units = localTextField(rew, {'gauss_sigmaUnits'}, 'px');
    if ismember(lower(strtrim(units)), {'deg', 'degree', 'degrees'})
        sigmaPx = visualDegToPx(sigmaVal, ex.setup);
    else
        sigmaPx = sigmaVal;
    end
    return
end
if isfield(rew, 'gauss_sigmaDeg') && isfinite(localFirstScalar(rew.gauss_sigmaDeg))
    sigmaPx = visualDegToPx(double(localFirstScalar(rew.gauss_sigmaDeg)), ex.setup);
end
end

function gaussScalar = localGaussScalar(ex, T)
gaussScalar = NaN;
if nargin > 1 && isstruct(T) && isfield(T, 'gauss_scalar') && isfinite(localFirstScalar(T.gauss_scalar))
    gaussScalar = double(localFirstScalar(T.gauss_scalar));
    return
end
if isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'ctl') && ...
        isfield(ex.exp.CoPs.ctl, 'gauss_scalar') && isfinite(localFirstScalar(ex.exp.CoPs.ctl.gauss_scalar))
    gaussScalar = double(localFirstScalar(ex.exp.CoPs.ctl.gauss_scalar));
end
end

function ctr = localGaussianCenterPxFallback(ex, T)
ctr = [NaN NaN];
if ~isfield(ex, 'exp') || ~isfield(ex.exp, 'CoPs') || ...
        ~isfield(ex.exp.CoPs, 'graph') || ~isfield(ex.exp.CoPs, 'rew') || ...
        ~isfield(ex, 'setup') || ~isfield(ex.setup, 'screenRect')
    return
end
graph = ex.exp.CoPs.graph;
rew = ex.exp.CoPs.rew;
if ~isfield(graph, 'texture_dims') || ~isfield(graph, 'size_mult') || ...
        isempty(graph.texture_dims) || isempty(graph.size_mult)
    return
end
gaussDim = double(graph.texture_dims(1)) * double(graph.size_mult);
screenRect = double(ex.setup.screenRect(:)');
if numel(screenRect) < 4 || ~isfinite(gaussDim) || gaussDim <= 0
    return
end
xshift = (screenRect(3) - gaussDim) / 2;
yshift = (screenRect(4) - gaussDim) / 2;

ctrNorm = [0.5, 0.5];
if nargin > 1 && isstruct(T) && isfield(T, 'gaussRewardCenterNorm') && ...
        numel(T.gaussRewardCenterNorm) >= 2 && all(isfinite(T.gaussRewardCenterNorm(1:2)))
    ctrNorm = double(T.gaussRewardCenterNorm(1:2));
elseif isfield(rew, 'gauss_center_positions_norm') && ~isempty(rew.gauss_center_positions_norm)
    centers = double(rew.gauss_center_positions_norm);
    idx = 1;
    if isfield(rew, 'gauss_center_idx') && isfinite(rew.gauss_center_idx)
        idx = max(1, min(size(centers, 1), round(double(rew.gauss_center_idx))));
    end
    ctrNorm = centers(idx, 1:2);
end

centerInMapPx = round(ctrNorm .* (gaussDim - 1)) + 1;
centerInMapPx = max(1, min(gaussDim, centerInMapPx));
ctr = [xshift + centerInMapPx(1), yshift + centerInMapPx(2)];
end

function circleDeg = localRewardPeakCircleDeg(circlePx, x0, y0, setup, flipY)
circleDeg = NaN(size(circlePx));
if isempty(circlePx)
    return
end
circleDeg(:, 1:2) = localPxToPlotDeg(circlePx(:, 1:2), x0, y0, setup, flipY);
circleDeg(:, 3) = px2deg(double(circlePx(:, 3)), setup);
end

function xyDeg = localPxToPlotDeg(xyPx, x0, y0, setup, flipY)
xyDeg = NaN(size(xyPx));
if isempty(xyPx)
    return
end
xyDeg(:, 1) = px2deg(double(xyPx(:, 1)) - x0, setup);
xyDeg(:, 2) = px2deg(double(xyPx(:, 2)) - y0, setup);
if flipY
    xyDeg(:, 2) = -xyDeg(:, 2);
end
end

function rows = localUniqueRowsTol(rows, tol)
if isempty(rows)
    return
end
rows = double(rows);
rows = rows(all(isfinite(rows), 2), :);
if isempty(rows)
    return
end
if nargin < 2 || isempty(tol) || ~isfinite(tol) || tol <= 0
    tol = 0;
end
if tol > 0
    roundedRows = round(rows ./ tol) .* tol;
else
    roundedRows = rows;
end
[~, ia] = unique(roundedRows, 'rows', 'stable');
rows = rows(sort(ia), :);
end

function value = localTextField(s, fieldNames, defaultValue)
value = defaultValue;
if ~isstruct(s)
    return
end
for i = 1:numel(fieldNames)
    fieldName = fieldNames{i};
    if isfield(s, fieldName) && ~isempty(s.(fieldName))
        value = char(string(s.(fieldName)));
        return
    end
end
end

function x = localFirstScalar(x)
if isempty(x)
    x = NaN;
else
    x = x(1);
end
end
