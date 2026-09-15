function out = plotSacTrigErr(ex, trialNo, opts)
% plotSacTrigErr  Plot saccade-triggered average error traces.
%
%   out = plotSacTrigErr(ex)
%   out = plotSacTrigErr(ex, trialNo)
%   out = plotSacTrigErr(ex, trialNo, opts)
%
% Inputs
%   ex      : experiment struct with Trials
%   trialNo : []/'all', numeric trials, named code ('bg','vis','tnum','im'),
%             or combined named code cell like {'bg','vis'}
%   opts    : optional struct with fields:
%       .onlyGoState   (default true)
%       .useEyeTime    (default false)
%       .lowpassHz     (default [])
%       .interpBlinkSec (default 0.15)
%       .truncateTrialFromStep (default 0)
%       .timeWindowSec (default [])
%       .lagWindowSec  (default [-0.5 0.5])
%       .binWidthSec   (default 0.01)
%       .alignTo       (default 'stop') one of: 'start','stop'
%       .errField      (default 'distDeg') one of:
%                      'distDeg','distPx','xDeg','xPx','yDeg','yPx'
%       .errLagSec     (default 0)
%       .errLagMs      (alias)
%       .stat          (default 'mean') one of: 'mean','median'
%       .speedThreshDegPerSec (default 10)
%       .minAmpDeg     (default 1)
%       .minDurSec     (default 0.008)
%       .maxDurSec     (default 5)
%       .smoothFrames  (default 5)
%       .newFigure     (default true)
%       .lineWidth     (default 1.5)
%       .colors        (default lines(nGroup))
%
% Output
%   out.groups{i}.tBinCenterSec
%   out.groups{i}.errTrace
%   out.groups{i}.nSamplesPerBin
%   out.groups{i}.nSaccades

if nargin < 2
    trialNo = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
if ~isstruct(ex) || ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('plotSacTrigErr:BadInput', 'First input must be an ex struct with Trials.');
end
if ~isstruct(opts)
    error('plotSacTrigErr:BadOpts', 'Third argument must be an opts struct.');
end

defaults = struct( ...
    'onlyGoState', true, ...
    'useEyeTime', true, ...
    'lowpassHz', [], ...
    'interpBlinkSec', 0.15, ...
    'truncateTrialFromStep', 0, ...
    'timeWindowSec', [], ...
    'lagWindowSec', [-0.5 2.5], ...
    'binWidthSec', 0.01, ...
    'alignTo', 'start', ...
    'errField', 'distDeg', ...
    'errLagSec', 0, ...
    'errLagMs', [], ...
    'stat', 'mean', ...
    'speedThreshDegPerSec', 10, ...
    'minAmpDeg', 1, ...
    'minDurSec', 0.008, ...
    'maxDurSec', 5, ...
    'smoothFrames', 5, ...
    'plot', true, ...
    'newFigure', true, ...
    'lineWidth', 1.5, ...
    'colors', []);
opts = localApplyLegacySaccadeAliases(opts);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field) || isempty(opts.(field))
        opts.(field) = defaults.(field);
    end
end
if ~isempty(opts.errLagMs)
    opts.errLagSec = double(opts.errLagMs) ./ 1000;
end
opts.lagWindowSec = double(opts.lagWindowSec(:)');
if numel(opts.lagWindowSec) ~= 2 || ~all(isfinite(opts.lagWindowSec)) || opts.lagWindowSec(2) <= opts.lagWindowSec(1)
    error('plotSacTrigErr:BadLagWindow', 'opts.lagWindowSec must be a finite 1x2 increasing vector.');
end
opts.binWidthSec = double(opts.binWidthSec);
if ~isscalar(opts.binWidthSec) || ~isfinite(opts.binWidthSec) || opts.binWidthSec <= 0
    error('plotSacTrigErr:BadBinWidth', 'opts.binWidthSec must be a finite positive scalar.');
end
opts.errLagSec = double(localFirstScalar(opts.errLagSec));
if ~isfinite(opts.errLagSec)
    error('plotSacTrigErr:BadErrLag', 'opts.errLagSec must be a finite scalar.');
end
opts.alignTo = validatestring(char(string(opts.alignTo)), {'start', 'stop'});
opts.errField = validatestring(char(string(opts.errField)), {'distDeg','distPx','xDeg','xPx','yDeg','yPx'});
opts.stat = validatestring(char(string(opts.stat)), {'mean', 'median'});

trialGroups = localNormalizeTrialGroups(trialNo, ex);
groupLabels = localBuildGroupLabels(trialNo, trialGroups, ex);
nGroup = numel(trialGroups);
plotFacetSpec = localResolvePlotFacetSpec(trialNo, ex, nGroup);
if isempty(opts.colors)
    if plotFacetSpec.enabled
        baseColors = lines(plotFacetSpec.nLineGroups);
        opts.colors = baseColors(plotFacetSpec.lineGroupIndex, :);
    else
        opts.colors = lines(nGroup);
    end
end

binEdgesSec = opts.lagWindowSec(1):opts.binWidthSec:opts.lagWindowSec(2);
if binEdgesSec(end) < opts.lagWindowSec(2)
    binEdgesSec(end+1) = opts.lagWindowSec(2); %#ok<AGROW>
end
tBinCenterSec = binEdgesSec(1:end-1) + diff(binEdgesSec) / 2;

groupOut = cell(nGroup, 1);
for g = 1:nGroup
    groupOut{g} = localComputeGroupTrace(ex, trialGroups{g}, tBinCenterSec, binEdgesSec, opts);
    groupOut{g}.groupLabel = groupLabels(g);
end

if logical(opts.plot)
    if opts.newFigure
        figure;
    end
    if plotFacetSpec.enabled
        tiledlayout(plotFacetSpec.nRows, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
        for iRow = 1:plotFacetSpec.nRows
            nexttile;
            localPlotGroupedErr(groupOut, opts, plotFacetSpec.rowGroupIdx{iRow}, ...
                plotFacetSpec.lineLabels, plotFacetSpec.rowLabels(iRow));
        end
    else
        hold on
        localPlotGroupedErr(groupOut, opts, 1:nGroup, cellstr(groupLabels), "");
    end
end

out = struct();
out.groups = groupOut;
out.groupLabels = groupLabels;
out.trialGroups = trialGroups;
out.tBinCenterSec = tBinCenterSec(:);
out.binEdgesSec = binEdgesSec(:);
out.errField = string(opts.errField);
out.stat = string(opts.stat);
out.alignTo = string(opts.alignTo);
out.errLagSec = opts.errLagSec;
end


function groupOut = localComputeGroupTrace(ex, trialList, tBinCenterSec, binEdgesSec, opts)
errCells = cell(numel(trialList), 1);
rowCount = 0;
nSaccades = 0;
for i = 1:numel(trialList)
    rows = localBuildTrialRows(ex, trialList(i), opts);
    if isempty(rows)
        continue
    end
    rowCount = rowCount + 1;
    errCells{rowCount, 1} = rows;
    nSaccades = nSaccades + numel(unique(rows.saccNo));
end
if rowCount == 0
    errTable = table();
else
    errTable = vertcat(errCells{1:rowCount});
end

errTrace = NaN(1, numel(tBinCenterSec));
nSamplesPerBin = zeros(1, numel(tBinCenterSec));
if ~isempty(errTable)
    for b = 1:numel(tBinCenterSec)
        leftEdge = binEdgesSec(b);
        rightEdge = binEdgesSec(b + 1);
        keep = isfinite(errTable.tFromSaccSec) & isfinite(errTable.errValue) & ...
            double(errTable.tFromSaccSec) >= leftEdge & double(errTable.tFromSaccSec) < rightEdge;
        if b == numel(tBinCenterSec)
            keep = keep | (isfinite(errTable.tFromSaccSec) & isfinite(errTable.errValue) & ...
                double(errTable.tFromSaccSec) == rightEdge);
        end
        x = double(errTable.errValue(keep));
        x = x(isfinite(x));
        nSamplesPerBin(b) = numel(x);
        if isempty(x)
            continue
        end
        switch opts.stat
            case 'mean'
                errTrace(b) = mean(x, 'omitnan');
            case 'median'
                errTrace(b) = median(x, 'omitnan');
        end
    end
end

groupOut = struct();
groupOut.tBinCenterSec = tBinCenterSec(:);
groupOut.errTrace = errTrace(:);
groupOut.nSamplesPerBin = nSamplesPerBin(:);
groupOut.nSaccades = nSaccades;
groupOut.rows = errTable;
end


function rows = localBuildTrialRows(ex, trialIdx, opts)
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

[texBounds, ~] = localTextureBounds(ex.setup.screenRect, ex.exp.CoPs.graph);
insideTexture = xPx >= texBounds.xMin & xPx <= texBounds.xMax & ...
    yPx >= texBounds.yMin & yPx <= texBounds.yMax;
xPx(~insideTexture) = NaN;
yPx(~insideTexture) = NaN;
valid = valid & insideTexture;
xPx(~valid) = NaN;
yPx(~valid) = NaN;

dtSec = localResolveSampleDt(tRel, 1 / inferFs(ex));
[xPx, yPx] = preprocessGazeForCcgCoPs(xPx, yPx, dtSec, opts.interpBlinkSec, opts.lowpassHz);

[targetXRef, targetYRef] = localLaggedTargetSeries(targetX, targetY, tRel, opts.errLagSec);
errSeries = localResolveErrorSeries(xPx, yPx, targetXRef, targetYRef, ex.setup, opts.errField);

saccParams = localBuildSaccadeParams(dtSec, opts);
[saccStarts, saccStops] = detectTrackingSaccadesCoPs(xPx, yPx, dtSec, ex.setup, saccParams);
if isempty(saccStarts)
    rows = table();
    return
end

alignIdx = double(saccStops(:));
if strcmp(opts.alignTo, 'start')
    alignIdx = double(saccStarts(:));
end

keepMask = false(numel(tRel), 1);
allTrial = [];
allSaccNo = [];
allT = [];
allErr = [];
for s = 1:numel(alignIdx)
    rel = double(tRel) - double(tRel(alignIdx(s)));
    win = rel >= opts.lagWindowSec(1) & rel <= opts.lagWindowSec(2) & isfinite(errSeries);
    if ~any(win)
        continue
    end
    n = nnz(win);
    allTrial = [allTrial; repmat(trialIdx, n, 1)]; %#ok<AGROW>
    allSaccNo = [allSaccNo; repmat(s, n, 1)]; %#ok<AGROW>
    allT = [allT; rel(win)]; %#ok<AGROW>
    allErr = [allErr; errSeries(win)]; %#ok<AGROW>
    keepMask = keepMask | win; %#ok<NASGU>
end

if isempty(allErr)
    rows = table();
else
    rows = table(allTrial, allSaccNo, allT, allErr, ...
        'VariableNames', {'trial','saccNo','tFromSaccSec','errValue'});
end
end


function errSeries = localResolveErrorSeries(xPx, yPx, targetXRef, targetYRef, setup, errField)
switch errField
    case 'distPx'
        errSeries = hypot(double(xPx) - double(targetXRef), double(yPx) - double(targetYRef));
    case 'distDeg'
        errSeries = px2deg(hypot(double(xPx) - double(targetXRef), double(yPx) - double(targetYRef)), setup);
    case 'xPx'
        errSeries = double(xPx) - double(targetXRef);
    case 'xDeg'
        errSeries = px2deg(double(xPx) - double(targetXRef), setup);
    case 'yPx'
        errSeries = double(yPx) - double(targetYRef);
    case 'yDeg'
        errSeries = px2deg(double(yPx) - double(targetYRef), setup);
end
end


function [targetXRef, targetYRef] = localLaggedTargetSeries(targetX, targetY, tRel, lagSec)
tRel = double(tRel(:));
targetX = double(targetX(:));
targetY = double(targetY(:));
tRef = tRel - lagSec;
targetXRef = NaN(size(tRel));
targetYRef = NaN(size(tRel));
for i = 1:numel(tRel)
    j = find(isfinite(tRel) & (tRel <= tRef(i)), 1, 'last');
    if isempty(j)
        j = find(isfinite(tRel), 1, 'first');
    end
    if isempty(j)
        continue
    end
    targetXRef(i) = targetX(j);
    targetYRef(i) = targetY(j);
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
    error('plotSacTrigErr:NamedGroupEmpty', 'No trials remained after combining the requested named groupings.');
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
        error('plotSacTrigErr:UnknownTrialCode', ...
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
    error('plotSacTrigErr:NamedGroupEmpty', ...
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
    error('plotSacTrigErr:BadTrialNo', 'Each trial selection must contain finite integer trial indices.');
end
trialVec = trialVec(trialVec >= 1 & trialVec <= nTrials);
if isempty(trialVec)
    error('plotSacTrigErr:BadTrialNo', 'No requested trials were within the valid range 1:%d.', nTrials);
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


function out = localTimeWindow(windowValue)
out = [];
if isempty(windowValue)
    return
end
out = double(windowValue(:)');
if numel(out) ~= 2 || ~all(isfinite(out)) || out(2) <= out(1)
    error('plotSacTrigErr:BadTimeWindow', ...
        'opts.timeWindowSec must be empty or a finite 1x2 increasing vector.');
end
end


function s = localPlural(n)
if n == 1
    s = '';
else
    s = 's';
end
end


function localPlotGroupedErr(groupOut, opts, groupIdx, legendLabelsOverride, rowLabel)
hold on
legendLabels = strings(numel(groupIdx), 1);
plotted = false(numel(groupIdx), 1);
for j = 1:numel(groupIdx)
    g = groupIdx(j);
    plot(groupOut{g}.tBinCenterSec, groupOut{g}.errTrace, ...
        'Color', opts.colors(g, :), 'LineWidth', opts.lineWidth);
    if ~isempty(legendLabelsOverride) && numel(legendLabelsOverride) >= j
        legendLabels(j) = string(legendLabelsOverride{j});
    else
        legendLabels(j) = string(groupOut{g}.groupLabel);
    end
    legendLabels(j) = sprintf('%s (n=%d)', legendLabels(j), groupOut{g}.nSaccades);
    plotted(j) = true;
end
xline(0, ':', 'Color', [0.4 0.4 0.4]);
yline(0, ':', 'Color', [0.4 0.4 0.4]);
xlabel('Time From Saccade (s)');
ylabel(sprintf('%s (%s)', string(opts.errField), string(opts.stat)));
titleText = 'Saccade-triggered error';
if strlength(strtrim(string(rowLabel))) > 0
    titleText = sprintf('%s | %s', titleText, char(string(rowLabel)));
end
title(titleText, 'Interpreter', 'none');
box off
if numel(groupIdx) > 1 && any(plotted)
    legend(cellstr(legendLabels(plotted)), 'Location', 'best', 'Interpreter', 'none');
end
end


function plotFacetSpec = localResolvePlotFacetSpec(trialNo, ex, nGroup)
plotFacetSpec = struct('enabled', false, 'nRows', 1, 'nLineGroups', nGroup, ...
    'rowGroupIdx', {{}}, 'rowLabels', strings(0, 1), ...
    'lineLabels', {{}}, 'lineGroupIndex', (1:nGroup)');
if ~localIsNamedCodeCell(trialNo) || numel(trialNo) ~= 2
    return
end
code1 = char(string(trialNo{1}));
code2 = char(string(trialNo{2}));
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
