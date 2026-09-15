
%% --------------------------------------------------------------
% Minimal Psychtoolbox mouse-tracking test using current screen setup
% --------------------------------------------------------------

try
    % Example: you must define these the same way your experiment does
    % ---------------------------------------------------------------
    % If they already exist in your workspace (e.g., after loading ex),
    % then delete this block.
    %
    % ex.setup.screenRect = [0 0 1920 1080];
    % ex.setup.window = [];  % placeholder
    % ex.idx.bg_lum = 0.5;   % 0–1 background luminance
    % ---------------------------------------------------------------
    
    Screen('Preference','SkipSyncTests',1); % test mode
    
    % Open PTB window exactly matching your experiment
    bgColor = ex.idx.bg_lum * [255 255 255];
    [win, winRect] = Screen('OpenWindow', max(Screen('Screens')), bgColor, ex.setup.screenRect);
    ex.setup.window = win;
    
    Screen('TextSize', win, 26);
    
    % Input unification
    KbName('UnifyKeyNames');
    escKey = KbName('ESCAPE');
    
    disp('Mouse-tracking test running...');
    disp('Move the mouse. Press ESC to quit.');
    
    while true
        
        % --- Get mouse coordinates exactly as your task does ---
        [mx, my, buttons] = GetMouse(win);
        
        % Print to command line (optional)
        fprintf('Mouse X: %4d   Y: %4d\n', mx, my);
        
        % Draw coordinates inside your PTB window
        Screen('FillRect', win, bgColor);
        DrawFormattedText(win, sprintf('X = %d\nY = %d', mx, my), ...
            'center', 'center', [255 255 255]);
        
        % Draw a dot where the mouse is
        Screen('DrawDots', win, [mx my], 12, [255 0 0], [], 2);
        
        Screen('Flip', win);
        
        % Quit on ESC
        [~,~,kc] = KbCheck;
        if kc(escKey)
            break;
        end
        
        WaitSecs(0.01);
        
    end
    
    Screen('CloseAll');
    ShowCursor;
    
catch err
    Screen('CloseAll');
    ShowCursor;
    rethrow(err);
end
