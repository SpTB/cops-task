function results = runCoPsSyncHardwareCheckx(options)
% Record the production binary patch protocol at high ADC rate, without trials.
% Uses the rig's RB3D mode and last stereo drawing buffer, as in the task.
% No EyeLink connection, animal input, or reward output is used. ESC/F4 stops.
arguments
    options.durationSec (1,1) double {mustBePositive,mustBeFinite} = 5
    options.framesPerBit (1,:) double {mustBeInteger,mustBePositive} = [1 2]
    options.adcRateHz (1,1) double {mustBeMember(options.adcRateHz,[500 10000])} = 10000
    options.outputDir {mustBeText} = ''
end
root=fileparts(mfilename('fullpath'));
oldPath=path; oldFolder=pwd; oldRng=rng;
environmentCleanup=onCleanup(@() restoreEnvironment(oldPath,oldFolder,oldRng)); %#ok<NASGU>
addpath(root,fullfile(root,'vsgui_dependencies'),'-begin'); cd(root);
outputDir=char(options.outputDir);
if isempty(outputDir)
    outputDir=fullfile(root,'test_data','output','sync_hardware', ...
        char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
end
mkdir(outputDir);
results=struct('outputDir',outputDir,'status','initializing','options',options,'trials',{{}});
save(fullfile(outputDir,'results.mat'),'results');
fprintf('SYNC_HARDWARE_OUTPUT: %s\n',outputDir);
KbName('UnifyKeyNames'); AssertOpenGL;
assert(isempty(Screen('Windows')),'CoPsSyncCheck:WindowAlreadyOpen', ...
    'Close existing Psychtoolbox windows before starting the check.');
Datapixx('Open'); Datapixx('RegWrRd');
oldVideo=Datapixx('GetVideoStatus');
oldSkip=Screen('Preference','SkipSyncTests');
hardwareCleanup=onCleanup(@() finishHardware(oldVideo,oldSkip)); %#ok<NASGU>
try
    stopCoPsBenchOutputx();
    evalc('ex=setDefaultsCoPs(struct());');
    evalc('ex=getDefaultSettingsx(ex,true,initializeAdc=false);');
    ex=initDisplayxx(ex,true,skipSyncTests=false);
    results.refreshIntervalSec=Screen('GetFlipInterval',ex.setup.window);
    ex.setup.adc.Rate=options.adcRateHz;
    ex.setup.adc.Channels=6; ex.setup.adc.DiffChannels=0;
    rect=[ex.setup.screenRect(3)-ex.synch.PSz 0 ex.setup.screenRect(3) ex.synch.PSz];
    for run=1:numel(options.framesPerBit)
        sync=prepareCoPsSyncx(struct('mode','binary','framesPerBit',options.framesPerBit(run)), ...
            results.refreshIntervalSec);
        sync.patchRect=rect; sync.lowColor=ex.idx.black; sync.highColor=ex.idx.white;
        nIdle=round(.2/sync.refreshIntervalSec);
        nFrames=nIdle+ceil(options.durationSec/sync.refreshIntervalSec);
        tr=struct('sync',sync,'flip_info',nan(nFrames,4),'frameSyncBit',nan(nFrames,1), ...
            'frameSyncIndex',nan(nFrames,1),'frameSyncPhase',zeros(nFrames,1,'uint8'), ...
            'adcChannels',6,'inputSource','eye','aborted',false);
        anchor=getCoPsBenchClockAnchorx();
        tr.syncClock=struct('ptbSec',anchor(1),'datapixxSec',anchor(2),'uncertaintySec',anchor(3));
        resetAdcBuffer(ex);
        cursor=0; lastVbl=NaN;
        fprintf('Capture %d/%d: %.1f s, %g ADC samples/s, %g display frames/bit.\n', ...
            run,numel(options.framesPerBit),options.durationSec,options.adcRateHz,sync.framesPerBit);
        for k=1:nFrames
            for eye=0:1
                Screen('SelectStereoDrawBuffer',ex.setup.window,eye);
                Screen('FillRect',ex.setup.window,ex.idx.black);
            end
            Screen('FillRect',ex.setup.overlay,ex.idx.black);
            % The production trial draws its patch after the second view.
            Screen('SelectStereoDrawBuffer',ex.setup.window,1);
            [cursor,bit,index,phase]=advanceCoPsSyncx(sync,cursor,k>nIdle);
            Screen('FillRect',ex.setup.window,sync.lowColor+bit*(sync.highColor-sync.lowColor),rect);
            Screen('DrawingFinished',ex.setup.window);
            when=0; if isfinite(lastVbl), when=lastVbl+.5*sync.refreshIntervalSec; end
            Screen('AsyncFlipBegin',ex.setup.window,when);
            [tr.flip_info(k,1),tr.flip_info(k,2),tr.flip_info(k,3),tr.flip_info(k,4)]= ...
                Screen('AsyncFlipEnd',ex.setup.window);
            lastVbl=tr.flip_info(k,1);
            tr.frameSyncBit(k)=bit; tr.frameSyncIndex(k)=index; tr.frameSyncPhase(k)=phase;
            [~,~,keys]=KbCheck;
            if keys(KbName('ESCAPE')) || keys(KbName('F4'))
                tr.aborted=true; break
            end
        end
        tr.flip_info=tr.flip_info(1:k,:); tr.frameSyncBit=tr.frameSyncBit(1:k);
        tr.frameSyncIndex=tr.frameSyncIndex(1:k); tr.frameSyncPhase=tr.frameSyncPhase(1:k);
        for eye=0:1
            Screen('SelectStereoDrawBuffer',ex.setup.window,eye);
            Screen('FillRect',ex.setup.window,ex.idx.black);
        end
        Screen('FillRect',ex.setup.overlay,ex.idx.black);
        tr.syncOffTime=Screen('Flip',ex.setup.window);
        WaitSecs('UntilTime',tr.syncOffTime+.1);
        Datapixx('RegWrRd'); status=Datapixx('GetAdcStatus');
        [v,t,underflow,overflow]=Datapixx('ReadAdcBuffer',status.newBufferFrames,-1);
        Datapixx('StopAdcSchedule'); Datapixx('RegWrRd');
        tr.Eye=struct('v',v,'t',t,'n',numel(t));
        tr.adcStatus=status; tr.adcUnderflow=underflow; tr.adcOverflow=overflow;
        tr.adcRateHz=options.adcRateHz;
        results.trials{end+1}=tr;
        results.status='captured';
        save(fullfile(outputDir,'results.mat'),'results','-v7.3');
        fprintf('SAVED capture %d: %d samples; underflow=%g overflow=%g.\n',run,numel(t),underflow,overflow);
        if tr.aborted, results.status='aborted'; break; end
    end
    if ~strcmp(results.status,'aborted'), results.status='complete'; end
    save(fullfile(outputDir,'results.mat'),'results','-v7.3');
catch err
    results.status='failed'; results.error=getReport(err,'extended','hyperlinks','off');
    save(fullfile(outputDir,'results.mat'),'results','-v7.3');
    rethrow(err)
end
clear hardwareCleanup
fprintf('SYNC_HARDWARE_STATUS: %s\n',results.status);
end

function finishHardware(oldVideo,oldSkip)
stopCoPsBenchOutputx();
try
    Datapixx('StopAdcSchedule');
    if isfield(oldVideo,'stereoBlueline') && ~oldVideo.stereoBlueline
        Datapixx('DisableVideoStereoBlueline');
    end
    Datapixx('RegWrRd');
catch
end
hadWindow=false; try, hadWindow=~isempty(Screen('Windows')); catch, end
closeCoPsDisplayx();
if ~hadWindow, try, Datapixx('Close'); catch, end, end
try, Screen('Preference','SkipSyncTests',oldSkip); catch, end
end

function restoreEnvironment(oldPath,oldFolder,oldRng)
path(oldPath); cd(oldFolder); rng(oldRng);
end
