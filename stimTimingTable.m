function T = stimTimingTable(in)
% Return per-trial stimulus generation timing as a table.

if isstruct(in) && isfield(in, 'Trials')
    trials = in.Trials;
else
    trials = in;
end

nTrials = numel(trials);
trial = (1:nTrials)';
totalSec = NaN(nTrials, 1);
setupSec = NaN(nTrials, 1);
loadSec = NaN(nTrials, 1);
composeSec = NaN(nTrials, 1);
extractSec = NaN(nTrials, 1);
backgroundPrepSec = NaN(nTrials, 1);
maskSec = NaN(nTrials, 1);
targetMeanNormSec = NaN(nTrials, 1);
blendSec = NaN(nTrials, 1);
compositeNormSec = NaN(nTrials, 1);
circleSec = NaN(nTrials, 1);
resizeSec = NaN(nTrials, 1);
rangeNormSec = NaN(nTrials, 1);
clipRgbSec = NaN(nTrials, 1);
makeTextureSec = NaN(nTrials, 1);
preloadSec = NaN(nTrials, 1);
stepSec = NaN(nTrials, 1);
nTextures = NaN(nTrials, 1);
targetCacheHitFrac = NaN(nTrials, 1);
backgroundCacheHitFrac = NaN(nTrials, 1);
scaleTextureOnDraw = NaN(nTrials, 1);

for iTrial = 1:nTrials
    if ~isfield(trials, 'stimTiming') || numel(trials) < iTrial || isempty(trials(iTrial).stimTiming)
        continue
    end
    s = trials(iTrial).stimTiming;
    if ~isstruct(s) || isempty(fieldnames(s))
        continue
    end
    totalSec(iTrial) = localFieldScalar(s, 'totalSec');
    setupSec(iTrial) = localFieldScalar(s, 'setupSec');
    loadSec(iTrial) = localFieldScalar(s, 'totalLoadSec');
    composeSec(iTrial) = localFieldScalar(s, 'totalComposeSec');
    extractSec(iTrial) = localFieldScalar(s, 'totalExtractSec');
    backgroundPrepSec(iTrial) = localFieldScalar(s, 'totalBackgroundPrepSec');
    maskSec(iTrial) = localFieldScalar(s, 'totalMaskSec');
    targetMeanNormSec(iTrial) = localFieldScalar(s, 'totalTargetMeanNormSec');
    blendSec(iTrial) = localFieldScalar(s, 'totalBlendSec');
    compositeNormSec(iTrial) = localFieldScalar(s, 'totalCompositeNormSec');
    circleSec(iTrial) = localFieldScalar(s, 'totalCircleSec');
    resizeSec(iTrial) = localFieldScalar(s, 'totalResizeSec');
    rangeNormSec(iTrial) = localFieldScalar(s, 'totalRangeNormSec');
    clipRgbSec(iTrial) = localFieldScalar(s, 'totalClipRgbSec');
    makeTextureSec(iTrial) = localFieldScalar(s, 'totalMakeTextureSec');
    preloadSec(iTrial) = localFieldScalar(s, 'preloadSec');
    stepSec(iTrial) = localFieldScalar(s, 'totalStepSec');
    nTextures(iTrial) = localFieldScalar(s, 'nTextures');
    targetCacheHitFrac(iTrial) = localFieldScalar(s, 'fracTargetCacheHit');
    backgroundCacheHitFrac(iTrial) = localFieldScalar(s, 'fracBackgroundCacheHit');
    scaleTextureOnDraw(iTrial) = localFieldScalar(s, 'scaleTextureOnDraw');
end

T = table(trial, totalSec, setupSec, loadSec, composeSec, extractSec, ...
    backgroundPrepSec, maskSec, targetMeanNormSec, blendSec, ...
    compositeNormSec, circleSec, resizeSec, rangeNormSec, clipRgbSec, ...
    makeTextureSec, preloadSec, stepSec, nTextures, targetCacheHitFrac, ...
    backgroundCacheHitFrac, scaleTextureOnDraw);
end


function value = localFieldScalar(s, fieldName)
value = NaN;
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    rawValue = s.(fieldName);
    if isnumeric(rawValue) || islogical(rawValue)
        rawValue = double(rawValue);
        value = rawValue(1);
    end
end
end
