function metrics = computePeakChoiceMetricsCoPs(assign, peakCloser, isTracking, stepIdx, xPx, yPx, ...
    targetX, targetY, target2X, target2Y, peakPx, nsteps, dtSec, setup, requireSaccade, distPx1, distPx2, trackingDistPx)
% Compute peak-vs-outer target preference and switch-conditioned metrics.

if nargin < 15 || isempty(requireSaccade)
    requireSaccade = false;
end
if nargin < 18 || isempty(trackingDistPx)
    trackingDistPx = NaN;
end

assignedSample = assign.assignedSample(:);
peakCloser = peakCloser(:);
isTracking = isTracking(:) >= 1;

metrics = struct( ...
    'trackPeakFrac', NaN, ...
    'trackOuterFrac', NaN, ...
    'peakTrackBias', NaN, ...
    'firstTrackPeakTarget', NaN, ...
    'trackedIsPeak', [], ...
    'trackedPeakBiasObs', [], ...
    'switchToPeakFrac', NaN, ...
    'switchWhenOtherPeakFrac', NaN, ...
    'switchProbPeak', NaN, ...
    'switchProbOuter', NaN, ...
    'switchProbDelta', NaN, ...
    'saccToPeak', NaN, ...
    'saccToOuter', NaN, ...
    'saccPeakFrac', NaN, ...
    'switchToPeakObs', [], ...
    'switchWhenOtherPeakObs', [], ...
    'switchProbPeakObs', [], ...
    'switchProbOuterObs', [], ...
    'saccEntryPeakObs', []);

peakCloserTracked = peakCloser;
peakCloserTracked(~isTracking) = 0;

assignedMask = assignedSample > 0;
peakAssigned = peakCloserTracked > 0 & assignedMask;
trackedMask = isTracking & assignedMask & peakCloserTracked > 0;

firstTrackedIdx = find(peakAssigned, 1, 'first');
if ~isempty(firstTrackedIdx)
    metrics.firstTrackPeakTarget = double(assignedSample(firstTrackedIdx) == peakCloserTracked(firstTrackedIdx));
end

trackedIsPeak = assignedSample(trackedMask) == peakCloserTracked(trackedMask);
metrics.trackedIsPeak = trackedIsPeak(:);
metrics.trackedPeakBiasObs = (2 * trackedIsPeak(:)) - 1;
metrics.trackPeakFrac = mean(trackedIsPeak, 'omitnan');
metrics.trackOuterFrac = 1 - metrics.trackPeakFrac;
metrics.peakTrackBias = (2 * metrics.trackPeakFrac) - 1;

assignedStep = assign.assignedStep(:);
steps = assign.step(:);
if isempty(assignedStep) || isempty(steps)
    return
end

stepPeak = computeStepPeakTargetLocal(stepIdx, steps, targetX, targetY, target2X, target2Y, peakPx);
validAssignedStep = assignedStep > 0;
seqAssigned = assignedStep(validAssignedStep);
seqPeak = stepPeak(validAssignedStep);
if numel(seqAssigned) < 2
    return
end

switched = diff(seqAssigned) ~= 0;
if requireSaccade
    stepHasSaccade = aggregateStepwiseSaccadeLocal(stepIdx, steps, xPx, yPx, dtSec, setup);
    seqStepHasSaccade = stepHasSaccade(validAssignedStep);
    if numel(seqStepHasSaccade) > 1
        switched = switched & seqStepHasSaccade(2:end);
    else
        switched(:) = false;
    end
end

switchIdx = find(switched) + 1; % index in the compressed valid-assignment sequence
if ~isempty(switchIdx)
    validToPeak = seqPeak(switchIdx) > 0;
    switchToPeakObs = seqAssigned(switchIdx(validToPeak)) == seqPeak(switchIdx(validToPeak));
    metrics.switchToPeakObs = switchToPeakObs(:);
    metrics.switchToPeakFrac = mean(switchToPeakObs, 'omitnan');

    prevIdx = switchIdx - 1;
    otherPrev = 3 - seqAssigned(prevIdx);
    validOtherPrev = seqPeak(prevIdx) > 0;
    switchWhenOtherPeakObs = seqPeak(prevIdx(validOtherPrev)) == otherPrev(validOtherPrev);
    metrics.switchWhenOtherPeakObs = switchWhenOtherPeakObs(:);
    metrics.switchWhenOtherPeakFrac = mean(switchWhenOtherPeakObs, 'omitnan');
end

prevAssigned = seqAssigned(1:end-1);
peakPrev = seqPeak(1:end-1);
otherPrev = 3 - prevAssigned;
otherCloserPrev = peakPrev == otherPrev;
peakCloserPrev = peakPrev == prevAssigned;

if any(otherCloserPrev)
    metrics.switchProbPeakObs = switched(otherCloserPrev);
    metrics.switchProbPeak = mean(metrics.switchProbPeakObs, 'omitnan');
end
if any(peakCloserPrev)
    metrics.switchProbOuterObs = switched(peakCloserPrev);
    metrics.switchProbOuter = mean(metrics.switchProbOuterObs, 'omitnan');
end
if isfinite(metrics.switchProbPeak) && isfinite(metrics.switchProbOuter)
    metrics.switchProbDelta = metrics.switchProbPeak - metrics.switchProbOuter;
end

if nargin >= 17 && ~isempty(distPx1) && ~isempty(distPx2) && isfinite(trackingDistPx) && trackingDistPx > 0
    metrics.saccEntryPeakObs = computeSaccadeEntryPeakObsLocal( ...
        xPx, yPx, dtSec, setup, distPx1, distPx2, peakCloser, trackingDistPx);
    if ~isempty(metrics.saccEntryPeakObs)
        metrics.saccToPeak = sum(metrics.saccEntryPeakObs, 'omitnan');
        metrics.saccToOuter = sum(~metrics.saccEntryPeakObs, 'omitnan');
        metrics.saccPeakFrac = mean(metrics.saccEntryPeakObs, 'omitnan');
    end
end
end


function stepPeak = computeStepPeakTargetLocal(stepIdx, steps, targetX, targetY, target2X, target2Y, peakPx)
stepX1 = aggregateStepwiseMeanLocal(stepIdx, targetX, steps);
stepY1 = aggregateStepwiseMeanLocal(stepIdx, targetY, steps);
stepX2 = aggregateStepwiseMeanLocal(stepIdx, target2X, steps);
stepY2 = aggregateStepwiseMeanLocal(stepIdx, target2Y, steps);

dist1 = hypot(stepX1 - peakPx(1), stepY1 - peakPx(2));
dist2 = hypot(stepX2 - peakPx(1), stepY2 - peakPx(2));

stepPeak = zeros(size(steps));
stepPeak(dist1 < dist2) = 1;
stepPeak(dist2 < dist1) = 2;
end


function stepMeans = aggregateStepwiseMeanLocal(stepIdx, values, steps)
stepIdx = stepIdx(:);
values = values(:);
steps = steps(:);
stepMeans = NaN(size(steps));
for i = 1:numel(steps)
    mask = isfinite(stepIdx) & stepIdx == steps(i) & isfinite(values);
    if any(mask)
        stepMeans(i) = mean(values(mask), 'omitnan');
    end
end
end


function stepHasSaccade = aggregateStepwiseSaccadeLocal(stepIdx, steps, xPx, yPx, dtSec, setup)
steps = steps(:);
stepHasSaccade = false(size(steps));
[~, saccadeStops] = detectTrackingSaccadesCoPs(xPx, yPx, dtSec, setup);
if isempty(saccadeStops)
    return
end
saccadeStep = stepIdx(saccadeStops);
for i = 1:numel(steps)
    stepHasSaccade(i) = any(saccadeStep == steps(i));
end
end


function saccEntryPeakObs = computeSaccadeEntryPeakObsLocal(xPx, yPx, dtSec, setup, distPx1, distPx2, peakCloser, trackingDistPx)
[saccadeStarts, saccadeStops] = detectTrackingSaccadesCoPs(xPx, yPx, dtSec, setup);
saccEntryPeakObs = false(0, 1);
if isempty(saccadeStops)
    return
end

keep = false(numel(saccadeStops), 1);
isPeak = false(numel(saccadeStops), 1);
for i = 1:numel(saccadeStops)
    i0 = saccadeStarts(i);
    i1 = saccadeStops(i);
    if ~isfinite(distPx1(i0)) || ~isfinite(distPx1(i1)) || ~isfinite(distPx2(i0)) || ~isfinite(distPx2(i1))
        continue
    end
    entered1 = distPx1(i0) > trackingDistPx && distPx1(i1) <= trackingDistPx;
    entered2 = distPx2(i0) > trackingDistPx && distPx2(i1) <= trackingDistPx;
    if xor(entered1, entered2) && peakCloser(i1) > 0
        keep(i) = true;
        enteredTarget = 1;
        if entered2
            enteredTarget = 2;
        end
        isPeak(i) = enteredTarget == peakCloser(i1);
    end
end
saccEntryPeakObs = isPeak(keep);
end
