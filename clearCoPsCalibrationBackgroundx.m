function clearCoPsCalibrationBackgroundx(ex, backgroundColor, clearOverlay)
% Clear calibration/validation backgrounds without relying on buffer state.
% Keep the overlay when its fixed validation guides have already been drawn.
if nargin < 3
    clearOverlay = true;
end
if isfield(ex.setup, 'stereo') && ex.setup.stereo.Display
    for eye = 0:1
        Screen('SelectStereoDrawBuffer', ex.setup.window, eye);
        Screen('FillRect', ex.setup.window, backgroundColor);
    end
else
    Screen('FillRect', ex.setup.window, backgroundColor);
end
if clearOverlay && isfield(ex.setup, 'overlay') && ~isempty(ex.setup.overlay)
    Screen('FillRect', ex.setup.overlay, backgroundColor);
end
end
