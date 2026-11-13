function out = saccStepLatency(ex, trialNo, opts, varargin)
% saccStepLatency  Step-triggered corrective-saccade analysis for CoPs.
%
%   out = saccStepLatency(ex)
%   out = saccStepLatency(ex, 1:120)
%   out = saccStepLatency(ex, 'bg')
%   out = saccStepLatency(ex, {'bg','vis'})
%
% Returns one row per target-step event. For each event, the function asks
% whether a saccade with a positive projection onto the immediate
% post-step corrective direction occurs in the requested post-step window.

if nargin < 2
    trialNo = [];
end
if nargin >= 2 && isstruct(trialNo) && (nargin < 3 || isempty(opts))
    opts = trialNo;
    trialNo = [];
elseif nargin < 3 || isempty(opts)
    opts = struct();
end
if ischar(opts) || (isstring(opts) && isscalar(opts))
    if ~strcmpi(char(string(opts)), 'all')
        error('saccStepLatency:BadOpts', ...
            'Third argument must be opts or the legacy string ''all''.');
    end
    if ~isempty(varargin)
        opts = varargin{1};
    else
        opts = struct();
    end
elseif ~isstruct(opts)
    error('saccStepLatency:BadOpts', ...
        'Third argument must be opts or the legacy string ''all''.');
end
if ~isstruct(ex) || ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('saccStepLatency:BadInput', 'First input must be an ex struct with Trials.');
end

defaults = struct( ...
    'onlyGoState', true, ...
    'useEyeTime', true, ...
    'lowpassHz', [], ...
    'interpBlinkSec', 0.15, ...
    'truncateTrialFromStep', 0, ...
    'postWindowSec', [0.05 0.4], ...
    'stepMinAmpPx', 0, ...
    'minProjPx', 0, ...
    'speedThreshDegPerSec', 10, ...
    'minAmpDeg', 1, ...
    'minDurSec', 0.008, ...
    'maxDurSec', 5, ...
    'smoothFrames', 5);
opts = localApplyLegacySaccadeAliases(opts);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field)
        opts.(field) = defaults.(field);
    end
end
opts.setup = ex.setup;

trialGroups = localNormalizeTrialGroups(trialNo, ex);
groupLabels = localBuildGroupLabels(trialNo, trialGroups, ex);
eventTables = cell(numel(ex.Trials) * max(1, numel(trialGroups)), 1);
tableCount = 0;
for g = 1:numel(trialGroups)
    groupTrials = trialGroups{g};
    for i = 1:numel(groupTrials)
        trialIdx = groupTrials(i);
        rows = localBuildTrialEvents(ex, trialIdx, g, opts);
        if isempty(rows)
            continue
        end
        tableCount = tableCount + 1;
        eventTables{tableCount, 1} = rows;
    end
end

if tableCount == 0
    events = table();
else
    events = vertcat(eventTables{1:tableCount});
    if ismember('groupLabel', events.Properties.VariableNames)
        for g = 1:numel(groupLabels)
            events.groupLabel(double(events.group) == g) = groupLabels(g);
        end
    end
end

out = struct();
out.events = events;
out.trialGroups = trialGroups;
out.groupLabels = groupLabels;
out.trials = [trialGroups{:}];
out.options = opts;
if isempty(events)
    out.summary = table();
else
    out.summary = localSummarizeEvents(events);
end
end


function rows = localBuildTrialEvents(ex, trialIdx, groupNo, opts)
T = ex.Trials(trialIdx);
[xPx, yPx, tRel, tAbs, valid] = reconstructEyePx(ex, T, opts.useEyeTime, opts);
[targetX, targetY, target2X, target2Y, stepIdx] = mapTargetsByStep(ex, T, tRel);

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
target2X = target2X(goMask);
target2Y = target2Y(goMask);
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
    target2X = target2X(keepMask);
    target2Y = target2Y(keepMask);
    stepIdx = stepIdx(keepMask);
end

[texBounds, ~] = localTextureBounds(ex.setup.screenRect, ex.exp.CoPs.graph);
insideTexture = xPx >= texBounds.xMin & xPx <= texBounds.xMax & ...
    yPx >= texBounds.yMin & yPx <= texBounds.yMax;
xPx(~insideTexture) = NaN;
yPx(~insideTexture) = NaN;
valid = valid & insideTexture;
xPx(~valid) = NaN;
yPx(~valid) = NaN;

dtSec = localResolveSampleDt(tRel, 1 / inferFs(ex));
[xPx, yPx] = preprocessGazeForCcgCoPs( ...
    xPx, yPx, dtSec, opts.interpBlinkSec, opts.lowpassHz);

saccParams = localBuildSaccadeParams(dtSec, opts);
[saccStarts, saccStops] = detectTrackingSaccadesCoPs(xPx, yPx, dtSec, ex.setup, saccParams);
if isempty(stepIdx) || numel(stepIdx) < 2
    rows = table();
    return
end

stepChangeIdx = find(diff(stepIdx(:)) ~= 0) + 1;
if isempty(stepChangeIdx)
    rows = table();
    return
end

rowCells = cell(numel(stepChangeIdx) * 2, 1);
rowCount = 0;
postWin = double(opts.postWindowSec(:)');
postWin = sort(postWin);
bg = localTrialBackgroundNoiseLevel(T);
vis = localTrialTargetVisibility(ex, T);
tnum = localTrialTargetNum(ex, T);
imageName = localTrialImageName(ex, T, trialIdx);

for ii = 1:numel(stepChangeIdx)
    idxCurr = stepChangeIdx(ii);
    idxPrev = idxCurr - 1;
    if idxPrev < 1 || idxCurr > numel(stepIdx)
        continue
    end
    eventTimeSec = double(tRel(idxCurr));
    stepPrev = double(stepIdx(idxPrev));
    stepCurr = double(stepIdx(idxCurr));
    targetRows = {
        1, [targetX(idxPrev), targetY(idxPrev)], [targetX(idxCurr), targetY(idxCurr)];
        2, [target2X(idxPrev), target2Y(idxPrev)], [target2X(idxCurr), target2Y(idxCurr)]
    };
    for k = 1:size(targetRows, 1)
        targetId = targetRows{k, 1};
        prevPos = double(targetRows{k, 2});
        currPos = double(targetRows{k, 3});
        if any(~isfinite(prevPos)) || any(~isfinite(currPos))
            continue
        end
        stepVec = currPos - prevPos;
        stepAmpPx = hypot(stepVec(1), stepVec(2));
        if ~(isfinite(stepAmpPx) && stepAmpPx >= double(localFirstScalar(opts.stepMinAmpPx)))
            continue
        end
        gazeAtEvent = [double(xPx(idxCurr)), double(yPx(idxCurr))];
        gazePre = [double(xPx(idxPrev)), double(yPx(idxPrev))];
        if any(~isfinite(gazeAtEvent)) || any(~isfinite(gazePre))
            continue
        end
        correctiveVec = currPos - gazeAtEvent;
        correctiveAmpPx = hypot(correctiveVec(1), correctiveVec(2));
        if ~(isfinite(correctiveAmpPx) && correctiveAmpPx > 0)
            continue
        end
        correctiveDir = correctiveVec ./ correctiveAmpPx;
        errPrePx = hypot(prevPos(1) - gazePre(1), prevPos(2) - gazePre(2));
        errAtStepPx = correctiveAmpPx;

        inWindow = saccStarts <= saccStops & ...
            tRel(saccStarts) >= eventTimeSec + postWin(1) & ...
            tRel(saccStarts) <= eventTimeSec + postWin(2);
        candStarts = saccStarts(inWindow);
        candStops = saccStops(inWindow);

        hasCorrective = false;
        latencySec = NaN;
        saccAmpPx = NaN;
        projPx = NaN;
        errAfterSaccPx = NaN;
        saccStartSec = NaN;
        saccStopSec = NaN;
        saccDxPx = NaN;
        saccDyPx = NaN;
        nSaccInWindow = numel(candStarts);
        firstProjPxWindow = NaN;
        maxProjPxWindow = NaN;
        latencyFirstSaccSec = NaN;
        projCandidates = NaN(numel(candStarts), 1);
        for c = 1:numel(candStarts)
            s0 = candStarts(c);
            s1 = candStops(c);
            if s0 < 1 || s1 > numel(xPx) || s1 <= s0
                continue
            end
            dx = double(xPx(s1) - xPx(s0));
            dy = double(yPx(s1) - yPx(s0));
            if ~isfinite(dx) || ~isfinite(dy)
                continue
            end
            proj = dx * correctiveDir(1) + dy * correctiveDir(2);
            projCandidates(c) = proj;
            if c == 1
                firstProjPxWindow = proj;
                latencyFirstSaccSec = double(tRel(s0)) - eventTimeSec;
            end
            if proj < double(localFirstScalar(opts.minProjPx))
                continue
            end
            hasCorrective = true;
            latencySec = double(tRel(s0)) - eventTimeSec;
            saccAmpPx = hypot(dx, dy);
            projPx = proj;
            saccStartSec = double(tRel(s0));
            saccStopSec = double(tRel(s1));
            saccDxPx = dx;
            saccDyPx = dy;
            errAfterSaccPx = hypot(currPos(1) - double(xPx(s1)), currPos(2) - double(yPx(s1)));
            break
        end
        if any(isfinite(projCandidates))
            maxProjPxWindow = max(projCandidates, [], 'omitnan');
        end

        rowCount = rowCount + 1;
        rowCells{rowCount, 1} = table( ...
            groupNo, trialIdx, stepPrev, stepCurr, eventTimeSec, targetId, tnum, ...
            string(missing), bg, vis, imageName, ...
            stepVec(1), stepVec(2), stepAmpPx, ...
            correctiveVec(1), correctiveVec(2), correctiveAmpPx, ...
            errPrePx, errAtStepPx, errAfterSaccPx, errAtStepPx - errAfterSaccPx, ...
            hasCorrective, latencySec, saccStartSec, saccStopSec, ...
            saccDxPx, saccDyPx, saccAmpPx, projPx, ...
            nSaccInWindow, latencyFirstSaccSec, firstProjPxWindow, maxProjPxWindow, ...
            'VariableNames', { ...
                'group','trial','stepPrev','stepCurr','eventTimeSec','targetId','targetNum', ...
                'groupLabel','backgroundNoiseLvl','targetVisibility','imageName', ...
                'stepDxPx','stepDyPx','stepAmpPx', ...
                'corrDxPx','corrDyPx','corrAmpPx', ...
                'errPrePx','errAtStepPx','errAfterSaccPx','errReductionPx', ...
                'hasCorrectiveSacc','latencySec','saccStartSec','saccStopSec', ...
                'saccDxPx','saccDyPx','saccAmpPx','projPx', ...
                'nSaccInWindow','latencyFirstSaccSec','firstProjPxWindow','maxProjPxWindow'});
    end
end

if rowCount == 0
    rows = table();
else
    rows = vertcat(rowCells{1:rowCount});
end
end


function summary = localSummarizeEvents(events)
groups = unique(double(events.group(:)'));
summaryRows = cell(numel(groups), 1);
for i = 1:numel(groups)
    E = events(double(events.group) == groups(i), :);
    label = string(missing);
    if ismember('groupLabel', E.Properties.VariableNames) && ~isempty(E.groupLabel)
        label = E.groupLabel(find(strlength(strtrim(E.groupLabel)) > 0, 1, 'first'));
        if isempty(label)
            label = string(missing);
        end
    end
    summaryRows{i} = table( ...
        groups(i), ...
        label, ...
        height(E), ...
        sum(logical(E.hasCorrectiveSacc)), ...
        mean(double(E.hasCorrectiveSacc), 'omitnan'), ...
        mean(E.latencySec, 'omitnan'), ...
        median(E.latencySec, 'omitnan'), ...
        mean(E.projPx, 'omitnan'), ...
        mean(E.errReductionPx, 'omitnan'), ...
        'VariableNames', {'group','groupLabel','nEvents','nCorrective','correctiveFrac', ...
        'latencyMeanSec','latencyMedianSec','projMeanPx','errReductionMeanPx'});
end
summary = vertcat(summaryRows{:});
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
if isempty(trialNo)
    trialGroups = {1:numel(ex.Trials)};
    return
end
if ischar(trialNo) || (isstring(trialNo) && isscalar(trialNo))
    code = char(string(trialNo));
    trialGroups = localResolveNamedTrialGroups(code, ex);
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
    error('saccStepLatency:NamedGroupEmpty', ...
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
        error('saccStepLatency:UnknownTrialCode', ...
            'Unknown trial grouping code ''%s''. Currently supported: ''all'', ''bg'', ''vis'', ''tnum'', ''im''.', code);
end
end


function trialGroups = localResolveNamedTrialGroupsFromEx(code, ex)
switch code
    case 'bg'
        values = NaN(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            T = ex.Trials(j);
            if isfield(T, 'background_noise_lvl') && isnumeric(T.background_noise_lvl) && isscalar(T.background_noise_lvl)
                values(j) = double(T.background_noise_lvl);
            end
        end
        levels = unique(values(isfinite(values)));
        if isempty(levels)
            error('saccStepLatency:NamedGroupEmpty', ...
                'No trials had finite background_noise_lvl values.');
        end
        trialGroups = cell(numel(levels), 1);
        for i = 1:numel(levels)
            trialGroups{i} = find(values == levels(i));
        end
    case 'vis'
        values = NaN(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            T = ex.Trials(j);
            if isfield(T, 'target_visibility') && isnumeric(T.target_visibility) && isscalar(T.target_visibility)
                values(j) = double(T.target_visibility);
            end
        end
        levels = unique(values(isfinite(values)));
        if isempty(levels)
            error('saccStepLatency:NamedGroupEmpty', ...
                'No trials had finite target_visibility values.');
        end
        trialGroups = cell(numel(levels), 1);
        for i = 1:numel(levels)
            trialGroups{i} = find(values == levels(i));
        end
    case 'tnum'
        values = NaN(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            T = ex.Trials(j);
            if isfield(T, 'target_num') && isnumeric(T.target_num) && isscalar(T.target_num)
                values(j) = double(T.target_num);
            end
        end
        levels = unique(values(isfinite(values)));
        if isempty(levels)
            error('saccStepLatency:NamedGroupEmpty', ...
                'No trials had finite target_num values.');
        end
        trialGroups = cell(numel(levels), 1);
        for i = 1:numel(levels)
            trialGroups{i} = find(values == levels(i));
        end
    case 'im'
        values = strings(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            T = ex.Trials(j);
            values(j) = localTrialImageName(ex, T, j);
        end
        levels = unique(values(values ~= "" & ~ismissing(values)), 'stable');
        if isempty(levels)
            error('saccStepLatency:NamedGroupEmpty', ...
                'No trials had finite imageName values.');
        end
        trialGroups = cell(numel(levels), 1);
        for i = 1:numel(levels)
            trialGroups{i} = find(values == levels(i));
        end
end
end


function trialVec = localValidateTrialVector(trialVec, nTrials)
trialVec = unique(double(trialVec(:)'));
if isempty(trialVec) || any(~isfinite(trialVec)) || any(trialVec ~= round(trialVec))
    error('saccStepLatency:BadTrialNo', ...
        'Each trial selection must contain finite integer trial indices.');
end
trialVec = trialVec(trialVec >= 1 & trialVec <= nTrials);
if isempty(trialVec)
    error('saccStepLatency:BadTrialNo', ...
        'No requested trials were within the valid range 1:%d.', nTrials);
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


function name = localBasenameString(pathStr)
name = string(missing);
if strlength(pathStr) == 0 || ismissing(pathStr)
    return
end
[~, stem, ext] = fileparts(char(pathStr));
candidate = string([stem ext]);
if strlength(strtrim(candidate)) > 0
    name = candidate;
end
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


function dtSec = localResolveSampleDt(tRelSec, fallbackDtSec)
dtSec = NaN;
if numel(tRelSec) >= 2
    dtCandidates = diff(double(tRelSec(:)));
    dtCandidates = dtCandidates(isfinite(dtCandidates) & dtCandidates > 0);
    if ~isempty(dtCandidates)
        dtSec = median(dtCandidates, 'omitnan');
        return
    end
end
dtSec = fallbackDtSec;
end


function [bounds, mask] = localTextureBounds(screenRect, graph)
texDimPx = graph.texture_dims(1) * graph.size_mult;
xShift = (screenRect(3) - texDimPx) / 2;
yShift = (screenRect(4) - texDimPx) / 2;
bounds = struct( ...
    'xMin', xShift, ...
    'xMax', xShift + texDimPx, ...
    'yMin', yShift, ...
    'yMax', yShift + texDimPx);
mask = bounds;
end
