function ex = calibrateEyex_fix(ex, calibrationFile)
arguments
    ex
    calibrationFile char = '/home/vpixx/ly1803.mat'
end

ex = resolveCalibrationValidationDisplaySizes(ex);

% calibrateEyex_fix
% Load fixed eye calibration parameters from file and keep them unchanged.
%
% Usage:
%   ex = calibrateEyex_fix(ex)
%       -> loads from ex.calib.file
%   ex = calibrateEyex_fix(ex, '/path/to/calibration.mat')
%       -> loads from explicit file path

val = ex.valid;

if isempty(calibrationFile)
    if isfield(ex, 'calib') && isfield(ex.calib, 'file') && ~isempty(ex.calib.file)
        calibrationFile = ex.calib.file;
    else
        error('calibrateEyex_fix:MissingCalibrationFile', ...
            ['No calibration file provided. Set ex.calib.file or pass ', ...
            'the file path as the second input.']);
    end
end

if ~isfile(calibrationFile)
    error('calibrateEyex_fix:FileNotFound', ...
        'Calibration file not found: %s', calibrationFile);
end

loaded = load(calibrationFile);
ex.eyeCal = parseFixedEyeCal(loaded);

% mark calibration as fixed/locked for downstream logic
ex.eyeCal.isFixed = true;
ex.eyeCal.sourceFile = calibrationFile;

% show calibration stimuli without changing loaded calibration values
ex = showCalibrationStimuli(ex);

% keep validation settings from calibrateEyex.m
ex.targ.WinW = val.targetWin(1);
ex.targ.WinH = val.targetWin(2);
ex.fix.duration = val.fixDur;
ex.reward.time = val.rewTime;
ex.stim.type = 'blank';
ex.j = 1;
ex.goodtrial = 0;

clearkeyboard = input('please press the RETURN key','s'); %#ok<NASGU>

end

function eyeCal = parseFixedEyeCal(loaded)
if isfield(loaded, 'eyeCal')
    eyeCal = loaded.eyeCal;
elseif isfield(loaded, 'ex') && isfield(loaded.ex, 'eyeCal')
    eyeCal = loaded.ex.eyeCal;
else
    error('calibrateEyex_fix:MissingEyeCal', ...
        'Calibration file must contain eyeCal or ex.eyeCal.');
end

if ~isfield(eyeCal, 'Delta') || isempty(eyeCal.Delta)
    eyeCal.Delta.cnt = 1;
    eyeCal.Delta.RX0 = 0;
    eyeCal.Delta.RY0 = 0;
    eyeCal.Delta.LX0 = 0;
    eyeCal.Delta.LY0 = 0;
elseif ~isfield(eyeCal.Delta, 'cnt') || isempty(eyeCal.Delta.cnt)
    eyeCal.Delta.cnt = 1;
end
end

function ex = showCalibrationStimuli(ex)
cal = ex.calib;

% default calibration positions:
%  1                2
%
%
%          0
%
%
%  3                4
offset = round(visualDegToPx(5, ex.setup));
distanceScaling = 1;
if isfield(cal, 'distance_scaling') && ~isempty(cal.distance_scaling)
    distanceScaling = cal.distance_scaling;
end
pos = [0,0;-1,-1;1,-1;-1,1;1,1] * offset * distanceScaling;

% optional visuals copied from calibrateEyex flow
if isfield(cal, 'Psz') && ~isempty(cal.Psz)
    ex.fix.PSz = cal.Psz;
end
if isfield(cal, 'background_color') && ~isempty(cal.background_color)
    Screen('FillRect', ex.setup.window, cal.background_color);
    Screen('Flip', ex.setup.window);
end

disp('click mouse on command window')
pause(.2)
disp('press any key to start fixed-calibration display')
pause(.2)
KbWait;
pause(.3)
resetAdcBuffer(ex);

for n = 1:size(pos,1)
    disp(['showing fixed calibration stimulus position ' num2str(n-1) ...
        ' (press key to accept/advance)'])
    plotEyePosFixed(ex, pos(n,:));
end

end

function [v,t] = plotEyePosFixed(ex,Pos)
if nargin < 2
    Pos = zeros(1,2);
end

bgColor = ones(1,3) * ex.idx.bg;
nBuffers = 10^6;
v = cell(1,nBuffers);
t = cell(1,nBuffers);

WaitSecs(0.2);
keyIsDown = false;
i = 0;
failedReadCnt = 0;
waitframes = 10;
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
            fprintf('%s\n','no new frames in Buffer; reset Datapixx');
            return
        else
            continue
        end
    end
    [vbad,t{i}] = Datapixx('ReadAdcBuffer',status.newBufferFrames,-1);
    v{i} = vbad;
    sizev = size(v{i});
    if sizev(1) < 4
        v{i}(1,:) = ex.setup.horEyeSign * v{i}(1,:);
    else
        v{i}([1,4],:) = ex.setup.horEyeSign * v{i}([1,4],:);
    end

    if sizev(1) < 4
        p = eyePosInScreenFixed(v{i}([1,2],:),ex.eyeCal,ex.fix.PCtr);
    else
        p = reshape(eyePosInScreenFixed(v{i}([1,2,4,5],:),ex.eyeCal,ex.fix.PCtr), 2, 2);
    end
    olPos = [p, mean(p,2)];

    if isempty(ex.setup.overlay)
        Screen('FillRect', ex.setup.window, bgColor);
    else
        Screen('FillRect', ex.setup.overlay, bgColor);
    end

    if sizev(1) < 4
        nDots = 1;
        olPSz = 5;
    else
        nDots = 3;
        olPSz = [ceil(ex.setup.eyePSz/2)*ones(1,2), ex.setup.eyePSz];
    end

    if isvector(ex.idx.overlay) && numel(ex.idx.overlay) == 3
        olCol = ex.idx.overlay;
    else
        olCol = repmat(ex.idx.overlay(:), 1, nDots);
    end

    if isempty(ex.setup.overlay)
        Screen('DrawDots', ex.setup.window, olPos, olPSz, olCol, [], 2);
    else
        Screen('DrawDots', ex.setup.overlay, olPos, olPSz, olCol, [], 2);
    end

    if isfield(ex.calib, 'img') && ~isempty(ex.calib.img)
        fpImg = imread(ex.calib.img);
        fpTex = Screen('MakeTexture', ex.setup.window, fpImg);
        xy = ex.fix.PCtr + Pos;
        dstRect = CenterRectOnPointd([0 0 ex.calib.Psz+200 ex.calib.Psz+200], xy(1), xy(2));
        Screen('SelectStereoDrawBuffer', ex.setup.window, 0);
        Screen('DrawTexture', ex.setup.window, fpTex, [], dstRect);
        Screen('SelectStereoDrawBuffer', ex.setup.window, 1);
        Screen('DrawTexture', ex.setup.window, fpTex, [], dstRect);
    else
        Screen('SelectStereoDrawBuffer', ex.setup.window, 0);
        Screen('Drawdots',ex.setup.window,ex.fix.PCtr'+Pos',ex.fix.PSz',ex.idx.white);
        Screen('SelectStereoDrawBuffer', ex.setup.window, 1);
        Screen('Drawdots',ex.setup.window,ex.fix.PCtr'+Pos',ex.fix.PSz',ex.idx.white);
    end

    Screen('DrawingFinished', ex.setup.window);
    vbl = Screen('Flip', ex.setup.window, vbl + (waitframes - 0.5) * ifi);
    keyIsDown = KbCheck;
end

if isempty(ex.setup.overlay)
    Screen('FillRect',ex.setup.window,bgColor);
else
    Screen('FillRect',ex.setup.overlay,bgColor);
end
Screen('Flip',ex.setup.window);

v = cell2mat(v(1:i));
t = cell2mat(t(1:i));
end

function p = eyePosInScreenFixed(v,eyeCal,PCtr)
sizev = size(v);
if sizev(1) == 4
    offset = [eyeCal.RX0; eyeCal.RY0; eyeCal.LX0; eyeCal.LY0] + ...
        [eyeCal.Delta(eyeCal.Delta(1).cnt).RX0; ...
        eyeCal.Delta(eyeCal.Delta(1).cnt).RY0; ...
        eyeCal.Delta(eyeCal.Delta(1).cnt).LX0; ...
        eyeCal.Delta(eyeCal.Delta(1).cnt).LY0] * ones(1,sizev(2));
    p = (v-offset) .* [eyeCal.RXGain; eyeCal.RYGain; eyeCal.LXGain; eyeCal.LYGain] + PCtr';
else
    offset = [eyeCal.RX0; eyeCal.RY0] + ...
        [eyeCal.Delta(eyeCal.Delta(1).cnt).RX0; eyeCal.Delta(eyeCal.Delta(1).cnt).RY0] * ones(1,sizev(2));
    p = (v-offset) .* [eyeCal.RXGain; eyeCal.RYGain] + PCtr';
end
end
