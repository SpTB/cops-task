function [refTrialGroups, info] = refGroupTrialGroupsCoPs(ex, trialGroups, refGroup)
% refGroupTrialGroupsCoPs  Intersect plot groups with a compact reference selector.
%
% Supported selectors:
%   ''        disabled
%   't1'      target_num == 1
%   'bg-1'    background_noise_lvl == -1
%   't1bg-1'  target_num == 1 and background_noise_lvl == -1
%   't12bg-1' separate target_num == 1 and target_num == 2 references
%
% If bg-1 is requested but the session has no background_noise_lvl == -1
% trials, bg0 is used as the fallback reference background.

if nargin < 2 || isempty(trialGroups)
    trialGroups = {[]};
end
refTrialGroups = cell(numel(trialGroups), 1);
for i = 1:numel(refTrialGroups)
    refTrialGroups{i} = [];
end

info = struct();
info.enabled = false;
info.requested = "";
info.label = "";
info.labels = strings(0, 1);
info.targetNum = NaN;
info.targetNums = [];
info.requestedBgLevel = NaN;
info.usedBgLevel = NaN;
info.usedBgLevels = [];
info.usedFallbackBg0 = false;
info.usedFallbackBg0ByRef = [];
info.trials = [];
info.trialsByRef = {};
info.nTrials = 0;
info.nTrialsByRef = [];

if nargin < 3 || isempty(refGroup)
    return
end
refGroup = string(refGroup);
refGroup = strtrim(refGroup(1));
if strlength(refGroup) == 0 || ismissing(refGroup)
    return
end
if ~(isstruct(ex) && isscalar(ex) && isfield(ex, 'Trials') && ~isempty(ex.Trials))
    error('refGroupTrialGroupsCoPs:BadInput', ...
        'Reference grouping requires an ex struct with Trials.');
end

spec = localParseRefGroup(refGroup);
if isempty(spec.targetNums) && ~isfinite(spec.bgLevel)
    error('refGroupTrialGroupsCoPs:BadRefGroup', ...
        'Unsupported refGroup ''%s''. Use compact selectors such as ''t1'', ''t12'', ''bg-1'', or ''t1bg-1''.', char(refGroup));
end

targetNum = localTrialTargetNums(ex);
bgLevel = localTrialBackgroundLevels(ex);

nRef = max(1, numel(spec.targetNums));
targetNums = spec.targetNums;
if isempty(targetNums)
    targetNums = NaN(1, nRef);
end
refTrialGroups = cell(numel(trialGroups), nRef);
refTrialsByRef = cell(1, nRef);
labels = strings(nRef, 1);
usedBgLevels = NaN(1, nRef);
usedFallbackBg0ByRef = false(1, nRef);

for r = 1:nRef
    mask = true(1, numel(ex.Trials));
    if isfinite(targetNums(r))
        mask = mask & localNumericEqual(targetNum, targetNums(r));
    end
    usedBgLevel = spec.bgLevel;
    usedFallbackBg0 = false;
    if isfinite(spec.bgLevel)
        if spec.bgLevel == -1 && ~any(localNumericEqual(bgLevel, -1))
            usedBgLevel = 0;
            usedFallbackBg0 = true;
        end
        mask = mask & localNumericEqual(bgLevel, usedBgLevel);
    end
    refTrials = find(mask);
    for i = 1:numel(trialGroups)
        refTrialGroups{i, r} = intersect(double(trialGroups{i}(:))', refTrials, 'stable');
    end
    refTrialsByRef{r} = refTrials;
    labels(r) = localRefLabel(targetNums(r), usedBgLevel);
    if strlength(labels(r)) == 0
        labels(r) = "ref " + refGroup;
    else
        labels(r) = "ref " + labels(r);
    end
    usedBgLevels(r) = usedBgLevel;
    usedFallbackBg0ByRef(r) = usedFallbackBg0;
end

if nRef == 1
    refTrials = refTrialsByRef{1};
    usedBgLevel = usedBgLevels(1);
    usedFallbackBg0 = usedFallbackBg0ByRef(1);
else
    refTrials = unique([refTrialsByRef{:}]);
    if all(isfinite(usedBgLevels)) && numel(unique(usedBgLevels)) == 1
        usedBgLevel = usedBgLevels(1);
    else
        usedBgLevel = NaN;
    end
    usedFallbackBg0 = any(usedFallbackBg0ByRef);
end

info.enabled = true;
info.requested = refGroup;
info.targetNum = targetNums(1);
info.targetNums = targetNums;
info.requestedBgLevel = spec.bgLevel;
info.usedBgLevel = usedBgLevel;
info.usedBgLevels = usedBgLevels;
info.usedFallbackBg0 = usedFallbackBg0;
info.usedFallbackBg0ByRef = usedFallbackBg0ByRef;
info.trials = refTrials;
info.trialsByRef = refTrialsByRef;
info.nTrials = numel(refTrials);
info.nTrialsByRef = cellfun(@numel, refTrialsByRef);
info.labels = labels;
info.label = strjoin(labels(:)', " + ");
end


function spec = localParseRefGroup(refGroup)
code = lower(char(refGroup));
code = regexprep(code, '[\s_=,;]+', '');
spec = struct('targetNums', [], 'bgLevel', NaN);

tok = regexp(code, 't(?:num)?(-?\d+(?:\.\d+)?)', 'tokens', 'once');
if ~isempty(tok)
    spec.targetNums = localParseTargetNums(tok{1});
end

tok = regexp(code, 'bg(-?\d+(?:\.\d+)?)', 'tokens', 'once');
if ~isempty(tok)
    spec.bgLevel = str2double(tok{1});
end


function targetNums = localParseTargetNums(token)
switch token
    case '12'
        targetNums = [1 2];
    case '21'
        targetNums = [2 1];
    otherwise
        targetNums = str2double(token);
end
targetNums = targetNums(isfinite(targetNums));
end
end


function label = localRefLabel(targetNum, bgLevel)
parts = strings(0, 1);
if isfinite(targetNum)
    parts(end+1, 1) = "t" + string(localFormatNumber(targetNum)); %#ok<AGROW>
end
if isfinite(bgLevel)
    parts(end+1, 1) = "bg" + string(localFormatNumber(bgLevel)); %#ok<AGROW>
end
label = strjoin(parts, "");
end


function txt = localFormatNumber(value)
if isfinite(value) && abs(value - round(value)) < 1e-9
    txt = sprintf('%d', round(value));
else
    txt = sprintf('%.6g', value);
end
end


function tf = localNumericEqual(values, target)
tf = isfinite(values) & abs(values - target) < 1e-9;
end


function values = localTrialTargetNums(ex)
values = NaN(1, numel(ex.Trials));
for i = 1:numel(ex.Trials)
    T = ex.Trials(i);
    if isfield(T, 'target_num') && isnumeric(T.target_num) && isscalar(T.target_num) && isfinite(T.target_num)
        values(i) = double(T.target_num);
    end
end
if all(~isfinite(values)) && isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && ...
        isfield(ex.exp.CoPs, 'ctl') && isfield(ex.exp.CoPs.ctl, 'target_num')
    v = ex.exp.CoPs.ctl.target_num;
    if isnumeric(v) && isscalar(v) && isfinite(v)
        values(:) = double(v);
    end
end
end


function values = localTrialBackgroundLevels(ex)
values = NaN(1, numel(ex.Trials));
for i = 1:numel(ex.Trials)
    T = ex.Trials(i);
    if isfield(T, 'background_noise_lvl') && isnumeric(T.background_noise_lvl) && isscalar(T.background_noise_lvl) && isfinite(T.background_noise_lvl)
        values(i) = double(T.background_noise_lvl);
    end
end
end
