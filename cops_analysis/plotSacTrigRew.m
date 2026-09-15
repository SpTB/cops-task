function out = plotSacTrigRew(in, trialSelection, opts)
% plotSacTrigRew  Plot saccade-triggered reward probability.
%
%   out = plotSacTrigRew(tbl)
%   out = plotSacTrigRew(tbl, opts)
%   out = plotSacTrigRew(ex)
%   out = plotSacTrigRew(ex, trialSelection)
%   out = plotSacTrigRew(ex, trialSelection, opts)

if nargin < 2
    trialSelection = [];
end
if nargin < 3
    opts = struct();
end

if istable(in)
    if nargin >= 2 && isstruct(trialSelection) && (nargin < 3 || isempty(opts))
        opts = trialSelection;
    end
    saccadeRewardTable = in;
else
    sacOut = sacTrigRew(in, trialSelection, opts);
    saccadeRewardTable = sacOut.saccadeRewards;
end

if nargin < 3 || isempty(opts)
    opts = struct();
end
defaults = struct( ...
    'windowSec', [-0.5 2.5], ...
    'binWidthSec', 0.05, ...
    'newFigure', true, ...
    'lineWidth', 1.5, ...
    'colors', []);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field)
        opts.(field) = defaults.(field);
    end
end
if isfield(opts, 'window') && ~isempty(opts.window)
    opts.windowSec = opts.window;
end

if ~istable(saccadeRewardTable) || isempty(saccadeRewardTable)
    error('plotSacTrigRew:InvalidTable', ...
        'saccadeRewardTable must be a non-empty table, or pass raw ex as the first argument.');
end

if ~ismember('group', saccadeRewardTable.Properties.VariableNames)
    saccadeRewardTable.group = ones(height(saccadeRewardTable), 1);
end
if ~ismember('groupLabel', saccadeRewardTable.Properties.VariableNames)
    saccadeRewardTable.groupLabel = repmat("group 1", height(saccadeRewardTable), 1);
end

groupIds = unique(double(saccadeRewardTable.group(:)'));
nGroup = numel(groupIds);
if isempty(opts.colors)
    opts.colors = lines(nGroup);
end

if opts.newFigure
    figure;
end
hold on

groupOut = cell(nGroup, 1);
legendLabels = strings(nGroup, 1);
for i = 1:nGroup
    g = groupIds(i);
    T = saccadeRewardTable(double(saccadeRewardTable.group) == g, :);
    plotOpts = struct( ...
        'windowSec', opts.windowSec, ...
        'binWidthSec', opts.binWidthSec, ...
        'newFigure', false, ...
        'lineColor', opts.colors(i, :), ...
        'lineWidth', opts.lineWidth, ...
        'showDecor', false);
    groupOut{i} = localPlotSacRewardProb(T, plotOpts);
    label = string(missing);
    if ~isempty(T.groupLabel)
        idx = find(strlength(strtrim(T.groupLabel)) > 0 & ~ismissing(T.groupLabel), 1, 'first');
        if ~isempty(idx)
            label = T.groupLabel(idx);
        end
    end
    if ismissing(label) || strlength(strtrim(label)) == 0
        label = "group " + string(i);
    end
    legendLabels(i) = sprintf('%s (n=%d)', label, groupOut{i}.nSaccades);
end

xline(0, ':', 'Color', [0.4 0.4 0.4]);
yline(0, ':', 'Color', [0.4 0.4 0.4]);
xlabel('Time From Saccade Onset (s)');
ylabel('Reward Probability');
title(sprintf('Saccade-triggered reward probability (%d group%s)', nGroup, localPlural(nGroup)));
box off
if nGroup > 1
    legend(cellstr(legendLabels), 'Location', 'best', 'Interpreter', 'none');
end

out = struct();
out.groups = groupOut;
out.groupLabels = legendLabels;
if ~isempty(groupOut)
    out.tBinCenterSec = groupOut{1}.tBinCenterSec;
    out.binEdgesSec = groupOut{1}.binEdgesSec;
else
    out.tBinCenterSec = [];
    out.binEdgesSec = [];
end
end


function out = localPlotSacRewardProb(saccadeRewardTable, opts)
defaults = struct( ...
    'windowSec', [-0.5 2.5], ...
    'binWidthSec', 0.05, ...
    'newFigure', true, ...
    'lineColor', [0 0 0], ...
    'lineWidth', 1.5, ...
    'showDecor', true);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field)
        opts.(field) = defaults.(field);
    end
end

requiredVars = {'trial', 'saccNo', 'tFromSaccSec', 'hasReward'};
missingVars = setdiff(requiredVars, saccadeRewardTable.Properties.VariableNames, 'stable');
if ~isempty(missingVars)
    error('plotSacTrigRew:MissingVars', ...
        'Missing required columns: %s', strjoin(missingVars, ', '));
end

windowSec = double(opts.windowSec(:)');
binWidthSec = double(opts.binWidthSec);
binEdgesSec = windowSec(1):binWidthSec:windowSec(2);
if binEdgesSec(end) < windowSec(2)
    binEdgesSec(end+1) = windowSec(2); %#ok<AGROW>
end
tBinCenterSec = binEdgesSec(1:end-1) + diff(binEdgesSec) / 2;

[saccGroup, saccInfo] = findgroups(saccadeRewardTable(:, {'trial', 'saccNo'}));
nSaccades = height(saccInfo);
rewardHas = false(nSaccades, numel(tBinCenterSec));
for i = 1:nSaccades
    T = saccadeRewardTable(saccGroup == i, :);
    rel = double(T.tFromSaccSec);
    rel = rel(logical(T.hasReward) & isfinite(rel));
    if isempty(rel)
        continue
    end
    binIdx = discretize(rel, binEdgesSec);
    binIdx = unique(binIdx(isfinite(binIdx)));
    rewardHas(i, binIdx) = true;
end
rewardProb = mean(rewardHas, 1, 'omitnan');

if opts.newFigure
    figure;
end
plot(tBinCenterSec, rewardProb, 'Color', opts.lineColor, 'LineWidth', opts.lineWidth);
hold on
if logical(opts.showDecor)
    xline(0, ':', 'Color', [0.4 0.4 0.4]);
    yline(0, ':', 'Color', [0.4 0.4 0.4]);
    xlabel('Time From Saccade Onset (s)');
    ylabel('Reward Probability');
    title(sprintf('Saccade-triggered reward probability (n saccades = %d)', nSaccades));
    box off
end

out = struct();
out.tBinCenterSec = tBinCenterSec(:);
out.rewardProb = rewardProb(:);
out.nSaccades = nSaccades;
out.binEdgesSec = binEdgesSec(:);
out.saccHasReward = rewardHas;
end


function s = localPlural(n)
if n == 1
    s = '';
else
    s = 's';
end
end
