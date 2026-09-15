function ex = calibrateEyexx(ex)
arguments
    ex
end

ex = resolveCalibrationValidationDisplaySizes(ex);
val = ex.valid;
cal = ex.calib;
if ~isfield(cal, 'signedGain') || isempty(cal.signedGain)
    cal.signedGain = true;
end
% function ex = calibrateEye(ex)
% --- initial work around for manual calibration of eye position
%
%
%
% history
% 11/14/13      hn: wrote it
% 04/17/14      hn: extend to binocular measurements
% 07/11/14  hn: -included field 'setup' and moved setup parameters into it
%               new parameter name          old parameter name
%               ex.setup.stereo             ex.stereo
%               ex.setup.window             ex.window
%               ex.setup.screen_number      ex.screenNum
%               ex.setup.screenRect         ex.screenRect
%               ex.setup.overlay            ex.overlay


% iknew - 9.26.2022
% initialize ex.eyeCal

if length(cal.file) > 0 % skip calibration
    exTemp=load(cal.file);
    if isfield(exTemp, 'ex') % whole ex struct case
        ex.eyeCal = exTemp.ex.eyeCal;
    elseif isfield (exTemp, 'eyeCal')
        ex.eyeCal = exTemp.eyeCal;
    else
        error('eyeCal field not found')
    end
else
    
    initialOffset = 0;
    %initialGain = 340;  % Lemieus
    initialGain = cal.initGain;  % for Barnum
    eyeflds = {'RX','RY','LX','LY'};
    
    if ~isfield(ex,'eyeCal')
        ex.eyeCal = [];
    end
    
    if isfield(ex.eyeCal,'Delta')
        ex.eyeCal.Delta = ex.eyeCal.Delta(1);
    end
    
    ex.eyeCal.Delta.cnt = 1;
    
    for i=1:length(eyeflds)
        ex.eyeCal.([eyeflds{i},'0']) = initialOffset;
        ex.eyeCal.([eyeflds{i},'Pos']) = NaN(1,4);
        ex.eyeCal.([eyeflds{i},'Gain']) = initialGain;
        ex.eyeCal.Delta.([eyeflds{i},'0']) = 0;
    end
    
    ex.eyeCal = orderfields(ex.eyeCal,{'RX0','RY0','LX0','LY0','RXPos',...
        'RYPos','LXPos','LYPos','RXGain','RYGain','LXGain','LYGain','Delta'});
    
    
    
    % number of samples per condition
    sampleDur = cal.sampleDur;
    nSamples = round(sampleDur*ex.setup.adc.Rate);
    
    ex.fix.PSz = cal.Psz;
    
    % Background color is set here
    Screen('FillRect', ex.setup.window,cal.background_color);%ex.idx.bg_lum);
    
    Screen('Flip', ex.setup.window);
    disp('click mouse on command window')
    pause(.2)
    disp('press any key to start calibration')
    pause(.2)
    KbWait ; % wait for subject to be ready
    pause(.3)
    resetAdcBuffer(ex);
    Screen('SelectStereoDrawBuffer', ex.setup.window, 0);
    Screen('Drawdots',ex.setup.window,ex.fix.PCtr',ex.fix.PSz',ex.idx.white); % draw FP
    
    Screen('SelectStereoDrawBuffer', ex.setup.window, 1);
    Screen('Drawdots',ex.setup.window,ex.fix.PCtr',ex.fix.PSz',ex.idx.white); % draw FP
    
    Screen('Flip', ex.setup.window);
    
    disp('press any key to accept eye position')
    
    while true
        [v,t,ex.eyeCal] = plotEyePos(ex );
        idx = max([1,length(t)-nSamples]);
        vv = v(:,idx:end);
        spread = acceptanceWindowSpread(vv, ex.eyeCal, ex.fix.PCtr);
        
        if cal.plot
            fig_h=figure;
            plot(t,v')
            legend({'RX','RY','RP','LX','LY','LP'})
            set(fig_h,'position',[1288         553         560         420]);
        end
        
        if spread > cal.sampleRejectThresh
            fprintf('Rejected center sample: window SD %.4f exceeds threshold %.4f. Retrying.\n', ...
            spread, cal.sampleRejectThresh);
            if cal.plot
                close(fig_h);
            end
            pause(.3)
            KbWait;
            pause(.3)
            continue
        end
        
        accepted = summarizeAcceptanceWindow(vv, cal.sampleEstimator);
        if size(v,1)>=5
            ex.eyeCal.RX0 = accepted(1);
            ex.eyeCal.RY0 = accepted(2);
            ex.eyeCal.LX0 = accepted(4);
            ex.eyeCal.LY0 = accepted(5);
        else
            ex.eyeCal.RX0 = accepted(1);
            ex.eyeCal.RY0 = accepted(2);
            ex.eyeCal.LX0 = [];
            ex.eyeCal.LY0 = [];
        end
        break
    end
    
    
    % default calibration positions:
    %  1                2
    %
    %
    %          0
    %
    %
    %  3                4
    
    % iknew
    % number of pixels corresponding a fixed visual angle, e.g., 5 deg
    offset = round(visualDegToPx(5, ex.setup));
    %pos = [0,0;-1,-1;1,-1;-1,1;1,1] * offset;%;-1,-1;1,-1;-1,1;1,1
    %pos = [0,0] * offset* cal.distance_scaling;
    pos1 = [0,0;-1,-1;1,-1;-1,1;1,1;0,0] * offset;
    pos2 = [0,0;-1,-1;1,-1;-1,1;1,1;0,0] * offset/2;
    %pos0 = [0,0; 0,0];
    pos = [pos1; pos2];
    %pos = [0,0; pos_all(randperm(size(pos_all,1)), :)];
    
    % prolly here can adjust how many...
    sizepos = size(pos);
    rp = [0,randperm(sizepos(1)-1)];
    
    ex.eyeCal.RXPos = NaN(1,sizepos(1));
    ex.eyeCal.RYPos = NaN(1,sizepos(1));
    ex.eyeCal.LXPos = NaN(1,sizepos(1));
    ex.eyeCal.LYPos = NaN(1,sizepos(1));
    
    for n = rp
        disp(['press any key to start getting position ' num2str(n)])
        pause(.3)
        KbWait ; % wait for subject to be ready
        pause(.3)
        
        while true
            [v,t] = plotEyePos(ex,pos(n+1,:), false);
            idx = max([1,length(t)-nSamples]);
            vv = v(:,idx:end);
            spread = acceptanceWindowSpread(vv, ex.eyeCal, ex.fix.PCtr);
            
            if cal.plot
                if exist('fig_h','var') && isgraphics(fig_h)
                    close(fig_h);
                end
                fig_h=figure;
                plot(t,v')
                legend({'RX','RY','RP','LX','LY','LP'})
                set(fig_h,'position',[1288         553         560         420]);
                drawnow;
            end
            
            if spread > cal.sampleRejectThresh
                fprintf('Rejected calibration point %d: window SD %.4f exceeds threshold %.4f. Retrying.\n', ...
                    n, spread, cal.sampleRejectThresh);
                pause(.3)
                KbWait;
                pause(.3)
                continue
            end
            
            accepted = summarizeAcceptanceWindow(vv, cal.sampleEstimator);
            if size(v,1)>=5
                ex.eyeCal.RXPos(n+1) = accepted(1);
                ex.eyeCal.RYPos(n+1) = accepted(2);
                ex.eyeCal.LXPos(n+1) = accepted(4);
                ex.eyeCal.LYPos(n+1) = accepted(5);
            else
                ex.eyeCal.RXPos(n+1) = accepted(1);
                ex.eyeCal.RYPos(n+1) = accepted(2);
                ex.eyeCal.LXPos = [];
                ex.eyeCal.LYPos = [];
            end
            break
        end
    end
    
    % robust center estimate from all repeated center samples
    centerMask = pos(:,1)==0 & pos(:,2)==0;
    RX0 = sort(ex.eyeCal.RXPos(centerMask));
    RY0 = sort(ex.eyeCal.RYPos(centerMask));
    if numel(RX0) > 2
        ex.eyeCal.RX0 = mean(RX0(2:end-1));
        ex.eyeCal.RY0 = mean(RY0(2:end-1));
    else
        ex.eyeCal.RX0 = mean(RX0,'omitnan');
        ex.eyeCal.RY0 = mean(RY0,'omitnan');
    end
    
    nonCenterMask = ~centerMask;
    xMask = nonCenterMask & pos(:,1) ~= 0;
    yMask = nonCenterMask & pos(:,2) ~= 0;
    [ex.eyeCal.RXGain, RXGain] = signedEyeCalGain(pos(xMask,1), ex.eyeCal.RXPos(xMask), ex.eyeCal.RX0, cal.signedGain);
    [ex.eyeCal.RYGain, RYGain] = signedEyeCalGain(pos(yMask,2), ex.eyeCal.RYPos(yMask), ex.eyeCal.RY0, cal.signedGain);
    ex.eyeCal.RXGains = RXGain;
    ex.eyeCal.RYGains = RYGain;
    
    if size(v,1)>=5
        LX0 = sort(ex.eyeCal.LXPos(centerMask));
        LY0 = sort(ex.eyeCal.LYPos(centerMask));
        if numel(LX0) > 2
            ex.eyeCal.LX0 = mean(LX0(2:end-1));
            ex.eyeCal.LY0 = mean(LY0(2:end-1));
        else
            ex.eyeCal.LX0 = mean(LX0,'omitnan');
            ex.eyeCal.LY0 = mean(LY0,'omitnan');
        end
        
        [ex.eyeCal.LXGain, LXGain] = signedEyeCalGain(pos(xMask,1), ex.eyeCal.LXPos(xMask), ex.eyeCal.LX0, cal.signedGain);
        [ex.eyeCal.LYGain, LYGain] = signedEyeCalGain(pos(yMask,2), ex.eyeCal.LYPos(yMask), ex.eyeCal.LY0, cal.signedGain);
        ex.eyeCal.LXGains = LXGain;
        ex.eyeCal.LYGains = LYGain;
    else
        ex.eyeCal.LX0 = [];
        ex.eyeCal.LY0 = [];
        ex.eyeCal.LXGain = [];
        ex.eyeCal.LYGain = [];
        ex.eyeCal.LXGains = [];
        ex.eyeCal.LYGains = [];
        
    end
    if cal.plot
        close(fig_h);
        fig_h=figure;
        plot(t,v')
        legend({'RX','RY','RP','LX','LY','LP'})
        set(fig_h,'position',[1288         553         560         420]);
    end
    
    % add offset?
    if cal.yOffset ~=  0
        ex.eyeCal.RY0 = ex.eyeCal.RY0+ cal.yOffset;
        ex.eyeCal.LY0 = ex.eyeCal.LY0+ cal.yOffset;
    end
    disp('done eye calibration')
    
    
    % saving...
    
    % iknew: 7.1.2022
    % second phase - more repetitions and store eye runExitions to ex.Trials
    % borrowed from the validation loop in calibrateEye_long.m
    
    % store the current experimental values
    reward_time = ex.reward.time;
    stim = ex.stim.type;
    finish = ex.finish;
    targ = ex.targ;
    fix_ = ex.fix;
    ex.finish = size(pos,1);
    
end

% extra valid settings here...
ex.targ.WinW = val.targetWin(1);
ex.targ.WinH = val.targetWin(2);
%ex.fix.WinW = 0; xx ????
ex.fix.duration = val.fixDur;
ex.reward.time = val.rewTime;
ex.stim.type = 'blank';
ex.j = 1;
ex.goodtrial = 0;

%
clearkeyboard = input('please press the RETURN key','s');


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%% store unique experiment ID
clocktime = fix(clock);
sendStrobes([ex.strobe.FILE_ID,clocktime,ex.strobe.EXPERIMENT_START]);

ex.Header.fileID = clocktime;

[fname,dirName] = makeFilenameAndDirx(ex,'EyeCal');
dirNameEyeCal = [dirName,'/',fname(1:(end-4))];
ex.Header.onlineFileName = fname;
ex.Header.onlineDirName = dirName;


ex.loopcnt =[];
if isfield(ex,'Trials')
    ex = rmfield(ex,'Trials');
    fnames = fieldnames(ex);
    for n = 1:length(fnames)
        if strfind(fnames{n},'tocs')
            ex = rmfield(ex,fnames{n});
        end
    end
end

% iknew
% number of pixels corresponding a fixed visual angle, e.g., 5 deg
offsets_inDeg = (val.offsetsDeg) * val.distance_scaling;
offsets = round(visualDegToPx(offsets_inDeg, ex.setup));
[x,y] = meshgrid(offsets);
pos = [x(:),y(:)];
%pos = [-1,-1;1,-1;-1,1;1,1] * offset;
%[x,y] = meshgrid(-1:1);
%pos = [x(:),y(:)] * offset;

% iknew 6.27.2022
% open Eyelink edf file
% close any open edf file
if Eyelink('IsConnected') == 1
    Eyelink('SetOfflineMode')
    Eyelink('CloseFile');
    
    % maximum length of an edf file name = 8
    ex.Header.edfFileName = sprintf('%02d%02d%02d%02d.edf',clocktime(2),clocktime(3),...
        clocktime(4),clocktime(5));
    Eyelink('OpenFile',ex.Header.edfFileName);
    Eyelink('Message','exFileName: %s',fname);
    Eyelink('StartRecording')
end

%% validation
if cal.validate
    nRepeat = val.nRepeat;
    nRepeated = 0;
    eyeCal = ex.eyeCal;
    ex.targ.Pos(2,:) = [1000,1000];
    centerIdx = find(pos(:,1) == 0 & pos(:,2) == 0,1,'first');
    useRecenterFirst = isfield(val,'recenterFirst') && val.recenterFirst && ...
        ~isempty(centerIdx);
    useOnlineUpdate = isfield(val,'onlineUpdate') && val.onlineUpdate;
    
    % initialize data table
    varNames = {'TX','TY','RX','RY','LX','LY','reward'};
    nTrials = nRepeat * size(pos,1);
    
    dat = array2table(NaN(nTrials,length(varNames)),'VariableNames',varNames);
    
    
    curr_idx = 1;
    while nRepeated < nRepeat && ex.quit ~= 4
        rp = randperm(size(pos,1));
        if useRecenterFirst && curr_idx == 1
            rp(rp == centerIdx) = [];
            rp = [centerIdx; rp(:)]';
        end
        for i=1:length(rp)
            HideCursor
            if ex.quit == 0
                resetAdcBuffer(ex);
                if useOnlineUpdate
                    ex.eyeCal = eyeCal;
                end
                if useRecenterFirst && curr_idx == 1 && rp(i) == centerIdx
                    ex.fix.duration = val.fixDur * 5;
                else
                    ex.fix.duration = val.fixDur;
                end
                ex.targ.Pos(1,:) = pos(rp(i),:);
                ex = runTrialFixTargx(ex);
                WaitSecs(val.iti);
                if useRecenterFirst && curr_idx == 1 && rp(i) == centerIdx && ...
                        ex.Trials(end).Reward
                    eyeCal = recenterEyeCalFromTrial(ex.Trials(end),eyeCal);
                    if useOnlineUpdate
                        ex.eyeCal = eyeCal;
                    end
                end
                
                [dat,eyeCal] = updateTable(ex.Trials(end),eyeCal,dat,curr_idx);
                %eyeCal
                curr_idx = curr_idx + 1;
                
            elseif ex.quit == 1
                disp('in pause')
                playRandomLines(ex);
                ex.quit = 0;
                keyboard
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
                
                keyboard
                ex.quit = 0;
                ShowCursor
            elseif ex.quit ==3
                disp('in timeout')
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
                pause(0.1)
                ex.quit =4;
            end
        end
        nRepeated = nRepeated + 1;
    end
    if isfield(val,'update') && val.update
        ex.eyeCal = eyeCal;
    end

end

cur_dir = pwd;
ex.dirName = dirName;
cd(dirNameEyeCal);
ex.fileName = fname;
disp('saving...')
save(fname, 'ex');
saveEyeCalDesktopCopy(fullfile(pwd, fname));
cd(cur_dir)
ex.quit = 0;


% iknew 06.27.2022
% close edf file
if Eyelink('IsConnected') == 1
    Eyelink('StopRecording')
    Eyelink('SetOfflineMode')
    Eyelink('CloseFile');
    
    % copy edf file to data foler
    fprintf('Transferring EDF file: %s...\n',ex.Header.edfFileName);
    Eyelink('ReceiveFile',ex.Header.edfFileName,dirName,1);
    % make a copy of edf file
    edfLocalName = sprintf('%s/%s',dirName,regexprep(fname,'.mat','.edf'));
    copyfile(sprintf('%s/%s',dirName,ex.Header.edfFileName),edfLocalName)
    fprintf('%s transferred and copied as %s\n',ex.Header.edfFileName,...
        edfLocalName);
    Eyelink('StartRecording')
end

ShowCursor

%ex.reward.time = reward_time;
%ex.stim.type = stim;
%ex.finish = finish;
%ex.targ = targ;
%ex.fix = fix_;

end

%%----------------------------------------------------- subfunctions------
% -----------------------------------------------------------------------
function [dat,eyeCal] = updateTable(Trial,eyeCal,dat,i)

dat.TX(i) = Trial.targ.Pos(1);
dat.TY(i) = Trial.targ.Pos(2);
dat.reward(i) = Trial.Reward;

t = Trial.Eye.t - Trial.TrialStartDatapixx;

if Trial.Reward
    idx = t >= Trial.times.reward - 0.15 & ...
        t <= Trial.times.reward - 0.05;
else
    idx = t >= Trial.times.startFixation + 0.05 & ...
        t <= min([t(end) - 0.01,...
        Trial.times.startFixation + 0.15]);
end
if ~isempty(idx) && sum(idx) >= 20
    if size(Trial.Eye.v,1)>3
        dat{i,{'RX','RY','LX','LY'}} = ...
            mean(Trial.Eye.v([1,2,4,5],idx),2)';
    else
        dat{i,{'RX','RY'}} = ...
            mean(Trial.Eye.v([1,2],idx),2)';
    end
end

eyeFields = {'RX','RY','LX','LY'};
tFields = {'TX','TY','TX','TY'};
idx0 = dat.TX == 0 & dat.TY == 0;
for i=1:length(eyeFields)
    if any(idx0)
        eyeCal.([eyeFields{i},'0']) = mean(dat.(eyeFields{i})(idx0),'omitnan');
    end
    idx = ~isnan(dat.(eyeFields{i}));
    if length(unique(dat.(tFields{i})(idx))) > 1
        p = polyfit(dat.(tFields{i})(idx),dat.(eyeFields{i})(idx),1);
        eyeCal.([eyeFields{i},'Gain']) = 1/p(1);
    end
end

end

function eyeCal = recenterEyeCalFromTrial(Trial,eyeCal)

t = Trial.Eye.t - Trial.TrialStartDatapixx;

if Trial.Reward
    idx = t >= Trial.times.reward - 0.15 & ...
        t <= Trial.times.reward - 0.05;
else
    idx = t >= Trial.times.startFixation + 0.05 & ...
        t <= min([t(end) - 0.01,...
        Trial.times.startFixation + 0.15]);
end

if sum(idx) < 20
    return
end

if size(Trial.Eye.v,1)>3
    eyeCal.RX0 = mean(Trial.Eye.v(1,idx));
    eyeCal.RY0 = mean(Trial.Eye.v(2,idx));
    eyeCal.LX0 = mean(Trial.Eye.v(4,idx));
    eyeCal.LY0 = mean(Trial.Eye.v(5,idx));
else
    eyeCal.RX0 = mean(Trial.Eye.v(1,idx));
    eyeCal.RY0 = mean(Trial.Eye.v(2,idx));
end

end

% submodules added by ik
% iknew - 9.23.2022

function [v,t,eyeCal] = plotEyePos(ex,Pos,resetOffset)


if nargin == 1
    Pos = zeros(1,2);
    resetOffset = true;
elseif nargin == 2
    resetOffset = false;
end

% if sum(abs(Pos)==0)
%     resetOffset = true;
% end %
% NOTE:
% Reset behavior is controlled explicitly by the resetOffset argument.
% Do not infer reset from Pos == [0 0], because calibration can visit center
% multiple times and we may want reset only on the first center acquisition.

olColBinoc = ex.idx.overlay * ones(3,3); % right, left, binoc, mouse
olPSz = [ceil(ex.setup.eyePSz/2)*ones(1,2), ex.setup.eyePSz]; % eye (R,L,B)

fpPos = ex.fix.PCtr+ex.targ.Pos(1,:);
fpCol = ex.idx.bg * ones(1,3);
bgColor = ones(1,3) * ex.idx.bg;

nBuffers = 10^6;
v = cell(1,nBuffers);
t = cell(1,nBuffers);

% new: rotation setting
hasCalibImage = length(ex.calib.img) > 0;
if hasCalibImage
    fpImg = imread(ex.calib.img);
    fpTex = Screen('MakeTexture', ex.setup.window, fpImg);
end


WaitSecs(0.2);
keyIsDown = false;
i = 0;
waitframes = 10;
ifi = Screen('GetFlipInterval',ex.setup.window);
vbl = Screen('Flip',ex.setup.window);

rotStepDeg = ex.calib.rotSpeedDegPerSec * waitframes * ifi; % new: rotation speed

while ~keyIsDown && i <= nBuffers
    i = i + 1;
    Datapixx RegWrRd
    status = Datapixx ('GetAdcStatus') ;
    if status.newBufferFrames <1
        i = i-1;
        failedReadCnt = failedReadCnt +1;
        if failedReadCnt >10
            sprintf('%s',' no new frames in Buffer; reset Datapixx');
            return
        else
            continue
        end
    end
    [vbad,t{i}] = Datapixx('ReadAdcBuffer',status.newBufferFrames,-1);
    %vbad( vbad > 10 ) = vbad( vbad > 10 ) - 20;
    v{i}=vbad;
    if (max(v{i}(:))>10) || (min(v{i}(:))< -10)
        keyboard
    end
    sizev=size(v{i});
    if sizev(1) < 4% monocular case
        v{i}([1],:) = ex.setup.horEyeSign * v{i}([1],:);
    else
        % added by IK: 06.04.2024
        v{i}([1,4],:) = ex.setup.horEyeSign * v{i}([1,4],:);
    end
    
    if resetOffset && i > 3
        vv = cell2mat(v(i-3:i));
        accepted = summarizeAcceptanceWindow(vv, ex.calib.sampleEstimator);
        if size(vv,1)>=5
            ex.eyeCal.RX0 = accepted(1);
            ex.eyeCal.RY0 = accepted(2);
            ex.eyeCal.LX0 = accepted(4);
            ex.eyeCal.LY0 = accepted(5);
        else
            ex.eyeCal.RX0 = accepted(1);
            ex.eyeCal.RY0 = accepted(2);
            ex.eyeCal.LX0 = [];
            ex.eyeCal.LY0 = [];
        end
    end
    
    if sizev(1) < 4
        p = eyePosInScreen(v{i}([1,2],:),ex.eyeCal,ex.fix.PCtr);
        
    else
        p = reshape(eyePosInScreen(v{i}([1,2,4,5],:),ex.eyeCal,ex.fix.PCtr),...
            2,2);
    end
    olPos = [p, mean(p,2)];
    
    % background
    if isempty(ex.setup.overlay)
        Screen('FillRect', ex.setup.window, bgColor);
    else
        Screen('FillRect', ex.setup.overlay, bgColor);
    end
    
    % make sizes and colors match number of dots in olPos
    if sizev(1)<4
        nDots = 1;%size(olPos, 2);                 % how many dots we actually have
        dotSize = 5;%ceil(ex.setup.eyePSz/2);      % choose a base dot size (your original)
        olPSz = repmat(dotSize, 1, nDots);      % 1 x nDots
    else
        nDots = 3;
    end
    
    % color: either a single RGB triple for all dots, or a 3 x nDots matrix
    % Option A: same RGB for all dots (preferred if ex.idx.overlay is an RGB triple)
    if isvector(ex.idx.overlay) && numel(ex.idx.overlay) == 3
        olCol = ex.idx.overlay;             % 1x3 or 3x1 accepted by PTB
    else
        % Option B: create a 3 x nDots RGB matrix using the overlay index
        olCol = repmat(ex.idx.overlay(:), 1, nDots);  % makes 3 x nDots
    end
    
    if isempty(ex.setup.overlay)
        Screen('DrawDots', ex.setup.window, olPos, olPSz, olCol, [], 2);   % dot type 2 = anti-aliased circle% draw eye dots, mouse position
    else
        Screen('DrawDots', ex.setup.overlay, olPos, olPSz, olCol, [], 2);   % dot type 2 = anti-aliased circle% draw eye dots, mouse position
    end
    
    % draw fixation point
    if hasCalibImage
        fpImg = imread(ex.calib.img);
        fpTex = Screen('MakeTexture', ex.setup.window, fpImg);
        % center used by DrawDots now:
        xy = ex.fix.PCtr + Pos;      % [x y]
        dstRect = CenterRectOnPointd([0 0 ex.calib.Psz+200 ex.calib.Psz+200], xy(1), xy(2));
        rotDeg = mod((i - 1) * rotStepDeg, 360); % rotation
        
        Screen('SelectStereoDrawBuffer', ex.setup.window, 0);
        Screen('DrawTexture', ex.setup.window, fpTex, [], dstRect, rotDeg);
        
        Screen('SelectStereoDrawBuffer', ex.setup.window, 1);
        Screen('DrawTexture', ex.setup.window, fpTex, [], dstRect, rotDeg);
    else
        Screen('SelectStereoDrawBuffer', ex.setup.window, 0);
        Screen('Drawdots',ex.setup.window,ex.fix.PCtr'+Pos',ex.fix.PSz',...
            ex.idx.white); % draw FP
        
        Screen('SelectStereoDrawBuffer', ex.setup.window, 1);
        Screen('Drawdots',ex.setup.window,ex.fix.PCtr'+Pos',ex.fix.PSz',...
            ex.idx.white); % draw FP
    end
    
    Screen('DrawingFinished', ex.setup.window);
    vbl = Screen('Flip', ex.setup.window,vbl + (waitframes - 0.5) * ifi);
    
    keyIsDown = KbCheck;
end

if hasCalibImage
    Screen('Close', fpTex);
end


if isempty(ex.setup.overlay)
    Screen('FillRect',ex.setup.window,bgColor);
else
    Screen('FillRect',ex.setup.overlay,bgColor);
end
Screen('Flip',ex.setup.window);

v = cell2mat(v(1:i));
t = cell2mat(t(1:i));
eyeCal = ex.eyeCal;

end


function p = eyePosInScreen(v,eyeCal,PCtr)
% v is a row vector - [RX, RY, LX, LY]'
samplePos = eyeSamplesInScreen(v, eyeCal, PCtr);
p = mean(samplePos, 2, 'omitnan');
% keyboard
end

function p = eyeSamplesInScreen(v, eyeCal, PCtr)
% v is 2xN or 4xN raw eye voltage matrix; output is in screen pixels.
sizev = size(v);
if sizev(1) == 4 % both eyes case
    offset = [eyeCal.RX0; eyeCal.RY0; eyeCal.LX0; eyeCal.LY0] + ...
        [eyeCal.Delta(eyeCal.Delta(1).cnt).RX0;...
        eyeCal.Delta(eyeCal.Delta(1).cnt).RY0;...
        eyeCal.Delta(eyeCal.Delta(1).cnt).LX0;...
        eyeCal.Delta(eyeCal.Delta(1).cnt).LY0];
    offset = offset * ones(1, sizev(2));
    gain = [eyeCal.RXGain; eyeCal.RYGain; eyeCal.LXGain; eyeCal.LYGain] * ones(1, sizev(2));
    PCtr = [PCtr(:);PCtr(:)] * ones(1, sizev(2));
else
    offset = [eyeCal.RX0; eyeCal.RY0] + ...
        [eyeCal.Delta(eyeCal.Delta(1).cnt).RX0;...
        eyeCal.Delta(eyeCal.Delta(1).cnt).RY0];
    offset = offset * ones(1, sizev(2));
    gain = [eyeCal.RXGain; eyeCal.RYGain] * ones(1, sizev(2));
    PCtr = PCtr(:) * ones(1, sizev(2));
end

p = (v - offset) .* gain + PCtr;
end

function accepted = summarizeAcceptanceWindow(vv, estimator)
if nargin < 2 || isempty(estimator)
    estimator = 'mean';
end
switch lower(char(estimator))
    case 'mean'
        accepted = mean(vv, 2, 'omitnan');
    case 'median'
        accepted = median(vv, 2, 'omitnan');
    otherwise
        error('calibrateEyexx:InvalidSampleEstimator', ...
            'Unsupported calib.sampleEstimator: %s', char(estimator));
end
end

function spread = acceptanceWindowSpread(vv, eyeCal, PCtr)
if size(vv, 1) >= 5
    vv = vv([1, 2, 4, 5], :);
else
    vv = vv(1:min(2, size(vv, 1)), :);
end
px = eyeSamplesInScreen(vv, eyeCal, PCtr);
spread = max(std(px, 0, 2, 'omitnan'));
if isempty(spread) || isnan(spread)
    spread = Inf;
end
end
