function ex = initDisplayxx(ex, overlayOn)
% Minimal display initialization for testing
% This function creates a basic Psychtoolbox window without hardware dependencies

arguments
    ex = struct
    overlayOn {mustBeNumericOrLogical} = false
end

ex.setup.screenNum = max(Screen('Screens'));

% initDisplay
PsychImaging('PrepareConfiguration');
PsychImaging('AddTask', 'General', 'UseDataPixx');

if ex.setup.stereo.Display
    Datapixx('EnableVideoStereoBlueline');
    Datapixx('RegWr');
end

Screen('Preference','ScreenToHead',1,1,2);
Screen('Preference','ScreenToHead',1,1,2);  % for some reason this has to be called twice
Screen('Preference', 'SkipSyncTests', 1);
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
    if overlayOn
        try
            [ex.setup.window, ex.setup.screenRect]=PsychImaging('OpenWindow',...
                ex.setup.screenNum, [], [], [], [], ex.setup.stereo.Mode,...
                ex.setup.stereo.Multisampling);
        catch
            [ex.setup.window, ex.setup.screenRect]=PsychImaging('OpenWindow',...
                ex.setup.screenNum, [], [], [], [], ex.setup.stereo.Mode,...
                ex.setup.stereo.Multisampling);
        end
        ex.setup.overlay = SetAnaglyphStereoParameters('CreateGreenOverlay',ex.setup.window);
    else
        [ex.setup.window, ex.setup.screenRect] = PsychImaging(...
            'OpenWindow', ex.setup.screenNum, 128,...
            [], ex.setup.stereo.Mode, ex.setup.stereo.Multisampling);
        ex.setup.overlay = [];%SetAnaglyphStereoParameters('CreateGreenOverlay',ex.setup.window);
    end
    % for monocular display use PLDAPS-type overlay
    % PsychImaging('AddTask', 'General', 'FloatingPoint32Bit');
    % PsychImaging('AddTask', 'General', 'EnableDataPixxM16OutputWithOverlay');
    % PsychImaging('AddTask', 'FinalFormatting', 'DisplayColorCorrection', 'SimpleGamma');
    % [ex.setup.window ex.setup.screenRect] = PsychImaging('OpenWindow',ex.setup.screenNum);

    % combinedClut = [ex.setup.Clut.monkey;ex.setup.Clut.human];
    % % open overlaywindow. Overlaywindow is a standard offscreen window except
    % % that it is a pure index window: it only has one color channel for values
    % % 0 to 255.  (Nonetheless it seems like Screen('Drawdots') needs a matrix
    % % of the color-indices: if col_n is an index vector of n dots, it has to be
    % % converted to into a n-by-3 matrix m= [col_n' * ones(1,3)]' )
    % ex.setup.overlay = PsychImaging('GetOverlayWindow', ex.setup.window);
    % Screen('LoadNormalizedGammaTable', ex.setup.window, combinedClut, 2);
    % tic
    % ex.setup.Clut.combined = combinedClut;
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
