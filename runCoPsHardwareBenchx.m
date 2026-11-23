function results = runCoPsHardwareBenchx(options)
% Subject-free test of the actual CoPs trial, projector, ADC and reward TTL.
%
%   results = runCoPsHardwareBenchx(rewardOutput=true)
%   results = runCoPsHardwareBenchx(probeOnly=true)
%   results = runCoPsHardwareBenchx(pairs=5, durationSec=18, rewardOutput=true)
%
% rewardOutput=true drives the real valve output: disconnect the valve or
% route it to a collection cup. ESC/F4 abort. All output goes below this
% repository's ignored test_data/output/hardware_bench directory.
arguments
    options.pairs (1,1) double {mustBeInteger,mustBePositive} = 1
    options.durationSec (1,1) double {mustBePositive} = 18
    options.rewardOutput (1,1) logical = false
    options.probeOnly (1,1) logical = false
    options.photodiodeChannel (1,1) double {mustBeInteger,mustBeNonnegative} = 6
    options.adcRateHz (1,1) double {mustBeMember(options.adcRateHz,[500 10000])} = 500
    options.conditions (1,:) string {mustBeMember(options.conditions,["fixed","movie"])} = ["fixed","movie"]
    options.outputDir {mustBeText} = ''
end

root = fileparts(mfilename('fullpath'));
originalPath = path; originalFolder = pwd; originalRng = rng;
addpath(root,fullfile(root,'vsgui_dependencies'),'-begin');
cd(root);
outputDir = char(options.outputDir);
if isempty(outputDir)
    outputDir = fullfile(root,'test_data','output','hardware_bench', ...
        char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
end
if ~isfolder(outputDir), mkdir(outputDir); end
fprintf('CoPs hardware bench: %s\n',outputDir);
fprintf('Real reward output: %d. ESC/F4 aborts.\n',options.rewardOutput);
results = struct('outputDir',outputDir,'options',options, ...
    'status','initializing','trials',{{}},'summary',table());
display = [];
environmentCleanup = onCleanup(@() restoreEnvironment(originalPath,originalFolder,originalRng)); %#ok<NASGU>
try
    KbName('UnifyKeyNames');
    AssertOpenGL;
    assert(isempty(Screen('Windows')), 'CoPsBench:DisplayAlreadyOpen', ...
        'Close existing Psychtoolbox windows before starting the bench.');
    Datapixx('Open');
    Datapixx('RegWrRd');
    oldVideo = Datapixx('GetVideoStatus');
    oldDin = Datapixx('GetDinStatus');
    oldSkipSync = Screen('Preference','SkipSyncTests',0);
    hardwareCleanup = onCleanup(@() finishHardware(oldVideo,oldDin,oldSkipSync)); %#ok<NASGU>
    Datapixx('StopAllSchedules');
    stopCoPsBenchOutputx();
    Datapixx('DisableDacAdcLoopback');
    Datapixx('EnableDoutDinLoopback');
    Datapixx('DisableDinDebounce');
    Datapixx('RegWrRd');
    ex = setDefaultsCoPs(struct());
    ex = getDefaultSettingsx(ex,true,initializeAdc=false);
    ex.states.PREGO = 5.95;
    results.experimentDefaults = ex;
    % Use the production initializer with synchronization tests enforced.
    screens = Screen('Screens');
    assert(ismember(1,screens),'CoPsBench:MissingRigDisplay', ...
        'Rig display screen 1 is missing. Available: %s.',mat2str(screens));
    results.displayMapping='PTB automatic on X screen 1';
    ex=initDisplayxx(ex,true,skipSyncTests=false);
    display=ex.setup.window;
    results.displayIntervalSec=Screen('GetFlipInterval',display);
    results.video=Datapixx('GetVideoStatus');
    fprintf('Measured display interval %.4f ms (%.3f Hz).\n', ...
        1000*results.displayIntervalSec,1/results.displayIntervalSec);
    results.clockStart=clockAnchor();
    probeEx=ex; probeEx.setup.adc.Rate=10000;
    results.probe=photodiodeProbe(probeEx,options.photodiodeChannel,results.clockStart);
    save(fullfile(outputDir,'probe.mat'),'results','-v7.3');
    assert(results.probe.valid,'CoPsBench:PhotodiodeNotDetected', ...
        ['No clear patch response on ADC %d (black %.4g V, white %.4g V). ' ...
        'Probe data saved. Check the diode placement/channel before reward trials.'], ...
        options.photodiodeChannel,results.probe.blackMeanV,results.probe.whiteMeanV);
    if options.probeOnly
        results.status='probe_complete';
        save(fullfile(outputDir,'results.mat'),'results','-v7.3');
        return
    end

    sourceDir=fullfile(outputDir,'sources');
    names=makeCoPsBenchRunnerx(sourceDir);
    addpath(sourceDir,'-begin');
    ex.eyeCal=benchCalibration();
    ex.setup.inputMode='eye'; % Real ADC reads, replaced gaze after decoding.
    ex.setup.adc.Rate=options.adcRateHz;
    ex.setup.dirRoot=outputDir;
    ex.exp.CoPs.ctl.jointBlocks=false;
    ex.exp.CoPs.pre.nreps=0; ex.exp.CoPs.tut.nreps=0; ex.exp.CoPs.pur.nreps=0;
    ex.exp.CoPs.rew.gauss_center_free=false;
    ex.exp.CoPs.rew.gauss_center_idx=1;
    ex.exp.CoPs.rew.gauss_center_coords=[];
    ex.exp.CoPs.ctl.nsteps=round(options.durationSec*ex.exp.CoPs.timing.waitHz);
    ex.setup.hardwareBench=struct('enabled',true,'rewardOutput',options.rewardOutput, ...
        'targetHz',ex.exp.CoPs.timing.waitHz,'pollRateHz',500,'adcRateHz',options.adcRateHz, ...
        'maxTrialSeconds',options.durationSec+35, ...
        'photodiodeChannel',options.photodiodeChannel, ...
        'photodiodeThresholdV',results.probe.thresholdV,'photodiodePolarity',results.probe.polarity);
    base=ex;
    conditions=cellstr(options.conditions);
    total=2*numel(conditions)*options.pairs;
    count=0;
    for pair=1:options.pairs
        for conditionIdx=1:numel(conditions)
            order=[1 2];
            if mod(pair+conditionIdx,2)==1, order=[2 1]; end
            seed=20261123+100*pair+1+strcmp(conditions{conditionIdx},'movie');
            for versionIdx=order
                count=count+1;
                ex=base;
                ex.j=1; ex.goodtrial=0; ex.quit=0; ex.Trials=struct([]); ex.loopcnt=0;
                ex.exp.nreps=1; ex.finish=1; ex.exp.total_nreps=1;
                ex.setup.hardwareBench.scenario=conditions{conditionIdx};
                ex.setup.hardwareBench.version={'legacy','vbl'};
                ex.setup.hardwareBench.version=ex.setup.hardwareBench.version{versionIdx};
                ex.setup.hardwareBench.pair=pair;
                ex.setup.hardwareBench.seed=seed;
                if strcmp(conditions{conditionIdx},'fixed')
                    ex.exp.CoPs.graph.background_noise_lvl=1;
                    ex.exp.CoPs.graph.target_visibility=1;
                    ex.exp.CoPs.ctl.target_num=1;
                    ex.exp.CoPs.ctl.step_size_mult=0;
                    ex.exp.CoPs.pos.initx1=0; ex.exp.CoPs.pos.inity1=0;
                    ex.setup.hardwareBench.markerMode='step';
                else
                    ex.setup.hardwareBench.markerMode='frame';
                end
                rng(seed,'twister');
                ex=prepareCoPsTrialParamSchedules(ex);
                active=isfinite(ex.exp.CoPs.trialParamSchedules.target_visibility);
                ex.stim.seq=buildCoPsStimulusSequencex(ex,false,active);
                validateCoPsStimulusSelection(ex);
                fprintf('\nBench trial %d/%d: pair %d, %s, %s; seed %d\n', ...
                    count,total,pair,conditions{conditionIdx},ex.setup.hardwareBench.version,seed);
                Datapixx('SetDinLog',48e6,10000); % Does not overlap ADC RAM.
                Datapixx('StartDinLog');
                Datapixx('RegWrRd');
                anchorBefore=clockAnchor();
                runner=str2func(names{versionIdx});
                ex=runner(ex,false,true,true);
                stopCoPsBenchOutputx();
                WaitSecs(0.06); % Retain the last optical transition and TTL fall.
                Datapixx('RegWrRd');
                adcStatus=Datapixx('GetAdcStatus');
                n=adcStatus.newBufferFrames;
                tailV=[]; tailT=[]; tailUnderflow=0; tailOverflow=0;
                if n>0
                    [tailV,tailT,tailUnderflow,tailOverflow]=Datapixx('ReadAdcBuffer',n,-1);
                end
                Datapixx('StopAdcSchedule'); Datapixx('StopDinLog'); Datapixx('RegWrRd');
                dinStatus=Datapixx('GetDinStatus');
                [dinData,dinTime,dinUnderflow]=Datapixx('ReadDinLog');
                anchorAfter=clockAnchor();
                trial=ex.Trials(1);
                if ~isempty(tailT)
                    idx=trial.Eye.n+(1:numel(tailT));
                    trial.Eye.v(:,idx)=tailV; trial.Eye.t(idx)=tailT;
                    trial.Eye.n=trial.Eye.n+numel(tailT);
                end
                trial.bench.dinData=dinData; trial.bench.dinTime=dinTime;
                trial.bench.adcStatus=adcStatus; trial.bench.dinStatus=dinStatus;
                trial.bench.tailUnderflow=tailUnderflow; trial.bench.tailOverflow=tailOverflow;
                trial.bench.dinUnderflow=dinUnderflow;
                trial.bench.clockBefore=anchorBefore; trial.bench.clockAfter=anchorAfter;
                trial.bench.aborted=ex.quit~=0;
                trial.bench.summary=analyzeCoPsHardwareBenchx(trial);
                results.trials{end+1}=trial;
                if mod(count,2)==0
                    previous=results.trials{end-1};
                    assert(isequaln(previous.targetPositions,trial.targetPositions), ...
                        'CoPsBench:UnmatchedTrajectories', ...
                        'Paired target trajectories differ; do not interpret this pair as controlled.');
                end
                rows=cellfun(@(t)t.bench.summary,results.trials,'UniformOutput',false);
                results.summary=struct2table([rows{:}]);
                disp(struct2table(trial.bench.summary));
                save(fullfile(outputDir,sprintf('trial_%02d.mat',count)),'trial','-v7.3');
                writetable(results.summary,fullfile(outputDir,'summary.csv'));
                results.status='running';
                save(fullfile(outputDir,'results.mat'),'results','-v7.3');
                if ex.quit~=0, results.status='aborted'; break; end
                Screen('FillRect',display,0); Screen('Flip',display); WaitSecs(0.25);
            end
            if strcmp(results.status,'aborted'), break; end
        end
        if strcmp(results.status,'aborted'), break; end
    end
    if ~strcmp(results.status,'aborted'), results.status='complete'; end
    results.clockEnd=clockAnchor();
    save(fullfile(outputDir,'results.mat'),'results','-v7.3');
    writeReport(results);
    clear hardwareCleanup % Release the projector before offscreen report plots.
    try
        results.plots=plotCoPsHardwareBenchx(results);
    catch plotError
        results.plotError=plotError.message;
        warning('CoPsBench:PlotExport','Data saved, but plot export failed: %s',plotError.message);
    end
    save(fullfile(outputDir,'results.mat'),'results','-v7.3');
    fprintf('\nHardware bench %s: %s\n',results.status,outputDir);
catch err
    stopCoPsBenchOutputx();
    results.status='failed'; results.error=getReport(err,'extended','hyperlinks','off');
    save(fullfile(outputDir,'results.mat'),'results','-v7.3');
    rethrow(err)
end
end

function finishHardware(oldVideo,oldDin,oldSkipSync)
% Values are captured by the cleanup handle; no exiting nested workspace.
stopCoPsBenchOutputx();
try
    Datapixx('StopAdcSchedule'); Datapixx('StopDinLog');
    if isfield(oldVideo,'stereoBlueline') && ~oldVideo.stereoBlueline
        Datapixx('DisableVideoStereoBlueline');
    end
    if oldDin.doutDinLoopback, Datapixx('EnableDoutDinLoopback');
    else, Datapixx('DisableDoutDinLoopback'); end
    Datapixx('RegWrRd');
catch
end
% PsychImaging owns the connection once a window exists and closes it via
% its shutdown hook. Do not call the low-level SDK again after that close.
hadWindow=false;
try, hadWindow=~isempty(Screen('Windows')); catch, end
closeCoPsDisplayx();
if ~hadWindow
    try, Datapixx('Close'); catch, end
end
try, Screen('Preference','SkipSyncTests',oldSkipSync); catch, end
end

function restoreEnvironment(originalPath,originalFolder,originalRng)
path(originalPath); cd(originalFolder); rng(originalRng);
end

function cal=benchCalibration()
cal=makeCoPsMouseEyeCalx();
cal.LX0=0; cal.LY0=0; cal.LXPos=zeros(1,4); cal.LYPos=zeros(1,4);
cal.LXGain=1; cal.LYGain=1;
end

function anchor=clockAnchor()
anchor=getCoPsBenchClockAnchorx();
end

function probe=photodiodeProbe(ex,channel,anchor)
fprintf('Photodiode probe: alternating corner patch on ADC %d; reward output low.\n',channel);
resetAdcBuffer(ex);
rect=ex.setup.screenRect;
sz=ex.synch.PSz;
patch=[rect(3)-sz 0 rect(3) sz];
vbl=zeros(8,1); levels=mod((0:7)',2);
for k=1:8
    Screen('FillRect',ex.setup.window,0);
    Screen('FillRect',ex.setup.window,255*levels(k),patch);
    vbl(k)=Screen('Flip',ex.setup.window);
    WaitSecs(0.25);
end
Screen('FillRect',ex.setup.window,0); Screen('Flip',ex.setup.window); WaitSecs(0.05);
Datapixx('RegWrRd'); status=Datapixx('GetAdcStatus');
[v,t,underflow,overflow]=Datapixx('ReadAdcBuffer',status.newBufferFrames,-1);
Datapixx('StopAdcSchedule'); Datapixx('RegWrRd');
row=find(ex.setup.adc.Channels==channel,1);
assert(~isempty(row),'CoPsBench:UnscheduledPhotodiode','ADC %d is not scheduled.',channel);
pt=t+anchor(1)-anchor(2);
black=[]; white=[];
for k=1:8
    selected=pt>=vbl(k)+0.06 & pt<=vbl(k)+0.20;
    if levels(k), white=[white v(row,selected)]; %#ok<AGROW>
    else, black=[black v(row,selected)]; end %#ok<AGROW>
end
lo=mean(black); hi=mean(white);
probe=struct('channel',channel,'sampleRateHz',ex.setup.adc.Rate, ...
    'v',v,'t',t,'vbl',vbl,'levels',levels, ...
    'blackMeanV',lo,'whiteMeanV',hi,'thresholdV',(lo+hi)/2, ...
    'polarity',sign(hi-lo),'underflow',underflow,'overflow',overflow, ...
    'valid',isfinite(lo)&&isfinite(hi)&&abs(hi-lo)>0.03&&~underflow&&~overflow);
fprintf('Photodiode black %.4f V, white %.4f V, difference %.4f V.\n',lo,hi,hi-lo);
end

function writeReport(results)
fid=fopen(fullfile(results.outputDir,'report.txt'),'w');
done=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'CoPs subject-free hardware bench\nStatus: %s\nReal reward output: %d\n', ...
    results.status,results.options.rewardOutput);
fprintf(fid,'Display: %.4f Hz; ADC: %g Hz; input polling target: 500 Hz.\n', ...
    1/results.displayIntervalSec,results.options.adcRateHz);
fprintf(fid,'Artificial gaze follows a fixed time-based target trace after real ADC acquisition.\n');
fprintf(fid,'Fixed condition uses one immobile central target; movie uses the experiment stimuli.\n');
fprintf(fid,'Legacy source: parent of c825eb7; VBL source: current working copy.\n');
fprintf(fid,'See summary.csv for trial metrics and trial_*.mat for raw ADC, poll, flip, and DIN data.\n');
fprintf(fid,'Optical timestamps at 500 Hz have approximately 2 ms sampling resolution.\n');
fprintf(fid,'Use the separate adcRateHz=10000 control for optical frame verification;\n');
fprintf(fid,'500 Hz can undersample short DLP illumination bursts.\n');
fprintf(fid,'TTL loopback measures controller output pulses, not liquid volume or valve mechanics.\n');
fprintf(fid,'The first 150 ms form an optical-onset preamble; steady marker measurements exclude it.\n');
fprintf(fid,'Instrumentation is identical in both timing variants and adds some processing cost.\n');
fprintf(fid,'\nMeasurements (one row per trial; see summary.csv for all columns):\n');
fprintf(fid,'scenario version poll_Hz start_to_GO_s skipped_refreshes GO_pulses median_pulse_ms ADC_gaps\n');
for k=1:height(results.summary)
    row=results.summary(k,:);
    fprintf(fid,'%s %s %.2f %.4f %d %d %.3f %d\n', ...
        string(row.scenario),string(row.version),row.pollHz,row.startToGoSec, ...
        row.skippedRefreshes,row.rewardPulsesGO,row.medianRewardWidthMs,row.adcGaps);
end
fprintf(fid,'Completed pairs passed the identical-target-trajectory check.\n');
end
