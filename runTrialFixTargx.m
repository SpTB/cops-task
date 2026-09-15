function [ex] = runTrialFixTargx(ex)
% run TrialFixTarg, forked off runTrialTask_new
% fixate on target (position in ex.targ.Pos(1,:) )instead
% of the fixation marker (position in ex.fix.Pos).
% Required for validation of eye calibration

% history of runTrialTask
% 6/17/14   hn: RDS dot patterns are no longer stored for each trial.
%           instead: ex.Trials(ex.j).rngState = rng; ex.Trials(ex.j).ndots
%           (number of dots in each RDS)
% 7/01/14   hn: enable randomized target onset during stimulus presentation
%           for this, targ-on state had to be removed; Instead, I now have
%           a separate state variable only for the targets
% 7/06/14   now storing all the times of events in ex-structure
% 07/11/14  hn: -included field 'setup' and moved setup parameters into it
%               new parameter name          old parameter name
%               ex.setup.Clut               ex.Clut
%               ex.setup.stereo             ex.stereo
%               ex.setup.window             ex.window
%               ex.setup.screen_number      ex.screenNum
%               ex.setup.screenRect         ex.screenRect
%               ex.setup.overlay            ex.overlay
%               ex.setup.refreshRate        ex.refreshrate

% history of runTrialStim_new
% 07/27/14  hn: started it
% 07/27/14  hn: included read-in of mouse positions to change stimulus x,y
% 07/29/14  hn: included read-in of RF center position and display on
%               overlay screen
% 08/02/14  hn: included read-in of helper lines on the screen (eg. RF
%               borders) and display on overlay screen
%               included re-centering of eye positions
% 08/31/14  hn: included read in of iontophoresis input;

% history of runTrialFixTarg
% 09/01/14  hn: started it
% 09/04/14  hn: included Datapixx trialStart time to match up PTB and
%               Datapixx clocks
% 11/19/24  bt: removed time out with 'o' (ex.quit == 3)

% ------------------------------------------------------------------------
% pretrial allocations, stimulus generation and setup
% ------------------------------------------------------------------------
fpPos = ex.fix.PCtr+ex.targ.Pos(1,:);
fpSz = ex.calib.Psz;%ex.fix.PSz;

% converting pixels to degrees (needed to change stimulus position with mouse)
dpp = visualPxToDeg(1, ex.setup);
ppd = 1/dpp;  % pixels per degree
showMouseTrace = isfield(ex, 'valid') && isfield(ex.valid, 'showMouseTrace') && ...
    logical(ex.valid.showMouseTrace);

% initial color assignments------------------------------------
fpCol = ex.idx.bg;
t1Col = ex.idx.bg;
t2Col = ex.idx.bg;
targWinCol = ex.idx.bg;

% assign colors for eye and mouse positions (overlay dots: ol)
if ~isempty(ex.eyeCal.LXPos)
    if ~ ex.setup.stereo.Display
        olColBinoc = [ex.idx.overlayRed,ex.idx.overlayGreen,ex.idx.overlayBlue, ex.idx.overlayGreen]; % right,left,binoc, mouse
        olColBinoc = [olColBinoc'*ones(1,3)];
    else
        olColBinoc = [ex.idx.overlay,ex.idx.overlay ex.idx.overlay ex.idx.overlay]; % right, left, binoc, mouse
        olColBinoc = [olColBinoc'*ones(1,3)];
    end
    olPSz = [ceil(ex.setup.eyePSz/2)*ones(2,1); ex.setup.eyePSz; 2]; % eye (R,L,B), mouse
    if ~showMouseTrace
        olColBinoc = olColBinoc(1:end-1, :);
        olPSz = olPSz(1:end-1);
    end
else
    nOverlayDots = 1 + double(showMouseTrace);
    olColBinoc = ex.idx.overlay*ones(nOverlayDots,3); %
    olPSz = ex.setup.eyePSz*ones(nOverlayDots, 1);
    if showMouseTrace
        olPSz(end) = 2; % eye, mouse pos
    end
end

% pre-allocate memory; initialize variables
frametimestep = 1/ex.setup.refreshRate;
eyetimestep = 1/ex.setup.adc.Rate;  % 500Hz is the fastest Eyelink sample binocularly
maxTrialDur = max(ex.fix.waitstop+ex.fix.freeduration+ex.fix.duration + ...
    ex.targ.go_delay+ex.targ.duration);

% helper variables to compute bar orientation
a = NaN;
b = NaN;

% loop indices
fi = 1; % frame index
si = 0; % frame index for stimulus
ei = 1; % frame index for eye sampling

% time variables
time_fpOn = NaN;
time_fpOff = NaN;  % this is the go cue
time_startFixation = NaN;
time_breakFixation = NaN;
time_fixationComplete = NaN;
time_fpOff = NaN;
time_reward = NaN;  % time when reward is given
time_error = NaN;   % time when error signal (if any) is played

line_t0 = GetSecs; % hack to prevent several line-updates per key-press
centerEye_t0 = GetSecs; % hack to prevent several re-centerings of eye position per key-press

% timing information on PTB display
flip_info = NaN(ceil(maxTrialDur*ex.setup.refreshRate),4); %[VBLTimestamp StimulusOnsetTime FlipTimestamp Missed]

%%
%initialize eye structure
trEye.v = NaN(length(ex.setup.adc.Channels),ceil(maxTrialDur*ex.setup.adc.Rate)); % pre-allocate memory
trEye.t = NaN(1,ceil(maxTrialDur*ex.setup.adc.Rate));
trEye.n = 0; % nAcquiredFrames
trEye.sacc = [];
%%
% initialize trial variables
pass_eye = 0;
if ~isempty(ex.eyeCal.LXPos)
    lastEyePos = [0 0;0 0];
else
    lastEyePos = [0 0];
end
[x,y] = GetMouse;
mousePos = [x+ex.setup.mouseXOffset,y];
first_choice = 0;
tchosen = 0;
RewardSize = 0;
lasteyepostime = 0;
lastframet = 0;
ex.loopcnt(ex.j) = 0;
ex.tocsFLIP{ex.j} = [];
ex.tocsGETMOUSE{ex.j} = [];

ex.stim.vals.framecnt = 0;

% MAKE STIMULUS AND REFRESH BACKGROUND-----------------------------------
[ex,RDS]=makeStimulus(ex);
StimStart = NaN*ones(1,ceil(ex.setup.refreshRate*ex.fix.duration));

% new: rotation setting
hasCalibImage = isfield(ex,'valid') && isfield(ex.valid,'img') && ~isempty(ex.valid.img);
if hasCalibImage
    fpImg = imread(ex.calib.img);
    fpTex = Screen('MakeTexture', ex.setup.window, fpImg);

    if isfield(ex,'valid') && isfield(ex.valid,'rotSpeedDegPerSec')
        rotSpeedDegPerSec = ex.valid.rotSpeedDegPerSec;
    elseif isfield(ex,'calib') && isfield(ex.calib,'rotSpeedDegPerSec')
        rotSpeedDegPerSec = ex.calib.rotSpeedDegPerSec;
    else
        rotSpeedDegPerSec = 0;
    end
else
    rotSpeedDegPerSec = 0;
end


% DRAW OVERLAY ITEMS THAT ARE FIXED DURING THE TRIAL --------------------
% (RF, FP frame, helper lines, correct target, if needed)
% draw these first to save timing during the while loop
drawOverlayHelperLines(ex);
drawOverlayFrames(ex,ex.targ.Pos(1,:));

% -----------------------------------------------------------------------
% TRIAL START
% ------------------------------------------------------------------------
% use clock time as unique trial ID
% clocktime: 1x6 vector: year month day hour(1:24) min sec
clocktime = fix(clock); % send strobe of this to rppl for trial identification

% iknew 6.27.2022
% send trial number to Eyelink
Eyelink('Message','trialNumber %d',ex.j)


% we store both the unique trial ID and the trial number in the ripple file
% This might be overkill and we can remove unique trial ID in the future.
%
% this also helps to wake up the port as for this timing is not essential
sendStrobes([ex.strobe.TRIAL_ID,clocktime,ex.strobe.TRIAL_NUMBER,ex.j]);
trstart = GetSecs;  % start of trial time
sendStrobe(ex.strobe.TRIAL_START);  % this takes up to ~1ms which we need to account for
trstartDatapixx = Datapixx('GetTime');  % to match up the Datapixx clock and the PTB clock
trstartEyelink = Eyelink('TrackerTime');
ttime = GetSecs-trstart; %  trial time

state = 0;
while state ~= ex.states.BREAKFIX && state~=ex.states.REWARD &&...
        state ~= ex.states.ERROR && state~=ex.states.NOCHOICEMADE && ...
        state ~= ex.states.SWITCHCHOICE && ...
        state ~=     ex.states.NOFIX && ex.quit == 0 &&ttime>0
    %tic;
    %--------------------------------------------------------------------
    % START STATE CHANGES -----------------------------------------------
    % BEFORE FIXATION DOT -----------------------------------------------
    if  state == ex.states.START && ttime > ex.fix.freeduration
        state = ex.states.FPON;
        fpCol = ex.idx.white;
        %disp('in fixation dot on');
        time_fpOn = GetSecs - trstart;
    end
    % WAITING FOR SUBJECT FIXATION --------------------------------------
    if  state == ex.states.FPON && ttime < ex.fix.waitstop && pass_eye
        time_startFixation = GetSecs - trstart;
        sendStrobe(ex.strobe.FIXATION_START)
        state = ex.states.FPHOLD;
        %disp('in fixation acquired');
    elseif state == ex.states.FPON && ttime > ex.fix.waitstop
        state = ex.states.NOFIX;
        %disp('in no fixation acquired');
        time_breakFixation = GetSecs - trstart;
    end
    % HOLD FIXATION -----------------------------------------------------
    if state == ex.states.FPHOLD;
        % check if fixation is broken
        %if ttime < time_startFixation + ex.fix.duration &&~ pass_eye
        if ~ pass_eye
            state = ex.states.BREAKFIX;
            %disp('in breakfix');
            time_breakFixation = GetSecs - trstart;
            % if fixation is held until end of fixduration, move to next
            % state
        elseif ttime > time_startFixation + ex.fix.duration && pass_eye
            state = ex.states.FIXATIONCOMPLETE;
            %disp('in trial complete');
            time_fixationComplete = GetSecs - trstart;
        end
    end
    % REWARD if fixation is held after trial is completed ----------------
    if state == ex.states.FIXATIONCOMPLETE  && pass_eye
        state = ex.states.REWARD;
    end
    
    %---------------------------------------------------------------------
    % END STATE CHANGES --------------------------------------------------
    %---------------------------------------------------------------------
    
    % update eye position (fast)
    ttime = GetSecs-trstart;
    if ttime > lasteyepostime + eyetimestep
        [pass_eye,trEye,lastEyePos,tchosen] = checkEyexx(trEye,ex,ex.targ,pass_eye,lastEyePos,tchosen);
        if find(tchosen) ==1;
            pass_eye = 1;
        else pass_eye = 0;
        end
        lasteyepostime = ttime;
        ei = ei+1;
    end
    
    % update frame stuff (slow)
    ttime = GetSecs-trstart;
    if ttime > lastframet + frametimestep - 0.008;
        
        %Prepare single screen call for all onscreen dots ( fp, eyepos, mousepos)
        if isempty(ex.eyeCal.LXPos) %monocular eye position
            olPos = lastEyePos; % eye pos
            if showMouseTrace
                olPos = [olPos;mousePos]; % mouse pos
            end
            dotPos=  [fpPos]; % fixation on ex.targ.Pos(1,:) is required
            
        else %overlay dot positions: binocular eye positions; mouse
            olPos = [lastEyePos;
                mean(lastEyePos,1)]; % mean R/L eye position
            if showMouseTrace
                olPos = [olPos;mousePos]; % mouse positions
            end
            dotPos =  [fpPos]; % fixation on ex.targ.Pos(1,:) is required
        end
        dotSz =  [fpSz];
        dotCol =  [fpCol*ones(1,3)];
        
        %% draw eye dots, mouse position
        Screen('FillRect', ex.setup.window, ex.valid.background_color); % xx new: background color
        Screen('Drawdots',ex.setup.overlay,olPos',olPSz',olColBinoc');
        
        %% draw FP,target and eye dots
       %% draw FP,target and eye dots
       
        if hasCalibImage
            rotDeg = mod(ttime * rotSpeedDegPerSec, 360);
            dstRect = CenterRectOnPointd([0 0 ex.calib.Psz+200 ex.calib.Psz+200], fpPos(1), fpPos(2));
            if ~ ex.setup.stereo.Display
                Screen('DrawTexture', ex.setup.window, fpTex, [], dstRect, rotDeg);
            else
                Screen('SelectStereoDrawBuffer', ex.setup.window, 0);
                Screen('DrawTexture', ex.setup.window, fpTex, [], dstRect, rotDeg);

                Screen('SelectStereoDrawBuffer', ex.setup.window, 1);
                Screen('DrawTexture', ex.setup.window, fpTex, [], dstRect, rotDeg);
            end
        else
            
            if ~ ex.setup.stereo.Display
                Screen('Drawdots',ex.setup.window,dotPos',dotSz',dotCol');
            else
                Screen('SelectStereoDrawBuffer', ex.setup.window, 0);
                Screen('Drawdots',ex.setup.window,dotPos',dotSz',dotCol');

                Screen('SelectStereoDrawBuffer', ex.setup.window, 1);
                Screen('Drawdots',ex.setup.window,dotPos',dotSz',dotCol');
            end
        end


        % independent version (prolly not worth it)
        % if isempty(ex.valid.img)
        %     if ~ ex.setup.stereo.Display
        % 
        %         Screen('Drawdots',ex.setup.window,dotPos',dotSz',dotCol');
        %     else
        %         Screen('SelectStereoDrawBuffer', ex.setup.window, 0);
        %         Screen('Drawdots',ex.setup.window,dotPos',dotSz',dotCol');
        % 
        %         Screen('SelectStereoDrawBuffer', ex.setup.window, 1);
        %         Screen('Drawdots',ex.setup.window,dotPos',dotSz',dotCol');
        %     end
        % else
        %        fpImg = imread(ex.valid.img);   
        %        fpTex = Screen('MakeTexture', ex.setup.window, fpImg);
        %        dstRect = CenterRectOnPointd([0 0 fpSz+200 fpSz+200], fpPos(1), fpPos(2));
        %        %if ~ ex.setup.stereo.Display
        %        Screen('SelectStereoDrawBuffer', ex.setup.window, 0);
        %        Screen('DrawTexture', ex.setup.window, fpTex, [], dstRect);
        % 
        %        Screen('SelectStereoDrawBuffer', ex.setup.window, 1);
        %        Screen('DrawTexture', ex.setup.window, fpTex, [], dstRect);
        %         %Screen('DrawTexture', ex.setup.window, fpTex, [], fpRect);
        %        %end
        % end
        
            
        tic
        % Play Stimulus
        if state == ex.states.FPHOLD
            ex=playStimulus(ex,RDS,ttime-time_startFixation);
            si = si+1;
        end
        tic
        Screen('DrawingFinished', ex.setup.window);
        [flip_info(fi,1), flip_info(fi,2), flip_info(fi,3), ...
            flip_info(fi,4)] = Screen('Flip', ex.setup.window);
        ex.tocsFLIP{ex.j} = [ex.tocsFLIP{ex.j} toc];
        
        % store Stimulus frame onsets
        if state == ex.states.FPHOLD
            StimStart(si) = flip_info(fi,1);
        end
        lastframet = 0;
        fi = fi+1;
    end
    
    % give feedback (exact timing is less crucial now)
    if state== ex.states.REWARD
        disp('in reward')
        RewardSize = ex.reward.time;
        
        %playTone
        time_reward = GetSecs - trstart;
        giveReward(RewardSize);
    elseif state== ex.states.BREAKFIX
        %playNoise
        time_error = GetSecs - trstart;
        disp('in ERROR')
    end
    ex.loopcnt(ex.j) = ex.loopcnt(ex.j)+1;
    
    ttime = GetSecs-trstart;
    
    
    % keyboard

    [keyIsDown, secs, keyCode] = KbCheck; % MAGIC NUMBER
    if ~isMatlabWindowFocusedLocal()
        keyCode = zeros(size(keyCode));
    end
    
    if strcmpi(KbName(keyCode),'F4');  %% quit
        ex.quit = 4;
        state
    elseif strcmpi(KbName(keyCode),'F1');  %% pause with gray screen
        ex.quit = 1;
        playRandomLines(ex);
        state
    elseif strcmpi(KbName(keyCode),'F2');  %% pause with black screen
        ex.nCorrectChoice = 0;
        ex.quit = 2;
    end
    
    % mouse input
    tic
    [x,y,b] = GetMouse;
    mousePos = [x+ex.setup.mouseXOffset,y];
    ex.tocsGETMOUSE{ex.j} = [ex.tocsGETMOUSE{ex.j} toc];
    % if mouse left button is pressed, use new x,y positions for stimulus
    % if right mouse button is pressed, use it to update the orientation
    % if "h" is pressed, use mouse position to update stimulus height
    % if "w" is pressed, use mouse position to update stimulus width
    % change orientation when right mouse button is pressed
    if  b(2)>0
        b = (y-ex.fix.PCtr(2))*dpp-ex.stim.vals.y0;
        a = (x+ex.setup.mouseXOffset-ex.fix.PCtr(1))*dpp - ex.stim.vals.x0;
        if ~ isnan(atan(b/a)*180/pi)
            ex.stim.vals.or = -atan(b/a)*180/pi;
        end
        % change x/y position when left mouse button is pressed
    elseif  b(1)>0
        ex.stim.vals.x0 = (x+ex.setup.mouseXOffset-ex.fix.PCtr(1))*dpp;
        ex.stim.vals.y0 = (y-ex.fix.PCtr(2))*dpp;
        % change stimulus height when 'h' is pressed
    elseif strcmpi(KbName(keyCode),'h')
        b = (y-ex.fix.PCtr(2))*dpp-ex.stim.vals.y0;
        a = (x+ex.setup.mouseXOffset-ex.fix.PCtr(1))*dpp - ex.stim.vals.x0;
        ex.stim.vals.hi = sqrt(a.^2+b^2);
        % change stimulus width when 'w' is pressed
    elseif strcmpi(KbName(keyCode),'w')
        b = (y-ex.fix.PCtr(2))*dpp-ex.stim.vals.y0;
        a = (x+ex.setup.mouseXOffset-ex.fix.PCtr(1))*dpp - ex.stim.vals.x0;
        ex.stim.vals.wi = sqrt(a.^2+b^2)/5;
        % get RF position when 'r' is pressed
    elseif strcmpi(KbName(keyCode),'r')
        ex.extras.rfx =  (x+ex.setup.mouseXOffset-ex.fix.PCtr(1))*dpp;
        ex.extras.rfy = (y-ex.fix.PCtr(2))*dpp;
        % add new line when 'l' is pressed
    elseif strcmpi(KbName(keyCode),'l')
        % to make sure that we only update the line once per keyboard press
        if GetSecs-line_t0 > .1
            ex.extras.line = [ex.extras.line,[x+ex.setup.mouseXOffset; y]];
            line_t0 = GetSecs;
        end
        % clear alls lines when 'a' and 'c' and'l' are pressed
    elseif sum([strcmpi(KbName(keyCode),'a'), ...
            strcmpi(KbName(keyCode),'c'), strcmpi(KbName(keyCode),'l')])>=3
        ex.extras.line = [];
        % center Eye when 'x' and 'y' are pressed
    elseif sum([strcmpi(KbName(keyCode),'z'), ...
            strcmpi(KbName(keyCode),'x')]) >=2
        % to make sure we only re-center once per keyboard press
        if GetSecs - centerEye_t0 > .5
            ex=centerEye(ex);
            disp(['eye recentering #: ' num2str(ex.eyeCal.Delta(1).cnt)])
            centerEye_t0 = GetSecs;
        end
    end
    
end
% ------------------------------------------------------------------------
% done with while loop ---------------------------------------------------
% ------------------------------------------------------------------------
% iknew
trEnd_Eyelink = Eyelink('TrackerTime');

trEnd = GetSecs;  % end of trial time
sendStrobe(ex.strobe.TRIAL_END)

% iknew: 7.1.2022
[~,~,trEnd_Datapixx] = getDatapixxDin(ex.strobe.TRIAL_END);


% blank screen at the end of trial, close offscreen stimulus windows----
ex=closeStimulus(ex);


% -------------------------------------------------------------------------
% store Trial information--------------------------------------------------
% -------------------------------------------------------------------------
ex.Trials(ex.j).ID = clocktime;

% iknew: 6. 28. 22
ex.Trials(ex.j).targ.Pos = ex.targ.Pos(1,:);

% store trial times---------------------------------------------
ex.Trials(ex.j).TrialStart = trstart;
ex.Trials(ex.j).TrialStartDatapixx = trstartDatapixx;
ex.Trials(ex.j).TrialStartEyelink = trstartEyelink;
ex.Trials(ex.j).TrialEnd = trEnd;

% iknew
ex.Trials(ex.j).TrialEndEyelink = trEnd_Eyelink;
ex.Trials(ex.j).TrialEndDatapixx = trEnd_Datapixx; % time stamp read immediately before trstart

ex.Trials(ex.j).times.fpOn = time_fpOn;
ex.Trials(ex.j).times.fpOff = time_fpOff;  % this is the go cue
ex.Trials(ex.j).times.startFixation = time_startFixation;
ex.Trials(ex.j).times.breakFixation = time_breakFixation;
ex.Trials(ex.j).times.reward = time_reward;  % time of starting to give rew
ex.Trials(ex.j).times.error = time_error; % time when error signal (if any) is played


% store display timing, eye info and signals from NPI (iontophoresis unit)
ex.Trials(ex.j).flip_info = flip_info(1:fi-1,:);
ex.Trials(ex.j).Start = StimStart(1:si);
ex.Trials(ex.j).Eye = trEye;
if ex.setup.iontophoresis.on
    ex.Trials(ex.j).iontophoresis = trEye.v(end-1:end,:);
    ex.Trials(ex.j).Eye.v = trEye.v(1:end-2,:);
end


% store behavioral performance and reward information-----------
good = 0;
if state == ex.states.REWARD;
    good = 1;
elseif isfield(ex.stim,'seq')
    fname = fieldnames(ex.stim.seq);
    for n = 1:length(fname)
        eval(['ex.stim.seq.' fname{n} '(end+1) = ex.stim.seq.' fname{n} '(ex.j);']);
        ex.finish = ex.finish+1;
    end
end
% number of successfully completed trials:
ex.goodtrial = ex.goodtrial + abs(good);
ex.Trials(ex.j).Reward = good;
ex.Trials(ex.j).RewardSize = RewardSize;


% read in spikes for this trial from grapevine
if ex.setup.recording
    ex=readSpksInTrial(ex);
end

if ex.valid.plot
    GetFigure('Online Plot');
    % plot Performance and tuning curves if we have spike datadfs
    plotEyePosTraces(ex,trEye)
end

% if ~strcmpi(ex.stim.type,'blank')
%     plotTC(ex)
% end

% increase trial counter----------------------------------------
ex.j = ex.j+1;

% -------------------------------------------------------------------------
% Trial online output for experimenter ------------------------------------
correct = length(find([ex.Trials.Reward]==1));
disp(['# trials:' num2str(ex.goodtrial) '  %success:' ...
    num2str(correct/ex.goodtrial) ])
if (ex.exp.afc)
    disp(['# max trials:' num2str(ex.finish) '  # stim:' ...
        num2str(length(ex.stim.seq)) ' # correct:' num2str(correct)])
end

end

function tf = isMatlabWindowFocusedLocal()
% Return true only when MATLAB desktop/main window is focused.
% If focus cannot be determined (e.g., no desktop/Java), default to true.
tf = true;
if ~usejava('desktop') || ~desktop('-inuse')
    return
end
try
    desktopObj = com.mathworks.mde.desk.MLDesktop.getInstance;
    mainFrame = desktopObj.getMainFrame;
    if ~isempty(mainFrame)
        tf = logical(mainFrame.isActive());
    end
catch
    tf = true;
end
end
