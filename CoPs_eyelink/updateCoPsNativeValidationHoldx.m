function [holdStart, holdEnd, lastTime] = updateCoPsNativeValidationHoldx( ...
    v, t, targetPx, halfWinPx, holdDuration, holdStart, lastTime)
% Require continuous valid binocular-mean (or available-eye) fixation.
% A blink, outside sample, or a gap over 100 ms restarts the hold.
holdEnd = NaN;
for i = 1:numel(t)
    if ~isfinite(t(i)) || t(i) <= lastTime
        continue
    end
    P = reshape(v([1 2 4 5], i), 2, 2)';
    P = P(all(isfinite(P), 2), :);
    within = ~isempty(P) && all(abs(mean(P,1) - targetPx) <= halfWinPx);
    if t(i) - lastTime > 0.1
        holdStart = NaN;
    end
    lastTime = t(i);
    if ~within
        holdStart = NaN;
    elseif isnan(holdStart)
        holdStart = t(i);
    end
    if isfinite(holdStart) && t(i) - holdStart >= holdDuration
        holdEnd = t(i);
        return
    end
end
end
