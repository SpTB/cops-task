function stepIdx = computeStepIndices(ex, T, tRel)
% Compute displayed step index per relative-time sample for CoPs trials.
%
% CoPsx displays step 1 before GO/PREGO, then advances current_step to 2 on
% the first GO drawing pass. Offline analysis therefore treats the GO-period
% target clock as starting from step 2 by default. Set
% ex.exp.CoPs.analysis.firstGoStep = 1 to recover the legacy reconstruction.
% ex.exp.CoPs.analysis.stepClockOffsetSec is signed: negative values advance
% the reconstructed target-step clock, positive values delay it.
%
% By default, the GO-period target clock is anchored to the photodiode
% stimOn pulse when one can be resolved from saved fields or the recorded
% sync channel. Set ex.exp.CoPs.analysis.targetStimOnMode = 'matlab' to force
% the saved T.times.stimOn timestamp.
%
% New trials can store T.frameStep with T.flip_info. When available, that
% frame log is used as the actual displayed target clock. Set
% ex.exp.CoPs.analysis.targetStepTimingMode = 'ideal' to force the
% analog/nominal fallback clock.

nS = numel(tRel);
stepIdx = NaN(nS,1);
if nS == 0
    return
end

[waitSecs, ~] = resolveCoPsWaitSecs(ex, NaN);
if ~isfinite(waitSecs) || waitSecs <= 0
    waitSecs = median(diff(tRel), 'omitnan') * 20;
    if ~isfinite(waitSecs) || waitSecs <= 0
        waitSecs = 0.1;
    end
end

nsteps = getfieldOrNaN(T, 'nsteps'); %#ok<GFLD>
if ~isfinite(nsteps) || nsteps < 1
    if isfield(T, 'targetPositions')
        nsteps = numel(T.targetPositions);
    else
        nsteps = 1;
    end
end
if isfield(T, 'targetPositions')
    nsteps = min(nsteps, numel(T.targetPositions));
end

tRel = tRel(:);
frameStepIdx = localFrameLoggedStepIndices(ex, T, tRel, nsteps);
if ~isempty(frameStepIdx)
    stepIdx = frameStepIdx;
    return
end

stimOnRel = localResolveTargetStimOnRel(ex, T, tRel);

firstGoStep = localResolveFirstGoStep(ex, T, nsteps);
stepClockOffsetSec = localResolveStepClockOffsetSec(ex, T);

stepIdx(:) = 1;
goClockMask = tRel >= (stimOnRel + stepClockOffsetSec);
stepIdx(goClockMask) = floor((tRel(goClockMask) - stimOnRel - stepClockOffsetSec) ./ waitSecs + 1e-9) + firstGoStep;
stepIdx(~isfinite(stepIdx)) = 1;
stepIdx = max(1, min(nsteps, stepIdx));
end


function stepIdx = localFrameLoggedStepIndices(ex, T, tRel, nsteps)
stepIdx = [];
if ~localUseFrameStepTiming(ex, T)
    return
end
if ~isstruct(T) || ~isfield(T, 'flip_info') || isempty(T.flip_info) || ...
        ~isfield(T, 'frameStep') || isempty(T.frameStep)
    return
end
trStart = getfieldOrNaN(T, 'TrialStart'); %#ok<GFLD>
if ~isfinite(trStart)
    return
end

flipInfo = double(T.flip_info);
if size(flipInfo, 2) < 1
    return
end
frameAbs = flipInfo(:, 1);
frameStep = double(T.frameStep(:));
n = min(numel(frameAbs), numel(frameStep));
if n < 1
    return
end

frameRel = frameAbs(1:n) - trStart;
frameStep = frameStep(1:n);
valid = isfinite(frameRel) & isfinite(frameStep) & frameStep >= 1;
if ~any(valid)
    return
end

frameRel = frameRel(valid);
frameStep = frameStep(valid);
[frameRel, order] = sort(frameRel(:));
frameStep = frameStep(order);
[frameRel, uniqueIdx] = unique(frameRel, 'last');
frameStep = frameStep(uniqueIdx);
if isempty(frameRel)
    return
end

frameStep = max(1, min(nsteps, round(frameStep)));
offsetSec = localResolveFrameStepOffsetSec(ex, T);
queryTime = tRel(:) - offsetSec + 1e-9;
edges = [frameRel(:); Inf];
bin = discretize(queryTime, edges);

stepIdx = ones(numel(tRel), 1);
hasFrame = isfinite(bin);
stepIdx(hasFrame) = frameStep(bin(hasFrame));
stepIdx(~isfinite(stepIdx)) = 1;
stepIdx = max(1, min(nsteps, stepIdx));
end


function tf = localUseFrameStepTiming(ex, T)
tf = true;
analysis = localAnalysisSettings(ex);
tf = localGetLogicalField(analysis, {'useFrameStepTiming','useActualStepTiming','useFlipStepTiming'}, tf);
mode = localGetTextField(analysis, {'targetStepTimingMode','stepTimingMode','frameStepTimingMode'}, '');
if isstruct(T)
    tf = localGetLogicalField(T, {'useFrameStepTiming','useActualStepTiming','useFlipStepTiming'}, tf);
    mode = localGetTextField(T, {'targetStepTimingMode','stepTimingMode','frameStepTimingMode'}, mode);
end
if isempty(mode)
    return
end
mode = lower(strtrim(mode));
switch mode
    case {'frame','frames','framelog','flip','flips','actual','displayed','logged'}
        tf = true;
    case {'ideal','nominal','analytic','estimated','analog','matlab','legacy','old'}
        tf = false;
end
end


function offsetSec = localResolveFrameStepOffsetSec(ex, T)
offsetSec = 0;
analysis = localAnalysisSettings(ex);
offsetSec = localGetScalarField(analysis, ...
    {'frameStepOffsetSec','frameStepTimingOffsetSec','actualStepOffsetSec','flipStepOffsetSec'}, offsetSec);
if isstruct(T)
    offsetSec = localGetScalarField(T, ...
        {'frameStepOffsetSec','frameStepTimingOffsetSec','actualStepOffsetSec','flipStepOffsetSec'}, offsetSec);
end
if ~isfinite(offsetSec)
    offsetSec = 0;
end
end


function stimOnRel = localResolveTargetStimOnRel(ex, T, tRel)
fallbackRel = localMatlabStimOnRel(T);
if strcmp(localResolveTargetStimOnMode(ex, T), 'matlab')
    stimOnRel = fallbackRel;
    if ~isfinite(stimOnRel)
        stimOnRel = 0;
    end
    return
end

stimOnRel = localExplicitAnalogStimOnRel(T);
if isfinite(stimOnRel)
    return
end

stimOnRel = localDetectedAnalogStimOnRel(ex, T, tRel, fallbackRel);
if isfinite(stimOnRel)
    return
end

stimOnRel = fallbackRel;
if ~isfinite(stimOnRel)
    stimOnRel = 0;
end
end


function mode = localResolveTargetStimOnMode(ex, T)
mode = 'analog';
analysis = localAnalysisSettings(ex);
mode = localGetTextField(analysis, ...
    {'targetStimOnMode','targetTimingMode','stepStimOnMode','stimOnAlignmentMode'}, mode);
if isstruct(T)
    mode = localGetTextField(T, ...
        {'targetStimOnMode','targetTimingMode','stepStimOnMode','stimOnAlignmentMode'}, mode);
end

mode = lower(strtrim(mode));
switch mode
    case {'matlab','saved','stim','stimon','ptb','legacy','old'}
        mode = 'matlab';
    otherwise
        mode = 'analog';
end
end


function stimOnRel = localMatlabStimOnRel(T)
stimOnRel = NaN;
stimOnAbs = NaN;
if isfield(T, 'times') && isfield(T.times, 'stimOn') && ~isempty(T.times.stimOn)
    stimOnAbs = double(T.times.stimOn(1));
end
trStart = getfieldOrNaN(T, 'TrialStart'); %#ok<GFLD>
if isfinite(stimOnAbs) && isfinite(trStart)
    stimOnRel = stimOnAbs - trStart;
end
end


function stimOnRel = localExplicitAnalogStimOnRel(T)
stimOnRel = NaN;
if ~isstruct(T)
    return
end

relNames = {'stimOnAnalogRel','stimOnVisualRel','stimOnPulseRel'};
for k = 1:numel(relNames)
    name = relNames{k};
    if isfield(T, name) && isnumeric(T.(name)) && ~isempty(T.(name))
        stimOnRel = double(T.(name)(1));
        if isfinite(stimOnRel)
            return
        end
    end
end
if isfield(T, 'times') && isstruct(T.times)
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
absNames = {'stimOnAnalog','stimOnVisual','stimOnPulse'};
for k = 1:numel(absNames)
    name = absNames{k};
    if isfield(T, name) && isnumeric(T.(name)) && ~isempty(T.(name))
        stimOnAbs = double(T.(name)(1));
        if isfinite(stimOnAbs)
            break
        end
    end
end
if ~isfinite(stimOnAbs) && isfield(T, 'times') && isstruct(T.times)
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


function stimOnRel = localDetectedAnalogStimOnRel(ex, T, tRel, fallbackRel)
stimOnRel = NaN;
if ~isfield(T, 'Eye') || ~isfield(T.Eye, 'v') || isempty(T.Eye.v) || ...
        ~isfield(T.Eye, 't') || isempty(T.Eye.t)
    return
end

Vraw = T.Eye.v;
nS = min(size(Vraw, 2), numel(T.Eye.t));
if isfield(T.Eye, 'n') && T.Eye.n > 0
    nS = min(nS, T.Eye.n);
end
if nS < 2
    return
end

rowIdx = localResolveGoPulseRowIndex(ex, T);
if ~isfinite(rowIdx)
    scheduledChannels = localResolveScheduledAdcChannels(ex, T);
    physicalChannel = localResolveGoPulsePhysicalChannel(ex, T);
    rowIdx = find(scheduledChannels == physicalChannel, 1, 'first');
end
if isempty(rowIdx) || ~isfinite(rowIdx) || rowIdx < 1 || rowIdx > size(Vraw, 1)
    return
end

sig = double(Vraw(rowIdx, 1:nS));
tDp = double(T.Eye.t(1:nS));
valid = isfinite(sig(:)) & isfinite(tDp(:));
if nnz(valid) < 2
    return
end

validIdx = find(valid);
sig = sig(valid);
tDp = tDp(valid);
threshold = localResolveGoPulseThreshold(ex, T, sig);
if ~isfinite(threshold)
    return
end
polarity = localResolveGoPulsePolarity(ex, T);
switch polarity
    case 'falling'
        logicSig = sig <= threshold;
    otherwise
        logicSig = sig >= threshold;
end
edgeIdx = find(diff(logicSig) == 1) + 1;
if isempty(edgeIdx)
    return
end

edgeIdx = localFilterEdgesByMinPulseWidth(edgeIdx, tDp, localResolveGoPulseMinPulseWidthSec(ex, T));
if isempty(edgeIdx)
    return
end

edgeChoice = localResolveGoPulseEdgeIndex(ex, T);
tRel = tRel(:);
sampleRel = NaN(size(edgeIdx));
for k = 1:numel(edgeIdx)
    sampleIdx = validIdx(edgeIdx(k));
    if sampleIdx >= 1 && sampleIdx <= numel(tRel)
        sampleRel(k) = tRel(sampleIdx);
    end
end
if any(isfinite(sampleRel))
    [sampleRel, edgeIdx] = localFilterEdgesByPlausiblePulseTime(ex, T, sampleRel, edgeIdx, fallbackRel);
    if isempty(edgeIdx) || ~any(isfinite(sampleRel))
        return
    end
    edgeChoice = localChooseEdge(edgeChoice, sampleRel, fallbackRel);
    stimOnRel = sampleRel(edgeChoice);
    return
end

trStartDp = getfieldOrNaN(T, 'TrialStartDatapixx'); %#ok<GFLD>
if isfinite(trStartDp)
    dpRel = tDp(edgeIdx) - trStartDp;
    maxDeltaSec = localResolveStimOnAnalogMaxDeltaSec(ex, T);
    if isfinite(fallbackRel) && isfinite(maxDeltaSec)
        dpRel(abs(dpRel - fallbackRel) > maxDeltaSec) = NaN;
    end
    [dpRel, edgeIdx] = localFilterEdgesByPlausiblePulseTime(ex, T, dpRel, edgeIdx, fallbackRel);
    if ~any(isfinite(dpRel))
        return
    end
    edgeChoice = localChooseEdge(edgeChoice, dpRel, fallbackRel);
    stimOnRel = dpRel(edgeChoice);
end
end


function edgeIdx = localFilterEdgesByMinPulseWidth(edgeIdx, t, minPulseWidthSec)
if isempty(edgeIdx) || minPulseWidthSec <= 0
    return
end
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


function edgeChoice = localChooseEdge(edgeChoice, edgeTimes, fallbackRel)
edgeTimes = edgeTimes(:);
finiteIdx = find(isfinite(edgeTimes));
if isempty(finiteIdx)
    edgeChoice = 1;
    return
end
if isfinite(edgeChoice)
    edgeChoice = max(1, min(numel(edgeTimes), round(double(edgeChoice))));
    if ~isfinite(edgeTimes(edgeChoice))
        edgeChoice = finiteIdx(1);
    end
elseif isfinite(fallbackRel)
    [~, iBest] = min(abs(edgeTimes(finiteIdx) - fallbackRel));
    edgeChoice = finiteIdx(iBest);
else
    edgeChoice = finiteIdx(1);
end
end


function [edgeTimes, edgeIdx] = localFilterEdgesByPlausiblePulseTime(ex, T, edgeTimes, edgeIdx, fallbackRel)
expectedRel = localExpectedPhotodiodePulseRel(T, fallbackRel);
windowSec = localResolvePhotodiodePulseWindowSec(ex, T);
if ~isfinite(expectedRel) || ~isfinite(windowSec)
    return
end
if windowSec <= 0
    edgeTimes = NaN(0, 1);
    edgeIdx = edgeIdx([]);
    return
end

edgeTimes = edgeTimes(:);
keep = isfinite(edgeTimes) & abs(edgeTimes - expectedRel) <= windowSec;
edgeTimes = edgeTimes(keep);
edgeIdx = edgeIdx(keep);
end


function expectedRel = localExpectedPhotodiodePulseRel(T, fallbackRel)
expectedRel = NaN;
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
            expectedRel = flipInfo(idx, 1) - trStart;
            if isfinite(expectedRel)
                return
            end
        end
    end
end
if isfinite(fallbackRel)
    expectedRel = fallbackRel;
end
end


function windowSec = localResolvePhotodiodePulseWindowSec(ex, T)
windowSec = 0.5;
analysis = localAnalysisSettings(ex);
windowSec = localGetScalarField(analysis, ...
    {'targetPhotodiodeWindowSec','photodiodePulseWindowSec','photodiodeWindowSec', ...
    'eyeTimePhotodiodeWindowSec','targetGoPulseWindowSec','goPulseWindowSec','syncPulseWindowSec'}, windowSec);
if isstruct(T)
    windowSec = localGetScalarField(T, ...
        {'targetPhotodiodeWindowSec','photodiodePulseWindowSec','photodiodeWindowSec', ...
        'eyeTimePhotodiodeWindowSec','targetGoPulseWindowSec','goPulseWindowSec','syncPulseWindowSec'}, windowSec);
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


function physicalChannel = localResolveGoPulsePhysicalChannel(ex, T)
physicalChannel = 6;
analysis = localAnalysisSettings(ex);
physicalChannel = localGetScalarField(analysis, ...
    {'targetPhotodiodePhysicalChannel','eyeTimePhotodiodePhysicalChannel', ...
    'photodiodePulsePhysicalChannel','photodiodePhysicalChannel', ...
    'eyeTimeGoPulsePhysicalChannel','goPulsePhysicalChannel','syncPhysicalChannel'}, physicalChannel);
if isstruct(T)
    physicalChannel = localGetScalarField(T, ...
        {'targetPhotodiodePhysicalChannel','eyeTimePhotodiodePhysicalChannel', ...
        'photodiodePulsePhysicalChannel','photodiodePhysicalChannel', ...
        'eyeTimeGoPulsePhysicalChannel','goPulsePhysicalChannel','syncPhysicalChannel'}, physicalChannel);
end
physicalChannel = round(double(physicalChannel));
end


function rowIdx = localResolveGoPulseRowIndex(ex, T)
rowIdx = NaN;
analysis = localAnalysisSettings(ex);
rowIdx = localGetScalarField(analysis, ...
    {'targetPhotodiodeRowIndex','eyeTimePhotodiodeRowIndex','photodiodePulseRowIndex', ...
    'photodiodeRowIndex','eyeTimeGoPulseRowIndex','goPulseRowIndex','syncRowIndex'}, ...
    rowIdx);
if isstruct(T)
    rowIdx = localGetScalarField(T, ...
        {'targetPhotodiodeRowIndex','eyeTimePhotodiodeRowIndex','photodiodePulseRowIndex', ...
        'photodiodeRowIndex','eyeTimeGoPulseRowIndex','goPulseRowIndex','syncRowIndex'}, ...
        rowIdx);
end
if isfinite(rowIdx)
    rowIdx = round(double(rowIdx));
end
end


function threshold = localResolveGoPulseThreshold(ex, T, sig)
threshold = 0.3;
analysis = localAnalysisSettings(ex);
threshold = localGetScalarField(analysis, ...
    {'targetPhotodiodeThresholdV','eyeTimePhotodiodeThresholdV','photodiodePulseThresholdV', ...
    'photodiodeThresholdV','eyeTimeGoPulseThreshold','goPulseThreshold','syncThreshold'}, ...
    threshold);
if isstruct(T)
    threshold = localGetScalarField(T, ...
        {'targetPhotodiodeThresholdV','eyeTimePhotodiodeThresholdV','photodiodePulseThresholdV', ...
        'photodiodeThresholdV','eyeTimeGoPulseThreshold','goPulseThreshold','syncThreshold'}, ...
        threshold);
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


function polarity = localResolveGoPulsePolarity(ex, T)
polarity = 'rising';
analysis = localAnalysisSettings(ex);
polarity = localGetTextField(analysis, ...
    {'targetPhotodiodePolarity','eyeTimePhotodiodePolarity','photodiodePulsePolarity', ...
    'photodiodePolarity','eyeTimeGoPulsePolarity','goPulsePolarity','syncPolarity'}, ...
    polarity);
if isstruct(T)
    polarity = localGetTextField(T, ...
        {'targetPhotodiodePolarity','eyeTimePhotodiodePolarity','photodiodePulsePolarity', ...
        'photodiodePolarity','eyeTimeGoPulsePolarity','goPulsePolarity','syncPolarity'}, ...
        polarity);
end
polarity = lower(strtrim(polarity));
if ~ismember(polarity, {'rising','falling'})
    polarity = 'rising';
end
end


function minPulseWidthSec = localResolveGoPulseMinPulseWidthSec(ex, T)
minPulseWidthSec = 0.001;
analysis = localAnalysisSettings(ex);
minPulseWidthSec = localGetScalarField(analysis, ...
    {'targetPhotodiodeMinPulseWidthSec','eyeTimePhotodiodeMinPulseWidthSec', ...
    'photodiodePulseMinPulseWidthSec','photodiodeMinPulseWidthSec', ...
    'eyeTimeGoPulseMinPulseWidthSec','goPulseMinPulseWidthSec','syncMinPulseWidthSec'}, minPulseWidthSec);
if isstruct(T)
    minPulseWidthSec = localGetScalarField(T, ...
        {'targetPhotodiodeMinPulseWidthSec','eyeTimePhotodiodeMinPulseWidthSec', ...
        'photodiodePulseMinPulseWidthSec','photodiodeMinPulseWidthSec', ...
        'eyeTimeGoPulseMinPulseWidthSec','goPulseMinPulseWidthSec','syncMinPulseWidthSec'}, minPulseWidthSec);
end
if ~isfinite(minPulseWidthSec) || minPulseWidthSec < 0
    minPulseWidthSec = 0.001;
end
end


function maxDeltaSec = localResolveStimOnAnalogMaxDeltaSec(ex, T)
maxDeltaSec = 0.25;
analysis = localAnalysisSettings(ex);
maxDeltaSec = localGetScalarField(analysis, ...
    {'stimOnAnalogMaxDeltaSec','targetStimOnAnalogMaxDeltaSec','goPulseStimOnMaxDeltaSec'}, maxDeltaSec);
if isstruct(T)
    maxDeltaSec = localGetScalarField(T, ...
        {'stimOnAnalogMaxDeltaSec','targetStimOnAnalogMaxDeltaSec','goPulseStimOnMaxDeltaSec'}, maxDeltaSec);
end
if ~isfinite(maxDeltaSec) || maxDeltaSec <= 0
    maxDeltaSec = 0.25;
end
end


function edgeIndex = localResolveGoPulseEdgeIndex(ex, T)
edgeIndex = NaN;
analysis = localAnalysisSettings(ex);
edgeIndex = localGetScalarField(analysis, ...
    {'targetPhotodiodeEdgeIndex','eyeTimePhotodiodeEdgeIndex','photodiodePulseEdgeIndex', ...
    'photodiodeEdgeIndex','eyeTimeGoPulseEdgeIndex','goPulseEdgeIndex','syncEdgeIndex'}, ...
    edgeIndex);
if isstruct(T)
    edgeIndex = localGetScalarField(T, ...
        {'targetPhotodiodeEdgeIndex','eyeTimePhotodiodeEdgeIndex','photodiodePulseEdgeIndex', ...
        'photodiodeEdgeIndex','eyeTimeGoPulseEdgeIndex','goPulseEdgeIndex','syncEdgeIndex'}, ...
        edgeIndex);
end
if isfinite(edgeIndex)
    edgeIndex = max(1, round(double(edgeIndex)));
end
end


function firstGoStep = localResolveFirstGoStep(ex, T, nsteps)
firstGoStep = min(2, max(1, round(double(nsteps))));
value = NaN;
if isstruct(T) && isfield(T, 'firstGoStep')
    value = localFirstScalar(T.firstGoStep);
elseif isstruct(T) && isfield(T, 'analysisFirstGoStep')
    value = localFirstScalar(T.analysisFirstGoStep);
end
if ~isfinite(value) && isstruct(ex) && isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && ...
        isfield(ex.exp.CoPs, 'analysis')
    analysis = ex.exp.CoPs.analysis;
    if isfield(analysis, 'firstGoStep')
        value = localFirstScalar(analysis.firstGoStep);
    elseif isfield(analysis, 'analysisFirstGoStep')
        value = localFirstScalar(analysis.analysisFirstGoStep);
    end
end
if isfinite(value)
    firstGoStep = max(1, min(nsteps, round(double(value))));
end
end


function stepClockOffsetSec = localResolveStepClockOffsetSec(ex, T)
stepClockOffsetSec = 0;
value = NaN;
if isstruct(T) && isfield(T, 'stepClockOffsetSec')
    value = localFirstScalar(T.stepClockOffsetSec);
elseif isstruct(T) && isfield(T, 'analysisStepClockOffsetSec')
    value = localFirstScalar(T.analysisStepClockOffsetSec);
end
if ~isfinite(value) && isstruct(ex) && isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && ...
        isfield(ex.exp.CoPs, 'analysis')
    analysis = ex.exp.CoPs.analysis;
    if isfield(analysis, 'stepClockOffsetSec')
        value = localFirstScalar(analysis.stepClockOffsetSec);
    elseif isfield(analysis, 'analysisStepClockOffsetSec')
        value = localFirstScalar(analysis.analysisStepClockOffsetSec);
    end
end
if isfinite(value)
    stepClockOffsetSec = double(value);
end
end


function analysis = localAnalysisSettings(ex)
analysis = struct();
if isstruct(ex) && isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && ...
        isfield(ex.exp.CoPs, 'analysis') && isstruct(ex.exp.CoPs.analysis)
    analysis = ex.exp.CoPs.analysis;
end
end


function value = localGetScalarField(S, names, defaultValue)
value = defaultValue;
if ~isstruct(S)
    return
end
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


function value = localGetLogicalField(S, names, defaultValue)
value = defaultValue;
if ~isstruct(S)
    return
end
for k = 1:numel(names)
    name = names{k};
    if isfield(S, name) && ~isempty(S.(name))
        candidate = S.(name);
        if islogical(candidate) || isnumeric(candidate)
            candidate = double(candidate(1));
            if isfinite(candidate)
                value = candidate ~= 0;
                return
            end
        elseif ischar(candidate)
            text = lower(strtrim(candidate));
        elseif isstring(candidate)
            text = lower(strtrim(char(candidate(1))));
        else
            text = '';
        end
        if ~isempty(text)
            if ismember(text, {'true','t','yes','y','on','1'})
                value = true;
                return
            elseif ismember(text, {'false','f','no','n','off','0'})
                value = false;
                return
            end
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
if isempty(value)
    return
end
if ischar(value)
    candidate = value;
elseif isstring(value)
    candidate = char(value(1));
else
    candidate = '';
end
if ~isempty(candidate)
    if ~isempty(strtrim(candidate))
        text = candidate;
    end
end
end


function value = localPercentileFinite(x, pct)
x = x(isfinite(x));
if isempty(x)
    value = NaN;
    return
end
x = sort(x(:));
if numel(x) == 1
    value = x;
    return
end
pos = 1 + (numel(x) - 1) .* pct ./ 100;
lo = floor(pos);
hi = ceil(pos);
if lo == hi
    value = x(lo);
else
    value = x(lo) + (x(hi) - x(lo)) .* (pos - lo);
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
