function ex = initDisplayx(ex)
% Minimal display initialization for testing
% This function creates a basic Psychtoolbox window without hardware dependencies

disp('in initDisplayx - minimal display initialization')

% This initializer always opens a normal monoscopic stimulus window.
% Keep the saved settings consistent for calibration and trial drawing.
ex.setup.stereo.Display = false;
ex.setup.stereo.Mode = 0;

Screen('Preference', 'SkipSyncTests', 0);

% Query available screens before applying any machine-specific output
% mapping. The historical mapping below targets Psychtoolbox screen 1 and
% is invalid on ordinary single-display systems, which usually expose only
% screen 0. Explicit host mappings also apply to portable test runs.
availableScreens = Screen('Screens');
ex.setup.availableScreens = availableScreens;
isTestMode = isfield(ex.setup, 'testMode') && ex.setup.testMode;
% Retain the legacy fallback for callers without an explicit overlay setting.
% Toggling the desktop overlay must not change the stimulus output mapping.
useLabOutputMapping = ~isTestMode && ...
    ~isfield(ex.setup, 'showExperimenterOverlay');


if isfield(ex.setup, 'screenToHead') && ~isempty(ex.setup.screenToHead)
    mapping = ex.setup.screenToHead;
    if ~ismember(mapping(1), availableScreens)
        error('initDisplayx:MappedScreenUnavailable', ...
            'Configured PTB screen %d is unavailable. Available screen IDs: %s', ...
            mapping(1), mat2str(availableScreens));
    end
    Screen('Preference', 'ScreenToHead', mapping(1), mapping(2), mapping(3));
elseif useLabOutputMapping && ismember(1, availableScreens)
    Screen('Preference', 'ScreenToHead', 1, 1, 2);
    Screen('Preference', 'ScreenToHead', 1, 1, 2);
elseif useLabOutputMapping
    warning('initDisplayx:ScreenToHeadSkipped', ...
        ['Skipping the lab ScreenToHead mapping because Psychtoolbox ' ...
        'screen 1 is unavailable. Available screen IDs: %s'], ...
        mat2str(availableScreens));
end

% Use the highest-numbered available display, matching the prior behavior.
ex.setup.screenNum = max(availableScreens);

% Basic screen parameters (without hardware dependencies)
try
    % Portable tests default to a centered, bounded window so an error does
    % not take over the whole desktop. Fullscreen remains opt-in.
    openRect = [];
    useWindowedTest = isTestMode && ...
        (~isfield(ex.setup, 'fullscreen') || ~ex.setup.fullscreen);
    if useWindowedTest
        displayRect = Screen('Rect', ex.setup.screenNum);
        displaySize = displayRect(3:4) - displayRect(1:2);
        requestedSize = [1280 720];
        if isfield(ex.setup, 'windowSizePx')
            requestedSize = double(ex.setup.windowSizePx);
        end
        windowSize = min(requestedSize, max([320 240], floor(displaySize .* 0.8)));
        openRect = CenterRect([0 0 windowSize], displayRect);
    end

    % Open a basic window without stereo or special features.
    % discard pending stereo/DataPixx imaging tasks from earlier attempts
    PsychImaging('PrepareConfiguration');
    useWindowedOverlay = isfield(ex.setup, 'showExperimenterOverlay') && ...
        ex.setup.showExperimenterOverlay;
    if useWindowedOverlay
        ex = configureCoPsOverlayDisplayx(ex);
    end
    [ex.setup.window, ex.setup.screenRect] = PsychImaging( ...
        'OpenWindow', ex.setup.screenNum, 128, openRect);
    
    % Set basic screen parameters
    ex.setup.refreshRate = FrameRate(ex.setup.window);
    
    % Calculate fixation point center
    ex.fix.PCtr = [ex.setup.screenRect(3:4)]/2;
    
    % Set synch pulse position (top right corner)
    ex.synch.Pos = [ex.setup.screenRect(3)-ex.synch.PSz/2; 0];
    
    ex.setup.overlay = [];
    if useWindowedOverlay
        ex = openCoPsOverlayDisplayx(ex);
    end
    
    fprintf('✓ Basic window opened successfully\n');
    fprintf('  Screen size: %dx%d\n', ex.setup.screenRect(3), ex.setup.screenRect(4));
    fprintf('  Refresh rate: %.1f Hz\n', ex.setup.refreshRate);
    fprintf('  Fixation center: [%d, %d]\n', ex.fix.PCtr(1), ex.fix.PCtr(2));
    if useWindowedTest
        fprintf('  Display mode: windowed test (%dx%d)\n', ...
            ex.setup.screenRect(3) - ex.setup.screenRect(1), ...
            ex.setup.screenRect(4) - ex.setup.screenRect(2));
    end

    % Set blending function for transparency.
    Screen('BlendFunction', ex.setup.window, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
catch err
    closeCoPsDisplayx();
    fprintf('✗ Failed to open display window: %s\n', err.message);
    rethrow(err);
end

end
