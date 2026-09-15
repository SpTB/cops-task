function metrics = computeTrackedBiasMetricsCoPs(targetX, targetY, target2X, target2Y, xPx, yPx, ...
    assignedSample, trackedMask, peakPx, screenCenterPx, dtSec, earlyTrackingSec, minPhaseTrackingSec)
% Compute tracking-error and projection-bias metrics for tracked samples.

assignedSample = assignedSample(:);
trackedMask = trackedMask(:);
if nargin < 11 || isempty(dtSec)
    dtSec = NaN;
end
if nargin < 12 || isempty(earlyTrackingSec)
    earlyTrackingSec = 0.150;
end
if nargin < 13 || isempty(minPhaseTrackingSec)
    minPhaseTrackingSec = 0.200;
end

metrics = struct( ...
    'trackErrorPx', NaN, ...
    'trackErrorRmsPx', NaN, ...
    'trackVariabilityPx', NaN, ...
    'trackBiasPx', NaN, ...
    'trackScreenCenterBiasPx', NaN, ...
    'trackGaussSpecificBiasPx', NaN, ...
    'trackBiasXPx', NaN, ...
    'trackBiasYPx', NaN, ...
    'trackedErrXPx', [], ...
    'trackedErrYPx', [], ...
    'trackedBiasPx', [], ...
    'trackedScreenCenterBiasPx', [], ...
    'trackedGaussSpecificBiasPx', [], ...
    'trackedBiasXPx', [], ...
    'trackedBiasYPx', [], ...
    'trackedTargetDistFromCtrPx', [], ...
    'trackedPhaseCode', []);

if ~any(trackedMask)
    return
end

trackedTargetX = NaN(size(assignedSample));
trackedTargetY = NaN(size(assignedSample));
trackedTargetX(assignedSample == 1) = targetX(assignedSample == 1);
trackedTargetY(assignedSample == 1) = targetY(assignedSample == 1);
trackedTargetX(assignedSample == 2) = target2X(assignedSample == 2);
trackedTargetY(assignedSample == 2) = target2Y(assignedSample == 2);

towardPeakX = sign(peakPx(1) - trackedTargetX);
towardPeakY = sign(peakPx(2) - trackedTargetY);
signedBiasX = (xPx(:) - trackedTargetX) .* towardPeakX;
signedBiasY = (yPx(:) - trackedTargetY) .* towardPeakY;

targetToPeakX = peakPx(1) - trackedTargetX;
targetToPeakY = peakPx(2) - trackedTargetY;
targetToPeakNorm = hypot(targetToPeakX, targetToPeakY);
unitToPeakX = targetToPeakX ./ targetToPeakNorm;
unitToPeakY = targetToPeakY ./ targetToPeakNorm;
unitToPeakX(~isfinite(unitToPeakX)) = NaN;
unitToPeakY(~isfinite(unitToPeakY)) = NaN;

targetToScreenCtrX = screenCenterPx(1) - trackedTargetX;
targetToScreenCtrY = screenCenterPx(2) - trackedTargetY;
targetToScreenCtrNorm = hypot(targetToScreenCtrX, targetToScreenCtrY);
unitToScreenCtrX = targetToScreenCtrX ./ targetToScreenCtrNorm;
unitToScreenCtrY = targetToScreenCtrY ./ targetToScreenCtrNorm;
unitToScreenCtrX(~isfinite(unitToScreenCtrX)) = NaN;
unitToScreenCtrY(~isfinite(unitToScreenCtrY)) = NaN;

peakOnScreenDot = unitToPeakX .* unitToScreenCtrX + unitToPeakY .* unitToScreenCtrY;
peakSpecificX = unitToPeakX - peakOnScreenDot .* unitToScreenCtrX;
peakSpecificY = unitToPeakY - peakOnScreenDot .* unitToScreenCtrY;
peakSpecificNorm = hypot(peakSpecificX, peakSpecificY);
unitPeakSpecificX = peakSpecificX ./ peakSpecificNorm;
unitPeakSpecificY = peakSpecificY ./ peakSpecificNorm;
unitPeakSpecificX(peakSpecificNorm < 1e-6) = NaN;
unitPeakSpecificY(peakSpecificNorm < 1e-6) = NaN;

gazeErrX = xPx(:) - trackedTargetX;
gazeErrY = yPx(:) - trackedTargetY;
signedBias = gazeErrX .* unitToPeakX + gazeErrY .* unitToPeakY;
signedScreenCenterBias = gazeErrX .* unitToScreenCtrX + gazeErrY .* unitToScreenCtrY;
signedGaussSpecificBias = gazeErrX .* unitPeakSpecificX + gazeErrY .* unitPeakSpecificY;

trackedErrX = gazeErrX(trackedMask);
trackedErrY = gazeErrY(trackedMask);
trackedSignedBias = signedBias(trackedMask);
trackedSignedScreenCenterBias = signedScreenCenterBias(trackedMask);
trackedSignedGaussSpecificBias = signedGaussSpecificBias(trackedMask);
trackedTargetDist = targetToPeakNorm(trackedMask);
trackedPhaseCode = labelTrackedPhaseSamples(trackedMask, dtSec, earlyTrackingSec, minPhaseTrackingSec);
meanErrX = mean(trackedErrX, 'omitnan');
meanErrY = mean(trackedErrY, 'omitnan');
centeredErrSq = (trackedErrX - meanErrX).^2 + (trackedErrY - meanErrY).^2;

metrics.trackErrorPx = mean(hypot(trackedErrX, trackedErrY), 'omitnan');
metrics.trackErrorRmsPx = sqrt(mean(trackedErrX.^2 + trackedErrY.^2, 'omitnan'));
metrics.trackVariabilityPx = sqrt(mean(centeredErrSq, 'omitnan'));
metrics.trackBiasPx = mean(trackedSignedBias, 'omitnan');
metrics.trackScreenCenterBiasPx = mean(trackedSignedScreenCenterBias, 'omitnan');
metrics.trackGaussSpecificBiasPx = mean(trackedSignedGaussSpecificBias, 'omitnan');
metrics.trackBiasXPx = mean(signedBiasX(trackedMask), 'omitnan');
metrics.trackBiasYPx = mean(signedBiasY(trackedMask), 'omitnan');
metrics.trackedErrXPx = trackedErrX;
metrics.trackedErrYPx = trackedErrY;
metrics.trackedBiasPx = trackedSignedBias;
metrics.trackedScreenCenterBiasPx = trackedSignedScreenCenterBias;
metrics.trackedGaussSpecificBiasPx = trackedSignedGaussSpecificBias;
metrics.trackedBiasXPx = signedBiasX(trackedMask);
metrics.trackedBiasYPx = signedBiasY(trackedMask);
metrics.trackedTargetDistFromCtrPx = trackedTargetDist;
metrics.trackedPhaseCode = trackedPhaseCode;
end


function phaseCode = labelTrackedPhaseSamples(trackedMask, dtSec, earlyTrackingSec, minPhaseTrackingSec)
phaseCode = zeros(nnz(trackedMask), 1);
if ~any(trackedMask)
    return
end

if ~isfinite(dtSec) || dtSec <= 0 || ~isfinite(earlyTrackingSec) || earlyTrackingSec <= 0
    earlyFrames = 1;
else
    earlyFrames = max(1, round(earlyTrackingSec / dtSec));
end
if ~isfinite(dtSec) || dtSec <= 0 || ~isfinite(minPhaseTrackingSec) || minPhaseTrackingSec <= 0
    minPhaseFrames = 1;
else
    minPhaseFrames = max(1, round(minPhaseTrackingSec / dtSec));
end

trackedIdx = find(trackedMask);
runBreak = [true; diff(trackedIdx) > 1];
runStartIdx = find(runBreak);
runEndIdx = [runStartIdx(2:end) - 1; numel(trackedIdx)];
for i = 1:numel(runStartIdx)
    idx0 = runStartIdx(i);
    idx1 = runEndIdx(i);
    nRun = idx1 - idx0 + 1;
    if nRun < minPhaseFrames
        continue
    end
    nEarly = min(earlyFrames, nRun);
    phaseCode(idx0:idx0+nEarly-1) = 1;
    if nEarly < nRun
        phaseCode(idx0+nEarly:idx1) = 2;
    end
end
end
