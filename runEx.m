function ex = runEx(eyeStr, overlayOn, pixOn, rewOn, eyeOn,skipQuest)
% with full questionnaire...

arguments
    eyeStr {mustBeText} = 't' % 'y' for 'yes, calibrate', 'l' for load, 't' for test
    overlayOn  {mustBeNumericOrLogical} = 1
    pixOn  {mustBeNumericOrLogical} = true
    rewOn {mustBeNumericOrLogical} = true
    eyeOn  {mustBeNumericOrLogical} = true
    skipQuest {mustBeNumericOrLogical} = true
end

Datapixx('Close')
Eyelink('Shutdown');
ex = struct();
if ~Datapixx('Open')
    initDatapixx(ex);
end

ex = setDefaultsCoPs(ex);

ex=getDefaultSettingsx(ex, skipQuest);
ex.states.PREGO = 5.95

if eyeOn
    ex = initDisplayxx(ex, overlayOn);
else
    ex = initDisplayx(ex );%can run initDisplayx for normal view
end
pause(1)

if eyeOn
    
    ex.setup.VSdirRoot = pwd;
    % handles = initEyeHandlesx(ex);
    % ex = initEyelink(ex, handles);
    ex = initEyelink(ex);
    ex.eyeCal = [];
    % ex.idx.bg = 0; % black test
    ex.calib = setDefaultsCalib(); % default eye calibration settings
    ex.valid = setDefaultsValid(); % default eye validation settings
    ex = resolveCalibrationValidationDisplaySizes(ex);

    switch lower(eyeStr)
        
        case 'y' % legacy calibration
            %ex = calibrateEye_rev(ex);
            ex = calibrateEyex(ex);
            disp('eye calibration done')
        case 't'
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

if ex.setup.el.binoc==0
    ex.eyeCal.LXPos = [];
    ex.eyeCal.LYPos = [];
end
%run Expt starts
ex.j = 1;  % current trial number
ex.goodtrial = 0;  % counter for successful trials
ex.loopcnt = zeros(1, ex.finish);  % loop counter for each trial
ex.changedBlock = 0;  % keeps track of whether we changed blocks
ex.exp.total_nreps = getCoPsTotalRepsx(ex);
ex.finish = ex.exp.total_nreps;
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
sendStrobes([ex.strobe.FILE_ID,clocktime,ex.strobe.EXPERIMENT_START]);

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
if Eyelink('IsConnected') == 1
    
    Eyelink('SetOfflineMode')
    Eyelink('CloseFile');
    
    % only when Eyelink is used to record eye positions
    if strcmpi(ex.setup.eyeTracker,'Eyelink')
        % maximum length of an edf file name = 8
        ex.Header.edfFileName = sprintf('%02d%02d%02d%02d.edf',clocktime(2),clocktime(3),...
            clocktime(4),clocktime(5));
        Eyelink('OpenFile',ex.Header.edfFileName);
        Eyelink('Message','exFileName: %s',fname);
        Eyelink('StartRecording');
    end
end

PsychDataPixx('GetPreciseTime'); % synchronizes Datapixx and PTB clocks (takes about .5sec)

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

while ex.j <= ex.finish && ex.quit~=4
    HideCursor
    dailyLog.nTrialsPerDay = dailyLog_old.nTrialsPerDay+ex.goodtrial;
    cur_dir = cd(dirName);
    save('dailyLog','dailyLog');
    cd(cur_dir);
    % updateGuiLogs(dailyLog);
    
    if ex.quit == 0
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %%%%%%%%%%%%%%%%% run Trial
        resetAdcBuffer(ex);  %% reset AdcBuffer for EyeSignals
        
        try
            ex = runTrialTaskCoPsx(ex);
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
playRandomLines(ex);

% signal end of experiment
sendStrobe(ex.strobe.EXPERIMENT_END);

% iknew 06.08.2022
% close edf file
if Eyelink('IsConnected') == 1
    Eyelink('StopRecording')
    Eyelink('SetOfflineMode')
    Eyelink('CloseFile');
end

% get GetSecs timestamps remapped onto Datapixx TrialStart and TrialEnd
sd = NaN;
ratio = NaN;
if isfield(ex, 'Trials') && ~isempty(ex.Trials) && ...
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
ex.Header.onlineDirName = dirName;
ex.Header.onlineExperimentalDirName = expDir;
ex.Header.onlineEdfDirName = edfDir;
cur_dir = cd(ex.Header.onlineExperimentalDirName);

%cur_dir = cd(ex.Header.onlineDirName);
ex.Header.onlineFileName = fname;
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
if Eyelink('IsConnected') == 1 && strcmpi(ex.setup.eyeTracker,'Eyelink')
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
    Eyelink('StartRecording')
    playRandomLines(ex);
end

% remove temporary trial folder
cur_dir = cd(trDir);
delete('*.mat');
a = dir;
cd(cur_dir);
subDirs = 0;
for n = 1:length(a)
    if a(n).isdir && a(n).bytes>0
        subDirs = 1;
        break
    end
end

if ~subDirs
    rmdir(trDir);
else
    warndlg('Trial directory contains subdirectories: there is likely a bug, check!')
end

ShowCursor
