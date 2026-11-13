function presentCoPsOverlayx(ex)
% Scale the experimenter canvas into its desktop window without waiting for VBL.
% A 30 Hz cap avoids updating this informational display on every stimulus flip.
persistent lastWindow lastUpdate
if ~isfield(ex.setup, 'overlayIsSeparate') || ~ex.setup.overlayIsSeparate
    return
end
now = GetSecs;
window = ex.setup.overlayWindow;
if isequal(window, lastWindow) && now - lastUpdate < 1 / ex.setup.overlayDisplayRateHz
    return
end
Screen('DrawTexture', window, ex.setup.overlay, [], Screen('Rect', window));
Screen('Flip', window, 0, 0, 2);
lastWindow = window;
lastUpdate = now;
end
