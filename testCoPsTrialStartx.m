function tests = testCoPsTrialStartx
% Run the real trial loop with a simulated clock, display and eye tracker.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
folder=tempname; mkdir(folder);
testCase.TestData.folder=folder;
testCase.TestData.originalPath=path;
repo=fileparts(mfilename('fullpath'));
addpath(repo,fullfile(repo,'CoPs_eyelink'));
writeMock(folder,'GetSecs',[
    "function t=GetSecs"
    "global COPS_TRIAL_START_TEST"
    "COPS_TRIAL_START_TEST.now=COPS_TRIAL_START_TEST.now+COPS_TRIAL_START_TEST.clockStep;"
    "assert(COPS_TRIAL_START_TEST.now<80,'TrialStartTest:Timeout','Trial did not progress.');"
    "t=COPS_TRIAL_START_TEST.now;"
    "end"]);
writeMock(folder,'Screen',[
    "function varargout=Screen(command,varargin)"
    "global COPS_TRIAL_START_TEST"
    "switch lower(command)"
    "case 'rect', varargout={[0 0 1920 1080]};"
    "case 'maketexture'"
    "    COPS_TRIAL_START_TEST.textures=COPS_TRIAL_START_TEST.textures+1;"
    "    varargout={COPS_TRIAL_START_TEST.textures};"
    "case 'preloadtextures', varargout={true,true};"
    "case 'flip'"
    "    t=GetSecs;"
    "    if COPS_TRIAL_START_TEST.scheduledFlips"
    "        when=0; if numel(varargin)>1, when=varargin{2}; end"
    "        t=ceil((max(t,when)+1e-10)/COPS_TRIAL_START_TEST.ifi)*COPS_TRIAL_START_TEST.ifi;"
    "        COPS_TRIAL_START_TEST.now=t;"
    "    end"
    "    varargout={t,t,t,0};"
    "case 'getflipinterval', varargout={1/60};"
    "case 'textsize', varargout={24};"
    "case 'drawdots'"
    "    xy=varargin{2}; colors=varargin{4};"
    "    assert((size(xy,1)==2 || numel(xy)==2) && (isscalar(colors) || numel(colors)==3 || numel(colors)==4 || size(colors,2)==size(xy,2)), ..."
    "        'TrialStartTest:DotColors','Dot colors must match the number of positions.');"
    "    assert(all(isfinite(xy(:))),'TrialStartTest:MissingDots','Missing gaze must not be drawn.');"
    "    COPS_TRIAL_START_TEST.dots{end+1}=varargin; varargout={};"
    "case 'fillrect'"
    "    COPS_TRIAL_START_TEST.fills{end+1}=varargin; varargout={};"
    "    COPS_TRIAL_START_TEST.now=COPS_TRIAL_START_TEST.now+COPS_TRIAL_START_TEST.drawCost;"
    "otherwise, varargout=cell(1,nargout);"
    "end"
    "end"]);
writeMock(folder,'KbName',[
    "function key=KbName(name)"
    "if strcmp(name,'UnifyKeyNames'), key=[]; return; end"
    "names={'F1','F2','F3','F4','F6','F7','F8','F9','space','q'};"
    "key=find(strcmp(name,names),1);"
    "end"]);
writeMock(folder,'KbCheck',[
    "function [down,t,keys]=KbCheck(varargin)"
    "global COPS_TRIAL_START_TEST"
    "COPS_TRIAL_START_TEST.now=COPS_TRIAL_START_TEST.now+COPS_TRIAL_START_TEST.keyboardCost;"
    "t=COPS_TRIAL_START_TEST.now; keys=false(1,256);"
    "keys(4)=t>=COPS_TRIAL_START_TEST.abortAt; down=any(keys);"
    "end"]);
writeMock(folder,'GetMouse',[
    "function varargout=GetMouse(varargin)"
    "global COPS_TRIAL_START_TEST"
    "assert(COPS_TRIAL_START_TEST.adcAllowed,'TrialStartTest:Mouse','Eye/no-input trial must not read mouse gaze.');"
    "varargout={960,540,[],true};"
    "end"]);
writeMock(folder,'resetAdcBuffer',[
    "function resetAdcBuffer(ex)"
    "global COPS_TRIAL_START_TEST"
    "assert(COPS_TRIAL_START_TEST.adcAllowed,'Unexpected ADC access');"
    "COPS_TRIAL_START_TEST.adcStart=COPS_TRIAL_START_TEST.now;"
    "COPS_TRIAL_START_TEST.adcRate=ex.setup.adc.Rate; COPS_TRIAL_START_TEST.adcRead=0;"
    "end"]);
writeMock(folder,'Datapixx',[
    "function varargout=Datapixx(command,varargin)"
    "global COPS_TRIAL_START_TEST"
    "assert(COPS_TRIAL_START_TEST.adcAllowed,'Unexpected ADC access');"
    "switch command"
    "case 'RegWrRd', varargout={};"
    "case 'GetTime', varargout={COPS_TRIAL_START_TEST.now+4900};"
    "otherwise, error('TrialStartTest:Datapixx','Unexpected command');"
    "end"
    "end"]);
writeMock(folder,'readCoPsAnalogx',[
    "function a=readCoPsAnalogx(a)"
    "global COPS_TRIAL_START_TEST"
    "s=COPS_TRIAL_START_TEST; n=1+floor((s.now-s.adcStart)*s.adcRate);"
    "count=n-s.adcRead; idx=a.n+(1:count);"
    "a.t(idx)=s.adcStart+(s.adcRead:n-1)/s.adcRate+4900; a.v(:,idx)=zeros(1,count);"
    "a.n=a.n+count; COPS_TRIAL_START_TEST.adcRead=n;"
    "end"]);
writeMock(folder,'checkEyex',[
    "function [pass,trEye,pos]=checkEyex(trEye,varargin)"
    "a=struct('v',trEye.v,'t',trEye.t,'n',trEye.n); a=readCoPsAnalogx(a);"
    "trEye.v=a.v; trEye.t=a.t; trEye.n=a.n; pass=false; pos=[NaN NaN];"
    "end"]);
writeMock(folder,'WaitSecs',[
    "function WaitSecs(command,when)"
    "global COPS_TRIAL_START_TEST"
    "assert(strcmp(command,'UntilTime'));"
    "COPS_TRIAL_START_TEST.waitUntil=when;"
    "COPS_TRIAL_START_TEST.now=max(COPS_TRIAL_START_TEST.now,when);"
    "end"]);
writeMock(folder,'showCoPsTrialFeedbackx',[
    "function ex=showCoPsTrialFeedbackx(ex,varargin)"
    "% The trial has finished; pause-screen keyboard handling is tested separately."
    "end"]);
writeMock(folder,'Eyelink',[
    "function varargout=Eyelink(command,varargin)"
    "global COPS_TRIAL_START_TEST"
    "switch lower(command)"
    "case 'trackertime', varargout={COPS_TRIAL_START_TEST.now};"
    "case 'getqueueddata'"
    "    s=zeros(31,1); s(1)=1000*COPS_TRIAL_START_TEST.now; s(2)=200;"
    "    s([15 17 13 14 16 12])=COPS_TRIAL_START_TEST.gaze;"
    "    varargout={s,[],true};"
    "otherwise, error('TrialStartTest:Tracker','Unexpected tracker call');"
    "end"
    "end"]);
addpath(folder,'-begin');
clear readCoPsKeyboardx GetSecs Screen KbCheck KbName GetMouse Eyelink showCoPsTrialFeedbackx Datapixx WaitSecs resetAdcBuffer readCoPsAnalogx checkEyex
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear readCoPsKeyboardx GetSecs Screen KbCheck KbName GetMouse Eyelink showCoPsTrialFeedbackx Datapixx WaitSecs resetAdcBuffer readCoPsAnalogx checkEyex
folder=testCase.TestData.folder;
assert(strcmp(fileparts(folder),fileparts(tempname)));
rmdir(folder,'s');
clear global COPS_TRIAL_START_TEST
end

function setup(~)
global COPS_TRIAL_START_TEST
COPS_TRIAL_START_TEST=struct('now',50,'textures',1000,'fills',{{}},'dots',{{}}, ...
    'gaze',[NaN NaN NaN NaN NaN NaN],'abortAt',Inf, ...
    'clockStep',.005,'scheduledFlips',false,'ifi',1/120,'drawCost',0,'keyboardCost',0, ...
    'adcAllowed',false,'adcStart',NaN,'adcRate',2000,'waitUntil',NaN);
end

function testFreeViewingStartsAndCompletesWithoutAnyInput(testCase)
ex=fixture(); ex.setup.inputMode='none';
ex=runTrial(testCase,ex,false);
verifyStartedWithoutPoints(testCase,ex);
verifyEqual(testCase,ex.Trials(1).inputSource,'none');
verifyEmpty(testCase,ex.Trials(1).mousePositions);
end

function testBothPhotodiodeProtocolsDrawAtBottomRight(testCase)
global COPS_TRIAL_START_TEST
for mode={'goPulse','binary'}
    COPS_TRIAL_START_TEST.fills={};
    ex=fixture(); ex.setup.inputMode='none';
    ex.exp.CoPs.sync.mode=mode{1};
    ex=runTrial(testCase,ex,false);
    expected=[1860 1020 1920 1080];
    verifyEqual(testCase,ex.Trials(1).sync.patchRect,expected);
    draws=COPS_TRIAL_START_TEST.fills;
    drawn=cellfun(@(c) numel(c)>=3 && isequal(c{1},101) && ...
        isequal(c{2},ex.synch.Col) && isequal(c{3}(:)',expected),draws);
    verifyTrue(testCase,any(drawn));
    if strcmp(mode{1},'binary')
        verifyEqual(testCase,ex.Trials(1).sync.lowColor,ex.idx.black);
        verifyEqual(testCase,ex.Trials(1).sync.highColor,ex.idx.white);
        patchDraws=draws(cellfun(@(c) numel(c)>=3 && isequal(c{1},101) && ...
            isequal(c{3}(:)',expected),draws));
        verifyEqual(testCase,patchDraws{end}{2},ex.idx.black);
    end
end
end

function testBinaryPlaybackKeepsEveryRefreshDespitePollingOverhead(testCase)
global COPS_TRIAL_START_TEST
ex=fixture(); ex.setup.inputMode='none'; ex.setup.refreshRate=120;
ex.exp.CoPs.sync=prepareCoPsSyncx(struct('mode','binary'),1/120);
ex.exp.CoPs.ctl.nsteps=30;
COPS_TRIAL_START_TEST.clockStep=.00001;
COPS_TRIAL_START_TEST.scheduledFlips=true;
COPS_TRIAL_START_TEST.drawCost=.0008;
COPS_TRIAL_START_TEST.keyboardCost=.0004;
ex=runTrial(testCase,ex,false);
tr=ex.Trials(1); intervals=diff(tr.flip_info(:,1));
active=tr.frameSyncPhase(1:end-1)>0 & tr.frameSyncPhase(2:end)>0;
verifyTrue(testCase,tr.trialCompleted);
verifyGreaterThan(testCase,nnz(active),100);
verifyEqual(testCase,intervals(active),repmat(1/120,nnz(active),1),'AbsTol',1e-9);
end

function testBinaryAdcCaptureIncludesFinalPhysicalResponse(testCase)
global COPS_TRIAL_START_TEST
for mode={'mouse','eye'}
ex=fixture(); ex.setup.inputMode=mode{1}; ex.setup.refreshRate=120;
ex.exp.CoPs.ctl.nsteps=30;
ex.setup.dependencies.adcOn=true; ex.setup.adc.Channels=0; ex.setup.adc.Rate=2000;
ex.exp.CoPs.sync=prepareCoPsSyncx(struct('mode','binary','physicalChannel',0),1/120);
COPS_TRIAL_START_TEST.adcAllowed=true;
COPS_TRIAL_START_TEST.clockStep=.00001;
COPS_TRIAL_START_TEST.scheduledFlips=true;
COPS_TRIAL_START_TEST.drawCost=.0008;
COPS_TRIAL_START_TEST.keyboardCost=.0004;
ex=runTrial(testCase,ex,false);
tr=ex.Trials(1);
verifyTrue(testCase,tr.trialCompleted);
verifyEqual(testCase,COPS_TRIAL_START_TEST.waitUntil,tr.syncOffTime+.1,'AbsTol',1e-9);
verifyGreaterThanOrEqual(testCase,tr.syncTiming.capturedTailSecs,.1-1/2000-1e-5);
verifyTrue(testCase,tr.syncTiming.tailComplete);
verifyEqual(testCase,tr.syncTiming.missedRefreshes,0);
verifyTrue(testCase,tr.syncTiming.passed);
end
end

function testOverloadedDrawingIsStillReportedAsMissedRefreshes(testCase)
global COPS_TRIAL_START_TEST
ex=fixture(); ex.setup.inputMode='none'; ex.setup.refreshRate=120;
ex.exp.CoPs.sync=prepareCoPsSyncx(struct('mode','binary'),1/120);
COPS_TRIAL_START_TEST.clockStep=.00001;
COPS_TRIAL_START_TEST.scheduledFlips=true;
COPS_TRIAL_START_TEST.drawCost=.003;
ex=runTrial(testCase,ex,false);
verifyGreaterThan(testCase,ex.Trials(1).syncTiming.missedRefreshes,0);
verifyFalse(testCase,ex.Trials(1).syncTiming.frameTimingPassed);
end

function testFreeViewingStartsAndCompletesWithMissingNativeGaze(testCase)
ex=fixture(); ex.setup.inputMode='eyelink';
ex=runTrial(testCase,ex,true);
verifyStartedWithoutPoints(testCase,ex);
verifyEqual(testCase,ex.Trials(1).inputSource,'eyelink');
verifyEmpty(testCase,ex.Trials(1).mousePositions);
end

function testFreeViewingStartsWithEyesAwayFromTargets(testCase)
global COPS_TRIAL_START_TEST
COPS_TRIAL_START_TEST.gaze=[2500 1800 30 2500 1800 30];
ex=fixture(); ex.setup.inputMode='eyelink';
ex=runTrial(testCase,ex,true);
verifyStartedWithoutPoints(testCase,ex);
end

function testNativeGazeOverlayCompletesFirstTrial(testCase)
global COPS_TRIAL_START_TEST
for gaze={[960 540 30 NaN NaN NaN],[960 540 30 970 550 30],NaN(1,6)}
    COPS_TRIAL_START_TEST.now=50;
    COPS_TRIAL_START_TEST.dots={};
    COPS_TRIAL_START_TEST.gaze=gaze{1};
    ex=fixture(); ex.setup.inputMode='eyelink';
    ex.setup.showExperimenterOverlay=true;
    ex.setup.overlay=201; ex.setup.overlayIsSeparate=true;
    ex.setup.overlayWindow=202; ex.setup.overlayDisplayRateHz=30;
    ex=runTrial(testCase,ex,true);
    verifyTrue(testCase,ex.Trials(1).trialCompleted);
    draws=COPS_TRIAL_START_TEST.dots;
    overlayDraws=draws(cellfun(@(c) isequal(c{1},201),draws));
    if all(isnan(gaze{1}))
        verifyEmpty(testCase,overlayDraws);
    else
        verifyNotEmpty(testCase,overlayDraws);
        expected=2+double(isfinite(gaze{1}(4)));
        verifyTrue(testCase,all(cellfun(@(c) size(c{2},2)==expected,overlayDraws)));
    end
end
end

function testMonocularOverlayKeepsEyeAndPointerColors(testCase)
global COPS_TRIAL_START_TEST
palette=[255 0 0; 0 255 0; 0 0 255; 255 255 255];
drawCoPsInputOverlayx(201,[960 540; 100 200],16,palette);
draw=COPS_TRIAL_START_TEST.dots{end};
verifyEqual(testCase,draw{2},[960 100; 540 200]);
verifyEqual(testCase,draw{4},palette([1 end],:)');
drawCoPsInputOverlayx(201,[960 540; NaN NaN],16,palette);
verifyEqual(testCase,COPS_TRIAL_START_TEST.dots{end}{4},palette(1,:)');
end

function testInstructionPracticeStartsWithoutGaze(testCase)
ex=fixture(); ex.setup.inputMode='none';
ex.exp.CoPs.instrOn=true;
ex.exp.CoPs.ctl.nsteps=4;
ex.finish=getCoPsTotalRepsx(ex);
ex.exp.total_nreps=ex.finish;
ex=prepareCoPsTrialParamSchedules(ex);
ex.stim.seq=buildCoPsStimulusSequencex(ex,false);
ex=runTrial(testCase,ex,false);
verifyStartedWithoutPoints(testCase,ex);
verifyTrue(testCase,ex.Trials(1).isInstructionTutorial);
end

function testExplicitFixationModeStillRequiresGaze(testCase)
global COPS_TRIAL_START_TEST
COPS_TRIAL_START_TEST.abortAt=53;
ex=fixture(); ex.setup.inputMode='none';
ex.exp.CoPs.freeViewing=false;
ex=runTrial(testCase,ex,false);
verifyTrue(testCase,isnan(ex.Trials(1).times.stimOn));
verifyFalse(testCase,ex.Trials(1).trialCompleted);
verifyEqual(testCase,ex.totalPoints,0);
end

function ex=fixture()
evalc('ex=setDefaultsCoPs(struct());');
evalc('ex=getDefaultSettingsx(ex,true,initializeAdc=false);');
ex.setup.window=101; ex.setup.screenRect=[0 0 1920 1080];
ex.setup.refreshRate=60; ex.setup.inputSampleRate=500;
ex.setup.stereo.Display=false; ex.setup.overlay=[];
ex.setup.showExperimenterOverlay=false; ex.setup.guiWindow=false;
ex.setup.keyboards=struct('separate',false);
ex.setup.dependencies=struct('adcOn',false);
ex.setup.rewardSound=struct('enabled',false);
ex.setup.el.SAMPLE_TYPE=200; ex.setup.el.MISSING_DATA=-32768;
ex.fix.PCtr=[960 540];
ex.eyeCal=makeCoPsMouseEyeCalx();
ex.j=1; ex.goodtrial=0; ex.totalPoints=0;
ex.Trials=struct([]); ex.loopcnt=zeros(1,2);
ex.exp.nreps=2; ex.finish=2;
ex.exp.total_nreps=2; ex.states.PREGO=5.95;
ex.exp.CoPs.instrOn=false; ex.exp.CoPs.freeViewing=true;
ex.exp.CoPs.pre.nreps=0; ex.exp.CoPs.tut.nreps=0; ex.exp.CoPs.pur.nreps=0;
ex.exp.CoPs.ctl.jointBlocks=false; ex.exp.CoPs.ctl.advance_trial_with_space=false;
ex.exp.CoPs.ctl.nsteps=4;
ex.exp.CoPs.graph.background_noise_lvl=1;
ex.exp.CoPs.graph.target_visibility=1;
ex.exp.CoPs.sync.mode='off';
ex=prepareCoPsPauseSchedulex(ex);
ex=prepareCoPsTrialParamSchedules(ex);
ex.stim.seq=buildCoPsStimulusSequencex(ex,false);
end

function ex=runTrial(testCase,ex,eyeOn)
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
evalc('ex=runTrialTaskCoPsx(ex,false,eyeOn,false);');
end

function verifyStartedWithoutPoints(testCase,ex)
trial=ex.Trials(1);
verifyTrue(testCase,trial.trialCompleted);
verifyTrue(testCase,isfinite(trial.times.stimOn));
verifyGreaterThanOrEqual(testCase,trial.times.stimOn-trial.times.startTrial, ...
    max(ex.fix.duration,500/ex.setup.inputSampleRate));
verifyLessThan(testCase,trial.times.stimOn-trial.times.startTrial,3);
verifyEqual(testCase,ex.j,2);
verifyEqual(testCase,ex.totalPoints,0);
verifyEqual(testCase,trial.pointsEarned,0);
verifyEqual(testCase,trial.rawPointsEvidence,0);
end

function writeMock(folder,name,lines)
fid=fopen(fullfile(folder,[name '.m']),'w');
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',lines);
end
