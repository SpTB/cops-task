function tests = testCoPsInstructionsx
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
folder = tempname; mkdir(folder);
testCase.TestData.folder = folder;
testCase.TestData.originalPath = path;
writeMock(folder,'Screen',[
    "function varargout = Screen(command,varargin)"
    "global COPS_INSTRUCTIONS_TEST"
    "s = COPS_INSTRUCTIONS_TEST;"
    "s.calls{end+1} = [{command} varargin];"
    "switch lower(command)"
    "case 'textsize'"
    "    varargout = {s.size}; if numel(varargin)>1, s.size = varargin{2}; end"
    "case 'textstyle'"
    "    varargout = {s.style}; if numel(varargin)>1, s.style = varargin{2}; end"
    "case 'fillrect', s.draws = {};"
    "case 'rect', varargout = {[0 0 960 540]};"
    "case 'drawtexture', s.draws = {};"
    "case 'screens', varargout = {s.screens};"
    "case 'preference', varargout = {0};"
    "case 'openwindow'"
    "    if s.popupFailure, error('InstructionsTest:Popup','Simulated unavailable display.'); end"
    "    varargout = {88};"
    "case 'close'"
    "case 'flip'"
    "    s.flips{end+1} = s.draws; varargout = {100+numel(s.flips)};"
    "otherwise, error('InstructionsTest:Screen','Unexpected Screen command.');"
    "end"
    "COPS_INSTRUCTIONS_TEST = s;"
    "end"]);
writeMock(folder,'DrawFormattedText',[
    "function [nx,ny,bounds] = DrawFormattedText(window,message,x,y,color,wrap,varargin)"
    "global COPS_INSTRUCTIONS_TEST"
    "s = COPS_INSTRUCTIONS_TEST;"
    "if ischar(y), y=100; end"
    "if isempty(wrap), wrap = 10000; end"
    "lines = regexp(message,'\n','split'); n = 0; width = 0;"
    "for k=1:numel(lines), n=n+max(1,ceil(numel(lines{k})/wrap)); width=max(width,min(wrap,numel(lines{k}))*s.size*0.5); end"
    "nx=0; ny=y+n*s.size*1.25; bounds=[0 y width ny];"
    "s.draws{end+1} = struct('text',message,'style',s.style,'size',s.size,'bounds',bounds);"
    "COPS_INSTRUCTIONS_TEST = s;"
    "end"]);
writeMock(folder,'readCoPsKeyboardx',[
    "function [keys,space,timestamp,question] = readCoPsKeyboardx(setup)"
    "global COPS_INSTRUCTIONS_TEST"
    "COPS_INSTRUCTIONS_TEST.polls = COPS_INSTRUCTIONS_TEST.polls+1;"
    "i=COPS_INSTRUCTIONS_TEST.polls; assert(i<=numel(COPS_INSTRUCTIONS_TEST.spaces),'Key sequence exhausted.');"
    "keys=false(1,256); keys(4)=ismember(i,COPS_INSTRUCTIONS_TEST.quitAt);"
    "keys(6)=ismember(i,COPS_INSTRUCTIONS_TEST.calibrationAt);"
    "space=COPS_INSTRUCTIONS_TEST.spaces(i);"
    "timestamp=200+i/100; question=ismember(i,COPS_INSTRUCTIONS_TEST.questionAt);"
    "end"]);
writeMock(folder,'KbName',["function key=KbName(name)";"if strcmp(name,'F4'), key=4; elseif strcmp(name,'F6'), key=6; else, key=[]; end";"end"]);
writeMock(folder,'kPsychGUIWindow',["function flag=kPsychGUIWindow";"flag=32;";"end"]);
writeMock(folder,'IsWin',["function value=IsWin";"global COPS_INSTRUCTIONS_TEST";"value=COPS_INSTRUCTIONS_TEST.isWindows;";"end"]);
writeMock(folder,'WaitSecs',["function WaitSecs(varargin)";"end"]);
writeMock(folder,'refreshCoPsPreviewWindowx',[
    "function changed=refreshCoPsPreviewWindowx(setup)"
    "global COPS_INSTRUCTIONS_TEST"
    "COPS_INSTRUCTIONS_TEST.refreshes=COPS_INSTRUCTIONS_TEST.refreshes+1;"
    "changed=ismember(COPS_INSTRUCTIONS_TEST.refreshes,COPS_INSTRUCTIONS_TEST.resizeAt);"
    "end"]);
writeMock(folder,'GetMouse',["function [x,y,b,focus]=GetMouse(varargin)";"x=0; y=0; b=[]; focus=true;";"end"]);
writeMock(folder,'GetSecs',["function t=GetSecs";"global COPS_INSTRUCTIONS_TEST";"t=200+COPS_INSTRUCTIONS_TEST.polls/100;";"end"]);
writeMock(folder,'msgbox',[
    "function handle=msgbox(message,varargin)"
    "global COPS_INSTRUCTIONS_TEST"
    "COPS_INSTRUCTIONS_TEST.popups{end+1}=message; handle=[];"
    "end"]);
addpath(fileparts(mfilename('fullpath')),'-begin'); addpath(folder,'-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear Screen DrawFormattedText readCoPsKeyboardx KbName WaitSecs refreshCoPsPreviewWindowx GetMouse GetSecs msgbox notifyCoPsQuestionx kPsychGUIWindow IsWin
folder=testCase.TestData.folder;
assert(strcmp(fileparts(folder),fileparts(tempname)));
rmdir(folder,'s');
clear global COPS_INSTRUCTIONS_TEST
end

function setup(~)
resetMock();
end

function testCopyUsesConfiguredBonusAndNoBoldMarkup(testCase)
[body,prompt]=formatCoPsInstructionTextx(struct('max_bonus_dollar',25));
verifySubstring(testCase,body,'up to $25 for this session.');
verifySubstring(testCase,body,'switch between them freely');
verifySubstring(testCase,body,'earn a point and hear a beep');
verifyFalse(testCase,contains(body,'landscape'));
verifyFalse(testCase,contains(body,'**'));
verifyEqual(testCase,prompt,'Press the SPACE BAR to begin.');
body=formatCoPsInstructionTextx(struct('max_bonus_dollar',12.5));
verifySubstring(testCase,body,'up to $12.50 for this session.');
verifyError(testCase,@() formatCoPsInstructionTextx(struct('max_bonus_dollar',-1)), ...
    'MATLAB:expectedNonnegative');
end

function testDisabledInstructionsDoNotTouchDisplay(testCase)
global COPS_INSTRUCTIONS_TEST
ex=fixture(); ex.exp.CoPs.instrOn=false;
verifyEqual(testCase,showCoPsInstructionsx(ex),ex);
verifyEmpty(testCase,COPS_INSTRUCTIONS_TEST.calls);
end

function testOnlySpaceSentenceIsBoldAndStylesAreRestored(testCase)
global COPS_INSTRUCTIONS_TEST
ex=showInstructions(testCase,fixture());
draws=COPS_INSTRUCTIONS_TEST.flips{1};
verifyNumElements(testCase,draws,2);
verifyEqual(testCase,[draws{1}.style draws{2}.style],[0 1]);
verifyEqual(testCase,draws{2}.text,'Press the SPACE BAR to begin.');
verifySubstring(testCase,draws{1}.text,'up to $0.41 for this session.');
verifyEqual(testCase,ex.Instructions.max_bonus_dollar,0.41);
verifyEqual(testCase,ex.Instructions.hourly_max_bonus_dollar,25);
verifyEqual(testCase,ex.Instructions.planned_paid_trials,3);
verifyEqual(testCase,COPS_INSTRUCTIONS_TEST.style,7);
verifyEqual(testCase,COPS_INSTRUCTIONS_TEST.size,42);
verifyTrue(testCase,ex.Instructions.acknowledged);
verifyEqual(testCase,[ex.Instructions.on ex.Instructions.off],[101 102]);
end

function testWelcomeScalesSessionCapAndExcludesBothPracticeTrials(testCase)
global COPS_INSTRUCTIONS_TEST
for n=[90 180 360]
    resetMock();
    ex=fixture(); ex.exp.nreps=n; % instruction flow adds two unpaid practices
    ex=showInstructions(testCase,ex);
    verifyEqual(testCase,ex.Instructions.max_bonus_dollar,25*n/180);
    verifyEqual(testCase,ex.Instructions.planned_paid_trials,n);
    if n==90
        verifySubstring(testCase,COPS_INSTRUCTIONS_TEST.flips{1}{1}.text,'$12.50 for this session');
    end
end
end

function testFormatterUsesExplicitSessionLength(testCase)
[body,~,cap]=formatCoPsInstructionTextx(struct(),'welcome',struct(),90);
verifySubstring(testCase,body,'up to $12.50 for this session.');
verifyEqual(testCase,cap.maxBonusDollars,12.5);
end

function testHeldSpaceAndResizeRequireFreshAcknowledgement(testCase)
global COPS_INSTRUCTIONS_TEST
COPS_INSTRUCTIONS_TEST.spaces=[true true false true false];
COPS_INSTRUCTIONS_TEST.resizeAt=2;
ex=showInstructions(testCase,fixture());
verifyTrue(testCase,ex.Instructions.acknowledged);
verifyEqual(testCase,COPS_INSTRUCTIONS_TEST.polls,5);
verifyEqual(testCase,numel(COPS_INSTRUCTIONS_TEST.flips),3);
end

function testOperatorCanAbortInstructions(testCase)
global COPS_INSTRUCTIONS_TEST
COPS_INSTRUCTIONS_TEST.spaces=[false false];
COPS_INSTRUCTIONS_TEST.quitAt=2;
ex=showInstructions(testCase,fixture());
verifyEqual(testCase,ex.quit,4);
verifyFalse(testCase,ex.Instructions.acknowledged);
verifyEqual(testCase,COPS_INSTRUCTIONS_TEST.style,7);
end

function testLayoutFitsCommonLogicalCanvasSizes(testCase)
global COPS_INSTRUCTIONS_TEST
for dims=[1920 1080;1280 720;1080 1080]'
    resetMock(); ex=fixture(); ex.setup.screenRect=[0 0 dims'];
    showInstructions(testCase,ex);
    draws=COPS_INSTRUCTIONS_TEST.flips{1};
    verifyGreaterThanOrEqual(testCase,draws{1}.bounds(2),0);
    verifyLessThanOrEqual(testCase,draws{2}.bounds(4),dims(2));
end
end

function testInstructionPracticeIsAdditionalAndPrecedesMainTrials(testCase)
ex=planningFixture();
info=getCoPsTrialBlockInfox(ex);
verifyEqual(testCase,info.instructionIdx,[1 2]);
verifyEqual(testCase,info.mainIdx,3:5);
verifyEqual(testCase,getCoPsTotalRepsx(ex),5);
ex=prepareCoPsTrialParamSchedules(ex);
s=ex.exp.CoPs.trialParamSchedules;
verifyEqual(testCase,[s.background_noise_lvl(1) s.target_num(1) s.target_visibility(1) s.coherence(1)],[-1 2 1 1]);
verifyEqual(testCase,[s.background_noise_lvl(2) s.target_num(2) s.target_visibility(2) s.coherence(2)],[1 2 1 1]);
ex.exp.CoPs.instrOn=false;
verifyEqual(testCase,getCoPsTotalRepsx(ex),3);
end

function testPracticeOverridesAreLocalAndFlat(testCase)
ex=planningFixture();
ctl=ex.exp.CoPs.ctl; graph=ex.exp.CoPs.graph; rew=ex.exp.CoPs.rew;
[a,b,c]=configureCoPsPracticeTrialx(ctl,graph,rew,128);
verifyEqual(testCase,[a.target_num a.gauss_scalar a.coherence],[2 1 1]);
verifyEqual(testCase,a.reward_type,'mult');
verifyFalse(testCase,a.independent_accumulation);
verifyEqual(testCase,[b.background_noise_lvl b.nullBackgroundGray b.target_visibility],[-1 128 1]);
verifyFalse(testCase,c.show_gauss_center_marker);
verifyFalse(testCase,c.show_gauss_center_marker_overlay);
verifyEqual(testCase,ex.exp.CoPs.ctl,ctl);
verifyEqual(testCase,ex.exp.CoPs.graph,graph);
verifyEqual(testCase,ex.exp.CoPs.rew,rew);
end

function testPracticePointsNeverEnterSavedSessionTotal(testCase)
ex=struct('j',1,'totalPoints',0,'Trials',struct('isInstructionTutorial',true));
ex=finalizeCoPsPointsx(ex,[2 3],2,true,true);
verifyEqual(testCase,ex.Trials(1).pointsEarned,2.5);
verifyEqual(testCase,ex.totalPoints,0);
verifyFalse(testCase,ex.Trials(1).pointsCountTowardTotal);
ex.j=2; ex.Trials(2).isInstructionTutorial=true;
ex=finalizeCoPsPointsx(ex,[3 4],2,true,true);
verifyEqual(testCase,ex.totalPoints,0);
verifyFalse(testCase,ex.Trials(2).pointsCountTowardTotal);
ex.j=3; ex.Trials(3).isInstructionTutorial=false;
ex=finalizeCoPsPointsx(ex,[3 4],2,true,true);
verifyEqual(testCase,ex.totalPoints,3.5);
verifyTrue(testCase,ex.Trials(3).pointsCountTowardTotal);
end

function testPracticeDoesNotShiftRegularPauseCadence(testCase)
ex=planningFixture(); ex.exp.nreps=11; ex.finish=13;
ex.exp.CoPs.ctl.between_trial_pause_mean=5;
ex=prepareCoPsPauseSchedulex(ex);
verifyEqual(testCase,find(ex.exp.CoPs.pauseSchedule.afterTrial),[7 12]);
end

function testSecondPracticeUsesConfiguredVisibilityAndDynamicNoise(testCase)
ex=planningFixture();
ex.exp.CoPs.graph.background_noise_lvl=[-1 0 5 1];
ex.exp.CoPs.instr.targetVisibility=0.35;
ex=prepareCoPsTrialParamSchedules(ex);
s=ex.exp.CoPs.trialParamSchedules;
verifyEqual(testCase,s.background_noise_lvl(1:2),[-1 5]);
verifyEqual(testCase,s.target_visibility(1:2),[1 0.35]);
[ctl,graph,rew]=configureCoPsPracticeTrialx(ex.exp.CoPs.ctl, ...
    ex.exp.CoPs.graph,ex.exp.CoPs.rew,128,2,ex.exp.CoPs.instr);
verifyEqual(testCase,[graph.background_noise_lvl graph.target_visibility ctl.target_num ctl.gauss_scalar],[5 0.35 2 1]);
verifyFalse(testCase,isfield(graph,'nullBackgroundGray'));
verifyFalse(testCase,rew.show_gauss_center_marker);
end

function testDynamicPracticeFallsBackWhenMainHasOnlyNullBackground(testCase)
ex=planningFixture();
ex.exp.CoPs.graph.background_noise_lvl=-1;
ex.exp.CoPs.graph.nullBackgroundGray=128;
ex=prepareCoPsTrialParamSchedules(ex);
verifyEqual(testCase,ex.exp.CoPs.trialParamSchedules.background_noise_lvl(2),1);
[~,graph]=configureCoPsPracticeTrialx(ex.exp.CoPs.ctl,ex.exp.CoPs.graph,ex.exp.CoPs.rew,128,2,ex.exp.CoPs.instr);
verifyEqual(testCase,graph.background_noise_lvl,1);
verifyFalse(testCase,isfield(graph,'nullBackgroundGray'));
end

function testReadyCopyUsesPauseSettingsAndAsksForQuestions(testCase)
ctl=struct('between_trial_pause_mean',5,'between_trial_pause_range',1);
[body,prompt]=formatCoPsInstructionTextx(struct(),'ready',ctl);
verifySubstring(testCase,body,'average of 5 trials');
verifySubstring(testCase,body,'range from 4 to 6');
verifySubstring(testCase,body,'Breaks are self-paced');
verifySubstring(testCase,body,'press Q now');
verifySubstring(testCase,body,'keep your head still throughout the task');
verifyEqual(testCase,prompt,'Press the SPACE BAR to start the main task.');
ctl.between_trial_pause_range=0;
body=formatCoPsInstructionTextx(struct(),'ready',ctl);
verifySubstring(testCase,body,'break every 5 trials');
verifyFalse(testCase,contains(body,'range from'));
ctl.between_trial_pause_mean=1;
body=formatCoPsInstructionTextx(struct(),'ready',ctl);
verifySubstring(testCase,body,'break after every trial');
verifyFalse(testCase,contains(body,'automatically'));
ctl.advance_trial_with_space=false;
body=formatCoPsInstructionTextx(struct(),'ready',ctl);
verifySubstring(testCase,body,'Trials will start automatically');
verifyFalse(testCase,contains(body,'self-paced'));
end

function testThreePagesAppearInOrderAroundBothPracticeTrials(testCase)
global COPS_INSTRUCTIONS_TEST
COPS_INSTRUCTIONS_TEST.spaces=repmat([false true false],1,3);
ex=fixture(); ex.j=1;
ex=showInstructions(testCase,ex);
ex.j=2; [ex,shown]=advanceInstructions(testCase,ex);
verifyTrue(testCase,shown);
verifyEqual(testCase,{ex.Instructions.pages.stage},{'welcome','dynamic'});
verifySubstring(testCase,ex.Instructions.pages(2).body,'changing, noisy background');
ex.j=3; [ex,shown]=advanceInstructions(testCase,ex);
verifyTrue(testCase,shown);
verifyEqual(testCase,{ex.Instructions.pages.stage},{'welcome','dynamic','ready'});
verifyTrue(testCase,all([ex.Instructions.pages.acknowledged]));
verifyEqual(testCase,[ex.Instructions.pages.on],[101 103 105]);
verifyEqual(testCase,[ex.Instructions.pages.off],[102 104 106]);
verifySubstring(testCase,ex.Instructions.body,'Welcome!');
for k=[1 3 5]
    draws=COPS_INSTRUCTIONS_TEST.flips{k};
    verifyEqual(testCase,[draws{1}.style draws{2}.style],[0 1]);
end
[same,shown]=advanceInstructions(testCase,ex);
verifyFalse(testCase,shown);
verifyEqual(testCase,same,ex);
ex.j=4;
[same,shown]=advanceInstructions(testCase,ex);
verifyFalse(testCase,shown);
verifyEqual(testCase,same,ex);
verifyEqual(testCase,COPS_INSTRUCTIONS_TEST.polls,9);
end

function testAbortOnSecondPagePreventsReadyPage(testCase)
global COPS_INSTRUCTIONS_TEST
COPS_INSTRUCTIONS_TEST.spaces=[false false];
COPS_INSTRUCTIONS_TEST.quitAt=2;
ex=showInstructions(testCase,fixture(),'dynamic');
verifyEqual(testCase,ex.quit,4);
verifyFalse(testCase,ex.Instructions.pages(end).acknowledged);
ex.j=3;
[same,shown]=advanceInstructions(testCase,ex);
verifyFalse(testCase,shown);
verifyEqual(testCase,same,ex);
end

function testReadyQuestionOpensSeparateExperimenterWindowOncePerPress(testCase)
global COPS_INSTRUCTIONS_TEST
COPS_INSTRUCTIONS_TEST.spaces=[false false false false true false];
COPS_INSTRUCTIONS_TEST.questionAt=[2 3];
ex=fixture();
ex.setup.overlayIsSeparate=true; ex.setup.overlayWindow=99; ex.setup.overlay=98;
ex.setup.screenNum=1; ex.setup.overlayScreen=0;
COPS_INSTRUCTIONS_TEST.screens=[0 1];
ex=showInstructions(testCase,ex,'ready');
verifyNumElements(testCase,ex.Instructions.pages.questionRequests,1);
verifyEqual(testCase,ex.Instructions.pages.questionRequests.target,'experimenterPopup');
verifyTrue(testCase,ex.Instructions.pages.acknowledged);
verifyEmpty(testCase,COPS_INSTRUCTIONS_TEST.popups);
opens=COPS_INSTRUCTIONS_TEST.calls(cellfun(@(c) strcmp(c{1},'OpenWindow'),COPS_INSTRUCTIONS_TEST.calls));
verifyNumElements(testCase,opens,1);
verifyEqual(testCase,opens{1}{2},0); % experimenter screen
verifyEqual(testCase,opens{1}{4},[130 80 830 460]); % centered GUI window
closed=cellfun(@(c) strcmp(c{1},'Close') && isequal(c{2},88),COPS_INSTRUCTIONS_TEST.calls);
verifyEqual(testCase,nnz(closed),1);
overlayDraws=cellfun(@(c) ismember(c{1},{'FillRect','DrawTexture'}) && isequal(c{2},99),COPS_INSTRUCTIONS_TEST.calls);
verifyFalse(testCase,any(overlayDraws));
end

function testQuestionUsesDesktopPopupInSharedPreviewAndDoesNotStartTask(testCase)
global COPS_INSTRUCTIONS_TEST
COPS_INSTRUCTIONS_TEST.spaces=[false true true false true false];
COPS_INSTRUCTIONS_TEST.questionAt=2;
ex=showInstructions(testCase,fixture(),'ready');
verifyEqual(testCase,COPS_INSTRUCTIONS_TEST.polls,6);
verifyNumElements(testCase,COPS_INSTRUCTIONS_TEST.popups,1);
verifySubstring(testCase,COPS_INSTRUCTIONS_TEST.popups{1},'Please come over to the participant');
verifyEqual(testCase,ex.Instructions.pages.questionRequests.target,'experimenterDesktop');
verifyTrue(testCase,ex.Instructions.pages.acknowledged);
end

function testAnotherQuestionClosesOldWindowBeforeOpeningNewOne(testCase)
global COPS_INSTRUCTIONS_TEST
COPS_INSTRUCTIONS_TEST.spaces=[false false false false false true false];
COPS_INSTRUCTIONS_TEST.questionAt=[2 4];
COPS_INSTRUCTIONS_TEST.screens=[0 1];
ex=fixture(); ex.setup.screenNum=1;
ex=showInstructions(testCase,ex,'ready');
verifyNumElements(testCase,ex.Instructions.pages.questionRequests,2);
opens=find(cellfun(@(c) strcmp(c{1},'OpenWindow'),COPS_INSTRUCTIONS_TEST.calls));
closes=find(cellfun(@(c) strcmp(c{1},'Close'),COPS_INSTRUCTIONS_TEST.calls));
verifyNumElements(testCase,opens,2);
verifyNumElements(testCase,closes,2);
verifyLessThan(testCase,opens(1),closes(1));
verifyLessThan(testCase,closes(1),opens(2));
verifyLessThan(testCase,opens(2),closes(2));
end

function testQuestionKeyWorksOnOtherInstructionPages(testCase)
global COPS_INSTRUCTIONS_TEST
for stage={'welcome','dynamic'}
    resetMock(); COPS_INSTRUCTIONS_TEST.questionAt=2;
    COPS_INSTRUCTIONS_TEST.spaces=[false false false true false];
    ex=showInstructions(testCase,fixture(),stage{1});
    verifyNumElements(testCase,ex.Instructions.pages.questionRequests,1);
    verifyNumElements(testCase,COPS_INSTRUCTIONS_TEST.popups,1);
end
end

function testInstructionF6QueuesCalibrationForUpcomingTrial(testCase)
global COPS_INSTRUCTIONS_TEST
COPS_INSTRUCTIONS_TEST.spaces=false(1,4);
COPS_INSTRUCTIONS_TEST.calibrationAt=[2 3];
ex=fixture(); ex.j=3; ex.setup.inputMode='eyelink';
ex=showInstructions(testCase,ex,'ready');
verifyTrue(testCase,ex.Instructions.pages.acknowledged);
verifyEqual(testCase,ex.Recalibration.pending.nextTrial,3);
verifyEqual(testCase,ex.Recalibration.pending.source,'instructions:ready');
verifyEqual(testCase,COPS_INSTRUCTIONS_TEST.polls,4); % release before tracker UI
end

function testQuestionPopupWorksWithoutOverlay(testCase)
global COPS_INSTRUCTIONS_TEST
COPS_INSTRUCTIONS_TEST.spaces=[false false false true false];
COPS_INSTRUCTIONS_TEST.questionAt=2;
COPS_INSTRUCTIONS_TEST.screens=[0 1 2];
ex=fixture(); ex.setup.screenNum=2; ex.setup.overlayScreen=1;
ex=showInstructions(testCase,ex,'dynamic');
opens=COPS_INSTRUCTIONS_TEST.calls(cellfun(@(c) strcmp(c{1},'OpenWindow'),COPS_INSTRUCTIONS_TEST.calls));
verifyNumElements(testCase,opens,1);
verifyEqual(testCase,opens{1}{2},1); % explicit experimenter screen, overlay off
verifyEqual(testCase,ex.Instructions.pages.questionRequests.target,'experimenterPopup');
end

function testWindowsVirtualDesktopIsNotMistakenForAnotherMonitor(testCase)
global COPS_INSTRUCTIONS_TEST
for screens={[0 1],[0 1 2]}
    resetMock();
    COPS_INSTRUCTIONS_TEST.isWindows=true;
    COPS_INSTRUCTIONS_TEST.spaces=[false false false true false];
    COPS_INSTRUCTIONS_TEST.questionAt=2;
    COPS_INSTRUCTIONS_TEST.screens=screens{1};
    ex=fixture(); ex.setup.screenNum=1;
    ex=showInstructions(testCase,ex,'ready');
    if numel(screens{1})==2
        verifyEqual(testCase,ex.Instructions.pages.questionRequests.target,'experimenterDesktop');
        verifyNumElements(testCase,COPS_INSTRUCTIONS_TEST.popups,1);
    else
        opens=COPS_INSTRUCTIONS_TEST.calls(cellfun(@(c) strcmp(c{1},'OpenWindow'),COPS_INSTRUCTIONS_TEST.calls));
        verifyNumElements(testCase,opens,1);
        verifyEqual(testCase,opens{1}{2},2);
    end
end
end

function testDedicatedPopupFailureRestoresPreferencesAndFallsBack(testCase)
global COPS_INSTRUCTIONS_TEST
COPS_INSTRUCTIONS_TEST.spaces=[false false false true false];
COPS_INSTRUCTIONS_TEST.questionAt=2;
COPS_INSTRUCTIONS_TEST.screens=[0 1];
COPS_INSTRUCTIONS_TEST.popupFailure=true;
ex=fixture(); ex.setup.screenNum=1;
warningState=warning('off','notifyCoPsQuestionx:Display');
cleanup=onCleanup(@() warning(warningState)); %#ok<NASGU>
ex=showInstructions(testCase,ex,'ready');
verifyTrue(testCase,ex.Instructions.pages.acknowledged);
verifyEqual(testCase,ex.Instructions.pages.questionRequests.target,'experimenterDesktop');
verifyNumElements(testCase,COPS_INSTRUCTIONS_TEST.popups,1);
for preference={'ConserveVRAM','SkipSyncTests'}
    calls=COPS_INSTRUCTIONS_TEST.calls(cellfun(@(c) ...
        strcmp(c{1},'Preference') && strcmp(c{2},preference{1}),COPS_INSTRUCTIONS_TEST.calls));
    verifyEqual(testCase,calls{end}{3},0);
end
end

function ex=showInstructions(testCase,ex,stage)
if nargin < 3, stage='welcome'; end
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
clear Screen DrawFormattedText readCoPsKeyboardx KbName WaitSecs refreshCoPsPreviewWindowx GetMouse
ex=showCoPsInstructionsx(ex,stage);
end

function [ex,shown]=advanceInstructions(testCase,ex)
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
clear Screen DrawFormattedText readCoPsKeyboardx KbName WaitSecs refreshCoPsPreviewWindowx GetMouse
[ex,shown]=advanceCoPsInstructionFlowx(ex);
end

function ex=fixture()
ex=struct('quit',0);
ex.exp.CoPs.instrOn=true; ex.exp.CoPs.pay=resolveCoPsPayx();
ex.exp.nreps=3;
ex.exp.CoPs.pre.nreps=0; ex.exp.CoPs.tut.nreps=0; ex.exp.CoPs.pur.nreps=0;
ex.setup=struct('window',7,'screenRect',[0 0 1920 1080],'guiWindow',false,'keyboards',struct('separate',false));
ex.idx=struct('bg_lum',128,'white',255,'black',0);
end

function ex=planningFixture()
evalc('ex=setDefaultsCoPs(struct());');
ex.exp.CoPs.instrOn=true;
ex.exp.CoPs.pre.nreps=0; ex.exp.CoPs.tut.nreps=0; ex.exp.CoPs.pur.nreps=0;
ex.exp.nreps=3; ex.finish=5;
end

function resetMock()
global COPS_INSTRUCTIONS_TEST
COPS_INSTRUCTIONS_TEST=struct('calls',{{}},'draws',{{}},'flips',{{}}, ...
    'size',42,'style',7,'polls',0,'spaces',[false true false],'quitAt',[], ...
    'refreshes',0,'resizeAt',[],'questionAt',[],'popups',{{}},'calibrationAt',[],'screens',[], ...
    'isWindows',false,'popupFailure',false);
end

function writeMock(folder,name,lines)
fid=fopen(fullfile(folder,[name '.m']),'w');
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',lines);
end
