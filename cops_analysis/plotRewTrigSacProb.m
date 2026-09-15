function out = plotRewTrigSacProb(in, trialSelection, opts)
% plotRewTrigSacProb  Plot reward-triggered saccade probability.
%
%   out = plotRewTrigSacProb(tbl)
%   out = plotRewTrigSacProb(tbl, opts)
%   out = plotRewTrigSacProb(ex)
%   out = plotRewTrigSacProb(ex, trialSelection)
%   out = plotRewTrigSacProb(ex, trialSelection, opts)

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
    ex = [];
else
    ex = in;
    rewardOut = rewTrigSac(in, trialSelection, opts);
    rewardSaccTable = rewardOut.rewardSaccades;
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

if ~istable(rewardSaccTable) || isempty(rewardSaccTable)
    error('plotRewTrigSacProb:InvalidTable', ...
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
plotFacetSpec = localResolvePlotFacetSpec(trialSelection, ex, nGroup);
if isempty(opts.colors)
    if plotFacetSpec.enabled
        baseColors = lines(plotFacetSpec.nLineGroups);
        opts.colors = baseColors(plotFacetSpec.lineGroupIndex, :);
    else
        opts.colors = lines(nGroup);
    end
end

if opts.newFigure
    figure;
end

groupOut = cell(nGroup, 1);
legendLabels = strings(nGroup, 1);
for i = 1:nGroup
    g = groupIds(i);
    T = rewardSaccTable(double(rewardSaccTable.group) == g, :);
    plotOpts = struct( ...
        'windowSec', opts.windowSec, ...
        'binWidthSec', opts.binWidthSec, ...
        'newFigure', false, ...
        'lineColor', opts.colors(i, :), ...
        'lineWidth', opts.lineWidth, ...
        'showDecor', false);
    groupOut{i} = plotRewardSaccProb(T, plotOpts);
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

if plotFacetSpec.enabled
    tiledlayout(plotFacetSpec.nRows, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
    for iRow = 1:plotFacetSpec.nRows
        nexttile;
        localPlotGroupedProb(groupOut, opts, plotFacetSpec.rowGroupIdx{iRow}, ...
            plotFacetSpec.lineLabels, plotFacetSpec.rowLabels(iRow));
    end
else
    hold on
    localPlotGroupedProb(groupOut, opts, 1:nGroup, cellstr(legendLabels), "");
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


function s = localPlural(n)
if n == 1
    s = '';
else
    s = 's';
end
end


function localPlotGroupedProb(groupOut, opts, groupIdx, legendLabelsOverride, rowLabel)
hold on
plotted = false(numel(groupIdx), 1);
legendLabels = strings(numel(groupIdx), 1);
for j = 1:numel(groupIdx)
    g = groupIdx(j);
    plot(groupOut{g}.tBinCenterSec, groupOut{g}.saccProb, ...
        'Color', opts.colors(g, :), 'LineWidth', opts.lineWidth);
    if ~isempty(legendLabelsOverride) && numel(legendLabelsOverride) >= j
        legendLabels(j) = string(legendLabelsOverride{j});
    else
        legendLabels(j) = string(groupOut{g}.groupLabel);
    end
    plotted(j) = true;
end
xline(0, ':', 'Color', [0.4 0.4 0.4]);
yline(0, ':', 'Color', [0.4 0.4 0.4]);
xlabel('Time From Reward Onset (s)');
ylabel('Saccade Probability');
titleText = 'Reward-aligned saccade probability';
if strlength(strtrim(string(rowLabel))) > 0
    titleText = sprintf('%s | %s', titleText, char(string(rowLabel)));
end
title(titleText, 'Interpreter', 'none');
box off
if numel(groupIdx) > 1 && any(plotted)
    legend(cellstr(legendLabels(plotted)), 'Location', 'best', 'Interpreter', 'none');
end
end


function plotFacetSpec = localResolvePlotFacetSpec(trialSelection, ex, nGroup)
plotFacetSpec = struct('enabled', false, 'nRows', 1, 'nLineGroups', nGroup, ...
    'rowGroupIdx', {{}}, 'rowLabels', strings(0, 1), ...
    'lineLabels', {{}}, 'lineGroupIndex', (1:nGroup)');
if isempty(ex) || ~isstruct(ex) || ~isfield(ex, 'Trials') || ~localIsNamedCodeCell(trialSelection) || numel(trialSelection) ~= 2
    return
end
code1 = char(string(trialSelection{1}));
code2 = char(string(trialSelection{2}));
labels1 = localGroupingLevelLabels(code1, ex);
labels2 = localGroupingLevelLabels(code2, ex);
count1 = numel(labels1);
count2 = numel(labels2);
if ~(count1 >= 1 && count2 >= 1 && count1 * count2 == nGroup)
    return
end
plotFacetSpec.enabled = true;
plotFacetSpec.nRows = count1;
plotFacetSpec.nLineGroups = count2;
plotFacetSpec.rowGroupIdx = cell(count1, 1);
plotFacetSpec.rowLabels = labels1(:);
plotFacetSpec.lineLabels = cellstr(labels2(:));
plotFacetSpec.lineGroupIndex = repmat((1:count2)', count1, 1);
for i = 1:count1
    plotFacetSpec.rowGroupIdx{i} = ((i - 1) * count2 + 1):(i * count2);
end
end


function labels = localGroupingLevelLabels(code, ex)
code = lower(strtrim(char(string(code))));
switch code
    case 'all'
        labels = "all";
    case {'bg', 'vis', 'tnum', 'im'}
        groups = localResolveNamedTrialGroups(code, ex);
        labels = strings(numel(groups), 1);
        for i = 1:numel(groups)
            labels(i) = localSingleGroupLabel(code, groups{i}(1), ex);
        end
    otherwise
        labels = strings(0, 1);
end
end


function label = localSingleGroupLabel(code, trialIdx, ex)
T = ex.Trials(trialIdx);
switch code
    case 'bg'
        label = "bg: " + string(localTrialBackgroundNoiseLevel(T));
    case 'vis'
        label = "vis: " + string(localTrialTargetVisibility(ex, T));
    case 'tnum'
        label = "tnum: " + string(localTrialTargetNum(ex, T));
    case 'im'
        label = "im: " + localTrialImageName(ex, T, trialIdx);
    otherwise
        label = "all";
end
prefix = code + ": ";
if startsWith(char(label), prefix)
    label = strip(extractAfter(string(label), strlength(prefix)));
end
end


function tf = localIsNamedCodeCell(trialNo)
tf = iscell(trialNo) && ~isempty(trialNo);
if ~tf
    return
end
for i = 1:numel(trialNo)
    item = trialNo{i};
    if ~(ischar(item) || (isstring(item) && isscalar(item)))
        tf = false;
        return
    end
end
end


function trialGroups = localResolveNamedTrialGroups(code, ex)
code = lower(strtrim(code));
switch code
    case 'all'
        trialGroups = {1:numel(ex.Trials)};
    case {'bg', 'vis', 'tnum', 'im'}
        trialGroups = localResolveNamedTrialGroupsFromEx(code, ex);
    otherwise
        error('plotRewTrigSacProb:UnknownTrialCode', ...
            'Unknown trial grouping code ''%s''. Supported: ''all'', ''bg'', ''vis'', ''tnum'', ''im''.', code);
end
end


function trialGroups = localResolveNamedTrialGroupsFromEx(code, ex)
switch code
    case 'bg'
        values = NaN(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            values(j) = localTrialBackgroundNoiseLevel(ex.Trials(j));
        end
        levels = unique(values(isfinite(values)));
    case 'vis'
        values = NaN(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            values(j) = localTrialTargetVisibility(ex, ex.Trials(j));
        end
        levels = unique(values(isfinite(values)));
    case 'tnum'
        values = NaN(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            values(j) = localTrialTargetNum(ex, ex.Trials(j));
        end
        levels = unique(values(isfinite(values)));
    case 'im'
        values = strings(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            values(j) = localTrialImageName(ex, ex.Trials(j), j);
        end
        levels = unique(values(values ~= "" & ~ismissing(values)), 'stable');
end
if isempty(levels)
    error('plotRewTrigSacProb:NamedGroupEmpty', ...
        'No trials had usable values for grouping code ''%s''.', code);
end
trialGroups = cell(numel(levels), 1);
for i = 1:numel(levels)
    trialGroups{i} = find(values == levels(i));
end
end


function noiseLevel = localTrialBackgroundNoiseLevel(T)
noiseLevel = NaN;
if isfield(T, 'background_noise_lvl') && isscalar(T.background_noise_lvl) && isnumeric(T.background_noise_lvl)
    noiseLevel = double(T.background_noise_lvl);
end
end


function value = localTrialTargetVisibility(ex, T)
value = NaN;
if isfield(T, 'target_visibility') && isscalar(T.target_visibility) && isfinite(T.target_visibility)
    value = double(T.target_visibility);
elseif isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'graph') && ...
        isfield(ex.exp.CoPs.graph, 'target_visibility')
    v = ex.exp.CoPs.graph.target_visibility;
    if isscalar(v) && isfinite(v)
        value = double(v);
    end
end
end


function value = localTrialTargetNum(ex, T)
value = NaN;
if isfield(T, 'target_num') && isscalar(T.target_num) && isfinite(T.target_num)
    value = double(T.target_num);
elseif isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'ctl') && ...
        isfield(ex.exp.CoPs.ctl, 'target_num')
    v = ex.exp.CoPs.ctl.target_num;
    if isscalar(v) && isfinite(v)
        value = double(v);
    end
end
end


function imageName = localTrialImageName(ex, T, trialIdx)
imageName = string(missing);
if isfield(T, 'imageName') && (ischar(T.imageName) || isstring(T.imageName))
    candidate = string(T.imageName);
    if strlength(strtrim(candidate)) > 0
        imageName = candidate;
        return
    end
end
if isfield(T, 'stimPath') && (ischar(T.stimPath) || isstring(T.stimPath))
    candidate = localBasenameString(string(T.stimPath));
    if strlength(strtrim(candidate)) > 0
        imageName = candidate;
        return
    end
end
if isfield(ex, 'stim') && isstruct(ex.stim) && isfield(ex.stim, 'seq') && numel(ex.stim.seq) >= trialIdx
    candidate = localBasenameString(string(ex.stim.seq{trialIdx}));
    if strlength(strtrim(candidate)) > 0
        imageName = candidate;
    end
end
end


function out = localBasenameString(pathStr)
out = string(missing);
if strlength(strtrim(pathStr)) == 0 || ismissing(pathStr)
    return
end
[~, name, ext] = fileparts(char(pathStr));
candidate = string([name ext]);
if strlength(strtrim(candidate)) > 0
    out = candidate;
end
end
