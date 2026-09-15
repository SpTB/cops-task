function out = errDistReg(ex, trialNo, opts)
% errDistReg  Relate tracking error to reward-center distance.
%
%   out = errDistReg(ex)
%   out = errDistReg(ex, trialNo)
%   out = errDistReg(ex, 'bg')
%   out = errDistReg(ex, {'bg', 'vis'}, opts)
%   out = errDistReg(ex, trialNo, opts)
%
% Computes Euclidean gaze-to-target error for a selected target, then fits
%   errDeg ~ distanceToRewardCenterDeg
% using step-averaged samples by default.
%
% Options
%   .targetChoice    (default 'gazeCloser') 'gazeCloser', 'rewardCloser',
%                    'target1', or 'target2'
%   .aggregation     (default 'step') 'step' or 'sample'
%   .useEyeTime      (default true) forwarded to reconstructEyePx()
%   .onlyGoState     (default true)
%   .mainTrialsOnly  (default true) skip tutorial/fixation/non-main trials
%   .preprocessGaze  (default false) use CCG-style interpolation/lowpass
%   .interpBlinkSec  (default 0.15) used only when preprocessGaze is true
%   .lowpassHz       (default []) used only when preprocessGaze is true
%   .minSamples      (default 25) minimum rows for regression
%   .nBins           (default 12) binned trend overlay
%   .plot            (default true)
%   .newFigure       (default true)
%
% Named grouping codes
%   'bg'   : one panel/model per background_noise_lvl
%   'vis'  : one panel/model per target_visibility
%   'tnum' : one panel/model per target_num
%   'im'   : one panel/model per imageName/stimPath
%   Cell arrays of codes, e.g. {'bg','vis'}, request intersections.

if nargin < 2
    trialNo = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
if ~isstruct(opts)
    error('errDistReg:BadOpts', 'opts must be a struct.');
end
if ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('errDistReg:BadEx', 'Input ex must contain ex.Trials.');
end

defaults = struct( ...
    'targetChoice', 'gazeCloser', ...
    'aggregation', 'step', ...
    'useEyeTime', true, ...
    'onlyGoState', true, ...
    'mainTrialsOnly', true, ...
    'preprocessGaze', false, ...
    'interpBlinkSec', 0.15, ...
    'lowpassHz', [], ...
    'minSamples', 25, ...
    'nBins', 12, ...
    'plot', true, ...
    'newFigure', true, ...
    'scatterAlpha', 0.18, ...
    'lineWidth', 1.5);
opts = localApplyDefaults(opts, defaults);
opts.targetChoice = validatestring(char(string(opts.targetChoice)), ...
    {'gazeCloser', 'rewardCloser', 'target1', 'target2'});
opts.aggregation = validatestring(char(string(opts.aggregation)), {'step', 'sample'});
opts.useEyeTime = logical(opts.useEyeTime);
opts.onlyGoState = logical(opts.onlyGoState);
opts.mainTrialsOnly = logical(opts.mainTrialsOnly);
opts.preprocessGaze = logical(opts.preprocessGaze);
opts.minSamples = max(1, round(double(localFirstScalar(opts.minSamples))));
opts.nBins = max(2, round(double(localFirstScalar(opts.nBins))));

[groupingSpec, trialGroups, groupLabels] = localResolveGroupingSpec(ex, trialNo, opts);
nGroup = numel(trialGroups);
groups = repmat(localEmptyGroup(), nGroup, 1);
for g = 1:nGroup
    groups(g) = localAnalyzeTrialGroup(ex, trialGroups{g}, g, groupLabels(g), opts);
end

if opts.plot
    localPlotErrorDistanceGroups(groups, opts);
end

out = struct();
out.samples = localVertcatGroupTables(groups, 'samples', localEmptySampleTable());
out.steps = localVertcatGroupTables(groups, 'steps', localEmptyStepTable());
out.fitTable = localVertcatGroupTables(groups, 'fitTable', localEmptyStepTable());
out.stats = localVertcatGroupTables(groups, 'stats', localDefaultStatsTable());
if nGroup == 1
    out.modelDeg = groups(1).modelDeg;
    out.modelZ = groups(1).modelZ;
else
    out.modelDeg = {groups.modelDeg}';
    out.modelZ = {groups.modelZ}';
end
out.groupingSpec = groupingSpec;
out.trialGroups = trialGroups;
out.groupLabels = groupLabels;
out.groups = groups;
out.opts = opts;
out.units = 'deg';
end


function opts = localApplyDefaults(opts, defaults)
fields = fieldnames(defaults);
for i = 1:numel(fields)
    field = fields{i};
    if ~isfield(opts, field)
        opts.(field) = defaults.(field);
    end
end
end


function [groupingSpec, trialGroups, groupLabels] = localResolveGroupingSpec(ex, trialNo, opts)
availableTrials = 1:numel(ex.Trials);
if logical(opts.mainTrialsOnly)
    keepMain = false(size(availableTrials));
    for i = 1:numel(availableTrials)
        keepMain(i) = localIsMainTaskTrial(ex.Trials(availableTrials(i)));
    end
    availableTrials = availableTrials(keepMain);
end

groupingSpec = struct('mode', 'trial', 'codeList', {{}});
if isempty(trialNo) || localIsAllCode(trialNo)
    trialGroups = {availableTrials};
    groupLabels = "all";
    groupingSpec.mode = 'all';
elseif isnumeric(trialNo)
    trialGroups = {localResolveTrialList(ex, trialNo)};
    trialGroups{1} = intersect(trialGroups{1}, availableTrials, 'stable');
    groupLabels = localNumericTrialGroupLabel(trialGroups{1});
elseif localIsNamedCodeSpec(trialNo)
    codeList = localGroupingCodeList(trialNo);
    [trialGroups, groupLabels] = localCombineNamedTrialGroups(ex, availableTrials, codeList);
    groupingSpec.mode = 'named';
    groupingSpec.codeList = codeList;
elseif iscell(trialNo) && localIsNumericGroupCell(trialNo)
    trialGroups = cell(numel(trialNo), 1);
    groupLabels = strings(numel(trialNo), 1);
    for i = 1:numel(trialNo)
        trialGroups{i} = localResolveTrialList(ex, trialNo{i});
        trialGroups{i} = intersect(trialGroups{i}, availableTrials, 'stable');
        groupLabels(i) = "group " + string(i);
    end
    groupingSpec.mode = 'trialCell';
else
    error('errDistReg:BadGrouping', ...
        'Second argument must be [], ''all'', trial numbers, numeric trial groups, or named grouping codes such as ''bg'' and {''bg'',''vis''}.');
end

nonempty = ~cellfun(@isempty, trialGroups);
trialGroups = trialGroups(nonempty);
groupLabels = groupLabels(nonempty);
if isempty(trialGroups)
    error('errDistReg:NoTrials', 'No trials remained after resolving the requested grouping.');
end
groupLabels = groupLabels(:);
end


function group = localAnalyzeTrialGroup(ex, trialList, groupNo, groupLabel, opts)
sampleTables = cell(numel(trialList), 1);
nTables = 0;
for i = 1:numel(trialList)
    j = trialList(i);
    T = ex.Trials(j);
    if opts.mainTrialsOnly && ~localIsMainTaskTrial(T)
        continue
    end
    S = localBuildTrialSampleTable(ex, T, j, opts);
    if isempty(S)
        continue
    end
    nTables = nTables + 1;
    sampleTables{nTables} = S;
end

if nTables == 0
    samples = localEmptySampleTable();
else
    samples = vertcat(sampleTables{1:nTables});
end

steps = localAggregateSamplesToSteps(samples, ex.setup);
switch opts.aggregation
    case 'step'
        fitTable = steps;
    case 'sample'
        fitTable = samples;
end
fitTable = localPrepareFitTable(fitTable);
[modelDeg, modelZ, stats] = localFitErrorDistanceModels(fitTable, opts);

samples = localAddGroupColumns(samples, groupNo, groupLabel);
steps = localAddGroupColumns(steps, groupNo, groupLabel);
fitTable = localAddGroupColumns(fitTable, groupNo, groupLabel);
stats = localAddGroupColumns(stats, groupNo, groupLabel);

group = localEmptyGroup();
group.group = groupNo;
group.groupLabel = string(groupLabel);
group.trials = trialList(:)';
group.samples = samples;
group.steps = steps;
group.fitTable = fitTable;
group.modelDeg = modelDeg;
group.modelZ = modelZ;
group.stats = stats;
end


function group = localEmptyGroup()
group = struct( ...
    'group', NaN, ...
    'groupLabel', "", ...
    'trials', [], ...
    'samples', localEmptySampleTable(), ...
    'steps', localEmptyStepTable(), ...
    'fitTable', localEmptyStepTable(), ...
    'modelDeg', [], ...
    'modelZ', [], ...
    'stats', localDefaultStatsTable());
end


function T = localAddGroupColumns(T, groupNo, groupLabel)
T.group = repmat(double(groupNo), height(T), 1);
T.groupLabel = repmat(string(groupLabel), height(T), 1);
T = movevars(T, {'group', 'groupLabel'}, 'Before', 1);
end


function T = localVertcatGroupTables(groups, fieldName, emptyTable)
if isempty(groups)
    T = emptyTable;
    return
end
tables = cell(numel(groups), 1);
for i = 1:numel(groups)
    tables{i} = groups(i).(fieldName);
end
if isempty(tables)
    T = emptyTable;
else
    T = vertcat(tables{:});
end
end


function trialList = localResolveTrialList(ex, trialNo)
if isempty(trialNo)
    trialList = 1:numel(ex.Trials);
elseif isnumeric(trialNo)
    trialList = double(trialNo(:)');
else
    error('errDistReg:BadTrialList', 'Trial list must be numeric.');
end
trialList = trialList(isfinite(trialList));
trialList = unique(round(trialList), 'stable');
trialList = trialList(trialList >= 1 & trialList <= numel(ex.Trials));
end


function tf = localIsAllCode(x)
tf = (ischar(x) || (isstring(x) && isscalar(x))) && strcmpi(strtrim(char(string(x))), 'all');
end


function tf = localIsNamedCodeSpec(x)
if ischar(x) || (isstring(x) && isscalar(x))
    tf = localIsNamedGroupingCode(x);
elseif iscell(x) && ~isempty(x)
    tf = true;
    for i = 1:numel(x)
        if ~localIsNamedGroupingCode(x{i})
            tf = false;
            return
        end
    end
else
    tf = false;
end
end


function tf = localIsNamedGroupingCode(x)
tf = false;
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    return
end
code = localCanonicalGroupingCode(x);
tf = ismember(code, {'all', 'bg', 'vis', 'tnum', 'im'});
end


function codeList = localGroupingCodeList(spec)
if ischar(spec) || (isstring(spec) && isscalar(spec))
    codeList = {localCanonicalGroupingCode(spec)};
else
    codeList = cell(numel(spec), 1);
    for i = 1:numel(spec)
        codeList{i} = localCanonicalGroupingCode(spec{i});
    end
end
end


function tf = localIsNumericGroupCell(x)
tf = iscell(x) && ~isempty(x);
if ~tf
    return
end
for i = 1:numel(x)
    if ~isnumeric(x{i})
        tf = false;
        return
    end
end
end


function [trialGroups, groupLabels] = localCombineNamedTrialGroups(ex, availableTrials, codeList)
trialGroups = {availableTrials};
groupLabels = "all";
for k = 1:numel(codeList)
    code = localCanonicalGroupingCode(codeList{k});
    [nextGroups, nextLabels] = localResolveNamedTrialGroupsFromEx(ex, availableTrials, code);
    combined = {};
    combinedLabels = strings(0, 1);
    nOut = 0;
    for i = 1:numel(trialGroups)
        for j = 1:numel(nextGroups)
            g = intersect(trialGroups{i}, nextGroups{j}, 'stable');
            if isempty(g)
                continue
            end
            nOut = nOut + 1;
            combined{nOut, 1} = g; %#ok<AGROW>
            if strcmp(groupLabels(i), "all")
                combinedLabels(nOut, 1) = nextLabels(j);
            else
                combinedLabels(nOut, 1) = groupLabels(i) + " | " + nextLabels(j);
            end
        end
    end
    trialGroups = combined;
    groupLabels = combinedLabels;
    if isempty(trialGroups)
        break
    end
end
if isempty(trialGroups)
    error('errDistReg:NamedGroupEmpty', ...
        'No trials remained after combining the requested named groupings.');
end
end


function [trialGroups, groupLabels] = localResolveNamedTrialGroupsFromEx(ex, availableTrials, code)
code = localCanonicalGroupingCode(code);
switch code
    case 'all'
        trialGroups = {availableTrials};
        groupLabels = "all";
    case {'bg', 'vis', 'tnum'}
        values = NaN(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            T = ex.Trials(j);
            switch code
                case 'bg'
                    values(j) = localTrialBackgroundNoiseLevel(T);
                case 'vis'
                    values(j) = localTrialTargetVisibility(ex, T);
                case 'tnum'
                    values(j) = localTrialTargetNum(ex, T);
            end
        end
        keep = isfinite(values) & ismember(1:numel(values), availableTrials);
        levels = unique(values(keep));
        if isempty(levels)
            error('errDistReg:NamedGroupEmpty', ...
                'No available trials had finite values for grouping code ''%s''.', code);
        end
        trialGroups = cell(numel(levels), 1);
        groupLabels = strings(numel(levels), 1);
        for i = 1:numel(levels)
            trialGroups{i} = find(values == levels(i));
            trialGroups{i} = intersect(trialGroups{i}, availableTrials, 'stable');
            groupLabels(i) = string(code) + ": " + string(levels(i));
        end
    case 'im'
        values = strings(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            values(j) = localTrialImageName(ex, ex.Trials(j), j);
        end
        keep = strlength(strtrim(values)) > 0 & ~ismissing(values) & ismember(1:numel(values), availableTrials);
        levels = unique(values(keep), 'stable');
        if isempty(levels)
            error('errDistReg:NamedGroupEmpty', ...
                'No available trials had finite imageName/stimPath values.');
        end
        trialGroups = cell(numel(levels), 1);
        groupLabels = strings(numel(levels), 1);
        for i = 1:numel(levels)
            trialGroups{i} = find(values == levels(i));
            trialGroups{i} = intersect(trialGroups{i}, availableTrials, 'stable');
            groupLabels(i) = "im: " + levels(i);
        end
    otherwise
        error('errDistReg:UnknownGroupingCode', ...
            'Unknown grouping code ''%s''. Supported codes are ''all'', ''bg'', ''vis'', ''tnum'', and ''im''.', code);
end
end


function code = localCanonicalGroupingCode(code)
code = lower(strtrim(char(string(code))));
end


function label = localNumericTrialGroupLabel(trialList)
if isempty(trialList)
    label = "trials: empty";
elseif isscalar(trialList)
    label = "trial: " + string(trialList);
else
    label = "trials: " + string(trialList(1)) + "-" + string(trialList(end));
end
end


function noiseLevel = localTrialBackgroundNoiseLevel(T)
noiseLevel = NaN;
if isfield(T, 'background_noise_lvl') && isnumeric(T.background_noise_lvl) && isscalar(T.background_noise_lvl)
    noiseLevel = double(T.background_noise_lvl);
end
end


function value = localTrialTargetVisibility(ex, T)
value = NaN;
if isfield(T, 'target_visibility') && isnumeric(T.target_visibility) && isscalar(T.target_visibility)
    value = double(T.target_visibility);
elseif isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'graph') && ...
        isfield(ex.exp.CoPs.graph, 'target_visibility')
    v = ex.exp.CoPs.graph.target_visibility;
    if isnumeric(v) && isscalar(v) && isfinite(v)
        value = double(v);
    end
end
end


function value = localTrialTargetNum(ex, T)
value = NaN;
if isfield(T, 'target_num') && isnumeric(T.target_num) && isscalar(T.target_num)
    value = double(T.target_num);
elseif isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'ctl') && ...
        isfield(ex.exp.CoPs.ctl, 'target_num')
    v = ex.exp.CoPs.ctl.target_num;
    if isnumeric(v) && isscalar(v) && isfinite(v)
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
    if strlength(candidate) > 0
        imageName = candidate;
        return
    end
end
if isfield(ex, 'stim') && isstruct(ex.stim) && isfield(ex.stim, 'seq') && numel(ex.stim.seq) >= trialIdx
    candidate = localBasenameString(string(ex.stim.seq{trialIdx}));
    if strlength(candidate) > 0
        imageName = candidate;
    end
end
end


function out = localBasenameString(pathValue)
out = string(missing);
if ismissing(pathValue) || strlength(strtrim(pathValue)) == 0
    return
end
[~, name, ext] = fileparts(char(pathValue));
out = string([name ext]);
end


function tf = localIsMainTaskTrial(T)
isFixationTrial = isfield(T, 'isFixationTrial') && logical(T.isFixationTrial);
isTutorialTrial = isfield(T, 'isTutorialTrial') && logical(T.isTutorialTrial);
if isFixationTrial || isTutorialTrial
    tf = false;
    return
end
if isfield(T, 'runPhase') && ~isempty(T.runPhase)
    tf = string(T.runPhase) == "main";
else
    tf = true;
end
end


function S = localBuildTrialSampleTable(ex, T, trialNo, opts)
S = localEmptySampleTable();
[xPx, yPx, tRel, tAbs, valid] = reconstructEyePx(ex, T, opts.useEyeTime, opts);
if isempty(tRel)
    return
end
[targetX, targetY, target2X, target2Y, stepIdx] = mapTargetsByStep(ex, T, tRel);

goMask = true(size(tRel));
if opts.onlyGoState && isfield(T, 'times') && isfield(T.times, 'stimOn') && isfield(T, 'TrialEnd')
    goMask = tAbs >= T.times.stimOn & tAbs <= T.TrialEnd;
end

xPx = xPx(goMask);
yPx = yPx(goMask);
tRel = tRel(goMask);
tAbs = tAbs(goMask);
valid = valid(goMask);
targetX = targetX(goMask);
targetY = targetY(goMask);
target2X = target2X(goMask);
target2Y = target2Y(goMask);
stepIdx = stepIdx(goMask);

dtSec = 1 / inferFs(ex);
if opts.preprocessGaze
    [xPx, yPx] = preprocessGazeForCcgCoPs(xPx, yPx, dtSec, opts.interpBlinkSec, opts.lowpassHz);
end

inBounds = valid(:) & localGazeInTexture(ex, xPx, yPx);
gaussCtr = getGaussianCenterPx(ex, T);
[selX, selY, selectedTarget, errPx] = localSelectTarget( ...
    xPx, yPx, targetX, targetY, target2X, target2Y, gaussCtr, opts.targetChoice);
distRewPx = hypot(selX - gaussCtr(1), selY - gaussCtr(2));
errDeg = px2deg(errPx, ex.setup);
distRewDeg = px2deg(distRewPx, ex.setup);

keep = inBounds(:) & isfinite(stepIdx(:)) & isfinite(errDeg(:)) & isfinite(distRewDeg(:));
if ~any(keep)
    return
end

n = nnz(keep);
S = table( ...
    repmat(double(trialNo), n, 1), ...
    double(stepIdx(keep)), ...
    double(tRel(keep)), ...
    double(tAbs(keep)), ...
    double(xPx(keep)), ...
    double(yPx(keep)), ...
    double(selX(keep)), ...
    double(selY(keep)), ...
    double(selectedTarget(keep)), ...
    double(errPx(keep)), ...
    double(errDeg(keep)), ...
    double(distRewPx(keep)), ...
    double(distRewDeg(keep)), ...
    repmat(double(gaussCtr(1)), n, 1), ...
    repmat(double(gaussCtr(2)), n, 1), ...
    'VariableNames', {'trial','step','tRelSec','tAbsSec','gazeX','gazeY', ...
    'targetX','targetY','selectedTarget','errPx','errDeg', ...
    'distRewPx','distRewDeg','gaussCtrX','gaussCtrY'});
end


function [selX, selY, selectedTarget, errPx] = localSelectTarget( ...
    gazeX, gazeY, targetX, targetY, target2X, target2Y, gaussCtr, targetChoice)
gazeX = double(gazeX(:));
gazeY = double(gazeY(:));
targetX = double(targetX(:));
targetY = double(targetY(:));
target2X = double(target2X(:));
target2Y = double(target2Y(:));

n = numel(gazeX);
selX = targetX;
selY = targetY;
selectedTarget = ones(n, 1);

d1 = hypot(gazeX - targetX, gazeY - targetY);
d2 = hypot(gazeX - target2X, gazeY - target2Y);
hasT2 = isfinite(target2X) & isfinite(target2Y);

switch char(string(targetChoice))
    case 'gazeCloser'
        useT2 = hasT2 & isfinite(d2) & ((~isfinite(d1)) | d2 < d1);
    case 'rewardCloser'
        r1 = hypot(targetX - gaussCtr(1), targetY - gaussCtr(2));
        r2 = hypot(target2X - gaussCtr(1), target2Y - gaussCtr(2));
        useT2 = hasT2 & isfinite(r2) & ((~isfinite(r1)) | r2 < r1);
    case 'target1'
        useT2 = false(n, 1);
    case 'target2'
        useT2 = hasT2;
end

selX(useT2) = target2X(useT2);
selY(useT2) = target2Y(useT2);
selectedTarget(useT2) = 2;
errPx = hypot(gazeX - selX, gazeY - selY);
selectedTarget(~isfinite(selX) | ~isfinite(selY)) = NaN;
end


function inBounds = localGazeInTexture(ex, xPx, yPx)
xPx = double(xPx(:));
yPx = double(yPx(:));
inBounds = isfinite(xPx) & isfinite(yPx);
if ~isfield(ex, 'setup') || ~isfield(ex.setup, 'screenRect') || ...
        ~isfield(ex, 'exp') || ~isfield(ex.exp, 'CoPs') || ~isfield(ex.exp.CoPs, 'graph')
    return
end
screenRect = double(ex.setup.screenRect);
graph = ex.exp.CoPs.graph;
if ~isfield(graph, 'texture_dims') || ~isfield(graph, 'size_mult')
    return
end
texW = double(graph.texture_dims(1)) * double(graph.size_mult);
texH = double(graph.texture_dims(min(2, numel(graph.texture_dims)))) * double(graph.size_mult);
xMin = (screenRect(3) - texW) / 2;
yMin = (screenRect(4) - texH) / 2;
xMax = xMin + texW;
yMax = yMin + texH;
inBounds = inBounds & xPx >= xMin & xPx <= xMax & yPx >= yMin & yPx <= yMax;
end


function steps = localAggregateSamplesToSteps(samples, setup)
steps = localEmptyStepTable();
if isempty(samples)
    return
end
[G, key] = findgroups(samples(:, {'trial','step'}));
if isempty(G)
    return
end
steps = table();
steps.trial = key.trial;
steps.step = key.step;
steps.tRelSec = splitapply(@(x) mean(x, 'omitnan'), samples.tRelSec, G);
steps.nSamples = splitapply(@numel, samples.errPx, G);
steps.errPx = splitapply(@(x) mean(x, 'omitnan'), samples.errPx, G);
steps.errDeg = splitapply(@(x) mean(x, 'omitnan'), samples.errDeg, G);
steps.distRewPx = splitapply(@(x) mean(x, 'omitnan'), samples.distRewPx, G);
steps.distRewDeg = splitapply(@(x) mean(x, 'omitnan'), samples.distRewDeg, G);
steps.targetX = splitapply(@(x) mean(x, 'omitnan'), samples.targetX, G);
steps.targetY = splitapply(@(x) mean(x, 'omitnan'), samples.targetY, G);
steps.selectedTarget = splitapply(@localModeOrNaN, samples.selectedTarget, G);
steps.gaussCtrX = splitapply(@(x) mean(x, 'omitnan'), samples.gaussCtrX, G);
steps.gaussCtrY = splitapply(@(x) mean(x, 'omitnan'), samples.gaussCtrY, G);
steps = sortrows(steps, {'trial','step'});
steps.targetStepAmpPx = localStepAmplitudes(steps);
steps.targetStepAmpDeg = px2deg(steps.targetStepAmpPx, setup);
end


function amp = localStepAmplitudes(steps)
amp = NaN(height(steps), 1);
if isempty(steps)
    return
end
trials = unique(steps.trial(:)', 'stable');
for i = 1:numel(trials)
    rows = find(steps.trial == trials(i));
    if numel(rows) < 2
        continue
    end
    dx = diff(steps.targetX(rows));
    dy = diff(steps.targetY(rows));
    amp(rows(2:end)) = hypot(dx, dy);
end
end


function value = localModeOrNaN(x)
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    value = mode(x);
end
end


function fitTable = localPrepareFitTable(fitTable)
if isempty(fitTable)
    return
end
keep = isfinite(fitTable.errDeg) & isfinite(fitTable.distRewDeg);
fitTable = fitTable(keep, :);
if isempty(fitTable)
    return
end
mu = mean(fitTable.distRewDeg, 'omitnan');
sd = std(fitTable.distRewDeg, 0, 'omitnan');
if ~isfinite(sd) || sd <= eps
    fitTable.distRewZ = NaN(height(fitTable), 1);
else
    fitTable.distRewZ = (fitTable.distRewDeg - mu) ./ sd;
end
end


function stats = localDefaultStatsTable()
stats = table(0, NaN, NaN, NaN, NaN, NaN, NaN, ...
    'VariableNames', {'n','slopeDegPerDeg','interceptDeg','slopeDegPerDistSD', ...
    'pSlopeZ','r2','corrPearson'});
end


function [modelDeg, modelZ, stats] = localFitErrorDistanceModels(fitTable, opts)
modelDeg = [];
modelZ = [];
stats = localDefaultStatsTable();
if isempty(fitTable) || height(fitTable) < opts.minSamples || ~isfinite(fitTable.distRewZ(1))
    return
end

xDeg = double(fitTable.distRewDeg(:));
xZ = double(fitTable.distRewZ(:));
y = double(fitTable.errDeg(:));
valid = isfinite(xDeg) & isfinite(xZ) & isfinite(y);
xDeg = xDeg(valid);
xZ = xZ(valid);
y = y(valid);
if numel(y) < opts.minSamples
    return
end

stats.n = numel(y);
stats.corrPearson = corr(xDeg, y, 'Rows', 'complete');
if exist('fitlm', 'file') == 2
    T = table(xDeg, xZ, y, 'VariableNames', {'distRewDeg','distRewZ','errDeg'});
    modelDeg = fitlm(T, 'errDeg ~ distRewDeg');
    modelZ = fitlm(T, 'errDeg ~ distRewZ');
    stats.slopeDegPerDeg = modelDeg.Coefficients.Estimate(2);
    stats.interceptDeg = modelDeg.Coefficients.Estimate(1);
    stats.slopeDegPerDistSD = modelZ.Coefficients.Estimate(2);
    stats.pSlopeZ = modelZ.Coefficients.pValue(2);
    stats.r2 = modelZ.Rsquared.Ordinary;
else
    Xdeg = [ones(numel(y), 1), xDeg];
    Xz = [ones(numel(y), 1), xZ];
    bDeg = Xdeg \ y;
    bZ = Xz \ y;
    yHat = Xz * bZ;
    stats.slopeDegPerDeg = bDeg(2);
    stats.interceptDeg = bDeg(1);
    stats.slopeDegPerDistSD = bZ(2);
    stats.r2 = localR2(y, yHat);
end
end


function localPlotErrorDistanceGroups(groups, opts)
if opts.newFigure
    figure;
end
nGroup = numel(groups);
plotOpts = opts;
plotOpts.newFigure = false;
if nGroup <= 1
    localPlotErrorDistance(groups(1).fitTable, groups(1).modelDeg, groups(1).stats, plotOpts, groups(1).groupLabel, true);
    return
end
nCol = min(3, ceil(sqrt(nGroup)));
nRow = ceil(nGroup ./ nCol);
tiledlayout(nRow, nCol, 'Padding', 'compact', 'TileSpacing', 'compact');
for g = 1:nGroup
    nexttile;
    localPlotErrorDistance(groups(g).fitTable, groups(g).modelDeg, groups(g).stats, plotOpts, groups(g).groupLabel, false);
end
sgtitle(sprintf('errDistReg (%d group%s)', nGroup, localPlural(nGroup)), 'Interpreter', 'none');
end


function localPlotErrorDistance(fitTable, modelDeg, stats, opts, panelLabel, showLegend)
if nargin < 5 || isempty(panelLabel)
    panelLabel = "all";
end
if nargin < 6
    showLegend = true;
end
if opts.newFigure
    figure;
end
hold on
if isempty(fitTable)
    title(sprintf('%s | no usable rows', char(string(panelLabel))), 'Interpreter', 'none');
    return
end
x = double(fitTable.distRewDeg(:));
y = double(fitTable.errDeg(:));
scatter(x, y, 12, [0.25 0.35 0.50], 'filled', ...
    'MarkerFaceAlpha', opts.scatterAlpha, 'MarkerEdgeAlpha', opts.scatterAlpha);

B = localBinnedSummary(x, y, opts.nBins);
if ~isempty(B)
    errorbar(B.xMean, B.yMean, B.ySem, 'o-', ...
        'Color', [0.90 0.35 0.10], 'MarkerFaceColor', [0.90 0.35 0.10], ...
        'LineWidth', opts.lineWidth);
end

if ~isempty(modelDeg)
    xx = linspace(min(x, [], 'omitnan'), max(x, [], 'omitnan'), 200)';
    yy = predict(modelDeg, table(xx, 'VariableNames', {'distRewDeg'}));
    plot(xx, yy, '-', 'Color', [0.05 0.05 0.05], 'LineWidth', opts.lineWidth);
elseif isfinite(stats.slopeDegPerDeg)
    xx = linspace(min(x, [], 'omitnan'), max(x, [], 'omitnan'), 200)';
    yy = stats.interceptDeg + stats.slopeDegPerDeg .* xx;
    plot(xx, yy, '-', 'Color', [0.05 0.05 0.05], 'LineWidth', opts.lineWidth);
end

xlabel('Selected-target distance to reward center (deg)');
ylabel('Gaze-target error (deg)');
titleText = sprintf('err ~ reward distance | slope %.3g deg/SD, R2 %.3g', ...
    stats.slopeDegPerDistSD, stats.r2);
if isfinite(stats.pSlopeZ)
    titleText = sprintf('%s, p %.3g', titleText, stats.pSlopeZ);
end
title(sprintf('%s | %s', char(string(panelLabel)), titleText), 'Interpreter', 'none');
grid on
box off
if showLegend
    legend({'steps/samples','binned mean','linear fit'}, 'Location', 'northeastoutside', 'Interpreter', 'none');
end
hold off
end


function B = localBinnedSummary(x, y, nBins)
B = table();
valid = isfinite(x) & isfinite(y);
x = x(valid);
y = y(valid);
if numel(y) < nBins
    return
end
edges = quantile(x, linspace(0, 1, nBins + 1));
edges = unique(edges);
if numel(edges) < 3
    return
end
edges(1) = -Inf;
edges(end) = Inf;
bin = discretize(x, edges);
keep = isfinite(bin);
if ~any(keep)
    return
end
[G, binId] = findgroups(bin(keep));
yKeep = y(keep);
xKeep = x(keep);
B = table();
B.bin = binId;
B.n = splitapply(@numel, yKeep, G);
B.xMean = splitapply(@(v) mean(v, 'omitnan'), xKeep, G);
B.yMean = splitapply(@(v) mean(v, 'omitnan'), yKeep, G);
B.ySem = splitapply(@localSem, yKeep, G);
end


function s = localSem(x)
x = x(isfinite(x));
if numel(x) < 2
    s = NaN;
else
    s = std(x) ./ sqrt(numel(x));
end
end


function r2 = localR2(y, yHat)
valid = isfinite(y) & isfinite(yHat);
if nnz(valid) < 2
    r2 = NaN;
    return
end
y = y(valid);
yHat = yHat(valid);
sst = sum((y - mean(y)).^2);
if sst <= eps
    r2 = NaN;
else
    r2 = 1 - sum((y - yHat).^2) ./ sst;
end
end


function T = localEmptySampleTable()
T = table( ...
    NaN(0, 1), NaN(0, 1), NaN(0, 1), NaN(0, 1), ...
    NaN(0, 1), NaN(0, 1), NaN(0, 1), NaN(0, 1), ...
    NaN(0, 1), NaN(0, 1), NaN(0, 1), NaN(0, 1), ...
    NaN(0, 1), NaN(0, 1), NaN(0, 1), ...
    'VariableNames', {'trial','step','tRelSec','tAbsSec','gazeX','gazeY', ...
    'targetX','targetY','selectedTarget','errPx','errDeg', ...
    'distRewPx','distRewDeg','gaussCtrX','gaussCtrY'});
end


function T = localEmptyStepTable()
T = table( ...
    NaN(0, 1), NaN(0, 1), NaN(0, 1), NaN(0, 1), ...
    NaN(0, 1), NaN(0, 1), NaN(0, 1), NaN(0, 1), ...
    NaN(0, 1), NaN(0, 1), NaN(0, 1), NaN(0, 1), ...
    NaN(0, 1), NaN(0, 1), NaN(0, 1), ...
    'VariableNames', {'trial','step','tRelSec','nSamples','errPx','errDeg', ...
    'distRewPx','distRewDeg','targetX','targetY','selectedTarget', ...
    'gaussCtrX','gaussCtrY','targetStepAmpPx','targetStepAmpDeg'});
end


function value = localFirstScalar(x)
value = NaN;
if isempty(x)
    return
end
if isscalar(x) && isfinite(double(x))
    value = double(x);
else
    value = double(x(1));
end
end


function suffix = localPlural(n)
if n == 1
    suffix = '';
else
    suffix = 's';
end
end
