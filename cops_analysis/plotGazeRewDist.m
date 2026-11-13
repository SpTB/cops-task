function out = plotGazeRewDist(in, trialNo, opts)
% plotGazeRewDist  Plot median gaze distance to reward with target references.
%
%   plotGazeRewDist(ex)
%   plotGazeRewDist(ex, 1:120, opts)
%   plotGazeRewDist(T)
%
% This is a focused distance-only view for gazeHeatTrajectory output. It
% plots median gaze distance to the reward center and two reference curves:
% perfect tracking of the reward-closer target and random target selection.
% Set opts.diff=true to plot only median gaze minus reward-closer target.

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
    error('plotGazeRewDist:BadOpts', 'opts must be a struct.');
end

opts = localDefaults(opts);
if localLooksLikeTrajectory(in)
    out = in;
else
    out = gazeHeatTrajectory(in, trialNo, opts);
end

S = out.summary;
if isempty(S) || height(S) == 0
    error('plotGazeRewDist:EmptySummary', 'Trajectory output has no summary rows.');
end
localRequireReferenceColumns(S);
ok = strcmp(string(S.status), "ok") & isfinite(S.medianDistToRewardDeg);
if ~any(ok)
    error('plotGazeRewDist:NoValidWindows', 'No valid distance windows were available to plot.');
end

if opts.newFigure
    figure;
end
ax = gca;
hold(ax, 'on');
t = localTrialCenterForPlot(S, ok);
if logical(opts.diff)
    y = S.medianDistToRewardDeg(ok) - S.rewardCloserTargetDistDeg(ok);
    plot(ax, t, y, '-o', ...
        'Color', opts.diffColor, ...
        'LineWidth', opts.lineWidth, ...
        'MarkerSize', opts.markerSize, ...
        'DisplayName', 'median gaze - reward-closer target');
    yline(ax, 0, ':', 'HandleVisibility', 'off');
else
    plot(ax, t, S.medianDistToRewardDeg(ok), '-o', ...
        'Color', opts.medianGazeColor, ...
        'LineWidth', opts.lineWidth, ...
        'MarkerSize', opts.markerSize, ...
        'DisplayName', 'median gaze');
    plot(ax, t, S.rewardCloserTargetDistDeg(ok), char(string(opts.rewardCloserLineStyle)), ...
        'Color', opts.rewardCloserColor, ...
        'LineWidth', opts.referenceLineWidth, ...
        'DisplayName', 'reward-closer target');
    plot(ax, t, S.randomTargetDistDeg(ok), char(string(opts.randomTargetLineStyle)), ...
        'Color', opts.randomTargetColor, ...
        'LineWidth', opts.referenceLineWidth, ...
        'DisplayName', 'random target');
end
hold(ax, 'off');
box(ax, 'off');
xlabel(ax, 'selected trial');
if logical(opts.diff)
    ylabel(ax, 'excess distance over reward-closer target (deg)');
    title(ax, 'Gaze distance above reward-closer target', 'Interpreter', 'none');
else
    ylabel(ax, 'distance to reward center (deg)');
    title(ax, 'Gaze distance to reward', 'Interpreter', 'none');
end
if logical(opts.showLegend)
    legend(ax, 'Location', char(string(opts.legendLocation)), 'Interpreter', 'none');
end

out.plotOptions = opts;
end


function opts = localDefaults(opts)
defaults = struct( ...
    'newFigure', true, ...
    'diff', false, ...
    'lineWidth', 1.6, ...
    'referenceLineWidth', 1.5, ...
    'markerSize', 5, ...
    'medianGazeColor', [0.85 0.33 0.10], ...
    'diffColor', [0.15 0.35 0.85], ...
    'rewardCloserColor', [0 0 0], ...
    'randomTargetColor', [0.35 0.35 0.35], ...
    'rewardCloserLineStyle', ':', ...
    'randomTargetLineStyle', '--', ...
    'showLegend', true, ...
    'legendLocation', 'northeastoutside');
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(opts, names{i}) || isempty(opts.(names{i}))
        opts.(names{i}) = defaults.(names{i});
    end
end
end


function localRequireReferenceColumns(S)
required = {'rewardCloserTargetDistDeg', 'randomTargetDistDeg'};
missing = required(~ismember(required, S.Properties.VariableNames));
if ~isempty(missing)
    error('plotGazeRewDist:MissingReferenceDistances', ...
        'Trajectory output lacks %s. Re-run gazeHeatTrajectory with the current version.', ...
        strjoin(missing, ', '));
end
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
