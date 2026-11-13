function [v, t] = decodeCoPsEyelinkSamplesx(samples, sampleType, missingData)
% PTB GetQueuedData rows --> [right X, Y, pupil: left X, Y, pupil]
% gaze already calibrated in display pixels, time is tracker seconds

if isempty(samples)
    v = zeros(6, 0);
    t = zeros(1, 0);
    return
end
isSample = samples(2,:) == sampleType;
v = samples([15 17 13 14 16 12], isSample);
t = samples(1, isSample) / 1000;
v(v == missingData | ~isfinite(v)) = NaN;
for firstRow = [1 4]
    bad = ~all(isfinite(v(firstRow:firstRow+2,:)),1) | v(firstRow+2, :) <=0;
    v(firstRow:firstRow+2, bad) = NaN;
end
end
