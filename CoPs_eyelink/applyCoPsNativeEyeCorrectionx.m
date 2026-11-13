function v = applyCoPsNativeEyeCorrectionx(v, eyeCal)
% Apply an optional CoPs pixel correction, leaving the saved raw samples alone.
if ~isfield(eyeCal,'correction') || ~eyeCal.correction.enabled
    return
end
c = eyeCal.correction;
for eye = 1:2
    rows = (eye-1)*3 + (1:2);
    v(rows,:) = (v(rows,:) - c.offsetPx(eye,:)') .* ...
        c.gain(eye,:)' + c.centerPx(:);
end
end
