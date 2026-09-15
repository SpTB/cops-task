function ex = calibrateEyex_long(ex)
arguments
    ex
end

ex = resolveCalibrationValidationDisplaySizes(ex);
val = ex.valid;
cal = ex.calib;
if ~isfield(cal, 'signedGain') || isempty(cal.signedGain)
    cal.signedGain = true;
end

% function ex = calibrateEye_long(ex)
% based on calibrateEye, but includes more measurements and validation
% (optional)
% 
% 
% history
% 08/28/14  hn: wrote it



tic
if isfield(cal,'Psz') && ~isempty(cal.Psz)
    ex.fix.PSz = cal.Psz;
end

if isfield(cal,'background_color') && ~isempty(cal.background_color)
    bgColor = cal.background_color;
else
    bgColor = ex.idx.bg_lum;
end

Screen('FillRect', ex.setup.window,bgColor);
Screen('Flip', ex.setup.window);
disp('click mouse on command window press') 
pause(.2)
disp('press any key to start calibration')
pause(.2) 
%%
pos = [ 0,0; 0,0; 0,0; 0,0; 0,0;...
    -400,-400;400,-400;-400,400;400,400;...
    -300,0;0,-300;0,300;300,0;...
    -200,-200;200,-200;-200,200;200,200; ...
    -200,0;0,-200;0,200;200,0;
    -100,-100;100,-100;-100,100;100,100; ...
    -100,0;0,-100;0,100;100,0;...
    -50,-50;50,-50;-50,50;50,50; ...
    -50,0;0,-50;0,50;50,0];  % screen Pixels 
%%
ex.eyeCal.RXPos = []; 
ex.eyeCal.RYPos = [];
ex.eyeCal.LXPos = [];
ex.eyeCal.LYPos = []; 
fig_h=figure;
% get values in a randomized way; start with the center position
rp = randperm(size(pos,1)-1);
rp = [1,rp+1];
for n = rp
    disp(['press any key to start getting position ' num2str(n)]) 
    pause(.3) 
    KbWait ; % wait for subject to be ready 
    pause(.3)
    resetAdcBuffer(ex);
    
    Screen('SelectStereoDrawBuffer', ex.setup.window, 0);
    Screen('Drawdots',ex.setup.window,ex.fix.PCtr' + pos(n,:)',ex.fix.PSz',ex.idx.white); % draw FP
    Screen('SelectStereoDrawBuffer', ex.setup.window, 1);
    Screen('Drawdots',ex.setup.window,ex.fix.PCtr' + pos(n,:)',ex.fix.PSz',ex.idx.white); % draw FP    
    Screen('Flip', ex.setup.window);
    
    disp('press any key to accept eye position') 
    KbWait;
    Datapixx RegWrRd ;
    status = Datapixx ('GetAdcStatus') ;
    [v,t]=Datapixx('ReadAdcBuffer',[status.newBufferFrames],-1);
    Screen('FillRect', ex.setup.window,ex.idx.bg_lum);
    Screen('Flip', ex.setup.window);

    if size(v,2)>20
        vv = v(:,end-20:end);
    else vv = v;
    end
    if size(v,1)>=5
        ex.eyeCal.RXPos(n) = mean(vv(1,:));  % smoothing over 20samples (40ms)
        ex.eyeCal.RYPos(n) = mean(vv(2,:));
        ex.eyeCal.LXPos(n) = mean(vv(4,:));  % smoothing over 20samples (40ms)
        ex.eyeCal.LYPos(n) = mean(vv(5,:));
    else 
        ex.eyeCal.RXPos(n) = mean(vv(1,:));  % smoothing over 20samples (40ms)
        ex.eyeCal.RYPos(n) = mean(vv(2,:));
        ex.eyeCal.LXPos = [];  
        ex.eyeCal.LYPos = [];
    end
    close(fig_h);
    fig_h=figure;
    set(fig_h,'position',[1288         553         560         420]);
    hold off;
    plot(t,v')
    legend(['X1',],['Y1'],['P1'],['X2',],['Y2'],['P2'])
end

RX0 = sort(ex.eyeCal.RXPos(1:5)); % remove outliers
RY0 = sort(ex.eyeCal.RYPos(1:5)); % remove outliers
ex.eyeCal.RX0 = mean(RX0(2:end-1));
ex.eyeCal.RY0 = mean(RY0(2:end-1));
 [ex.eyeCal.RXGain, RXGain] = signedEyeCalGain(pos(6:end,1), ex.eyeCal.RXPos(6:end), ex.eyeCal.RX0, cal.signedGain);
[ex.eyeCal.RYGain, RYGain] = signedEyeCalGain(pos(6:end,2), ex.eyeCal.RYPos(6:end), ex.eyeCal.RY0, cal.signedGain);
    close(fig_h);
    fig_h=figure;
set(fig_h,'position',[1288         553         560         420]);

if ~isempty(ex.eyeCal.LXPos)
    LX0 = sort(ex.eyeCal.LXPos(1:5));
    LY0 = sort(ex.eyeCal.LYPos(1:5));
    ex.eyeCal.LX0 = mean(LX0(2:end-1));
    ex.eyeCal.LY0 = mean(LY0(2:end-1));
    %%
    [ex.eyeCal.LXGain, LXGain] = signedEyeCalGain(pos(6:end,1), ex.eyeCal.LXPos(6:end), ex.eyeCal.LX0, cal.signedGain);
    
    [ex.eyeCal.LYGain, LYGain] = signedEyeCalGain(pos(6:end,2), ex.eyeCal.LYPos(6:end), ex.eyeCal.LY0, cal.signedGain);
    %%
    str = {'RX0','RY0','LX0','LY0','RXGain','RYGain','LXGain','LYGain'};
    for n = 1:length(str);
        subplot(2,4,n);
        plot(1,eval(str{n}),'ko');
        title(str{n})
    end
else 
    str = {'RX0','RY0','RXGain','RYGain'};
    for n = 1:length(str);
        subplot(2,2,n);
        plot(1,eval(str{n}),'ko');
        title(str{n})
    end
end
ex.eyeCal.RXGain = median(RXGain);  
ex.eyeCal.RYGain = median(RYGain);
ex.eyeCal.LXGain = median(LXGain);  
ex.eyeCal.LYGain = median(LYGain);

ex.eyeCal.RXGains = (RXGain);  
ex.eyeCal.RYGains = (RYGain);
ex.eyeCal.LXGains = (LXGain);  
ex.eyeCal.LYGains = (LYGain);

%%
% counter for the number of centering corrections 
ex.eyeCal.Delta(1).cnt = 1;
% Delta X/Y by which the eye position from calibration should be corrected
% initial correction is 0
ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RX0 = 0;
ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RY0 = 0;
ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).LX0 = 0;
ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).LY0 = 0;
%%
% validation ?
doValidate = true;
if isfield(cal,'validate') && ~isempty(cal.validate)
    doValidate = logical(cal.validate);
end
if ~doValidate
    return
end

button = questdlg('do you want to check the quality of the calibration?' ...
    ,'validation','yes','no','cancel');
switch button
    case 'yes'
    case 'no'
        return
    case 'cancel'
        return
end

pos = [pos;pos];
%%
% store the current experimental values
reward_time = ex.reward.time;
stim = ex.stim.type;
finish = ex.finish;
targ = ex.targ;
fix_ = ex.fix;

ex.targ.WinW = val.targetWin(1);
ex.targ.WinH = val.targetWin(2);
ex.fix.WinW = 0;
ex.fix.duration = val.fixDur;
ex.reward.time = val.rewTime; 
ex.stim.type = 'blank';
ex.finish = size(pos,1);
ex.j = 1;
ex.goodtrial = 0;
%
clearkeyboard = input('please press the RETURN key','s');
[fname,dirName] = makeFilenameAndDir(ex,'ValidateEyeCal');
%
ex.loopcnt =[];
if isfield(ex,'Trials')
    ex = rmfield(ex,[{'Trials'}]);
    fnames = fieldnames(ex);
    for n = 1:length(fnames)
        if findstr(fnames{n},'tocs')
            ex = rmfield(ex,fnames{n});
        end
    end
end

rp = randperm(size(pos,1));
while ex.j <= size(pos,1) && ex.quit ~=4
    HideCursor
    if ex.quit == 0
        resetAdcBuffer(ex);
        ex.targ.Pos(1,:) = pos(rp(ex.j),:);
        ex.targ.Pos(2,:) = [1000,1000];
        ex = runTrialFixTarg(ex);
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


cur_dir = pwd;
ex.dirName = dirName;
cd(ex.dirName)
ex.fileName = fname;
disp('saving...')
save(fname, 'ex');
cd(cur_dir)
ex.quit = 0;
ShowCursor

ex.reward.time = reward_time;
ex.stim.type = stim;
ex.finish = finish;
ex.targ = targ;
ex.fix = fix_;
