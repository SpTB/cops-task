function [saccadeStarts, saccadeStops, speedDegPerSec, params] = detectTrackingSaccadesCoPs(xPx, yPx, dtSec, setup, params)
% Detect saccade-like events using the CoPs tracking criteria.

xPx = xPx(:);
yPx = yPx(:);
if nargin < 5 || isempty(params)
    params = getTrackingSaccadeDefaultsCoPs(dtSec);
end

n = numel(xPx);
speedDegPerSec = NaN(n, 1);
saccadeStarts = zeros(0, 1);
saccadeStops = zeros(0, 1);
if n < 2 || ~isfinite(dtSec) || dtSec <= 0
    return
end

xSmooth = movmean(xPx, params.smoothFrames, 'omitnan');
ySmooth = movmean(yPx, params.smoothFrames, 'omitnan');
dxPx = [0; diff(xSmooth)];
dyPx = [0; diff(ySmooth)];
speedPxPerSec = hypot(dxPx, dyPx) ./ dtSec;
speedDegPerSec = px2deg(speedPxPerSec, setup);

validMask = isfinite(speedDegPerSec) & isfinite(xSmooth) & isfinite(ySmooth);
candidateMask = validMask & (speedDegPerSec >= params.speedThreshDegPerSec);
if ~any(candidateMask)
    return
end

maskPadded = [false; candidateMask; false];
segStarts = find(diff(maskPadded) == 1);
segStops = find(diff(maskPadded) == -1) - 1;
keep = false(size(segStarts));
for k = 1:numel(segStarts)
    segLen = segStops(k) - segStarts(k) + 1;
    if segLen < params.minDurFrames || segLen > params.maxDurFrames
        continue
    end
    ampPx = hypot(xSmooth(segStops(k)) - xSmooth(segStarts(k)), ySmooth(segStops(k)) - ySmooth(segStarts(k)));
    ampDeg = px2deg(ampPx, setup);
    if isfinite(ampDeg) && ampDeg >= params.minAmpDeg
        keep(k) = true;
    end
end
saccadeStarts = segStarts(keep);
saccadeStops = segStops(keep);
end


function params = getTrackingSaccadeDefaultsCoPs(dtSec)
params = struct();
params.preSaccadeWindowFrames = 3;
params.speedThreshDegPerSec = 30;
params.minAmpDeg = 1;
params.minDurSec = 0.008;
params.maxDurSec = 5;
params.smoothFrames = 5;
if ~isfinite(dtSec) || dtSec <= 0
    params.preSaccadeWindowFrames = max(1, params.preSaccadeWindowFrames);
    params.minDurFrames = 1;
    params.maxDurFrames = inf;
else
    params.preSaccadeWindowSec = params.preSaccadeWindowFrames * dtSec;
    params.minDurFrames = max(1, round(params.minDurSec / dtSec));
    params.maxDurFrames = max(params.minDurFrames, round(params.maxDurSec / dtSec));
end
end
