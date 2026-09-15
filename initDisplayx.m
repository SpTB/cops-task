function ex = initDisplayx(ex)
% Minimal display initialization for testing
% This function creates a basic Psychtoolbox window without hardware dependencies

disp('in initDisplayx - minimal display initialization')

Screen('Preference','ScreenToHead',1,1,2);
Screen('Preference','ScreenToHead',1,1,2);  % for some reason this has to be called twice
Screen('Preference', 'SkipSyncTests', 1);
% Get screen number
ex.setup.screenNum = max(Screen('Screens'));

% Basic screen parameters (without hardware dependencies)
try
    % Open a basic window without stereo or special features
    [ex.setup.window, ex.setup.screenRect] = PsychImaging('OpenWindow', ex.setup.screenNum, 128);
    
    % Set basic screen parameters
    ex.setup.refreshRate = FrameRate(ex.setup.window);
    
    % Calculate fixation point center
    ex.fix.PCtr = [ex.setup.screenRect(3:4)]/2;
    
    % Set synch pulse position (top right corner)
    ex.synch.Pos = [ex.setup.screenRect(3)-ex.synch.PSz/2; 0];
    
    % Set overlay to empty (not used in minimal version)
    ex.setup.overlay = [];
    
    fprintf('✓ Basic window opened successfully\n');
    fprintf('  Screen size: %dx%d\n', ex.setup.screenRect(3), ex.setup.screenRect(4));
    fprintf('  Refresh rate: %.1f Hz\n', ex.setup.refreshRate);
    fprintf('  Fixation center: [%d, %d]\n', ex.fix.PCtr(1), ex.fix.PCtr(2));
    
catch err
    fprintf('✗ Failed to open display window: %s\n', err.message);
    rethrow(err);
end

% Set blending function for transparency
Screen('BlendFunction', ex.setup.window, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

end
