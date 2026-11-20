function drawCoPsIdleSyncx(ex)
% Maintain a black photodiode baseline outside binary playback.
if isfield(ex.exp.CoPs, 'sync') && strcmp(ex.exp.CoPs.sync.mode, 'binary')
    sz = ex.synch.PSz;
    r = ex.setup.screenRect;
    Screen('FillRect', ex.setup.window, ex.idx.black, [r(3)-sz r(4)-sz r(3) r(4)]);
end
end
