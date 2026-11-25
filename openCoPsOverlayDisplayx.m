function ex = openCoPsOverlayDisplayx(ex)
% Open an independent GUI overlay, including across Linux X screens.
% Linux previews render in a separate process; legacy platforms can use inline.

backend = 'auto';
if isfield(ex.setup,'overlayBackend'), backend = char(ex.setup.overlayBackend); end
analog = isfield(ex.setup,'inputMode') && strcmp(ex.setup.inputMode,'eye');
isX11 = isunix && ~ismac && ~isempty(getenv('DISPLAY')) && ...
    ~strcmpi(getenv('XDG_SESSION_TYPE'),'wayland');
if strcmp(backend,'auto')
    backend = 'inline';
    if isX11 && usejava('jvm') && ~analog, backend = 'process'; end
end
ex.setup.overlayBackend = backend;
ex.setup.overlayDisplayRateHz = 30;
ex.setup.overlayOpenedAt = GetSecs;
ex.setup.overlayBackgroundColor = ex.idx.bg;
if strcmp(backend,'process')
    if ~isX11 || ~usejava('jvm')
        error('CoPs:OverlayPlatform','The process preview requires Linux X11 and MATLAB''s JVM.');
    end
    if analog
        error('CoPs:OverlayAnalog','Use overlayBackend="inline" for legacy analog calibration.');
    end
    ex.setup.overlayViewer = coPsOverlayProcessx('open',ex.setup);
    % Retain a compatibility canvas on the stimulus context, without opening
    % another PTB onscreen window or touching a second OpenGL context.
    canvasRect = [0 0 ex.setup.screenRect(3:4)-ex.setup.screenRect(1:2)];
    ex.setup.overlay = Screen('OpenOffscreenWindow',ex.setup.window,ex.idx.bg,canvasRect,[],32);
    ex.setup.overlayWindow = [];
    ex.setup.overlayIsSeparate = true;
    fprintf('CoPs overlay: separate viewer process %d, latest-only UDP at up to 30 Hz.\n',ex.setup.overlayViewer.pid);
    return
end

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
ex.setup.overlayOpenedAt = GetSecs;
windowRect = Screen('Rect', ex.setup.overlayWindow);
ex.setup.overlayCanvasSizePx = windowRect(3:4) - windowRect(1:2);
ex.setup.overlayScale = ex.setup.overlayCanvasSizePx ./ ...
    (ex.setup.screenRect(3:4) - ex.setup.screenRect(1:2));
textSize = Screen('TextSize', ex.setup.overlay);
Screen('TextSize', ex.setup.overlayWindow, max(1, round(textSize*min(ex.setup.overlayScale))));
end

function restoreDisplayPreferences(oldVRAM, oldSkip)
Screen('Preference', 'ConserveVRAM', oldVRAM);
Screen('Preference', 'SkipSyncTests', oldSkip);
end
