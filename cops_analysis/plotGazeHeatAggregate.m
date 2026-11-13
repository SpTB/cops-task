function out = plotGazeHeatAggregate(A, groupingArg, opts)
% plotGazeHeatAggregate  Plot output from collectGazeHeat.
%
%   plotGazeHeatAggregate(A)
%   plotGazeHeatAggregate(A, 'block')
%   out = plotGazeHeatAggregate(A, [], opts)
%
% A can be collected once with collectGazeHeat(..., [], opts); the block
% view uses A.blockGroups when available.

if nargin < 2
    groupingArg = [];
end
if nargin < 3 || isempty(opts)
    if isstruct(groupingArg)
        opts = groupingArg;
        groupingArg = [];
    else
        opts = struct();
    end
elseif ~isstruct(opts)
    error('plotGazeHeatAggregate:BadOpts', 'opts must be a struct.');
end

opts = localDefaults(opts, A);
localValidateAggregate(A, groupingArg);
[plotGroups, plotLabels, groupingUsed] = localSelectPlotGroups(A, groupingArg);

nGroup = numel(plotGroups);
if nGroup == 0
    error('plotGazeHeatAggregate:NoGroups', '%s', localEmptyGroupsMessage(A));
end

if opts.newFigure
    figure;
end

cmap = localGetColormap(A, opts);
clim = localSharedColorLimits(plotGroups, opts);
nRows = opts.nRows;
nCols = opts.nCols;
if isempty(nRows) || isempty(nCols)
    if strcmpi(groupingUsed, 'block') && nGroup <= 3
        nRows = 1;
        nCols = nGroup;
    else
        nCols = ceil(sqrt(nGroup));
        nRows = ceil(nGroup ./ nCols);
    end
end

tl = tiledlayout(nRows, nCols, 'Padding', 'compact', 'TileSpacing', 'compact');
for g = 1:nGroup
    ax = nexttile(tl, g);
    group = plotGroups{g};
    imagesc(ax, A.xCentersDeg, A.yCentersDeg, group.density');
    set(ax, 'YDir', 'normal');
    axis(ax, 'image');
    colormap(ax, cmap);
    if ~isempty(clim)
        caxis(ax, clim);
    end
    hold(ax, 'on');
    if opts.showRewardPeakCircle && isfield(group, 'rewardPeakCircleDeg') && ~isempty(group.rewardPeakCircleDeg)
        localDrawRewardPeakCircle(ax, group.rewardPeakCircleDeg, opts, A);
    end
    if opts.showRewardPeak && isfield(group, 'rewardPeakPlotDeg') && numel(group.rewardPeakPlotDeg) >= 2 && ...
            all(isfinite(group.rewardPeakPlotDeg(1:2)))
        plot(ax, group.rewardPeakPlotDeg(1), group.rewardPeakPlotDeg(2), opts.rewardPeakMarker, ...
            'Color', opts.rewardPeakColor, ...
            'MarkerSize', opts.rewardPeakMarkerSize, ...
            'LineWidth', opts.rewardPeakLineWidth);
    end
    hold(ax, 'off');
    title(ax, sprintf('%s | n=%d trials, %.0f samples', ...
        char(string(group.groupLabel)), group.nTrials, group.nGazeSamples), ...
        'Interpreter', 'none');
    xlabel(ax, opts.xLabel);
    ylabel(ax, opts.yLabel);
end

cb = localSharedColorbar(tl);
if isfield(A, 'colorbarLabel') && strlength(string(A.colorbarLabel)) > 0
    ylabel(cb, char(string(A.colorbarLabel)));
end
if isfield(A, 'subject')
    title(tl, sprintf('Aggregated gaze heat: %s', char(string(A.subject))), 'Interpreter', 'none');
end

out = A;
out.plotOptions = opts;
out.colorLimits = clim;
out.plotGrouping = groupingUsed;
out.plotGroupLabels = plotLabels;
end


function opts = localDefaults(opts, A)
defaults = struct( ...
    'newFigure', true, ...
    'sharedColorLimits', true, ...
    'colorLimits', [], ...
    'colorLimitMode', 'symmetricPrctile', ...
    'colorLimitPrctile', 99, ...
    'colormap', [], ...
    'showRewardPeak', true, ...
    'rewardPeakMarker', '+', ...
    'rewardPeakColor', [0 0 0], ...
    'rewardPeakMarkerSize', 10, ...
    'rewardPeakLineWidth', 2.25, ...
    'showRewardPeakCircle', true, ...
    'rewardPeakCircleColor', [0 0 0], ...
    'rewardPeakCircleLineStyle', ':', ...
    'rewardPeakCircleLineWidth', 1.5, ...
    'xLabel', 'rotated x position (deg)', ...
    'yLabel', 'rotated y position (deg)', ...
    'nRows', [], ...
    'nCols', []);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(opts, names{i}) || isempty(opts.(names{i}))
        opts.(names{i}) = defaults.(names{i});
    end
end
alignRewardToTopLeft = false;
plotRotate45 = false;
if isfield(A, 'transform')
    if isfield(A.transform, 'alignRewardToTopLeft')
        alignRewardToTopLeft = logical(A.transform.alignRewardToTopLeft);
    end
    if isfield(A.transform, 'plotRotate45')
        plotRotate45 = logical(A.transform.plotRotate45);
    end
end
if ~alignRewardToTopLeft && ~plotRotate45
    opts.xLabel = 'x position (deg)';
    opts.yLabel = 'y position (deg)';
elseif alignRewardToTopLeft && ~plotRotate45
    opts.xLabel = 'reward-aligned x position (deg)';
    opts.yLabel = 'reward-aligned y position (deg)';
end
opts.colorLimitPrctile = double(opts.colorLimitPrctile);
if ~isfinite(opts.colorLimitPrctile) || opts.colorLimitPrctile <= 0 || opts.colorLimitPrctile > 100
    opts.colorLimitPrctile = 99;
end
end


function localValidateAggregate(A, groupingArg)
if ~isstruct(A) || ~isfield(A, 'groups') || ~iscell(A.groups)
    error('plotGazeHeatAggregate:BadInput', 'A must be output from collectGazeHeat.');
end
if ~isempty(groupingArg) && ~(ischar(groupingArg) || (isstring(groupingArg) && isscalar(groupingArg)))
    error('plotGazeHeatAggregate:BadGrouping', 'groupingArg must be a text scalar, [], or omitted.');
end
if ~isempty(groupingArg) && strcmpi(strtrim(string(groupingArg)), "block")
    if ~isfield(A, 'blockGroups') || ~iscell(A.blockGroups)
        error('plotGazeHeatAggregate:NoBlockGroups', ...
            'A does not contain blockGroups. Re-run collectGazeHeat with the current version.');
    end
    if isempty(A.blockGroups)
        error('plotGazeHeatAggregate:EmptyGroups', '%s', localEmptyGroupsMessage(A));
    end
    return
end
if ~isempty(groupingArg) && isfield(A, 'groupingArg') && ~isempty(A.groupingArg)
    requested = lower(strtrim(string(groupingArg)));
    actual = lower(strtrim(string(A.groupingArg)));
    if requested ~= actual
        error('plotGazeHeatAggregate:GroupingMismatch', ...
            'A was collected with groupingArg=''%s'', not ''%s''.', actual, requested);
    end
end
end


function [groups, labels, groupingUsed] = localSelectPlotGroups(A, groupingArg)
if ~isempty(groupingArg) && strcmpi(strtrim(string(groupingArg)), "block")
    groups = A.blockGroups;
    if isfield(A, 'blockLabels')
        labels = string(A.blockLabels(:));
    else
        labels = ["block 1"; "block 2"; "block 3"];
    end
    groupingUsed = 'block';
    return
end
groups = A.groups;
if isfield(A, 'groupLabels')
    labels = string(A.groupLabels(:));
else
    labels = strings(numel(groups), 1);
    for i = 1:numel(groups)
        labels(i) = "group " + string(i);
    end
end
if isfield(A, 'groupingArg') && ~isempty(A.groupingArg)
    groupingUsed = char(string(A.groupingArg));
else
    groupingUsed = 'all';
end
end


function cmap = localGetColormap(A, opts)
if ~isempty(opts.colormap)
    if isnumeric(opts.colormap)
        cmap = double(opts.colormap);
        return
    end
    cmap = localColormapByName(opts.colormap, 256);
elseif isfield(A, 'colormap') && ~isempty(A.colormap)
    cmap = A.colormap;
else
    cmap = localColormapByName('balance', 256);
end
end


function cb = localSharedColorbar(tl)
try
    cb = colorbar(tl, 'eastoutside');
catch
    cb = colorbar;
    try
        cb.Layout.Tile = 'east';
    catch
    end
end
end


function localDrawRewardPeakCircle(ax, rewardPeakCircleDeg, opts, A)
if isempty(rewardPeakCircleDeg)
    return
end
circleRows = double(rewardPeakCircleDeg);
if size(circleRows, 2) < 3
    return
end
keep = all(isfinite(circleRows(:, 1:3)), 2) & circleRows(:, 3) > 0;
if ~any(keep)
    return
end
bounds = localPlotBounds(A);
theta = linspace(0, 2*pi, 241);
for i = find(keep(:))'
    x = circleRows(i, 1) + circleRows(i, 3) .* cos(theta);
    y = circleRows(i, 2) + circleRows(i, 3) .* sin(theta);
    if ~isempty(bounds)
        inBounds = x >= bounds(1) & x <= bounds(2) & y >= bounds(3) & y <= bounds(4);
        if ~any(inBounds)
            continue
        end
        x(~inBounds) = NaN;
        y(~inBounds) = NaN;
    end
    plot(ax, x, y, ...
        'LineStyle', char(string(opts.rewardPeakCircleLineStyle)), ...
        'Color', opts.rewardPeakCircleColor, ...
        'LineWidth', opts.rewardPeakCircleLineWidth);
end
end


function bounds = localPlotBounds(A)
bounds = [];
if isfield(A, 'xEdgesDeg') && isfield(A, 'yEdgesDeg') && ...
        ~isempty(A.xEdgesDeg) && ~isempty(A.yEdgesDeg)
    xEdges = double(A.xEdgesDeg(:));
    yEdges = double(A.yEdgesDeg(:));
    if any(isfinite(xEdges)) && any(isfinite(yEdges))
        bounds = [min(xEdges, [], 'omitnan'), max(xEdges, [], 'omitnan'), ...
            min(yEdges, [], 'omitnan'), max(yEdges, [], 'omitnan')];
    end
end
end


function clim = localSharedColorLimits(groups, opts)
if ~isempty(opts.colorLimits)
    clim = double(opts.colorLimits(:)');
    if numel(clim) >= 2 && all(isfinite(clim(1:2))) && clim(2) > clim(1)
        clim = clim(1:2);
        return
    end
end
if ~logical(opts.sharedColorLimits)
    clim = [];
    return
end
vals = [];
for g = 1:numel(groups)
    if isfield(groups{g}, 'density')
        v = groups{g}.density(:);
        vals = [vals; v(isfinite(v))]; %#ok<AGROW>
    end
end
if isempty(vals)
    clim = [];
    return
end
mode = lower(strtrim(char(string(opts.colorLimitMode))));
switch mode
    case {'none', 'auto'}
        clim = [];
    case {'symmetric', 'sym'}
        m = max(abs(vals));
        clim = [-m, m];
    case {'symmetricprctile', 'symprctile'}
        m = prctile(abs(vals), opts.colorLimitPrctile);
        clim = [-m, m];
    case 'prctile'
        lo = prctile(vals, 100 - opts.colorLimitPrctile);
        hi = prctile(vals, opts.colorLimitPrctile);
        clim = [lo, hi];
    otherwise
        m = prctile(abs(vals), opts.colorLimitPrctile);
        clim = [-m, m];
end
if numel(clim) ~= 2 || ~all(isfinite(clim)) || clim(2) <= clim(1)
    clim = [];
end
end


function cmap = localColormapByName(scheme, nColors)
scheme = lower(strtrim(char(string(scheme))));
switch scheme
    case {'balance', 'balanced', 'diverging', 'bluered', 'bluewhitered'}
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
    case {'hot', 'parula', 'turbo', 'jet', 'gray', 'grey'}
        if strcmp(scheme, 'grey')
            scheme = 'gray';
        end
        try
            cmap = feval(scheme, nColors);
        catch
            cmap = hot(nColors);
        end
    otherwise
        cmap = localColormapByName('balance', nColors);
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


function msg = localEmptyGroupsMessage(A)
msg = "No aggregate gaze-heat groups were available to plot.";
if ~isstruct(A)
    msg = msg + " Input was not a collectGazeHeat output struct.";
    return
end
if isfield(A, 'fileTable') && istable(A.fileTable) && ~isempty(A.fileTable)
    msg = msg + " Check A.fileTable.status and A.fileTable.message.";
    if ismember('status', A.fileTable.Properties.VariableNames)
        try
            statuses = string(A.fileTable.status);
            u = unique(statuses, 'stable');
            parts = strings(numel(u), 1);
            for i = 1:numel(u)
                parts(i) = sprintf('%s=%d', u(i), nnz(statuses == u(i)));
            end
            msg = msg + " Status counts: " + strjoin(parts, ", ") + ".";
        catch
        end
    end
else
    msg = msg + " The collection output has no fileTable diagnostics.";
end
end
