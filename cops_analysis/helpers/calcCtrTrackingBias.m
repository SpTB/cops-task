function out = calcCtrTrackingBias(targetX, targetY, target2X, target2Y, xPx, yPx, distPx1, distPx2, ...
    inBounds, betweenMarginPx, peakPx, stepIdx, nsteps, trackingDistPx, minTrackingSec, dtSec, screenCenterPx, earlyTrackingSec, minPhaseTrackingSec, setup, requireTrackingSaccade, switchRequireSaccade, assignedTargetOverride)
% Compute peak-related tracking and switching bias for two targets.

if nargin < 17 || isempty(screenCenterPx)
    screenCenterPx = peakPx;
end
if nargin < 18 || isempty(earlyTrackingSec)
    earlyTrackingSec = 0.150;
end
if nargin < 19 || isempty(minPhaseTrackingSec)
    minPhaseTrackingSec = 0.200;
end
if nargin < 20
    setup = struct();
end
if nargin < 21 || isempty(requireTrackingSaccade)
    requireTrackingSaccade = true;
end
if nargin < 22 || isempty(switchRequireSaccade)
    switchRequireSaccade = false;
end
if nargin < 23
    assignedTargetOverride = [];
end

out = struct( ...
    'trackPeakFrac', NaN, ...
    'trackOuterFrac', NaN, ...
    'peakTrackBias', NaN, ...
    'firstTrackPeakTarget', NaN, ...
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
    'trackedPhaseCode', [], ...
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
    'isTracking', [], ...
    'isTrackingSacc', [], ...
    'switchToPeakObs', [], ...
    'switchWhenOtherPeakObs', [], ...
    'switchProbPeakObs', [], ...
    'switchProbOuterObs', [], ...
    'saccEntryPeakObs', [], ...
    'isTrackingConserv', [], ...
    'isTrackingLib', [], ...
    'isTrackingWTA', [], ...
    'trackedTargetIdWTA', []);

singleTargetTrial = ~any(isfinite(target2X(:)) & isfinite(target2Y(:)));
if singleTargetTrial
    assigned3 = ones(size(targetX(:)));
    tracked = detectTrackedSamplesCoPs(assigned3, distPx1, distPx2, xPx, yPx, trackingDistPx, minTrackingSec, dtSec, setup, requireTrackingSaccade);
    trackedMask = tracked.isTracking >= 1 & assigned3 > 0;
    out.isTracking = tracked.isTracking;
    out.isTrackingSacc = tracked.isTrackingSacc;
    out.isTrackingConserv = tracked.isTrackingConserv;
    out.isTrackingLib = tracked.isTrackingLib;
    out.isTrackingWTA = tracked.isTrackingWTA;
    out.trackedTargetIdWTA = tracked.trackedTargetIdWTA;

    biasMetrics = computeTrackedBiasMetricsCoPs( ...
        targetX, targetY, target2X, target2Y, xPx, yPx, ...
        assigned3, trackedMask, peakPx, screenCenterPx, dtSec, earlyTrackingSec, minPhaseTrackingSec);
    metricFields = fieldnames(biasMetrics);
    for i = 1:numel(metricFields)
        out.(metricFields{i}) = biasMetrics.(metricFields{i});
    end
    return
end


distCtr1 = hypot(targetX(:) - peakPx(1), targetY(:) - peakPx(2));
distCtr2 = hypot(target2X(:) - peakPx(1), target2Y(:) - peakPx(2));

peakCloser = zeros(size(distCtr1)); % 1=t1, 2=t2, 0=tie/invalid
peakCloser(distCtr1 < distCtr2) = 1;
peakCloser(distCtr2 < distCtr1) = 2;

if isempty(assignedTargetOverride)
    assign = assignTargetIdentityCoPs(distPx1, distPx2, inBounds, betweenMarginPx, stepIdx);
    assigned3 = assign.assignedSample;
    tracked = detectTrackedSamplesCoPs(assigned3, distPx1, distPx2, xPx, yPx, trackingDistPx, minTrackingSec, dtSec, setup, requireTrackingSaccade);
else
    assign = localAssignmentFromOverride(assignedTargetOverride, stepIdx);
    assigned3 = assign.assignedSample;
    tracked = localTrackedFromHmmState(assigned3);
end
trackedMask = tracked.isTracking >= 1 & assigned3 > 0;
out.isTracking = tracked.isTracking;
out.isTrackingSacc = tracked.isTrackingSacc;
out.isTrackingConserv = tracked.isTrackingConserv;
out.isTrackingLib = tracked.isTrackingLib;
out.isTrackingWTA = tracked.isTrackingWTA;
out.trackedTargetIdWTA = tracked.trackedTargetIdWTA;

biasMetrics = computeTrackedBiasMetricsCoPs( ...
    targetX, targetY, target2X, target2Y, xPx, yPx, ...
    assigned3, trackedMask, peakPx, screenCenterPx, dtSec, earlyTrackingSec, minPhaseTrackingSec);
choiceMetrics = computePeakChoiceMetricsCoPs( ...
    assign, peakCloser, tracked.isTracking, stepIdx, xPx, yPx, ...
    targetX, targetY, target2X, target2Y, peakPx, nsteps, dtSec, setup, switchRequireSaccade, distPx1, distPx2, trackingDistPx);

metricFields = fieldnames(biasMetrics);
for i = 1:numel(metricFields)
    out.(metricFields{i}) = biasMetrics.(metricFields{i});
end

metricFields = fieldnames(choiceMetrics);
for i = 1:numel(metricFields)
    out.(metricFields{i}) = choiceMetrics.(metricFields{i});
end

end


function assign = localAssignmentFromOverride(assignedTarget, stepIdx)
assignedTarget = double(assignedTarget(:));
invalidCode = isfinite(assignedTarget) & ~ismember(assignedTarget, [0 1 2]);
assignedTarget(invalidCode) = 0;

assign = struct();
assign.assignedSample = assignedTarget;
assign.betweenSample = assignedTarget == 0;

if isempty(stepIdx)
    assign.step = zeros(0, 1);
    assign.assignedStep = zeros(0, 1);
    return
end

stepIdx = double(stepIdx(:));
uStep = unique(stepIdx(isfinite(stepIdx)));
uStep = uStep(:);
assignedStep = zeros(size(uStep));
for k = 1:numel(uStep)
    values = assignedTarget(stepIdx == uStep(k));
    values = values(values > 0);
    if isempty(values)
        continue
    end
    n1 = sum(values == 1);
    n2 = sum(values == 2);
    if n1 > n2
        assignedStep(k) = 1;
    elseif n2 > n1
        assignedStep(k) = 2;
    end
end
assign.step = uStep;
assign.assignedStep = assignedStep;
end


function tracked = localTrackedFromHmmState(assignedTarget)
assignedTarget = double(assignedTarget(:));
isTracking = nan(size(assignedTarget));
isTracking(assignedTarget == 0) = 0;
isTracking(assignedTarget == 1 | assignedTarget == 2) = 1;

tracked = struct();
tracked.isTracking = isTracking;
tracked.isTrackingSacc = isTracking;
tracked.isTrackingConserv = isTracking;
tracked.isTrackingLib = isTracking;
tracked.isTrackingWTA = isTracking;
tracked.trackedTargetIdWTA = assignedTarget;
end
