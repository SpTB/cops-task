function out = exportCoPsTwoTargetLqg(exOrPath, outPath, opts)
% exportCoPsTwoTargetLqg
% Convert CoPs ex.Trials data into simple arrays for the two-target LQG code.
%
% out = exportCoPsTwoTargetLqg(ex)
% out = exportCoPsTwoTargetLqg('/path/to/session.mat')
% out = exportCoPsTwoTargetLqg(ex, '/path/to/lqg_export.mat')
%
% Output arrays use display pixels and are shaped:
%   out.x1      : N x T x 2, target 1 [x y]
%   out.x2      : N x T x 2, target 2 [x y]
%   out.gaze    : N x T x 2, calibrated gaze [x y]
%   out.mask    : N x T, true where gaze and required targets are finite/in-bounds
%   out.tRelSec : N x T, time relative to trial start
%   out.step    : N x T, target-step index
%   out.trialMeta.rewardCenterPx : N x 2, Gaussian reward center [x y]
%
% One-target trials keep out.x2 as NaN. out.targetPresent marks which
% target columns are meaningful, and out.fit has separate singleTarget and
% twoTarget views for model-specific Python code.
%
% Gaze preprocessing mirrors plotTraj by default: invalid/out-of-texture
% samples are masked, true short missing/blink gaps are interpolated,
% position traces are low-pass filtered, then the requested modelling
% timebase is applied.
%
% When opts.canonicalizeTargets is true, target order is determined once
% from the first output sample where both targets are finite. T1 is the
% target that starts on the left (then upper on an exact x tie), and that
% identity assignment is retained for the entire trial.

if nargin < 2
    outPath = [];
end
if nargin == 2 && isstruct(outPath)
    opts = outPath;
    outPath = [];
elseif nargin < 3 || isempty(opts)
    opts = struct();
end

analysisDir = fileparts(mfilename('fullpath'));
helperDir = fullfile(analysisDir, 'helpers');
repoDir = fileparts(analysisDir);
if exist(repoDir, 'dir') == 7
    addpath(repoDir);
end
if exist(helperDir, 'dir') == 7
    addpath(helperDir);
end

ex = localLoadEx(exOrPath);
opts = localApplyDefaults(opts);

if ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('exportCoPsTwoTargetLqg:MissingTrials', 'Input ex has no ex.Trials.');
end

timebase = lower(char(string(opts.timebase)));
if ~ismember(timebase, {'step', 'sample'})
    error('exportCoPsTwoTargetLqg:BadTimebase', ...
        'opts.timebase must be ''step'' or ''sample''.');
end

trialRows = struct([]);
nTr = numel(ex.Trials);

for j = 1:nTr
    T = ex.Trials(j);
    if opts.mainOnly && ~localIsMainTrial(T, opts.includePreTrials)
        continue
    end
    targetNum = localTargetNum(ex, T);
    if ~localModelAcceptsTargetNum(opts.modelType, targetNum)
        continue
    end
    if ~isfield(T, 'targetPositions') || isempty(T.targetPositions)
        continue
    end

    [xPx, yPx, tRel, tAbs, valid] = reconstructEyePx(ex, T, opts.useEyeTime, opts);
    if isempty(tRel)
        continue
    end

    [targetX, targetY, target2X, target2Y, stepIdx] = mapTargetsByStep(ex, T, tRel);

    keep = true(size(tRel(:)));
    if opts.onlyGoState
        keep = keep & localGoMask(T, tAbs);
    end

    xPx = xPx(keep);
    yPx = yPx(keep);
    tRel = tRel(keep);
    valid = valid(keep);
    targetX = targetX(keep);
    targetY = targetY(keep);
    target2X = target2X(keep);
    target2Y = target2Y(keep);
    stepIdx = stepIdx(keep);

    [xPx, yPx, inBounds] = localPreprocessGaze(ex, xPx, yPx, valid, opts);
    switch timebase
        case 'step'
            row = localBuildStepRow(ex, T, j, xPx, yPx, tRel, inBounds, ...
                targetX, targetY, target2X, target2Y, stepIdx, opts);
        case 'sample'
            row = localBuildSampleRow(ex, T, j, xPx, yPx, tRel, inBounds, ...
                targetX, targetY, target2X, target2Y, stepIdx);
    end
    if opts.canonicalizeTargets
        [row.x1(:, 1), row.x1(:, 2), row.x2(:, 1), row.x2(:, 2)] = ...
            localCanonicalizeTargetOrder(row.x1(:, 1), row.x1(:, 2), ...
            row.x2(:, 1), row.x2(:, 2));
    end

    if row.finiteFrac < opts.minFiniteFrac
        continue
    end

    if isempty(trialRows)
        trialRows = row;
    else
        trialRows(end + 1) = row; %#ok<AGROW>
    end
end

out = localPackRows(ex, trialRows, opts, timebase);

if ~isempty(outPath)
    save(outPath, '-struct', 'out');
end
end


function ex = localLoadEx(exOrPath)
if ischar(exOrPath) || (isstring(exOrPath) && isscalar(exOrPath))
    s = load(char(exOrPath));
    if ~isfield(s, 'ex')
        error('exportCoPsTwoTargetLqg:MissingEx', ...
            'MAT file does not contain a variable named ex: %s', char(exOrPath));
    end
    ex = s.ex;
elseif isstruct(exOrPath)
    ex = exOrPath;
else
    error('exportCoPsTwoTargetLqg:BadInput', ...
        'First input must be an ex struct or path to a MAT file containing ex.');
end
end


function opts = localApplyDefaults(opts)
hadModelType = isfield(opts, 'modelType') && ~isempty(opts.modelType);
hadTwoTargetOnly = isfield(opts, 'twoTargetOnly') && ~isempty(opts.twoTargetOnly);
hadGazeAgg = isfield(opts, 'gazeAgg') && ~isempty(opts.gazeAgg);
hadLegacyAgg = isfield(opts, 'cursorAgg') && ~isempty(opts.cursorAgg);
legacyTwoTargetOnly = [];
if hadTwoTargetOnly
    legacyTwoTargetOnly = logical(opts.twoTargetOnly);
end
legacyGazeAgg = [];
if hadLegacyAgg
    legacyGazeAgg = opts.cursorAgg;
end

defaults = struct( ...
    'timebase', 'step', ...
    'modelType', 'mixed', ...
    'useEyeTime', true, ...
    'onlyGoState', true, ...
    'mainOnly', true, ...
    'includePreTrials', true, ...
    'twoTargetOnly', [], ...
    'canonicalizeTargets', true, ...
    'gazeAgg', 'median', ...
    'interpBlinkSec', 0.15, ...
    'lowpassHz', 5, ...
    'inBoundsPadPx', 0, ...
    'minFiniteFrac', 0.5, ...
    'nSteps', NaN);

names = fieldnames(defaults);
for i = 1:numel(names)
    name = names{i};
    if ~isfield(opts, name)
        opts.(name) = defaults.(name);
    end
end

opts.useEyeTime = logical(opts.useEyeTime);
opts.onlyGoState = logical(opts.onlyGoState);
opts.mainOnly = logical(opts.mainOnly);
opts.includePreTrials = logical(opts.includePreTrials);
if ~hadGazeAgg && hadLegacyAgg
    opts.gazeAgg = legacyGazeAgg;
end
if ~hadModelType && hadTwoTargetOnly
    if legacyTwoTargetOnly
        opts.modelType = 'twoTarget';
    else
        opts.modelType = 'mixed';
    end
end
opts.modelType = localCanonicalModelType(opts.modelType);
if isempty(opts.twoTargetOnly)
    opts.twoTargetOnly = strcmp(opts.modelType, 'twoTarget');
else
    opts.twoTargetOnly = logical(opts.twoTargetOnly);
end
opts.canonicalizeTargets = logical(opts.canonicalizeTargets);
opts.interpBlinkSec = double(opts.interpBlinkSec);
opts.lowpassHz = double(opts.lowpassHz);
opts.inBoundsPadPx = double(opts.inBoundsPadPx);
opts.minFiniteFrac = double(opts.minFiniteFrac);
opts.nSteps = double(opts.nSteps);
end


function modelType = localCanonicalModelType(value)
modelType = lower(strrep(strrep(char(string(value)), '-', ''), '_', ''));
switch modelType
    case {'mixed', 'all', 'any'}
        modelType = 'mixed';
    case {'single', 'singletarget', 'onetarget', 'one', '1'}
        modelType = 'singleTarget';
    case {'two', 'twotarget', 'twotargets', 'twoonly', '2'}
        modelType = 'twoTarget';
    otherwise
        error('exportCoPsTwoTargetLqg:BadModelType', ...
            'opts.modelType must be ''mixed'', ''singleTarget'', or ''twoTarget''.');
end
end


function tf = localModelAcceptsTargetNum(modelType, targetNum)
switch modelType
    case 'singleTarget'
        tf = targetNum == 1;
    case 'twoTarget'
        tf = targetNum >= 2;
    otherwise
        tf = ismember(targetNum, [1, 2]);
end
end


function tf = localIsMainTrial(T, includePreTrials)
isFixationTrial = isfield(T, 'isFixationTrial') && logical(T.isFixationTrial);
isTutorialTrial = isfield(T, 'isTutorialTrial') && logical(T.isTutorialTrial);
if isfield(T, 'runPhase') && ~isempty(T.runPhase)
    phase = string(T.runPhase);
    tf = phase == "main" || (includePreTrials && phase == "pre");
else
    tf = ~isFixationTrial && ~isTutorialTrial;
end
tf = tf && ~isFixationTrial && ~isTutorialTrial;
end


function n = localTargetNum(ex, T)
n = localScalarField(T, 'target_num', NaN);
if ~isfinite(n) && isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && ...
        isfield(ex.exp.CoPs, 'ctl') && isfield(ex.exp.CoPs.ctl, 'target_num')
    val = ex.exp.CoPs.ctl.target_num;
    if isnumeric(val) && ~isempty(val)
        n = double(val(1));
    end
end
if ~isfinite(n)
    n = 1;
    if isfield(T, 'targetPositions') && ~isempty(T.targetPositions) && ...
            isfield(T.targetPositions(1), 'targ2')
        n = 2;
    end
end
n = round(n);
end


function mask = localGoMask(T, tAbs)
mask = true(size(tAbs(:)));
if isfield(T, 'times') && isstruct(T.times) && isfield(T.times, 'stimOn') && ...
        isfield(T, 'TrialEnd') && ~isempty(T.times.stimOn) && ~isempty(T.TrialEnd)
    stimOn = double(T.times.stimOn(1));
    trialEnd = double(T.TrialEnd(1));
    if isfinite(stimOn) && isfinite(trialEnd)
        mask = tAbs(:) >= stimOn & tAbs(:) <= trialEnd;
    end
end
end


function inBounds = localInBounds(ex, xPx, yPx, valid, padPx)
inBounds = valid(:) & isfinite(xPx(:)) & isfinite(yPx(:));
bounds = localGazeBounds(ex);
if ~isempty(bounds)
    inBounds = inBounds & xPx(:) >= bounds.xMin - padPx & ...
        xPx(:) <= bounds.xMax + padPx & yPx(:) >= bounds.yMin - padPx & ...
        yPx(:) <= bounds.yMax + padPx;
end
end


function [xPx, yPx, inBounds] = localPreprocessGaze(ex, xPx, yPx, valid, opts)
xPx = xPx(:);
yPx = yPx(:);
valid = logical(valid(:)) & isfinite(xPx) & isfinite(yPx);

rawInBounds = localInBounds(ex, xPx, yPx, valid, opts.inBoundsPadPx);
xPx(~rawInBounds) = NaN;
yPx(~rawInBounds) = NaN;
filled = false(size(xPx));

interpBlinkSec = localFirstScalar(opts.interpBlinkSec);
if isfinite(interpBlinkSec) && interpBlinkSec > 0
    dtSec = 1 / inferFs(ex);
    maxGapSamples = max(1, round(interpBlinkSec / dtSec));
    blinkGap = ~valid;
    [xPx, filledX] = localInterpShortNaNGaps(xPx, maxGapSamples, blinkGap);
    [yPx, filledY] = localInterpShortNaNGaps(yPx, maxGapSamples, blinkGap);
    filled = filledX & filledY;
end

processedValid = (rawInBounds | filled) & isfinite(xPx) & isfinite(yPx);
lowpassHz = localFirstScalar(opts.lowpassHz);
if isfinite(lowpassHz) && lowpassHz > 0
    dtSec = 1 / inferFs(ex);
    xPx = localZeroPhaseLowpassTrace(xPx, processedValid, dtSec, lowpassHz);
    yPx = localZeroPhaseLowpassTrace(yPx, processedValid, dtSec, lowpassHz);
end

inBounds = (rawInBounds | filled) & localInBounds(ex, xPx, yPx, ...
    true(size(xPx)), opts.inBoundsPadPx);
end


function row = localBuildStepRow(ex, T, trialIdx, xPx, yPx, tRel, inBounds, ...
    targetX, targetY, target2X, target2Y, stepIdx, opts)
nsteps = localResolveNSteps(T);
targetNum = localTargetNum(ex, T);
if isfinite(opts.nSteps) && opts.nSteps > 0
    nsteps = min(nsteps, round(opts.nSteps));
end

x1 = NaN(nsteps, 2);
x2 = NaN(nsteps, 2);
gaze = NaN(nsteps, 2);
targetPresent = false(nsteps, 2);
tOut = NaN(nsteps, 1);
stepOut = (1:nsteps)';
mask = false(nsteps, 1);

for s = 1:nsteps
    mStep = stepIdx(:) == s;
    if any(mStep)
        x1(s, :) = localFirstFinitePair(targetX(mStep), targetY(mStep));
        x2(s, :) = localFirstFinitePair(target2X(mStep), target2Y(mStep));
        tOut(s) = median(tRel(mStep), 'omitnan');
    else
        [x1(s, :), x2(s, :)] = localTargetsFromSavedStep(T, s);
    end

    mGaze = mStep & inBounds(:);
    gaze(s, :) = localAggregateGaze(xPx(mGaze), yPx(mGaze), opts.gazeAgg);
    targetPresent(s, 1) = all(isfinite(x1(s, :)));
    targetPresent(s, 2) = targetNum >= 2 && all(isfinite(x2(s, :)));
    mask(s) = all(isfinite(gaze(s, :))) && targetPresent(s, 1) && ...
        (targetNum < 2 || targetPresent(s, 2));
end
tOut = localFillMissingStepTimes(tOut, stepOut, T);

row = localBaseRow(ex, T, trialIdx);
row.x1 = x1;
row.x2 = x2;
row.gaze = gaze;
row.targetPresent = targetPresent;
row.tRelSec = tOut;
row.step = stepOut;
row.mask = mask;
row.nTime = nsteps;
row.finiteFrac = mean(mask, 'omitnan');
row.inBoundsFrac = mean(inBounds, 'omitnan');
end


function time = localFillMissingStepTimes(time, step, T)
% Fill target steps lacking eye samples without discarding the eye-time offset.
time = double(time(:));
step = double(step(:));
missing = ~isfinite(time);
if ~any(missing)
    return
end
dt = localScalarField(T, 'waitSecs', NaN);
observed = isfinite(time) & isfinite(step);
if ~(isfinite(dt) && dt > 0) && nnz(observed) >= 2
    observedStep = step(observed);
    observedTime = time(observed);
    slopes = diff(observedTime) ./ diff(observedStep);
    slopes = slopes(isfinite(slopes) & slopes > 0);
    if ~isempty(slopes)
        dt = median(slopes);
    end
end
if ~(isfinite(dt) && dt > 0)
    return
end
if any(observed)
    % Observed step times can include a trial-specific eye-time alignment
    % offset. Estimate it robustly instead of reverting to time zero.
    offset = median(time(observed) - (step(observed) - 1) .* dt, 'omitnan');
else
    offset = 0;
end
time(missing) = offset + (step(missing) - 1) .* dt;
end


function row = localBuildSampleRow(ex, T, trialIdx, xPx, yPx, tRel, inBounds, ...
    targetX, targetY, target2X, target2Y, stepIdx)
n = numel(tRel);
targetNum = localTargetNum(ex, T);
row = localBaseRow(ex, T, trialIdx);
row.x1 = [targetX(:), targetY(:)];
row.x2 = [target2X(:), target2Y(:)];
row.gaze = [xPx(:), yPx(:)];
row.gaze(~inBounds(:), :) = NaN;
row.targetPresent = false(n, 2);
row.targetPresent(:, 1) = all(isfinite(row.x1), 2);
row.targetPresent(:, 2) = targetNum >= 2 & all(isfinite(row.x2), 2);
row.tRelSec = tRel(:);
row.step = stepIdx(:);
row.mask = inBounds(:) & row.targetPresent(:, 1) & ...
    (targetNum < 2 | row.targetPresent(:, 2));
row.nTime = n;
row.finiteFrac = mean(row.mask, 'omitnan');
row.inBoundsFrac = mean(inBounds, 'omitnan');
end


function row = localBaseRow(ex, T, trialIdx)
row = struct();
row.trialIdx = trialIdx;
row.targetNum = localTargetNum(ex, T);
row.nsteps = localScalarField(T, 'nsteps', NaN);
row.waitSecs = localScalarField(T, 'waitSecs', NaN);
row.backgroundNoiseLvl = localScalarField(T, 'background_noise_lvl', NaN);
row.targetVisibility = localScalarField(T, 'target_visibility', NaN);
row.coherence = localScalarField(T, 'coherence', NaN);
row.rewardAccumulated = localScalarField(T, 'rewardAccumulated', NaN);
row.rewardCenterPx = localRewardCenterPx(ex, T);
row.runPhase = localRunPhase(T);
end


function out = localPackRows(ex, rows, opts, timebase)
out = struct();
out.format = 'CoPsTwoTargetLqgExport';
out.formatVersion = 4;
out.timebase = timebase;
out.units = 'display_pixels';
out.geometry = localExportGeometry(ex);
out.opts = opts;

if isempty(rows)
    out.x1 = NaN(0, 0, 2);
    out.x2 = NaN(0, 0, 2);
    out.gaze = NaN(0, 0, 2);
    out.targetPresent = false(0, 0, 2);
    out.mask = false(0, 0);
    out.tRelSec = NaN(0, 0);
    out.step = NaN(0, 0);
    out.trialMeta = struct();
    out.fit = localFitViews(out.x1, out.x2, out.gaze, out.mask, ...
        NaN(0, 1), NaN(0, 1), false(0, 1));
    return
end

n = numel(rows);
Tmax = max([rows.nTime]);
if isfinite(opts.nSteps) && opts.nSteps > 0
    Tmax = round(opts.nSteps);
end

x1 = NaN(n, Tmax, 2);
x2 = NaN(n, Tmax, 2);
gaze = NaN(n, Tmax, 2);
targetPresent = false(n, Tmax, 2);
mask = false(n, Tmax);
tRelSec = NaN(n, Tmax);
step = NaN(n, Tmax);

meta = struct();
meta.trialIdx = NaN(n, 1);
meta.targetNum = NaN(n, 1);
meta.nsteps = NaN(n, 1);
meta.waitSecs = NaN(n, 1);
meta.backgroundNoiseLvl = NaN(n, 1);
meta.targetVisibility = NaN(n, 1);
meta.coherence = NaN(n, 1);
meta.rewardAccumulated = NaN(n, 1);
meta.rewardCenterPx = NaN(n, 2);
meta.inBoundsFrac = NaN(n, 1);
meta.finiteFrac = NaN(n, 1);
meta.runPhase = cell(n, 1);

for i = 1:n
    nt = min(rows(i).nTime, Tmax);
    x1(i, 1:nt, :) = rows(i).x1(1:nt, :);
    x2(i, 1:nt, :) = rows(i).x2(1:nt, :);
    gaze(i, 1:nt, :) = rows(i).gaze(1:nt, :);
    targetPresent(i, 1:nt, :) = rows(i).targetPresent(1:nt, :);
    mask(i, 1:nt) = rows(i).mask(1:nt);
    tRelSec(i, 1:nt) = rows(i).tRelSec(1:nt);
    step(i, 1:nt) = rows(i).step(1:nt);

    meta.trialIdx(i) = rows(i).trialIdx;
    meta.targetNum(i) = rows(i).targetNum;
    meta.nsteps(i) = rows(i).nsteps;
    meta.waitSecs(i) = rows(i).waitSecs;
    meta.backgroundNoiseLvl(i) = rows(i).backgroundNoiseLvl;
    meta.targetVisibility(i) = rows(i).targetVisibility;
    meta.coherence(i) = rows(i).coherence;
    meta.rewardAccumulated(i) = rows(i).rewardAccumulated;
    meta.rewardCenterPx(i, :) = rows(i).rewardCenterPx;
    meta.inBoundsFrac(i) = rows(i).inBoundsFrac;
    meta.finiteFrac(i) = rows(i).finiteFrac;
    meta.runPhase{i} = rows(i).runPhase;
end

out.x1 = x1;
out.x2 = x2;
out.gaze = gaze;
out.targetPresent = targetPresent;
out.mask = mask;
out.tRelSec = tRelSec;
out.step = step;
out.trialMeta = meta;

complete = all(mask, 2);
out.fit = localFitViews(x1, x2, gaze, mask, meta.trialIdx, meta.targetNum, complete);
end


function centerPx = localRewardCenterPx(ex, T)
centerPx = [NaN, NaN];
try
    value = getGaussianCenterPx(ex, T);
catch
    value = [];
end
if isempty(value) && isfield(T, 'gaussRewardCenterPx')
    value = T.gaussRewardCenterPx;
end
if isnumeric(value) && numel(value) >= 2
    value = double(value(:)');
    if all(isfinite(value(1:2)))
        centerPx = value(1:2);
    end
end
end


function fit = localFitViews(x1, x2, gaze, mask, trialIdx, targetNum, complete)
complete = complete(:);
targetNum = targetNum(:);

singleComplete = complete & targetNum == 1;
twoComplete = complete & targetNum >= 2;

fit = struct();
fit.x1 = x1(complete, :, :);
fit.x2 = x2(complete, :, :);
fit.gaze = gaze(complete, :, :);
fit.mask = mask(complete, :);
fit.trialIdx = trialIdx(complete);
fit.targetNum = targetNum(complete);
fit.completeMask = complete;

fit.singleTarget = struct();
fit.singleTarget.x1 = x1(singleComplete, :, :);
fit.singleTarget.gaze = gaze(singleComplete, :, :);
fit.singleTarget.mask = mask(singleComplete, :);
fit.singleTarget.trialIdx = trialIdx(singleComplete);
fit.singleTarget.targetNum = targetNum(singleComplete);

fit.twoTarget = struct();
fit.twoTarget.x1 = x1(twoComplete, :, :);
fit.twoTarget.x2 = x2(twoComplete, :, :);
fit.twoTarget.gaze = gaze(twoComplete, :, :);
fit.twoTarget.mask = mask(twoComplete, :);
fit.twoTarget.trialIdx = trialIdx(twoComplete);
fit.twoTarget.targetNum = targetNum(twoComplete);
end


function nsteps = localResolveNSteps(T)
nsteps = localScalarField(T, 'nsteps', NaN);
if ~isfinite(nsteps) || nsteps < 1
    if isfield(T, 'targetPositions')
        nsteps = numel(T.targetPositions);
    else
        nsteps = 0;
    end
end
nsteps = max(0, round(nsteps));
if isfield(T, 'targetPositions')
    nsteps = min(nsteps, numel(T.targetPositions));
end
end


function xy = localFirstFinitePair(x, y)
x = x(:);
y = y(:);
idx = find(isfinite(x) & isfinite(y), 1, 'first');
if isempty(idx)
    xy = [NaN, NaN];
else
    xy = [double(x(idx)), double(y(idx))];
end
end


function xy = localAggregateGaze(x, y, mode)
x = x(:);
y = y(:);
keep = isfinite(x) & isfinite(y);
if ~any(keep)
    xy = [NaN, NaN];
    return
end
x = x(keep);
y = y(keep);

switch lower(char(string(mode)))
    case 'mean'
        xy = [mean(x, 'omitnan'), mean(y, 'omitnan')];
    case 'first'
        xy = [x(1), y(1)];
    case 'last'
        xy = [x(end), y(end)];
    otherwise
        xy = [median(x, 'omitnan'), median(y, 'omitnan')];
end
end


function y = localZeroPhaseLowpassTrace(x, valid, dtSec, cutoffHz)
x = x(:);
valid = logical(valid(:)) & isfinite(x);
y = x;
if ~isfinite(cutoffHz) || cutoffHz <= 0 || ~isfinite(dtSec) || dtSec <= 0
    return
end

fs = 1 / dtSec;
nyq = fs / 2;
normCutoff = cutoffHz / nyq;
if ~isfinite(normCutoff) || normCutoff <= 0 || normCutoff >= 1
    return
end

[b, a] = butter(2, normCutoff, 'low');
idx = find(valid);
if isempty(idx)
    return
end

minRunSamples = max(7, ceil((2 / cutoffHz) / dtSec));
edgePadSamples = max(1, ceil((1 / cutoffHz) / dtSec));
runBreak = [true; diff(idx) > 1];
runStarts = find(runBreak);
runEnds = [runStarts(2:end) - 1; numel(idx)];
for i = 1:numel(runStarts)
    ii = idx(runStarts(i):runEnds(i));
    if numel(ii) < minRunSamples || numel(ii) <= 2 * edgePadSamples
        continue
    end
    yf = filtfilt(b, a, x(ii));
    interior = (edgePadSamples + 1):(numel(ii) - edgePadSamples);
    y(ii(interior)) = yf(interior);
end
end


function [x, filled] = localInterpShortNaNGaps(x, maxGapSamples, fillAllowed)
x = x(:);
filled = false(size(x));
if isempty(x) || maxGapSamples < 1
    return
end
if nargin < 3 || isempty(fillAllowed)
    fillAllowed = true(size(x));
else
    fillAllowed = logical(fillAllowed(:));
end

nanMask = ~isfinite(x);
if ~any(nanMask)
    return
end

d = diff([false; nanMask; false]);
gapStarts = find(d == 1);
gapEnds = find(d == -1) - 1;
for i = 1:numel(gapStarts)
    g0 = gapStarts(i);
    g1 = gapEnds(i);
    gapLen = g1 - g0 + 1;
    if gapLen > maxGapSamples || g0 <= 1 || g1 >= numel(x)
        continue
    end
    if ~all(fillAllowed(g0:g1))
        continue
    end
    if ~isfinite(x(g0 - 1)) || ~isfinite(x(g1 + 1))
        continue
    end
    fillVals = linspace(x(g0 - 1), x(g1 + 1), gapLen + 2);
    x(g0:g1) = fillVals(2:end-1);
    filled(g0:g1) = true;
end
end


function bounds = localGazeBounds(ex)
bounds = [];
if isfield(ex, 'setup') && isfield(ex.setup, 'screenRect') && ...
        isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && ...
        isfield(ex.exp.CoPs, 'graph')
    bounds = localTextureBounds(ex.setup.screenRect, ex.exp.CoPs.graph);
    if ~isempty(bounds)
        return
    end
end

if isfield(ex, 'setup') && isfield(ex.setup, 'screenRect') && ...
        numel(ex.setup.screenRect) >= 4
    sr = double(ex.setup.screenRect);
    bounds = struct('xMin', sr(1), 'xMax', sr(3), 'yMin', sr(2), 'yMax', sr(4));
end
end


function bounds = localTextureBounds(screenRect, graph)
bounds = [];
if numel(screenRect) < 4 || ~isstruct(graph) || ...
        ~isfield(graph, 'texture_dims') || ~isfield(graph, 'size_mult') || ...
        isempty(graph.texture_dims) || isempty(graph.size_mult)
    return
end

screenRect = double(screenRect);
texDimPx = double(graph.texture_dims(1)) * double(graph.size_mult(1));
if ~isfinite(texDimPx) || texDimPx <= 0
    return
end

xShift = (screenRect(3) - texDimPx) / 2;
yShift = (screenRect(4) - texDimPx) / 2;
bounds = struct( ...
    'xMin', xShift, ...
    'xMax', xShift + texDimPx, ...
    'yMin', yShift, ...
    'yMax', yShift + texDimPx);
end


function geometry = localExportGeometry(ex)
[centerX, centerY] = localReferenceCenterPx(ex);
geometry = struct( ...
    'positionUnits', 'display_pixels', ...
    'angleUnits', 'visual_degrees', ...
    'centerPx', [centerX, centerY], ...
    'degPerPx', NaN, ...
    'pxPerDeg', NaN, ...
    'screenRect', NaN(1, 4), ...
    'monitorWidth', NaN, ...
    'viewingDistance', NaN);

if isfield(ex, 'setup') && isfield(ex.setup, 'screenRect') && ...
        numel(ex.setup.screenRect) >= 4
    geometry.screenRect = double(ex.setup.screenRect(1:4));
end
if isfield(ex, 'setup') && isfield(ex.setup, 'monitorWidth') && ...
        ~isempty(ex.setup.monitorWidth)
    geometry.monitorWidth = double(ex.setup.monitorWidth(1));
end
if isfield(ex, 'setup') && isfield(ex.setup, 'viewingDistance') && ...
        ~isempty(ex.setup.viewingDistance)
    geometry.viewingDistance = double(ex.setup.viewingDistance(1));
end
if isfield(ex, 'setup')
    try
        geometry.degPerPx = double(px2deg(1, ex.setup));
        geometry.pxPerDeg = 1 / geometry.degPerPx;
    catch
        geometry.degPerPx = NaN;
        geometry.pxPerDeg = NaN;
    end
end
end


function [x0, y0] = localReferenceCenterPx(ex)
if isfield(ex, 'fix') && isfield(ex.fix, 'PCtr') && numel(ex.fix.PCtr) >= 2 && ...
        all(isfinite(ex.fix.PCtr(1:2)))
    x0 = double(ex.fix.PCtr(1));
    y0 = double(ex.fix.PCtr(2));
    return
end
if isfield(ex, 'setup') && isfield(ex.setup, 'screenRect') && ...
        numel(ex.setup.screenRect) >= 4
    rect = double(ex.setup.screenRect);
    x0 = mean(rect([1 3]));
    y0 = mean(rect([2 4]));
    return
end
x0 = 0;
y0 = 0;
end


function [x1, x2] = localTargetsFromSavedStep(T, s)
x1 = [NaN, NaN];
x2 = [NaN, NaN];
if ~isfield(T, 'targetPositions') || numel(T.targetPositions) < s
    return
end
tp = T.targetPositions(s);
if isfield(tp, 'targ1') && isfield(tp.targ1, 'pos_abs') && numel(tp.targ1.pos_abs) >= 2
    x1 = double(tp.targ1.pos_abs(1:2));
end
if isfield(tp, 'targ2') && isfield(tp.targ2, 'pos_abs') && numel(tp.targ2.pos_abs) >= 2
    x2 = double(tp.targ2.pos_abs(1:2));
end
end


function [targetX, targetY, target2X, target2Y] = localCanonicalizeTargetOrder(targetX, targetY, target2X, target2Y)
firstValid = find(isfinite(targetX) & isfinite(targetY) & ...
    isfinite(target2X) & isfinite(target2Y), 1, 'first');
if isempty(firstValid)
    return
end

swapTrial = targetX(firstValid) > target2X(firstValid) || ...
    (targetX(firstValid) == target2X(firstValid) && ...
    targetY(firstValid) > target2Y(firstValid));
if ~swapTrial
    return
end

tmpX = targetX;
tmpY = targetY;
targetX = target2X;
targetY = target2Y;
target2X = tmpX;
target2Y = tmpY;
end


function val = localScalarField(S, name, defaultValue)
val = defaultValue;
if isstruct(S) && isfield(S, name)
    x = S.(name);
    if isnumeric(x) || islogical(x)
        if ~isempty(x)
            val = double(x(1));
        end
    end
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


function phase = localRunPhase(T)
if isfield(T, 'runPhase') && ~isempty(T.runPhase)
    phase = char(string(T.runPhase));
elseif isfield(T, 'isTutorialTrial') && logical(T.isTutorialTrial)
    phase = 'tutorial';
elseif isfield(T, 'isFixationTrial') && logical(T.isFixationTrial)
    phase = 'fixation';
else
    phase = 'main';
end
end
