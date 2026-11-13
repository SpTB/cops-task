function ex = configureCoPsOverlayDisplayx(ex)
% Choose a separate monitor and a bounded experimenter window.

screens = Screen('Screens');
otherScreens = screens(screens ~= ex.setup.screenNum);
if isfield(ex.setup, 'overlayScreen') && ~isempty(ex.setup.overlayScreen)
    overlayScreen = ex.setup.overlayScreen;
    validateattributes(overlayScreen, {'numeric'}, ...
        {'scalar', 'integer', 'nonnegative', 'finite'});
else
    if isempty(otherScreens)
        error('configureCoPsOverlayDisplayx:NoSeparateScreen', ...
            ['The experimenter overlay needs a separate PTB screen. ' ...
            'Connect the stimulus display, or use overlayOn=0.']);
    end
    overlayScreen = min(otherScreens);
end
if ~ismember(overlayScreen, otherScreens)
    error('configureCoPsOverlayDisplayx:InvalidScreen', ...
        'overlayScreen must be an available screen other than stimulus screen %d.', ...
        ex.setup.screenNum);
end

desktopRect = Screen('Rect', overlayScreen);
desktopSize = desktopRect(3:4) - desktopRect(1:2);
stimulusRect = Screen('Rect', ex.setup.screenNum);
stimulusSize = stimulusRect(3:4) - stimulusRect(1:2);
requestedSize = [960 540];
if isfield(ex.setup, 'overlayWindowSizePx')
    requestedSize = ex.setup.overlayWindowSizePx;
end
validateattributes(requestedSize, {'numeric'}, ...
    {'size', [1 2], 'integer', 'positive', 'finite'});
% Preserve the stimulus aspect ratio and leave desktop space around the window.
scale = min([requestedSize ./ stimulusSize, 0.8 * desktopSize ./ stimulusSize]);
windowSize = max([1 1], floor(stimulusSize * scale));
overlayRect = CenterRect([0 0 windowSize], desktopRect);

ex.setup.overlayScreen = overlayScreen;
ex.setup.overlayWindowRect = overlayRect;
end
