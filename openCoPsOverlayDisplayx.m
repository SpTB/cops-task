function ex = openCoPsOverlayDisplayx(ex)
% Open an independent GUI overlay, including across Linux X screens.
% The full-size offscreen canvas preserves all stimulus-pixel coordinates.

oldVRAM = Screen('Preference', 'ConserveVRAM');
oldSkip = Screen('Preference', 'SkipSyncTests');
restorePreferences = onCleanup(@() restoreDisplayPreferences(oldVRAM, oldSkip));
% Linux X screens cannot share OpenGL contexts. Disable sharing only while
% opening this window; all task textures still belong to the stimulus window.
Screen('Preference', 'ConserveVRAM', bitor(oldVRAM, 32));
% This GUI is informational; the main display retains its strict sync checks.
Screen('Preference', 'SkipSyncTests', 2);
ex.setup.overlayWindow = Screen('OpenWindow', ex.setup.overlayScreen, ...
    ex.idx.bg, ex.setup.overlayWindowRect, [], [], [], [], [], kPsychGUIWindow);
canvasRect = [0 0 ex.setup.screenRect(3:4) - ex.setup.screenRect(1:2)];
ex.setup.overlay = Screen('OpenOffscreenWindow', ex.setup.overlayWindow, ...
    ex.idx.bg, canvasRect, [], 32);
ex.setup.overlayIsSeparate = true;
ex.setup.overlayDisplayRateHz = 30;
end

function restoreDisplayPreferences(oldVRAM, oldSkip)
Screen('Preference', 'ConserveVRAM', oldVRAM);
Screen('Preference', 'SkipSyncTests', oldSkip);
end
