function out = plotGazeHeatTrajectoryAggregate(A, groupingArg, opts)
% plotGazeHeatTrajectoryAggregate  Plot output from collectGazeHeatTrajectory.
%
%   plotGazeHeatTrajectoryAggregate(A)
%   plotGazeHeatTrajectoryAggregate(A, 'block')
%   out = plotGazeHeatTrajectoryAggregate(A, [], opts)
%
% A can be collected once with collectGazeHeatTrajectory(..., [], opts);
% the block view uses A.blockGroups when available.

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
    error('plotGazeHeatTrajectoryAggregate:BadOpts', 'opts must be a struct.');
end

opts = localDefaults(opts, A);
localValidateAggregate(A, groupingArg);
[plotGroups, plotLabels, groupingUsed] = localSelectPlotGroups(A, groupingArg);

nGroup = numel(plotGroups);
if nGroup == 0
    error('plotGazeHeatTrajectoryAggregate:NoGroups', '%s', localEmptyGroupsMessage(A));
end

if opts.newFigure
    figure;
end

mode = lower(strtrim(char(string(opts.plotMode))));
switch mode
    case {'trajectory', 'xy'}
        [nRows, nCols] = localGrid(nGroup, groupingUsed, opts);
        tl = tiledlayout(nRows, nCols, 'Padding', 'compact', 'TileSpacing', 'compact');
        for g = 1:nGroup
            ax = nexttile(tl, g);
            localPlotTrajectoryPanel(ax, plotGroups{g}, opts);
        end
    case {'distance', 'dist'}
        [nRows, nCols] = localGrid(nGroup, groupingUsed, opts);
        tl = tiledlayout(nRows, nCols, 'Padding', 'compact', 'TileSpacing', 'compact');
        for g = 1:nGroup
            ax = nexttile(tl, g);
            localPlotDistancePanel(ax, plotGroups{g}, opts);
        end
    otherwise
        tl = tiledlayout(2, nGroup, 'Padding', 'compact', 'TileSpacing', 'compact');
        for g = 1:nGroup
            ax = nexttile(tl, g);
            localPlotTrajectoryPanel(ax, plotGroups{g}, opts);
            ax = nexttile(tl, g + nGroup);
            localPlotDistancePanel(ax, plotGroups{g}, opts);
        end
end

if isfield(A, 'subject')
    title(tl, sprintf('Aggregated gaze density peak trajectory: %s', char(string(A.subject))), ...
        'Interpreter', 'none');
end

out = A;
out.plotOptions = opts;
out.plotGrouping = groupingUsed;
out.plotGroupLabels = plotLabels;
end


function opts = localDefaults(opts, A)
defaults = struct( ...
    'newFigure', true, ...
    'plotMode', 'both', ...
    'lineWidth', 1.8, ...
    'sessionLineWidth', 0.75, ...
    'markerSize', 34, ...
    'rewardMarkerSize', 11, ...
    'rewardLineWidth', 2.25, ...
    'showSessionTrajectories', true, ...
    'showSessionDistance', false, ...
    'showRewardPeak', true, ...
    'showRewardCircle', true, ...
    'showColorbar', true, ...
    'showDistanceSE', true, ...
    'distanceSEAlpha', 0.18, ...
    'showDistanceLegend', true, ...
    'rewardCircleLineStyle', ':', ...
    'rewardCircleLineWidth', 1.5, ...
    'rewardColor', [0 0 0], ...
    'trajectoryColor', [0.15 0.35 0.85], ...
    'medianDistanceColor', [0.85 0.33 0.10], ...
    'sessionColor', [0.75 0.75 0.75], ...
    'distanceMetric', 'both', ...
    'showFracWithin1sd', true, ...
    'xLabel', 'peak x position (deg)', ...
    'yLabel', 'peak y position (deg)', ...
    'trialLabel', 'trial within day', ...
    'nRows', [], ...
    'nCols', []);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(opts, names{i}) || isempty(opts.(names{i}))
        opts.(names{i}) = defaults.(names{i});
    end
end
if isfield(A, 'transform') && isfield(A.transform, 'plotRotate45') && logical(A.transform.plotRotate45)
    opts.xLabel = 'rotated peak x position (deg)';
    opts.yLabel = 'rotated peak y position (deg)';
end
end


function localValidateAggregate(A, groupingArg)
if ~isstruct(A) || ~isfield(A, 'groups') || ~iscell(A.groups)
    error('plotGazeHeatTrajectoryAggregate:BadInput', ...
        'A must be output from collectGazeHeatTrajectory.');
end
if ~isempty(groupingArg) && ~(ischar(groupingArg) || (isstring(groupingArg) && isscalar(groupingArg)))
    error('plotGazeHeatTrajectoryAggregate:BadGrouping', ...
        'groupingArg must be a text scalar, [], or omitted.');
end
if ~isempty(groupingArg) && strcmpi(strtrim(string(groupingArg)), "block")
    if ~isfield(A, 'blockGroups') || ~iscell(A.blockGroups)
        error('plotGazeHeatTrajectoryAggregate:NoBlockGroups', ...
            'A does not contain blockGroups. Re-run collectGazeHeatTrajectory with the current version.');
    end
    if isempty(A.blockGroups)
        error('plotGazeHeatTrajectoryAggregate:EmptyGroups', '%s', localEmptyGroupsMessage(A));
    end
    return
end
if ~isempty(groupingArg) && isfield(A, 'groupingArg') && ~isempty(A.groupingArg)
    requested = lower(strtrim(string(groupingArg)));
    actual = lower(strtrim(string(A.groupingArg)));
    if requested ~= actual
        error('plotGazeHeatTrajectoryAggregate:GroupingMismatch', ...
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


function [nRows, nCols] = localGrid(nGroup, groupingUsed, opts)
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
end


function localPlotTrajectoryPanel(ax, group, opts)
S = localSummary(group);
ok = localOkRows(S);
if ~any(ok)
    localNoDataAxis(ax, group, 'No trajectory windows');
    return
end
hold(ax, 'on');
if logical(opts.showSessionTrajectories)
    localPlotSessionTrajectories(ax, S, ok, opts);
end

M = localMeanTrajectory(group);
if ~isempty(M) && height(M) > 0
    x = M.peakXDeg;
    y = M.peakYDeg;
    t = M.trialCenterDay;
else
    x = S.peakXDeg(ok);
    y = S.peakYDeg(ok);
    t = S.trialCenterDay(ok);
end
scatter(ax, x, y, opts.markerSize, t, 'filled', ...
    'MarkerEdgeColor', 'none', 'HandleVisibility', 'off');

if logical(opts.showRewardCircle)
    r = localRewardRadius(group, S, ok);
    [cx, cy] = localRewardCenter(group, S, ok);
    if isfinite(r) && r > 0 && isfinite(cx) && isfinite(cy)
        theta = linspace(0, 2*pi, 241);
        plot(ax, cx + r .* cos(theta), cy + r .* sin(theta), ...
            'LineStyle', char(string(opts.rewardCircleLineStyle)), ...
            'Color', opts.rewardColor, ...
            'LineWidth', opts.rewardCircleLineWidth, ...
            'HandleVisibility', 'off');
    end
end
if logical(opts.showRewardPeak)
    [cx, cy] = localRewardCenter(group, S, ok);
    if isfinite(cx) && isfinite(cy)
        plot(ax, cx, cy, '+', 'Color', opts.rewardColor, ...
            'MarkerSize', opts.rewardMarkerSize, ...
            'LineWidth', opts.rewardLineWidth, ...
            'HandleVisibility', 'off');
    end
end
hold(ax, 'off');
axis(ax, 'image');
box(ax, 'off');
xlabel(ax, opts.xLabel);
ylabel(ax, opts.yLabel);
title(ax, localGroupTitle(group), 'Interpreter', 'none');
if logical(opts.showColorbar)
    cb = colorbar(ax);
    ylabel(cb, opts.trialLabel);
end
end


function localPlotSessionTrajectories(ax, S, ok, opts)
files = unique(string(S.fileName(ok)), 'stable');
for i = 1:numel(files)
    ii = ok & string(S.fileName) == files(i);
    if ~any(ii)
        continue
    end
    rows = find(ii);
    [~, order] = sort(S.trialCenterDay(rows));
    rows = rows(order);
    scatter(ax, S.peakXDeg(rows), S.peakYDeg(rows), max(9, round(opts.markerSize ./ 3)), ...
        opts.sessionColor, 'filled', ...
        'MarkerFaceAlpha', 0.6, ...
        'MarkerEdgeAlpha', 0.6, ...
        'HandleVisibility', 'off');
end
end


function localPlotDistancePanel(ax, group, opts)
S = localSummary(group);
ok = localOkRows(S);
if ~any(ok)
    localNoDataAxis(ax, group, 'No distance windows');
    return
end
hold(ax, 'on');
if logical(opts.showSessionDistance)
    localPlotSessionDistance(ax, S, ok, opts);
end

M = localMeanTrajectory(group);
if isempty(M) || height(M) == 0
    M = S(ok, :);
end
t = M.trialCenterDay;
metric = lower(strtrim(char(string(opts.distanceMetric))));
peakSE = localTableColumn(M, 'peakDistToRewardDegSE');
medianSE = localTableColumn(M, 'medianDistToRewardDegSE');
if isempty(peakSE)
    peakSE = localDistanceSEFromSummary(group, M, 'peakDistToRewardDeg');
end
if isempty(medianSE)
    medianSE = localDistanceSEFromSummary(group, M, 'medianDistToRewardDeg');
end
switch metric
    case {'peak', 'peakdist', 'peakdistance'}
        localPlotDistanceSE(ax, t, M.peakDistToRewardDeg, peakSE, opts.trajectoryColor, opts);
        plot(ax, t, M.peakDistToRewardDeg, '-o', ...
            'Color', opts.trajectoryColor, ...
            'LineWidth', opts.lineWidth, ...
            'DisplayName', 'density peak');
    case {'median', 'gaze', 'mediandist', 'mediandistance'}
        localPlotDistanceSE(ax, t, M.medianDistToRewardDeg, medianSE, opts.medianDistanceColor, opts);
        plot(ax, t, M.medianDistToRewardDeg, '-s', ...
            'Color', opts.medianDistanceColor, ...
            'LineWidth', opts.lineWidth, ...
            'DisplayName', 'median gaze');
    otherwise
        localPlotDistanceSE(ax, t, M.peakDistToRewardDeg, peakSE, opts.trajectoryColor, opts);
        localPlotDistanceSE(ax, t, M.medianDistToRewardDeg, medianSE, opts.medianDistanceColor, opts);
        plot(ax, t, M.peakDistToRewardDeg, '-o', ...
            'Color', opts.trajectoryColor, ...
            'LineWidth', opts.lineWidth, ...
            'DisplayName', 'density peak');
        plot(ax, t, M.medianDistToRewardDeg, '-s', ...
            'Color', opts.medianDistanceColor, ...
            'LineWidth', opts.lineWidth, ...
            'DisplayName', 'median gaze');
end
yyaxis(ax, 'right');
if logical(opts.showFracWithin1sd) && ismember('fracWithin1sd', M.Properties.VariableNames)
    rightColor = ax.YAxis(2).Color;
    plot(ax, t, M.fracWithin1sd, ':', ...
        'Color', rightColor, ...
        'LineWidth', opts.lineWidth, ...
        'DisplayName', 'frac within 1 SD');
    ylabel(ax, 'fraction within 1 SD');
    ylim(ax, [0 0.4]);
end
yyaxis(ax, 'left');
hold(ax, 'off');
box(ax, 'off');
xlabel(ax, opts.trialLabel);
ylabel(ax, 'distance to reward center (deg)');
title(ax, sprintf('%s distance', char(string(group.groupLabel))), 'Interpreter', 'none');
if logical(opts.showDistanceLegend)
    legend(ax, 'Location', 'best', 'Interpreter', 'none');
end
end


function localPlotDistanceSE(ax, x, y, se, color, opts)
if ~logical(opts.showDistanceSE) || isempty(se)
    return
end
x = double(x(:));
y = double(y(:));
se = double(se(:));
n = min([numel(x), numel(y), numel(se)]);
x = x(1:n);
y = y(1:n);
se = se(1:n);
keep = isfinite(x) & isfinite(y) & isfinite(se) & se >= 0;
if nnz(keep) < 2
    return
end
x = x(keep);
y = y(keep);
se = se(keep);
[x, order] = sort(x);
y = y(order);
se = se(order);
patch(ax, [x; flipud(x)], [y - se; flipud(y + se)], color, ...
    'FaceAlpha', opts.distanceSEAlpha, ...
    'EdgeColor', 'none', ...
    'HandleVisibility', 'off');
end


function values = localTableColumn(T, name)
values = [];
if istable(T) && ismember(name, T.Properties.VariableNames)
    values = T.(name);
end
end


function se = localDistanceSEFromSummary(group, M, fieldName)
se = [];
S = localSummary(group);
if isempty(S) || height(S) == 0 || isempty(M) || height(M) == 0 || ...
        ~ismember(fieldName, S.Properties.VariableNames)
    return
end
fieldValues = S.(fieldName);
ok = localOkRows(S) & isfinite(S.trialCenterDay) & isfinite(fieldValues);
if ~any(ok)
    return
end
centers = double(M.trialCenterDay(:));
if isempty(centers) || any(~isfinite(centers))
    return
end
[centersSorted, order] = sort(centers);
edges = localCenterEdges(centersSorted);
seSorted = NaN(size(centersSorted));
x = double(S.trialCenterDay(ok));
y = double(fieldValues(ok));
for i = 1:numel(centersSorted)
    if i == numel(centersSorted)
        ii = x >= edges(i) & x <= edges(i + 1);
    else
        ii = x >= edges(i) & x < edges(i + 1);
    end
    seSorted(i) = localStandardError(y(ii));
end
se = NaN(size(seSorted));
se(order) = seSorted;
end


function edges = localCenterEdges(centers)
centers = double(centers(:));
if numel(centers) == 1
    edges = [centers(1) - 0.5; centers(1) + 0.5];
    return
end
midpoints = centers(1:end-1) + diff(centers) ./ 2;
firstWidth = max(eps, midpoints(1) - centers(1));
lastWidth = max(eps, centers(end) - midpoints(end));
edges = [centers(1) - firstWidth; midpoints; centers(end) + lastWidth];
end


function value = localStandardError(values)
values = double(values(:));
values = values(isfinite(values));
n = numel(values);
if n < 2
    value = NaN;
else
    value = std(values, 0, 'omitnan') ./ sqrt(n);
end
end


function localPlotSessionDistance(ax, S, ok, opts)
files = unique(string(S.fileName(ok)), 'stable');
for i = 1:numel(files)
    ii = ok & string(S.fileName) == files(i);
    if ~any(ii)
        continue
    end
    rows = find(ii);
    [~, order] = sort(S.trialCenterDay(rows));
    rows = rows(order);
    plot(ax, S.trialCenterDay(rows), S.peakDistToRewardDeg(rows), '-', ...
        'Color', opts.sessionColor, ...
        'LineWidth', opts.sessionLineWidth, ...
        'HandleVisibility', 'off');
end
end


function S = localSummary(group)
if isstruct(group) && isfield(group, 'summary') && istable(group.summary)
    S = group.summary;
else
    S = table();
end
end


function M = localMeanTrajectory(group)
if isstruct(group) && isfield(group, 'meanTrajectory') && istable(group.meanTrajectory)
    M = group.meanTrajectory;
else
    M = table();
end
end


function ok = localOkRows(S)
ok = false(height(S), 1);
need = {'status','trialCenterDay','peakXDeg','peakYDeg'};
if isempty(S) || ~all(ismember(need, S.Properties.VariableNames))
    return
end
ok = strcmp(string(S.status), "ok") & ...
    isfinite(S.trialCenterDay) & isfinite(S.peakXDeg) & isfinite(S.peakYDeg);
end


function [cx, cy] = localRewardCenter(group, S, ok)
cx = NaN;
cy = NaN;
if isstruct(group) && isfield(group, 'rewardPeakDeg') && numel(group.rewardPeakDeg) >= 2 && ...
        all(isfinite(group.rewardPeakDeg(1:2)))
    cx = group.rewardPeakDeg(1);
    cy = group.rewardPeakDeg(2);
    return
end
if any(ok) && all(ismember({'rewardXDeg','rewardYDeg'}, S.Properties.VariableNames))
    cx = median(S.rewardXDeg(ok), 'omitnan');
    cy = median(S.rewardYDeg(ok), 'omitnan');
end
end


function r = localRewardRadius(group, S, ok)
r = NaN;
if isstruct(group) && isfield(group, 'rewardRadius1sdDeg') && isfinite(group.rewardRadius1sdDeg)
    r = group.rewardRadius1sdDeg;
    return
end
if any(ok) && ismember('rewardRadius1sdDeg', S.Properties.VariableNames)
    r = median(S.rewardRadius1sdDeg(ok), 'omitnan');
end
end


function titleText = localGroupTitle(group)
label = "group";
if isstruct(group) && isfield(group, 'groupLabel')
    label = string(group.groupLabel);
end
nWin = 0;
nSess = 0;
if isstruct(group)
    if isfield(group, 'nOkWindows')
        nWin = group.nOkWindows;
    end
    if isfield(group, 'nSessions')
        nSess = group.nSessions;
    end
end
titleText = sprintf('%s | n=%d windows, %d sessions', char(label), nWin, nSess);
end


function localNoDataAxis(ax, group, message)
axis(ax, 'off');
label = "group";
if isstruct(group) && isfield(group, 'groupLabel')
    label = string(group.groupLabel);
end
text(ax, 0.5, 0.5, sprintf('%s\n%s', char(label), message), ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', ...
    'Interpreter', 'none');
end


function msg = localEmptyGroupsMessage(A)
msg = "No aggregate gaze-heat-trajectory groups were available to plot.";
if ~isstruct(A)
    msg = msg + " Input was not a collectGazeHeatTrajectory output struct.";
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
