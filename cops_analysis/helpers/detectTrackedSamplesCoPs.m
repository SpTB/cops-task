function tracked = detectTrackedSamplesCoPs(assignedSample, distPx1, distPx2, xPx, yPx, trackingDistPx, minTrackingSec, dtSec, setup, requireTrackingSaccade)
% Detect sustained tracking epochs for already-assigned target identity.
%
% A sample is considered trackable when gaze is assigned to one target and
% remains within trackingDistPx of that assigned target. Short contiguous
% runs are discarded using minTrackingSec. A trackable run only becomes a
% tracking episode if it is preceded by a saccade-like gaze jump.

assignedSample = assignedSample(:);
distPx1 = distPx1(:);
distPx2 = distPx2(:);
xPx = xPx(:);
yPx = yPx(:);
if nargin < 10 || isempty(requireTrackingSaccade)
    requireTrackingSaccade = true;
end

closerDist = NaN(size(assignedSample));
closerDist(assignedSample == 1) = distPx1(assignedSample == 1);
closerDist(assignedSample == 2) = distPx2(assignedSample == 2);

proximateToAssigned = assignedSample > 0 & isfinite(closerDist) & (closerDist <= trackingDistPx);
proximateToT1 = isfinite(distPx1) & (distPx1 <= trackingDistPx);
proximateToT2 = isfinite(distPx2) & (distPx2 <= trackingDistPx);
ambiguousProximate = proximateToT1 & proximateToT2;
minTrackingFrames = max(1, ceil(minTrackingSec / dtSec));
[saccadeStarts, saccadeStops, speedDegPerSec, saccadeParams] = detectTrackingSaccadesCoPs(xPx, yPx, dtSec, setup);

isTrackingT1 = buildTrackingSeriesLocal(proximateToAssigned & (assignedSample == 1), assignedSample, distPx1, ...
    saccadeStarts, saccadeStops, minTrackingFrames, saccadeParams.preSaccadeWindowFrames, false);
isTrackingT2 = buildTrackingSeriesLocal(proximateToAssigned & (assignedSample == 2), assignedSample, distPx2, ...
    saccadeStarts, saccadeStops, minTrackingFrames, saccadeParams.preSaccadeWindowFrames, false);
isTracking = max(isTrackingT1, isTrackingT2);

isTrackingSaccT1 = buildTrackingSeriesLocal(proximateToAssigned & (assignedSample == 1), assignedSample, distPx1, ...
    saccadeStarts, saccadeStops, minTrackingFrames, saccadeParams.preSaccadeWindowFrames, true);
isTrackingSaccT2 = buildTrackingSeriesLocal(proximateToAssigned & (assignedSample == 2), assignedSample, distPx2, ...
    saccadeStarts, saccadeStops, minTrackingFrames, saccadeParams.preSaccadeWindowFrames, true);
isTrackingSacc = max(isTrackingSaccT1, isTrackingSaccT2);

isTrackingConservT1 = buildTrackingSeriesLocal(proximateToAssigned & (assignedSample == 1) & ~ambiguousProximate, assignedSample, distPx1, ...
    saccadeStarts, saccadeStops, minTrackingFrames, saccadeParams.preSaccadeWindowFrames, false);
isTrackingConservT2 = buildTrackingSeriesLocal(proximateToAssigned & (assignedSample == 2) & ~ambiguousProximate, assignedSample, distPx2, ...
    saccadeStarts, saccadeStops, minTrackingFrames, saccadeParams.preSaccadeWindowFrames, false);
isTrackingConserv = max(isTrackingConservT1, isTrackingConservT2);

isTrackingLibT1 = buildTrackingSeriesLocal(proximateToT1, ones(size(assignedSample)), distPx1, ...
    saccadeStarts, saccadeStops, minTrackingFrames, saccadeParams.preSaccadeWindowFrames, false);
isTrackingLibT2 = buildTrackingSeriesLocal(proximateToT2, ones(size(assignedSample)), distPx2, ...
    saccadeStarts, saccadeStops, minTrackingFrames, saccadeParams.preSaccadeWindowFrames, false);
isTrackingLib = max(isTrackingLibT1, isTrackingLibT2);

eligibleWta1 = buildTrackingSeriesLocal(proximateToT1, ones(size(assignedSample)), distPx1, ...
    saccadeStarts, saccadeStops, minTrackingFrames, saccadeParams.preSaccadeWindowFrames, requireTrackingSaccade) >= 1;
eligibleWta2 = buildTrackingSeriesLocal(proximateToT2, ones(size(assignedSample)), distPx2, ...
    saccadeStarts, saccadeStops, minTrackingFrames, saccadeParams.preSaccadeWindowFrames, requireTrackingSaccade) >= 1;
[isTrackingWTA, trackedTargetIdWTA] = buildTrackingSeriesWtaLocal(eligibleWta1, eligibleWta2, assignedSample);

tracked = struct();
tracked.isTracking = isTracking;
tracked.isTrackingSacc = isTrackingSacc;
tracked.isTrackingConserv = isTrackingConserv;
tracked.isTrackingLib = isTrackingLib;
tracked.isTrackingWTA = isTrackingWTA;
tracked.trackedTargetIdWTA = trackedTargetIdWTA;
tracked.closerDist = closerDist;
tracked.proximateToAssigned = proximateToAssigned;
tracked.proximateToT1 = proximateToT1;
tracked.proximateToT2 = proximateToT2;
tracked.ambiguousProximate = ambiguousProximate;
tracked.speedDegPerSec = speedDegPerSec;
tracked.saccadeStarts = saccadeStarts;
tracked.saccadeStops = saccadeStops;
end


function [vals, trackedId] = buildTrackingSeriesWtaLocal(eligibleT1, eligibleT2, assignedSample)
eligibleT1 = logical(eligibleT1(:));
eligibleT2 = logical(eligibleT2(:));
assignedSample = assignedSample(:);
trackedId = zeros(size(assignedSample));

currentId = 0;
for i = 1:numel(trackedId)
    switch currentId
        case 1
            if eligibleT1(i)
                trackedId(i) = 1;
                continue
            elseif eligibleT2(i)
                currentId = 2;
                trackedId(i) = 2;
                continue
            else
                currentId = 0;
            end
        case 2
            if eligibleT2(i)
                trackedId(i) = 2;
                continue
            elseif eligibleT1(i)
                currentId = 1;
                trackedId(i) = 1;
                continue
            else
                currentId = 0;
            end
    end

    if eligibleT1(i) && ~eligibleT2(i)
        currentId = 1;
    elseif eligibleT2(i) && ~eligibleT1(i)
        currentId = 2;
    elseif eligibleT1(i) && eligibleT2(i)
        if assignedSample(i) == 1
            currentId = 1;
        elseif assignedSample(i) == 2
            currentId = 2;
        else
            currentId = 1;
        end
    else
        currentId = 0;
    end
    trackedId(i) = currentId;
end

vals = double(trackedId > 0);
end


function vals = buildTrackingSeriesLocal(baseMask, segmentId, distToTarget, saccadeStarts, saccadeStops, minTrackingFrames, preWindowFrames, requireTrackingSaccade)
baseMask = baseMask(:);
segmentId = segmentId(:);
distToTarget = distToTarget(:);
vals = zeros(size(baseMask));
if ~any(baseMask)
    return
end

activeCode = zeros(size(baseMask));
activeCode(baseMask) = segmentId(baseMask);
segStart = 1;
while segStart <= numel(activeCode)
    if activeCode(segStart) <= 0
        segStart = segStart + 1;
        continue
    end
    segCode = activeCode(segStart);
    segStop = segStart;
    while segStop < numel(activeCode) && activeCode(segStop + 1) == segCode
        segStop = segStop + 1;
    end
    if (segStop - segStart + 1) >= minTrackingFrames
        if ~requireTrackingSaccade
            vals(segStart:segStop) = 1;
            segStart = segStop + 1;
            continue
        end
        preStart = max(1, segStart - preWindowFrames);
        validSac = find( ...
            saccadeStops >= preStart & ...
            saccadeStops < segStart & ...
            saccadeStarts <= saccadeStops & ...
            isfinite(distToTarget(saccadeStarts)) & ...
            isfinite(distToTarget(saccadeStops)) & ...
            (distToTarget(saccadeStops) < distToTarget(saccadeStarts)), 1, 'last');
        if ~isempty(validSac)
            vals(segStart:segStop) = 1;
            vals(saccadeStarts(validSac):segStart-1) = max(vals(saccadeStarts(validSac):segStart-1), 0.5);
        end
    end
    segStart = segStop + 1;
end
end
