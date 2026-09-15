function out = plotRewTrigVel(in, trialSelection, opts)
% plotRewTrigVel  Plot reward-triggered saccade velocity.
%
%   out = plotRewTrigVel(tbl)
%   out = plotRewTrigVel(tbl, opts)
%   out = plotRewTrigVel(ex)
%   out = plotRewTrigVel(ex, trialSelection)
%   out = plotRewTrigVel(ex, trialSelection, opts)

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
    rewardSaccTable = in;
else
    rewardOut = rewTrigSac(in, trialSelection, opts);
    rewardSaccTable = rewardOut.rewardSaccades;
end

if nargin < 3 || isempty(opts)
    opts = struct();
end
defaults = struct( ...
    'windowSec', [-0.5 2.5], ...
    'binWidthSec', 0.05, ...
    'velField', 'peakSpeedDegPerSec', ...
    'stat', 'mean', ...
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

if ~istable(rewardSaccTable) || isempty(rewardSaccTable)
    error('plotRewTrigVel:InvalidTable', ...
        'rewardSaccTable must be a non-empty table, or pass raw ex as the first argument.');
end

if ~ismember('group', rewardSaccTable.Properties.VariableNames)
    rewardSaccTable.group = ones(height(rewardSaccTable), 1);
end
if ~ismember('groupLabel', rewardSaccTable.Properties.VariableNames)
    rewardSaccTable.groupLabel = repmat("group 1", height(rewardSaccTable), 1);
end

groupIds = unique(double(rewardSaccTable.group(:)'));
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
    T = rewardSaccTable(double(rewardSaccTable.group) == g, :);
    plotOpts = struct( ...
        'windowSec', opts.windowSec, ...
        'binWidthSec', opts.binWidthSec, ...
        'velField', opts.velField, ...
        'stat', opts.stat, ...
        'newFigure', false, ...
        'lineColor', opts.colors(i, :), ...
        'lineWidth', opts.lineWidth, ...
        'showDecor', false);
    groupOut{i} = plotRewardSaccVel(T, plotOpts);
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
    legendLabels(i) = sprintf('%s (n=%d)', label, groupOut{i}.nRewards);
end

xline(0, ':', 'Color', [0.4 0.4 0.4]);
yline(0, ':', 'Color', [0.4 0.4 0.4]);
xlabel('Time From Reward Onset (s)');
ylabel(sprintf('%s (%s)', string(opts.velField), string(opts.stat)));
title(sprintf('Reward-aligned saccade velocity (%d group%s)', nGroup, localPlural(nGroup)));
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
out.velField = string(opts.velField);
out.stat = string(opts.stat);
end


function s = localPlural(n)
if n == 1
    s = '';
else
    s = 's';
end
end
