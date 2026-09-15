% White Grid on Black Background using Psychtoolbox
% Press any key to exit

try
    % Clear the workspace and screen
    sca;
    close all;
    clearvars;

    % Basic PTB setup
    PsychDefaultSetup(2);
    Screen('Preference', 'SkipSyncTests', 1); % Remove for real experiments
    screens = Screen('Screens');
    screenNumber = max(screens);

    % Define colors
    white = WhiteIndex(screenNumber);
    black = BlackIndex(screenNumber);

    % Open fullscreen window
    [window, windowRect] = PsychImaging('OpenWindow', screenNumber, black);

    % Get screen size
    [screenXpixels, screenYpixels] = Screen('WindowSize', window);

    % ---------- GRID PARAMETERS ----------
    gridSpacing = 50;   % pixels between grid lines
    lineWidth   = 2;     % thickness of grid lines
    % -------------------------------------

    % Generate vertical line coordinates
    xPositions = 0:gridSpacing:screenXpixels;
    for x = xPositions
        Screen('DrawLine', window, white, x, 0, x, screenYpixels, lineWidth);
    end

    % Generate horizontal line coordinates
    yPositions = 0:gridSpacing:screenYpixels;
    for y = yPositions
        Screen('DrawLine', window, white, 0, y, screenXpixels, y, lineWidth);
    end

    % Flip to screen
    Screen('Flip', window);

    % Wait for key press
    KbStrokeWait;

    % Close screen
    sca;

catch ME
    sca;
    rethrow(ME);
end