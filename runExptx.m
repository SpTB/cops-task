function runExptx
% my first function to run an experiment using the DataPixx/PTB (daps) setup
% will need to expand:
% -make gui to do input/experimental control (?), check timing here!!!
%
% history
% 11/11/13: hn written (based on 8/31/13)
% 07/11/14  hn: -included field 'setup' and moved setup parameters into it
%               new parameter name          old parameter name
%               ex.setup.stereo             ex.stereo
%               ex.setup.window             ex.window
%               ex.setup.overlay            ex.overlay
% 09/02/14  hn: included ex.exp.StimPerTrial (option for multiple Stimuli
%               presented per trial)
% 03/08/21  ik: when saving ex file, if it exceeds 2GB, use '-v7.3' flag
% 05/20/24: bt: introduced a variable called "reward type" to
% 03/29/23  ik: added runTrialSCMap() fof SC response field mapping
% 05/20/24: bt: introduced a variable called "reward type" to
% provide control over switching between sequential or
% asymmetric reward types (line 192)
% 05/20/24: bt: switch rewardbias at a specific trial number if reward
% asymmetry (line 219)
% 08/19/24  hn: re-enabled control of stimulus duration during 4-per experiment
% 11/19/24  bt: commented out the fixed ex.fix.Duration when StimPerTrial == 4
% 1/21/25: st: changed names of asymmetry types to stimulusAsymmetry and
% responseAymmetry from "asymmetry" alone

global ex
global myhandles
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% flag if we use a big reward %%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%%%%%%% get trellis file name if recording
if ex.setup.recording
    not_recording = 0;
    status = [];
    
    if ex.setup.gv.recording
        try % for backwards compatibility: Trellis version < 1.8; i.e. xippmex version <1.2.1.294
            oper = xippmex('opers');
            status = xippmex('trial',oper);
            ex.Header.XippmexVersion = '<1.2.1.294';
            xippmex('trial',oper,'recording',[],[],1);
            status = xippmex('trial',oper);
        catch
            disp('in catch')
            status = xippmex('trial');
            ex.Header.XippmexVersion = '1.2.1.294'; % came with Trellis 1.8.3
            xippmex('trial','recording',[],[],[]);  % previous settings gave an error
            status = xippmex('trial');
        end
        
        if strcmpi(status.status,'recording')
            %ex.Header.fileNameTrellis = [status.filebase '_' num2str(status.incr_num)];
            ex.Header.fileNameTrellis = sprintf('%s%04d',status.filebase,...
                status.incr_num);
            setGuiVariables(myhandles);
        else
            not_recording=1;
        end
    else
        not_recording = 1;
    end
    status
    
    if not_recording
        ex.Header.fileNameTrellis = [];
        button = questdlg('are you sure you do not want to store the neural data? ' ...
            ,'no recording','yes','no','yes');
        switch button
            case 'yes'
            case 'no'
                return
            case 'cancel'
                disp('forced exit: please respond whether you want to record');
                return
        end
    else
        areas = {'V2'};
        if isfield(ex,'area')
            areas = ex.area;
        end
        answer = inputdlg('which area are you recording from?','Area?',...
            1,areas);
        ex.area = answer;
    end
    
end

ex.j = 1;  % trial counter
ex.goodtrial = 0;
ex.changedBlock = 0;  % keeps track of whether we changed blocks

ex.exp.total_nreps = getCoPsTotalRepsx(ex);
ex.finish = ex.exp.total_nreps;
ex = prepareCoPsTrialParamSchedules(ex);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
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

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% if there are several changes of eye position offset (delta x, delta y)
%%% stored from a previous experiment, use only the last one
ex = resetEyeDelta(ex);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%% store unique experiment ID
clocktime = fix(clock);
sendStrobes([ex.strobe.FILE_ID,clocktime,ex.strobe.EXPERIMENT_START]);

ex.Header.fileID = clocktime;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%% make filename and, if needed, a directory where to store current file
if isfield(ex.exp, 'CoPs')
    sfx = makeFilenameSuffixCoPsx(ex);
    [fname,dirName,trDir] = makeFilenameAndDirx(ex, sfx); % no difference right now... (as in v2.7)
else
    [fname,dirName,trDir] = makeFilenameAndDirx(ex);
end

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
ex.nCorrectChoice = 0;
ex.nErrorChoice=0;
if isfield(ex,'fileName')
    ex = rmfield(ex,'fileName');
end


ex.Header.onlineFileName = fname;
ex.Header.onlineDirName = dirName;

fix_duration = ex.fix.duration;
stimDuration = ex.fix.stimDuration;

ex.nStimFinished = 0;
ex.bigReward = 0;

% iknew 6.8.2022
% open Eyelink edf file
% close any open edf file
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
else dailyLog.nTrialsPerDay = 0;
    dailyLog.nCorrectTrialsPerDay = 0;
end
cd(cur_dir);

dailyLog_old = dailyLog;

% keep track of hte number of trials after a shake for which we scale down
% the rewards after shakes and keep track of the number of
ex.reward.nTrialsAfterShake = inf; % default baseline

% 05/20/24: bt: introduced a variable called "ex.reward.type" to
% provide control over switching between sequential or
% asymmetric reward types
% 1/21/25: st: changed names of asymmetry types to stimulusAsymmetry and
% responseAymmetry from "asymmetry" alone
if ex.exp.afc
    if strcmp(ex.reward.type((end-8):end),'Asymmetry')
        switch_trials = ex.reward.switchTrials;
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%% run Experiment
while ex.j <= ex.finish && ex.quit~=4
    HideCursor
    dailyLog.nTrialsPerDay = dailyLog_old.nTrialsPerDay+ex.goodtrial;
    % if isfield(ex,'Trials') && isfield(ex.Trials,'Reward')
    % correct = length(find([ex.Trials.Reward]==1));
    % dailyLog.nCorrectTrialsPerDay = dailyLog_old.nCorrectTrialsPerDay + correct;
    % else dailyLog.nCorrectTrialsPerDay = dailyLog_old.nTrialsPerDay + ex.goodtrial;
    % end
    cur_dir = cd(dirName);
    save('dailyLog','dailyLog');
    cd(cur_dir);
    updateGuiLogs(dailyLog);
    % adjust the down-scaling of the reward; default is 1
    % ex.reward.scale = min([ex.reward.scaleStepSize+ex.reward.nTrialsAfterShake*ex.reward.scaleStepSize,1]);
    % 05/20/24: bt: switch rewardbias at a specific trial number if reward
    % asymmetry
    % 1/21/25: st: changed names of asymmetry types to stimulusAsymmetry and
    % responseAymmetry from "asymmetry" alone
    % if strcmp(ex.reward.type((end-8):end),'Asymmetry')
    %     if ~isempty(switch_trials) && dailyLog.nTrialsPerDay > switch_trials(1)
    %         ex.reward.rewardBias = fliplr(ex.reward.rewardBias);
    %         switch_trials = switch_trials(2:end);
    %     end
    % end
    
    if ex.quit == 0
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %%%%%%%%%%%%%%%%% run Trial
        resetAdcBuffer(ex);  %% reset AdcBuffer for EyeSignals
        if ex.exp.afc %&& ex.reward.nTrialsAfterShake >ex.reward.nTrialsThreshold
            %ex.reward.scale = 1; % for the task we want to use the default reward size
            ex = runTrialTask(ex);
            
        else
            
            if ismember(ex.exp.scmap,[1,2])       % added by ik, 3.29.2023.
                ex = runTrialSCMap(ex);
            elseif isfield(ex.exp,'CoPs') && ex.exp.CoPs
                ex = runTrialTaskCoPs(ex);
            else
                ex = runTrialStim(ex);
            end
            
            % if ex.setup.recording &&  ex.exp.scmap && ...
            %         ex.j > ex.exp.StimPerTrial && ...
            %         ex.Trials(ex.j-ex.exp.StimPerTrial).Reward && ...
            %         ex.nStimFinished == 0
            %     tic
            %     scmap('addTrials');
            %     etime = toc;
            %     fprintf('\n\nscmap took %5.4f\n\n',etime);
            % end
            
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

% store additional information
ex.fix.duration = fix_duration;
%ex.fix.stimDuration = stimDuration; % hn: not necessary


% get GetSecs timestamps remapped onto Datapixx TrialStart and TrialEnd
TrStartDP = [ex.Trials.TrialStartDatapixx];
TrEndDP = [ex.Trials.TrialEndDatapixx];
[tgetsecs, sd, ratio] = PsychDataPixx('BoxsecsToGetsecs',[TrStartDP,TrEndDP]);
TrStartgetsecs = tgetsecs(1:length(TrStartDP));
TrEndgetsecs = tgetsecs(length(TrStartDP)+1:end);
for n = 1:length(TrStartDP)
    ex.Trials(n).TrialStart_remappedGetSecs = TrStartgetsecs(n);
    ex.Trials(n).TrialEnd_remappedGetSecs = TrEndgetsecs(n);
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
cur_dir = cd(ex.Header.onlineDirName);
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

dailyLog.nTrialsPerDay = dailyLog_old.nTrialsPerDay+ex.goodtrial;
if isfield(ex,'Trials') && isfield(ex.Trials,'Reward')
    correct = length(find([ex.Trials.Reward]==1));
    dailyLog.nCorrectTrialsPerDay = dailyLog_old.nCorrectTrialsPerDay + correct;
else
    dailyLog.nCorrectTrialsPerDay = dailyLog_old.nTrialsPerDay + ex.goodtrial;
end
cur_dir = cd(dirName);
save('dailyLog','dailyLog');
cd(cur_dir);
updateGuiLogs(dailyLog);


%%%%%%%%%%%%%%%%%%%%%%%%%% put trellis in standby
if ex.setup.recording
    not_recording = 0;
    try % for backwards compatibility: Trellis version < 1.8; i.e. xippmex version <1.2.1.294
        oper = xippmex('opers');
        status = xippmex('trial',oper);
        if strcmpi(status.status,'recording')
            xippmex('trial',oper,'stopped',[],[],[1,[]]);
        end
    catch
        status = xippmex('trial');
        if strcmpi(status.status,'recording')
            xippmex('trial','stopped',[],[],[1,[]]);
        end
    end
    
end

% iknew 06.08.2022
% copy edf file to data foler if Eyelink is on
if Eyelink('IsConnected') == 1 && strcmpi(ex.setup.eyeTracker,'Eyelink')
    fprintf('Transferring EDF file: %s...\n',ex.Header.edfFileName);
    Eyelink('ReceiveFile',ex.Header.edfFileName,dirName,1);
    % make a copy of edf file
    edfLocalName = sprintf('%s/%s',dirName,regexprep(fname,'.mat','.edf'));
    copyfile(sprintf('%s/%s',dirName,ex.Header.edfFileName),edfLocalName)
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
