function out = rewardTriggeredSaccades(ex, trialNo, opts)
% rewardTriggeredSaccades  Build reward-aligned saccade event table for CoPs.
%
%   out = rewardTriggeredSaccades(ex)
%   out = rewardTriggeredSaccades(ex, 1:120)
%   out = rewardTriggeredSaccades(ex, 'bg')
%   out = rewardTriggeredSaccades(ex, {'bg','vis'}, opts)
%
% Output
%   out.rewardSaccades : one row per reward-aligned saccade, or one
%                        placeholder row per reward when no saccade falls
%                        inside opts.windowSec

if nargin < 2
    trialNo = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
if ~isstruct(ex) || ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('rewardTriggeredSaccades:BadInput', 'First input must be an ex struct with Trials.');
end
if ~isstruct(opts)
    error('rewardTriggeredSaccades:BadOpts', 'Third argument must be an opts struct.');
end

defaults = struct( ...
    'onlyGoState', true, ...
    'useEyeTime', true, ...
    'lowpassHz', [], ...
    'interpBlinkSec', 0.15, ...
    'truncateTrialFromStep', 0, ...
    'timeWindowSec', [], ...
    'windowSec', [-0.5 2.5], ...
    'errLagSec', 0, ...
    'errLagMs', [], ...
    'speedThreshDegPerSec', 10, ...
    'minAmpDeg', 1, ...
    'minDurSec', 0.008, ...
    'maxDurSec', 1, ...
    'smoothFrames', 5);
opts = localApplyLegacySaccadeAliases(opts);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field) || isempty(opts.(field))
        opts.(field) = defaults.(field);
    end
end
if isempty(opts.errLagSec) && ~isempty(opts.errLagMs)
    opts.errLagSec = double(opts.errLagMs) ./ 1000;
elseif ~isempty(opts.errLagMs)
    opts.errLagSec = double(opts.errLagMs) ./ 1000;
end
opts.windowSec = double(opts.windowSec(:)');
if numel(opts.windowSec) ~= 2 || ~all(isfinite(opts.windowSec)) || opts.windowSec(2) <= opts.windowSec(1)
    error('rewardTriggeredSaccades:BadWindow', ...
        'opts.windowSec must be a finite 1x2 increasing vector.');
end
opts.errLagSec = double(localFirstScalar(opts.errLagSec));
if ~isfinite(opts.errLagSec)
    error('rewardTriggeredSaccades:BadErrLag', ...
        'opts.errLagSec must be a finite scalar.');
end

trialGroups = localNormalizeTrialGroups(trialNo, ex);
groupLabels = localBuildGroupLabels(trialNo, trialGroups, ex);
rows = cell(numel(ex.Trials) * max(1, numel(trialGroups)), 1);
rowCount = 0;
for g = 1:numel(trialGroups)
    groupTrials = trialGroups{g};
    for i = 1:numel(groupTrials)
        trialIdx = groupTrials(i);
        trialRows = localBuildTrialRewardSaccades(ex, trialIdx, g, opts);
        if isempty(trialRows)
            continue
        end
        rowCount = rowCount + 1;
        rows{rowCount, 1} = trialRows;
    end
end

if rowCount == 0
    rewardSaccades = table();
else
    rewardSaccades = vertcat(rows{1:rowCount});
    for g = 1:numel(groupLabels)
        rewardSaccades.groupLabel(double(rewardSaccades.group) == g) = groupLabels(g);
    end
end

out = struct();
out.rewardSaccades = rewardSaccades;
out.trials = localFlattenTrialGroups(trialGroups);
out.trialGroups = trialGroups;
out.groupLabels = groupLabels;
out.options = opts;
end


function rows = localBuildTrialRewardSaccades(ex, trialIdx, groupNo, opts)
T = ex.Trials(trialIdx);
[xPx, yPx, tRel, tAbs, valid] = reconstructEyePx(ex, T, opts.useEyeTime, opts);
[targetX, targetY, ~, ~, stepIdx] = mapTargetsByStep(ex, T, tRel);

goMask = true(size(tRel));
if opts.onlyGoState && isfield(T, 'times') && isfield(T.times, 'stimOn') && isfield(T, 'TrialEnd')
    goMask = tAbs >= T.times.stimOn & tAbs <= T.TrialEnd;
end

xPx = xPx(goMask);
yPx = yPx(goMask);
tRel = tRel(goMask);
valid = valid(goMask);
targetX = targetX(goMask);
targetY = targetY(goMask);
stepIdx = stepIdx(goMask);

truncateFromStep = double(localFirstScalar(opts.truncateTrialFromStep));
if isfinite(truncateFromStep) && truncateFromStep > 0
    keepMask = isfinite(stepIdx) & stepIdx >= truncateFromStep;
    xPx = xPx(keepMask);
    yPx = yPx(keepMask);
    tRel = tRel(keepMask);
    valid = valid(keepMask);
    targetX = targetX(keepMask);
    targetY = targetY(keepMask);
    stepIdx = stepIdx(keepMask);
end

tw = localTimeWindow(opts.timeWindowSec);
if ~isempty(tw)
    keepMask = tRel >= tw(1) & tRel <= tw(2);
    xPx = xPx(keepMask);
    yPx = yPx(keepMask);
    tRel = tRel(keepMask);
    valid = valid(keepMask);
    targetX = targetX(keepMask);
    targetY = targetY(keepMask);
    stepIdx = stepIdx(keepMask);
end

if isempty(tRel) || numel(tRel) < 2
    rows = table();
    return
end

texBounds = localTextureBounds(ex.setup.screenRect, ex.exp.CoPs.graph);
insideTexture = xPx >= texBounds.xMin & xPx <= texBounds.xMax & ...
    yPx >= texBounds.yMin & yPx <= texBounds.yMax;
xPx(~insideTexture) = NaN;
yPx(~insideTexture) = NaN;
valid = valid & insideTexture;
xPx(~valid) = NaN;
yPx(~valid) = NaN;

dtSec = localResolveSampleDt(tRel, 1 / inferFs(ex));
[xPx, yPx] = preprocessGazeForCcgCoPs(xPx, yPx, dtSec, opts.interpBlinkSec, opts.lowpassHz);

saccParams = localBuildSaccadeParams(dtSec, opts);
[saccStarts, saccStops, speedDegPerSec] = detectTrackingSaccadesCoPs( ...
    xPx, yPx, dtSec, ex.setup, saccParams);

rewardTimes = localRewardTimesRelSec(T, tRel, stepIdx, truncateFromStep);
if isempty(rewardTimes)
    rows = table();
    return
end

bg = localTrialBackgroundNoiseLevel(T);
vis = localTrialTargetVisibility(ex, T);
tnum = localTrialTargetNum(ex, T);
imageName = localTrialImageName(ex, T, trialIdx);

rowCells = cell(numel(rewardTimes), 1);
rowCount = 0;
for r = 1:numel(rewardTimes)
    if isempty(saccStarts)
        keep = false(0,1);
    else
        rel = double(tRel(saccStarts)) - rewardTimes(r);
        keep = rel >= opts.windowSec(1) & rel <= opts.windowSec(2);
    end
    if any(keep)
        idxKeep = find(keep);
        nKeep = numel(idxKeep);
        startSec = double(tRel(saccStarts(idxKeep)));
        stopSec = double(tRel(saccStops(idxKeep)));
        ampPx = hypot(double(xPx(saccStops(idxKeep))) - double(xPx(saccStarts(idxKeep))), ...
            double(yPx(saccStops(idxKeep))) - double(yPx(saccStarts(idxKeep))));
        ampDeg = px2deg(ampPx, ex.setup);
        [targetXErr, targetYErr, errRefSec] = localLaggedTargetAtIndices( ...
            targetX, targetY, tRel, double(saccStops(idxKeep)), opts.errLagSec);
        errPx = hypot(double(xPx(saccStops(idxKeep))) - targetXErr, ...
            double(yPx(saccStops(idxKeep))) - targetYErr);
        errDeg = px2deg(errPx, ex.setup);
        peakSpeed = NaN(nKeep, 1);
        for k = 1:nKeep
            s0 = saccStarts(idxKeep(k));
            s1 = saccStops(idxKeep(k));
            peakSpeed(k) = max(speedDegPerSec(s0:s1), [], 'omitnan');
        end
        rowCount = rowCount + 1;
        rowCells{rowCount,1} = table( ...
            repmat(groupNo, nKeep, 1), repmat(string(missing), nKeep, 1), ...
            repmat(trialIdx, nKeep, 1), repmat(r, nKeep, 1), ...
            rewardTimes(r) * ones(nKeep, 1), ...
            idxKeep, ...
            double(saccStarts(idxKeep)), double(saccStops(idxKeep)), ...
            startSec, stopSec, ...
            startSec - rewardTimes(r), ...
            ampPx, ampDeg, errPx, errDeg, ...
            opts.errLagSec * ones(nKeep, 1), errRefSec, ...
            peakSpeed, ...
            repmat(bg, nKeep, 1), repmat(vis, nKeep, 1), repmat(tnum, nKeep, 1), repmat(imageName, nKeep, 1), ...
            true(nKeep, 1), ...
            'VariableNames', {'group','groupLabel','trial','rewardNo','rewardTimeRelSec', ...
            'saccNo','startIdx','stopIdx','startSec','stopSec','tFromRewardSec', ...
            'saccAmpPx','saccAmpDeg','saccErrPx','saccErrDeg','saccErrLagSec','saccErrRefSec','peakSpeedDegPerSec', ...
            'backgroundNoiseLvl','targetVisibility','targetNum','imageName','hasSaccade'});
    else
        rowCount = rowCount + 1;
        rowCells{rowCount,1} = table( ...
            groupNo, string(missing), trialIdx, r, rewardTimes(r), ...
            NaN, NaN, NaN, NaN, NaN, NaN, ...
            NaN, NaN, NaN, NaN, opts.errLagSec, NaN, NaN, ...
            bg, vis, tnum, imageName, false, ...
            'VariableNames', {'group','groupLabel','trial','rewardNo','rewardTimeRelSec', ...
            'saccNo','startIdx','stopIdx','startSec','stopSec','tFromRewardSec', ...
            'saccAmpPx','saccAmpDeg','saccErrPx','saccErrDeg','saccErrLagSec','saccErrRefSec','peakSpeedDegPerSec', ...
            'backgroundNoiseLvl','targetVisibility','targetNum','imageName','hasSaccade'});
    end
end

if rowCount == 0
    rows = table();
else
    rows = vertcat(rowCells{1:rowCount});
end
end


function rewardTimes = localRewardTimesRelSec(T, tRel, stepIdx, analysisStartStep)
rewardTimes = [];
if ~isfield(T, 'times') || ~isfield(T.times, 'reward') || isempty(T.times.reward)
    return
end
rewardTimes = T.times.reward(:);
rewardTimes = rewardTimes(isfinite(rewardTimes));
if isempty(rewardTimes)
    return
end
if isfield(T, 'TrialStart') && isfinite(T.TrialStart)
    rewardTimes = rewardTimes - T.TrialStart;
end
if nargin >= 4 && isfinite(analysisStartStep) && analysisStartStep > 0
    analysisStartTime = min(tRel(isfinite(tRel) & isfinite(stepIdx) & stepIdx >= analysisStartStep), [], 'omitnan');
    if isfinite(analysisStartTime)
        rewardTimes = rewardTimes(rewardTimes >= analysisStartTime);
    end
end
trialEndTime = max(tRel, [], 'omitnan');
if isfinite(trialEndTime)
    rewardTimes = rewardTimes(rewardTimes <= trialEndTime);
end
end


function out = localTimeWindow(windowValue)
out = [];
if isempty(windowValue)
    return
end
out = double(windowValue(:)');
if numel(out) ~= 2 || ~all(isfinite(out)) || out(2) <= out(1)
    error('rewardTriggeredSaccades:BadTimeWindow', ...
        'opts.timeWindowSec must be empty or a finite 1x2 increasing vector.');
end
end


function params = localBuildSaccadeParams(dtSec, opts)
params = struct();
params.preSaccadeWindowFrames = 3;
params.speedThreshDegPerSec = double(localFirstScalar(opts.speedThreshDegPerSec));
if ~isfinite(params.speedThreshDegPerSec) || params.speedThreshDegPerSec <= 0
    params.speedThreshDegPerSec = 10;
end
params.minAmpDeg = double(localFirstScalar(opts.minAmpDeg));
params.minDurSec = double(localFirstScalar(opts.minDurSec));
params.maxDurSec = double(localFirstScalar(opts.maxDurSec));
params.smoothFrames = max(1, round(double(localFirstScalar(opts.smoothFrames))));
if ~isfinite(dtSec) || dtSec <= 0
    params.preSaccadeWindowFrames = max(1, params.preSaccadeWindowFrames);
    params.minDurFrames = 1;
    params.maxDurFrames = inf;
else
    params.preSaccadeWindowSec = params.preSaccadeWindowFrames * dtSec;
    params.minDurFrames = max(1, round(params.minDurSec / dtSec));
    if isfinite(params.maxDurSec)
        params.maxDurFrames = max(params.minDurFrames, round(params.maxDurSec / dtSec));
    else
        params.maxDurFrames = inf;
    end
end
end


function [targetXRef, targetYRef, refSec] = localLaggedTargetAtIndices(targetX, targetY, tRel, idx, lagSec)
idx = double(idx(:));
tStop = double(tRel(idx));
tRef = tStop - lagSec;
targetXRef = NaN(size(idx));
targetYRef = NaN(size(idx));
refSec = NaN(size(idx));
for i = 1:numel(idx)
    j = find(isfinite(tRel) & (double(tRel) <= tRef(i)), 1, 'last');
    if isempty(j)
        j = find(isfinite(tRel), 1, 'first');
    end
    if isempty(j)
        continue
    end
    targetXRef(i) = double(targetX(j));
    targetYRef(i) = double(targetY(j));
    refSec(i) = double(tRel(j));
end
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
    error('rewardTriggeredSaccades:NamedGroupEmpty', ...
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
        error('rewardTriggeredSaccades:UnknownTrialCode', ...
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
    error('rewardTriggeredSaccades:NamedGroupEmpty', ...
        'No trials had usable values for grouping code ''%s''.', code);
end
trialGroups = cell(numel(levels), 1);
for i = 1:numel(levels)
    trialGroups{i} = find(values == levels(i));
end
end


function trialVec = localValidateTrialVector(trialVec, nTrials)
trialVec = unique(double(trialVec(:)'));
if isempty(trialVec) || any(~isfinite(trialVec)) || any(trialVec ~= round(trialVec))
    error('rewardTriggeredSaccades:BadTrialNo', ...
        'Each trial selection must contain finite integer trial indices.');
end
trialVec = trialVec(trialVec >= 1 & trialVec <= nTrials);
if isempty(trialVec)
    error('rewardTriggeredSaccades:BadTrialNo', ...
        'No requested trials were within the valid range 1:%d.', nTrials);
end
end


function opts = localApplyLegacySaccadeAliases(opts)
aliasPairs = {
    'saccadeVelThreshDegPerSec', 'speedThreshDegPerSec'
    'saccadeMinAmpDeg', 'minAmpDeg'
    'saccadeMinDurSec', 'minDurSec'
    'saccadeMaxDurSec', 'maxDurSec'
    'saccadeSmoothFrames', 'smoothFrames'
    };
for i = 1:size(aliasPairs, 1)
    oldField = aliasPairs{i, 1};
    newField = aliasPairs{i, 2};
    if (~isfield(opts, newField) || isempty(opts.(newField))) && isfield(opts, oldField) && ~isempty(opts.(oldField))
        opts.(newField) = opts.(oldField);
    end
end
end


function trials = localFlattenTrialGroups(trialGroups)
if isempty(trialGroups)
    trials = [];
    return
end
trialGroups = cellfun(@(x) double(x(:)), trialGroups, 'UniformOutput', false);
trials = unique(vertcat(trialGroups{:}))';
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


function value = localFirstScalar(x)
if isempty(x)
    value = NaN;
elseif isscalar(x)
    value = double(x);
else
    value = double(x(1));
end
end


function dtSec = localResolveSampleDt(tRel, fallbackDtSec)
tRel = double(tRel(:));
tRel = tRel(isfinite(tRel));
if numel(tRel) < 2
    dtSec = fallbackDtSec;
    return
end
d = diff(tRel);
d = d(isfinite(d) & d > 0);
if isempty(d)
    dtSec = fallbackDtSec;
else
    dtSec = median(d, 'omitnan');
end
if ~isfinite(dtSec) || dtSec <= 0
    dtSec = fallbackDtSec;
end
end


function bounds = localTextureBounds(screenRect, graph)
texDimPx = graph.texture_dims(1) * graph.size_mult;
xShift = (screenRect(3) - texDimPx) / 2;
yShift = (screenRect(4) - texDimPx) / 2;
bounds = struct( ...
    'xMin', xShift, ...
    'xMax', xShift + texDimPx, ...
    'yMin', yShift, ...
    'yMax', yShift + texDimPx);
end
