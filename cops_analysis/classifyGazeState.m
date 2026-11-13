function out = classifyGazeState(ex, trialNo, opts)
% classifyGazeState  Classify gaze samples as missing, fixation, pursuit, or saccade.
%
%   out = classifyGazeState(ex)
%   out = classifyGazeState(ex, 1:120)
%   out = classifyGazeState(ex, [], opts)
%
% States
%   0 : missing / invalid
%   1 : fixation
%   2 : smooth pursuit
%   3 : saccade
%
% Fixation definition
%   A fixation sample must:
%     - be valid and non-saccadic
%     - have eye speed <= opts.fixationMaxEyeSpeedDeg
%     - have centered-window spatial dispersion <= opts.fixationMaxDispDeg
%   and belong to a contiguous run lasting at least opts.fixationMinDurSec.
%
% Smooth pursuit definition
%   Any remaining valid, non-saccadic, non-fixation sample is labeled
%   smooth pursuit.

if nargin < 2 || isempty(trialNo)
    trialNo = [];
end
if nargin >= 2 && isstruct(trialNo) && (nargin < 3 || isempty(opts))
    opts = trialNo;
    trialNo = [];
elseif nargin < 3 || isempty(opts)
    opts = struct();
end

defaults = struct( ...
    'onlyGoState', true, ...
    'useEyeTime', true, ...
    'truncateTrialFromStep', 0, ...
    'timeWindowSec', [], ...
    'interpBlinkSec', 0, ...
    'lowpassHz', [], ...
    'fixationMaxEyeSpeedDeg', 2, ...
    'fixationSpeedSmoothFrames', 10, ...
    'fixationMaxDispDeg', 2, ...
    'fixationWindowSec', 0.10, ...
    'fixationMinValidFrac', 0.5, ...
    'fixationMinDurSec', 0.025, ...
    'fixationBridgeGapSec', 0.05, ...
    'speedThreshDegPerSec', 10, ...
    'saccadePadSec', 0.02, ...
    'minAmpDeg', 1, ...
    'minDurSec', 0.008, ...
    'maxDurSec', 5, ...
    'smoothFrames', 5);
opts = localApplyLegacySaccadeAliases(opts);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field) || isempty(opts.(field))
        opts.(field) = defaults.(field);
    end
end

if ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('classifyGazeState:NoTrials', 'Input ex has no trials in ex.Trials.');
end

trialVec = localNormalizeTrialVector(trialNo, numel(ex.Trials));
nTrials = numel(trialVec);
sampleRows = cell(nTrials, 1);
summaryRows = cell(nTrials, 1);
for iTrial = 1:nTrials
    j = trialVec(iTrial);
    sampleRows{iTrial} = localClassifyOneTrial(ex, j, opts);
    summaryRows{iTrial} = localSummarizeTrial(sampleRows{iTrial});
end

samples = vertcat(sampleRows{:});
summary = vertcat(summaryRows{:});

out = struct();
out.samples = samples;
out.summary = summary;
out.trials = trialVec(:);
out.options = opts;
out.stateCodes = table( ...
    uint8([0; 1; 2; 3]), ...
    string({'missing'; 'fixation'; 'smoothPursuit'; 'saccade'}), ...
    'VariableNames', {'state', 'stateName'});
end


function S = localClassifyOneTrial(ex, trialNo, opts)
T = ex.Trials(trialNo);
[xPx, yPx, tRel, tAbs, valid] = reconstructEyePx(ex, T, opts.useEyeTime, opts);
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

truncateFromStep = double(localFirstScalar(opts.truncateTrialFromStep));
if isfinite(truncateFromStep) && truncateFromStep > 0
    keepMask = isfinite(stepIdx) & stepIdx >= truncateFromStep;
    xPx = xPx(keepMask);
    yPx = yPx(keepMask);
    tRel = tRel(keepMask);
    tAbs = tAbs(keepMask);
    valid = valid(keepMask);
    targetX = targetX(keepMask);
    targetY = targetY(keepMask);
    target2X = target2X(keepMask);
    target2Y = target2Y(keepMask);
    stepIdx = stepIdx(keepMask);
end

sampleIdx = (1:numel(tRel))';
dtSec = localResolveSampleDt(tRel, 1 / inferFs(ex));

if isfinite(localFirstScalar(opts.interpBlinkSec)) && localFirstScalar(opts.interpBlinkSec) > 0
    maxGapSamples = max(1, round(localFirstScalar(opts.interpBlinkSec) / dtSec));
    xPx = localInterpShortNaNGaps(xPx, maxGapSamples);
    yPx = localInterpShortNaNGaps(yPx, maxGapSamples);
    valid = valid & isfinite(xPx) & isfinite(yPx);
end

if isfinite(localFirstScalar(opts.lowpassHz)) && localFirstScalar(opts.lowpassHz) > 0
    xPx = localZeroPhaseLowpassTrace(xPx, valid, dtSec, localFirstScalar(opts.lowpassHz));
    yPx = localZeroPhaseLowpassTrace(yPx, valid, dtSec, localFirstScalar(opts.lowpassHz));
end

saccParams = localSaccadeParams(dtSec, opts);
[saccStarts, saccStops, eyeSpeedDegPerSec] = detectTrackingSaccadesCoPs(xPx, yPx, dtSec, ex.setup, saccParams);
saccMask = false(size(xPx));
padFrames = max(0, round(localFirstScalar(opts.saccadePadSec) / dtSec));
for i = 1:numel(saccStarts)
    i0 = max(1, saccStarts(i) - padFrames);
    i1 = min(numel(saccMask), saccStops(i) + padFrames);
    saccMask(i0:i1) = true;
end

dispersionDeg = localCenteredDispersionDeg(xPx, yPx, valid, ex.setup, ...
    opts.fixationWindowSec, opts.fixationMinValidFrac, dtSec);
fixationSpeedDegPerSec = localFixationSpeedFromPosition( ...
    xPx, yPx, valid & ~saccMask, opts.fixationSpeedSmoothFrames, dtSec, ex.setup);
fixCandidate = valid & ~saccMask & ...
    isfinite(fixationSpeedDegPerSec) & fixationSpeedDegPerSec <= opts.fixationMaxEyeSpeedDeg & ...
    isfinite(dispersionDeg) & dispersionDeg <= opts.fixationMaxDispDeg;
fixCandidateBridged = localBridgeShortFalseGaps(fixCandidate, opts.fixationBridgeGapSec, dtSec);
fixMask = localKeepRunsAtLeast(fixCandidateBridged, opts.fixationMinDurSec, dtSec);
smoothMask = valid & ~saccMask & ~fixMask;
fixSpeedEligible = valid & ~saccMask & isfinite(fixationSpeedDegPerSec) & ...
    fixationSpeedDegPerSec <= opts.fixationMaxEyeSpeedDeg;
fixDispEligible = valid & ~saccMask & isfinite(dispersionDeg) & ...
    dispersionDeg <= opts.fixationMaxDispDeg;

state = zeros(size(xPx), 'uint8');
state(fixMask) = uint8(1);
state(smoothMask) = uint8(2);
state(saccMask & valid) = uint8(3);
stateName = strings(size(state));
stateName(state == 0) = "missing";
stateName(state == 1) = "fixation";
stateName(state == 2) = "smoothPursuit";
stateName(state == 3) = "saccade";

S = table( ...
    repmat(double(trialNo), numel(sampleIdx), 1), ...
    sampleIdx, tRel(:), tAbs(:), stepIdx(:), ...
    xPx(:), yPx(:), targetX(:), targetY(:), target2X(:), target2Y(:), ...
    valid(:), eyeSpeedDegPerSec(:), fixationSpeedDegPerSec(:), dispersionDeg(:), ...
    saccMask(:), fixSpeedEligible(:), fixDispEligible(:), ...
    fixCandidate(:), fixCandidateBridged(:), ...
    fixMask(:), smoothMask(:), state(:), stateName(:), ...
    'VariableNames', {'trial','sampleIdx','tRelSec','tAbsSec','step', ...
    'xPx','yPx','targetX','targetY','target2X','target2Y', ...
    'valid','eyeSpeedDegPerSec','fixationSpeedDegPerSec','fixationDispDeg', ...
    'isSaccade','fixSpeedEligible','fixDispEligible','fixCandidate', ...
    'fixCandidateBridged', ...
    'isFixation','isSmoothPursuit','state','stateName'});

timeWindowSec = localTimeWindow(opts.timeWindowSec);
if ~isempty(timeWindowSec)
    keepMask = S.tRelSec >= timeWindowSec(1) & S.tRelSec <= timeWindowSec(2);
    S = S(keepMask, :);
end
end


function row = localSummarizeTrial(S)
if isempty(S)
    row = table(NaN, 0, 0, 0, 0, NaN, NaN, NaN, ...
        'VariableNames', {'trial','nValidSamples','nFixationSamples', ...
        'nSmoothPursuitSamples','nSaccadeSamples', ...
        'fixationFrac','smoothPursuitFrac','saccadeFrac'});
    return
end
validMask = S.valid;
nValid = sum(validMask);
fixFrac = NaN;
smoothFrac = NaN;
saccFrac = NaN;
if nValid > 0
    fixFrac = mean(S.isFixation(validMask));
    smoothFrac = mean(S.isSmoothPursuit(validMask));
    saccFrac = mean(S.isSaccade(validMask));
end
row = table( ...
    S.trial(1), ...
    nValid, ...
    sum(S.isFixation), ...
    sum(S.isSmoothPursuit), ...
    sum(S.isSaccade), ...
    fixFrac, smoothFrac, saccFrac, ...
    'VariableNames', {'trial','nValidSamples','nFixationSamples', ...
    'nSmoothPursuitSamples','nSaccadeSamples', ...
    'fixationFrac','smoothPursuitFrac','saccadeFrac'});
end


function trialVec = localNormalizeTrialVector(trialNo, nTrials)
if isempty(trialNo) || (ischar(trialNo) && strcmpi(strtrim(trialNo), 'all')) || ...
        (isstring(trialNo) && isscalar(trialNo) && strcmpi(strtrim(char(trialNo)), 'all'))
    trialVec = 1:nTrials;
    return
end
if ~isnumeric(trialNo)
    error('classifyGazeState:InvalidTrialNo', ...
        'trialNo must be numeric, [], or ''all''.');
end
trialVec = unique(double(trialNo(:)'));
trialVec = trialVec(isfinite(trialVec) & trialVec == round(trialVec) & trialVec >= 1 & trialVec <= nTrials);
if isempty(trialVec)
    error('classifyGazeState:NoValidTrials', 'No valid trial indices were selected.');
end
end


function value = localFirstScalar(value)
if isempty(value)
    value = NaN;
else
    value = double(value(1));
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


function dtSec = localResolveSampleDt(tRel, fallbackDtSec)
dtSec = fallbackDtSec;
if numel(tRel) >= 2
    d = diff(tRel(:));
    d = d(isfinite(d) & d > 0);
    if ~isempty(d)
        dtSec = median(d);
    end
end
if ~isfinite(dtSec) || dtSec <= 0
    dtSec = fallbackDtSec;
end
end


function y = localInterpShortNaNGaps(x, maxGapSamples)
y = x(:);
if isempty(y) || maxGapSamples < 1
    return
end
nanMask = ~isfinite(y);
if ~any(nanMask)
    return
end
d = diff([false; nanMask; false]);
gapStarts = find(d == 1);
gapStops = find(d == -1) - 1;
for i = 1:numel(gapStarts)
    i0 = gapStarts(i);
    i1 = gapStops(i);
    if (i1 - i0 + 1) > maxGapSamples || i0 == 1 || i1 == numel(y)
        continue
    end
    if ~isfinite(y(i0 - 1)) || ~isfinite(y(i1 + 1))
        continue
    end
    xi = [i0 - 1; i1 + 1];
    yi = [y(i0 - 1); y(i1 + 1)];
    y(i0:i1) = interp1(xi, yi, (i0:i1)', 'linear');
end
end


function y = localZeroPhaseLowpassTrace(x, validMask, dtSec, cutoffHz)
y = x(:);
if numel(y) < 5 || ~isfinite(dtSec) || dtSec <= 0 || ~isfinite(cutoffHz) || cutoffHz <= 0
    return
end
fs = 1 / dtSec;
wn = cutoffHz / (fs / 2);
if ~(wn > 0 && wn < 1)
    return
end
[b, a] = butter(2, wn, 'low');
finiteMask = validMask(:) & isfinite(y);
runs = localMaskRuns(finiteMask);
for i = 1:size(runs, 1)
    idx = runs(i,1):runs(i,2);
    if numel(idx) < max(5, 3 * max(numel(a), numel(b)))
        continue
    end
    y(idx) = filtfilt(b, a, y(idx));
end
end


function speedDegPerSec = localFixationSpeedFromPosition(xPx, yPx, validMask, smoothFrames, dtSec, setup)
speedDegPerSec = NaN(size(xPx(:)));
if isempty(speedDegPerSec)
    return
end
smoothFrames = max(1, round(double(smoothFrames)));
finiteMask = validMask(:) & isfinite(xPx(:)) & isfinite(yPx(:));
runs = localMaskRuns(finiteMask);
for i = 1:size(runs, 1)
    idx = runs(i,1):runs(i,2);
    xRun = xPx(idx);
    yRun = yPx(idx);
    if smoothFrames > 1
        xRun = movmean(xRun, smoothFrames, 'omitnan');
        yRun = movmean(yRun, smoothFrames, 'omitnan');
    end
    dxPx = [0; diff(xRun)];
    dyPx = [0; diff(yRun)];
    speedPxPerSec = hypot(dxPx, dyPx) ./ dtSec;
    speedDegPerSec(idx) = px2deg(speedPxPerSec, setup);
end
end


function dispersionDeg = localCenteredDispersionDeg(xPx, yPx, validMask, setup, windowSec, minValidFrac, dtSec)
n = numel(xPx);
dispersionDeg = NaN(n, 1);
if n == 0 || ~isfinite(windowSec) || windowSec <= 0 || ~isfinite(dtSec) || dtSec <= 0
    return
end
halfWindow = max(0, floor(round(windowSec / dtSec) / 2));
for i = 1:n
    i0 = max(1, i - halfWindow);
    i1 = min(n, i + halfWindow);
    idx = i0:i1;
    winValid = validMask(idx) & isfinite(xPx(idx)) & isfinite(yPx(idx));
    if mean(winValid) < minValidFrac || sum(winValid) < 3
        continue
    end
    xw = xPx(idx);
    yw = yPx(idx);
    xw = xw(winValid);
    yw = yw(winValid);
    rangeXPx = max(xw) - min(xw);
    rangeYPx = max(yw) - min(yw);
    % Use the larger axis spread so the 1 deg criterion acts like a
    % window-width bound rather than a diagonal-distance bound.
    dispersionDeg(i) = max(px2deg(rangeXPx, setup), px2deg(rangeYPx, setup));
end
end


function keepMask = localKeepRunsAtLeast(mask, minDurSec, dtSec)
keepMask = false(size(mask));
if isempty(mask) || ~any(mask)
    return
end
minFrames = max(1, round(minDurSec / dtSec));
runs = localMaskRuns(mask(:));
for i = 1:size(runs, 1)
    idx = runs(i,1):runs(i,2);
    if numel(idx) >= minFrames
        keepMask(idx) = true;
    end
end
end


function bridgedMask = localBridgeShortFalseGaps(mask, maxGapSec, dtSec)
bridgedMask = logical(mask(:));
if isempty(bridgedMask) || ~any(bridgedMask) || ~isfinite(maxGapSec) || maxGapSec <= 0
    return
end
maxGapFrames = max(1, round(maxGapSec / dtSec));
runs = localMaskRuns(~bridgedMask);
for i = 1:size(runs, 1)
    idx = runs(i,1):runs(i,2);
    if numel(idx) > maxGapFrames
        continue
    end
    if runs(i,1) == 1 || runs(i,2) == numel(bridgedMask)
        continue
    end
    if bridgedMask(runs(i,1) - 1) && bridgedMask(runs(i,2) + 1)
        bridgedMask(idx) = true;
    end
end
end


function runs = localMaskRuns(mask)
if isempty(mask)
    runs = zeros(0, 2);
    return
end
dm = diff([false; logical(mask(:)); false]);
starts = find(dm == 1);
stops = find(dm == -1) - 1;
runs = [starts, stops];
end


function params = localSaccadeParams(dtSec, opts)
params = struct();
params.preSaccadeWindowFrames = 3;
params.speedThreshDegPerSec = localFirstScalar(opts.speedThreshDegPerSec);
params.minAmpDeg = localFirstScalar(opts.minAmpDeg);
params.minDurSec = localFirstScalar(opts.minDurSec);
params.maxDurSec = localFirstScalar(opts.maxDurSec);
params.smoothFrames = max(1, round(localFirstScalar(opts.smoothFrames)));
if ~isfinite(dtSec) || dtSec <= 0
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
