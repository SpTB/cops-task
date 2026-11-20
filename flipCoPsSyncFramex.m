function [flipInfo, cursor, bit, index, phase] = flipCoPsSyncFramex(sync, cursor, active, setup, colors, previousVbl)
% Draw the patch last and flip it with the already-drawn stimulus.
[cursor, bit, index, phase] = advanceCoPsSyncx(sync, cursor, active);
low = colors.black; high = colors.white;
if isfield(sync,'lowColor'), low = sync.lowColor; end
if isfield(sync,'highColor'), high = sync.highColor; end
color = low + bit * (high-low);
Screen('FillRect', setup.window, color, sync.patchRect);
Screen('DrawingFinished', setup.window);
when = 0;
if isfinite(previousVbl), when = previousVbl + 0.5*sync.refreshIntervalSec; end
flipInfo = NaN(1,4);
[flipInfo(1),flipInfo(2),flipInfo(3),flipInfo(4)] = Screen('Flip', setup.window, when);
end
