function out = saccadeCorrectiveness(ex, trialNo, opts, varargin)
% saccadeCorrectiveness  Measure whether detected saccades reduce target error.
%
%   out = saccadeCorrectiveness(ex)
%   out = saccadeCorrectiveness(ex, 1:120)
%   out = saccadeCorrectiveness(ex, 'bg')
%   out = saccadeCorrectiveness(ex, {'bg','vis'}, opts)
%
% The detector uses the same current defaults as the saccade-oriented CoPs
% analysis functions: speed >= 10 deg/s, amplitude >= 1 deg, duration >=
% 8 ms, and 5-frame smoothing.
%
% Correctiveness is computed relative to the target position sampled
% opts.targetLeadSec before saccade landing. A saccade is corrective when
% landing reduces the distance to that reference target and lands within
% the scaled task target radius, or opts.landingRadiusDeg when explicitly
% supplied.
%
% opts.targetMode:
%   'any'  evaluate t1 and t2, then use the target with largest error
%          reduction
%   't1'   evaluate only target 1
%   't2'   evaluate only target 2

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
        error('saccadeCorrectiveness:BadOpts', ...
            'Third argument must be opts or the legacy string ''all''.');
    end
    if ~isempty(varargin)
        opts = varargin{1};
    else
        opts = struct();
    end
elseif ~isstruct(opts)
    error('saccadeCorrectiveness:BadOpts', ...
        'Third argument must be opts or the legacy string ''all''.');
end
if ~isstruct(ex) || ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('saccadeCorrectiveness:BadInput', 'First input must be an ex struct with Trials.');
end

defaults = struct( ...
    'onlyGoState', true, ...
    'useEyeTime', true, ...
    'lowpassHz', [], ...
    'interpBlinkSec', 0.15, ...
    'truncateTrialFromStep', 0, ...
    'timeWindowSec', [], ...
    'targetMode', 'any', ...
    'targetLeadSec', 0.150, ...
    'minErrReductionPx', 0, ...
    'landingRadiusScale', 2.5, ...
    'landingRadiusDeg', [], ...
    'speedThreshDegPerSec', 10, ...
    'minAmpDeg', 1, ...
    'minDurSec', 0.008, ...
    'maxDurSec', 1, ...
    'smoothFrames', 5, ...
    'plot', false, ...
    'newFigure', true);
opts = localApplyLegacySaccadeAliases(opts);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field) || isempty(opts.(field))
        opts.(field) = defaults.(field);
    end
end
opts.targetMode = localResolveTargetMode(opts.targetMode);
opts.targetLeadSec = max(0, double(localFirstScalar(opts.targetLeadSec)));
opts.minErrReductionPx = double(localFirstScalar(opts.minErrReductionPx));
if ~isfinite(opts.minErrReductionPx)
    opts.minErrReductionPx = 0;
end
opts.setup = ex.setup;
[opts.landingRadiusPx, opts.landingRadiusDeg] = localResolveLandingRadius(ex, opts);

trialGroups = localNormalizeTrialGroups(trialNo, ex);
groupLabels = localBuildGroupLabels(trialNo, trialGroups, ex);
rows = cell(numel(ex.Trials) * max(1, numel(trialGroups)), 1);
rowCount = 0;
for g = 1:numel(trialGroups)
    groupTrials = trialGroups{g};
    for i = 1:numel(groupTrials)
        trialIdx = groupTrials(i);
        trialRows = localBuildTrialSaccades(ex, trialIdx, g, opts);
        if isempty(trialRows)
            continue
        end
        rowCount = rowCount + 1;
        rows{rowCount, 1} = trialRows;
    end
end

if rowCount == 0
    saccades = table();
else
    saccades = vertcat(rows{1:rowCount});
    if ismember('groupLabel', saccades.Properties.VariableNames)
        for g = 1:numel(groupLabels)
            saccades.groupLabel(double(saccades.group) == g) = groupLabels(g);
        end
    end
end

out = struct();
out.saccades = saccades;
out.trials = [trialGroups{:}];
out.trialGroups = trialGroups;
out.groupLabels = groupLabels;
out.options = opts;
if isempty(saccades)
    out.summary = table();
    out.summaryByTarget = table();
else
    out.summary = localSummarizeSaccades(saccades, "group");
    out.summaryByTarget = localSummarizeSaccades(saccades, "target");
end

if logical(opts.plot) && ~isempty(saccades)
    localPlotSaccades(saccades, opts);
end
end


function rows = localBuildTrialSaccades(ex, trialIdx, groupNo, opts)
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
tAbs = tAbs(goMask); %#ok<NASGU>
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

if isempty(tRel) || numel(tRel) < 2
    rows = table();
    return
end

trialAnalyzedDurationSec = localAnalyzedDurationSec(tRel);

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
[saccStarts, saccStops, speedDegPerSec] = detectTrackingSaccadesCoPs( ...
    xPx, yPx, dtSec, ex.setup, saccParams);
if isempty(saccStarts)
    rows = table();
    return
end

xSmooth = movmean(xPx, saccParams.smoothFrames, 'omitnan');
ySmooth = movmean(yPx, saccParams.smoothFrames, 'omitnan');

tw = localTimeWindow(opts.timeWindowSec);
bg = localTrialBackgroundNoiseLevel(T);
vis = localTrialTargetVisibility(ex, T);
tnum = localTrialTargetNum(ex, T);
imageName = localTrialImageName(ex, T, trialIdx);

rowCells = cell(numel(saccStarts), 1);
rowCount = 0;
for k = 1:numel(saccStarts)
    s0 = double(saccStarts(k));
    s1 = double(saccStops(k));
    if s0 < 1 || s1 > numel(xPx) || s1 < s0
        continue
    end
    if ~isempty(tw) && ~(tRel(s0) >= tw(1) && tRel(s0) <= tw(2))
        continue
    end
    startPos = [double(xPx(s0)), double(yPx(s0))];
    landingPos = [double(xPx(s1)), double(yPx(s1))];
    if any(~isfinite(startPos)) || any(~isfinite(landingPos))
        continue
    end

    refTimeSec = double(tRel(s1)) - opts.targetLeadSec;
    refIdx = localReferenceIndex(tRel, refTimeSec);
    if isempty(refIdx)
        continue
    end

    targetCandidates = localTargetCandidatesAtRef( ...
        opts.targetMode, targetX, targetY, target2X, target2Y, refIdx);
    if isempty(targetCandidates)
        continue
    end

    saccVec = landingPos - startPos;
    saccAmpPx = hypot(saccVec(1), saccVec(2));
    if ~(isfinite(saccAmpPx) && saccAmpPx > 0)
        continue
    end

    targetEval = localEvaluateTargets(targetCandidates, startPos, landingPos, saccVec);
    if isempty(targetEval)
        continue
    end

    selected = localSelectTargetEvaluation(targetEval, opts.targetMode);
    if isempty(selected)
        continue
    end

    detectorAmpPx = hypot( ...
        double(xSmooth(s1)) - double(xSmooth(s0)), ...
        double(ySmooth(s1)) - double(ySmooth(s0)));
    peakSpeed = max(speedDegPerSec(s0:s1), [], 'omitnan');
    landedWithinTarget = selected.postErrPx <= opts.landingRadiusPx;
    isCorrective = selected.errReductionPx > opts.minErrReductionPx && landedWithinTarget;

    rowCount = rowCount + 1;
    rowCells{rowCount, 1} = table( ...
        groupNo, string(missing), double(trialIdx), double(k), ...
        s0, s1, double(tRel(s0)), double(tRel(s1)), double(tRel(s1) - tRel(s0)), ...
        trialAnalyzedDurationSec, ...
        double(stepIdx(s0)), double(stepIdx(s1)), double(stepIdx(refIdx)), ...
        opts.targetLeadSec, double(refIdx), double(tRel(refIdx)), string(opts.targetMode), ...
        double(selected.targetId), double(size(targetCandidates, 1)), ...
        selected.targetX, selected.targetY, ...
        startPos(1), startPos(2), landingPos(1), landingPos(2), ...
        saccVec(1), saccVec(2), saccAmpPx, px2deg(saccAmpPx, ex.setup), ...
        detectorAmpPx, px2deg(detectorAmpPx, ex.setup), peakSpeed, ...
        selected.preErrPx, selected.postErrPx, selected.errReductionPx, ...
        px2deg(selected.errReductionPx, ex.setup), selected.fracErrReduction, ...
        selected.postErrPx, px2deg(selected.postErrPx, ex.setup), ...
        opts.landingRadiusPx, opts.landingRadiusDeg, opts.landingRadiusScale, landedWithinTarget, ...
        selected.projTowardTargetPx, px2deg(selected.projTowardTargetPx, ex.setup), ...
        selected.directionCosine, isCorrective, bg, vis, tnum, imageName, ...
        'VariableNames', { ...
            'group','groupLabel','trial','saccNo', ...
            'startIdx','stopIdx','startSec','stopSec','durationSec', ...
            'trialAnalyzedDurationSec', ...
            'startStep','stopStep','targetRefStep', ...
            'targetLeadSec','targetRefIdx','targetRefSec','targetMode', ...
            'selectedTargetId','nTargetsConsidered', ...
            'targetX','targetY', ...
            'startX','startY','landingX','landingY', ...
            'saccDxPx','saccDyPx','saccAmpPx','saccAmpDeg', ...
            'detectorAmpPx','detectorAmpDeg','peakSpeedDegPerSec', ...
            'preErrPx','postErrPx','errReductionPx', ...
            'errReductionDeg','fracErrReduction', ...
            'landingDistToTargetPx','landingDistToTargetDeg', ...
            'landingRadiusPx','landingRadiusDeg','landingRadiusScale','landedWithinTarget', ...
            'projTowardTargetPx','projTowardTargetDeg', ...
            'directionCosine','isCorrective', ...
            'backgroundNoiseLvl','targetVisibility','targetNum','imageName'});
end

if rowCount == 0
    rows = table();
else
    rows = vertcat(rowCells{1:rowCount});
end
end


function candidates = localTargetCandidatesAtRef(targetMode, targetX, targetY, target2X, target2Y, refIdx)
allTargets = [
    1, double(targetX(refIdx)), double(targetY(refIdx));
    2, double(target2X(refIdx)), double(target2Y(refIdx))
    ];
switch targetMode
    case 't1'
        allTargets = allTargets(allTargets(:, 1) == 1, :);
    case 't2'
        allTargets = allTargets(allTargets(:, 1) == 2, :);
end
finiteTarget = isfinite(allTargets(:, 2)) & isfinite(allTargets(:, 3));
candidates = allTargets(finiteTarget, :);
end


function evalRows = localEvaluateTargets(targetCandidates, startPos, landingPos, saccVec)
template = struct( ...
    'targetId', NaN, ...
    'targetX', NaN, ...
    'targetY', NaN, ...
    'preErrPx', NaN, ...
    'postErrPx', NaN, ...
    'errReductionPx', NaN, ...
    'fracErrReduction', NaN, ...
    'projTowardTargetPx', NaN, ...
    'directionCosine', NaN);
evalRows = repmat(template, size(targetCandidates, 1), 1);
nEval = 0;
for i = 1:size(targetCandidates, 1)
    targetId = targetCandidates(i, 1);
    targetPos = targetCandidates(i, 2:3);
    preVec = targetPos - startPos;
    preErrPx = hypot(preVec(1), preVec(2));
    postErrPx = hypot(targetPos(1) - landingPos(1), targetPos(2) - landingPos(2));
    errReductionPx = preErrPx - postErrPx;
    fracErrReduction = NaN;
    projTowardTargetPx = NaN;
    directionCosine = NaN;
    saccAmpPx = hypot(saccVec(1), saccVec(2));
    if isfinite(preErrPx) && preErrPx > 0
        fracErrReduction = errReductionPx ./ preErrPx;
        unitToTarget = preVec ./ preErrPx;
        projTowardTargetPx = saccVec(1) .* unitToTarget(1) + saccVec(2) .* unitToTarget(2);
        if isfinite(saccAmpPx) && saccAmpPx > 0
            directionCosine = projTowardTargetPx ./ saccAmpPx;
        end
    end
    if ~(isfinite(preErrPx) && isfinite(postErrPx) && isfinite(errReductionPx))
        continue
    end
    nEval = nEval + 1;
    evalRows(nEval, 1) = struct( ...
        'targetId', targetId, ...
        'targetX', targetPos(1), ...
        'targetY', targetPos(2), ...
        'preErrPx', preErrPx, ...
        'postErrPx', postErrPx, ...
        'errReductionPx', errReductionPx, ...
        'fracErrReduction', fracErrReduction, ...
        'projTowardTargetPx', projTowardTargetPx, ...
        'directionCosine', directionCosine);
end
if nEval == 0
    evalRows = template([]);
else
    evalRows = evalRows(1:nEval);
end
end


function selected = localSelectTargetEvaluation(targetEval, targetMode)
selected = [];
if isempty(targetEval)
    return
end
switch targetMode
    case {'t1', 't2'}
        selected = targetEval(1);
    case 'any'
        reductions = [targetEval.errReductionPx];
        [~, idx] = max(reductions);
        selected = targetEval(idx);
end
end


function summary = localSummarizeSaccades(saccades, mode)
if isempty(saccades)
    summary = table();
    return
end
switch mode
    case "target"
        [groupIdx, groupInfo] = findgroups(saccades(:, {'group','selectedTargetId'}));
    otherwise
        [groupIdx, groupInfo] = findgroups(saccades(:, {'group'}));
end
nGroup = height(groupInfo);
rows = cell(nGroup, 1);
for i = 1:nGroup
    S = saccades(groupIdx == i, :);
    label = string(missing);
    if ismember('groupLabel', S.Properties.VariableNames) && ~isempty(S.groupLabel)
        labelIdx = find(strlength(strtrim(S.groupLabel)) > 0 & ~ismissing(S.groupLabel), 1, 'first');
        if ~isempty(labelIdx)
            label = S.groupLabel(labelIdx);
        end
    end
    targetId = NaN;
    if ismember('selectedTargetId', groupInfo.Properties.VariableNames)
        targetId = groupInfo.selectedTargetId(i);
    end
    isCorr = logical(S.isCorrective);
    landed = logical(S.landedWithinTarget);
    analyzedDurationSec = localSummaryAnalyzedDurationSec(S);
    saccFreqHz = NaN;
    if isfinite(analyzedDurationSec) && analyzedDurationSec > 0
        saccFreqHz = height(S) ./ analyzedDurationSec;
    end
    rows{i} = table( ...
        double(groupInfo.group(i)), label, targetId, height(S), ...
        analyzedDurationSec, saccFreqHz, ...
        sum(isCorr), mean(double(isCorr), 'omitnan'), ...
        sum(landed), mean(double(landed), 'omitnan'), ...
        mean(S.saccAmpDeg, 'omitnan'), median(S.saccAmpDeg, 'omitnan'), ...
        mean(S.saccAmpDeg(isCorr), 'omitnan'), mean(S.saccAmpDeg(~isCorr), 'omitnan'), ...
        mean(S.landingDistToTargetDeg, 'omitnan'), median(S.landingDistToTargetDeg, 'omitnan'), ...
        mean(S.errReductionDeg, 'omitnan'), median(S.errReductionDeg, 'omitnan'), ...
        mean(S.fracErrReduction, 'omitnan'), median(S.fracErrReduction, 'omitnan'), ...
        localPearson(S.saccAmpDeg, S.errReductionDeg), ...
        localPearson(S.saccAmpDeg, S.fracErrReduction), ...
        localPearson(S.saccAmpDeg, double(isCorr)), ...
        'VariableNames', { ...
            'group','groupLabel','selectedTargetId','nSaccades', ...
            'analyzedDurationSec','saccFreqHz', ...
            'nCorrective','correctiveFrac', ...
            'nLandedWithinTarget','landedWithinTargetFrac', ...
            'ampMeanDeg','ampMedianDeg', ...
            'ampCorrectiveMeanDeg','ampNonCorrectiveMeanDeg', ...
            'landingDistMeanDeg','landingDistMedianDeg', ...
            'errReductionMeanDeg','errReductionMedianDeg', ...
            'fracErrReductionMean','fracErrReductionMedian', ...
            'corrAmpErrReduction','corrAmpFracErrReduction', ...
            'corrAmpCorrective'});
end
summary = vertcat(rows{:});
if mode ~= "target"
    summary.selectedTargetId = [];
end
end


function durationSec = localAnalyzedDurationSec(tRel)
tRel = double(tRel(:));
tRel = tRel(isfinite(tRel));
if numel(tRel) < 2
    durationSec = NaN;
    return
end
durationSec = max(tRel) - min(tRel);
if ~(isfinite(durationSec) && durationSec > 0)
    durationSec = NaN;
end
end


function durationSec = localSummaryAnalyzedDurationSec(S)
durationSec = NaN;
if ~ismember('trialAnalyzedDurationSec', S.Properties.VariableNames) || isempty(S)
    return
end
[trialGroups, trialInfo] = findgroups(S(:, {'trial'}));
trialDur = splitapply(@(x) max(double(x), [], 'omitnan'), S.trialAnalyzedDurationSec, trialGroups);
trialDur = double(trialDur(:));
trialDur = trialDur(isfinite(trialDur) & trialDur > 0);
if isempty(trialDur)
    return
end
durationSec = sum(trialDur, 'omitnan');
end


function r = localPearson(x, y)
x = double(x(:));
y = double(y(:));
ok = isfinite(x) & isfinite(y);
x = x(ok);
y = y(ok);
if numel(x) < 2 || numel(unique(x)) < 2 || numel(unique(y)) < 2
    r = NaN;
    return
end
x = x - mean(x);
y = y - mean(y);
den = sqrt(sum(x.^2) .* sum(y.^2));
if den <= 0 || ~isfinite(den)
    r = NaN;
else
    r = sum(x .* y) ./ den;
end
end


function localPlotSaccades(saccades, opts)
if logical(opts.newFigure)
    figure;
end
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
hold on
notCorr = ~logical(saccades.isCorrective);
scatter(saccades.saccAmpDeg(notCorr), saccades.errReductionDeg(notCorr), ...
    18, [0.55 0.55 0.55], 'filled', 'MarkerFaceAlpha', 0.45);
scatter(saccades.saccAmpDeg(logical(saccades.isCorrective)), ...
    saccades.errReductionDeg(logical(saccades.isCorrective)), ...
    20, [0.15 0.45 0.85], 'filled', 'MarkerFaceAlpha', 0.65);
yline(0, ':k');
xlabel('Saccade amplitude (deg)');
ylabel('Error reduction (deg)');
title('Correctiveness by amplitude', 'Interpreter', 'none');
box off

nexttile;
hold on
edges = localHistogramEdges(saccades.saccAmpDeg);
histogram(saccades.saccAmpDeg(notCorr), edges, 'FaceColor', [0.55 0.55 0.55], ...
    'FaceAlpha', 0.45, 'EdgeColor', 'none');
histogram(saccades.saccAmpDeg(logical(saccades.isCorrective)), edges, ...
    'FaceColor', [0.15 0.45 0.85], 'FaceAlpha', 0.55, 'EdgeColor', 'none');
xlabel('Saccade amplitude (deg)');
ylabel('Count');
title('Amplitude distribution', 'Interpreter', 'none');
legend({'not corrective', 'corrective'}, 'Location', 'best');
box off
sgtitle(sprintf('Saccade correctiveness, targetMode=%s, targetLead=%.0f ms', ...
    opts.targetMode, 1000 * opts.targetLeadSec), 'Interpreter', 'none');
end


function edges = localHistogramEdges(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    edges = 0:1;
    return
end
xMin = min(x);
xMax = max(x);
if xMin == xMax
    pad = max(0.5, abs(xMin) * 0.1);
    edges = [xMin - pad, xMax + pad];
    return
end
nBins = max(5, min(30, round(sqrt(numel(x)))));
edges = linspace(xMin, xMax, nBins + 1);
end


function refIdx = localReferenceIndex(tRel, refTimeSec)
refIdx = find(double(tRel(:)) <= refTimeSec, 1, 'last');
if isempty(refIdx)
    [~, refIdx] = min(abs(double(tRel(:)) - refTimeSec));
end
end


function targetMode = localResolveTargetMode(value)
if isempty(value)
    targetMode = 'any';
    return
end
targetMode = validatestring(char(string(value)), {'any','t1','t2'});
end


function [radiusPx, radiusDeg] = localResolveLandingRadius(ex, opts)
radiusDeg = localFirstScalar(opts.landingRadiusDeg);
radiusPx = NaN;
if isfinite(radiusDeg) && radiusDeg > 0
    radiusPx = localDeg2px(radiusDeg, ex.setup);
    return
end

radiusScale = localFirstScalar(opts.landingRadiusScale);
if ~(isfinite(radiusScale) && radiusScale > 0)
    radiusScale = 2.5;
end

if isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'graph')
    graph = ex.exp.CoPs.graph;
    if isfield(graph, 'radius') && isfield(graph, 'size_mult') && ...
            isscalar(graph.radius) && isscalar(graph.size_mult) && ...
            isfinite(graph.radius) && isfinite(graph.size_mult)
        radiusPx = radiusScale .* double(graph.radius) .* double(graph.size_mult);
        radiusDeg = px2deg(radiusPx, ex.setup);
    end
end

if ~(isfinite(radiusPx) && radiusPx > 0 && isfinite(radiusDeg) && radiusDeg > 0)
    radiusDeg = 4;
    radiusPx = localDeg2px(radiusDeg, ex.setup);
end

if ~(isfinite(radiusPx) && radiusPx > 0)
    error('saccadeCorrectiveness:BadLandingRadius', ...
        'Could not resolve a finite positive landing radius.');
end
end


function px = localDeg2px(deg, setup)
dpp = px2deg(1, setup);
if ~(isfinite(dpp) && dpp > 0)
    px = NaN;
else
    px = double(deg) ./ dpp;
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
    error('saccadeCorrectiveness:NamedGroupEmpty', ...
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
        error('saccadeCorrectiveness:UnknownTrialCode', ...
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
            error('saccadeCorrectiveness:NamedGroupEmpty', ...
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
            error('saccadeCorrectiveness:NamedGroupEmpty', ...
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
            error('saccadeCorrectiveness:NamedGroupEmpty', ...
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
            error('saccadeCorrectiveness:NamedGroupEmpty', ...
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
    error('saccadeCorrectiveness:BadTrialNo', ...
        'Each trial selection must contain finite integer trial indices.');
end
trialVec = trialVec(trialVec >= 1 & trialVec <= nTrials);
if isempty(trialVec)
    error('saccadeCorrectiveness:BadTrialNo', ...
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


function tw = localTimeWindow(value)
tw = [];
if isempty(value) || ~isnumeric(value) || numel(value) < 2
    return
end
tw = double(value(1:2));
if any(~isfinite(tw))
    tw = [];
    return
end
tw = sort(tw(:))';
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
