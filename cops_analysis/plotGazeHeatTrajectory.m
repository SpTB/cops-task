function out = plotGazeHeatTrajectory(in, trialNo, opts)
% plotGazeHeatTrajectory  Plot output from gazeHeatTrajectory.
%
%   plotGazeHeatTrajectory(ex)
%   plotGazeHeatTrajectory(ex, 1:120, opts)
%   plotGazeHeatTrajectory(T)
%
% The left panel shows the rolling density-peak trajectory in visual
% degrees. The right panel shows distance-to-reward over trial windows.

if nargin < 2 || isempty(trialNo)
    trialNo = [];
end
if nargin < 3 || isempty(opts)
    if isstruct(trialNo) && ~localLooksLikeTrialArg(trialNo)
        opts = trialNo;
        trialNo = [];
    else
        opts = struct();
    end
elseif ~isstruct(opts)
    error('plotGazeHeatTrajectory:BadOpts', 'opts must be a struct.');
end

opts = localDefaults(opts);
if localLooksLikeTrajectory(in)
    out = in;
else
    out = gazeHeatTrajectory(in, trialNo, opts);
end

S = out.summary;
if isempty(S) || height(S) == 0
    error('plotGazeHeatTrajectory:EmptySummary', 'Trajectory output has no summary rows.');
end
ok = strcmp(string(S.status), "ok") & isfinite(S.peakXDeg) & isfinite(S.peakYDeg);
if ~any(ok)
    error('plotGazeHeatTrajectory:NoValidWindows', 'No valid trajectory windows were available to plot.');
end

if opts.newFigure
    figure;
end
tl = tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

ax1 = nexttile(tl, 1);
localPlotTrajectoryPanel(ax1, S, ok, opts);

ax2 = nexttile(tl, 2);
localPlotDistancePanel(ax2, S, ok, opts);

if isfield(out, 'transform') && (out.transform.alignRewardToTopLeft || out.transform.plotRotate45)
    title(tl, 'Gaze density peak trajectory (transformed coordinates)', 'Interpreter', 'none');
else
    title(tl, 'Gaze density peak trajectory', 'Interpreter', 'none');
end

out.plotOptions = opts;
end


function opts = localDefaults(opts)
defaults = struct( ...
    'newFigure', true, ...
    'lineWidth', 1.5, ...
    'markerSize', 38, ...
    'rewardMarkerSize', 11, ...
    'rewardLineWidth', 2.25, ...
    'showRewardPeak', true, ...
    'showRewardCircle', true, ...
    'rewardCircleLineStyle', ':', ...
    'rewardCircleLineWidth', 1.5, ...
    'rewardColor', [0 0 0], ...
    'trajectoryColor', [0.15 0.35 0.85], ...
    'distanceMetric', 'both', ...
    'showDotColorLegend', true, ...
    'showFracWithin1sd', true);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(opts, names{i}) || isempty(opts.(names{i}))
        opts.(names{i}) = defaults.(names{i});
    end
end
end


function localPlotTrajectoryPanel(ax, S, ok, opts)
hold(ax, 'on');
x = S.peakXDeg(ok);
y = S.peakYDeg(ok);
t = localTrialCenterForPlot(S, ok);
scatter(ax, x, y, opts.markerSize, t, 'filled', ...
    'MarkerEdgeColor', 'none', ...
    'HandleVisibility', 'off');
if opts.showRewardCircle
    r = median(S.rewardRadius1sdDeg(ok), 'omitnan');
    cx = median(S.rewardXDeg(ok), 'omitnan');
    cy = median(S.rewardYDeg(ok), 'omitnan');
    if isfinite(r) && r > 0 && isfinite(cx) && isfinite(cy)
        theta = linspace(0, 2*pi, 241);
        plot(ax, cx + r .* cos(theta), cy + r .* sin(theta), ...
            'LineStyle', char(string(opts.rewardCircleLineStyle)), ...
            'Color', opts.rewardColor, ...
            'LineWidth', opts.rewardCircleLineWidth, ...
            'HandleVisibility', 'off');
    end
end
if opts.showRewardPeak
    cx = median(S.rewardXDeg(ok), 'omitnan');
    cy = median(S.rewardYDeg(ok), 'omitnan');
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
xlabel(ax, 'peak x position (deg)');
ylabel(ax, 'peak y position (deg)');
title(ax, 'Density peak trajectory');
if logical(opts.showDotColorLegend)
    cb = colorbar(ax);
    ylabel(cb, 'selected trial center');
end
end


function localPlotDistancePanel(ax, S, ok, opts)
hold(ax, 'on');
t = localTrialCenterForPlot(S, ok);
mode = lower(strtrim(char(string(opts.distanceMetric))));
switch mode
    case {'peak', 'peakdist', 'peakdistance'}
        plot(ax, t, S.peakDistToRewardDeg(ok), '-o', ...
            'LineWidth', opts.lineWidth, 'DisplayName', 'density peak');
    case {'median', 'gaze', 'mediandist', 'mediandistance'}
        plot(ax, t, S.medianDistToRewardDeg(ok), '-o', ...
            'LineWidth', opts.lineWidth, 'DisplayName', 'median gaze');
    otherwise
        plot(ax, t, S.peakDistToRewardDeg(ok), '-o', ...
            'LineWidth', opts.lineWidth, 'DisplayName', 'density peak');
        plot(ax, t, S.medianDistToRewardDeg(ok), '-s', ...
            'LineWidth', opts.lineWidth, 'DisplayName', 'median gaze');
end
yyaxis(ax, 'right');
if logical(opts.showFracWithin1sd)
    rightColor = ax.YAxis(2).Color;
    plot(ax, t, S.fracWithin1sd(ok), ':', ...
        'Color', rightColor, ...
        'LineWidth', opts.lineWidth, 'DisplayName', 'frac within 1 SD');
    ylabel(ax, 'fraction within 1 SD');
    ylim(ax, [0 0.4]);
end
yyaxis(ax, 'left');
hold(ax, 'off');
box(ax, 'off');
xlabel(ax, 'selected trial');
ylabel(ax, 'distance to reward center (deg)');
title(ax, 'Distance to reward');
end


function t = localTrialCenterForPlot(S, ok)
if ismember('trialCenterSelected', S.Properties.VariableNames)
    t = S.trialCenterSelected(ok);
else
    t = S.trialCenter(ok);
end
end


function tf = localLooksLikeTrajectory(value)
tf = isstruct(value) && isfield(value, 'summary') && istable(value.summary);
end


function tf = localLooksLikeTrialArg(value)
tf = isnumeric(value) || islogical(value) || ischar(value) || isstring(value) || iscell(value);
end
