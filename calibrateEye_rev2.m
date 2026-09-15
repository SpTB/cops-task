function ex = calibrateEye_rev2(ex)

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

initialOffset = 0;
%initialGain = 340;  % Lemieus
initialGain = 10;  % for Barnum
eyeflds = {'RX','RY','LX','LY'};

if ~isfield(ex,'eyeCal')
    ex.eyeCal = [];
end

if isfield(ex.eyeCal,'Delta')
    ex.eyeCal.Delta = ex.eyeCal.Delta(1);
end

ex.eyeCal.Delta.cnt = 1;
ex.eyeCal.RX0 = -.79;
ex.eyeCal.RY0 = -9.59;
ex.eyeCal.LX0 = -.79;
ex.eyeCal.LY0 = -9.59;
ex.eyeCal.RXGain = 150.43;
ex.eyeCal.RYGain = 150.63;
ex.eyeCal.LXGain = 150.43;
ex.eyeCal.LYGain = 150.63;
for i=1:length(eyeflds)
    %ex.eyeCal.([eyeflds{i},'0']) = initialOffset;
    ex.eyeCal.([eyeflds{i},'Pos']) = NaN(1,4);
    %ex.eyeCal.([eyeflds{i},'Gain']) = initialGain;
    ex.eyeCal.Delta.([eyeflds{i},'0']) = 0;
end

ex.eyeCal = orderfields(ex.eyeCal,{'RX0','RY0','LX0','LY0','RXPos',...
    'RYPos','LXPos','LYPos','RXGain','RYGain','LXGain','LYGain','Delta'});
%keyboard;

% number of samples per condition
sampleDur = 0.1;    % in second
nSamples = round(sampleDur*ex.setup.adc.Rate);

ex.fix.PSz = 12;

Screen('FillRect', ex.setup.window,ex.idx.bg_lum);

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

[v,t,ex.eyeCal] = plotEyePos(ex);
idx = max([1,length(t)-nSamples]);
vv = v(:,idx:end);

fig_h=figure;
plot(t,v')
legend({'RX','RY','RP','LX','LY','LP'})
set(fig_h,'position',[1288         553         560         420]);


% getting 0 position
if size(v,1)>=5
    ex.eyeCal.RX0 = mean(vv(1,:));  % smoothing over 20samples (40ms)
    ex.eyeCal.RY0 = mean(vv(2,:));
    ex.eyeCal.LX0 = mean(vv(4,:));  % smoothing over 20samples (40ms)
    ex.eyeCal.LY0 = mean(vv(5,:));
else
    ex.eyeCal.RX0 = mean(vv(1,:));  % smoothing over 20samples (40ms)
    ex.eyeCal.RY0 = mean(vv(2,:));
    ex.eyeCal.LX0 = [];
    ex.eyeCal.LY0 = [];
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
pos = [0,0;-1,-1;1,-1;-1,1;1,1] * offset;

rp = [0,randperm(4)];
for n = rp
    disp(['press any key to start getting position ' num2str(n)])
    pause(.3)
    KbWait ; % wait for subject to be ready
    pause(.3)
    
    [v,t] = plotEyePos(ex,pos(n+1,:),0);
    
    idx = max([1,length(t)-nSamples]);
    vv = v(:,idx:end);
    
    % if n == 0
    %     if size(v,1)>=5
    %         ex.eyeCal.RX0 = mean(vv(1,:));  % smoothing over 20samples (40ms)
    %         ex.eyeCal.RY0 = mean(vv(2,:));
    %         ex.eyeCal.LX0 = mean(vv(4,:));  % smoothing over 20samples (40ms)
    %         ex.eyeCal.LY0 = mean(vv(5,:));
    %     else
    %         ex.eyeCal.RX0 = mean(vv(1,:));  % smoothing over 20samples (40ms)
    %         ex.eyeCal.RY0 = mean(vv(2,:));
    %         ex.eyeCal.LX0 = [];
    %         ex.eyeCal.LY0 = [];
    %     end
    % 
    % else
    %     if size(v,1)>=5
    %         ex.eyeCal.RXPos(n) = mean(vv(1,:));  % smoothing over 20samples (40ms)
    %         ex.eyeCal.RYPos(n) = mean(vv(2,:));
    %         ex.eyeCal.LXPos(n) = mean(vv(4,:));  % smoothing over 20samples (40ms)
    %         ex.eyeCal.LYPos(n) = mean(vv(5,:));
    %     else
    %         ex.eyeCal.RXPos(n) = mean(vv(1,:));  % smoothing over 20samples (40ms)
    %         ex.eyeCal.RYPos(n) = mean(vv(2,:));
    %         ex.eyeCal.LXPos = [];
    %         ex.eyeCal.LYPos = [];
    %     end
    % 
    %     ex.eyeCal.RXGain = offset/mean(abs(ex.eyeCal.RXPos-ex.eyeCal.RX0),'omitnan');
    %     ex.eyeCal.RYGain = offset/mean(abs(ex.eyeCal.RYPos-ex.eyeCal.RY0),'omitnan');
    %     ex.eyeCal.LXGain = offset/mean(abs(ex.eyeCal.LXPos-ex.eyeCal.LX0),'omitnan');
    %     ex.eyeCal.LYGain = offset/mean(abs(ex.eyeCal.LYPos-ex.eyeCal.LY0),'omitnan');
    % 
    % end
    
    close(fig_h);
    fig_h=figure;
    plot(t,v')
    legend({'RX','RY','RP','LX','LY','LP'})
    set(fig_h,'position',[1288         553         560         420]);
    drawnow;
end

% iknew
% unit - pixel/adc
storedPos = pos(2:min(size(pos, 1), numel(ex.eyeCal.RXPos) + 1), :);
nStored = size(storedPos, 1);
signedGain = true;
if isfield(ex, 'calib') && isfield(ex.calib, 'signedGain') && ~isempty(ex.calib.signedGain)
    signedGain = logical(ex.calib.signedGain);
end
[ex.eyeCal.RXGain, ex.eyeCal.RXGains] = signedEyeCalGain(storedPos(:,1), ex.eyeCal.RXPos(1:nStored), ex.eyeCal.RX0, signedGain);
[ex.eyeCal.RYGain, ex.eyeCal.RYGains] = signedEyeCalGain(storedPos(:,2), ex.eyeCal.RYPos(1:nStored), ex.eyeCal.RY0, signedGain);
if ~isempty(ex.eyeCal.LXPos)
    [ex.eyeCal.LXGain, ex.eyeCal.LXGains] = signedEyeCalGain(storedPos(:,1), ex.eyeCal.LXPos(1:nStored), ex.eyeCal.LX0, signedGain);
    [ex.eyeCal.LYGain, ex.eyeCal.LYGains] = signedEyeCalGain(storedPos(:,2), ex.eyeCal.LYPos(1:nStored), ex.eyeCal.LY0, signedGain);
end

close(fig_h);
fig_h=figure;
plot(t,v')
legend({'RX','RY','RP','LX','LY','LP'})
set(fig_h,'position',[1288         553         560         420]);

disp('done eye calibration')




% iknew: 7.1.2022
% second phase - more repetitions and store eye positions to ex.Trials
% borrowed from the validation loop in calibrateEye_long.m

% store the current experimental values
reward_time = ex.reward.time;
stim = ex.stim.type;
finish = ex.finish;
targ = ex.targ;
fix_ = ex.fix;

ex.targ.WinW = 80;
ex.targ.WinH = 80;
ex.fix.WinW = 0;
ex.fix.duration = 0.3;
ex.stim.type = 'blank';
ex.finish = size(pos,1);
ex.j = 1;
ex.goodtrial = 0;

% set reward size differently for dome
if strcmpi(ex.setup.computerName,'lab-ms-98h9')
    ex.reward.time = 0.02;
else
    ex.reward.time = 0.2;
end

%
clearkeyboard = input('please press the RETURN key','s');


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%% store unique experiment ID
clocktime = fix(clock);
sendStrobes([ex.strobe.FILE_ID,clocktime,ex.strobe.EXPERIMENT_START]);

ex.Header.fileID = clocktime;

[fname,dirName] = makeFilenameAndDir(ex,'EyeCal');
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
offsets_inDeg = -10:5:10;
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

nRepeat = 3;
nRepeated = 0;
ex.targ.Pos(2,:) = [1000,1000];

% initialize data table
varNames = {'TX','TY','RX','RY','LX','LY','reward'};
nTrials = nRepeat * size(pos,1);

dat = array2table(NaN(nTrials,length(varNames)),'VariableNames',varNames);


curr_idx = 1;
while nRepeated <= nRepeat && ex.quit ~= 4
    rp = randperm(size(pos,1));
    for i=1:length(rp)
        HideCursor
        if ex.quit == 0
            resetAdcBuffer(ex);
            ex.targ.Pos(1,:) = pos(rp(i),:);
            ex = runTrialFixTarg(ex);
            
            [dat,eyeCal] = updateTable(ex.Trials(end),ex.eyeCal,dat,curr_idx);
            %eyeCal
            curr_idx = curr_idx + 1;
            
        elseif ex.quit == 1
            disp('in pause')
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


cur_dir = pwd;
ex.dirName = dirName;
cd(ex.dirName)
ex.fileName = fname;
disp('saving...')
save(fname, 'ex');
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

ex.reward.time = reward_time;
ex.stim.type = stim;
ex.finish = finish;
ex.targ = targ;
ex.fix = fix_;

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
    dat{i,{'RX','RY','LX','LY'}} = ...
        mean(Trial.Eye.v([1,2,4,5],idx),2)';
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



% submodules added by ik
% iknew - 9.23.2022

function [v,t,eyeCal] = plotEyePos(ex,Pos,resetOffset)


if nargin == 1
    Pos = zeros(1,2);
    resetOffset = true;
elseif nargin == 2
    resetOffset = false;
end

if sum(abs(Pos)==0)
    resetOffset = true;
end

olColBinoc = ex.idx.overlay * ones(3,3); % right, left, binoc, mouse
olPSz = [ceil(ex.setup.eyePSz/2)*ones(1,2), ex.setup.eyePSz]; % eye (R,L,B)


fpPos = ex.fix.PCtr+ex.targ.Pos(1,:);
fpCol = ex.idx.bg * ones(1,3);
bgColor = ones(1,3) * ex.idx.bg;

nBuffers = 10^6;
v = cell(1,nBuffers);
t = cell(1,nBuffers);

WaitSecs(0.2);
keyIsDown = false;
i = 0;
waitframes = 10;
failedReadCnt = 0;
ifi = Screen('GetFlipInterval',ex.setup.window);
vbl = Screen('Flip',ex.setup.window);
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
    [v{i},t{i}] = Datapixx('ReadAdcBuffer',status.newBufferFrames,-1);
    
    % added by IK: 06.04.2024
    v{i}([1,4],:) = ex.setup.horEyeSign * v{i}([1,4],:);
    
    if resetOffset && i > 3
        vv = cell2mat(v(i-3:i));
        if size(vv,1)>=5
            ex.eyeCal.RX0 = mean(vv(1,:));  % smoothing over 20samples (40ms)
            ex.eyeCal.RY0 = mean(vv(2,:));
            ex.eyeCal.LX0 = mean(vv(4,:));  % smoothing over 20samples (40ms)
            ex.eyeCal.LY0 = mean(vv(5,:));
        else
            ex.eyeCal.RX0 = mean(vv(1,:));  % smoothing over 20samples (40ms)
            ex.eyeCal.RY0 = mean(vv(2,:));
            ex.eyeCal.LX0 = [];
            ex.eyeCal.LY0 = [];
        end
    end
    
    
    p = reshape(eyePosInScreen(v{i}([1,2,4,5],:),ex.eyeCal,ex.fix.PCtr),...
        2,2);
    olPos = [p, mean(p,2)];
    
    % background
    Screen('FillRect',ex.setup.overlay,bgColor);
    
    % draw eye dots, mouse position
    Screen('Drawdots',ex.setup.overlay,olPos,olPSz,olColBinoc);
    
    
    % draw fixation point
    Screen('SelectStereoDrawBuffer', ex.setup.window, 0);
    Screen('Drawdots',ex.setup.window,ex.fix.PCtr'+Pos',ex.fix.PSz',...
        ex.idx.white); % draw FP
    
    Screen('SelectStereoDrawBuffer', ex.setup.window, 1);
    Screen('Drawdots',ex.setup.window,ex.fix.PCtr'+Pos',ex.fix.PSz',...
        ex.idx.white); % draw FP
    
    Screen('DrawingFinished', ex.setup.window);
    vbl = Screen('Flip', ex.setup.window,vbl + (waitframes - 0.5) * ifi);
    
    keyIsDown = KbCheck;
end

Screen('FillRect',ex.setup.overlay,bgColor);
Screen('Flip',ex.setup.window);

v = cell2mat(v(1:i));
t = cell2mat(t(1:i));
eyeCal = ex.eyeCal;

end


function p = eyePosInScreen(v,eyeCal,PCtr)
% v is a row vector - [RX, RY, LX, LY]'

offset = [eyeCal.RX0; eyeCal.RY0; eyeCal.LX0; eyeCal.LY0] + ...
    [eyeCal.Delta(eyeCal.Delta(1).cnt).RX0;...
    eyeCal.Delta(eyeCal.Delta(1).cnt).RY0;...
    eyeCal.Delta(eyeCal.Delta(1).cnt).LX0;...
    eyeCal.Delta(eyeCal.Delta(1).cnt).LY0];

gain = [eyeCal.RXGain; eyeCal.RYGain; eyeCal.LXGain; eyeCal.LYGain];

PCtr = [PCtr(:);PCtr(:)];

p = (mean(v,2) - offset) .* gain + PCtr;

end
