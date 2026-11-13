function result = summarizeCoPsNativeValidationx(Trial, setup, center)
% Evaluate an accepted fixation before its completion, using raw native gaze.
result = struct('targetPx', Trial.targetPx, ...
    'targetDeg', visualPxToDeg(Trial.targetPx - center, setup), ...
    'windowTrackerSec', [NaN NaN], 'nSamples', [0 0], ...
    'gazePx', NaN(2,2), 'gazeDeg', NaN(2,2), ...
    'spreadPx', NaN(2,2), 'errorPx', NaN(2,2), ...
    'errorDeg', NaN(2,2), 'radialErrorDeg', NaN(2,1));
if ~Trial.Reward
    return
end
finish = Trial.fixationCompleteTrackerSec;
result.windowTrackerSec = finish + [-.15 -.05];
idx = Trial.Eye.t >= result.windowTrackerSec(1) & ...
    Trial.Eye.t <= result.windowTrackerSec(2);
for eye = 1:2
    rows = (eye-1)*3 + (1:2);
    P = Trial.Eye.v(rows, idx)';
    P = P(all(isfinite(P),2),:);
    result.nSamples(eye) = size(P,1);
    if size(P,1) < 20
        continue
    end
    result.gazePx(eye,:) = mean(P,1);
    result.spreadPx(eye,:) = std(P,0,1);
    result.gazeDeg(eye,:) = visualPxToDeg(result.gazePx(eye,:) - center, setup);
    result.errorPx(eye,:) = result.gazePx(eye,:) - result.targetPx;
    result.errorDeg(eye,:) = result.gazeDeg(eye,:) - result.targetDeg;
    result.radialErrorDeg(eye) = norm(result.errorDeg(eye,:));
end
end
