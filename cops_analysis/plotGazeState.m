function out = plotGazeState(ex, trialNo, opts)
% plotGazeState  Plot gaze-state classification for one trial or trial groups.
%
%   plotGazeState(ex, 10)
%   plotGazeState(ex, 1:120)
%   plotGazeState(ex, 'bg')
%   plotGazeState(ex, {'bg','vis'})
%   plotGazeState(ex, [], opts)
%
% Useful opts fields passed through to classifyGazeState include:
%   .timeWindowSec         [tMin tMax] in trial-relative seconds
%   .truncateTrialFromStep scalar minimum step to keep
%   .onlyGoState           default true
%   .speedThreshDegPerSec
%   .minAmpDeg
%   .minDurSec
%   .maxDurSec
%   .smoothFrames
%
% Scalar numeric trialNo:
%   plots x/y trajectories plus a samplewise state strip for one trial.
%
% Non-scalar or named grouping:
%   plots stacked fractions of fixation / smooth pursuit / saccade.

if nargin < 2 || isempty(trialNo)
    trialNo = [];
end
if nargin >= 2 && isstruct(trialNo) && (nargin < 3 || isempty(opts))
    opts = trialNo;
    trialNo = [];
elseif nargin < 3 || isempty(opts)
    opts = struct();
end

defaults = struct( ...
    'newFigure', true, ...
    'lineWidth', 1.25, ...
    'gazeColor', [0 0.45 0.74], ...
    'target1Color', [0 0 0], ...
    'target2Color', [0.85 0.33 0.10], ...
    'positionUnits', 'deg', ...
    'stateColors', [0.65 0.65 0.65; 0.20 0.60 0.20; 0.85 0.35 0.10], ...
    'showLegend', true);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field)
        opts.(field) = defaults.(field);
    end
end

if localIsScalarTrial(trialNo)
    out = localPlotSingleTrial(ex, double(trialNo), opts);
else
    out = localPlotGroupedSummary(ex, trialNo, opts);
end
end


function out = localPlotSingleTrial(ex, trialNo, opts)
G = classifyGazeState(ex, trialNo, opts);
S = G.samples;
if isempty(S)
    error('plotGazeState:EmptyTrial', 'No samples available for trial %d.', trialNo);
end

[gazeX, gazeY, target1X, target1Y, target2X, target2Y, unitLabel] = localPositionSeriesForPlot(ex, S, opts);

if opts.newFigure
    figure;
end
tiledlayout(3, 1, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
localPlotAxisTrace(S.tRelSec, gazeX, target1X, target2X, ...
    any(isfinite(S.target2X) & isfinite(S.target2Y)), ...
    sprintf('X Position (%s)', unitLabel), opts);
title(sprintf('Trial %d', trialNo), 'Interpreter', 'none');

nexttile;
localPlotAxisTrace(S.tRelSec, gazeY, target1Y, target2Y, ...
    any(isfinite(S.target2X) & isfinite(S.target2Y)), ...
    sprintf('Y Position (%s)', unitLabel), opts);

nexttile;
localPlotStateStrip(S.tRelSec, S.state, opts);
ylim([0.5 3.5]);
yticks([1 2 3]);
yticklabels({'fix', 'pursuit', 'sacc'});
xlabel('Trial Time (s)');
ylabel('State');
title(sprintf('Fix %.2f | Pursuit %.2f | Sacc %.2f', ...
    G.summary.fixationFrac, G.summary.smoothPursuitFrac, G.summary.saccadeFrac), ...
    'Interpreter', 'none');

out = G;
end


function out = localPlotGroupedSummary(ex, trialNo, opts)
[trialGroups, groupLabels] = localResolveTrialGroups(ex, trialNo);
allTrials = unique([trialGroups{:}]);
G = classifyGazeState(ex, allTrials, opts);

nGroups = numel(trialGroups);
M = NaN(nGroups, 3);
for g = 1:nGroups
    keep = ismember(G.summary.trial, trialGroups{g});
    if any(keep)
        M(g, 1) = mean(G.summary.fixationFrac(keep), 'omitnan');
        M(g, 2) = mean(G.summary.smoothPursuitFrac(keep), 'omitnan');
        M(g, 3) = mean(G.summary.saccadeFrac(keep), 'omitnan');
    end
end

if opts.newFigure
    figure;
end
h = bar(M, 'stacked');
for i = 1:min(numel(h), size(opts.stateColors, 1))
    h(i).FaceColor = opts.stateColors(i, :);
end
ylim([0 1]);
ylabel('Fraction of Valid Samples');
xticks(1:nGroups);
xticklabels(groupLabels);
xtickangle(25);
if opts.showLegend
    legend({'Fixation', 'Smooth pursuit', 'Saccade'}, 'Location', 'best');
end
box off

out = G;
out.groupLabels = groupLabels(:);
out.groupFractions = array2table(M, ...
    'VariableNames', {'fixationFrac','smoothPursuitFrac','saccadeFrac'});
out.groupFractions.groupLabel = string(groupLabels(:));
out.groupFractions = movevars(out.groupFractions, 'groupLabel', 'Before', 1);
end


function localPlotAxisTrace(tSec, gazePos, target1Pos, target2Pos, hasTarget2, yLabelText, opts)
plot(tSec, target1Pos, 'Color', opts.target1Color, 'LineWidth', opts.lineWidth);
hold on
if hasTarget2
    plot(tSec, target2Pos, '--', 'Color', opts.target2Color, 'LineWidth', opts.lineWidth);
end
plot(tSec, gazePos, 'Color', opts.gazeColor, 'LineWidth', opts.lineWidth);
ylabel(yLabelText);
if opts.showLegend
    if hasTarget2
        legend({'Target 1', 'Target 2', 'Gaze'}, 'Location', 'best');
    else
        legend({'Target', 'Gaze'}, 'Location', 'best');
    end
end
box off
end


function localPlotStateStrip(tSec, state, opts)
hold on
plot([tSec(1), tSec(end)], [0, 0], 'w');
stairs(tSec, double(state), 'Color', [0.25 0.25 0.25], 'LineWidth', 1);
stateCodes = [1 2 3];
for i = 1:numel(stateCodes)
    code = stateCodes(i);
    mask = state == code;
    if any(mask)
        scatter(tSec(mask), repmat(code, sum(mask), 1), 18, ...
            repmat(opts.stateColors(i, :), sum(mask), 1), 'filled');
    end
end
yline(0, ':', 'Color', [0.7 0.7 0.7]);
box off
end


function [gazeX, gazeY, target1X, target1Y, target2X, target2Y, unitLabel] = localPositionSeriesForPlot(ex, S, opts)
unitChoice = lower(strtrim(char(string(opts.positionUnits))));
switch unitChoice
    case 'px'
        gazeX = S.xPx;
        gazeY = S.yPx;
        target1X = S.targetX;
        target1Y = S.targetY;
        target2X = S.target2X;
        target2Y = S.target2Y;
        unitLabel = 'px';
    case 'deg'
        [x0, y0] = localReferenceCenterPx(ex);
        gazeX = px2deg(S.xPx - x0, ex.setup);
        gazeY = px2deg(S.yPx - y0, ex.setup);
        target1X = px2deg(S.targetX - x0, ex.setup);
        target1Y = px2deg(S.targetY - y0, ex.setup);
        target2X = px2deg(S.target2X - x0, ex.setup);
        target2Y = px2deg(S.target2Y - y0, ex.setup);
        unitLabel = 'deg';
    otherwise
        error('plotGazeState:BadPositionUnits', ...
            'opts.positionUnits must be ''px'' or ''deg''.');
end
end


function [x0, y0] = localReferenceCenterPx(ex)
if isfield(ex, 'fix') && isfield(ex.fix, 'PCtr') && numel(ex.fix.PCtr) >= 2 && all(isfinite(ex.fix.PCtr(1:2)))
    x0 = double(ex.fix.PCtr(1));
    y0 = double(ex.fix.PCtr(2));
    return
end
if isfield(ex, 'setup') && isfield(ex.setup, 'screenRect') && numel(ex.setup.screenRect) >= 4
    rect = double(ex.setup.screenRect);
    x0 = mean(rect([1 3]));
    y0 = mean(rect([2 4]));
    return
end
x0 = 0;
y0 = 0;
end


function tf = localIsScalarTrial(trialNo)
tf = isnumeric(trialNo) && isscalar(trialNo) && isfinite(trialNo);
end


function [trialGroups, groupLabels] = localResolveTrialGroups(ex, trialNo)
nTrials = numel(ex.Trials);
if isempty(trialNo) || localIsAllCode(trialNo)
    trialGroups = {1:nTrials};
    groupLabels = {'all'};
    return
end
if isnumeric(trialNo)
    trialVec = unique(double(trialNo(:)'));
    trialVec = trialVec(isfinite(trialVec) & trialVec == round(trialVec) & trialVec >= 1 & trialVec <= nTrials);
    if isempty(trialVec)
        error('plotGazeState:NoValidTrials', 'No valid trial indices were selected.');
    end
    trialGroups = {trialVec};
    groupLabels = {sprintf('n=%d trials', numel(trialVec))};
    return
end
if ischar(trialNo) || (isstring(trialNo) && isscalar(trialNo))
    code = lower(strtrim(char(trialNo)));
    [trialGroups, groupLabels] = localResolveNamedGroups(ex, {code});
    return
end
if iscell(trialNo) && all(cellfun(@(x) ischar(x) || (isstring(x) && isscalar(x)), trialNo))
    codes = cellfun(@(x) lower(strtrim(char(x))), trialNo, 'UniformOutput', false);
    [trialGroups, groupLabels] = localResolveNamedGroups(ex, codes);
    return
end
error('plotGazeState:InvalidTrialNo', ...
    'trialNo must be scalar numeric, numeric vector, [], ''all'', a named code, or a cell of named codes.');
end


function [trialGroups, groupLabels] = localResolveNamedGroups(ex, codes)
trialGroups = {1:numel(ex.Trials)};
groupLabels = {''};
for i = 1:numel(codes)
    [groupsThis, labelsThis] = localNamedGroupsForCode(ex, codes{i});
    nextGroups = {};
    nextLabels = {};
    for g = 1:numel(trialGroups)
        for h = 1:numel(groupsThis)
            inter = intersect(trialGroups{g}, groupsThis{h});
            if isempty(inter)
                continue
            end
            nextGroups{end+1} = inter; %#ok<AGROW>
            if strlength(string(groupLabels{g})) == 0
                nextLabels{end+1} = labelsThis{h}; %#ok<AGROW>
            else
                nextLabels{end+1} = sprintf('%s | %s', groupLabels{g}, labelsThis{h}); %#ok<AGROW>
            end
        end
    end
    trialGroups = nextGroups;
    groupLabels = nextLabels;
end
end


function [trialGroups, labels] = localNamedGroupsForCode(ex, code)
nTrials = numel(ex.Trials);
switch code
    case 'all'
        trialGroups = {1:nTrials};
        labels = {'all'};
    case 'bg'
        values = localTrialFieldValues(ex, 'background_noise_lvl');
        [trialGroups, labels] = localNumericGrouping(values, 'bg');
    case 'vis'
        values = localTrialFieldValues(ex, 'target_visibility');
        [trialGroups, labels] = localNumericGrouping(values, 'vis');
    case 'tnum'
        values = localTrialFieldValues(ex, 'target_num');
        [trialGroups, labels] = localNumericGrouping(values, 'tnum');
    case 'im'
        values = localImageNameValues(ex);
        [trialGroups, labels] = localStringGrouping(values, 'im');
    otherwise
        error('plotGazeState:UnknownGroupingCode', 'Unknown grouping code ''%s''.', code);
end
end


function values = localTrialFieldValues(ex, fieldName)
nTrials = numel(ex.Trials);
values = NaN(nTrials, 1);
for i = 1:nTrials
    T = ex.Trials(i);
    if isfield(T, fieldName) && isfinite(T.(fieldName))
        values(i) = double(T.(fieldName));
    end
end
end


function values = localImageNameValues(ex)
nTrials = numel(ex.Trials);
values = strings(nTrials, 1);
for i = 1:nTrials
    T = ex.Trials(i);
    if isfield(T, 'imageName') && ~isempty(T.imageName)
        values(i) = string(T.imageName);
    elseif isfield(T, 'stimPath') && ~isempty(T.stimPath)
        [~, name, ext] = fileparts(char(string(T.stimPath)));
        values(i) = string([name, ext]);
    elseif isfield(ex, 'stim') && isfield(ex.stim, 'seq') && numel(ex.stim.seq) >= i && ~isempty(ex.stim.seq{i})
        [~, name, ext] = fileparts(char(string(ex.stim.seq{i})));
        values(i) = string([name, ext]);
    end
end
end


function [trialGroups, labels] = localNumericGrouping(values, prefix)
keep = isfinite(values);
u = unique(values(keep));
trialGroups = cell(numel(u), 1);
labels = cell(numel(u), 1);
for i = 1:numel(u)
    trialGroups{i} = find(values == u(i));
    labels{i} = sprintf('%s: %g', prefix, u(i));
end
end


function [trialGroups, labels] = localStringGrouping(values, prefix)
keep = strlength(values) > 0;
u = unique(values(keep), 'stable');
trialGroups = cell(numel(u), 1);
labels = cell(numel(u), 1);
for i = 1:numel(u)
    trialGroups{i} = find(values == u(i));
    labels{i} = sprintf('%s: %s', prefix, u(i));
end
end


function tf = localIsAllCode(value)
tf = (ischar(value) && strcmpi(strtrim(value), 'all')) || ...
    (isstring(value) && isscalar(value) && strcmpi(strtrim(char(value)), 'all'));
end
