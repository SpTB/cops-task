function [passEye, trEye, lastEyePos, sample] = sampleCoPsBenchInputx( ...
    ~, trEye, ex, passEye, freeViewing, lastEyePos, toleranceScalar)
% Read the actual eye/photodiode ADC path, then substitute a timed gaze trace.
% Called only by the isolated runners built by makeCoPsBenchRunnerx.

pollStart = GetSecs;
before = trEye.n;
[~, trEye, lastEyePos, io] = readCoPsBenchAdcx( ...
    trEye, ex, passEye, freeViewing, lastEyePos, 0, 0, toleranceScalar);
[mouseX, mouseY] = GetMouse(ex.setup.window);
cfg = ex.setup.hardwareBench;
inGO = isfinite(cfg.goStart);
step = 1;
position = ex.fix.PCtr;
if inGO
    elapsed = max(0, pollStart - cfg.goStart);
    step = min(numel(cfg.targetPositions), 1 + floor(elapsed * cfg.targetHz));
    position = cfg.targetPositions(step).targ1.pos_abs;
end
if isempty(ex.eyeCal.LXPos)
    lastEyePos = position;
    overlay = [position; mouseX mouseY];
else
    lastEyePos = [position; position];
    overlay = [lastEyePos; position; mouseX mouseY];
end
within = all(abs(position - ex.fix.PCtr) <= [ex.fix.WinW ex.fix.WinH] * toleranceScalar);
passEye = logical(freeViewing) || within;
rect = ex.setup.screenRect;
sample = struct('source','hardwareBench','position',position, ...
    'pointerPosition',[mouseX mouseY], ...
    'overlayPositions',overlay, ...
    'inBounds',all(isfinite(position)) && position(1)>=rect(1) && position(1)<=rect(3) && ...
        position(2)>=rect(2) && position(2)<=rect(4), ...
    'timestamp',pollStart);
sample.benchPoll = [pollStart GetSecs trEye.n-before trEye.n inGO position step ...
    io.underflow io.overflow value(io.status,'numStreamOverflows') ...
    value(io.status,'numStreamUnderflows')];
end

function out = value(s, key)
out = NaN;
if isfield(s,key), out=double(s.(key)); end
end
