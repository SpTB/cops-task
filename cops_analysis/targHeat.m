function out = targHeat(ex, trialNo, opts)
% targHeat  Plot target-location probability for the CoPs task.
%
%   targHeat(ex)
%   targHeat(ex, 1:120)
%   out = targHeat(ex, [], opts)
%
% By default, targHeat(ex) plots the theoretical target occupancy implied by
% the current CoPs movement settings. It accounts for randomized starts by
% Monte Carlo sampling a uniform start angle at the configured start radius.
%
% Passing trial numbers switches to realized target occupancy from saved
% trial target positions, similar to gazeHeat:
%   targHeat(ex, 1:(ex.j-1))
%
% Useful options:
%   opts.source = 'theoretical' (default without trialNo) or 'trials'
%   opts.nSimTrials = 2000
%   opts.rngSeed = 1
%   opts.normalize = 'probability' (default), 'pdf', 'count', or 'peak'
%   opts.target = 'all' (default), 'target1', or 'target2'
%   opts.showRewardPeak = true
%   opts.rewardPeakNorm = []   % explicit [x y] in normalized texture coords [0,1]
%   opts.rewardPeakDeg = []    % explicit [x y] in plotted visual degrees
%   opts.rewardPeakPx = []     % explicit [x y] in screen pixels
%   opts.queryDeg = []         % return probability at [x y] plot coords
%   opts.queryNorm = []        % return probability at [x y] texture coords [0,1]
%   opts.queryTargetNorm = []  % return probability at target coords [-1,1]
%   opts.queryPx = []          % return probability at [x y] screen pixels
%   opts.queryCircleRadiusDeg = [] % default: reward Gaussian 1 SD
%   opts.showQueryCircle = true
%
% Query rows include point-bin probability and circleProbability, the summed
% smoothed probability inside queryCircleRadiusDeg. With the current
% setDefaultsCoPs.m reward settings, 1 SD is 3.5 visual degrees.
%
% Examples:
%   out = targHeat(ex, [], struct('queryDeg', [0 0], 'plot', false));
%   out = targHeat(ex, [], struct('queryNorm', [0.2685 0.2952]));

if nargin < 2
    trialNo = [];
end
trialNoProvided = nargin >= 2 && ~isempty(trialNo) && ~isstruct(trialNo);
if nargin < 3 || isempty(opts)
    if isstruct(trialNo)
        opts = trialNo;
        trialNo = [];
        trialNoProvided = false;
    else
        opts = struct();
    end
elseif ~isstruct(opts)
    error('targHeat:BadOpts', 'opts must be a struct.');
end

opts = localDefaults(opts, trialNoProvided);
localRequireCoPsEx(ex);
opts = localResolveQueryDefaults(ex, opts);

[x0, y0] = localReferenceCenterPx(ex);
[plotBoundsPx, textureBoundsPx, geom] = localPlotGeometryPx(ex, opts);
boundsDeg = localBoundsDeg(plotBoundsPx, x0, y0, ex.setup, opts.flipY);
xEdges = localEdges(boundsDeg.xMin, boundsDeg.xMax, opts.binSizeDeg);
yEdges = localEdges(boundsDeg.yMin, boundsDeg.yMax, opts.binSizeDeg);

switch lower(opts.source)
    case 'theoretical'
        [targetXPx, targetYPx, meta] = localTheoreticalTargetsPx(ex, opts, geom);
    case {'trials', 'realized', 'empirical'}
        trialList = localResolveTrialList(ex, trialNo);
        [targetXPx, targetYPx, meta] = localRealizedTargetsPx(ex, trialList, opts, geom);
    otherwise
        error('targHeat:BadSource', 'opts.source must be ''theoretical'' or ''trials''.');
end

keep = isfinite(targetXPx) & isfinite(targetYPx);
if opts.insideTextureOnly
    keep = keep & targetXPx >= textureBoundsPx.xMin & targetXPx <= textureBoundsPx.xMax & ...
        targetYPx >= textureBoundsPx.yMin & targetYPx <= textureBoundsPx.yMax;
end
targetXPx = targetXPx(keep);
targetYPx = targetYPx(keep);
if isempty(targetXPx)
    error('targHeat:NoSamples', 'No target samples remained after filtering.');
end

xDeg = localPxToDeg(targetXPx - x0, ex.setup);
yDeg = localPxToDeg(targetYPx - y0, ex.setup);
if opts.flipY
    yDeg = -yDeg;
end

counts = localHistcounts2(xDeg, yDeg, xEdges, yEdges);
probability = localNormalizeDensity(counts, 'probability', opts.binSizeDeg);
smoothProbability = localSmooth2(probability, opts.smoothSigmaDeg ./ opts.binSizeDeg);
smoothProbability = localRenormalizeProbability(smoothProbability);
density = localDisplayMap(counts, probability, smoothProbability, opts.normalize, opts.binSizeDeg);
[plotColormap, plotColorLimits, colorSchemeUsed] = localResolveColorDisplay(density, opts);
xCenters = localBinCenters(xEdges);
yCenters = localBinCenters(yEdges);
[rewardPeakPx, rewardPeakDeg] = localRewardPeakForPlot(ex, x0, y0, opts);
query = localQueryProbability(opts, geom, x0, y0, ex.setup, xEdges, yEdges, ...
    probability, smoothProbability, density, counts, opts.queryCircleRadiusDeg);
if opts.printQuery && ~isempty(query)
    disp(query);
end

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
    ylabel(cb, localColorbarLabel(opts.normalize));
    xlabel('x position (deg)');
    if opts.flipY
        ylabel('y position (deg, up positive)');
    else
        ylabel('y position (deg, screen down positive)');
    end
    title(localPlotTitle(opts, meta, numel(targetXPx)), 'Interpreter', 'none');
    if opts.showTextureBox || opts.showRewardPeak || opts.showQueryCircle
        hold on;
    end
    if opts.showTextureBox
        textureBoundsDeg = localBoundsDeg(textureBoundsPx, x0, y0, ex.setup, opts.flipY);
        localDrawBounds(textureBoundsDeg, [1 1 1] .* 0.95);
    end
    if opts.showRewardPeak
        localDrawRewardPeak(rewardPeakDeg, opts);
    end
    if opts.showQueryCircle
        localDrawQueryCircles(query, opts, boundsDeg);
    end
    if opts.showTextureBox || opts.showRewardPeak || opts.showQueryCircle
        hold off;
    end
end

out = struct();
out.source = opts.source;
out.xDeg = xDeg;
out.yDeg = yDeg;
out.xPx = targetXPx;
out.yPx = targetYPx;
out.xEdgesDeg = xEdges;
out.yEdgesDeg = yEdges;
out.xCentersDeg = xCenters;
out.yCentersDeg = yCenters;
out.counts = counts;
out.probability = probability;
out.smoothProbability = smoothProbability;
out.smoothCounts = localSmooth2(counts, opts.smoothSigmaDeg ./ opts.binSizeDeg);
out.density = density;
out.normalize = opts.normalize;
out.colorbarLabel = localColorbarLabel(opts.normalize);
out.colormap = plotColormap;
out.colorLimits = plotColorLimits;
out.colorScheme = colorSchemeUsed;
out.boundsDeg = boundsDeg;
out.rewardPeakPx = rewardPeakPx;
out.rewardPeakDeg = rewardPeakDeg;
out.query = query;
out.queryCircleRadiusDeg = opts.queryCircleRadiusDeg;
out.geometry = geom;
out.meta = meta;
out.opts = opts;
end


function opts = localDefaults(opts, trialNoProvided)
if trialNoProvided
    defaultSource = 'trials';
else
    defaultSource = 'theoretical';
end
defaults = struct( ...
    'source', defaultSource, ...
    'nSimTrials', 2000, ...
    'rngSeed', 1, ...
    'target', 'all', ...
    'targetNum', [], ...
    'stepSizeMult', [], ...
    'randomizeStartPos', [], ...
    'binSizeDeg', 0.25, ...
    'smoothSigmaDeg', 0.5, ...
    'normalize', 'probability', ...
    'insideTextureOnly', true, ...
    'flipY', true, ...
    'plot', true, ...
    'newFigure', true, ...
    'showTextureBox', true, ...
    'showRewardPeak', true, ...
    'rewardPeakNorm', [], ...
    'rewardPeakDeg', [], ...
    'rewardPeakPx', [], ...
    'rewardPeakMarker', '+', ...
    'rewardPeakColor', [0 0 0], ...
    'rewardPeakMarkerSize', 10, ...
    'rewardPeakLineWidth', 2.25, ...
    'queryDeg', [], ...
    'queryNorm', [], ...
    'queryTargetNorm', [], ...
    'queryPx', [], ...
    'queryCircleRadiusDeg', [], ...
    'showQueryCircle', true, ...
    'queryCircleColor', [0 0 0], ...
    'queryCircleLineStyle', ':', ...
    'queryCircleLineWidth', 1.5, ...
    'printQuery', true, ...
    'colorScheme', 'density', ...
    'colormap', [], ...
    'nColors', 256, ...
    'colorLimits', [], ...
    'colorLimitMode', 'none', ...
    'colorLimitPrctile', 99);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(opts, names{i}) || isempty(opts.(names{i}))
        opts.(names{i}) = defaults.(names{i});
    end
end
opts.source = lower(strtrim(char(string(opts.source))));
opts.target = lower(strtrim(char(string(opts.target))));
if ~ismember(opts.target, {'all', 'target1', 'target2'})
    error('targHeat:BadTarget', 'opts.target must be ''all'', ''target1'', or ''target2''.');
end
opts.nSimTrials = max(1, round(double(localFirstScalar(opts.nSimTrials))));
opts.binSizeDeg = double(localFirstScalar(opts.binSizeDeg));
opts.smoothSigmaDeg = double(localFirstScalar(opts.smoothSigmaDeg));
if ~isfinite(opts.binSizeDeg) || opts.binSizeDeg <= 0
    error('targHeat:BadBinSize', 'opts.binSizeDeg must be positive.');
end
if ~isfinite(opts.smoothSigmaDeg) || opts.smoothSigmaDeg < 0
    error('targHeat:BadSmoothSigma', 'opts.smoothSigmaDeg must be non-negative.');
end
opts.normalize = lower(strtrim(char(string(opts.normalize))));
opts.showRewardPeak = logical(localFirstScalar(opts.showRewardPeak));
opts.showQueryCircle = logical(localFirstScalar(opts.showQueryCircle));
opts.printQuery = logical(localFirstScalar(opts.printQuery));
opts.nColors = max(2, round(double(localFirstScalar(opts.nColors))));
opts.colorScheme = char(string(opts.colorScheme));
opts.colorLimitMode = lower(strtrim(char(string(opts.colorLimitMode))));
opts.colorLimitPrctile = double(localFirstScalar(opts.colorLimitPrctile));
if ~isfinite(opts.colorLimitPrctile) || opts.colorLimitPrctile <= 0 || opts.colorLimitPrctile > 100
    error('targHeat:BadColorLimitPrctile', 'opts.colorLimitPrctile must be in (0, 100].');
end
end


function localRequireCoPsEx(ex)
if ~isstruct(ex) || ~isfield(ex, 'exp') || ~isfield(ex.exp, 'CoPs')
    error('targHeat:BadEx', 'Input ex must contain ex.exp.CoPs.');
end
if ~isfield(ex, 'setup') || ~isfield(ex.setup, 'screenRect') || ...
        ~isfield(ex.setup, 'monitorWidth') || ~isfield(ex.setup, 'viewingDistance')
    error('targHeat:MissingSetup', ...
        'ex.setup.screenRect, monitorWidth, and viewingDistance are required.');
end
end


function opts = localResolveQueryDefaults(ex, opts)
if ~isempty(opts.queryNorm) && isempty(opts.rewardPeakNorm) && ...
        isempty(opts.rewardPeakDeg) && isempty(opts.rewardPeakPx)
    opts.rewardPeakNorm = opts.queryNorm;
end
if isempty(opts.queryCircleRadiusDeg)
    opts.queryCircleRadiusDeg = localRewardSigmaDeg(ex);
else
    opts.queryCircleRadiusDeg = double(localFirstScalar(opts.queryCircleRadiusDeg));
end
if ~isfinite(opts.queryCircleRadiusDeg) || opts.queryCircleRadiusDeg <= 0
    opts.queryCircleRadiusDeg = NaN;
end
end


function [targetXPx, targetYPx, meta] = localTheoreticalTargetsPx(ex, opts, geom)
ctl = ex.exp.CoPs.ctl;
pos = ex.exp.CoPs.pos;
graph = geom.graph;

oldRng = rng;
cleanupObj = onCleanup(@() rng(oldRng)); %#ok<NASGU>
if isnumeric(opts.rngSeed) && ~isempty(opts.rngSeed) && isfinite(localFirstScalar(opts.rngSeed))
    rng(round(double(localFirstScalar(opts.rngSeed))));
end

nsteps = max(1, round(localGetScalarField(ctl, 'nsteps', 1)));
stepSizeLevels = localOptionOrField(opts.stepSizeMult, ctl, 'step_size_mult', 1);
targetNumLevels = localOptionOrField(opts.targetNum, ctl, 'target_num', 2);
targetNumLevels = round(double(targetNumLevels(:)'));
targetNumLevels = targetNumLevels(ismember(targetNumLevels, [1, 2]));
if isempty(targetNumLevels)
    targetNumLevels = 2;
end

stepNoiseType = localGetTextField(ctl, 'stepNoiseType', 'uniform');
stepNoiseSigmaBase = localGetScalarField(ctl, 'stepNoiseSigma', 0.07);
stepNoiseCapSigma = localGetScalarField(ctl, 'stepNoiseCapSigma', 3.5);
boundaryMode = localGetTextField(ctl, 'boundaryMode', 'clip');
boundaryRejectMaxAttempts = localGetScalarField(ctl, 'boundaryRejectMaxAttempts', 50);
hiddenFrac = localGetScalarField(ctl, 'targetHiddenBoundsFrac', 0);
positionBound = localTargetPositionBound(graph, hiddenFrac);
randomizeStart = localResolveRandomizeStart(opts, ctl);

maxSamples = opts.nSimTrials * nsteps * 2;
targetXPx = NaN(maxSamples, 1);
targetYPx = NaN(maxSamples, 1);
n = 0;
targetNumDraws = NaN(opts.nSimTrials, 1);
stepSizeDraws = NaN(opts.nSimTrials, 1);

for simIdx = 1:opts.nSimTrials
    targetNum = localSampleLevel(targetNumLevels);
    stepSizeMult = localSampleLevel(stepSizeLevels);
    targetNumDraws(simIdx) = targetNum;
    stepSizeDraws(simIdx) = stepSizeMult;

    simPos = pos;
    if randomizeStart
        startRadius = hypot(localGetScalarField(pos, 'initx1', 0), ...
            localGetScalarField(pos, 'inity1', 0));
        startTheta = rand() * (2 * pi);
        simPos.initx1 = startRadius * cos(startTheta);
        simPos.inity1 = startRadius * sin(startTheta);
        if targetNum == 2
            simPos.initx2 = -simPos.initx1;
            simPos.inity2 = -simPos.inity1;
        end
    end

    stepNoiseSigma = stepSizeMult * stepNoiseSigmaBase;
    dxRange1 = stepSizeMult .* [localGetScalarField(simPos, 'dxmin1', 0), localGetScalarField(simPos, 'dxmax1', 0)];
    dyRange1 = stepSizeMult .* [localGetScalarField(simPos, 'dymin1', 0), localGetScalarField(simPos, 'dymax1', 0)];
    dxRange2 = stepSizeMult .* [localGetScalarField(simPos, 'dxmin2', 0), localGetScalarField(simPos, 'dxmax2', 0)];
    dyRange2 = stepSizeMult .* [localGetScalarField(simPos, 'dymin2', 0), localGetScalarField(simPos, 'dymax2', 0)];

    x1 = sim_targ_pos(nsteps, localGetScalarField(simPos, 'initx1', 0), ...
        dxRange1(1), dxRange1(2), stepNoiseType, stepNoiseSigma, ...
        stepNoiseCapSigma, boundaryMode, boundaryRejectMaxAttempts, positionBound);
    y1 = sim_targ_pos(nsteps, localGetScalarField(simPos, 'inity1', 0), ...
        dyRange1(1), dyRange1(2), stepNoiseType, stepNoiseSigma, ...
        stepNoiseCapSigma, boundaryMode, boundaryRejectMaxAttempts, positionBound);
    [px, py] = localNormToScreenPx(x1(:), y1(:), geom);
    if strcmp(opts.target, 'all') || strcmp(opts.target, 'target1')
        idx = n + (1:numel(px));
        targetXPx(idx) = px;
        targetYPx(idx) = py;
        n = n + numel(px);
    end

    if targetNum == 2
        x2 = sim_targ_pos(nsteps, localGetScalarField(simPos, 'initx2', 0), ...
            dxRange2(1), dxRange2(2), stepNoiseType, stepNoiseSigma, ...
            stepNoiseCapSigma, boundaryMode, boundaryRejectMaxAttempts, positionBound);
        y2 = sim_targ_pos(nsteps, localGetScalarField(simPos, 'inity2', 0), ...
            dyRange2(1), dyRange2(2), stepNoiseType, stepNoiseSigma, ...
            stepNoiseCapSigma, boundaryMode, boundaryRejectMaxAttempts, positionBound);
        [px, py] = localNormToScreenPx(x2(:), y2(:), geom);
        if strcmp(opts.target, 'all') || strcmp(opts.target, 'target2')
            idx = n + (1:numel(px));
            targetXPx(idx) = px;
            targetYPx(idx) = py;
            n = n + numel(px);
        end
    end
end

targetXPx = targetXPx(1:n);
targetYPx = targetYPx(1:n);
meta = struct();
meta.source = 'theoretical';
meta.nSimTrials = opts.nSimTrials;
meta.nSteps = nsteps;
meta.nTargetSamples = n;
meta.randomizeStartPos = randomizeStart;
meta.startRadiusNorm = hypot(localGetScalarField(pos, 'initx1', 0), localGetScalarField(pos, 'inity1', 0));
meta.startHandling = localStartHandlingDescription(randomizeStart);
meta.targetNumLevels = targetNumLevels;
meta.targetNumDraws = targetNumDraws;
meta.stepSizeLevels = stepSizeLevels;
meta.stepSizeDraws = stepSizeDraws;
meta.stepNoiseType = stepNoiseType;
meta.stepNoiseSigmaBase = stepNoiseSigmaBase;
meta.stepNoiseCapSigma = stepNoiseCapSigma;
meta.boundaryMode = boundaryMode;
meta.boundaryRejectMaxAttempts = boundaryRejectMaxAttempts;
meta.targetPositionBound = positionBound;
end


function [targetXPx, targetYPx, meta] = localRealizedTargetsPx(ex, trialList, opts, geom)
targetXPx = [];
targetYPx = [];
trialsUsed = [];

for i = 1:numel(trialList)
    trialIdx = trialList(i);
    T = ex.Trials(trialIdx);
    [x1, y1, x2, y2] = localTrialTargetNorm(T);
    if isempty(x1) || isempty(y1)
        continue
    end
    if strcmp(opts.target, 'all') || strcmp(opts.target, 'target1')
        [px, py] = localNormToScreenPx(x1(:), y1(:), geom);
        targetXPx = [targetXPx; px(:)]; %#ok<AGROW>
        targetYPx = [targetYPx; py(:)]; %#ok<AGROW>
    end
    if ~isempty(x2) && ~isempty(y2) && ...
            (strcmp(opts.target, 'all') || strcmp(opts.target, 'target2'))
        [px, py] = localNormToScreenPx(x2(:), y2(:), geom);
        targetXPx = [targetXPx; px(:)]; %#ok<AGROW>
        targetYPx = [targetYPx; py(:)]; %#ok<AGROW>
    end
    trialsUsed(end+1) = trialIdx; %#ok<AGROW>
end

meta = struct();
meta.source = 'trials';
meta.trialsRequested = trialList;
meta.trialsUsed = trialsUsed;
meta.nTrialsUsed = numel(trialsUsed);
meta.nTargetSamples = numel(targetXPx);
end


function [x1, y1, x2, y2] = localTrialTargetNorm(T)
x1 = [];
y1 = [];
x2 = [];
y2 = [];
if isfield(T, 'posT') && isstruct(T.posT) && isfield(T.posT, 'x1') && isfield(T.posT, 'y1')
    x1 = double(T.posT.x1(:));
    y1 = double(T.posT.y1(:));
    if isfield(T.posT, 'x2') && isfield(T.posT, 'y2')
        x2 = double(T.posT.x2(:));
        y2 = double(T.posT.y2(:));
    end
    return
end
if isfield(T, 'targetPositions') && isstruct(T.targetPositions) && ...
        isfield(T.targetPositions, 'targ1')
    nSteps = numel(T.targetPositions);
    x1 = NaN(nSteps, 1);
    y1 = NaN(nSteps, 1);
    x2 = NaN(nSteps, 1);
    y2 = NaN(nSteps, 1);
    has2 = false;
    for j = 1:nSteps
        if isfield(T.targetPositions(j).targ1, 'norm_pos') && ...
                numel(T.targetPositions(j).targ1.norm_pos) >= 2
            x1(j) = T.targetPositions(j).targ1.norm_pos(1);
            y1(j) = T.targetPositions(j).targ1.norm_pos(2);
        end
        if isfield(T.targetPositions(j), 'targ2') && ...
                isfield(T.targetPositions(j).targ2, 'norm_pos') && ...
                numel(T.targetPositions(j).targ2.norm_pos) >= 2
            x2(j) = T.targetPositions(j).targ2.norm_pos(1);
            y2(j) = T.targetPositions(j).targ2.norm_pos(2);
            has2 = true;
        end
    end
    if ~has2
        x2 = [];
        y2 = [];
    end
end
end


function [px, py] = localNormToScreenPx(xNorm, yNorm, geom)
[imgX, imgY] = pix_norm(xNorm, yNorm, geom.imgWidth, geom.imgHeight, ...
    geom.radiusTexturePx, geom.targetHiddenBoundsFrac);
px = geom.screenRect(1) + geom.xShift + imgX .* geom.drawScaleX;
py = geom.screenRect(2) + geom.yShift + imgY .* geom.drawScaleY;
end


function [plotBounds, textureBounds, geom] = localPlotGeometryPx(ex, opts)
graph = ex.exp.CoPs.graph;
graph = localResolveGraphRadiusForDisplay(graph, ex.setup);
screenRect = double(ex.setup.screenRect(:)');
if numel(screenRect) < 4
    error('targHeat:BadScreenRect', 'ex.setup.screenRect must have 4 elements.');
end
if isfield(graph, 'texture_dims') && ~isempty(graph.texture_dims)
    textureDims = double(graph.texture_dims(:)');
else
    textureDims = [320, 320];
end
if numel(textureDims) < 2
    textureDims = [textureDims(1), textureDims(1)];
end
imgHeight = textureDims(1);
imgWidth = textureDims(2);
sizeMult = localGetScalarField(graph, 'size_mult', 1);
drawnTexH = imgHeight * sizeMult;
drawnTexW = imgWidth * sizeMult;
xShift = (screenRect(3) - drawnTexW) / 2;
yShift = (screenRect(4) - drawnTexH) / 2;

targetHiddenBoundsFrac = 0;
if isfield(ex.exp.CoPs, 'ctl')
    targetHiddenBoundsFrac = localGetScalarField(ex.exp.CoPs.ctl, 'targetHiddenBoundsFrac', 0);
end

textureBounds = struct('xMin', screenRect(1) + xShift, ...
    'xMax', screenRect(1) + xShift + drawnTexW, ...
    'yMin', screenRect(2) + yShift, ...
    'yMax', screenRect(2) + yShift + drawnTexH);
plotBounds = struct('xMin', screenRect(1), 'xMax', screenRect(3), ...
    'yMin', screenRect(2), 'yMax', screenRect(4));
if opts.insideTextureOnly
    plotBounds = textureBounds;
end

geom = struct();
geom.graph = graph;
geom.screenRect = screenRect;
geom.imgHeight = imgHeight;
geom.imgWidth = imgWidth;
geom.drawnTexH = drawnTexH;
geom.drawnTexW = drawnTexW;
geom.drawScaleX = drawnTexW / imgWidth;
geom.drawScaleY = drawnTexH / imgHeight;
geom.xShift = xShift;
geom.yShift = yShift;
geom.radiusTexturePx = localGetScalarField(graph, 'radius', 1);
geom.radiusScreenPx = geom.radiusTexturePx * sizeMult;
geom.targetHiddenBoundsFrac = targetHiddenBoundsFrac;
end


function graph = localResolveGraphRadiusForDisplay(graph, setup)
if ~isfield(graph, 'radius') || isempty(graph.radius)
    return
end
sizeMult = localGetScalarField(graph, 'size_mult', 1);
radiusInput = double(localFirstScalar(graph.radius));
units = localGetTextField(graph, 'radiusUnits', 'texturePx');
if ~localIsVisualDegUnits(units)
    graph.radius = radiusInput;
    graph.radiusScreenPx = radiusInput * sizeMult;
    return
end
radiusDeg = localGetScalarField(graph, 'radiusDeg', NaN);
if ~isfinite(radiusDeg) || radiusDeg <= 0
    originalTexturePx = localGetScalarField(graph, 'radiusOriginalTexturePx', NaN);
    if ~isfinite(originalTexturePx) || originalTexturePx <= 0
        originalTexturePx = localGetScalarField(graph, 'radiusReferenceTexturePx', radiusInput);
    end
    refMonitorWidth = localGetScalarField(graph, 'radiusReferenceMonitorWidth', 38.5);
    refViewingDistance = localGetScalarField(graph, 'radiusReferenceViewingDistance', setup.viewingDistance);
    refScreenWidthPx = localGetScalarField(graph, 'radiusReferenceScreenWidthPx', setup.screenRect(3));
    radiusDeg = originalTexturePx * sizeMult * localDegPerPixel(refMonitorWidth, refViewingDistance, refScreenWidthPx);
end
currentDpp = localDegPerPixel(setup.monitorWidth, setup.viewingDistance, setup.screenRect(3));
graph.radius = radiusDeg / currentDpp / sizeMult;
graph.radiusScreenPx = graph.radius * sizeMult;
graph.radiusDeg = radiusDeg;
end


function bound = localTargetPositionBound(graph, hiddenFrac)
bound = 1;
hiddenFrac = double(localFirstScalar(hiddenFrac));
if ~isfinite(hiddenFrac) || hiddenFrac <= 0 || ~isfield(graph, 'texture_dims') || ~isfield(graph, 'radius')
    return
end
texDims = double(graph.texture_dims(:)');
if numel(texDims) < 2
    texDims = [texDims(1), texDims(1)];
end
radius = double(localFirstScalar(graph.radius));
visibleRange = min((texDims(1:2) / 2) - radius);
if isfinite(radius) && radius > 0 && isfinite(visibleRange) && visibleRange > 0
    bound = 1 + (2 * radius * hiddenFrac) / visibleRange;
end
end


function tf = localResolveRandomizeStart(opts, ctl)
if isfield(opts, 'randomizeStartPos') && ~isempty(opts.randomizeStartPos)
    tf = logical(localFirstScalar(opts.randomizeStartPos));
elseif isfield(ctl, 'randomize_start_pos') && ~isempty(ctl.randomize_start_pos)
    tf = logical(localFirstScalar(ctl.randomize_start_pos));
else
    tf = false;
end
end


function description = localStartHandlingDescription(randomizeStart)
if randomizeStart
    description = 'uniform random start angle at configured target-1 start radius; target 2 starts opposite target 1';
else
    description = 'configured fixed start position';
end
end


function trialList = localResolveTrialList(ex, trialNo)
if ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('targHeat:NoTrials', 'Input ex has no trials in ex.Trials.');
end
nTrials = numel(ex.Trials);
if isempty(trialNo) || (ischar(trialNo) && strcmpi(trialNo, 'all')) || ...
        (isstring(trialNo) && isscalar(trialNo) && strcmpi(trialNo, "all"))
    trialList = 1:nTrials;
    return
end
if islogical(trialNo)
    if numel(trialNo) ~= nTrials
        error('targHeat:BadTrialMask', 'Logical trialNo must match numel(ex.Trials).');
    end
    trialList = find(trialNo(:))';
    return
end
trialList = unique(double(trialNo(:)'));
trialList = trialList(isfinite(trialList) & trialList == round(trialList));
trialList = trialList(trialList >= 1 & trialList <= nTrials);
if isempty(trialList)
    error('targHeat:NoTrialsSelected', 'No valid trials selected.');
end
end


function value = localOptionOrField(optionValue, s, fieldName, defaultValue)
if ~isempty(optionValue)
    value = double(optionValue);
elseif isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = double(s.(fieldName));
else
    value = defaultValue;
end
value = value(:)';
value = value(isfinite(value));
if isempty(value)
    value = defaultValue;
end
end


function value = localSampleLevel(levels)
levels = double(levels(:)');
levels = levels(isfinite(levels));
if isempty(levels)
    value = NaN;
elseif numel(levels) == 1
    value = levels;
else
    value = levels(randi(numel(levels)));
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
yMin = localPxToDeg(boundsPx.yMin - y0, setup);
yMax = localPxToDeg(boundsPx.yMax - y0, setup);
if flipY
    yVals = sort([-yMin, -yMax]);
else
    yVals = sort([yMin, yMax]);
end
boundsDeg = struct( ...
    'xMin', localPxToDeg(boundsPx.xMin - x0, setup), ...
    'xMax', localPxToDeg(boundsPx.xMax - x0, setup), ...
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
        error('targHeat:BadNormalize', ...
            'opts.normalize must be count, probability, pdf, or peak.');
end
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


function probability = localRenormalizeProbability(probability)
total = sum(probability(isfinite(probability)));
if total > 0
    probability = probability ./ total;
end
probability(~isfinite(probability)) = 0;
end


function map = localDisplayMap(counts, probability, smoothProbability, mode, binSizeDeg)
mode = lower(strtrim(mode));
switch mode
    case {'count', 'counts'}
        map = counts;
    case {'probability', 'prob'}
        map = smoothProbability;
    case {'pdf', 'density', 'probabilitydensity'}
        map = smoothProbability ./ max(binSizeDeg .* binSizeDeg, eps);
    case {'peak', 'max'}
        map = smoothProbability ./ max(max(smoothProbability(:)), eps);
    otherwise
        error('targHeat:BadNormalize', ...
            'opts.normalize must be count, probability, pdf, or peak.');
end
end


function query = localQueryProbability(opts, geom, x0, y0, setup, xEdges, yEdges, probability, smoothProbability, displayMap, counts, circleRadiusDeg)
query = table();
rows = struct('units', {}, 'inputX', {}, 'inputY', {}, 'xDeg', {}, 'yDeg', {}, ...
    'xBin', {}, 'yBin', {}, 'insideMap', {}, 'probability', {}, ...
    'rawProbability', {}, 'displayValue', {}, 'count', {}, ...
    'circleRadiusDeg', {}, 'circleAreaDeg2', {}, 'circleProbability', {}, ...
    'rawCircleProbability', {}, 'circleDisplayValueSum', {}, 'circleCount', {});

rows = localAppendQueryRows(rows, opts.queryDeg, 'deg', x0, y0, setup, opts, geom);
rows = localAppendQueryRows(rows, opts.queryNorm, 'norm', x0, y0, setup, opts, geom);
rows = localAppendQueryRows(rows, opts.queryTargetNorm, 'targetNorm', x0, y0, setup, opts, geom);
rows = localAppendQueryRows(rows, opts.queryPx, 'px', x0, y0, setup, opts, geom);
if isempty(rows)
    return
end

for i = 1:numel(rows)
    xBin = localBinIndex(rows(i).xDeg, xEdges);
    yBin = localBinIndex(rows(i).yDeg, yEdges);
    rows(i).xBin = xBin;
    rows(i).yBin = yBin;
    rows(i).insideMap = isfinite(xBin) && isfinite(yBin);
    rows(i).circleRadiusDeg = circleRadiusDeg;
    if isfinite(circleRadiusDeg) && circleRadiusDeg > 0
        rows(i).circleAreaDeg2 = pi * circleRadiusDeg ^ 2;
    end
    if rows(i).insideMap
        rows(i).probability = smoothProbability(xBin, yBin);
        rows(i).rawProbability = probability(xBin, yBin);
        rows(i).displayValue = displayMap(xBin, yBin);
        rows(i).count = counts(xBin, yBin);
    end
    if isfinite(circleRadiusDeg) && circleRadiusDeg > 0
        circleMask = localCircleBinMask(rows(i).xDeg, rows(i).yDeg, circleRadiusDeg, xEdges, yEdges);
        rows(i).circleProbability = sum(smoothProbability(circleMask));
        rows(i).rawCircleProbability = sum(probability(circleMask));
        rows(i).circleDisplayValueSum = sum(displayMap(circleMask));
        rows(i).circleCount = sum(counts(circleMask));
    end
end

query = struct2table(rows);
end


function rows = localAppendQueryRows(rows, coords, units, x0, y0, setup, opts, geom)
if isempty(coords)
    return
end
coords = localFirstPointRows(coords);
for i = 1:size(coords, 1)
    inputXY = coords(i, :);
    [xDeg, yDeg] = localQueryToPlotDeg(inputXY, units, x0, y0, setup, opts, geom);
    row = struct();
    row.units = string(units);
    row.inputX = inputXY(1);
    row.inputY = inputXY(2);
    row.xDeg = xDeg;
    row.yDeg = yDeg;
    row.xBin = NaN;
    row.yBin = NaN;
    row.insideMap = false;
    row.probability = NaN;
    row.rawProbability = NaN;
    row.displayValue = NaN;
    row.count = NaN;
    row.circleRadiusDeg = NaN;
    row.circleAreaDeg2 = NaN;
    row.circleProbability = NaN;
    row.rawCircleProbability = NaN;
    row.circleDisplayValueSum = NaN;
    row.circleCount = NaN;
    rows(end+1) = row; %#ok<AGROW>
end
end


function [xDeg, yDeg] = localQueryToPlotDeg(inputXY, units, x0, y0, setup, opts, geom)
switch lower(units)
    case 'deg'
        xDeg = inputXY(1);
        yDeg = inputXY(2);
    case 'norm'
        xyPx = [geom.screenRect(1) + geom.xShift + inputXY(1) .* geom.drawnTexW, ...
            geom.screenRect(2) + geom.yShift + inputXY(2) .* geom.drawnTexH];
        xyDeg = localScreenPxToPlotDeg(xyPx, x0, y0, setup, opts.flipY);
        xDeg = xyDeg(1);
        yDeg = xyDeg(2);
    case 'targetnorm'
        [px, py] = localNormToScreenPx(inputXY(1), inputXY(2), geom);
        xyDeg = localScreenPxToPlotDeg([px, py], x0, y0, setup, opts.flipY);
        xDeg = xyDeg(1);
        yDeg = xyDeg(2);
    case 'px'
        xyDeg = localScreenPxToPlotDeg(inputXY, x0, y0, setup, opts.flipY);
        xDeg = xyDeg(1);
        yDeg = xyDeg(2);
    otherwise
        xDeg = NaN;
        yDeg = NaN;
end
end


function mask = localCircleBinMask(xDeg, yDeg, radiusDeg, xEdges, yEdges)
xCenters = localBinCenters(xEdges);
yCenters = localBinCenters(yEdges);
[xGrid, yGrid] = ndgrid(xCenters, yCenters);
mask = hypot(xGrid - xDeg, yGrid - yDeg) <= radiusDeg;
end


function binIdx = localBinIndex(value, edges)
binIdx = NaN;
if ~isfinite(value) || isempty(edges) || numel(edges) < 2
    return
end
idx = find(value >= edges(1:end-1) & value < edges(2:end), 1, 'first');
if isempty(idx) && value == edges(end)
    idx = numel(edges) - 1;
end
if ~isempty(idx)
    binIdx = idx;
end
end


function [cmap, colorLimits, schemeUsed] = localResolveColorDisplay(map, opts)
schemeUsed = lower(strtrim(char(string(opts.colorScheme))));
if ~isempty(opts.colormap)
    if isnumeric(opts.colormap)
        cmap = double(opts.colormap);
        if size(cmap, 2) ~= 3 || isempty(cmap)
            error('targHeat:BadColormap', 'opts.colormap must be an n x 3 RGB array or a colormap name.');
        end
        cmap = max(0, min(1, cmap));
        schemeUsed = 'custom';
    else
        schemeUsed = lower(strtrim(char(string(opts.colormap))));
        cmap = localColormapByName(schemeUsed, opts.nColors);
    end
else
    cmap = localColormapByName(schemeUsed, opts.nColors);
end
colorLimits = localResolveColorLimits(map, opts);
end


function cmap = localColormapByName(scheme, nColors)
scheme = lower(strtrim(char(string(scheme))));
switch scheme
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
        error('targHeat:BadColorScheme', ...
            'Unknown opts.colorScheme ''%s''. Use density, hot, parula, turbo, viridis, magma, gray, jet, bone, copper, or pass opts.colormap.', scheme);
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
    error('targHeat:BadColorLimits', 'opts.colorLimits must contain two increasing finite values.');
end

mode = lower(strtrim(char(string(opts.colorLimitMode))));
finiteVals = double(map(isfinite(map)));
if isempty(finiteVals)
    colorLimits = [];
    return
end
switch mode
    case 'none'
        colorLimits = [];
    case 'prctile'
        colorLimits = prctile(finiteVals, [0, opts.colorLimitPrctile]);
        if colorLimits(2) <= colorLimits(1)
            colorLimits = [];
        end
    otherwise
        error('targHeat:BadColorLimitMode', 'opts.colorLimitMode must be ''none'' or ''prctile''.');
end
end


function label = localColorbarLabel(normalizeMode)
switch lower(strtrim(normalizeMode))
    case {'count', 'counts'}
        label = 'target count';
    case {'probability', 'prob'}
        label = 'target probability per bin';
    case {'pdf', 'density', 'probabilitydensity'}
        label = 'target probability density';
    case {'peak', 'max'}
        label = 'target probability, peak normalized';
    otherwise
        label = 'target probability';
end
end


function titleText = localPlotTitle(opts, meta, nSamples)
switch lower(opts.source)
    case 'theoretical'
        titleText = sprintf('Theoretical target probability: %d simulated trials, n=%d target samples', ...
            meta.nSimTrials, nSamples);
    otherwise
        titleText = sprintf('Realized target probability: %d trials, n=%d target samples', ...
            meta.nTrialsUsed, nSamples);
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


function localDrawQueryCircles(query, opts, boundsDeg)
if isempty(query) || ~ismember('circleRadiusDeg', query.Properties.VariableNames)
    return
end
theta = linspace(0, 2*pi, 241);
for i = 1:height(query)
    if ~query.insideMap(i) || ~isfinite(query.circleRadiusDeg(i)) || query.circleRadiusDeg(i) <= 0
        continue
    end
    x = query.xDeg(i) + query.circleRadiusDeg(i) .* cos(theta);
    y = query.yDeg(i) + query.circleRadiusDeg(i) .* sin(theta);
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
        'LineStyle', char(string(opts.queryCircleLineStyle)), ...
        'Color', opts.queryCircleColor, ...
        'LineWidth', opts.queryCircleLineWidth);
end
end


function [rewardPeakPx, rewardPeakDeg] = localRewardPeakForPlot(ex, x0, y0, opts)
[rewardPeakPx, rewardPeakDeg, hasOverride] = localRewardPeakOverride(ex, x0, y0, opts);
if hasOverride
    return
end
rewardPeakPx = localRewardPeakPx(ex);
rewardPeakDeg = NaN(size(rewardPeakPx));
if isempty(rewardPeakPx)
    return
end
rewardPeakDeg(:, 1) = localPxToDeg(rewardPeakPx(:, 1) - x0, ex.setup);
rewardPeakDeg(:, 2) = localPxToDeg(rewardPeakPx(:, 2) - y0, ex.setup);
if opts.flipY
    rewardPeakDeg(:, 2) = -rewardPeakDeg(:, 2);
end
end


function [rewardPeakPx, rewardPeakDeg, hasOverride] = localRewardPeakOverride(ex, x0, y0, opts)
rewardPeakPx = NaN(0, 2);
rewardPeakDeg = NaN(0, 2);
hasOverride = false;

if isfield(opts, 'rewardPeakNorm') && ~isempty(opts.rewardPeakNorm)
    rewardPeakPx = localRewardNormToScreenPx(ex, opts.rewardPeakNorm);
    rewardPeakDeg = localScreenPxToPlotDeg(rewardPeakPx, x0, y0, ex.setup, opts.flipY);
    hasOverride = true;
elseif isfield(opts, 'rewardPeakDeg') && ~isempty(opts.rewardPeakDeg)
    rewardPeakDeg = localFirstPointRows(opts.rewardPeakDeg);
    rewardPeakPx = localPlotDegToScreenPx(rewardPeakDeg, x0, y0, ex.setup, opts.flipY);
    hasOverride = true;
elseif isfield(opts, 'rewardPeakPx') && ~isempty(opts.rewardPeakPx)
    rewardPeakPx = localFirstPointRows(opts.rewardPeakPx);
    rewardPeakDeg = localScreenPxToPlotDeg(rewardPeakPx, x0, y0, ex.setup, opts.flipY);
    hasOverride = true;
end

if hasOverride
    keep = all(isfinite(rewardPeakPx), 2) & all(isfinite(rewardPeakDeg), 2);
    rewardPeakPx = rewardPeakPx(keep, :);
    rewardPeakDeg = rewardPeakDeg(keep, :);
end
end


function rewardPeakPx = localRewardPeakPx(ex)
rewardPeakPx = NaN(0, 2);
if isfield(ex, 'Trials') && ~isempty(ex.Trials)
    for i = 1:numel(ex.Trials)
        T = ex.Trials(i);
        if isfield(T, 'gaussRewardCenterNorm') && numel(T.gaussRewardCenterNorm) >= 2 && ...
                all(isfinite(T.gaussRewardCenterNorm(1:2)))
            ctr = localRewardNormToScreenPx(ex, T.gaussRewardCenterNorm);
            if all(isfinite(ctr))
                rewardPeakPx(end+1, :) = ctr; %#ok<AGROW>
            end
        elseif isfield(T, 'gaussRewardCenterPx') && numel(T.gaussRewardCenterPx) >= 2 && ...
                all(isfinite(T.gaussRewardCenterPx(1:2)))
            ctr = localRewardMapPxToScreenPx(ex, T.gaussRewardCenterPx);
            if all(isfinite(ctr))
                rewardPeakPx(end+1, :) = ctr; %#ok<AGROW>
            end
        end
    end
end
if isempty(rewardPeakPx)
    ctrNorm = localRewardCenterNormFromSettings(ex);
    ctr = localRewardNormToScreenPx(ex, ctrNorm);
    if all(isfinite(ctr))
        rewardPeakPx = ctr;
    end
end
rewardPeakPx = localUniqueRowsTol(rewardPeakPx, 1e-6);
end


function sigmaDeg = localRewardSigmaDeg(ex)
sigmaDeg = NaN;
if ~isfield(ex, 'exp') || ~isfield(ex.exp, 'CoPs') || ~isfield(ex.exp.CoPs, 'rew')
    return
end
rew = ex.exp.CoPs.rew;
if isfield(rew, 'gauss_sigmaDeg') && isfinite(localFirstScalar(rew.gauss_sigmaDeg))
    sigmaDeg = double(localFirstScalar(rew.gauss_sigmaDeg));
    return
end
if isfield(rew, 'gauss_sigma') && isfinite(localFirstScalar(rew.gauss_sigma))
    sigmaVal = double(localFirstScalar(rew.gauss_sigma));
    units = localGetTextField(rew, 'gauss_sigmaUnits', 'px');
    if localIsVisualDegUnits(units)
        sigmaDeg = sigmaVal;
    else
        sigmaDeg = localPxToDeg(sigmaVal, ex.setup);
    end
    return
end
if isfield(rew, 'gauss_sigmaPx') && isfinite(localFirstScalar(rew.gauss_sigmaPx))
    sigmaDeg = localPxToDeg(double(localFirstScalar(rew.gauss_sigmaPx)), ex.setup);
end
end


function ctrNorm = localRewardCenterNormFromSettings(ex)
ctrNorm = [NaN, NaN];
if ~isfield(ex.exp.CoPs, 'rew')
    return
end
rew = ex.exp.CoPs.rew;
if isfield(rew, 'gauss_center_free') && logical(localFirstScalar(rew.gauss_center_free)) && ...
        isfield(rew, 'gauss_center_coords') && numel(rew.gauss_center_coords) >= 2 && ...
        all(isfinite(rew.gauss_center_coords(1:2)))
    ctrNorm = double(rew.gauss_center_coords(1:2));
    return
end
if isfield(rew, 'gauss_center_positions_norm') && ~isempty(rew.gauss_center_positions_norm)
    centers = double(rew.gauss_center_positions_norm);
    idx = localGetScalarField(rew, 'gauss_center_idx', 1);
    idx = max(1, min(size(centers, 1), round(idx)));
    ctrNorm = centers(idx, 1:2);
end
end


function ctr = localRewardNormToScreenPx(ex, ctrNorm)
ctrNorm = localFirstPointRows(ctrNorm);
ctr = NaN(size(ctrNorm));
if isempty(ctrNorm)
    return
end
[~, ~, geom] = localPlotGeometryPx(ex, struct('insideTextureOnly', true));
ctr(:, 1) = geom.screenRect(1) + geom.xShift + ctrNorm(:, 1) .* geom.drawnTexW;
ctr(:, 2) = geom.screenRect(2) + geom.yShift + ctrNorm(:, 2) .* geom.drawnTexH;
end


function ctr = localRewardMapPxToScreenPx(ex, ctrMapPx)
ctrMapPx = localFirstPointRows(ctrMapPx);
ctr = NaN(size(ctrMapPx));
if isempty(ctrMapPx)
    return
end
[~, ~, geom] = localPlotGeometryPx(ex, struct('insideTextureOnly', true));
ctr(:, 1) = geom.screenRect(1) + geom.xShift + ctrMapPx(:, 1);
ctr(:, 2) = geom.screenRect(2) + geom.yShift + ctrMapPx(:, 2);
end


function rows = localFirstPointRows(value)
rows = double(value);
if isempty(rows)
    rows = NaN(0, 2);
    return
end
if isvector(rows)
    rows = rows(:)';
end
if size(rows, 2) < 2 && size(rows, 1) >= 2
    rows = rows';
end
if size(rows, 2) < 2
    rows = NaN(0, 2);
else
    rows = rows(:, 1:2);
end
end


function xyDeg = localScreenPxToPlotDeg(xyPx, x0, y0, setup, flipY)
xyPx = localFirstPointRows(xyPx);
xyDeg = NaN(size(xyPx));
if isempty(xyPx)
    return
end
xyDeg(:, 1) = localPxToDeg(xyPx(:, 1) - x0, setup);
xyDeg(:, 2) = localPxToDeg(xyPx(:, 2) - y0, setup);
if flipY
    xyDeg(:, 2) = -xyDeg(:, 2);
end
end


function xyPx = localPlotDegToScreenPx(xyDeg, x0, y0, setup, flipY)
xyDeg = localFirstPointRows(xyDeg);
xyPx = NaN(size(xyDeg));
if isempty(xyDeg)
    return
end
xyPx(:, 1) = x0 + localDegToPx(xyDeg(:, 1), setup);
if flipY
    xyPx(:, 2) = y0 - localDegToPx(xyDeg(:, 2), setup);
else
    xyPx(:, 2) = y0 + localDegToPx(xyDeg(:, 2), setup);
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


function deg = localPxToDeg(px, setup)
cm = double(px) .* double(setup.monitorWidth) ./ double(setup.screenRect(3));
deg = rad2deg(atan(cm ./ double(setup.viewingDistance)));
end


function px = localDegToPx(deg, setup)
px = double(setup.viewingDistance) .* tan(deg2rad(double(deg))) .* ...
    double(setup.screenRect(3)) ./ double(setup.monitorWidth);
end


function dpp = localDegPerPixel(monitorWidthCm, viewingDistanceCm, screenWidthPx)
dpp = NaN;
monitorWidthCm = double(monitorWidthCm);
viewingDistanceCm = double(viewingDistanceCm);
screenWidthPx = double(screenWidthPx);
if isfinite(monitorWidthCm) && monitorWidthCm > 0 && ...
        isfinite(viewingDistanceCm) && viewingDistanceCm > 0 && ...
        isfinite(screenWidthPx) && screenWidthPx > 0
    dpp = atan((monitorWidthCm / 2) / viewingDistanceCm) * 180 / pi / (screenWidthPx / 2);
end
end


function tf = localIsVisualDegUnits(units)
units = lower(strtrim(char(string(units))));
tf = ismember(units, {'deg', 'degree', 'degrees', 'visualdeg', 'visualdegree', 'visualdegrees'});
end


function value = localGetScalarField(s, fieldName, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    candidate = double(localFirstScalar(s.(fieldName)));
    if isfinite(candidate)
        value = candidate;
    end
end
end


function value = localGetTextField(s, fieldName, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = char(string(s.(fieldName)));
end
end


function x = localFirstScalar(x)
if isempty(x)
    x = NaN;
else
    x = x(1);
end
end
