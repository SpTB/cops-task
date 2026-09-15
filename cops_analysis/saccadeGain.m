function out = saccadeGain(ex, mode, opts)
% saccadeGain  Estimate target-aligned saccade under/overshoot.
%
%   out = saccadeGain(ex)
%   out = saccadeGain(ex, 'clo')
%   out = saccadeGain(ex, 'vis')
%   out = saccadeGain(ex, mode, opts)
%
% Modes:
%   'all'  all usable saccades in one group (default)
%   'clo'  selected target is closer to versus further from reward
%   'vis'  group by target visibility
%
% This function reuses saccadeCorrectiveness for saccade detection and
% target selection. By default, the reference target is sampled at saccade
% landing (targetLeadSec = 0) and targetMode = 'any'.
%
% Axial gain and signed error are:
%   axialGain     = projected movement toward target / initial target error
%   axialErrorDeg = projected movement toward target - initial target error
%
% gain < 1 and error < 0 indicate undershoot; gain > 1 and error > 0
% indicate overshoot.

if nargin < 2 || isempty(mode)
    mode = 'all';
elseif isstruct(mode)
    if nargin >= 3 && ~isempty(opts)
        error('saccadeGain:BadInput', ...
            'When the second argument is opts, do not provide a third argument.');
    end
    opts = mode;
    mode = 'all';
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
if ~isstruct(opts)
    error('saccadeGain:BadOpts', 'opts must be a struct.');
end
if ~isstruct(ex) || ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('saccadeGain:BadInput', 'First input must be an ex struct with Trials.');
end
mode = validatestring(lower(strtrim(char(string(mode)))), {'all','clo','vis'});

defaults = struct( ...
    'targetMode', 'any', ...
    'targetLeadSec', 0, ...
    'minDirectionCosine', 0.8, ...
    'minPreErrorDeg', 0, ...
    'plot', true, ...
    'newFigure', true);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field) || isempty(opts.(field))
        opts.(field) = defaults.(field);
    end
end

correctivenessOpts = opts;
correctivenessOpts.plot = false;
switch mode
    case 'vis'
        correctiveness = saccadeCorrectiveness(ex, 'vis', correctivenessOpts);
    otherwise
        correctiveness = saccadeCorrectiveness(ex, [], correctivenessOpts);
end

saccades = correctiveness.saccades;
if isempty(saccades)
    out = localEmptyOutput(mode, opts, correctiveness);
    warning('saccadeGain:NoSaccades', 'No saccades were detected.');
    return
end
saccades = localAddGainMetrics(saccades, ex);

minDirectionCosine = double(localFirstScalar(opts.minDirectionCosine));
if ~isfinite(minDirectionCosine)
    minDirectionCosine = 0.8;
end
minPreErrorDeg = double(localFirstScalar(opts.minPreErrorDeg));
if ~(isfinite(minPreErrorDeg) && minPreErrorDeg >= 0)
    minPreErrorDeg = 0;
end
keep = isfinite(saccades.axialGain) & isfinite(saccades.axialErrorDeg) & ...
    isfinite(saccades.preErrDeg) & saccades.preErrDeg > minPreErrorDeg & ...
    isfinite(saccades.directionCosine) & ...
    saccades.directionCosine > minDirectionCosine;

switch mode
    case 'clo'
        className = string(saccades.selectedTargetCloseness);
        keep = keep & (className == "closer" | className == "further");
        groupLevels = ["closer", "further"];
        groupName = className;
    case 'vis'
        visibility = double(saccades.targetVisibility);
        keep = keep & isfinite(visibility);
        levels = sort(unique(visibility(keep)), 'descend');
        groupLevels = "vis=" + string(levels(:));
        groupName = strings(height(saccades), 1);
        for i = 1:numel(levels)
            groupName(visibility == levels(i)) = groupLevels(i);
        end
    otherwise
        groupLevels = "all";
        groupName = repmat("all", height(saccades), 1);
end

gainSaccades = saccades(keep, :);
if isempty(gainSaccades)
    out = localEmptyOutput(mode, opts, correctiveness);
    out.saccades = saccades;
    warning('saccadeGain:NoUsableSaccades', ...
        'No saccades passed the target-direction and grouping criteria.');
    return
end
gainSaccades.gainGroup = categorical(groupName(keep), groupLevels, 'Ordinal', true);
summary = localSummarizeGain(gainSaccades, groupLevels);

out = struct();
out.mode = string(mode);
out.saccades = saccades;
out.gainSaccades = gainSaccades;
out.summary = summary;
out.groupLabels = groupLevels;
out.options = opts;
out.correctiveness = correctiveness;
out.figure = gobjects(0);
if logical(opts.plot)
    out.figure = localPlotGain(gainSaccades, groupLevels, mode, opts);
end
end


function saccades = localAddGainMetrics(saccades, ex)
n = height(saccades);
saccades.preErrDeg = px2deg(double(saccades.preErrPx), ex.setup);
saccades.axialGain = double(saccades.projTowardTargetPx) ./ double(saccades.preErrPx);
saccades.axialErrorPx = ...
    double(saccades.projTowardTargetPx) - double(saccades.preErrPx);
saccades.axialErrorDeg = px2deg(saccades.axialErrorPx, ex.setup);
saccades.rewardCenterX = NaN(n, 1);
saccades.rewardCenterY = NaN(n, 1);
saccades.rewardCloserTargetId = NaN(n, 1);
saccades.selectedRewardDistPx = NaN(n, 1);
saccades.otherRewardDistPx = NaN(n, 1);
saccades.selectedTargetCloseness = strings(n, 1);
saccades.selectedTargetCloseness(:) = missing;

for i = 1:n
    trialNo = double(saccades.trial(i));
    step = round(double(saccades.targetRefStep(i)));
    if ~(isfinite(trialNo) && trialNo >= 1 && trialNo <= numel(ex.Trials) && ...
            isfinite(step))
        continue
    end
    T = ex.Trials(trialNo);
    [targetIds, targetXY] = localTargetsAtStep(T, step);
    if size(targetXY, 1) < 2
        continue
    end
    rewardCenter = localRewardCenter(ex, T);
    if any(~isfinite(rewardCenter))
        continue
    end
    distance = hypot( ...
        targetXY(:, 1) - rewardCenter(1), ...
        targetXY(:, 2) - rewardCenter(2));
    [sortedDistance, order] = sort(distance, 'ascend');
    if numel(sortedDistance) < 2 || ~all(isfinite(sortedDistance(1:2))) || ...
            sortedDistance(1) == sortedDistance(2)
        continue
    end
    closerId = targetIds(order(1));
    selectedId = double(saccades.selectedTargetId(i));
    selectedIndex = find(targetIds == selectedId, 1, 'first');
    otherIndex = find(targetIds ~= selectedId, 1, 'first');
    if isempty(selectedIndex) || isempty(otherIndex)
        continue
    end
    saccades.rewardCenterX(i) = rewardCenter(1);
    saccades.rewardCenterY(i) = rewardCenter(2);
    saccades.rewardCloserTargetId(i) = closerId;
    saccades.selectedRewardDistPx(i) = distance(selectedIndex);
    saccades.otherRewardDistPx(i) = distance(otherIndex);
    if selectedId == closerId
        saccades.selectedTargetCloseness(i) = "closer";
    else
        saccades.selectedTargetCloseness(i) = "further";
    end
end
end


function [targetIds, targetXY] = localTargetsAtStep(T, step)
targetIds = zeros(0, 1);
targetXY = zeros(0, 2);
if ~isfield(T, 'targetPositions') || isempty(T.targetPositions)
    return
end
step = max(1, min(numel(T.targetPositions), step));
tp = T.targetPositions(step);
targets = {'targ1', 'targ2'};
for i = 1:numel(targets)
    name = targets{i};
    if isfield(tp, name) && isfield(tp.(name), 'pos_abs')
        pos = double(tp.(name).pos_abs(:)');
        if numel(pos) >= 2 && all(isfinite(pos(1:2)))
            targetIds(end + 1, 1) = i; %#ok<AGROW>
            targetXY(end + 1, :) = pos(1:2); %#ok<AGROW>
        end
    end
end
end


function center = localRewardCenter(ex, T)
center = [NaN NaN];
try
    value = double(getGaussianCenterPx(ex, T));
    value = value(:)';
    if numel(value) >= 2 && all(isfinite(value(1:2)))
        center = value(1:2);
    end
catch
end
end


function summary = localSummarizeGain(S, groupLevels)
rows = cell(numel(groupLevels), 1);
nRows = 0;
for i = 1:numel(groupLevels)
    keep = string(S.gainGroup) == groupLevels(i);
    if ~any(keep)
        continue
    end
    G = S(keep, :);
    nRows = nRows + 1;
    rows{nRows} = table( ...
        categorical(groupLevels(i), groupLevels, 'Ordinal', true), ...
        height(G), numel(unique(G.trial)), ...
        mean(G.axialGain, 'omitnan'), median(G.axialGain, 'omitnan'), ...
        mean(G.axialErrorDeg, 'omitnan'), median(G.axialErrorDeg, 'omitnan'), ...
        mean(double(G.axialGain < 1), 'omitnan'), ...
        mean(double(G.axialGain > 1), 'omitnan'), ...
        'VariableNames', { ...
            'gainGroup','nSaccades','nTrials','gainMean','gainMedian', ...
            'axialErrorMeanDeg','axialErrorMedianDeg', ...
            'undershootFrac','overshootFrac'});
end
summary = vertcat(rows{1:nRows});
end


function fig = localPlotGain(S, groupLevels, mode, opts)
if logical(opts.newFigure)
    fig = figure;
else
    fig = gcf;
end
tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
colors = lines(max(1, numel(groupLevels)));

nexttile;
hold on
for i = 1:numel(groupLevels)
    keep = string(S.gainGroup) == groupLevels(i);
    if any(keep)
        boxchart(i .* ones(sum(keep), 1), S.axialGain(keep), ...
            'BoxFaceColor', colors(i, :));
    end
end
yline(1, '--k', 'gain = 1');
xlim([0.5 numel(groupLevels) + 0.5]);
xticks(1:numel(groupLevels));
xticklabels(cellstr(groupLevels));
xlabel(localGroupAxisLabel(mode));
ylabel('Axial saccade gain');
title('Saccade gain');
grid on

nexttile;
hold on
for i = 1:numel(groupLevels)
    keep = string(S.gainGroup) == groupLevels(i);
    if any(keep)
        boxchart(i .* ones(sum(keep), 1), S.axialErrorDeg(keep), ...
            'BoxFaceColor', colors(i, :));
    end
end
yline(0, '--k', 'accurate');
xlim([0.5 numel(groupLevels) + 0.5]);
xticks(1:numel(groupLevels));
xticklabels(cellstr(groupLevels));
xlabel(localGroupAxisLabel(mode));
ylabel('Axial endpoint error (deg)');
title('Under/overshoot');
grid on

sgtitle(sprintf( ...
    'Target-aligned saccade gain (%s; n = %d saccades)', ...
    mode, height(S)), 'Interpreter', 'none');
end


function label = localGroupAxisLabel(mode)
switch mode
    case 'clo'
        label = 'Selected target relative to reward';
    case 'vis'
        label = 'Target visibility';
    otherwise
        label = 'All usable saccades';
end
end


function out = localEmptyOutput(mode, opts, correctiveness)
out = struct();
out.mode = string(mode);
out.saccades = table();
out.gainSaccades = table();
out.summary = table();
out.groupLabels = strings(0, 1);
out.options = opts;
out.correctiveness = correctiveness;
out.figure = gobjects(0);
end


function value = localFirstScalar(x)
value = NaN;
if isempty(x) || ~isnumeric(x)
    return
end
x = double(x(:));
idx = find(isfinite(x), 1, 'first');
if ~isempty(idx)
    value = x(idx);
end
end
