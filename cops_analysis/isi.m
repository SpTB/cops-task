function out = isi(ex, trialNo, opts)
% isi  Compute inter-saccadic intervals from CoPs gaze-state classification.
%
%   out = isi(ex)
%   out = isi(ex, 1:120)
%   out = isi(ex, 'bg')
%   out = isi(ex, {'bg','vis'})
%   out = isi(ex, [], opts)
%
% Inputs
%   ex       : experiment struct with ex.Trials
%   trialNo  : optional scalar/vector of trial numbers, or named grouping
%              code(s): 'all', 'bg', 'vis', 'tnum', 'im'
%   opts     : optional struct passed through to classifyGazeState()
%
% Output
%   out.events     : one row per inter-saccadic interval
%   out.summary    : per-group summary table
%   out.trialGroups: resolved trial groups
%   out.groupLabels: readable group labels

if nargin < 2
    trialNo = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
if ~isstruct(ex) || ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('isi:BadInput', 'First input must be an ex struct with Trials.');
end
if ~isstruct(opts)
    error('isi:BadOpts', 'Third argument must be an opts struct.');
end

trialGroups = localNormalizeTrialGroups(trialNo, ex);
groupLabels = localBuildGroupLabels(trialNo, trialGroups, ex);

rowCells = cell(numel(ex.Trials), 1);
rowCount = 0;
for g = 1:numel(trialGroups)
    trials = trialGroups{g};
    for i = 1:numel(trials)
        trialIdx = trials(i);
        G = classifyGazeState(ex, trialIdx, opts);
        S = G.samples;
        if isempty(S) || ~ismember('isSaccade', S.Properties.VariableNames)
            continue
        end
        S = sortrows(S, 'tRelSec');
        starts = find(diff([false; logical(S.isSaccade(:))]) == 1);
        if numel(starts) < 2
            continue
        end
        saccStartSec = double(S.tRelSec(starts));
        isiSec = diff(saccStartSec);
        for k = 1:numel(isiSec)
            rowCount = rowCount + 1;
            rowCells{rowCount,1} = table( ...
                g, trialIdx, string(groupLabels(g)), ...
                k, starts(k), starts(k+1), ...
                saccStartSec(k), saccStartSec(k+1), isiSec(k), ...
                'VariableNames', {'group','trial','groupLabel', ...
                'intervalNo','startRow1','startRow2', ...
                'saccStartSec1','saccStartSec2','isiSec'});
        end
    end
end

if rowCount == 0
    events = table();
else
    events = vertcat(rowCells{1:rowCount});
end

out = struct();
out.events = events;
out.summary = localSummarizeIsi(events, trialGroups, groupLabels);
out.trials = [trialGroups{:}];
out.trialGroups = trialGroups;
out.groupLabels = groupLabels;
end


function summary = localSummarizeIsi(events, trialGroups, groupLabels)
nGroup = numel(trialGroups);
rows = cell(nGroup, 1);
for g = 1:nGroup
    if isempty(events)
        E = table();
    else
        E = events(double(events.group) == g, :);
    end
    x = [];
    if ~isempty(E)
        x = double(E.isiSec(:));
        x = x(isfinite(x) & x >= 0);
    end
    p = NaN(1, 5);
    if ~isempty(x)
        p = prctile(x, [10 25 50 75 90]);
    end
    rows{g} = table( ...
        g, string(groupLabels(g)), numel(trialGroups{g}), height(E), ...
        mean(x, 'omitnan'), median(x, 'omitnan'), ...
        p(1), p(2), p(3), p(4), p(5), ...
        'VariableNames', {'group','groupLabel','nTrials','nIntervals', ...
        'meanIsiSec','medianIsiSec', ...
        'p10Sec','p25Sec','p50Sec','p75Sec','p90Sec'});
end
summary = vertcat(rows{:});
end


function labels = localBuildGroupLabels(trialNo, trialGroups, ex)
nGroup = numel(trialGroups);
labels = strings(nGroup, 1);
if isempty(trialGroups)
    return
end
if isempty(trialNo)
    labels(:) = "all";
    return
end
if ischar(trialNo) || (isstring(trialNo) && isscalar(trialNo))
    codeList = {char(string(trialNo))};
elseif localIsNamedCodeCell(trialNo)
    codeList = cellfun(@(x) char(string(x)), trialNo, 'UniformOutput', false);
else
    for i = 1:nGroup
        labels(i) = "group " + string(i);
    end
    return
end

for i = 1:nGroup
    tr = trialGroups{i}(1);
    T = ex.Trials(tr);
    parts = strings(0, 1);
    for k = 1:numel(codeList)
        code = lower(strtrim(codeList{k}));
        switch code
            case 'all'
                parts(end+1,1) = "all"; %#ok<AGROW>
            case 'bg'
                parts(end+1,1) = "bg: " + string(localTrialBackgroundNoiseLevel(T)); %#ok<AGROW>
            case 'vis'
                parts(end+1,1) = "vis: " + string(localTrialTargetVisibility(ex, T)); %#ok<AGROW>
            case 'tnum'
                parts(end+1,1) = "tnum: " + string(localTrialTargetNum(ex, T)); %#ok<AGROW>
            case 'im'
                parts(end+1,1) = "im: " + localTrialImageName(ex, T, tr); %#ok<AGROW>
            otherwise
                parts(end+1,1) = "group " + string(i); %#ok<AGROW>
        end
    end
    labels(i) = strjoin(parts, " | ");
end
end


function trialGroups = localNormalizeTrialGroups(trialNo, ex)
if isempty(trialNo) || localIsAllCode(trialNo)
    trialGroups = {1:numel(ex.Trials)};
    return
end
if ischar(trialNo) || (isstring(trialNo) && isscalar(trialNo))
    trialGroups = localResolveNamedTrialGroups(char(string(trialNo)), ex);
    return
end
nTrials = numel(ex.Trials);
if iscell(trialNo)
    if localIsNamedCodeCell(trialNo)
        trialGroups = localCombineNamedTrialGroups(trialNo, ex);
        return
    end
    trialGroups = cell(size(trialNo));
    for i = 1:numel(trialNo)
        trialGroups{i} = localValidateTrialVector(trialNo{i}, nTrials);
    end
else
    trialGroups = {localValidateTrialVector(trialNo, nTrials)};
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


function trialGroups = localCombineNamedTrialGroups(codeList, ex)
trialGroups = {1:numel(ex.Trials)};
for k = 1:numel(codeList)
    code = char(string(codeList{k}));
    nextGroups = localResolveNamedTrialGroups(code, ex);
    combined = {};
    nOut = 0;
    for i = 1:numel(trialGroups)
        for j = 1:numel(nextGroups)
            g = intersect(trialGroups{i}, nextGroups{j}, 'stable');
            if ~isempty(g)
                nOut = nOut + 1;
                combined{nOut,1} = g; %#ok<AGROW>
            end
        end
    end
    trialGroups = combined;
    if isempty(trialGroups)
        break
    end
end
if isempty(trialGroups)
    error('isi:NamedGroupEmpty', ...
        'No trials remained after combining the requested named groupings.');
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
        error('isi:UnknownTrialCode', ...
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
    error('isi:NamedGroupEmpty', 'No trials had usable values for grouping code ''%s''.', code);
end
trialGroups = cell(numel(levels), 1);
for i = 1:numel(levels)
    switch code
        case 'im'
            trialGroups{i} = find(values == levels(i));
        otherwise
            trialGroups{i} = find(values == levels(i));
    end
end
end


function trialVec = localValidateTrialVector(trialVec, nTrials)
trialVec = unique(double(trialVec(:)'));
if isempty(trialVec) || any(~isfinite(trialVec)) || any(trialVec ~= round(trialVec))
    error('isi:BadTrialNo', ...
        'Each trial selection must contain finite integer trial indices.');
end
trialVec = trialVec(trialVec >= 1 & trialVec <= nTrials);
if isempty(trialVec)
    error('isi:BadTrialNo', ...
        'No requested trials were within the valid range 1:%d.', nTrials);
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


function tf = localIsAllCode(value)
tf = (ischar(value) && strcmpi(strtrim(value), 'all')) || ...
    (isstring(value) && isscalar(value) && strcmpi(strtrim(char(value)), 'all'));
end
