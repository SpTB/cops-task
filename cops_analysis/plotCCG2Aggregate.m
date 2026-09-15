function out = plotCCG2Aggregate(A, opts)
% plotCCG2Aggregate  Plot collectCCG2 aggregate output.
%
%   plotCCG2Aggregate(A)
%   plotCCG2Aggregate(A, opts)
%
% For two named grouping codes, e.g. collectCCG2(..., {'bg','vis'}, ...),
% the first code is plotted as rows and the second as line colors.
%
% If A contains a controlAggregate from collectCCG2, bg=-1 controls are
% overlaid by default with matching visibility colors: target_num=2 is
% dashed and target_num=1 is dotted. Disable with
% opts.showControlConditions=false.

if nargin < 2 || isempty(opts)
    opts = struct();
elseif ~isstruct(opts)
    error('plotCCG2Aggregate:BadOpts', 'opts must be a struct.');
end
if ~isstruct(A) || ~isfield(A, 'groups') || isempty(A.groups)
    error('plotCCG2Aggregate:EmptyGroups', '%s', localEmptyGroupsMessage(A));
end
opts = localDefaults(opts, A);

facetSpec = localResolveFacetSpec(A);
if opts.newFigure
    figure;
end
if facetSpec.enabled
    tiledlayout(facetSpec.nRows, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
    for iRow = 1:facetSpec.nRows
        nexttile;
        localPlotGroupSet(A, facetSpec.rowGroupIdx{iRow}, opts, facetSpec.groupLineLabels, facetSpec.rowLabels(iRow), facetSpec.lineGroupIndex);
    end
else
    localPlotGroupSet(A, 1:numel(A.groups), opts, {}, "", (1:numel(A.groups))');
end
sgtitle(localTitle(A, opts), 'Interpreter', 'none');

out = A;
out.plotOptions = opts;
end


function opts = localDefaults(opts, A)
defaults = struct( ...
    'newFigure', true, ...
    'lineWidth', 1.75, ...
    'showError', true, ...
    'errorAlpha', 0.18, ...
    'legendLocation', 'northeastoutside', ...
    'colors', [], ...
    'levelColors', [], ...
    'showControlConditions', true, ...
    'hideControlGroupsInMain', true, ...
    'controlBackgroundNoiseLvl', -1, ...
    'controlTargetNums', [2 1], ...
    'controlLineStyles', {{'--', ':'}}, ...
    'controlColor', [0 0 0], ...
    'controlLineWidth', [], ...
    'controlLegendPrefix', 'control', ...
    'xlim', [], ...
    'title', []);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(opts, names{i}) || isempty(opts.(names{i}))
        opts.(names{i}) = defaults.(names{i});
    end
end
nColors = numel(A.groups);
facetSpec = localResolveFacetSpec(A);
opts.colors = resolveCcgPlotColors(nColors, opts, facetSpec, localGroupLabels(A));
end


function localPlotGroupSet(A, groupIdx, opts, legendLabelsOverride, rowLabel, lineGroupIndex)
hold on;
lagSec = double(A.lagSec(:));
handles = gobjects(0, 1);
labels = cell(0, 1);
for i = 1:numel(groupIdx)
    g = groupIdx(i);
    group = A.groups{g};
    y = double(group.aggregate2D(:));
    if isempty(lagSec) || isempty(y) || numel(y) ~= numel(lagSec) || ~any(isfinite(y))
        continue
    end
    rawLabel = string(group.groupLabel);
    if opts.showControlConditions && opts.hideControlGroupsInMain && localIsControlGroupLabel(rawLabel, opts)
        continue
    end
    colorIdx = g;
    if nargin >= 6 && numel(lineGroupIndex) >= g && isfinite(lineGroupIndex(g))
        colorIdx = g;
    end
    color = opts.colors(colorIdx, :);
    if opts.showError && isfield(group, 'sem2D') && numel(group.sem2D) == numel(y)
        localPlotErrorPatch(lagSec, y, double(group.sem2D(:)), color, opts.errorAlpha);
    end
    handles(end+1, 1) = plot(lagSec, y, 'Color', color, 'LineWidth', opts.lineWidth); %#ok<AGROW>
    if ~isempty(legendLabelsOverride) && numel(legendLabelsOverride) >= g && strlength(string(legendLabelsOverride{g})) > 0
        label = string(legendLabelsOverride{g});
    else
        label = string(group.groupLabel);
    end
    labels{end+1, 1} = sprintf('%s (nSess=%d, nTrial=%d)', char(label), group.nSessions, group.nTrials); %#ok<AGROW>
end
[controlHandles, controlLabels] = localPlotControlConditions(A, opts);
if ~isempty(controlHandles)
    handles = [handles; controlHandles(:)]; %#ok<AGROW>
    labels = [labels; controlLabels(:)]; %#ok<AGROW>
end
xline(0, ':');
yline(0, ':');
if ~isempty(opts.xlim)
    xlim(double(opts.xlim(:)'));
elseif isfield(A, 'options') && isfield(A.options, 'ccgOpts') && ...
        isfield(A.options.ccgOpts, 'ccgWindowSec') && ~isempty(A.options.ccgOpts.ccgWindowSec)
    xw = double(A.options.ccgOpts.ccgWindowSec(:)');
    if numel(xw) >= 2 && all(isfinite(xw(1:2))) && xw(2) > xw(1)
        xlim(xw(1:2));
    end
end
xlabel('Lag (s)');
ylabel('2D velocity xcorr');
titleText = 'Aggregate 2D Velocity CCG';
if strlength(strtrim(string(rowLabel))) > 0
    titleText = sprintf('%s | %s', titleText, char(rowLabel));
end
title(titleText, 'Interpreter', 'none');
box off;
if ~isempty(handles)
    legend(handles, labels, 'Location', char(string(opts.legendLocation)), 'Interpreter', 'none');
end
hold off;
end


function localPlotErrorPatch(x, y, sem, color, alphaValue)
keep = isfinite(x) & isfinite(y) & isfinite(sem);
if nnz(keep) < 2
    return
end
x = x(:);
y = y(:);
sem = sem(:);
upper = y + sem;
lower = y - sem;
patchX = [x(keep); flipud(x(keep))];
patchY = [upper(keep); flipud(lower(keep))];
patch(patchX, patchY, color, ...
    'FaceAlpha', alphaValue, ...
    'EdgeColor', 'none', ...
    'HandleVisibility', 'off');
end


function [handles, labels] = localPlotControlConditions(A, opts)
handles = gobjects(0, 1);
labels = cell(0, 1);
if ~opts.showControlConditions
    return
end
controlA = localControlAggregate(A, opts);
if isempty(controlA) || ~isfield(controlA, 'groups') || isempty(controlA.groups)
    return
end

targetNums = double(opts.controlTargetNums(:)');
targetNums = targetNums(isfinite(targetNums));
for i = 1:numel(targetNums)
    [groups, groupLabels] = localFindControlGroups(controlA, opts.controlBackgroundNoiseLvl, targetNums(i));
    for j = 1:numel(groups)
        group = groups{j};
        if isempty(group) || ~isfield(group, 'aggregate2D') || isempty(group.aggregate2D)
            continue
        end
        y = double(group.aggregate2D(:));
        x = localGroupLagSec(controlA, group, numel(y));
        if isempty(x) || numel(x) ~= numel(y) || ~any(isfinite(y))
            continue
        end
        handles(end+1, 1) = plot(x, y, ...
            'Color', localControlColorForGroup(A, opts, groupLabels(j), i), ...
            'LineStyle', localControlLineStyle(opts, i), ...
            'LineWidth', localControlLineWidth(opts)); %#ok<AGROW>
        labels{end+1, 1} = localControlLegendLabel(group, groupLabels(j), opts, targetNums(i)); %#ok<AGROW>
    end
end
end


function controlA = localControlAggregate(A, opts)
controlA = [];
if isfield(A, 'controlAggregate') && isstruct(A.controlAggregate) && ...
        isfield(A.controlAggregate, 'groups') && ~isempty(A.controlAggregate.groups)
    controlA = A.controlAggregate;
    return
end
if isfield(A, 'groups') && ~isempty(A.groups)
    groupLabels = localGroupLabels(A);
    for g = 1:numel(groupLabels)
        if localIsControlGroupLabel(groupLabels(g), opts) && ...
                strlength(localGroupLabelValue(groupLabels(g), 'tnum')) > 0
            controlA = A;
            return
        end
    end
end
end


function [groups, labels] = localFindControlGroups(A, backgroundLevel, targetNum)
groups = {};
labels = strings(0, 1);
groupLabels = localGroupLabels(A);
for g = 1:numel(A.groups)
    if g > numel(groupLabels)
        continue
    end
    if localNumericLabelMatches(localGroupLabelValue(groupLabels(g), 'bg'), backgroundLevel) && ...
            localNumericLabelMatches(localGroupLabelValue(groupLabels(g), 'tnum'), targetNum)
        groups{end+1, 1} = A.groups{g}; %#ok<AGROW>
        labels(end+1, 1) = groupLabels(g); %#ok<AGROW>
    end
end
end


function tf = localIsControlGroupLabel(groupLabel, opts)
tf = localNumericLabelMatches(localGroupLabelValue(groupLabel, 'bg'), opts.controlBackgroundNoiseLvl);
end


function tf = localNumericLabelMatches(labelValue, targetValue)
tf = false;
labelValue = strtrim(string(labelValue));
if ismissing(labelValue) || strlength(labelValue) == 0
    return
end
targetValue = double(targetValue(:));
targetValue = targetValue(isfinite(targetValue));
if isempty(targetValue)
    return
end
labelNum = str2double(labelValue);
for i = 1:numel(targetValue)
    if isfinite(labelNum) && abs(labelNum - targetValue(i)) <= 1e-9
        tf = true;
        return
    end
    if strcmpi(labelValue, string(targetValue(i)))
        tf = true;
        return
    end
end
end


function x = localGroupLagSec(A, group, n)
x = [];
if isstruct(group) && isfield(group, 'lagSec') && numel(group.lagSec) == n
    x = double(group.lagSec(:));
elseif isstruct(A) && isfield(A, 'lagSec') && numel(A.lagSec) == n
    x = double(A.lagSec(:));
end
end


function color = localControlColor(opts, idx)
color = double(opts.controlColor);
if isempty(color)
    color = [0 0 0];
end
if size(color, 2) ~= 3
    color = color(:)';
end
if size(color, 2) ~= 3
    color = [0 0 0];
elseif size(color, 1) > 1
    color = color(min(idx, size(color, 1)), :);
else
    color = color(1, :);
end
color = min(max(color, 0), 1);
end


function color = localControlColorForGroup(A, opts, controlLabel, fallbackIdx)
visibilityCode = localControlVisibilityCode(controlLabel);
if strlength(visibilityCode) > 0
    controlVisibility = localGroupLabelValue(controlLabel, visibilityCode);
    mainLabels = localGroupLabels(A);
    for g = 1:numel(mainLabels)
        if g > size(opts.colors, 1)
            continue
        end
        mainVisibility = localGroupLabelValue(mainLabels(g), visibilityCode);
        if localLevelLabelMatches(mainVisibility, controlVisibility)
            color = opts.colors(g, :);
            return
        end
    end
end
color = localControlColor(opts, fallbackIdx);
end


function code = localControlVisibilityCode(groupLabel)
code = "";
if strlength(localGroupLabelValue(groupLabel, 'vislvl3')) > 0
    code = "vislvl3";
elseif strlength(localGroupLabelValue(groupLabel, 'vis')) > 0
    code = "vis";
end
end


function tf = localLevelLabelMatches(a, b)
tf = false;
a = strtrim(string(a));
b = strtrim(string(b));
if ismissing(a) || ismissing(b) || strlength(a) == 0 || strlength(b) == 0
    return
end
if strcmpi(a, b)
    tf = true;
    return
end
aNum = str2double(a);
bNum = str2double(b);
tf = isfinite(aNum) && isfinite(bNum) && abs(aNum - bNum) <= 1e-9;
end


function style = localControlLineStyle(opts, idx)
styles = opts.controlLineStyles;
if iscell(styles)
    if isempty(styles)
        style = '-';
    else
        style = char(string(styles{min(idx, numel(styles))}));
    end
elseif isstring(styles) || ischar(styles)
    styles = string(styles);
    style = char(styles(min(idx, numel(styles))));
else
    style = '-';
end
end


function lineWidth = localControlLineWidth(opts)
lineWidth = [];
if isfield(opts, 'controlLineWidth') && ~isempty(opts.controlLineWidth)
    candidate = double(opts.controlLineWidth);
    if isscalar(candidate) && isfinite(candidate) && candidate > 0
        lineWidth = candidate;
    end
end
if isempty(lineWidth)
    lineWidth = opts.lineWidth;
end
end


function label = localControlLegendLabel(group, groupLabel, opts, targetNum)
nSess = localGroupScalar(group, 'nSessions');
nTrial = localGroupScalar(group, 'nTrials');
targetText = "targets";
if abs(targetNum - 1) <= 1e-9
    targetText = "target";
end
visibilityText = localControlVisibilityLegendText(groupLabel);
label = sprintf('%s %s%g %s (bg=%g, nSess=%d, nTrial=%d)', ...
    char(string(opts.controlLegendPrefix)), char(visibilityText), targetNum, char(targetText), ...
    double(opts.controlBackgroundNoiseLvl), nSess, nTrial);
end


function text = localControlVisibilityLegendText(groupLabel)
text = "";
visLvl3 = localGroupLabelValue(groupLabel, 'vislvl3');
if strlength(visLvl3) > 0
    text = "visLvl3 " + visLvl3 + ", ";
    return
end
vis = localGroupLabelValue(groupLabel, 'vis');
if strlength(vis) > 0
    text = "vis " + vis + ", ";
end
end


function value = localGroupScalar(group, fieldName)
value = 0;
if isstruct(group) && isfield(group, fieldName) && ~isempty(group.(fieldName))
    candidate = double(group.(fieldName));
    if isscalar(candidate) && isfinite(candidate)
        value = round(candidate);
    end
end
end


function titleText = localTitle(A, opts)
if isfield(opts, 'title') && ~isempty(opts.title)
    titleText = char(string(opts.title));
    return
end
subject = "";
if isfield(A, 'subject')
    subject = string(A.subject);
end
mode = "";
if isfield(A, 'aggregateAcrossSessions')
    mode = string(A.aggregateAcrossSessions);
end
if strlength(subject) > 0
    titleText = sprintf('CCG2 aggregate: %s (%d sessions, %s-weighted)', char(subject), localNSessions(A), char(mode));
else
    titleText = sprintf('CCG2 aggregate (%d sessions, %s-weighted)', localNSessions(A), char(mode));
end
end


function n = localNSessions(A)
n = 0;
if isfield(A, 'sessionOutputs')
    n = numel(A.sessionOutputs);
elseif isfield(A, 'nSessions')
    n = A.nSessions;
end
end


function facetSpec = localResolveFacetSpec(A)
nGroup = numel(A.groups);
facetSpec = struct('enabled', false, 'nRows', 1, 'nLineGroups', nGroup, ...
    'rowGroupIdx', {{}}, 'rowLabels', strings(0, 1), ...
    'groupLineLabels', {{}}, 'lineGroupIndex', (1:nGroup)');
if ~isfield(A, 'groupingArg') || ~localIsNamedCodeCell(A.groupingArg) || numel(A.groupingArg) ~= 2
    return
end
code1 = localCanonicalGroupingCode(A.groupingArg{1});
code2 = localCanonicalGroupingCode(A.groupingArg{2});
if localIsPercentileCode(code1) || localIsPercentileCode(code2)
    return
end

labels = localGroupLabels(A);
levelLabels = strings(nGroup, 2);
for g = 1:nGroup
    levelLabels(g, 1) = localGroupLabelValue(labels(g), code1);
    levelLabels(g, 2) = localGroupLabelValue(labels(g), code2);
end
valid = strlength(strtrim(levelLabels(:, 1))) > 0 & strlength(strtrim(levelLabels(:, 2))) > 0;
if ~any(valid)
    return
end
rowLabels = localUniqueStableStrings(levelLabels(valid, 1));
lineLabels = localUniqueStableStrings(levelLabels(valid, 2));
if isempty(rowLabels) || isempty(lineLabels)
    return
end

facetSpec.enabled = true;
facetSpec.nRows = numel(rowLabels);
facetSpec.nLineGroups = numel(lineLabels);
facetSpec.rowLabels = rowLabels(:);
facetSpec.groupLineLabels = cellstr(levelLabels(:, 2));
facetSpec.rowGroupIdx = cell(facetSpec.nRows, 1);
for i = 1:facetSpec.nRows
    facetSpec.rowGroupIdx{i} = find(valid & strcmp(levelLabels(:, 1), rowLabels(i))).';
end
facetSpec.lineGroupIndex = ones(nGroup, 1);
for g = 1:nGroup
    idx = find(strcmp(lineLabels, levelLabels(g, 2)), 1, 'first');
    if ~isempty(idx)
        facetSpec.lineGroupIndex(g) = idx;
    end
end
end


function labels = localGroupLabels(A)
nGroup = numel(A.groups);
labels = strings(nGroup, 1);
if isfield(A, 'groupLabels') && numel(A.groupLabels) >= nGroup
    raw = string(A.groupLabels(:));
    labels(:) = raw(1:nGroup);
    return
end
for g = 1:nGroup
    if isfield(A.groups{g}, 'groupLabel')
        labels(g) = string(A.groups{g}.groupLabel);
    else
        labels(g) = "group " + string(g);
    end
end
end


function value = localGroupLabelValue(groupLabel, code)
groupLabel = string(groupLabel);
value = "";
if strlength(strtrim(groupLabel)) == 0 || ismissing(groupLabel)
    return
end
parts = split(groupLabel, "|");
prefix = string(code) + ":";
for i = 1:numel(parts)
    part = strtrim(parts(i));
    if startsWith(lower(part), lower(prefix))
        value = strtrim(extractAfter(part, strlength(prefix)));
        return
    end
end
end


function labels = localUniqueStableStrings(values)
values = string(values(:));
labels = strings(0, 1);
for i = 1:numel(values)
    value = strtrim(values(i));
    if strlength(value) == 0 || ismissing(value)
        continue
    end
    if ~any(strcmp(labels, value))
        labels(end+1, 1) = value; %#ok<AGROW>
    end
end
end


function tf = localIsNamedCodeCell(value)
tf = iscell(value) && ~isempty(value);
if ~tf
    return
end
for i = 1:numel(value)
    if ~(ischar(value{i}) || (isstring(value{i}) && isscalar(value{i})))
        tf = false;
        return
    end
end
end


function code = localCanonicalGroupingCode(code)
code = lower(strtrim(char(string(code))));
if ismember(code, {'purs', 'pursuit', 'pursuittrial', 'pursuittrials'})
    code = 'pur';
elseif ismember(code, {'rewq', 'rquad', 'rewardquad', 'rewardquadrant'})
    code = 'rq';
end
end


function tf = localIsPercentileCode(value)
code = lower(strtrim(char(string(value))));
tf = ~isempty(regexp(code, '^p\d+(\.\d+)?$', 'once'));
end


function msg = localEmptyGroupsMessage(A)
msg = "No aggregate CCG2 groups were available to plot.";
if ~isstruct(A)
    msg = msg + " Input was not a collectCCG2 output struct.";
    return
end
if isfield(A, 'diagnostics') && isstruct(A.diagnostics)
    if isfield(A.diagnostics, 'nSessionOutputs')
        msg = msg + sprintf(" nSessionOutputs=%d.", A.diagnostics.nSessionOutputs);
    end
    if isfield(A.diagnostics, 'statusCounts') && istable(A.diagnostics.statusCounts) && ~isempty(A.diagnostics.statusCounts)
        msg = msg + " Check A.diagnostics.statusCounts.";
        try
            statusText = strings(height(A.diagnostics.statusCounts), 1);
            for i = 1:height(A.diagnostics.statusCounts)
                statusText(i) = sprintf('%s=%d', ...
                    string(A.diagnostics.statusCounts.status(i)), ...
                    A.diagnostics.statusCounts.count(i));
            end
            msg = msg + " Status counts: " + strjoin(statusText, ", ") + ".";
        catch
        end
    end
    if isfield(A.diagnostics, 'failedMessages') && istable(A.diagnostics.failedMessages) && ~isempty(A.diagnostics.failedMessages)
        msg = msg + " Check A.diagnostics.failedMessages for the exact file-level failures.";
    end
elseif isfield(A, 'fileTable') && istable(A.fileTable)
    msg = msg + " Check A.fileTable.status and A.fileTable.message.";
end
end
