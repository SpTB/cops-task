function out = plotRew(varargin)
% plotRew  Plot the CoPs Gaussian reward field.
%
%   plotRew(1) plots the top-left reward field.
%   plotRew(2) plots top-right, 3 bottom-left, 4 bottom-right.
%   plotRew(0) plots a 45 deg tilted square with reward on the left side.
%
%   plotRew(idx, opts)
%   plotRew(ex, idx)
%   plotRew(ex, idx, opts)
%
% By default this uses the current CoPs convention where the reward peak is
% at the quadrant center, not exactly on the texture edge. Set
% opts.cornerInsetNorm = 0 for literal corners.

[ex, idx, opts] = localParseInputs(varargin{:});
opts = localDefaults(opts);
idx = localValidateIndex(idx);

setup = localResolveSetup(ex, opts);
sidePx = localTextureSidePx(ex, opts);
sideDeg = localPxToDeg(sidePx, setup);
sigmaDeg = localResolveSigmaDeg(ex, setup, opts);
gaussScalar = localResolveGaussScalar(ex, opts);

centerNorm = localResolveCenterNorm(ex, idx, opts);
isDiamond = idx == 0;
[xDeg, yDeg, rewardMap, centerDeg, shapeDeg] = localBuildRewardMap( ...
    idx, centerNorm, sideDeg, sigmaDeg, opts);
rewardDisplay = localApplyValueMode(rewardMap, gaussScalar, opts);

[cmap, colorLimits, colorSchemeUsed] = localResolveColorDisplay(rewardDisplay, opts, gaussScalar);

if opts.plot
    if opts.newFigure
        figure;
    end
    hImg = imagesc(xDeg, yDeg, rewardDisplay);
    set(gca, 'YDir', 'normal');
    set(hImg, 'AlphaData', isfinite(rewardDisplay));
    axis image;
    colormap(cmap);
    if ~isempty(colorLimits)
        caxis(colorLimits);
    end
    cb = colorbar;
    ylabel(cb, localColorbarLabel(opts));
    xlabel('x position (deg)');
    ylabel('y position (deg, up positive)');
    title(localPlotTitle(idx, centerNorm, sigmaDeg, opts));
    hold on;
    if opts.showTextureBox
        plot(shapeDeg(:, 1), shapeDeg(:, 2), '-', ...
            'Color', opts.textureBoxColor, ...
            'LineWidth', opts.textureBoxLineWidth);
    end
    if opts.showRewardPeakCircle
        localDrawRewardPeakCircle(centerDeg, sideDeg, sigmaDeg, gaussScalar, isDiamond, opts);
    end
    if opts.showRewardPeak
        plot(centerDeg(1), centerDeg(2), char(opts.rewardPeakMarker), ...
            'Color', opts.rewardPeakColor, ...
            'MarkerSize', opts.rewardPeakMarkerSize, ...
            'LineWidth', opts.rewardPeakLineWidth);
    end
    hold off;
end

out = struct();
out.idx = idx;
out.centerNorm = centerNorm;
out.centerDeg = centerDeg;
out.sigmaDeg = sigmaDeg;
out.sideDeg = sideDeg;
out.sidePx = sidePx;
out.gaussScalar = gaussScalar;
out.valueMode = char(opts.valueMode);
out.xDeg = xDeg;
out.yDeg = yDeg;
out.gaussian = rewardMap;
out.reward = rewardDisplay;
out.shapeDeg = shapeDeg;
out.isDiamond = isDiamond;
out.colorScheme = colorSchemeUsed;
out.colorLimits = colorLimits;
out.colormap = cmap;
out.opts = opts;
end

function [ex, idx, opts] = localParseInputs(varargin)
ex = [];
idx = [];
opts = struct();

if nargin < 1 || isempty(varargin{1})
    idx = 1;
    return
end

arg1 = varargin{1};
if isstruct(arg1) && localLooksLikeEx(arg1)
    ex = arg1;
    if nargin >= 2 && ~isempty(varargin{2})
        idx = varargin{2};
    else
        idx = 1;
    end
    if nargin >= 3 && ~isempty(varargin{3})
        opts = varargin{3};
    end
else
    idx = arg1;
    if nargin >= 2 && ~isempty(varargin{2})
        opts = varargin{2};
    end
end

if isempty(opts)
    opts = struct();
elseif ~isstruct(opts)
    error('plotRew:BadOpts', 'opts must be a struct.');
end
end

function tf = localLooksLikeEx(s)
tf = isstruct(s) && (isfield(s, 'setup') || isfield(s, 'exp') || isfield(s, 'Trials'));
end

function opts = localDefaults(opts)
defaults = struct( ...
    'plot', true, ...
    'newFigure', true, ...
    'nGrid', 401, ...
    'cornerInsetNorm', 0.25, ...
    'centerNorm', [], ...
    'zeroCenterNorm', [], ...
    'diamondRotationDeg', 45, ...
    'sigmaDeg', [], ...
    'textureSidePx', [], ...
    'textureSideDeg', [], ...
    'screenRect', [0 0 1920 1080], ...
    'monitorWidth', 47, ...
    'viewingDistance', 58, ...
    'gaussScalar', [], ...
    'valueMode', 'gaussian', ...
    'colorScheme', 'density', ...
    'colormap', [], ...
    'nColors', 256, ...
    'colorLimits', [], ...
    'colorLimitMode', 'auto', ...
    'colorLimitPrctile', 99, ...
    'showTextureBox', true, ...
    'textureBoxColor', [1 1 1] .* 0.95, ...
    'textureBoxLineWidth', 1.25, ...
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
    'rewardPeakSigmaRadius', 3);

names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(opts, names{i}) || isempty(opts.(names{i}))
        opts.(names{i}) = defaults.(names{i});
    end
end

opts.nGrid = round(double(localFirstScalar(opts.nGrid)));
if ~isfinite(opts.nGrid) || opts.nGrid < 16
    error('plotRew:BadNGrid', 'opts.nGrid must be at least 16.');
end
opts.nColors = round(double(localFirstScalar(opts.nColors)));
if ~isfinite(opts.nColors) || opts.nColors < 2
    opts.nColors = 256;
end
opts.cornerInsetNorm = double(localFirstScalar(opts.cornerInsetNorm));
if ~isfinite(opts.cornerInsetNorm) || opts.cornerInsetNorm < 0 || opts.cornerInsetNorm > 0.5
    error('plotRew:BadCornerInset', 'opts.cornerInsetNorm must be in [0, 0.5].');
end
opts.valueMode = lower(strtrim(char(opts.valueMode)));
switch opts.valueMode
    case {'gaussian', 'raw', 'fraction'}
        opts.valueMode = 'gaussian';
    case {'mult', 'multiplier', 'rewardmultiplier'}
        opts.valueMode = 'multiplier';
    otherwise
        error('plotRew:BadValueMode', 'opts.valueMode must be ''gaussian'' or ''multiplier''.');
end
opts.circleBound = localResolveCircleBound(opts.circleBound);
end

function idx = localValidateIndex(idx)
idx = round(double(localFirstScalar(idx)));
if ~isfinite(idx) || ~ismember(idx, 0:4)
    error('plotRew:BadIndex', 'idx must be 0, 1, 2, 3, or 4.');
end
end

function setup = localResolveSetup(ex, opts)
setup = struct();
if isstruct(ex) && isfield(ex, 'setup') && isstruct(ex.setup)
    setup = ex.setup;
end
if ~isfield(setup, 'screenRect') || isempty(setup.screenRect)
    setup.screenRect = opts.screenRect;
end
if ~isfield(setup, 'monitorWidth') || isempty(setup.monitorWidth)
    setup.monitorWidth = opts.monitorWidth;
end
if ~isfield(setup, 'viewingDistance') || isempty(setup.viewingDistance)
    setup.viewingDistance = opts.viewingDistance;
end
end

function sidePx = localTextureSidePx(ex, opts)
if ~isempty(opts.textureSidePx)
    sidePx = double(localFirstScalar(opts.textureSidePx));
    return
end
if ~isempty(opts.textureSideDeg)
    sidePx = NaN;
    return
end
sidePx = NaN;
if isstruct(ex) && isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && ...
        isfield(ex.exp.CoPs, 'graph')
    graph = ex.exp.CoPs.graph;
    if isfield(graph, 'texture_dims') && ~isempty(graph.texture_dims) && ...
            isfield(graph, 'size_mult') && ~isempty(graph.size_mult)
        sidePx = double(localFirstScalar(graph.texture_dims)) .* double(localFirstScalar(graph.size_mult));
    elseif isfield(graph, 'texture_dim') && ~isempty(graph.texture_dim) && ...
            isfield(graph, 'size_mult') && ~isempty(graph.size_mult)
        sidePx = double(localFirstScalar(graph.texture_dim)) .* double(localFirstScalar(graph.size_mult));
    end
end
if ~isfinite(sidePx) || sidePx <= 0
    sidePx = 1080;
end
end

function deg = localPxToDeg(px, setup)
if isnan(px)
    deg = NaN;
    return
end
if exist('visualPxToDeg', 'file') == 2
    deg = visualPxToDeg(px, setup);
else
    cm = double(px) .* double(setup.monitorWidth) ./ double(setup.screenRect(3));
    deg = rad2deg(atan(cm ./ double(setup.viewingDistance)));
end
end

function sigmaDeg = localResolveSigmaDeg(ex, setup, opts)
if ~isempty(opts.sigmaDeg)
    sigmaDeg = double(localFirstScalar(opts.sigmaDeg));
    return
end
sigmaDeg = NaN;
rew = localRewardStruct(ex);
if isfield(rew, 'gauss_sigmaDeg') && ~isempty(rew.gauss_sigmaDeg)
    sigmaDeg = double(localFirstScalar(rew.gauss_sigmaDeg));
elseif isfield(rew, 'gauss_sigma') && ~isempty(rew.gauss_sigma)
    sigmaVal = double(localFirstScalar(rew.gauss_sigma));
    units = localTextField(rew, 'gauss_sigmaUnits', 'px');
    if ismember(lower(strtrim(units)), {'deg', 'degree', 'degrees'})
        sigmaDeg = sigmaVal;
    else
        sigmaDeg = localPxToDeg(sigmaVal, setup);
    end
elseif isfield(rew, 'gauss_sigmaPx') && ~isempty(rew.gauss_sigmaPx)
    sigmaDeg = localPxToDeg(double(localFirstScalar(rew.gauss_sigmaPx)), setup);
end
if ~isfinite(sigmaDeg) || sigmaDeg <= 0
    sigmaDeg = 3.5;
end
end

function gaussScalar = localResolveGaussScalar(ex, opts)
if ~isempty(opts.gaussScalar)
    gaussScalar = double(localFirstScalar(opts.gaussScalar));
    return
end
gaussScalar = NaN;
if isstruct(ex) && isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && ...
        isfield(ex.exp.CoPs, 'ctl') && isfield(ex.exp.CoPs.ctl, 'gauss_scalar') && ...
        ~isempty(ex.exp.CoPs.ctl.gauss_scalar)
    gaussScalar = double(localFirstScalar(ex.exp.CoPs.ctl.gauss_scalar));
end
if ~isfinite(gaussScalar) || gaussScalar <= 1
    gaussScalar = 2.25;
end
end

function centerNorm = localResolveCenterNorm(ex, idx, opts)
if ~isempty(opts.centerNorm)
    centerNorm = double(opts.centerNorm(:)');
    if numel(centerNorm) < 2 || any(~isfinite(centerNorm(1:2)))
        error('plotRew:BadCenterNorm', 'opts.centerNorm must contain [x y].');
    end
    centerNorm = centerNorm(1:2);
    return
end

cornerCenters = localCornerCentersNorm(ex, opts);
if idx == 0
    if ~isempty(opts.zeroCenterNorm)
        centerNorm = double(opts.zeroCenterNorm(:)');
        centerNorm = centerNorm(1:2);
    else
        centerNorm = cornerCenters(1, :);
    end
else
    centerNorm = cornerCenters(idx, :);
end
centerNorm = max(0, min(1, centerNorm));
end

function centers = localCornerCentersNorm(ex, opts)
centers = [];
rew = localRewardStruct(ex);
if isfield(rew, 'gauss_center_positions_norm') && ~isempty(rew.gauss_center_positions_norm)
    allCenters = double(rew.gauss_center_positions_norm);
    if size(allCenters, 1) >= 5
        centers = allCenters(2:5, 1:2);
    elseif size(allCenters, 1) >= 4
        centers = allCenters(1:4, 1:2);
    end
end
if isempty(centers)
    inset = double(opts.cornerInsetNorm);
    centers = [ ...
        inset,  inset; ...
        1-inset, inset; ...
        inset,  1-inset; ...
        1-inset, 1-inset];
end
end

function rew = localRewardStruct(ex)
rew = struct();
if isstruct(ex) && isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && ...
        isfield(ex.exp.CoPs, 'rew') && isstruct(ex.exp.CoPs.rew)
    rew = ex.exp.CoPs.rew;
end
end

function [xVals, yVals, rewardMap, centerDeg, shapeDeg] = localBuildRewardMap( ...
    idx, centerNorm, sideDeg, sigmaDeg, opts)
if ~isempty(opts.textureSideDeg)
    sideDeg = double(localFirstScalar(opts.textureSideDeg));
end
if ~isfinite(sideDeg) || sideDeg <= 0
    error('plotRew:BadTextureSize', 'Could not resolve a positive texture side size in deg.');
end
if ~isfinite(sigmaDeg) || sigmaDeg <= 0
    error('plotRew:BadSigma', 'Could not resolve a positive Gaussian sigma in deg.');
end

halfSide = sideDeg ./ 2;
if idx == 0
    lim = halfSide .* sqrt(2);
    xVals = linspace(-lim, lim, opts.nGrid);
    yVals = linspace(-lim, lim, opts.nGrid);
    [xGrid, yGrid] = meshgrid(xVals, yVals);
    theta = deg2rad(double(opts.diamondRotationDeg));
    [uGrid, vGrid] = localGlobalToLocalRotated(xGrid, yGrid, theta);
    [u0, v0] = localNormToLocalDeg(centerNorm, sideDeg);
    centerDeg = localLocalToGlobalRotated([u0, v0], theta);
    inShape = abs(uGrid) <= halfSide & abs(vGrid) <= halfSide;
    rewardMap = exp(-((uGrid - u0).^2 + (vGrid - v0).^2) ./ (2 .* sigmaDeg.^2));
    rewardMap(~inShape) = NaN;
    verticesLocal = [-halfSide halfSide; halfSide halfSide; halfSide -halfSide; -halfSide -halfSide; -halfSide halfSide];
    shapeDeg = localLocalToGlobalRotated(verticesLocal, theta);
else
    xVals = linspace(-halfSide, halfSide, opts.nGrid);
    yVals = linspace(-halfSide, halfSide, opts.nGrid);
    [xGrid, yGrid] = meshgrid(xVals, yVals);
    [u0, v0] = localNormToLocalDeg(centerNorm, sideDeg);
    centerDeg = [u0, v0];
    rewardMap = exp(-((xGrid - u0).^2 + (yGrid - v0).^2) ./ (2 .* sigmaDeg.^2));
    shapeDeg = [-halfSide halfSide; halfSide halfSide; halfSide -halfSide; -halfSide -halfSide; -halfSide halfSide];
end
end

function [u, v] = localNormToLocalDeg(centerNorm, sideDeg)
halfSide = sideDeg ./ 2;
u = -halfSide + double(centerNorm(1)) .* sideDeg;
v =  halfSide - double(centerNorm(2)) .* sideDeg;
end

function xy = localLocalToGlobalRotated(uv, theta)
uv = double(uv);
x = uv(:, 1) .* cos(theta) - uv(:, 2) .* sin(theta);
y = uv(:, 1) .* sin(theta) + uv(:, 2) .* cos(theta);
xy = [x, y];
end

function [u, v] = localGlobalToLocalRotated(x, y, theta)
u = x .* cos(theta) + y .* sin(theta);
v = -x .* sin(theta) + y .* cos(theta);
end

function rewardDisplay = localApplyValueMode(rewardMap, gaussScalar, opts)
switch opts.valueMode
    case 'gaussian'
        rewardDisplay = rewardMap;
    case 'multiplier'
        rewardDisplay = 1 + (gaussScalar - 1) .* rewardMap;
    otherwise
        rewardDisplay = rewardMap;
end
end

function [cmap, colorLimits, schemeUsed] = localResolveColorDisplay(map, opts, gaussScalar)
schemeUsed = lower(strtrim(char(opts.colorScheme)));
if ~isempty(opts.colormap)
    cmap = localColormapFromValue(opts.colormap, opts.nColors);
    if isnumeric(opts.colormap)
        schemeUsed = 'custom';
    else
        schemeUsed = lower(strtrim(char(opts.colormap)));
    end
else
    cmap = localColormapByName(schemeUsed, opts.nColors);
end
colorLimits = localResolveColorLimits(map, opts, gaussScalar);
end

function cmap = localColormapFromValue(value, nColors)
if isnumeric(value)
    cmap = double(value);
    if isempty(cmap) || size(cmap, 2) ~= 3
        error('plotRew:BadColormap', 'opts.colormap must be an n x 3 RGB array or colormap name.');
    end
    cmap = max(0, min(1, cmap));
else
    cmap = localColormapByName(lower(strtrim(char(value))), nColors);
end
end

function cmap = localColormapByName(scheme, nColors)
scheme = lower(strtrim(char(scheme)));
switch scheme
    case {'density', 'fire'}
        cmap = localInterpolatedColormap([ ...
            0.00 0.00 0.00; ...
            0.15 0.05 0.35; ...
            0.70 0.10 0.20; ...
            0.95 0.58 0.10; ...
            1.00 0.96 0.72], nColors);
    case {'balance', 'balanced', 'diverging', 'bluered', 'bluewhitered'}
        cmap = localInterpolatedColormap([ ...
            0.08 0.19 0.55; ...
            0.26 0.57 0.78; ...
            0.96 0.96 0.96; ...
            0.88 0.42 0.31; ...
            0.55 0.08 0.11], nColors);
    case {'redblue', 'redwhiteblue'}
        cmap = flipud(localColormapByName('balance', nColors));
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
        error('plotRew:BadColorScheme', ...
            'Unknown opts.colorScheme ''%s''.', scheme);
end
end

function cmap = localBuiltinColormap(name, nColors)
try
    cmap = feval(name, nColors);
catch
    switch lower(name)
        case {'turbo', 'parula'}
            cmap = jet(nColors);
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

function colorLimits = localResolveColorLimits(map, opts, gaussScalar)
if ~isempty(opts.colorLimits)
    colorLimits = double(opts.colorLimits(:)');
    if numel(colorLimits) < 2 || any(~isfinite(colorLimits(1:2))) || colorLimits(2) <= colorLimits(1)
        error('plotRew:BadColorLimits', 'opts.colorLimits must be [low high].');
    end
    colorLimits = colorLimits(1:2);
    return
end
mode = lower(strtrim(char(opts.colorLimitMode)));
finiteVals = map(isfinite(map));
if isempty(finiteVals)
    colorLimits = [];
    return
end
switch mode
    case 'auto'
        if strcmp(opts.valueMode, 'multiplier')
            colorLimits = [1, gaussScalar];
        else
            colorLimits = [0, 1];
        end
    case 'none'
        colorLimits = [];
    case 'prctile'
        colorLimits = [min(finiteVals(:)), prctile(finiteVals(:), opts.colorLimitPrctile)];
        if colorLimits(2) <= colorLimits(1)
            colorLimits = [];
        end
    otherwise
        colorLimits = [];
end
end

function label = localColorbarLabel(opts)
switch opts.valueMode
    case 'multiplier'
        label = 'reward multiplier';
    otherwise
        label = 'normalized Gaussian reward';
end
end

function titleText = localPlotTitle(idx, centerNorm, sigmaDeg, opts)
if idx == 0
    loc = 'tilted-left';
else
    labels = {'top-left', 'top-right', 'bottom-left', 'bottom-right'};
    loc = labels{idx};
end
titleText = sprintf('Reward field: %s, center=[%.2f %.2f], sigma=%.2f deg', ...
    loc, centerNorm(1), centerNorm(2), sigmaDeg);
if strcmp(opts.valueMode, 'multiplier')
    titleText = [titleText, ', multiplier'];
end
end

function localDrawRewardPeakCircle(centerDeg, sideDeg, sigmaDeg, gaussScalar, isDiamond, opts)
radii = localRewardPeakRadiiDeg(sigmaDeg, gaussScalar, opts);
if isempty(radii)
    return
end
theta = linspace(0, 2*pi, 361);
halfSide = sideDeg ./ 2;
rotTheta = deg2rad(double(opts.diamondRotationDeg));
for i = 1:numel(radii)
    x = centerDeg(1) + radii(i) .* cos(theta);
    y = centerDeg(2) + radii(i) .* sin(theta);
    if isDiamond
        [u, v] = localGlobalToLocalRotated(x, y, rotTheta);
        inShape = abs(u) <= halfSide & abs(v) <= halfSide;
    else
        inShape = x >= -halfSide & x <= halfSide & y >= -halfSide & y <= halfSide;
    end
    if ~any(inShape)
        continue
    end
    x(~inShape) = NaN;
    y(~inShape) = NaN;
    plot(x, y, ...
        'LineStyle', char(opts.rewardPeakCircleLineStyle), ...
        'Color', opts.rewardPeakCircleColor, ...
        'LineWidth', opts.rewardPeakCircleLineWidth);
end
end

function radii = localRewardPeakRadiiDeg(sigmaDeg, gaussScalar, opts)
switch opts.circleBound
    case '1sd'
        radii = sigmaDeg;
    case '2sd'
        radii = sigmaDeg .* [1, 2];
    case '3sd'
        radii = sigmaDeg .* [1, 2, 3];
    case 'mult'
        minMultiplier = double(opts.rewardPeakMinMultiplier);
        if ~isfinite(gaussScalar) || gaussScalar <= minMultiplier
            radii = [];
            return
        end
        requiredRewardFrac = (minMultiplier - 1) ./ (gaussScalar - 1);
        requiredRewardFrac = max(realmin, min(1, requiredRewardFrac));
        radii = sigmaDeg .* sqrt(-2 .* log(requiredRewardFrac));
        radii = min(double(opts.rewardPeakSigmaRadius) .* sigmaDeg, radii);
    otherwise
        radii = [];
end
radii = radii(isfinite(radii) & radii > 0);
end

function circleBound = localResolveCircleBound(value)
circleBound = lower(strtrim(char(value)));
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
        error('plotRew:BadCircleBound', ...
            'opts.circleBound must be ''mult'', ''1sd'', ''2sd'', or ''3sd''.');
end
end

function txt = localTextField(s, fieldName, defaultValue)
txt = defaultValue;
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    txt = char(s.(fieldName));
end
end

function value = localFirstScalar(value)
if isempty(value)
    value = NaN;
    return
end
value = value(1);
end
