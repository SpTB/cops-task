function ex = getDefaultSettingsx(ex, skipQuests, defaults, options)

% modified version of getDefaultSettings with added arg skipQuests for skipping the innitional questionnaire during testing.

% Default values:
% ex.setup.recording = 0;
% ex.Header.experimenter = 'xx'; ex.setup.filePrefix = 'test'
% ex.setup.el.binoc = 1;
% ex.setup.motionDetector.on = 0

% history
% 12/04/25  wz: created by adding skipQuests argument (defaults to yes for now) and an argument block
% xx create a helper func to fill this? Maybe just easier to go through the questionnaire at that point...
arguments
    ex struct
    skipQuests {mustBeNumericOrLogical} = true
    defaults struct = struct( ...
        'recording', false, ... % neural recording
        'experimenter',  "xx", ... % experimenter initials
        'filePrefix',  "test",... % monkey name (2letters)
        'binoc', 1,... % binocular defaults, 'false' for monocular
        'motionDetector', false... %whether to initiate motion detection
        );
    options.initializeAdc {mustBeNumericOrLogical} = true
    
end

%% %%%%%%%%%%%%%%%%%%%%%%%%%%%% make the experimental control structure
ex.finish = 300;  % last trial
ex.quit = 0; % 0 = continue, 1 = pause, 2 = quit,
ex.passOn = 0;
ex.freeViewing = 0;
ex.reward.time = 0.15;
ex.reward.earlyRewardTime = 0.08;
ex.reward.includeBigReward = 1;
ex.reward.juice_proportion = NaN; % accommodating Bharath's changes
ex.reward.scale = 1;  % scales the reward size down following shakes
ex.reward.nTrialsAfterShake = inf; % counter to check how many trials back the monkey was shaking; default inf, i.e. no recent shake.
ex.reward.nTrialsThreshold = 5; % number of trials after a shakebefore reward is set back to default
ex.reward.scaleStepSize = 0.05; % step size by which we increase rewards after shakes
ex.reward.type = 'sequential'; % default

%% --------------------setup parameters----------------------------------
%% -----------------------------------------------------------------------
ex.setup.eyePSz = 6;   % eye point (cursor) size
ex.setup.computerName = getComputerName;
ex.setup.horEyeSign = 1; % set to -1 to account for the hot-mirror

% stereo setup parameters
ex.setup.stereo.Display = 1; % 1 for stereo Setup, 0 for  mono display (no stereo)
ex.setup.stereo.Mode = 8;   %1: use hardware stereo (frame alternating stereo)
%8: anaglyph stereo: red channel:  left
%                    blue channel: right
ex.setup.stereo.Multisampling = 8;  % anti-aliasing; option included starting 0/25/17
% 0 means no anti-aliasing used


% grapevine parameters
ex.setup.gv.elec = 1;  % channel IDs that should be read out online
ex.setup.gv.readLFP = 0; % do not read out the online LFP for single channels by default

% color indices for stereo setup------------------------------------------
ex.idx.bg = 128;
ex.idx.bg_lum = 128;
ex.idx.white = 255;
ex.idx.black = 0;
% for the stereo setup we only have one salient color for the overlay
% which only is visible when the background is not black.
ex.idx.overlay = 255;

% -------------------------------------------------------------------------
% setup for NIH rig 1 on linux-machine
% -------------------------------------------------------------------------
if strcmpi(ex.setup.computerName,'hn-stim-1')
    
    % RIG B
    %ex.setup.viewingDistance = 57.5; % Mango measured on 09/28/22
    %ex.setup.monitorWidth = 46;
    
    % 09/28/22: changed the screen distance to hopefully get mango to do
    % the task
    ex.setup.viewingDistance = 57.5;
    ex.setup.monitorWidth = 46;
    
    ex.setup.mouseXOffset = 0 ;
    ex.setup.dirRoot = '/usr/data';
    
    % for Datapixx the Buffer size has to be <1e6 for binocular signals; for Propixx 1e7 works
    ex.setup.adc.NumBufferFrames = 9e5;  % large number for lots of buffer space
    
elseif strcmpi(ex.setup.computerName,'lab-ms-98h9') % dome in Leopold lab
    
    ex.setup.viewingDistance = 104; % dome in Leopold lab
    %ex.setup.monitorWidth = 326.73;
    ex.setup.monitorWidth = 357.45;
    
    ex.setup.mouseXOffset = 0 ;
    ex.setup.horEyeSign = -1; % to flip sign of horizontal eye position when using hot mirror
    ex.setup.dirRoot = '/home/lab/Desktop/data';
    
    % for Datapixx the Buffer size has to be <1e6 for bino
    % monocular signals; for Propixx 1e7 works
    ex.setup.adc.NumBufferFrames = 9e5;  % large number for lots of buffer space
    
    % currently we only have monocular display
    ex.setup.stereo.Display = false; % 1 for stereo Setup, 0 for  mono display (no stereo)
    ex.setup.stereo.Mode = NaN;   %1: use hardware stereo (frame alternating stereo)
    %8: anaglyph stereo: red channel:  left
    %                    blue channel: right
    ex.setup.stereo.Multisampling = NaN;  % anti-aliasing; option included starting 0/25/17
    % 0 means no anti-aliasing used
    
    
    ex.idx.bg         = .5; % midgray background (colors go from 0 to 1)
    
    %% calibration file for display geometrycorrection
    ex.setup.warpingCalibrationFile = fullfile(ex.setup.VSdirRoot ,...
        '../setupFiles/DisplayCalibrationFiles/', ...
        'calibBusseProcess_20240729_Completed-draft1.mat');
    if ~exist(ex.setup.warpingCalibrationFile,"file")
        [fileN,pathN] = uigetfile('*.mat','Select a display warping calibration file');
        ex.setup.warpingCalibrationFile = fullfile(pathN,fileN);
    end
    
    % we set the CLUTs in initDisplay.m
    
    
elseif strcmpi(ex.setup.computerName,'klab-mouse-3')
    
    % NEI Rig A
    %ex.setup.viewingDistance = 46; % LEM measured on 12/02/20
    %ex.setup.monitorWidth = 68;
    
    ex.setup.viewingDistance = 45; % LEM measured on 11/03/22
    ex.setup.monitorWidth = 66;
    
    ex.setup.mouseXOffset = 0 ;
    ex.setup.dirRoot = '/usr/data';
    
    % for Datapixx the Buffer size has to be <1e6 for bino
    % monocular signals; for Propixx 1e7 works
    ex.setup.adc.NumBufferFrames = 9e5;  % large number for lots of buffer space
    
    
    % temporary to test Vpixx Linux machine
elseif strcmpi(ex.setup.computerName,'vpixx')
    
    % NEI RIG E
    ex.setup.viewingDistance = 58; % Kaki/Lychee
    ex.setup.monitorWidth = 47;%38.5; original (up to June 4, 2026)
    
    ex.setup.mouseXOffset = 0 ;
    ex.setup.dirRoot = '/media/vpixx/DATA/CoPs/';%/home/vpixx/data';
    
    % for Datapixx the Buffer size has to be <1e6 for bino
    % monocular signals; for Propixx 1e7 works
    ex.setup.adc.NumBufferFrames = 9e5;  % large number for lots of buffer space
    
    % -------------------------------------------------------------------------
    % old setup for rig 2 (two projection-design projectors); now obsolete ----
    % -------------------------------------------------------------------------
    % elseif strcmpi(ex.setup.computerName,'hns-mac-pro-OBSOLETE.cin.medizin.uni-tuebingen.de') || ...
    %         strcmpi(ex.setup.computerName,'hns-mac-pro-OBSOLETE.local')
    %     ex.setup.viewingDistance = 97; % until changes on 1/10/15
    %     ex.setup.viewingDistance = 149; % starting on 1/10/15
    %     ex.setup.monitorWidth = 59;
    %     ex.setup.mouseXOffset = 1920;
    %     ex.setup.dirRoot = '/Users/nienborg_group1/CIN_local/data';
    %
    %     % for Datapixx the Buffer size has to be <1e6 for binocular signals; for Propixx 1e7 works
    %     ex.setup.adc.NumBufferFrames = 9e5;  % large number for lots of buffer space
    % 11/24/15  pump in rig 2 at 4 (0.5 reward Time corresponds to 0.01ml/trial)
    
    % -------------------------------------------------------------------------
    % setup for rig 1 (Propixx projector) ---------------------- now obsolete
    % -------------------------------------------------------------------------
elseif strcmpi(ex.setup.computerName,'hns-mac-pro1.cin.medizin.uni-tuebingen.de') || ...
        strcmpi(ex.setup.computerName,'hns-mac-pro1.local') || ...
        strcmpi(ex.setup.computerName,'nienborg-groups-mac-pro.local')
    ex.setup.viewingDistance = 97.5; % Mango in cm
    ex.setup.monitorWidth = 56;
    ex.setup.mouseXOffset = 1920;
    ex.setup.dirRoot = '/Users/nienborg_group/CIN_local/data';
    
    % for Datapixx the Buffer size has to be <1e6 for binocular signals; for Propixx 1e7 works
    ex.setup.adc.NumBufferFrames = 9e6;  % large number for lots of buffer space
    % 11/24/15  pump in rig 1 at 10 (0.15 reward Time corresponds to 0.01ml/trial)
    
    % if ~ running in stereo mode use PLDAPS type setup
    if ~ex.setup.stereo.Display
        %% CLUTs:
        ex.setup.Clut.monkey = [0.5,0.5,0.5;0.5,0.5,0.5;0.5,0.5,0.5;0.5,0.5,0.5;0.5,0.5,0.5;linspace(0, 1, 251)' * [1, 1, 1]];
        ex.setup.Clut.human =  [0.5,0.5,0.5;1 1 1      ;1,0,0      ;0,1,0      ;0,0,1      ;linspace(0, 1, 251)' * [1, 1, 1]];
        
        %%% keeping track of which color is which
        % idx to the bg color; this is the only value that needs to be changed;
        % the overlay luminance values get automatically updated below.
        ex.idx.bg = 130;
        ex.idx.bg_lum   = ex.Clut.monkey(ex.idx.bg+1,1);  % luminance level of bg
        ex.idx.cursor     = 100;
        ex.idx.window     = 200;
        ex.idx.fixation   = 255;
        ex.idx.white      = 255;
        ex.idx.black      = 5;
        ex.idx.overlayBlue = 4;
        ex.idx.overlayGreen = 3;
        ex.idx.overlayRed = 2;
        ex.idx.overlayWhite = 1;
        ex.idx.overlay = ex.idx.overlayRed;
        
        ex.setup.Clut.monkey(1,:) = ex.setup.Clut.monkey(ex.idx.bg+1,1); % first line in both Cluts corresponds to bg
        ex.setup.Clut.human(1,:) = ex.setup.Clut.human(ex.idx.bg+1,1);
        ex.setup.Clut.monkey(1:5,:) = ex.setup.Clut.monkey(ex.idx.bg+1,1);  % make overlaycolor is same as bg
    end
    % -------------------------------------------------------------------------
    % NEW setup for rig 2 (Propixx projector) ---------------------- obsolete
    % -------------------------------------------------------------------------
elseif strcmpi(ex.setup.computerName,'hns-mac-pro-2.cin.medizin.uni-tuebingen.de') ||...
        strcmpi(ex.setup.computerName,'hns-mac-pro-2.local')
    ex.setup.viewingDistance = 103; % Mango in cm
    ex.setup.monitorWidth = 53.5;
    ex.setup.mouseXOffset = 1920;
    ex.setup.dirRoot = '/Users/nienborg_group1/CIN_local/data';
    %ex.online.rootName = '/Users/nienborg_group/CIN_share';  % obsolete
    % for Datapixx the Buffer size has to be <1e6 for binocular signals; for Propixx 1e7 works
    ex.setup.adc.NumBufferFrames = 9e6;  % large number for lots of buffer space
    
    % if ~ running in stereo mode use PLDAPS type setup
    if ~ex.setup.stereo.Display
        %% CLUTs:
        ex.setup.Clut.monkey = [0.5,0.5,0.5;0.5,0.5,0.5;0.5,0.5,0.5;0.5,0.5,0.5;0.5,0.5,0.5;linspace(0, 1, 251)' * [1, 1, 1]];
        ex.setup.Clut.human =  [0.5,0.5,0.5;1 1 1      ;1,0,0      ;0,1,0      ;0,0,1      ;linspace(0, 1, 251)' * [1, 1, 1]];
        %%% keeping track of which color is which
        
        % idx to the bg color; this is the only value that needs to be changed;
        % the overlay luminance values get automatically updated below.
        ex.idx.bg = 130;
        ex.idx.bg_lum   = ex.Clut.monkey(ex.idx.bg+1,1);  % luminance level of bg
        ex.idx.cursor     = 100;
        ex.idx.window     = 200;
        ex.idx.fixation   = 255;
        ex.idx.white      = 255;
        ex.idx.black      = 5;
        ex.idx.overlayBlue = 4;
        ex.idx.overlayGreen = 3;
        ex.idx.overlayRed = 2;
        ex.idx.overlayWhite = 1;
        ex.idx.ovrlay = ex.idx.overlayRed;
        
        ex.setup.Clut.monkey(1,:) = ex.setup.Clut.monkey(ex.idx.bg+1,1); % first line in both Cluts corresponds to bg
        ex.setup.Clut.human(1,:) = ex.setup.Clut.human(ex.idx.bg+1,1);
        ex.setup.Clut.monkey(1:5,:) = ex.setup.Clut.monkey(ex.idx.bg+1,1);  % make overlaycolor is same as bg
    end
else
    isTestMode = isfield(ex.setup, 'testMode') && ex.setup.testMode;
    hasTestGeometry = isfield(ex.setup, 'viewingDistance') && ...
        isfield(ex.setup, 'monitorWidth');

    if isTestMode && hasTestGeometry
        fprintf(['CoPs test display geometry (not calibrated): %.1f cm viewing ' ...
            'distance, %.1f cm monitor width.\n'], ...
            ex.setup.viewingDistance, ex.setup.monitorWidth);
    else
        warndlg([ex.setup.computerName ': host machine not known, viewing distance not calibrated'])
        ex.setup.viewingDistance = 100; % preliminary values; measure these
        ex.setup.monitorWidth = 50;
    end
end

%%%%%%%%%%%%%%%%%%%%%% ask user whether we are recording, check connection, get grid location
if skipQuests
    ex.setup.recording =  defaults.recording;
else
    button = questdlg('are we recording neural data?','','yes','no','no');
    switch button
        case 'yes'
            ex.setup.recording = 1;
            ex.setup.gv.cl = [0 1 2];
            ex.setup.gv.recording = 0;
        case 'no'
            ex.setup.recording = 0;
        case 'cancel'
            disp('forced exit: please respond whether we are running a recording session when starting VisStim');
            return
    end
end
if ex.setup.recording == true
    ex.readOnlineSpikes = true;
end

%%%%%%%%%%%%%%%%%%%%%%% get experimenter initials
if skipQuests
    ex.Header.experimenter = defaults.experimenter;
else
    initials = getExperimenterInitialsVS(ex);
    ex.Header.experimenter = initials;
end
%%%%%%%%%%%%%%%%%%%%%%% get monkey name
if skipQuests
    ex.setup.filePrefix = defaults.filePrefix;
else
    animalPrefix = inputdlg('Enter first two letters of monkey name','Subject');
    if length(animalPrefix{1})<2
        animalPrefix{1} = 'xx';
    end
    ex.setup.filePrefix = lower(animalPrefix{1}(1:2));
    switch lower(ex.setup.filePrefix)
        case 'ki'
            ex.Header.animal = 'kiwi';
        case 'ma'
            ex.Header.animal = 'mango';
        case 'le'
            ex.Header.animal = 'lemieux';
        case 'ba'
            ex.Header.animal = 'barnum';
        case 'sh'
            ex.Header.animal = 'shocktop';
        case 'hu'
            ex.Header.animal = 'hummus';
        case 'te'
            ex.Header.animal = 'tempura';
        case 'ta'
            ex.Header.animal = 'tamago';
        case 'jo'
            ex.Header.animal = 'jocamo';
        case 'ka'
            ex.Header.animal = 'kaki';
        case 'ly'
            ex.Header.animal = 'lychee';
        otherwise
            ex.Header.animal = 'test';
    end
end
%%%%%%%%%%%%%%%%%%%%%% check whether we have a connection to ripple
if ex.setup.recording
    sendStrobe(1);% for debugging
    xippmex('digin');
    getStrobes;
    testS = 1;
    sendStrobe(testS); % sending a test
    pause(.1)
    a = getStrobes;
    if length(a)<1 || a(1)~=testS
        disp('%%% faulty digital connection with grapevine NIP');
        disp('%%% if you want to run a recording session check the following:');
        disp('%%% -is the datapixx (propixx controller) switched on?');
        disp('%%% -did you check the box "Capture input on parallel bit change" in the trellis Digital I/O Options?')
        disp('%%% -is the NIP running?');
        disp('%%% -are all the grapevine digital I/O connectors connected correctly?')
        disp('%%% -is the Nienborg Active Pump Trigger (made by Jonathan Newport for reward) on power?')
        error('faulty digital connection with grapevine NIP;')
    end
    %%
    button = questdlg('are we recording microwire brush arrays (MBA)?' ...
        ,'','yes','no','no');
    ex.setup.gv.probe.type = '';
    
    switch button
        case 'yes'
            ex = userInput(ex,'MBA');
            ex.setup.probe.type = 'MBA';
        otherwise
            
            promt = {'how many electrodes (probes):'};
            dlg_title = '# electrodes (probes)';
            num_lines = 1;
            def = {'1'};
            answer = inputdlg(promt,dlg_title,num_lines,def);
            if ~isempty(answer)
                num_probes = str2double(answer{1});
            end
            if ~isnumeric(num_probes)
                promt = {'how many electrodes (probes); (integer value) :'};
                dlg_title = '# electrodes (probes)';
                num_lines = 1;
                def = {'1'};
                answer = inputdlg(promt,dlg_title,num_lines,def);
                if ~isempty(answer)
                    num_probes = str2double(answer{1});
                end
            end
            if ~isnumeric(num_probes)
                num_probes = 1;
                warndlg('input undefined; setting num_probes to default value 1');
            end
            
            
            % get grid position
            %%
            for n=1:num_probes
                promt = {'hemisphere (L, R, B(both)):','grid location; enter x-position:','grid location; enter y-position'};
                dlg_title = ['probe #' num2str(num_probes)];
                num_lines = 1;
                def = {'L','100','100'};
                answer = inputdlg(promt,dlg_title,num_lines,def);
                % hn: 05/05=3/18: check whether it works
                if ~isempty(answer)
                    if strcmpi(answer{1},'l')
                        ex.setup.leftHemisphereRecorded = 1;
                        ex.setup.rightHemisphereRecorded = 0;
                        ex.setup.Left_Hemisphere_gridX = str2num(answer{2});
                        ex.setup.Left_Hemisphere_gridY = str2num(answer{3});
                        ex.setup.gv.probe(n).leftHemisphereRecorded = 1;
                        ex.setup.gv.probe(n).rightHemisphereRecorded = 0;
                        ex.setup.gv.probe(n).gridX = str2num(answer{2});
                        ex.setup.gv.probe(n).gridY = str2num(answer{3});
                    elseif strcmpi(answer{1},'r')
                        ex.setup.leftHemisphereRecorded = 0;
                        ex.setup.rightHemisphereRecorded = 1;
                        ex.setup.Right_Hemisphere_gridX = str2num(answer{2});
                        ex.setup.Right_Hemisphere_gridY = str2num(answer{3});
                        ex.setup.gv.probe(n).leftHemisphereRecorded = 0;
                        ex.setup.gv.probe(n).rightHemisphereRecorded = 1;
                        ex.setup.gv.probe(n).gridX = str2num(answer{2});
                        ex.setup.gv.probe(n).gridY = str2num(answer{3});
                    elseif strcmpi(answer{1},'b')
                        ex.setup.leftHemisphereRecorded = 1;
                        ex.setup.Right_Hemisphere_gridX = [];
                        ex.setup.Right_Hemisphere_gridY = [];
                        ex.setup.Left_Hemisphere_gridX = [];
                        ex.setup.Left_Hemisphere_gridY = [];
                        
                    else
                        promt = {'hemisphere undefined; please enter left (L), right (R) or both (B):'};
                        dlg_title = [' probe #' num2str(num_probes)];
                        num_lines = 1;
                        def = {'L'};
                        answer = inputdlg(promt,dlg_title,num_lines,def);
                        if strcmpi(answer{1},'l')
                            ex.setup.leftHemisphereRecorded = 1;
                            ex.setup.rightHemisphereRecorded = 0;
                        elseif strcmpi(answer{1},'r')
                            ex.setup.leftHemisphereRecorded = 0;
                            ex.setup.rightHemisphereRecorded = 1;
                        elseif strcmpi(answer{1},'b')
                            ex.setup.leftHemisphereRecorded = 1;
                            ex.setup.rightHemisphereRecorded = 1;
                        else
                            ex.setup.leftHemisphereRecorded = [];
                            ex.setup.rightHemisphereRecorded = [];
                        end
                    end
                end
            end
    end
    
    ServoDrive
    
end


%% Eyelink
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% monocular or binocular eye signals %%%%
if skipQuests
    ex.setup.el.binoc = defaults.binoc;
else
    button = questdlg('are we recording monocular or binocular eye signals?' ...
        ,'','monocular','binocular','binocular');
    switch button
        case 'monocular'
            ex.setup.el.binoc = 0;
        case 'binocular'
            ex.setup.el.binoc = 1;
        case 'cancel'
            disp('forced exit: please respond whether you want to record monocular or binocular eye signals');
            return
    end
end
ex.setup.el.edfFileName = 'tmp.edf';
ex.setup.el.Cmd_SampleData = 'link_sample_data = LEFT,RIGHT,GAZE,AREA,INPUT,HTARGET';
% added by IK, 2024.07.10. % hn: doesn't appear to be used
ex.setup.eyeToCheck = 0;

%% Datapixx AdcChannel settings  (Adc channels used for eye data)
ex.setup.adc.Rate = 500; % 500/sec is the max rate for binocular data in Eyelink
if ex.setup.el.binoc
    ex.setup.adc.Channels = [0:5];  % channels 0 to 5 for binocular data
    ex.setup.adc.DiffChannels = [0,0,0,0,0,0]; % 0:= compute no differential voltages;
    % Channel 6 is the CoPs photodiode sync signal. Keep channel 7
    % recorded as well for compatibility with the previous camera-sync setup.
    ex.setup.adc.Channels = [ex.setup.adc.Channels, 6, 7];
    ex.setup.adc.DiffChannels = [ex.setup.adc.DiffChannels, 0, 0];
else
    ex.setup.adc.Channels = [0:2];  % channels 0 to 2 for monocular data
    ex.setup.adc.DiffChannels = [0,0,0]; % 0:= compute no differential voltages;
    % Record the CoPs photodiode sync signal in monocular sessions too.
    ex.setup.adc.Channels = [ex.setup.adc.Channels, 6];
    ex.setup.adc.DiffChannels = [ex.setup.adc.DiffChannels, 0];
end
% for more information: http://docs.psychtoolbox.org/SetAdcSchedule
ex.setup.adc.BufferBaseAddress = 0;  % our default AdcBufferAddress

% Initialize ADC channels only when an eye-input configuration needs them.
% Hardware-free test profiles still retain the channel metadata above.
if options.initializeAdc
    resetAdcBuffer(ex)
end

% hn 05/05/24   : uncommented iontophoresis and motion detection for
% convenience
%{
%% iontophoresis
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% iontophoresis signals recorded? %%%%
button = questdlg('are we performing iontophoresis?' ...
    ,'iontophoresis','yes','no','no');
switch button
    case 'yes'
        ex.setup.iontophoresis.on = 1;
        ex.setup.adc.Channels = [ex.setup.adc.Channels, [1,2]+ ex.setup.adc.Channels(end)];
        ex.setup.adc.DiffChannels = [ex.setup.adc.DiffChannels, 0,0];
    case 'no'
        ex.setup.iontophoresis.on = 0;
    case 'cancel'
        disp('forced exit: please respond whether you want to run iontophoresis');
        return
end

%}
ex.setup.iontophoresis.on = false;

%% motion detection
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% motion signals recorded? %%%%
if skipQuests
    ex.setup.motionDetector.on = defaults.motionDetector;
else
    button = questdlg('are we using the motion detector or video motiontracking?' ...
        ,'shake detector','yes','no','no');
    switch button
        case 'yes'
            ex.setup.motionDetector.on = 1;
            ex.setup.adc.Channels = [ex.setup.adc.Channels, ex.setup.adc.Channels(end)+1];
            ex.setup.adc.DiffChannels = [ex.setup.adc.DiffChannels, 0];
        case 'no'
            ex.setup.motionDetector.on = 0;
        case 'cancel'
            disp('forced exit: please respond whether you monitor movements');
            return
    end
end
%% States:
ex.states.START             = 0;
ex.states.FPON              = 1;
ex.states.FPHOLD            = 2;
ex.states.NOFIX             = 3;  % fixation never acquired; start new trial
%ex.states.TARGON            = 4;  % hn: 7/5/14 removed after I introduced target
%                                   onset randomization to manipulate those
%                                   independently
ex.states.ERROR             = 5;
ex.states.GO                = 6;
ex.states.CHOICE            = 6.5;
ex.states.NOCHOICEMADE      = 6.6;
ex.states.SWITCHCHOICE      = 6.7;
ex.states.BREAKFIX          = 7;
ex.states.FIXATIONCOMPLETE  = 8;
ex.states.REWARD            = 9;

ex.states.BREAKHOLD         = 7.5;  % ik - added to designate trials on
% the eyes entered target window then
% go out of the target window.
% 4.19.2024

% ik - added to control trial duration indepdent of reward for freeViewing
% trials.  This may not be in use any more.
ex.states.TRIALCOMPLETE     = 10;

%% strobe words to send to grapevine
ex = getStrobeDefinitionsx(ex);

%%

% fixation parameters
ex.fix.duration = 0.1; % xx original: 2 sec; now different implementation through pass_eye_accum?
ex.fix.preStimDuration = 0;
ex.fix.stimDuration = 2;
ex.fix.waitstop = 20;
ex.fix.freeduration = 0; % pre-FP duration
ex.fix.WinW = 60;  % fixation window width in pixels
ex.fix.WinH = 60;  % fixation window hight in pixels
ex.fix.PSz = 7;  % fix point size
ex.fix.duration_forEarlyReward = [2.1 3.7] ;
ex.fix.toDurationAfterFixBreak = 0;
ex.fix.fixCross = false;
ex.fix.lineWidth = 5;
ex.fix.searchW = 200; % search window width for ex.freeViewing=2 in pixels
ex.fix.searchH = 200; % search window height for ex.freeViewing=2 in pixels
ex.fix.SSz = 46; %deg2pixel(2,ex.setup); % surround of the fixation
% synch pulse for photodiode (white point in top right corner of screen)
ex.synch.PSz = 120; % use an even number
ex.synch.Col = ex.idx.white;

% target parameters
ex.targ.duration = 2;
ex.targ.freeduration = 0;
ex.targ.icon.type='rds';
ex.targ.WinW = 100;  % target window width in pixels
ex.targ.WinH = 100;  % target window hight in pixels
ex.targ.PSz = 8;  % targ point size
ex.targ.Pos = [ 0 180;  0 -180];  % targ position in pixels relative to fixation point
ex.targ.T1Col = ex.idx.white;  %correct targ color
ex.targ.T2Col = ex.idx.white; % error target color
ex.targ.go_delay = 0.05; % delay until monkey can choose a target
ex.targ.RT_delay = 0;  % if one wants to include a delay to prevent early choices
ex.targ.fixOnDuringDelay = true; % fixation point is on during tagrte onset delay
ex.targ.hold = .1;
ex.targ.icon.sz = 2.2; % center size of target icon
ex.targ.icon.ssz = 3; % surround size of target icon

ex.targ.icon.T1co = 1;
ex.targ.icon.T2co = 1;
ex.targ.icon.T1co2 = 0;  % target contrast during stimulus presentation
ex.targ.icon.T2co2 = 0;
ex.targ.icon.hdx = 0.2;
ex.targ.icon.rampDur = 0;

% audio parameters for big reward
ex.setup.audio.bigRewardLoops = 1; % duration
ex.setup.audio.bigRewardFreq = 60000; % frequency of tone
ex.setup.audio.errorLoops = 1; % duration
ex.setup.audio.errorFreq = 15000; % frequency of tone
ex.setup.audio.errordB = 0.6; % frequency of tone
ex.setup.audio.rewardLoops = 1; % duration
ex.setup.audio.rewardFreq = 36000; % frequency of tone
ex.setup.audio.rewarddB = 0.3; % frequency of tone
%%
if isfield(ex,'stim')
    ex=rmfield(ex,'stim');
end


%
%% experiment type
% for CoPs this setting is moved to setDefaultsCoPs
% ex.exp.nreps = 2; % for CoPs: nreps*(~30 sec) =~ exp length. For nreps=100 -> 50min
ex.exp.afc = 0;
%% SC mapping  04/04/23: accounting for Incheol's SC mapping
ex.exp.scmap = false;
%% Synthetic mask experiment
ex.exp.spatialAttention = 0;
ex.exp.nInstructionTrials = 0;
%%
ex.exp.addInstructionTrials = 0; % flag to manually add instruction trials on the fly
ex.exp.countAddInstructionTrials = 0;
ex.exp.numberAdditionalInstructionTrials = 2;  % default for additional instruction trials added on the fly
ex.exp.monocBlank = false; % added on 2/6/24

%% experiment1 : hdx
ex.exp.e1.type = 'hdx';
ex.exp.e1.min = -.2;
ex.exp.e1.inc = 0.4;
ex.exp.e1.scale = 'lin';
ex.exp.e1.nsamples = 2;

ex.exp.e3.type = 'targOn_delay';
ex.exp.e3.min = 0;
ex.exp.e3.inc = 0.5;
ex.exp.e3.scale = 'lin';
ex.exp.e3.nsamples = 3;

ex.exp.e2.type = 'Dc';
ex.exp.e2.min = 0.4;
ex.exp.e2.inc = 0.3;
ex.exp.e2.scale = 'range';
ex.exp.e2.nsamples = 4;
ex.exp.e2.range = [0 .1 .2 1];
ex.stim.vals.hdx_range = [-.8 : 0.2 : .8];  % disparity values from which the noise is drawn

ex.exp.CoPs.type = 'texture';
ex.exp.CoPs.nsamples = 1;

ex.finish = ex.exp.e1.nsamples*ex.exp.e2.nsamples  ...
    * ex.exp.nreps;


%%  % define extras (RF position, helper lines for online orientation)
ex.extras.rfW = .5;
ex.extras.rfH = .5;
ex.extras.rfx = 10;
ex.extras.rfy = 10;
ex.extras.line = [];
%%
% general parameters
ex.stim.vals.st = 1;
ex.stim.vals.RC = 0;  % reverse correlation sequence?: yes: 1, no: 0
ex.stim.vals.me = 0;  % binocular stimulus (1: right monocular, -1: left monocular)

% %% RDS stimulus
ex.stim.type = 'rds';
ex.stim.vals.dd = 100;    %: dot density
ex.stim.vals.wi = 6;    %: width in dva
ex.stim.vals.hi =6;    %: height in dva
ex.stim.vals.swi = 7;    %: surround width in dva
ex.stim.vals.shi =7;    %: surround height in dva
ex.stim.vals.hdx =0.1;    %: horizontal dx of center patch in dva
ex.stim.vals.vdx =0;    %: vertical dx of center in dva
ex.stim.vals.shdx =0;   %: horizontal dx of surround in dva
ex.stim.vals.svdx =0;   %: vertical dx of surround in dva
ex.stim.vals.dotSz=7;  % dot size in pixels
ex.stim.vals.co = 1;  % max. stimulus contrast
ex.stim.vals.x0 = 3; % center of stimulus (in x) rel. to fp center in dva
ex.stim.vals.y0 = 0; % center of stimulus (in y) rel. to fp center in dva
ex.stim.vals.dyn = 1; % dynamic (1) or static (0) RDS?
ex.stim.vals.dcol = 'blwi'; % dot color
ex.stim.vals.me = 0;  % binocular stimulus (1: right monocular, -1: left monocular)
ex.stim.vals.Dc2 = 0.5;
ex.stim.vals.hdx2 = -0.05;
ex.stim.vals.co2 = 0.2;
ex.stim.vals.ce = 1; % interocular correlation: -1 (anticorrelated) 0 1

%% grating stimulus
ex.stim.type = 'grating';
ex.stim.vals.sf = 0.5; % grating sf in cpd
ex.stim.vals.tf = 1;
ex.stim.vals.sz = 5;  % stimulus size in dva
ex.stim.vals.wi = 5;  % stimulus width in dva
ex.stim.vals.hi = 5;  % stimulus height in dva
ex.stim.vals.or = 30; % grating orientation in degrees; 0 is horizontal
ex.stim.vals.x0 = 10; % center of stimulus (in x) rel. to fp center in dva
ex.stim.vals.y0 = 5; % center of stimulus (in y) rel. to fp center in dva
ex.stim.vals.co = 1;  % max. stimulus contrast
ex.stim.drawmask = 1;
ex.stim.vals.adaptation = 0;
ex.stim.vals.adaptationDur = 0;
ex.stim.vals.adaptationOr = 0;
ex.stim.vals.adaptationMe = 0;
ex.stim.vals.RC = 0;
ex.stim.masktype = 'circle';

ex.exp.spatialAttention = 0;

%% bar stimulus
ex.stim.type = 'bar';
ex.stim.vals.or = 30;
ex.stim.vals.hi = 5;
ex.stim.vals.wi = .3;
ex.stim.vals.sf = 1;
ex.stim.vals.tf = 1;
ex.stim.vals.flickerTF=0;
ex.stim.vals.col = ex.idx.white;
ex.stim.vals.me = 0;  % binocular stimulus (1: right monocular, -1: left monocular)

ex.stim.type = 'texture'

ex.exp.StimPerTrial = 1;
ex.exp.include_blank = 0;
ex.exp.include_monoc = 0;

if ~ex.exp.afc
    ex.stim.nseq = ex.finish; % number of stimuli in sequence (only used when running an experiment);
end
