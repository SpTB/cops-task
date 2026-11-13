function ex = initDisplayxx(ex, overlayOn)
% Initialize the DataPixx stimulus display and optional desktop overlay.

arguments
    ex = struct
    overlayOn {mustBeNumericOrLogical} = false
end

ex.setup.screenNum = max(Screen('Screens'));

% initDisplay
PsychImaging('PrepareConfiguration');
PsychImaging('AddTask', 'General', 'UseDataPixx');
if overlayOn
    ex = configureCoPsOverlayDisplayx(ex);
end

if ex.setup.stereo.Display
    Datapixx('EnableVideoStereoBlueline');
    Datapixx('RegWr');
end

if isfield(ex.setup, 'screenToHead') && ~isempty(ex.setup.screenToHead)
    mapping = ex.setup.screenToHead;
    Screen('Preference', 'ScreenToHead', mapping(1), mapping(2), mapping(3));
else
    Screen('Preference','ScreenToHead',1,1,2);
    Screen('Preference','ScreenToHead',1,1,2);  % legacy lab mapping
end
Screen('Preference', 'SkipSyncTests', 0);
% Get screen number
ex.setup.screenNum = max(Screen('Screens'));

% Basic screen parameters (without hardware dependencies)

if ex.setup.stereo.Display
    disp('cumming mode')
    Datapixx('SetPropixxDlpSequenceProgram' , 1);  % 1: Cumming3D mode; 0 back to normal
    Datapixx('RegWr');
    disp('checking datapixx')
    Datapixx('isready')
    
    ex.setup.stereo.Mode = 8; % in case the wrong mode was set
    [ex.setup.window, ex.setup.screenRect] = PsychImaging('OpenWindow', ...
        ex.setup.screenNum, ex.idx.bg, [], [], [], ex.setup.stereo.Mode, ...
        ex.setup.stereo.Multisampling);
else
    [ex.setup.window, ex.setup.screenRect] = PsychImaging('OpenWindow', ...
        ex.setup.screenNum, ex.idx.bg);
end
ex.setup.overlay = [];
if overlayOn
    ex = openCoPsOverlayDisplayx(ex);
end

% Set blending function for transparency
Screen('BlendFunction', ex.setup.window, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

%%% store settings and define position of fixation point and photodiode synch
%%% pulse %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
ex.setup.refreshRate = FrameRate(ex.setup.window);
ex.fix.PCtr = [ex.setup.screenRect(3:4)]/2;
% ex.synch.Pos = [ex.setup.screenRect(3)-ex.synch.PSz/2;0]; % right top corner
ex.synch.Pos = [ex.synch.PSz/2; ex.synch.PSz/2]; % left top

% if ex.setup.stereo.Display
%     % Initially fill left- and right-eye image buffer with gray background
%     % color:
%     Screen('SelectStereoDrawBuffer', ex.setup.window, 0);
%     Screen('FillRect', ex.setup.window, ex.idx.bg_lum);
%     Screen('SelectStereoDrawBuffer', ex.setup.window, 1);
%     Screen('FillRect', ex.setup.window, ex.idx.bg_lum);
%
%     Screen('Flip', ex.setup.window);
% end

end
