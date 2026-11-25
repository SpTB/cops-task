function ex = runEx(eyeStr, varargin)
% Run the CoPs task.
%
% usage examples:
%   runEx() normal human run, equivalent to runEx('h') (default)
%   runEx('h', filePrefix="P001") % save under <data root>/P001/<date>/
%   runEx('h', 0) disable the experimenter overlay
%   runEx('h', 1, 1) windowed desktop overlay with DataPixx enabled
%   runEx('h', 1, 1, overlayScreen=0, overlayWindowSizePx=[960 540])
%   runEx('h', eyeSource='analog') legacy analog eye calibration
%   runEx('h', nativeValidation=false) save tracker calibration, skip custom validation
%   runEx('h', calibrationBeepVolume=0.05) % quieter EyeLink tones (0 to 1; default 0.1)
%   runEx('t') full task for solo testing; no eye tracking/calibration/validation
%   runEx('t', 1, 0) solo test with DataPixx strobes disabled
%   runEx('test1')  % fullscreen mouse test
%   runEx('test1', 0)  % disable the experimenter overlay
%   runEx('test1', overlayOn=true, overlayScreen=0)
%   runEx('test1', testTrials=5)
%   runEx('mouse_mini', stimulusDir="stimuli/my_session") % use a generated bank
%   runEx('test1', viewingDistanceCm=60, monitorWidthCm=53)
%   runEx('mouse_mini')  % full-display preview in a normal desktop window
%   runEx('mouse_mini', 1)  % enable the overlay on a separate monitor
%   runEx('mouse_mini', overlayOn=true, overlayWindowSizePx=[960 540])
%   runEx('mouse_mini', windowSizePx=[960 540], testTrials=5)
%   runEx('mouse_mini', showCursor=false)  % hide the normally visible cursor
%   runEx('mouse_mini', filePrefix="P001")  % supply the subject ID without a dialog
%   runEx('mouse_mini', soundOn=false)  % disable reward-threshold beeps
%   runEx('mouse_mini', participantFeedback=false) % skip the final comment box
%   runEx('mouse_mini', instrOn=true)  % three instruction pages + two practice trials
%   runEx('mouse_mini', jointBlocks=true) % preview the configured reward-peak blocks
%   runEx('mouse_mini', syncMode='binary')  % preview a frame-coded photodiode patch
%   runEx('test1', syncMode='binary', photodiodeRecord=true, photodiodeSampleRate=2000)
% See docs/photodiode_sync.md before using photodiode acquisition on the rig.
%   runEx('h', participantKeyboard=participantID, experimenterKeyboard=operatorID)
% On the op4 rig, normal runs default to Dell participant / Apple experimenter.
%   runEx('t', 0, keyboardMode="shared") % explicitly use shared-keyboard controls
% Separate keyboards require Linux/X11. Explicit device IDs override rig defaults.
%   runEx('test1', fullscreen=false)  % use a window with test1 settings
% overlayOn can be the second positional argument or a name-value option
% for every mode. The name-value option takes precedence when both are given.

% Supply the default before validation so an explicit calibration mode is
% required by the inner function. Otherwise MATLAB parses 't', 0 as the
% abbreviated name-value pair testTrials=0.
addpath(fullfile(fileparts(mfilename('fullpath')), 'helpers'), '-begin');

if nargin == 0
    eyeStr = 'h';
end
ex = runCoPsWithOptions(eyeStr, varargin{:});
end


function ex = runCoPsWithOptions(eyeStr, overlayEnabled, pixOn, rewOn, eyeOn, skipQuest, options)
arguments
    eyeStr {mustBeText} % 'h' human, 't' no-eye solo test, 'test1', or 'mouse_mini'
    overlayEnabled {mustBeNumericOrLogical} = 0;% ~strcmpi(strtrim(eyeStr), 'mouse_mini')
    pixOn  {mustBeNumericOrLogical} = 1
    rewOn {mustBeNumericOrLogical} = false
    eyeOn  {mustBeNumericOrLogical} = true
    skipQuest {mustBeNumericOrLogical} = true
    options.eyeSource {mustBeMember(options.eyeSource,{'eyelink','analog'})} = 'eyelink'
    options.nativeValidation (1,1) logical = true % custom validation after tracker setup
    options.calibrationBeepVolume (1,1) double {mustBeFinite, mustBeNonnegative, mustBeLessThanOrEqual(options.calibrationBeepVolume,1)} = 0.1
    options.testTrials (1,1) double {mustBeInteger, mustBePositive} = 3
    options.viewingDistanceCm (1,1) double {mustBePositive} = 55 %100
    options.monitorWidthCm (1,1) double {mustBePositive} = 54 %50
    options.fullscreen (1,1) logical = ~strcmpi(strtrim(eyeStr), 'mouse_mini')
    options.showCursor (1,1) logical = strcmpi(strtrim(eyeStr), 'mouse_mini')
    options.soundOn (1,1) logical = true
    options.showEndScreen (1,1) logical = true % false for unattended diagnostics
    options.participantFeedback (1,:) logical = [] % [] uses ex.exp.CoPs.fbOn
    options.instrOn (1,:) logical = [] % [] uses setDefaultsCoPs; explicit true/false overrides
    options.jointBlocks (1,:) logical = [] % [] uses profile defaults; true overrides testTrials
    options.syncMode (1,1) string {mustBeMember(options.syncMode, ["","goPulse","binary","off"])} = ""
    options.syncFramesPerBit (1,:) double {mustBeInteger, mustBePositive, mustBeFinite} = []
    options.syncSequence (1,:) double = []
    options.photodiodeRecord (1,1) logical = false
    options.photodiodeTailSecs (1,:) double {mustBeNonnegative,mustBeFinite} = []
    options.photodiodeChannel (1,:) double {mustBeInteger, mustBeNonnegative, mustBeFinite, mustBeLessThanOrEqual(options.photodiodeChannel,15)} = []
    options.photodiodeSampleRate (1,1) double {mustBeInteger, mustBePositive, mustBeFinite, mustBeLessThanOrEqual(options.photodiodeSampleRate,200000)} = 500
    options.filePrefix (1,1) string = ""
    options.stimulusDir (1,1) string {mustBeStimulusDirectoryOrEmpty} = ""
    options.keyboardMode (1,1) string {mustBeMember(options.keyboardMode, ["auto","shared","separate"])} = "shared" %"auto"
    options.participantKeyboard (1,:) double {mustBeInteger, mustBeNonnegative, mustBeFinite} = []
    options.experimenterKeyboard (1,:) double {mustBeInteger, mustBeNonnegative, mustBeFinite} = []
    options.overlayOn (1,1) logical = logical(overlayEnabled)
    options.overlayScreen (1,:) double {mustBeInteger, mustBeNonnegative} = []
    options.overlayWindowSizePx (1,2) double {mustBeInteger, mustBePositive} = [960 540]
    options.windowSizePx (1,2) double {mustBeInteger, mustBePositive} = defaultWindowSizePx(eyeStr)
    options.recording (1,1) struct = struct() % configured by recEx
end

dependencies = resolveCoPsRunDependenciesx(eyeStr, pixOn, eyeOn, rewOn, options.eyeSource, options.photodiodeRecord);
isTestProfile = ismember(dependencies.profile, {'test1', 'mouse_mini'});
recordingEnabled = ~isempty(fieldnames(options.recording));
if recordingEnabled && ~isTestProfile
    error('recEx:Profile','Presentation recording requires a mouse test profile.');
end
pixOn = dependencies.pixOn;
eyeOn = dependencies.eyeOn;
rewOn = dependencies.rewOn;

% close any display left by a previous run before resetting hardware handles
closeCoPsDisplayx();
if dependencies.datapixxOn
    Datapixx('Close')
end
if dependencies.eyelinkOn
    Eyelink('Shutdown');
end
ex = struct();
if dependencies.datapixxOn && ~Datapixx('Open')
    initDatapixx(ex);
end

ex = setDefaultsCoPs(ex);
if ~isempty(options.participantFeedback)
    validateattributes(options.participantFeedback,{'logical'},{'scalar'});
    ex.exp.CoPs.fbOn = options.participantFeedback;
end
if ~isempty(options.instrOn)
    validateattributes(options.instrOn, {'logical'}, {'scalar'});
    ex.exp.CoPs.instrOn = options.instrOn;
end
ex.exp.CoPs.pay = resolveCoPsPayx(ex.exp.CoPs.pay);
formatCoPsInstructionTextx(ex.exp.CoPs.pay);
if strlength(options.syncMode) > 0, ex.exp.CoPs.sync.mode = char(options.syncMode); end
if ~isempty(options.syncFramesPerBit)
    validateattributes(options.syncFramesPerBit, {'numeric'}, {'scalar'});
    ex.exp.CoPs.sync.framesPerBit = options.syncFramesPerBit;
end
if ~isempty(options.syncSequence), ex.exp.CoPs.sync.sequence = options.syncSequence; end
if ~isempty(options.photodiodeTailSecs)
    validateattributes(options.photodiodeTailSecs, {'numeric'}, {'scalar'});
    ex.exp.CoPs.sync.captureTailSecs = options.photodiodeTailSecs;
end
if ~isempty(options.photodiodeChannel)
    validateattributes(options.photodiodeChannel, {'numeric'}, {'scalar'});
    ex.exp.CoPs.sync.physicalChannel = options.photodiodeChannel;
end

if isTestProfile
    % Make the portable display geometry explicit before the host-specific
    % defaults are resolved. These values affect degrees-to-pixels
    % conversions and should be replaced with measured values when known.
    ex.setup.testMode = true;
    ex.setup.viewingDistance = options.viewingDistanceCm;
    ex.setup.monitorWidth = options.monitorWidthCm;
    ex.setup.fullscreen = options.fullscreen;
    ex.setup.windowSizePx = options.windowSizePx;
end

ex = getDefaultSettingsx(ex, skipQuest, initializeAdc=false); %eyeOn
if isTestProfile
    [ex, testConfig] = configureCoPsTestRunx(ex, options.testTrials, dependencies.profile);
    ex.setup.testConfig = testConfig;
    if options.photodiodeRecord
        fprintf('CoPs %s: %d trial(s), mouse input, DataPixx ADC enabled for photodiode recording.\n', ...
            dependencies.profile, options.testTrials);
    else
        fprintf('CoPs %s: %d trial(s), mouse input, no DataPixx/EyeLink/reward hardware.\n', ...
            dependencies.profile, options.testTrials);
    end
    ex.Header.animal = 'test';
end
if strlength(options.stimulusDir) > 0
    ex = useStimulusDirectoryLocal(ex,options.stimulusDir);
end
if ~isempty(options.jointBlocks)
    validateattributes(options.jointBlocks, {'logical'}, {'scalar'});
    ex.exp.CoPs.ctl.jointBlocks = options.jointBlocks;
end
if recordingEnabled, ex = configureCoPsRecordingx(ex,options.recording); end
% Resolve identity once, before calibration or any session output is created.
subjectIDEntered = strtrim(char(options.filePrefix));
if isempty(subjectIDEntered) && isfield(ex, 'Header')
    if isfield(ex.Header, 'subjectIDEntered') && ~isempty(ex.Header.subjectIDEntered)
        subjectIDEntered = strtrim(char(ex.Header.subjectIDEntered));
    elseif isfield(ex.Header, 'subjectID')
        subjectIDEntered = strtrim(char(ex.Header.subjectID));
    end
end
if isempty(subjectIDEntered)
    defaultPrefix = 'test';
    if isfield(ex.setup, 'filePrefix') && ~isempty(ex.setup.filePrefix)
        defaultPrefix = char(ex.setup.filePrefix);
    end
    answer = inputdlg('Subject ID / filename prefix:', 'CoPs subject', ...
        [1 50], {defaultPrefix});
    if isempty(answer)
        ex.quit = 4;
        return
    end
    subjectIDEntered = strtrim(answer{1});
end
ex.Header.subjectIDEntered = subjectIDEntered;
ex.Header.subjectID = normalizeCoPsSubjectIDx(subjectIDEntered);
ex.setup.filePrefix = ex.Header.subjectID;
fprintf('CoPs subject ID: %s.\n', ex.Header.subjectID);
ex.setup.dependencies = dependencies;
ex.setup.runProfile = dependencies.profile;
ex.setup.inputMode = dependencies.inputMode;
if ~eyeOn, ex.setup.eyeTracker = 'none'; end
if strcmp(dependencies.profile,'t')
    ex.exp.CoPs.freeViewing = true; % advance trials by time without gaze input
    fprintf('CoPs solo test: full task, no eye tracking, calibration, or validation.\n');
end
fprintf('CoPs behavioral input: %s.\n', dependencies.inputMode);
ex.setup.showCursor = options.showCursor;
ex.setup.soundOn = options.soundOn;
ex.setup.showEndScreen = options.showEndScreen;
ex.exp.CoPs.rew.soundOn = options.soundOn;
ex.setup.showExperimenterOverlay = options.overlayOn;
ex.setup.overlayScreen = options.overlayScreen;
ex.setup.overlayWindowSizePx = options.overlayWindowSizePx;
[participantKeyboard, experimenterKeyboard] = resolveCoPsKeyboardSelectionx( ...
    ex.setup, dependencies.profile, options.keyboardMode, ...
    options.participantKeyboard, options.experimenterKeyboard);
[ex.setup.keyboards, keyboardCleanup] = initCoPsKeyboardsx( ...
    participantKeyboard, experimenterKeyboard); %#ok<NASGU>
if ex.setup.keyboards.separate
    fprintf('CoPs participant keyboard: %s (PTB %d).\n', ...
        ex.setup.keyboards.participantName, ex.setup.keyboards.participantIndex);
    fprintf('CoPs experimenter keyboard: %s (PTB %d).\n', ...
        ex.setup.keyboards.experimenterName, ex.setup.keyboards.experimenterIndex);
    fprintf('CoPs keyboards: participant SPACE/Q at pauses; experimenter F6 recalibrates at pauses, F4 quits.\n');
else
    fprintf('CoPs keyboards: shared test mode (participant keyboard is not isolated).\n');
end
if strcmp(dependencies.inputMode, 'eyelink')
    % Native gaze arrives through EyeLink; ADC records only the photodiode.
    ex.setup.adc.Channels = ex.exp.CoPs.sync.physicalChannel;
    ex.setup.adc.DiffChannels = zeros(size(ex.setup.adc.Channels));
end
% Keep behavioral polling independent of the optional photodiode ADC rate.
ex.setup.inputSampleRate = ex.setup.adc.Rate;
if options.photodiodeRecord
    if ~isfield(ex.setup.adc, 'NumBufferFrames')
        ex.setup.adc.NumBufferFrames = 900000; % conservative existing rig default; validate on new hardware
    end
    if ~eyeOn
        ex.setup.adc.Channels = ex.exp.CoPs.sync.physicalChannel;
        ex.setup.adc.DiffChannels = 0;
    end
    ex.setup.adc.Rate = options.photodiodeSampleRate;
end
if dependencies.adcOn
    % Honor the selected diode input for automatically enabled ADC runs too.
    if ~ismember(ex.exp.CoPs.sync.physicalChannel, ex.setup.adc.Channels)
        ex.setup.adc.Channels(end+1) = ex.exp.CoPs.sync.physicalChannel;
        ex.setup.adc.DiffChannels(end+1) = 0;
    end
    analogCleanup = onCleanup(@stopCoPsAnalogx); %#ok<NASGU>
    resetAdcBuffer(ex);
end

ex.states.PREGO = 5.95

% install cleanup before initialization, including partially opened windows
displayCleanup = onCleanup(@closeCoPsDisplayx); %ok<NASGU>
% The desktop overlay must not change stimulus colors or display mode.
% DataPixx input, strobes, and reward remain controlled by the hardware flags.
ex = initDisplayx(ex);
flipInterval = 1 / ex.setup.refreshRate;
if strcmp(ex.exp.CoPs.sync.mode, 'binary')
    flipInterval = Screen('GetFlipInterval', ex.setup.window);
end
ex.exp.CoPs.sync = prepareCoPsSyncx(ex.exp.CoPs.sync, flipInterval);
ex.exp.CoPs.sync.lowColor = ex.idx.black;
ex.exp.CoPs.sync.highColor = ex.idx.white;
if strcmp(ex.exp.CoPs.sync.mode, 'binary')
    fprintf('CoPs binary sync: %.3f bits/s, %d refresh(es)/bit, same code reset each trial.\n', ...
        ex.exp.CoPs.sync.bitRateHz, ex.exp.CoPs.sync.framesPerBit);
end
if options.showCursor
    ShowCursor('Arrow', ex.setup.window);
    if recordingEnabled
        [width,height] = Screen('WindowSize',ex.setup.window,1);
        SetMouse(round(width/2),round(height/2),ex.setup.window);
    end
end
pause(1)

% Use the task gray for calibration, validation, and every null-background
% texture instead of deriving the null gray from each source image's mean.
ex.exp.CoPs.graph.nullBackgroundGray = ex.idx.bg_lum;
if eyeOn
    ex.calib = setDefaultsCalib();
    ex.valid = setDefaultsValid();
    ex.calib.background_color = ex.idx.bg_lum;
    ex.valid.background_color = ex.idx.bg_lum;
end

if eyeOn && strcmp(dependencies.inputMode, 'eyelink')
    ex.calib.file = ''; % native calibration is provided by the tracker
    % valid.update optionally fits a separate native pixel correction.
    ex.valid.onlineUpdate = false;
    ex.valid.recenterFirst = false;
    ex = resolveCalibrationValidationDisplaySizes(ex);
    ex.setup.el.edfFileName = ['c' datestr(now,'HHMMSS') '.edf'];
    ex.setup.el.calibrationBeepVolume = options.calibrationBeepVolume;
    ex = initCoPsEyelinkx(ex);
    ex = saveCoPsNativeEyeCalx(ex);
    if options.nativeValidation && ex.calib.validate
        ex = validateCoPsNativeEyelinkx(ex);
    end
    ex = saveCoPsNativeEyeCalx(ex, true);
    if ex.quit == 4
        return
    end
elseif eyeOn
    
    ex.setup.VSdirRoot = pwd;
    % handles = initEyeHandlesx(ex);
    % ex = initEyelink(ex, handles);
    ex = initEyelink(ex);
    ex.eyeCal = [];
    % ex.idx.bg = 0; % black test
    ex = resolveCalibrationValidationDisplaySizes(ex);

    switch lower(eyeStr)
        
        case 'y' % legacy calibration
            %ex = calibrateEye_rev(ex);
            ex = calibrateEyex(ex);
            disp('eye calibration done')
        case 'h'
               ex = calibrateEye2vx(ex);
        case 'l' % long version
               ex = calibrateEyexx(ex);
        case 'mix'
               ex = calibrateEyex_mix(ex);       
        case 'm2' % monocular mouse sim case
            exTemp=load('/home/vpixx/Desktop/t.mat')
            if isfield(exTemp, 'ex') % whole ex struct case
                ex.eyeCal = exTemp.ex.eyeCal;
            elseif isfield (exTemp, 'eyeCal')
                ex.eyeCal = exTemp.eyeCal;
            else
                error('eyeCal field not found')
            end
            if ~isfield(ex.eyeCal,'Delta') || isempty(ex.eyeCal.Delta)
              ex.eyeCal.Delta.cnt = 1;
              ex.eyeCal.Delta.RX0 = 0;
              ex.eyeCal.Delta.RY0 = 0;
              ex.eyeCal.Delta.LX0 = 0;
              ex.eyeCal.Delta.LY0 = 0;
            end

        case 'm1' % monocular mouse sim case
            exTemp=load('/home/vpixx/data/test/2026.03.09/t_12.19.EyeCal/t_12.19.EyeCal.mat')
            if isfield(exTemp, 'ex') % whole ex struct case
                ex.eyeCal = exTemp.ex.eyeCal;
            elseif isfield (exTemp, 'eyeCal')
                ex.eyeCal = exTemp.eyeCal;
            else
                error('eyeCal field not found')
            end
            
        case 'ka1' % kaki case: rigth eye only
            exTemp=load('/home/vpixx/Desktop/ka1.mat')
            if isfield(exTemp, 'ex') % whole ex struct case
                ex.eyeCal = exTemp.ex.eyeCal;
            elseif isfield (exTemp, 'eyeCal')
                ex.eyeCal = exTemp.eyeCal;
            else
                error('eyeCal field not found')
            end
        case 'ka' % kaki case
            exTemp=load('/home/vpixx/Desktop/ka.mat')
            if isfield(exTemp, 'ex') % whole ex struct case
                ex.eyeCal = exTemp.ex.eyeCal;
            elseif isfield (exTemp, 'eyeCal')
                ex.eyeCal = exTemp.eyeCal;
            else
                error('eyeCal field not found')
            end

        case 'ly' % lychee case
            exTemp=load('/home/vpixx/Desktop/ly.mat')
            if isfield(exTemp, 'ex') % whole ex struct case
                ex.eyeCal = exTemp.ex.eyeCal;
            elseif isfield (exTemp, 'eyeCal')
                ex.eyeCal = exTemp.eyeCal;
            else
                error('eyeCal field not found')
            end

        otherwise
    end
end

if ~eyeOn && ~isfield(ex, 'eyeCal')
    ex.eyeCal = makeCoPsMouseEyeCalx();
end

if ex.setup.el.binoc==0
    ex.eyeCal.LXPos = [];
    ex.eyeCal.LYPos = [];
end
% Preload reward audio after tracker calibration has released its audio device.
if options.soundOn && eyeOn
    Snd('Close'); % release any calibration-feedback device before opening ours
end
[ex.setup.rewardSound, soundCleanup] = initCoPsRewardSoundx(options.soundOn); %#ok<NASGU>
%run Expt starts
ex.j = 1;  % current trial number
ex.goodtrial = 0;  % counter for successful trials
ex.totalPoints = 0; % counter for total points earned
ex.loopcnt = zeros(1, ex.finish);  % loop counter for each trial
ex.changedBlock = 0;  % keeps track of whether we changed blocks
ex = prepareCoPsJointBlocksx(ex); % geometry is initialized; plan before counts and schedules
ex.exp.total_nreps = getCoPsTotalRepsx(ex);
ex.finish = ex.exp.total_nreps;
ex = prepareCoPsPauseSchedulex(ex);
ex = prepareCoPsTrialParamSchedules(ex);

%%%%%%%%%%%%%%%%%%%%%%%%%  make stimulus/trial sequence
if isfield(ex.stim,'seq')
    ex.stim = rmfield(ex.stim,'seq');
end
sequenceModeIm = false;
if isfield(ex.exp.CoPs.graph, 'sequenceMode_im') && ~isempty(ex.exp.CoPs.graph.sequenceMode_im)
    sequenceModeIm = ex.exp.CoPs.graph.sequenceMode_im;
elseif isfield(ex.exp.CoPs.graph, 'sequenceMode') && ~isempty(ex.exp.CoPs.graph.sequenceMode)
    sequenceModeIm = ex.exp.CoPs.graph.sequenceMode;
end
activeTrialMask = [];
if isfield(ex.exp.CoPs, 'trialParamSchedules') && ...
        isfield(ex.exp.CoPs.trialParamSchedules, 'target_visibility')
    activeTrialMask = isfinite(ex.exp.CoPs.trialParamSchedules.target_visibility);
end
ex.stim.seq = buildCoPsStimulusSequencex(ex, sequenceModeIm, activeTrialMask);
ex.exp.CoPs.stimValidation = validateCoPsStimulusSelection(ex);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% if there are several changes of eye position offset (delta x, delta y)
%%% stored from a previous experiment, use only the last one
ex = resetEyeDelta(ex);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%% store unique experiment ID
clocktime = fix(clock);
if pixOn
    sendStrobes([ex.strobe.FILE_ID,clocktime,ex.strobe.EXPERIMENT_START]);
end

ex.Header.fileID = clocktime;

sfx = makeFilenameSuffixCoPsx(ex);
[fname,dirName,trDir] = makeFilenameAndDirx(ex, sfx); % no difference right now... (as in v2.7)
% new: separate dirs to reduce mess
expDir = fullfile(dirName,'experimental');
edfDir = fullfile(dirName,'edf');
if ~exist(expDir,'dir')
    mkdir(expDir);
end
if ~exist(edfDir,'dir')
    mkdir(edfDir);
end
ex.Header.onlineDirName = dirName;
ex.Header.onlineExperimentalDirName = expDir;
ex.Header.onlineEdfDirName = edfDir;
ex.Header.onlineFileName = fname;
if recordingEnabled, ex = prepareCoPsMovieOutputx(ex); end
fprintf('CoPs output: %s\n', fullfile(expDir, fname));

% create Trials
ex.loopcnt =[];
if isfield(ex,'Trials')
    ex = rmfield(ex,'Trials');
    fnames = fieldnames(ex);
    for n = 1:length(fnames)
        if findstr(fnames{n},'tocs')
            ex = rmfield(ex,fnames{n});
        end
    end
end

% Always reinitialize Trials so downstream cleanup/save code can handle
% sessions that end before the first trial completes.
ex.Trials = struct('ID', {}, 'TrialStart', {}, 'TrialEnd', {}, ...
    'posT', {}, 'mousePositions', {}, 'closeness', {}, ...
    'reward', {}, 'scaledReward', {}, 'targetPositions', {}, ...
    'nsteps', {}, 'Reward', {}, 'RewardSize', {}, ...
    'flip_info', {}, 'times', struct(), ...
    'eyeRecenterCount', {}, 'eyeDeltaCntStart', {}, 'eyeDeltaCntEnd', {});


ex.nCorrectChoice = 0;
ex.nErrorChoice=0;
if isfield(ex,'fileName')
    ex = rmfield(ex,'fileName');
end

% start recording ET
if eyeOn && Eyelink('IsConnected') == 1
    
    Eyelink('SetOfflineMode')
    Eyelink('CloseFile');
    
    % only when Eyelink is used to record eye positions
    if strcmpi(ex.setup.eyeTracker,'Eyelink')
        % maximum length of an edf file name = 8
        ex.Header.edfFileName = sprintf('%02d%02d%02d%02d.edf',clocktime(2),clocktime(3),...
            clocktime(4),clocktime(5));
        Eyelink('OpenFile',ex.Header.edfFileName);
        if strcmp(dependencies.inputMode, 'eyelink')
            r = ex.setup.screenRect;
            Eyelink('Message', 'DISPLAY_COORDS 0 0 %d %d', r(3)-r(1)-1, r(4)-r(2)-1);
        end
        Eyelink('Message','exFileName: %s',fname);
        Eyelink('StartRecording');
    end
end

if pixOn
    PsychDataPixx('GetPreciseTime'); % synchronize Datapixx and PTB clocks
end

% save initial state of ex structure to recover the data in case of a crash
cur_dir = cd (trDir);
save(fname, 'ex');
cd(cur_dir);

% get daily Log (number of trials, number of correct trials)
cur_dir = cd(dirName);

if exist('dailyLog.mat') ==2
    load('dailyLog.mat');
else 
    %dailyLog.nTrialsPerDay = 0;
    %dailyLog.nCorrectTrialsPerDay = 0;
     dailyLog = struct( ...
        'nTrialsPerDay', 0, ...
        'nCorrectTrialsPerDay', 0, ...
        'sessionHistory', {{}}, ...
        'lastSessionSummary', struct([]));
end
cd(cur_dir);

dailyLog_old = dailyLog;

% keep track of hte number of trials after a shake for which we scale down
% the rewards after shakes and keep track of the number of
ex.reward.nTrialsAfterShake = inf; % default baseline

if ex.exp.CoPs.instrOn
    ex = showCoPsInstructionsx(ex);
    cur_dir = cd(trDir);
    save(fname,'ex'); % preserve the instruction text, timestamps, and acknowledgement
    cd(cur_dir);
end

ex = completeCoPsPauseActionsx(ex,fullfile(trDir,fname));
ex = runCoPsInstructionPracticex(ex,pixOn,eyeOn,rewOn,fullfile(trDir,fname));

while ex.j <= ex.finish && ex.quit~=4
    if options.showCursor
        ShowCursor('Arrow', ex.setup.window);
    else
        HideCursor
    end
    dailyLog.nTrialsPerDay = dailyLog_old.nTrialsPerDay+ex.goodtrial;
    cur_dir = cd(dirName);
    save('dailyLog','dailyLog');
    cd(cur_dir);
    % updateGuiLogs(dailyLog);
    
    if ex.quit == 0
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %%%%%%%%%%%%%%%%% run Trial
        if dependencies.adcOn %eyeOn
            resetAdcBuffer(ex);  %% reset AdcBuffer for EyeSignals
        end
        
        try
            ex = runTrialTaskCoPsx(ex, pixOn, eyeOn, rewOn);
        catch err
                        fprintf(2,'Error during trial execution (trial %d): %s\n', ex.j, err.message);
            fprintf(2,'%s\n', getReport(err, 'extended'));

            % Save immediately so data are preserved as in a normal quit.
            ex.lastError = err;
            ex.quit = 4;
            cur_dir = cd(dirName);
            whosEx = whos('ex');
            if whosEx.bytes < 1e+9
                save(fname, 'ex');
            else
                save(fname,'ex','-v7.3');
            end
            cd(cur_dir);

            % Also keep a copy of the latest completed trial when available.
            if ex.j > 1 && isfield(ex,'Trials') && numel(ex.Trials) >= (ex.j - 1)
                cur_dir = cd (trDir);
                Trials = ex.Trials(ex.j-1);
                save(['tr' num2str(ex.j-1)],'Trials');
                cd(cur_dir);
            end
            break
        end

        
        cur_dir = cd (trDir);
        Trials = ex.Trials(ex.j-1);
        save(['tr' num2str(ex.j-1)],'Trials');
        cd(cur_dir)
        ex = completeCoPsPauseActionsx(ex,fullfile(trDir,fname));
        
    elseif ex.quit ==1
        disp('in pause')
        cur_dir = cd (trDir);
        Trials = ex.Trials(ex.j-1);
        save(['tr' num2str(ex.j-1)],'Trials')
        cd(cur_dir)
        playRandomLines(ex);
        %sca
        keyboard
        ex.quit = 0;
        ShowCursor
    elseif ex.quit ==2
        disp('in pause with timeout')
        if ex.setup.stereo.Display
            % right eye
            Screen('SelectStereoDrawBuffer', ex.setup.window, 0);
            Screen('FillRect',ex.setup.window,0);  % black background
            % Select left-eye image buffer for drawing:
            Screen('SelectStereoDrawBuffer', ex.setup.window, 1);
            % Draw left stim:
            Screen('FillRect',ex.setup.window,0);  % black background
        else
            % black screen
            Screen('FillRect', ex.setup.overlay,ex.idx.black);
        end
        Screen('Flip', ex.setup.window);
        presentCoPsOverlayx(ex);
        cur_dir = cd (trDir);
        Trials = ex.Trials(ex.j-1);
        save(['tr' num2str(ex.j-1)],'Trials')
        cd(cur_dir)
        
        keyboard
        ex.quit = 0;
        ShowCursor
    elseif ex.quit ==3
        % 11/19/24
        % for future use if needed
    end
end

% end experiment
% playRandomLines(ex);

% F4 and handled errors also finalize payment. Checkpoint before an early
% outro or hardware shutdown so payment does not depend on reaching the end.
ex = finalizeCoPsSessionx(ex,fullfile(ex.Header.onlineExperimentalDirName,fname));

% signal end of experiment
if pixOn
    sendStrobe(ex.strobe.EXPERIMENT_END);
end

% iknew 06.08.2022
% close edf file
if eyeOn && Eyelink('IsConnected') == 1
    Eyelink('StopRecording')
    Eyelink('SetOfflineMode')
    Eyelink('CloseFile');
end

% get GetSecs timestamps remapped onto Datapixx TrialStart and TrialEnd
sd = NaN;
ratio = NaN;
if pixOn && isfield(ex, 'Trials') && ~isempty(ex.Trials) && ...
        all(isfield(ex.Trials, {'TrialStartDatapixx', 'TrialEndDatapixx'}))
    TrStartDP = [ex.Trials.TrialStartDatapixx];
    TrEndDP = [ex.Trials.TrialEndDatapixx];
    if ~isempty(TrStartDP) && ~isempty(TrEndDP)
        [tgetsecs, sd, ratio] = PsychDataPixx('BoxsecsToGetsecs',[TrStartDP,TrEndDP]);
        TrStartgetsecs = tgetsecs(1:length(TrStartDP));
        TrEndgetsecs = tgetsecs(length(TrStartDP)+1:end);
        for n = 1:length(TrStartDP)
            ex.Trials(n).TrialStart_remappedGetSecs = TrStartgetsecs(n);
            ex.Trials(n).TrialEnd_remappedGetSecs = TrEndgetsecs(n);
        end
    end
end
% ex.times.timelog = PsychDataPixx('GetTimestampLog',1);
ex.times.remappingSD = sd;
ex.times.PTBvsDatapixxClockRatio = ratio;
% PsychDataPixx('ClearTimestampLog');
ex.quit = 0;

% make sure to switch off fixed Seed if it was turned on
if isfield(ex.stim.vals,'fixedSeed')
    ex.stim.vals.fixedSeed = false;
end

% save file
cur_dir = cd(ex.Header.onlineExperimentalDirName);

%cur_dir = cd(ex.Header.onlineDirName);
disp('saving...')

% 2021.03.08 ik: check the size of ex, if it exceeds 2GB, use '-v7.3' flag
whosEx = whos('ex');
if whosEx.bytes < 1e+9
    save(fname, 'ex');
else
    save(fname,'ex','-v7.3');
end
cd(cur_dir)

%update log
% dailyLog.nTrialsPerDay = dailyLog_old.nTrialsPerDay+ex.goodtrial;
% dailyLog.nCorrectTrialsPerDay = dailyLog_old.nTrialsPerDay + ex.goodtrial;
dailyLog = finalizeDailyLogSessionx(dailyLog, dailyLog_old, ex, fname);
cur_dir = cd(dirName);
save('dailyLog','dailyLog');
cd(cur_dir);
% updateGuiLogs(dailyLog);

% iknew 06.08.2022
% copy edf file to data foler if Eyelink is on
if eyeOn && Eyelink('IsConnected') == 1 && strcmpi(ex.setup.eyeTracker,'Eyelink')
    fprintf('Transferring EDF file: %s...\n',ex.Header.edfFileName);
    % xx new (clean)
    Eyelink('ReceiveFile',ex.Header.edfFileName,edfDir,1);
    % make a copy of edf file
    edfLocalName = sprintf('%s/%s',edfDir,regexprep(fname,'.mat','.edf'));
    copyfile(sprintf('%s/%s',edfDir,ex.Header.edfFileName),edfLocalName)
    % x old:
    % Eyelink('ReceiveFile',ex.Header.edfFileName,dirName,1);
    % % make a copy of edf file
    % edfLocalName = sprintf('%s/%s',dirName,regexprep(fname,'.mat','.edf'));
    % copyfile(sprintf('%s/%s',dirName,ex.Header.edfFileName),edfLocalName)

    fprintf('%s transferred and copied as %s\n',ex.Header.edfFileName,...
        edfLocalName);
    % The session is over; leave the tracker offline and let displayCleanup
    % close the windows. Drawing here can mask an earlier trial error.
end

% Remove temporary task checkpoints; retain separately saved practice files.
cleanupCoPsTrialDirectoryx(trDir);

ShowCursor
if ex.j > ex.finish && ~ex.SessionEnd.endedEarly && ~isempty(ex.Trials) && ...
        isfield(ex.Trials, 'endScreenAcknowledged') && ex.Trials(end).endScreenAcknowledged
    fprintf('Session complete: participant pressed SPACE on the end screen.\nData saved: %s\n', ...
        fullfile(ex.Header.onlineExperimentalDirName, fname));
end
if recordingEnabled
    for movieIndex = 1:numel(ex.MovieFiles)
        fprintf('Movie saved: %s\n',ex.MovieFiles{movieIndex});
    end
elseif isfield(ex,'Payout')
    fprintf('Participant bonus: $%.2f (%d points / %d completed task trials; average %.4f).\nData saved: %s\n', ...
        ex.Payout.bonusDollars,ex.Payout.totalPoints,ex.Payout.nTrials,ex.Payout.averagePointsPerTrial, ...
        fullfile(ex.Header.onlineExperimentalDirName,fname));
end
end


function mustBeStimulusDirectoryOrEmpty(folder)
if strlength(folder) > 0 && ~isfolder(folder)
    error('CoPs:StimulusDirectory','Stimulus directory does not exist: %s',folder);
end
end

function ex = useStimulusDirectoryLocal(ex,folder)
[ok,attributes] = fileattrib(char(folder));
if ~ok
    error('CoPs:StimulusDirectory','Cannot resolve stimulus directory: %s',folder);
end
resolved = attributes.Name;
[parent,name] = fileparts(resolved);
ex.exp.CoPs.dirs.all = [resolved filesep];
ex.exp.CoPs.graph.texture_root = parent;
ex.exp.CoPs.graph.texture_folder = name;
ex.exp.CoPs.graph.texture_folder_resolved = ex.exp.CoPs.dirs.all;
if isfield(ex.setup,'testConfig')
    ex.setup.testConfig.stimulusRoot = resolved;
end
end

function windowSizePx = defaultWindowSizePx(profileName)
if strcmpi(strtrim(profileName), 'mouse_mini')
    windowSizePx = [2560 1440];
    %windowSizePx = [960 540];%1080×1080
else
    windowSizePx = [2560 1440];
end
end
