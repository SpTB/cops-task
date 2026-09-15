function [xPx, yPx] = preprocessGazeForCcgCoPs(xPx, yPx, dtSec, interpBlinkSec, lowpassHz, protectedNaNMask)
% preprocessGazeForCcgCoPs  Prepare gaze traces for CCG analysis.
%
% Applies short-gap interpolation first, then optional zero-phase low-pass
% filtering on contiguous finite segments. Intended for use before
% step-aggregated velocity CCGs.

xPx = double(xPx(:));
yPx = double(yPx(:));

if nargin < 4 || isempty(interpBlinkSec)
    interpBlinkSec = 0;
end
if nargin < 5 || isempty(lowpassHz)
    lowpassHz = [];
end
if nargin < 6 || isempty(protectedNaNMask)
    protectedNaNMask = false(size(xPx));
end
protectedNaNMask = logical(protectedNaNMask(:));

interpBlinkSec = double(interpBlinkSec);
if isfinite(interpBlinkSec) && interpBlinkSec > 0 && isfinite(dtSec) && dtSec > 0
    maxGapSamples = max(1, round(interpBlinkSec / dtSec));
    xPx = localInterpShortNaNGaps(xPx, maxGapSamples, protectedNaNMask);
    yPx = localInterpShortNaNGaps(yPx, maxGapSamples, protectedNaNMask);
end

lowpassHz = double(localFirstScalar(lowpassHz));
if isfinite(lowpassHz) && lowpassHz > 0 && isfinite(dtSec) && dtSec > 0
    xPx = localZeroPhaseLowpassTrace(xPx, dtSec, lowpassHz);
    yPx = localZeroPhaseLowpassTrace(yPx, dtSec, lowpassHz);
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


function y = localZeroPhaseLowpassTrace(x, dtSec, cutoffHz)
x = x(:);
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
idx = find(isfinite(x));
if isempty(idx)
    return
end

runBreak = [true; diff(idx) > 1];
runStarts = find(runBreak);
runEnds = [runStarts(2:end) - 1; numel(idx)];
for i = 1:numel(runStarts)
    ii = idx(runStarts(i):runEnds(i));
    if numel(ii) < 7
        continue
    end
    y(ii) = filtfilt(b, a, x(ii));
end
end


function x = localInterpShortNaNGaps(x, maxGapSamples, protectedNaNMask)
x = x(:);
if isempty(x) || maxGapSamples < 1
    return
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
    if any(protectedNaNMask(g0:g1))
        continue
    end
    if ~isfinite(x(g0 - 1)) || ~isfinite(x(g1 + 1))
        continue
    end
    fillVals = linspace(x(g0 - 1), x(g1 + 1), gapLen + 2);
    x(g0:g1) = fillVals(2:end-1);
end
end
