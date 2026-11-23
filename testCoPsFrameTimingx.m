function tests = testCoPsFrameTimingx
% Exercise the real trial loop with a clock and VBL-synchronized display.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
folder = tempname; mkdir(folder);
testCase.TestData.folder = folder;
testCase.TestData.originalPath = path;
addpath(fileparts(mfilename('fullpath')));
writeMock(folder,'GetSecs',[
    "function t=GetSecs"
    "global COPS_FRAME_TIMING_TEST"
    "COPS_FRAME_TIMING_TEST.now=COPS_FRAME_TIMING_TEST.now+1e-5;"
    "assert(COPS_FRAME_TIMING_TEST.now<80,'FrameTimingTest:Timeout','Trial did not progress.');"
    "t=COPS_FRAME_TIMING_TEST.now;"
    "end"]);
writeMock(folder,'Screen',[
    "function varargout=Screen(command,varargin)"
    "global COPS_FRAME_TIMING_TEST"
    "s=COPS_FRAME_TIMING_TEST;"
    "switch lower(command)"
    "case 'rect', varargout={[0 0 1920 1080]};"
    "case 'getflipinterval', varargout={s.ifi};"
    "case {'fillrect','drawingfinished','drawtexture','drawdots','framerect','frameoval','drawline','drawtext','filloval'}"
    "    assert(isnan(s.pendingVbl),'FrameTimingTest:PendingDraw','Drew to a window with an unfinished flip.');"
    "    s.drawLog{end+1}=struct('command',lower(command),'args',{varargin});"
    "    if strcmpi(command,'drawdots') && numel(varargin)>=4"
    "        xy=varargin{2}; colors=varargin{4};"
    "        assert(isvector(colors) || size(colors,2)==size(xy,2),'FrameTimingTest:DotColors','Overlay position/color counts differ.');"
    "    end"
    "    if strcmpi(command,'fillrect')"
    "        s.now=s.now+s.drawCost;"
    "        if s.now>=s.overloadAt && ~s.overloaded"
    "            s.now=s.now+2.2*s.ifi; s.overloaded=true;"
    "        end"
    "    end"
    "    varargout=cell(1,nargout);"
    "case 'asyncflipbegin'"
    "    assert(isnan(s.pendingVbl),'FrameTimingTest:PendingBegin','Submitted two pending flips.');"
    "    when=0; if numel(varargin)>1, when=varargin{2}; end"
    "    t=ceil((max(s.now,when)+1e-10)/s.ifi)*s.ifi;"
    "    s.submittedDraws{end+1}=s.drawLog; s.drawLog={};"
    "    s.requests(end+1)=when; s.vbl(end+1)=t; s.pendingVbl=t; varargout={};"
    "case {'asyncflipcheckend','asyncflipend'}"
    "    if strcmpi(command,'AsyncFlipEnd'), s.endCalls=s.endCalls+1; end"
    "    t=0;"
    "    if ~isnan(s.pendingVbl) && (strcmpi(command,'AsyncFlipEnd') || s.now>=s.pendingVbl)"
    "        t=s.pendingVbl; s.now=max(s.now,t); s.pendingVbl=NaN;"
    "        s.completed(end+1)=t; s.lastVbl=t;"
    "    elseif isnan(s.pendingVbl), t=s.lastVbl; end"
    "    varargout={t,t,t,0,-1};"
    "case 'flip'"
    "    assert(isnan(s.pendingVbl),'FrameTimingTest:PendingFlip','Synchronous flip before pending flip was collected.');"
    "    when=0; if numel(varargin)>1, when=varargin{2}; end"
    "    t=ceil((max(s.now,when)+1e-10)/s.ifi)*s.ifi; s.now=t;"
    "    s.finalDraws=s.drawLog; s.drawLog={}; s.finalVbl=t;"
    "    s.lastVbl=t; varargout={t,t,t,0,-1};"
    "otherwise, varargout=cell(1,nargout);"
    "end"
    "COPS_FRAME_TIMING_TEST=s;"
    "end"]);
writeMock(folder,'KbCheck',[
    "function [down,t,keys]=KbCheck(varargin)"
    "global COPS_FRAME_TIMING_TEST"
    "COPS_FRAME_TIMING_TEST.now=COPS_FRAME_TIMING_TEST.now+COPS_FRAME_TIMING_TEST.keyboardCost;"
    "t=COPS_FRAME_TIMING_TEST.now; keys=false(1,256);"
    "if numel(COPS_FRAME_TIMING_TEST.requests)>=COPS_FRAME_TIMING_TEST.abortAfter && ~isnan(COPS_FRAME_TIMING_TEST.pendingVbl)"
    "    keys(COPS_FRAME_TIMING_TEST.abortKey)=true;"
    "end"
    "if numel(COPS_FRAME_TIMING_TEST.requests)>=10 && ~isnan(COPS_FRAME_TIMING_TEST.pendingVbl)"
    "    if COPS_FRAME_TIMING_TEST.injectError"
    "        COPS_FRAME_TIMING_TEST.errorInjected=true; error('FrameTimingTest:Injected','Injected pending-flip input error.');"
    "    elseif COPS_FRAME_TIMING_TEST.requestHeat && ~COPS_FRAME_TIMING_TEST.heatRequested"
    "        keys(8)=true; COPS_FRAME_TIMING_TEST.heatRequested=true;"
    "    end"
    "end"
    "down=any(keys);"
    "end"]);
writeMock(folder,'KbName',[
    "function key=KbName(value)"
    "names={'F1','F2','F3','F4','F6','F7','F8','F9','space'};"
    "if isnumeric(value) || islogical(value)"
    "    idx=find(value,1); key=''; if ~isempty(idx), key=names{idx}; end; return;"
    "end"
    "if strcmp(value,'UnifyKeyNames'), key=[]; return; end"
    "key=find(strcmpi(value,names),1);"
    "end"]);
writeMock(folder,'GetMouse',[
    "function [x,y,buttons]=GetMouse(varargin)"
    "x=960; y=540; buttons=[];"
    "end"]);
writeMock(folder,'WaitSecs',[
    "function WaitSecs(varargin)"
    "global COPS_FRAME_TIMING_TEST"
    "if isnumeric(varargin{1}), d=varargin{1};"
    "elseif strcmpi(varargin{1},'UntilTime')"
    "    COPS_FRAME_TIMING_TEST.waitUntil=varargin{2};"
    "    COPS_FRAME_TIMING_TEST.now=max(COPS_FRAME_TIMING_TEST.now,varargin{2}); return;"
    "else, d=varargin{2}; end"
    "COPS_FRAME_TIMING_TEST.now=COPS_FRAME_TIMING_TEST.now+d;"
    "end"]);
writeMock(folder,'resetAdcBuffer',[
    "function resetAdcBuffer(ex)"
    "global COPS_FRAME_TIMING_TEST"
    "assert(COPS_FRAME_TIMING_TEST.adcAllowed,'FrameTimingTest:UnexpectedADC','ADC must remain disabled.');"
    "COPS_FRAME_TIMING_TEST.adcStart=COPS_FRAME_TIMING_TEST.now;"
    "COPS_FRAME_TIMING_TEST.adcRate=ex.setup.adc.Rate; COPS_FRAME_TIMING_TEST.adcRead=0;"
    "end"]);
writeMock(folder,'Datapixx',[
    "function varargout=Datapixx(command,varargin)"
    "global COPS_FRAME_TIMING_TEST"
    "assert(COPS_FRAME_TIMING_TEST.adcAllowed,'FrameTimingTest:UnexpectedADC','ADC must remain disabled.');"
    "switch lower(command)"
    "case 'regwrrd', varargout={};"
    "case 'gettime', varargout={COPS_FRAME_TIMING_TEST.now+4900};"
    "otherwise, error('FrameTimingTest:UnexpectedADC','Unexpected DataPixx command.');"
    "end"
    "end"]);
writeMock(folder,'Eyelink',[
    "function t=Eyelink(command,varargin)"
    "global COPS_FRAME_TIMING_TEST"
    "assert(COPS_FRAME_TIMING_TEST.adcAllowed && strcmpi(command,'TrackerTime'),'FrameTimingTest:UnexpectedEyeLink','Unexpected EyeLink access.');"
    "t=COPS_FRAME_TIMING_TEST.now;"
    "end"]);
writeMock(folder,'checkEyex',[
    "function [pass,trEye,pos]=checkEyex(trEye,ex,varargin)"
    "global COPS_FRAME_TIMING_TEST"
    "s=COPS_FRAME_TIMING_TEST; assert(s.adcAllowed,'FrameTimingTest:UnexpectedADC','ADC must remain disabled.');"
    "n=1+floor((s.now-s.adcStart)*s.adcRate); count=n-s.adcRead;"
    "if count>0"
    "    idx=trEye.n+(1:count); trEye.v(:,idx)=zeros(numel(ex.setup.adc.Channels),count);"
    "    trEye.t(idx)=s.adcStart+(s.adcRead:n-1)/s.adcRate+4900; trEye.n=trEye.n+count;"
    "end"
    "s.adcRead=n; s.lastDrainTime=s.now; COPS_FRAME_TIMING_TEST=s; pass=true; pos=[960 540];"
    "end"]);
writeMock(folder,'getComputerName',[
    "function name=getComputerName"
    "name='frame-timing-test';"
    "end"]);
writeMock(folder,'CenterRectOnPointd',[
    "function rect=CenterRectOnPointd(rect,x,y)"
    "rect=rect+[x-mean(rect([1 3])),y-mean(rect([2 4])),x-mean(rect([1 3])),y-mean(rect([2 4]))];"
    "end"]);
writeMock(folder,'makeStimulusCoPsx',[
    "function [textures,positions,timing]=makeStimulusCoPsx(setup,ctl,varargin)"
    "textures=ones(1,ctl.nsteps+1);"
    "target=struct('pos_abs',[960 540]);"
    "positions=repmat(struct('targ1',target,'targ2',target),1,ctl.nsteps+1);"
    "timing=struct();"
    "end"]);
writeMock(folder,'gazeHeat',[
    "function gazeHeat(varargin)"
    "global COPS_FRAME_TIMING_TEST"
    "COPS_FRAME_TIMING_TEST.heatCalls=COPS_FRAME_TIMING_TEST.heatCalls+1;"
    "COPS_FRAME_TIMING_TEST.heatWhilePending=~isnan(COPS_FRAME_TIMING_TEST.pendingVbl);"
    "assert(~COPS_FRAME_TIMING_TEST.heatWhilePending,'FrameTimingTest:PendingPlot','Plotted during a pending flip.');"
    "end"]);
writeMock(folder,'drawnow',[
    "function drawnow(varargin)"
    "global COPS_FRAME_TIMING_TEST"
    "assert(isnan(COPS_FRAME_TIMING_TEST.pendingVbl),'FrameTimingTest:PendingDrawnow','Processed graphics during a pending flip.');"
    "end"]);
addpath(folder,'-begin');
clearMocks();
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clearMocks();
folder=testCase.TestData.folder;
assert(strcmp(fileparts(folder),fileparts(tempname)));
rmdir(folder,'s');
clear global COPS_FRAME_TIMING_TEST
end

function testConsecutiveGoFramesAt60And120Hz(testCase)
for rate=[60 120]
    ex=runSimulatedTrial(testCase,rate,Inf);
    trial=ex.Trials(1);
    intervals=goIntervals(trial);
    verifyGreaterThan(testCase,numel(intervals),rate);
    verifyEqual(testCase,intervals,repmat(1/rate,size(intervals)),'AbsTol',1e-9);
    verifyDeadlinesUseActualVbl(testCase,trial,1/rate);
end
end

function testBinocularOverlayBeforeFirstInputPoll(testCase)
ex=runSimulatedTrial(testCase,120,Inf,4,'earlyBinocular');
verifyEqual(testCase,ex.quit,4);
verifyEqual(testCase,numel(ex.Trials(1).frameState),1);
end

function testOverloadRemainsVisibleAndPlaybackRecovers(testCase)
rate=120;
ex=runSimulatedTrial(testCase,rate,52.3);
global COPS_FRAME_TIMING_TEST
verifyTrue(testCase,COPS_FRAME_TIMING_TEST.overloaded);
trial=ex.Trials(1); intervals=goIntervals(trial);
late=find(intervals>1.5/rate);
verifyNumElements(testCase,late,1);
if isempty(late), return; end
verifyGreaterThan(testCase,numel(intervals)-late,5);
verifyEqual(testCase,intervals(late+1:late+5),repmat(1/rate,5,1),'AbsTol',1e-9);
verifyDeadlinesUseActualVbl(testCase,trial,1/rate);
end

function testExitKeysCollectOutstandingFlipBeforeBlanking(testCase)
global COPS_FRAME_TIMING_TEST
for key=[1 2 4]
    ex=runSimulatedTrial(testCase,120,Inf,key);
    verifyEqual(testCase,ex.quit,key);
    verifyTrue(testCase,isnan(COPS_FRAME_TIMING_TEST.pendingVbl));
    verifyGreaterThanOrEqual(testCase,COPS_FRAME_TIMING_TEST.endCalls,1);
    verifyNumElements(testCase,COPS_FRAME_TIMING_TEST.completed, ...
        numel(COPS_FRAME_TIMING_TEST.requests));
end
end

function testInputPollingAndFixationRemainFasterThanDisplay(testCase)
for rate=[60 120]
    ex=runSimulatedTrial(testCase,rate,Inf);
    trial=ex.Trials(1);
    startup=trial.times.stimOn-trial.times.startTrial;
    verifyGreaterThanOrEqual(testCase,startup,500/ex.setup.adc.Rate);
    verifyLessThan(testCase,startup,3);
    samples=trial.mousePositions(:,3);
    samples=samples(samples>=trial.times.stimOn & samples<=trial.flip_info(end,1));
    verifyGreaterThan(testCase,numel(samples),2);
    sampleRate=(numel(samples)-1)/(samples(end)-samples(1));
    fprintf('Simulated %g Hz display: GO polling %.1f Hz; startup %.3f s.\n',rate,sampleRate,startup);
    verifyGreaterThan(testCase,sampleRate,400);
    verifyGreaterThan(testCase,numel(trial.scaledReward), ...
        nnz(trial.frameState==trial.frameStateLookup.GO));
end
end

function testPendingF9RequestDefersPlotting(testCase)
global COPS_FRAME_TIMING_TEST
ex=runSimulatedTrial(testCase,120,Inf,0,'heat');
verifyEqual(testCase,ex.j,3);
verifyTrue(testCase,COPS_FRAME_TIMING_TEST.heatRequested);
verifyEqual(testCase,COPS_FRAME_TIMING_TEST.heatCalls,1);
verifyFalse(testCase,COPS_FRAME_TIMING_TEST.heatWhilePending);
end

function testPendingInputErrorFinishesFlipDuringCleanup(testCase)
global COPS_FRAME_TIMING_TEST
verifyError(testCase,@() runSimulatedTrial(testCase,120,Inf,0,'error'),'FrameTimingTest:Injected');
verifyTrue(testCase,COPS_FRAME_TIMING_TEST.errorInjected);
verifyTrue(testCase,isnan(COPS_FRAME_TIMING_TEST.pendingVbl));
verifyGreaterThanOrEqual(testCase,COPS_FRAME_TIMING_TEST.endCalls,1);
verifyNumElements(testCase,COPS_FRAME_TIMING_TEST.completed,numel(COPS_FRAME_TIMING_TEST.requests));
end

function testMeasuredIntervalOverridesNominalRefreshRate(testCase)
ex=runSimulatedTrial(testCase,120,Inf,0,'nominalMismatch');
intervals=goIntervals(ex.Trials(1));
verifyEqual(testCase,ex.setup.refreshRate,60);
verifyEqual(testCase,intervals,repmat(1/120,size(intervals)),'AbsTol',1e-9);
end

function testBinaryPlaybackPreservesCadenceAndFastBehavioralPolling(testCase)
for workload={'binaryLight','binaryHeavy'}
    for rate=[60 120]
        ex=runSimulatedTrial(testCase,rate,Inf,0,workload{1},binaryConfig(1));
        trial=ex.Trials(1); intervals=goIntervals(trial);
        verifyGreaterThan(testCase,numel(intervals),rate);
        verifyEqual(testCase,intervals,repmat(1/rate,size(intervals)),'AbsTol',1e-9);
        samples=trial.mousePositions(:,3);
        samples=samples(samples>=trial.times.stimOn & samples<=trial.flip_info(end,1));
        sampleRate=(numel(samples)-1)/(samples(end)-samples(1));
        fprintf('Binary %s %g Hz display: GO polling %.1f Hz.\n',workload{1},rate,sampleRate);
        if strcmp(workload{1},'binaryLight')
            verifyGreaterThan(testCase,sampleRate,400);
        else
            % Heavy drawing consumes polling time without locking it to VBL.
            verifyGreaterThan(testCase,sampleRate,2*rate);
        end
        verifyGreaterThan(testCase,numel(trial.scaledReward), ...
            nnz(trial.frameState==trial.frameStateLookup.GO));
        verifyDeadlinesUseActualVbl(testCase,trial,1/rate);
        verifyBinaryMetadata(testCase,trial);
    end
end
end

function testBinaryPatchIsDrawnLastAndFinalBlankIsBlack(testCase)
global COPS_FRAME_TIMING_TEST
ex=runSimulatedTrial(testCase,120,Inf,0,'',binaryConfig(1));
trial=ex.Trials(1);
expectedRect=[1920-ex.synch.PSz 0 1920 ex.synch.PSz];
verifyEqual(testCase,trial.sync.patchRect,expectedRect);
draws=COPS_FRAME_TIMING_TEST.submittedDraws;
verifyNumElements(testCase,draws,size(trial.flip_info,1));
for idx=1:numel(draws)
    ops=draws{idx};
    assertGreaterThanOrEqual(testCase,numel(ops),2);
    verifyEqual(testCase,ops{end}.command,'drawingfinished');
    patch=ops{end-1};
    verifyEqual(testCase,patch.command,'fillrect');
    verifyEqual(testCase,patch.args{1},ex.setup.window);
    verifyEqual(testCase,patch.args{3},expectedRect);
    expectedColor=ex.idx.black+trial.frameSyncBit(idx)*(ex.idx.white-ex.idx.black);
    verifyEqual(testCase,patch.args{2},expectedColor);
end
finalPatch=COPS_FRAME_TIMING_TEST.finalDraws{end};
verifyEqual(testCase,finalPatch.command,'fillrect');
verifyEqual(testCase,finalPatch.args{2},ex.idx.black);
verifyEqual(testCase,finalPatch.args{3},expectedRect);
verifyEqual(testCase,trial.syncOffTime,COPS_FRAME_TIMING_TEST.finalVbl,'AbsTol',1e-12);
verifyTrue(testCase,all(trial.frameSyncBit(trial.frameSyncPhase==0)==0));
end

function testBinaryFramesPerBitAndCursorResetEachTrial(testCase)
ex=runSimulatedTrial(testCase,120,Inf,0,'twoTrials',binaryConfig(2));
for trial=ex.Trials
    verifyBinaryMetadata(testCase,trial);
    payload=find(trial.frameSyncPhase==3);
    verifyGreaterThan(testCase,numel(payload),20);
    indices=trial.frameSyncIndex(payload);
    verifyEqual(testCase,indices,floor((0:numel(payload)-1)'/2)+1);
    verifyEqual(testCase,indices(1),1);
    verifyEqual(testCase,trial.frameSyncBit(payload(1)),double(trial.sync.sequence(1)));
end
first=ex.Trials(1); second=ex.Trials(2);
a=first.frameSyncBit(first.frameSyncPhase>0);
b=second.frameSyncBit(second.frameSyncPhase>0);
n=min(numel(a),numel(b));
verifyEqual(testCase,a(1:n),b(1:n));
end

function testBinaryAbortKeepsMetadataForEveryCompletedSubmittedFrame(testCase)
global COPS_FRAME_TIMING_TEST
ex=runSimulatedTrial(testCase,120,Inf,4,'binaryGoAbort',binaryConfig(1));
trial=ex.Trials(1);
verifyEqual(testCase,ex.quit,4);
verifyGreaterThan(testCase,nnz(trial.frameSyncPhase==3),10);
verifyBinaryMetadata(testCase,trial);
verifyEqual(testCase,trial.flip_info(:,1),COPS_FRAME_TIMING_TEST.completed(:),'AbsTol',1e-12);
verifyNumElements(testCase,trial.frameSyncBit,numel(COPS_FRAME_TIMING_TEST.requests));
verifyTrue(testCase,isnan(COPS_FRAME_TIMING_TEST.pendingVbl));
verifyGreaterThan(testCase,trial.syncOffTime,trial.flip_info(end,1));
end

function testBinaryShortSequenceIsRejectedBeforeSubmittingFrames(testCase)
global COPS_FRAME_TIMING_TEST
sync=binaryConfig(1); sync.sequence=[0 1];
verifyError(testCase,@() runSimulatedTrial(testCase,120,Inf,0,'',sync), ...
    'runTrialTaskCoPsx:SyncSequenceTooShort');
verifyEmpty(testCase,COPS_FRAME_TIMING_TEST.requests);
verifyEmpty(testCase,COPS_FRAME_TIMING_TEST.completed);
end

function testBinaryEyeRecordingCapturesClockAndFinalBlackTail(testCase)
global COPS_FRAME_TIMING_TEST
sync=binaryConfig(1); sync.captureTailSecs=.1;
ex=runSimulatedTrial(testCase,120,Inf,0,'binaryEye',sync);
trial=ex.Trials(1);
verifyEqual(testCase,trial.inputSource,'eye');
verifyGreaterThan(testCase,trial.Eye.n,500);
verifyTrue(testCase,isfinite(trial.syncClock.ptbSec));
verifyTrue(testCase,isfinite(trial.syncClock.datapixxSec));
verifyGreaterThanOrEqual(testCase,trial.syncClock.uncertaintySec,0);
verifyEqual(testCase,COPS_FRAME_TIMING_TEST.waitUntil,trial.syncOffTime+.1,'AbsTol',1e-12);
verifyGreaterThanOrEqual(testCase,COPS_FRAME_TIMING_TEST.lastDrainTime,trial.syncOffTime+.1);
sampleEnd=trial.Eye.t(trial.Eye.n)-trial.syncClock.datapixxSec+trial.syncClock.ptbSec;
verifyGreaterThanOrEqual(testCase,sampleEnd,trial.syncOffTime+.1-1/ex.setup.adc.Rate- ...
    trial.syncClock.uncertaintySec);
verifyBinaryMetadata(testCase,trial);
end

function testLegacyGoPulseRemainsTopRightAndOffDisablesMarker(testCase)
global COPS_FRAME_TIMING_TEST
for mode={'goPulse','off'}
    ex=runSimulatedTrial(testCase,120,Inf,0,'',struct('mode',mode{1}));
    trial=ex.Trials(1);
    verifyEqual(testCase,string(trial.sync.mode),string(mode{1}));
    rect=[1920-ex.synch.PSz 0 1920 ex.synch.PSz];
    patchCount=0;
    for frame=COPS_FRAME_TIMING_TEST.submittedDraws
        ops=frame{1};
        for idx=1:numel(ops)
            op=ops{idx};
            if strcmp(op.command,'fillrect') && numel(op.args)>=3 && isequal(op.args{3}(:)',rect)
                patchCount=patchCount+1;
                verifyEqual(testCase,op.args{2},ex.synch.Col);
            end
        end
    end
    if strcmp(mode{1},'goPulse')
        verifyGreaterThan(testCase,patchCount,0);
        verifyEqual(testCase,nnz(trial.frameSyncPulse),patchCount);
    else
        verifyEqual(testCase,patchCount,0);
        verifyFalse(testCase,any(trial.frameSyncPulse));
    end
end
end

function verifyBinaryMetadata(testCase,trial)
n=size(trial.flip_info,1);
verifyNumElements(testCase,trial.frameSyncBit,n);
verifyNumElements(testCase,trial.frameSyncIndex,n);
verifyNumElements(testCase,trial.frameSyncPhase,n);
verifyTrue(testCase,all(isfinite(trial.flip_info(:,1))));
active=trial.frameState==trial.frameStateLookup.GO & isfinite(trial.frameStep);
verifyEqual(testCase,trial.frameSyncPhase>0,active);
verifyEqual(testCase,trial.frameSyncPulse,trial.frameSyncPhase==1);
phases=trial.frameSyncPhase(active);
verifyEqual(testCase,nnz(phases==1),trial.sync.preambleFrames);
verifyEqual(testCase,nnz(phases==2),trial.sync.gapFrames);
payload=trial.frameSyncPhase==3;
indices=trial.frameSyncIndex(payload);
expected=double(trial.sync.sequence(indices));
verifyEqual(testCase,trial.frameSyncBit(payload),expected(:));
end

function sync=binaryConfig(framesPerBit)
sync=struct('mode','binary','framesPerBit',framesPerBit, ...
    'sequence',logical(repmat([1 0 0 1 1 0 1],1,1024)));
end

function ex=runSimulatedTrial(testCase,rate,overloadAt,abortKey,scenario,syncConfig)
if nargin<4, abortKey=0; end
if nargin<5, scenario=''; end
if nargin<6, syncConfig=struct(); end
global COPS_FRAME_TIMING_TEST
COPS_FRAME_TIMING_TEST=struct('now',50,'ifi',1/rate,'drawCost',.0008, ...
    'keyboardCost',.0004,'overloadAt',overloadAt,'overloaded',false, ...
    'requests',[],'vbl',[],'completed',[],'pendingVbl',NaN,'lastVbl',0, ...
    'endCalls',0,'abortAfter',Inf,'abortKey',abortKey, ...
    'requestHeat',strcmp(scenario,'heat'),'heatRequested',false,'heatCalls',0, ...
    'heatWhilePending',false,'injectError',strcmp(scenario,'error'),'errorInjected',false, ...
    'drawLog',{{}},'submittedDraws',{{}},'finalDraws',{{}},'finalVbl',NaN, ...
    'adcAllowed',strcmp(scenario,'binaryEye'),'adcStart',NaN,'adcRead',0, ...
    'adcRate',500,'waitUntil',NaN,'lastDrainTime',NaN);
if abortKey>0, COPS_FRAME_TIMING_TEST.abortAfter=10; end
if strcmp(scenario,'binaryLight'), COPS_FRAME_TIMING_TEST.drawCost=.0001; end
ex=fixture(rate);
for name=fieldnames(syncConfig)'
    ex.exp.CoPs.sync.(name{1})=syncConfig.(name{1});
end
if strcmp(scenario,'earlyBinocular')
    ex.setup.inputMode='eye'; ex.setup.stereo.Display=true;
    ex.eyeCal.LXPos=zeros(1,4);
    COPS_FRAME_TIMING_TEST.abortAfter=1;
elseif strcmp(scenario,'heat')
    ex.j=2; ex.Trials(1).ID=0; ex.loopcnt=zeros(1,2);
    ex.exp.nreps=2; ex.finish=2; ex.exp.total_nreps=2;
    ex.stim.seq=repmat(ex.stim.seq,1,2);
elseif strcmp(scenario,'nominalMismatch'), ex.setup.refreshRate=rate/2;
elseif strcmp(scenario,'binaryGoAbort'), COPS_FRAME_TIMING_TEST.abortAfter=250;
elseif strcmp(scenario,'binaryEye'), ex.setup.inputMode='eye';
elseif strcmp(scenario,'twoTrials')
    ex.exp.nreps=2; ex.finish=2; ex.exp.total_nreps=2;
    ex.stim.seq=repmat(ex.stim.seq,1,2);
end
trialIdx=ex.j;
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
eyeOn=strcmp(scenario,'binaryEye');
evalc('ex=runTrialTaskCoPsx(ex,false,eyeOn,false);');
if strcmp(scenario,'twoTrials')
    evalc('ex=runTrialTaskCoPsx(ex,false,false,false);');
    verifyEqual(testCase,ex.j,trialIdx+2);
else
    verifyEqual(testCase,ex.j,trialIdx+1);
end
verifyEqual(testCase,ex.quit,abortKey);
verifyEqual(testCase,ex.Trials(trialIdx).displayRefreshIntervalSec,1/rate,'AbsTol',1e-12);
if abortKey==0, verifyTrue(testCase,isfinite(ex.Trials(trialIdx).times.stimOn)); end
end

function intervals=goIntervals(trial)
active=trial.frameState==trial.frameStateLookup.GO;
intervals=diff(trial.flip_info(:,1));
intervals=intervals(active(1:end-1) & active(2:end));
end

function verifyDeadlinesUseActualVbl(testCase,trial,ifi)
global COPS_FRAME_TIMING_TEST
n=size(trial.flip_info,1);
requests=COPS_FRAME_TIMING_TEST.requests(1:n);
verifyEqual(testCase,requests(2:end)',trial.flip_info(1:end-1,1)+.5*ifi,'AbsTol',1e-9);
end

function ex=fixture(rate)
ex.setup=struct('testMode',true,'viewingDistance',58,'monitorWidth',47);
evalc('ex=setDefaultsCoPs(ex);');
evalc('ex=getDefaultSettingsx(ex,true,initializeAdc=false);');
ex.setup.window=101; ex.setup.screenRect=[0 0 1920 1080];
ex.setup.refreshRate=rate; ex.setup.adc.Rate=500;
ex.setup.stereo.Display=false; ex.setup.overlay=[]; ex.setup.inputMode='mouse';
ex.fix.PCtr=[960 540]; ex.eyeCal=struct('LXPos',[],'Delta',[]);
ex.j=1; ex.goodtrial=0; ex.Trials=struct([]); ex.loopcnt=0;
ex.exp.nreps=1; ex.finish=1; ex.exp.total_nreps=1; ex.states.PREGO=5.95;
ex.exp.CoPs.pre.nreps=0; ex.exp.CoPs.tut.nreps=0; ex.exp.CoPs.pur.nreps=0;
ex.exp.CoPs.freeViewing=true; ex.exp.CoPs.ctl.jointBlocks=false;
ex.exp.CoPs.ctl.nsteps=90; ex.exp.CoPs.ctl.target_num=1;
ex.exp.CoPs.graph.background_noise_lvl=1; ex.exp.CoPs.graph.target_visibility=1;
ex.exp.CoPs.graph.texture_dims=[32 32]; ex.exp.CoPs.graph.size_mult=1;
ex.exp.CoPs.graph.radiusUnits='texturePx'; ex.exp.CoPs.graph.radius=3;
ex.exp.CoPs.graph.autoTextureDims=false;
ex.exp.CoPs.rew.gauss_center_free=false; ex.exp.CoPs.rew.gauss_center_mode='manual';
ex.exp.CoPs.rew.gauss_center_idx=1;
ex.stim.seq={'simulated-stimulus'};
end

function clearMocks()
clear GetSecs Screen KbCheck KbName GetMouse WaitSecs getComputerName ...
    CenterRectOnPointd makeStimulusCoPsx gazeHeat drawnow ...
    resetAdcBuffer Datapixx Eyelink checkEyex
end

function writeMock(folder,name,lines)
fid=fopen(fullfile(folder,[name '.m']),'w');
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',lines);
end
