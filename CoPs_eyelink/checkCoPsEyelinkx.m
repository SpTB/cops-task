function [passEye, trEye, lastEyePos] = checkCoPsEyelinkx(trEye, ex, freeViewing, tolerance)

% drain native samples without applying analog gains, offsets, or mirror
% signals

drained = false;
first = trEye.n +1;
while ~drained
    [samples, ~, drained] = Eyelink('GetQueuedData');
    [v, t] = decodeCoPsEyelinkSamplesx(samples, ...
        ex.setup.el.SAMPLE_TYPE, ex.setup.el.MISSING_DATA);
    % ignore pretrial samples, including any that arrived during queue
    % reset
    keep = t >= trEye.trackerStart;
    v = v(:,keep);
    t = t(keep);
    count = numel(t);
    if count > 0
        idx = trEye.n + (1:count);
        trEye.v(:, idx) = v;
        trEye.t(idx) = t;
        trEye.n = trEye.n + count;
    end
end

% these adc channels carry sync pulses only, on an independent clock
if isfield(ex.setup, 'dependencies') && ex.setup.dependencies.adcOn
    Datapixx('RegWrRd');
    status = Datapixx('GetAdcStatus');
    count = status.newBufferFrames;
    if count > 0
        idx = trEye.analog.n + (1:count);
        [trEye.analog.v(:,idx), trEye.analog.t(idx)] = ...
            Datapixx('ReadAdcBuffer', count, -1);
        trEye.analog.n = trEye.analog.n + count;
    end
end
lastEyePos = NaN(2,2);
passEye = false;
if trEye.n == 0
    return
end

% a disconnected link must not leave a previously valid gaze earning reward
sampleAge = GetSecs - (trEye.ptbStart + trEye.t(trEye.n) - trEye.trackerStart);
if sampleAge > 0.1
    return
end
% Keep Eye.v in the original tracker coordinates; only behavior uses the
% optional validation-derived pixel correction.
gaze = applyCoPsNativeEyeCorrectionx(trEye.v(:,trEye.n), ex.eyeCal);
lastEyePos = reshape(gaze([1 2 4 5]), 2, 2)';
idx = min(first, trEye.n):trEye.n;
gaze = applyCoPsNativeEyeCorrectionx(trEye.v(:,idx), ex.eyeCal);
x = mean(gaze([1 4],:), 1, 'omitnan');
y = mean(gaze([2 5],:), 1, 'omitnan');
within = isfinite(x) & isfinite(y) & ...
    abs(x - ex.fix.PCtr(1)) <= ex.fix.WinW * tolerance & ...
    abs(y - ex.fix.PCtr(2)) <= ex.fix.WinH * tolerance;
passEye = all(within) || logical(freeViewing) || logical(ex.passOn);
end
