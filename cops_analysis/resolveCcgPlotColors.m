function colors = resolveCcgPlotColors(nGroup, opts, facetSpec, groupLabels)
% resolveCcgPlotColors  Shared color defaults for CCG plotting functions.
%
% opts.colors is a full nGroup x 3 group-color override.
% opts.levelColors maps plotted level labels to RGB values. Supported forms:
%   opts.levelColors = struct('levels', ["low","mid","high"], 'colors', C)
%   opts.levelColors = {'low', [1 0 0]; 'mid', [1 .5 0]; 'high', [0 0 1]}
%   opts.levelColors = C  % nLevel x 3 RGB rows in plotted level order

if nargin < 2 || isempty(opts)
    opts = struct();
end
if nargin < 3 || isempty(facetSpec)
    facetSpec = struct();
end
if nargin < 4
    groupLabels = strings(0, 1);
end

nGroup = double(nGroup);
if ~isscalar(nGroup) || ~isfinite(nGroup) || nGroup < 0
    error('resolveCcgPlotColors:BadGroupCount', 'nGroup must be a finite non-negative scalar.');
end
nGroup = round(nGroup);

if isstruct(opts) && isfield(opts, 'colors') && ~isempty(opts.colors)
    colors = localValidateRgbMatrix(double(opts.colors), nGroup, 'opts.colors');
    return
end

if localFacetEnabled(facetSpec)
    nLine = max(1, round(double(facetSpec.nLineGroups)));
    lineColors = localDefaultColorOrder(nLine);
    lineLabels = localFacetLineLabels(facetSpec, nLine);
    lineColors = localApplyLevelColors(lineColors, lineLabels, opts);
    lineGroupIndex = localLineGroupIndex(facetSpec, nGroup, nLine);
    colors = lineColors(lineGroupIndex, :);
else
    colors = localDefaultColorOrder(nGroup);
    labels = localStringLabels(groupLabels, nGroup);
    colors = localApplyLevelColors(colors, labels, opts);
end
end


function colors = localDefaultColorOrder(nColor)
colors = lines(nColor);
if nColor == 3
    % Warm-to-cool order: previous middle, previous highest, previous lowest.
    colors = colors([2 3 1], :);
end
end


function tf = localFacetEnabled(facetSpec)
tf = isstruct(facetSpec) && isfield(facetSpec, 'enabled') && logical(facetSpec.enabled) && ...
    isfield(facetSpec, 'nLineGroups') && isfield(facetSpec, 'lineGroupIndex');
end


function labels = localFacetLineLabels(facetSpec, nLine)
labels = strings(nLine, 1);
if isfield(facetSpec, 'lineLabels') && ~isempty(facetSpec.lineLabels)
    raw = string(facetSpec.lineLabels(:));
    n = min(numel(raw), nLine);
    labels(1:n) = raw(1:n);
    return
end
if ~isfield(facetSpec, 'groupLineLabels') || isempty(facetSpec.groupLineLabels)
    return
end
groupLabels = string(facetSpec.groupLineLabels(:));
lineGroupIndex = double(facetSpec.lineGroupIndex(:));
n = min(numel(groupLabels), numel(lineGroupIndex));
for i = 1:n
    idx = lineGroupIndex(i);
    if isfinite(idx) && idx >= 1 && idx <= nLine && strlength(labels(idx)) == 0
        labels(idx) = groupLabels(i);
    end
end
end


function lineGroupIndex = localLineGroupIndex(facetSpec, nGroup, nLine)
lineGroupIndex = ones(nGroup, 1);
candidate = double(facetSpec.lineGroupIndex(:));
n = min(numel(candidate), nGroup);
if n > 0
    lineGroupIndex(1:n) = candidate(1:n);
end
bad = ~isfinite(lineGroupIndex) | lineGroupIndex < 1 | lineGroupIndex > nLine;
lineGroupIndex(bad) = 1;
lineGroupIndex = round(lineGroupIndex);
end


function labels = localStringLabels(groupLabels, nGroup)
labels = strings(nGroup, 1);
if isempty(groupLabels)
    return
end
raw = string(groupLabels(:));
n = min(numel(raw), nGroup);
labels(1:n) = raw(1:n);
end


function colors = localApplyLevelColors(colors, labels, opts)
if ~isstruct(opts) || ~isfield(opts, 'levelColors') || isempty(opts.levelColors)
    return
end
[levels, levelColors, usesLabels] = localParseLevelColors(opts.levelColors);
if ~usesLabels
    levelColors = localValidateRgbMatrix(levelColors, size(colors, 1), 'opts.levelColors');
    colors = levelColors(1:size(colors, 1), :);
    return
end
levelColors = localValidateRgbMatrix(levelColors, numel(levels), 'opts.levelColors');

for i = 1:numel(labels)
    idx = localFindMatchingLevel(labels(i), levels);
    if ~isempty(idx)
        colors(i, :) = levelColors(idx, :);
    end
end
end


function [levels, colors, usesLabels] = localParseLevelColors(levelColors)
usesLabels = true;
levels = strings(0, 1);

if isnumeric(levelColors) || islogical(levelColors)
    colors = double(levelColors);
    usesLabels = false;
    return
end

if iscell(levelColors)
    if size(levelColors, 2) < 2
        error('resolveCcgPlotColors:BadLevelColors', ...
            'opts.levelColors cell form must be nLevel x 2: {levelLabel, rgb}.');
    end
    levels = string(levelColors(:, 1));
    colors = zeros(size(levelColors, 1), 3);
    for i = 1:size(levelColors, 1)
        colors(i, :) = localRgbValue(levelColors{i, 2});
    end
    return
end

if isstruct(levelColors)
    if isfield(levelColors, 'levels') && isfield(levelColors, 'colors')
        levels = string(levelColors.levels(:));
        colors = double(levelColors.colors);
        return
    end
    fields = fieldnames(levelColors);
    levels = string(fields(:));
    colors = zeros(numel(fields), 3);
    for i = 1:numel(fields)
        colors(i, :) = localRgbValue(levelColors.(fields{i}));
    end
    return
end

error('resolveCcgPlotColors:BadLevelColors', ...
    'opts.levelColors must be an RGB matrix, nLevel x 2 cell array, or struct.');
end


function colors = localValidateRgbMatrix(colors, nNeeded, name)
if isempty(colors)
    return
end
if size(colors, 2) ~= 3 || size(colors, 1) < nNeeded
    error('resolveCcgPlotColors:BadColors', '%s must have at least %d rows and exactly 3 RGB columns.', name, nNeeded);
end
colors = double(colors);
if any(~isfinite(colors(:))) || any(colors(:) < 0) || any(colors(:) > 1)
    error('resolveCcgPlotColors:BadColors', '%s RGB values must be finite values in [0, 1].', name);
end
end


function rgb = localRgbValue(value)
if isnumeric(value) || islogical(value)
    rgb = double(value(:)');
else
    error('resolveCcgPlotColors:BadRgbValue', 'Each level color must be a 1 x 3 RGB numeric vector.');
end
if numel(rgb) ~= 3 || any(~isfinite(rgb)) || any(rgb < 0) || any(rgb > 1)
    error('resolveCcgPlotColors:BadRgbValue', 'Each level color must be a finite 1 x 3 RGB vector in [0, 1].');
end
end


function idx = localFindMatchingLevel(label, levels)
idx = [];
if isempty(levels)
    return
end
labelKey = localLevelKey(label);
labelNum = str2double(labelKey);
for i = 1:numel(levels)
    levelKey = localLevelKey(levels(i));
    if strcmp(labelKey, levelKey)
        idx = i;
        return
    end
    levelNum = str2double(levelKey);
    if isfinite(labelNum) && isfinite(levelNum) && abs(labelNum - levelNum) < 1e-10
        idx = i;
        return
    end
end
end


function key = localLevelKey(value)
key = lower(strtrim(string(value)));
if ismissing(key) || strlength(key) == 0
    key = "";
    return
end
parts = split(key, "|");
key = strtrim(parts(end));
parts = split(key, ":");
key = strtrim(parts(end));
end
