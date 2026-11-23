function [xPx, yPx, tRel, tAbs, valid, eyeInfo] = reconstructEyePx(ex, T, useEyeTime, opts)
% Reconstruct eye position in display pixels from raw Eye.v channels.
%
% Binocular sessions default to the legacy NaN-omitting mean across eyes.
% To automatically reject a noisy eye, pass opts.eyeSelection='auto' or set
% ex.exp.CoPs.analysis.eyeSelection='auto'. Use 'best' to force selection of
% the lower-noise usable eye even when both eyes are similar.
%
% Eye-time alignment defaults to the photodiode GO pulse when Eye.t is
% available. The pulse is used as a Datapixx anchor; the saved frame-sync or
% MATLAB stimOn time gates plausible pulse times so startup transients are
% ignored. Set
% opts.eyeTimeAlignmentMode='legacyAuto' to use the older
% TrialStartDatapixx/fallback-end logic directly.

xPx = zeros(0,1); yPx = zeros(0,1); tRel = zeros(0,1); tAbs = zeros(0,1); valid = false(0,1);
eyeInfo = localEmptyEyeInfo();

if nargin < 4 || isempty(opts)
    opts = struct();
end

if ~isfield(T, 'Eye') || isempty(T.Eye) || ~isfield(T.Eye, 'v') || isempty(T.Eye.v)
    return
end

V = T.Eye.v;
if isfield(T.Eye, 'n') && T.Eye.n > 0 && T.Eye.n <= size(V,2)
    V = V(:,1:T.Eye.n);
end

nS = size(V,2);
if nS == 0
    return
end

% Apply horizontal sign rule used online.
horSign = 1;
if isfield(ex, 'setup') && isfield(ex.setup, 'horEyeSign')
    horSign = ex.setup.horEyeSign;
end
if size(V,1) > 3
    V([1,4],:) = horSign .* V([1,4],:);
else
    V(1,:) = horSign .* V(1,:);
end

fs = inferFs(ex);
tRel = ((0:nS-1)' ./ fs); % time relative to trial start
timingInfo = localEmptyTimingInfo();
if useEyeTime && isfield(T.Eye, 't') && numel(T.Eye.t) >= nS
    tt = T.Eye.t(1:nS);
    if all(isfinite(tt)) && range(tt) > 0
        tt = tt(:);
        [tRel, timingInfo] = localAlignEyeTime(ex, T, tt, opts);
    end
end

trStart = getfieldOrNaN(T, 'TrialStart'); %#ok<GFLD>
tAbs = localAbsoluteEyeTime(T, tRel, timingInfo);
if isempty(tAbs)
    tAbs = trStart + tRel;
end

% Calibration fields and dynamic drift offset (Delta) used online.
EC = ex.eyeCal;
PC = ex.fix.PCtr;

if isfield(EC, 'Delta') && ~isempty(EC.Delta) && isfield(EC.Delta, 'cnt') && ~isempty(EC.Delta(1).cnt)
    dIdx = EC.Delta(1).cnt;
else
    dIdx = 1;
end

dRX0 = safeDeltaField(EC, dIdx, 'RX0'); %EC(dIdx).RX0
dRY0 = safeDeltaField(EC, dIdx, 'RY0');
dLX0 = safeDeltaField(EC, dIdx, 'LX0');
dLY0 = safeDeltaField(EC, dIdx, 'LY0');

if size(V,1) > 3 && isfield(EC, 'LXPos') && ~isempty(EC.LXPos)
    xR = ((V(1,:) - EC.RX0 - dRX0) .* EC.RXGain + PC(1))';
    yR = ((V(2,:) - EC.RY0 - dRY0) .* EC.RYGain + PC(2))';
    xL = ((V(4,:) - EC.LX0 - dLX0) .* EC.LXGain + PC(1))';
    yL = ((V(5,:) - EC.LY0 - dLY0) .* EC.LYGain + PC(2))';

    [xPx, yPx, eyeInfo] = localCombineBinocularEyes(xR, yR, xL, yL, ex, opts);
else
    xPx = ((V(1,:) - EC.RX0 - dRX0) .* EC.RXGain + PC(1))';
    yPx = ((V(2,:) - EC.RY0 - dRY0) .* EC.RYGain + PC(2))';
    eyeInfo = localMonocularEyeInfo(xPx, yPx);
end
eyeInfo.timing = timingInfo;

valid = isfinite(xPx) & isfinite(yPx);

end

function [xPx, yPx, eyeInfo] = localCombineBinocularEyes(xR, yR, xL, yL, ex, userOpts)
xR = xR(:); yR = yR(:); xL = xL(:); yL = yL(:);
n = min([numel(xR), numel(yR), numel(xL), numel(yL)]);
xR = xR(1:n); yR = yR(1:n); xL = xL(1:n); yL = yL(1:n);

settings = localResolveEyeSettings(ex, userOpts);
qR = localEyeQuality(xR, yR, settings);
qL = localEyeQuality(xL, yL, settings);

mode = localCanonicalEyeSelection(settings.eyeSelection);
selectedEye = 'both';
modeUsed = 'mean';
reason = 'legacy_mean';

switch mode
    case 'right'
        selectedEye = 'right';
        modeUsed = 'right';
        reason = 'requested_right';
    case 'left'
        selectedEye = 'left';
        modeUsed = 'left';
        reason = 'requested_left';
    case 'best'
        [selectedEye, reason] = localSelectBestEye(qR, qL);
        modeUsed = selectedEye;
    case 'auto'
        [selectedEye, reason] = localSelectAutoEye(qR, qL, settings.eyeAutoScoreRatio);
        modeUsed = selectedEye;
    otherwise
        selectedEye = 'both';
        modeUsed = 'mean';
        reason = 'requested_mean';
end

switch selectedEye
    case 'right'
        xPx = xR;
        yPx = yR;
    case 'left'
        xPx = xL;
        yPx = yL;
    otherwise
        xPx = localMeanPair(xR, xL);
        yPx = localMeanPair(yR, yL);
        selectedEye = 'both';
        modeUsed = 'mean';
end

eyeInfo = struct( ...
    'isBinocular', true, ...
    'modeRequested', settings.eyeSelection, ...
    'modeResolved', mode, ...
    'modeUsed', modeUsed, ...
    'selectedEye', selectedEye, ...
    'reason', reason, ...
    'autoScoreRatio', settings.eyeAutoScoreRatio, ...
    'autoMinValidFrac', settings.eyeAutoMinValidFrac, ...
    'autoMinScoreSamples', settings.eyeAutoMinScoreSamples, ...
    'scoreRight', qR.score, ...
    'scoreLeft', qL.score, ...
    'validFracRight', qR.validFrac, ...
    'validFracLeft', qL.validFrac, ...
    'nScoreSamplesRight', qR.nScoreSamples, ...
    'nScoreSamplesLeft', qL.nScoreSamples, ...
    'medianStepPxRight', qR.medianStepPx, ...
    'medianStepPxLeft', qL.medianStepPx, ...
    'medianJitterPxRight', qR.medianJitterPx, ...
    'medianJitterPxLeft', qL.medianJitterPx, ...
    'p90JitterPxRight', qR.p90JitterPx, ...
    'p90JitterPxLeft', qL.p90JitterPx);
end

function eyeInfo = localMonocularEyeInfo(xPx, yPx)
settings = localDefaultEyeSettings();
q = localEyeQuality(xPx, yPx, settings);
eyeInfo = struct( ...
    'isBinocular', false, ...
    'modeRequested', 'right', ...
    'modeResolved', 'right', ...
    'modeUsed', 'right', ...
    'selectedEye', 'right', ...
    'reason', 'monocular', ...
    'autoScoreRatio', settings.eyeAutoScoreRatio, ...
    'autoMinValidFrac', settings.eyeAutoMinValidFrac, ...
    'autoMinScoreSamples', settings.eyeAutoMinScoreSamples, ...
    'scoreRight', q.score, ...
    'scoreLeft', NaN, ...
    'validFracRight', q.validFrac, ...
    'validFracLeft', NaN, ...
    'nScoreSamplesRight', q.nScoreSamples, ...
    'nScoreSamplesLeft', 0, ...
    'medianStepPxRight', q.medianStepPx, ...
    'medianStepPxLeft', NaN, ...
    'medianJitterPxRight', q.medianJitterPx, ...
    'medianJitterPxLeft', NaN, ...
    'p90JitterPxRight', q.p90JitterPx, ...
    'p90JitterPxLeft', NaN);
end

function settings = localResolveEyeSettings(ex, userOpts)
settings = localDefaultEyeSettings();

analysis = struct();
if isstruct(ex) && isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && ...
        isfield(ex.exp.CoPs, 'analysis') && isstruct(ex.exp.CoPs.analysis)
    analysis = ex.exp.CoPs.analysis;
end

settings = localApplyEyeSettings(settings, analysis);
if nargin >= 2 && isstruct(userOpts)
    settings = localApplyEyeSettings(settings, userOpts);
end
end

function mode = localResolveEyeTimeAlignmentMode(ex, userOpts)
mode = 'photodiodePulse';

analysis = localAnalysisSettings(ex);
mode = localGetTextField(analysis, ...
    {'eyeTimeAlignmentMode','eyeTimeAlignment','eyeTimeMode'}, mode);
if nargin >= 2 && isstruct(userOpts)
    mode = localGetTextField(userOpts, ...
        {'eyeTimeAlignmentMode','eyeTimeAlignment','eyeTimeMode'}, mode);
end

mode = lower(strtrim(mode));
switch mode
    case {'auto','automatic','photodiode','photodiodepulse','pd','pdpulse','gopulse','go','sync'}
        mode = 'photodiodePulse';
    case {'photodiodeonly','photodiodepulseonly','pdonly','pdpulseonly','gopulseonly','goonly','synconly'}
        mode = 'photodiodePulseOnly';
    case {'legacy','legacyauto','legacy_auto','old','oldauto','trialstartauto','datapixxauto'}
        mode = 'legacyAuto';
    case {'datapixx','datapixxstart','dp','start','trialstart'}
        mode = 'datapixxStart';
    case {'fallback','fallbackend','end','trialend','buffer'}
        mode = 'fallbackEnd';
    otherwise
        mode = 'photodiodePulse';
end
end

function [tRel, timingInfo] = localAlignEyeTime(ex, T, tt, opts)
mode = localResolveEyeTimeAlignmentMode(ex, opts);
timingInfo = localEmptyTimingInfo();
timingInfo.modeRequested = mode;

switch mode
    case {'photodiodePulse','photodiodePulseOnly'}
        [goDp, goSampleIdx, threshold, rowIdx, physicalChannel, reason] = localDetectGoPulseDatapixx(ex, T, tt, opts);
        if isfinite(goDp)
            [stimOnRel, stimOnSource, stimOnAnalogRel, stimOnMatlabRel] = localStimOnRelForGoPulse(ex, T, goDp, opts);
            if ~isfinite(stimOnRel)
                stimOnRel = 0;
            end
            tRel = (tt - goDp) + stimOnRel;
            timingInfo.modeUsed = 'photodiodePulse';
            timingInfo.fallbackReason = '';
            timingInfo.goPulseDatapixx = goDp;
            timingInfo.goPulseSampleIdx = goSampleIdx;
            timingInfo.goPulseThreshold = threshold;
            timingInfo.goPulseRowIndex = rowIdx;
            timingInfo.goPulsePhysicalChannel = physicalChannel;
            timingInfo.stimOnRelSec = stimOnRel;
            timingInfo.stimOnSource = stimOnSource;
            timingInfo.stimOnAnalogRelSec = stimOnAnalogRel;
            timingInfo.stimOnMatlabRelSec = stimOnMatlabRel;
            timingInfo.stimOnAnalogDeltaSec = stimOnAnalogRel - stimOnMatlabRel;
            return
        end
        timingInfo.fallbackReason = reason;
        if strcmp(mode, 'photodiodePulseOnly')
            tRel = (tt - tt(1));
            timingInfo.modeUsed = 'eyeTimeFirstSample';
            return
        end

        [tRel, legacyInfo] = localAlignEyeTimeLegacy(ex, T, tt, opts, 'legacyAuto');
        timingInfo = localMergeTimingInfo(timingInfo, legacyInfo);
        return

    otherwise
        [tRel, timingInfo] = localAlignEyeTimeLegacy(ex, T, tt, opts, mode);
end
end

function [tRel, timingInfo] = localAlignEyeTimeLegacy(ex, T, tt, opts, mode)
timingInfo = localEmptyTimingInfo();
timingInfo.modeRequested = mode;

trStartDatapixx = getfieldOrNaN(T, 'TrialStartDatapixx'); %#ok<GFLD>
useFallbackAlignment = strcmp(mode, 'fallbackEnd') || ...
    (strcmp(mode, 'legacyAuto') && localDatapixxTrialStartLooksBuffered(T, ex, opts));

if isfinite(trStartDatapixx) && ~useFallbackAlignment
    % Use the Datapixx trial-start strobe when available so any pretrial
    % ADC accumulation stays at negative relative time.
    tRel = tt - trStartDatapixx;
    timingInfo.modeUsed = 'datapixxStart';
else
    tRel = localFallbackEyeTimeToTrialEnd(tt, T, ex, opts);
    timingInfo.modeUsed = 'fallbackEnd';
end
end

function [stimOnRel, source, analogRel, matlabRel] = localStimOnRelForGoPulse(ex, T, goDp, opts)
matlabRel = localStimOnRelativeToTrialStart(T);
analogRel = localExplicitAnalogStimOnRel(T);
source = 'matlabStimOn';

if ~isfinite(analogRel)
    analogRel = localFrameSyncPulseRel(T);
end

if ~isfinite(analogRel)
    trStartDp = getfieldOrNaN(T, 'TrialStartDatapixx'); %#ok<GFLD>
    if isfinite(goDp) && isfinite(trStartDp)
        analogRel = goDp - trStartDp;
        maxDeltaSec = localResolveStimOnAnalogMaxDeltaSec(ex, T, opts);
        if isfinite(matlabRel) && isfinite(maxDeltaSec) && abs(analogRel - matlabRel) > maxDeltaSec
            analogRel = NaN;
        end
    end
end

if isfinite(analogRel)
    stimOnRel = analogRel;
    source = 'analogStimOn';
elseif isfinite(matlabRel)
    stimOnRel = matlabRel;
else
    stimOnRel = NaN;
    source = 'missingStimOn';
end
end


function stimOnRel = localExplicitAnalogStimOnRel(T)
stimOnRel = NaN;
if ~isstruct(T)
    return
end

if isfield(T, 'stimOnAnalogRel') && isnumeric(T.stimOnAnalogRel) && ~isempty(T.stimOnAnalogRel)
    stimOnRel = double(T.stimOnAnalogRel(1));
    if isfinite(stimOnRel)
        return
    end
end
if isfield(T, 'times') && isstruct(T.times)
    relNames = {'stimOnAnalogRel','stimOnVisualRel','stimOnPulseRel'};
    for k = 1:numel(relNames)
        name = relNames{k};
        if isfield(T.times, name) && isnumeric(T.times.(name)) && ~isempty(T.times.(name))
            stimOnRel = double(T.times.(name)(1));
            if isfinite(stimOnRel)
                return
            end
        end
    end
end

stimOnAbs = NaN;
if isfield(T, 'stimOnAnalog') && isnumeric(T.stimOnAnalog) && ~isempty(T.stimOnAnalog)
    stimOnAbs = double(T.stimOnAnalog(1));
elseif isfield(T, 'times') && isstruct(T.times)
    absNames = {'stimOnAnalog','stimOnVisual','stimOnPulse'};
    for k = 1:numel(absNames)
        name = absNames{k};
        if isfield(T.times, name) && isnumeric(T.times.(name)) && ~isempty(T.times.(name))
            stimOnAbs = double(T.times.(name)(1));
            if isfinite(stimOnAbs)
                break
            end
        end
    end
end

trStart = getfieldOrNaN(T, 'TrialStart'); %#ok<GFLD>
if isfinite(stimOnAbs) && isfinite(trStart)
    stimOnRel = stimOnAbs - trStart;
end
end


function maxDeltaSec = localResolveStimOnAnalogMaxDeltaSec(ex, T, opts)
maxDeltaSec = 0.25;
analysis = localAnalysisSettings(ex);
maxDeltaSec = localGetScalarField(analysis, ...
    {'stimOnAnalogMaxDeltaSec','targetStimOnAnalogMaxDeltaSec','goPulseStimOnMaxDeltaSec'}, maxDeltaSec);
if isstruct(T)
    maxDeltaSec = localGetScalarField(T, ...
        {'stimOnAnalogMaxDeltaSec','targetStimOnAnalogMaxDeltaSec','goPulseStimOnMaxDeltaSec'}, maxDeltaSec);
end
if nargin >= 4 && isstruct(opts)
    maxDeltaSec = localGetScalarField(opts, ...
        {'stimOnAnalogMaxDeltaSec','targetStimOnAnalogMaxDeltaSec','goPulseStimOnMaxDeltaSec'}, maxDeltaSec);
end
if ~isfinite(maxDeltaSec) || maxDeltaSec <= 0
    maxDeltaSec = 0.25;
end
end


function [goDp, goSampleIdx, threshold, rowIdx, physicalChannel, reason] = localDetectGoPulseDatapixx(ex, T, tt, opts)
goDp = NaN;
goSampleIdx = NaN;
threshold = NaN;
rowIdx = NaN;
physicalChannel = localResolveGoPulsePhysicalChannel(ex, opts);
reason = '';

if ~isfield(T, 'Eye') || ~isfield(T.Eye, 'v') || isempty(T.Eye.v) || ...
        ~isfield(T.Eye, 't') || isempty(T.Eye.t)
    reason = 'missing_eye_data';
    return
end

Vraw = T.Eye.v;
nS = min([size(Vraw,2), numel(tt), numel(T.Eye.t)]);
if isfield(T.Eye, 'n') && T.Eye.n > 0
    nS = min(nS, T.Eye.n);
end
if nS < 2
    reason = 'too_few_samples';
    return
end

rowIdxOverride = localResolveGoPulseRowIndex(opts);
if isfinite(rowIdxOverride)
    rowIdx = rowIdxOverride;
else
    scheduledChannels = localResolveScheduledAdcChannels(ex, T);
    if isempty(scheduledChannels)
        reason = 'missing_scheduled_channels';
        return
    end
    rowIdx = find(scheduledChannels == physicalChannel, 1, 'first');
    if isempty(rowIdx)
        rowIdx = NaN;
    end
end

if ~isfinite(rowIdx) || rowIdx < 1 || rowIdx > size(Vraw,1)
    reason = 'sync_channel_not_recorded';
    return
end

sig = Vraw(rowIdx, 1:nS);
t = tt(1:nS);
valid = isfinite(sig(:)) & isfinite(t(:));
if nnz(valid) < 2
    reason = 'no_finite_sync_samples';
    return
end

validIdx = find(valid);
sig = sig(valid);
t = t(valid);

threshold = localResolveGoPulseThreshold(ex, T, opts, sig);
polarity = localResolveGoPulsePolarity(opts);
switch polarity
    case 'rising'
        logicSig = sig >= threshold;
    case 'falling'
        logicSig = sig <= threshold;
    otherwise
        logicSig = sig >= threshold;
end
edgeIdx = find(diff(logicSig) == 1) + 1;
if isempty(edgeIdx)
    reason = 'no_sync_edges';
    return
end

minPulseWidthSec = localResolveGoPulseMinPulseWidthSec(ex, opts);
if minPulseWidthSec > 0
    keep = true(size(edgeIdx));
    lastT = t(edgeIdx(1));
    for k = 2:numel(edgeIdx)
        if (t(edgeIdx(k)) - lastT) < minPulseWidthSec
            keep(k) = false;
        else
            lastT = t(edgeIdx(k));
        end
    end
    edgeIdx = edgeIdx(keep);
end
if isempty(edgeIdx)
    reason = 'no_sync_edges_after_filter';
    return
end

[edgeIdx, reason] = localFilterEdgesByPlausiblePulseTime(ex, T, tt, opts, validIdx, edgeIdx);
if isempty(edgeIdx)
    if isempty(reason)
        reason = 'no_sync_edges_in_plausible_window';
    end
    return
end

edgeChoice = localResolveGoPulseEdgeIndex(opts);
if isfinite(edgeChoice)
    edgeChoice = max(1, min(numel(edgeIdx), edgeChoice));
else
    expectedGoDp = localExpectedGoPulseDatapixx(ex, T, tt, opts);
    if isfinite(expectedGoDp)
        [~, edgeChoice] = min(abs(t(edgeIdx) - expectedGoDp));
    else
        edgeChoice = 1;
    end
end
goSampleIdx = validIdx(edgeIdx(edgeChoice));
goDp = t(edgeIdx(edgeChoice));
end

function expectedGoDp = localExpectedGoPulseDatapixx(ex, T, tt, opts)
expectedGoDp = NaN;
stimOnRel = localStimOnRelativeToTrialStart(T);
if ~isfinite(stimOnRel)
    return
end

[legacyRel, ~] = localAlignEyeTimeLegacy(ex, T, tt, opts, 'legacyAuto');
if isempty(legacyRel) || numel(legacyRel) ~= numel(tt)
    return
end

good = isfinite(legacyRel) & isfinite(tt);
if ~any(good)
    return
end

idxGood = find(good);
[~, iBest] = min(abs(legacyRel(good) - stimOnRel));
expectedGoDp = tt(idxGood(iBest));
end

function [edgeIdx, reason] = localFilterEdgesByPlausiblePulseTime(ex, T, tt, opts, validIdx, edgeIdx)
reason = '';
expectedRel = localExpectedPhotodiodePulseRel(T);
windowSec = localResolvePhotodiodePulseWindowSec(ex, T, opts);
if ~isfinite(expectedRel) || ~isfinite(windowSec)
    return
end
if windowSec <= 0
    edgeIdx = [];
    reason = 'invalid_photodiode_pulse_window';
    return
end

[legacyRel, ~] = localAlignEyeTimeLegacy(ex, T, tt, opts, 'legacyAuto');
if isempty(legacyRel) || numel(legacyRel) ~= numel(tt)
    return
end

sampleIdx = validIdx(edgeIdx);
keep = sampleIdx >= 1 & sampleIdx <= numel(legacyRel);
edgeIdx = edgeIdx(keep);
sampleIdx = sampleIdx(keep);
if isempty(edgeIdx)
    reason = 'no_sync_edges_with_valid_samples';
    return
end

edgeRelLegacy = legacyRel(sampleIdx);
edgeRelBuffer = tt(sampleIdx) - tt(1);
keep = (isfinite(edgeRelLegacy) & abs(edgeRelLegacy - expectedRel) <= windowSec) | ...
    (isfinite(edgeRelBuffer) & abs(edgeRelBuffer - expectedRel) <= windowSec);
edgeIdx = edgeIdx(keep);
if isempty(edgeIdx)
    reason = 'no_sync_edges_in_plausible_window';
end
end

function expectedRel = localExpectedPhotodiodePulseRel(T)
expectedRel = NaN;
frameRel = localFrameSyncPulseRel(T);
if isfinite(frameRel)
    expectedRel = frameRel;
    return
end
expectedRel = localStimOnRelativeToTrialStart(T);
end

function frameRel = localFrameSyncPulseRel(T)
frameRel = NaN;
if isstruct(T) && isfield(T, 'frameSyncPulse') && isfield(T, 'flip_info') && ...
        ~isempty(T.frameSyncPulse) && ~isempty(T.flip_info)
    syncMask = logical(T.frameSyncPulse(:));
    flipInfo = double(T.flip_info);
    n = min(numel(syncMask), size(flipInfo, 1));
    if n > 0
        syncMask = syncMask(1:n);
        idx = find(syncMask, 1, 'first');
        trStart = getfieldOrNaN(T, 'TrialStart'); %#ok<GFLD>
        if ~isempty(idx) && isfinite(trStart) && size(flipInfo, 2) >= 1
            frameRel = flipInfo(idx, 1) - trStart;
            if isfinite(frameRel)
                return
            end
        end
    end
end
end

function windowSec = localResolvePhotodiodePulseWindowSec(ex, T, opts)
windowSec = 0.5;
analysis = localAnalysisSettings(ex);
windowSec = localGetScalarField(analysis, ...
    {'eyeTimePhotodiodeWindowSec','photodiodePulseWindowSec','photodiodeWindowSec', ...
    'eyeTimeGoPulseWindowSec','goPulseWindowSec','syncPulseWindowSec'}, windowSec);
if isstruct(T)
    windowSec = localGetScalarField(T, ...
        {'eyeTimePhotodiodeWindowSec','photodiodePulseWindowSec','photodiodeWindowSec', ...
        'eyeTimeGoPulseWindowSec','goPulseWindowSec','syncPulseWindowSec'}, windowSec);
end
if nargin >= 3 && isstruct(opts)
    windowSec = localGetScalarField(opts, ...
        {'eyeTimePhotodiodeWindowSec','photodiodePulseWindowSec','photodiodeWindowSec', ...
        'eyeTimeGoPulseWindowSec','goPulseWindowSec','syncPulseWindowSec'}, windowSec);
end
end

function tAbs = localAbsoluteEyeTime(T, tRel, timingInfo)
tAbs = [];
if ~isstruct(timingInfo) || ~isfield(timingInfo, 'modeUsed')
    return
end

if any(strcmp(timingInfo.modeUsed, {'photodiodePulse','goPulse'})) && isfinite(timingInfo.goPulseDatapixx)
    trStart = getfieldOrNaN(T, 'TrialStart'); %#ok<GFLD>
    if isfinite(trStart)
        tAbs = trStart + tRel;
        return
    end
    stimOnAbs = localExplicitAnalogStimOnAbs(T);
    if ~isfinite(stimOnAbs)
        stimOnAbs = localStimOnAbs(T);
    end
    if isfinite(stimOnAbs) && isfinite(timingInfo.stimOnRelSec)
        tAbs = stimOnAbs + (tRel - timingInfo.stimOnRelSec);
        return
    end
end

trStart = getfieldOrNaN(T, 'TrialStart'); %#ok<GFLD>
if isfinite(trStart)
    tAbs = trStart + tRel;
end
end

function stimOnRel = localStimOnRelativeToTrialStart(T)
stimOnAbs = localStimOnAbs(T);
trStart = getfieldOrNaN(T, 'TrialStart'); %#ok<GFLD>
if isfinite(stimOnAbs) && isfinite(trStart)
    stimOnRel = stimOnAbs - trStart;
else
    stimOnRel = NaN;
end
end

function stimOnAbs = localExplicitAnalogStimOnAbs(T)
stimOnAbs = NaN;
if ~isstruct(T)
    return
end
if isfield(T, 'stimOnAnalog') && isnumeric(T.stimOnAnalog) && ~isempty(T.stimOnAnalog)
    stimOnAbs = double(T.stimOnAnalog(1));
    if isfinite(stimOnAbs)
        return
    end
end
if isfield(T, 'times') && isstruct(T.times)
    absNames = {'stimOnAnalog','stimOnVisual','stimOnPulse'};
    for k = 1:numel(absNames)
        name = absNames{k};
        if isfield(T.times, name) && isnumeric(T.times.(name)) && ~isempty(T.times.(name))
            stimOnAbs = double(T.times.(name)(1));
            if isfinite(stimOnAbs)
                return
            end
        end
    end
end
end

function stimOnAbs = localStimOnAbs(T)
stimOnAbs = NaN;
if isfield(T, 'times') && isfield(T.times, 'stimOn') && ~isempty(T.times.stimOn)
    candidate = double(T.times.stimOn(1));
    if isfinite(candidate)
        stimOnAbs = candidate;
    end
end
end

function scheduledChannels = localResolveScheduledAdcChannels(ex, T)
scheduledChannels = [];
if isstruct(T) && isfield(T, 'scheduledChannels') && isnumeric(T.scheduledChannels)
    scheduledChannels = double(T.scheduledChannels(:)');
elseif isstruct(T) && isfield(T, 'adcChannels') && isnumeric(T.adcChannels)
    scheduledChannels = double(T.adcChannels(:)');
elseif isstruct(ex) && isfield(ex, 'setup') && isfield(ex.setup, 'adc') && ...
        isfield(ex.setup.adc, 'Channels') && isnumeric(ex.setup.adc.Channels)
    scheduledChannels = double(ex.setup.adc.Channels(:)');
end
end

function physicalChannel = localResolveGoPulsePhysicalChannel(ex, opts)
physicalChannel = 6;
analysis = localAnalysisSettings(ex);
physicalChannel = localGetScalarField(analysis, ...
    {'eyeTimePhotodiodePhysicalChannel','photodiodePulsePhysicalChannel','photodiodePhysicalChannel', ...
    'eyeTimeGoPulsePhysicalChannel','goPulsePhysicalChannel','syncPhysicalChannel'}, physicalChannel);
if nargin >= 2 && isstruct(opts)
    physicalChannel = localGetScalarField(opts, ...
        {'eyeTimePhotodiodePhysicalChannel','photodiodePulsePhysicalChannel','photodiodePhysicalChannel', ...
        'eyeTimeGoPulsePhysicalChannel','goPulsePhysicalChannel','syncPhysicalChannel'}, physicalChannel);
end
physicalChannel = round(double(physicalChannel));
end

function rowIdx = localResolveGoPulseRowIndex(opts)
rowIdx = NaN;
if isstruct(opts)
    rowIdx = localGetScalarField(opts, ...
        {'eyeTimePhotodiodeRowIndex','photodiodePulseRowIndex','photodiodeRowIndex', ...
        'eyeTimeGoPulseRowIndex','goPulseRowIndex','syncRowIndex'}, ...
        rowIdx);
end
if isfinite(rowIdx)
    rowIdx = round(double(rowIdx));
end
end

function threshold = localResolveGoPulseThreshold(ex, T, opts, sig)
threshold = 0.3;
analysis = localAnalysisSettings(ex);
threshold = localGetScalarField(analysis, ...
    {'eyeTimePhotodiodeThresholdV','photodiodePulseThresholdV','photodiodeThresholdV', ...
    'eyeTimeGoPulseThreshold','goPulseThreshold','syncThreshold'}, threshold);
if isstruct(T)
    threshold = localGetScalarField(T, ...
        {'eyeTimePhotodiodeThresholdV','photodiodePulseThresholdV','photodiodeThresholdV', ...
        'eyeTimeGoPulseThreshold','goPulseThreshold','syncThreshold'}, threshold);
end
if nargin >= 3 && isstruct(opts)
    threshold = localGetScalarField(opts, ...
        {'eyeTimePhotodiodeThresholdV','photodiodePulseThresholdV','photodiodeThresholdV', ...
        'eyeTimeGoPulseThreshold','goPulseThreshold','syncThreshold'}, threshold);
end
if ~isfinite(threshold)
    lo = localPercentileFinite(sig, 10);
    hi = localPercentileFinite(sig, 90);
    if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
        finiteSig = sig(isfinite(sig));
        if isempty(finiteSig)
            threshold = NaN;
            return
        end
        lo = min(finiteSig);
        hi = max(finiteSig);
    end
    threshold = (lo + hi) ./ 2;
end
end

function polarity = localResolveGoPulsePolarity(opts)
polarity = 'rising';
if isstruct(opts)
    polarity = localGetTextField(opts, ...
        {'eyeTimePhotodiodePolarity','photodiodePulsePolarity','photodiodePolarity', ...
        'eyeTimeGoPulsePolarity','goPulsePolarity','syncPolarity'}, ...
        polarity);
end
polarity = lower(strtrim(polarity));
if ~ismember(polarity, {'rising','falling'})
    polarity = 'rising';
end
end

function minPulseWidthSec = localResolveGoPulseMinPulseWidthSec(ex, opts)
minPulseWidthSec = 0.001;
analysis = localAnalysisSettings(ex);
minPulseWidthSec = localGetScalarField(analysis, ...
    {'eyeTimePhotodiodeMinPulseWidthSec','photodiodePulseMinPulseWidthSec','photodiodeMinPulseWidthSec', ...
    'eyeTimeGoPulseMinPulseWidthSec','goPulseMinPulseWidthSec','syncMinPulseWidthSec'}, minPulseWidthSec);
if nargin >= 2 && isstruct(opts)
    minPulseWidthSec = localGetScalarField(opts, ...
        {'eyeTimePhotodiodeMinPulseWidthSec','photodiodePulseMinPulseWidthSec','photodiodeMinPulseWidthSec', ...
        'eyeTimeGoPulseMinPulseWidthSec','goPulseMinPulseWidthSec','syncMinPulseWidthSec'}, minPulseWidthSec);
end
if ~isfinite(minPulseWidthSec) || minPulseWidthSec < 0
    minPulseWidthSec = 0.001;
end
end

function edgeIndex = localResolveGoPulseEdgeIndex(opts)
edgeIndex = NaN;
if isstruct(opts)
    edgeIndex = localGetScalarField(opts, ...
        {'eyeTimePhotodiodeEdgeIndex','photodiodePulseEdgeIndex','photodiodeEdgeIndex', ...
        'eyeTimeGoPulseEdgeIndex','goPulseEdgeIndex','syncEdgeIndex'}, ...
        edgeIndex);
end
if isfinite(edgeIndex)
    if edgeIndex < 1
        edgeIndex = 1;
    end
    edgeIndex = round(double(edgeIndex));
end
end

function timingInfo = localMergeTimingInfo(goInfo, fallbackInfo)
timingInfo = fallbackInfo;
timingInfo.modeRequested = goInfo.modeRequested;
timingInfo.goPulseDatapixx = goInfo.goPulseDatapixx;
timingInfo.goPulseSampleIdx = goInfo.goPulseSampleIdx;
timingInfo.goPulseThreshold = goInfo.goPulseThreshold;
timingInfo.goPulseRowIndex = goInfo.goPulseRowIndex;
timingInfo.goPulsePhysicalChannel = goInfo.goPulsePhysicalChannel;
timingInfo.stimOnRelSec = goInfo.stimOnRelSec;
timingInfo.stimOnSource = goInfo.stimOnSource;
timingInfo.stimOnAnalogRelSec = goInfo.stimOnAnalogRelSec;
timingInfo.stimOnMatlabRelSec = goInfo.stimOnMatlabRelSec;
timingInfo.stimOnAnalogDeltaSec = goInfo.stimOnAnalogDeltaSec;
timingInfo.fallbackReason = goInfo.fallbackReason;
end

function timingInfo = localEmptyTimingInfo()
timingInfo = struct( ...
    'modeRequested', '', ...
    'modeUsed', 'sampleIndex', ...
    'fallbackReason', '', ...
    'goPulseDatapixx', NaN, ...
    'goPulseSampleIdx', NaN, ...
    'goPulseThreshold', NaN, ...
    'goPulseRowIndex', NaN, ...
    'goPulsePhysicalChannel', NaN, ...
    'stimOnRelSec', NaN, ...
    'stimOnSource', '', ...
    'stimOnAnalogRelSec', NaN, ...
    'stimOnMatlabRelSec', NaN, ...
    'stimOnAnalogDeltaSec', NaN);
end

function tf = localDatapixxTrialStartLooksBuffered(T, ex, userOpts)
tf = false;

ptbTrialDurSec = getfieldOrNaN(T, 'TrialEnd') - getfieldOrNaN(T, 'TrialStart'); %#ok<GFLD>
dpTrialDurSec = getfieldOrNaN(T, 'TrialEndDatapixx') - getfieldOrNaN(T, 'TrialStartDatapixx'); %#ok<GFLD>
maxExcessSec = localResolveEyeTimeDatapixxMaxDurExcessSec(ex, userOpts);

if isfinite(ptbTrialDurSec) && isfinite(dpTrialDurSec) && isfinite(maxExcessSec)
    tf = (dpTrialDurSec - ptbTrialDurSec) > maxExcessSec;
end
end

function tRel = localFallbackEyeTimeToTrialEnd(tt, T, ex, userOpts)
% Fallback for sessions where eye acquisition started before TrialStart:
% estimate the pretrial lead from excess eye duration relative to PTB trial
% duration, leaving a configurable post-trial tail.
ptbTrialDurSec = getfieldOrNaN(T, 'TrialEnd') - getfieldOrNaN(T, 'TrialStart'); %#ok<GFLD>
eyeDurSec = tt(end) - tt(1);
postTrialTailSec = localResolveEyeTimeFallbackPostTrialTailSec(ex, userOpts);
pretrialLeadSec = (eyeDurSec - ptbTrialDurSec) - postTrialTailSec;
if ~isfinite(pretrialLeadSec)
    pretrialLeadSec = 0;
end
pretrialLeadSec = max(0, pretrialLeadSec);
tRel = (tt - tt(1)) - pretrialLeadSec;
end

function postTrialTailSec = localResolveEyeTimeFallbackPostTrialTailSec(ex, userOpts)
postTrialTailSec = 0.200;

analysis = localAnalysisSettings(ex);

postTrialTailSec = localGetScalarField(analysis, ...
    {'eyeTimeFallbackPostTrialTailSec','eyeTimeFallbackTailSec','fallbackPostTrialTailSec'}, ...
    postTrialTailSec);
if nargin >= 2 && isstruct(userOpts)
    postTrialTailSec = localGetScalarField(userOpts, ...
        {'eyeTimeFallbackPostTrialTailSec','eyeTimeFallbackTailSec','fallbackPostTrialTailSec'}, ...
        postTrialTailSec);
end
if ~isfinite(postTrialTailSec)
    postTrialTailSec = 0.200;
end
end

function maxExcessSec = localResolveEyeTimeDatapixxMaxDurExcessSec(ex, userOpts)
maxExcessSec = 0.500;

analysis = localAnalysisSettings(ex);
maxExcessSec = localGetScalarField(analysis, ...
    {'eyeTimeDatapixxMaxDurExcessSec','eyeTimeMaxDatapixxDurExcessSec','eyeTimeDatapixxDurToleranceSec'}, ...
    maxExcessSec);
if nargin >= 2 && isstruct(userOpts)
    maxExcessSec = localGetScalarField(userOpts, ...
        {'eyeTimeDatapixxMaxDurExcessSec','eyeTimeMaxDatapixxDurExcessSec','eyeTimeDatapixxDurToleranceSec'}, ...
        maxExcessSec);
end
if ~isfinite(maxExcessSec) || maxExcessSec < 0
    maxExcessSec = 0.500;
end
end

function analysis = localAnalysisSettings(ex)
analysis = struct();
if isstruct(ex) && isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && ...
        isfield(ex.exp.CoPs, 'analysis') && isstruct(ex.exp.CoPs.analysis)
    analysis = ex.exp.CoPs.analysis;
end
end

function settings = localDefaultEyeSettings()
settings = struct( ...
    'eyeSelection', 'mean', ...
    'eyeAutoScoreRatio', 1.5, ...
    'eyeAutoMinValidFrac', 0.25, ...
    'eyeAutoMinScoreSamples', 20);
end

function settings = localApplyEyeSettings(settings, source)
if ~isstruct(source)
    return
end

if isfield(source, 'eyeSelection')
    settings.eyeSelection = localFirstText(source.eyeSelection, settings.eyeSelection);
elseif isfield(source, 'eyeSelectionMode')
    settings.eyeSelection = localFirstText(source.eyeSelectionMode, settings.eyeSelection);
elseif isfield(source, 'binocularEyeSelection')
    settings.eyeSelection = localFirstText(source.binocularEyeSelection, settings.eyeSelection);
end

settings.eyeAutoScoreRatio = localGetScalarField(source, ...
    {'eyeAutoScoreRatio','eyeSelectionScoreRatio','binocularEyeScoreRatio'}, ...
    settings.eyeAutoScoreRatio);
settings.eyeAutoMinValidFrac = localGetScalarField(source, ...
    {'eyeAutoMinValidFrac','eyeSelectionMinValidFrac','binocularEyeMinValidFrac'}, ...
    settings.eyeAutoMinValidFrac);
settings.eyeAutoMinScoreSamples = localGetScalarField(source, ...
    {'eyeAutoMinScoreSamples','eyeSelectionMinScoreSamples','binocularEyeMinScoreSamples'}, ...
    settings.eyeAutoMinScoreSamples);

if ~isfinite(settings.eyeAutoScoreRatio) || settings.eyeAutoScoreRatio < 1
    settings.eyeAutoScoreRatio = 1.5;
end
if ~isfinite(settings.eyeAutoMinValidFrac) || settings.eyeAutoMinValidFrac < 0 || settings.eyeAutoMinValidFrac > 1
    settings.eyeAutoMinValidFrac = 0.25;
end
if ~isfinite(settings.eyeAutoMinScoreSamples) || settings.eyeAutoMinScoreSamples < 1
    settings.eyeAutoMinScoreSamples = 20;
end
settings.eyeAutoMinScoreSamples = round(settings.eyeAutoMinScoreSamples);
end

function mode = localCanonicalEyeSelection(value)
mode = lower(strtrim(localFirstText(value, 'mean')));
switch mode
    case {'avg','average','both','binocular'}
        mode = 'mean';
    case {'r','right','right_eye','reye'}
        mode = 'right';
    case {'l','left','left_eye','leye'}
        mode = 'left';
    case {'auto','automatic','best_if_noisy'}
        mode = 'auto';
    case {'best','cleanest','less_noisy','least_noisy'}
        mode = 'best';
    otherwise
        mode = 'mean';
end
end

function [selectedEye, reason] = localSelectAutoEye(qR, qL, scoreRatio)
selectedEye = 'both';
reason = 'auto_similar_scores';

if qR.usable && ~qL.usable
    selectedEye = 'right';
    reason = 'auto_left_unusable';
    return
elseif qL.usable && ~qR.usable
    selectedEye = 'left';
    reason = 'auto_right_unusable';
    return
elseif ~qR.usable && ~qL.usable
    reason = 'auto_both_unusable_mean';
    return
end

if qR.score <= qL.score ./ scoreRatio
    selectedEye = 'right';
    reason = 'auto_right_cleaner';
elseif qL.score <= qR.score ./ scoreRatio
    selectedEye = 'left';
    reason = 'auto_left_cleaner';
end
end

function [selectedEye, reason] = localSelectBestEye(qR, qL)
selectedEye = 'both';
reason = 'best_tie_or_unusable';

if qR.usable && ~qL.usable
    selectedEye = 'right';
    reason = 'best_left_unusable';
elseif qL.usable && ~qR.usable
    selectedEye = 'left';
    reason = 'best_right_unusable';
elseif qR.usable && qL.usable
    if qR.score < qL.score
        selectedEye = 'right';
        reason = 'best_right_cleaner';
    elseif qL.score < qR.score
        selectedEye = 'left';
        reason = 'best_left_cleaner';
    end
end
end

function q = localEyeQuality(xPx, yPx, settings)
xPx = xPx(:);
yPx = yPx(:);
n = min(numel(xPx), numel(yPx));
xPx = xPx(1:n);
yPx = yPx(1:n);

valid = isfinite(xPx) & isfinite(yPx);
validFrac = mean(double(valid));

stepGood = valid(1:end-1) & valid(2:end);
stepPx = hypot(diff(xPx), diff(yPx));
stepPx = stepPx(stepGood);

tripletGood = valid(1:end-2) & valid(2:end-1) & valid(3:end);
jitterPx = hypot(diff(xPx, 2), diff(yPx, 2));
jitterPx = jitterPx(tripletGood);

medianStepPx = localMedianFinite(stepPx);
medianJitterPx = localMedianFinite(jitterPx);
p90JitterPx = localPercentileFinite(jitterPx, 90);
nScoreSamples = numel(jitterPx);

usable = validFrac >= settings.eyeAutoMinValidFrac && nScoreSamples >= settings.eyeAutoMinScoreSamples && ...
    isfinite(medianJitterPx) && isfinite(p90JitterPx);
if usable
    score = (medianJitterPx + 0.25 .* p90JitterPx) ./ max(validFrac, 0.01);
else
    score = Inf;
end

q = struct( ...
    'score', score, ...
    'usable', usable, ...
    'validFrac', validFrac, ...
    'nScoreSamples', nScoreSamples, ...
    'medianStepPx', medianStepPx, ...
    'medianJitterPx', medianJitterPx, ...
    'p90JitterPx', p90JitterPx);
end

function m = localMeanPair(a, b)
a = a(:);
b = b(:);
n = min(numel(a), numel(b));
a = a(1:n);
b = b(1:n);

m = NaN(n, 1);
fa = isfinite(a);
fb = isfinite(b);
both = fa & fb;
m(both) = (a(both) + b(both)) ./ 2;
m(fa & ~fb) = a(fa & ~fb);
m(fb & ~fa) = b(fb & ~fa);
end

function value = localGetScalarField(S, names, defaultValue)
value = defaultValue;
for k = 1:numel(names)
    name = names{k};
    if isfield(S, name) && isnumeric(S.(name)) && ~isempty(S.(name))
        candidate = double(S.(name)(1));
        if isfinite(candidate)
            value = candidate;
            return
        end
    end
end
end

function text = localGetTextField(S, names, defaultValue)
text = defaultValue;
if ~isstruct(S)
    return
end
for k = 1:numel(names)
    name = names{k};
    if isfield(S, name)
        candidate = localFirstText(S.(name), '');
        if ~isempty(candidate)
            text = candidate;
            return
        end
    end
end
end

function text = localFirstText(value, defaultValue)
text = defaultValue;
if ischar(value)
    if ~isempty(value)
        text = value;
    end
elseif isa(value, 'string')
    if ~isempty(value) && strlength(value(1)) > 0
        text = char(value(1));
    end
elseif iscell(value) && ~isempty(value)
    text = localFirstText(value{1}, defaultValue);
end
end

function m = localMedianFinite(x)
x = x(isfinite(x));
if isempty(x)
    m = NaN;
else
    m = median(x);
end
end

function p = localPercentileFinite(x, percentile)
x = sort(x(isfinite(x)));
if isempty(x)
    p = NaN;
    return
end

idx = 1 + (numel(x) - 1) .* percentile ./ 100;
lo = floor(idx);
hi = ceil(idx);
if lo == hi
    p = x(lo);
else
    frac = idx - lo;
    p = x(lo) .* (1 - frac) + x(hi) .* frac;
end
end

function eyeInfo = localEmptyEyeInfo()
eyeInfo = struct( ...
    'isBinocular', false, ...
    'modeRequested', '', ...
    'modeResolved', '', ...
    'modeUsed', '', ...
    'selectedEye', '', ...
    'reason', 'no_eye_data', ...
    'autoScoreRatio', NaN, ...
    'autoMinValidFrac', NaN, ...
    'autoMinScoreSamples', NaN, ...
    'scoreRight', NaN, ...
    'scoreLeft', NaN, ...
    'validFracRight', NaN, ...
    'validFracLeft', NaN, ...
    'nScoreSamplesRight', 0, ...
    'nScoreSamplesLeft', 0, ...
    'medianStepPxRight', NaN, ...
    'medianStepPxLeft', NaN, ...
    'medianJitterPxRight', NaN, ...
    'medianJitterPxLeft', NaN, ...
    'p90JitterPxRight', NaN, ...
    'p90JitterPxLeft', NaN);
end
