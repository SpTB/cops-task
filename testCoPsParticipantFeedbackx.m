function tests = testCoPsParticipantFeedbackx
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
folder = tempname; mkdir(folder);
testCase.TestData.folder = folder;
testCase.TestData.originalPath = path;
writeMock(folder,'Screen',[
    "function varargout=Screen(command,varargin)"
    "global COPS_COMMENT_TEST"
    "switch lower(command)"
    "case 'textsize'"
    "    varargout={COPS_COMMENT_TEST.textSize};"
    "    if numel(varargin)>1, COPS_COMMENT_TEST.textSize=varargin{2}; end"
    "case 'rect', varargout={[0 0 960 540]};"
    "case 'textbounds', varargout={[0 0 16 20]};"
    "case {'fillrect','framerect'}, varargout={};"
    "case 'flip'"
    "    COPS_COMMENT_TEST.flips=COPS_COMMENT_TEST.flips+1;"
    "    assert(COPS_COMMENT_TEST.flips~=COPS_COMMENT_TEST.failFlip,'CommentTest:Display','Display failed.');"
    "    if ~isempty(COPS_COMMENT_TEST.checkpoint)"
    "        saved=load(COPS_COMMENT_TEST.checkpoint,'ex');"
    "        assert(isfield(saved.ex,'Payout'),'Payout must be saved before text entry.');"
    "    end"
    "    varargout={100+COPS_COMMENT_TEST.flips};"
    "otherwise, error('CommentTest:Screen','Unexpected Screen command');"
    "end"
    "end"]);
writeMock(folder,'DrawFormattedText',[
    "function DrawFormattedText(window,text,varargin)"
    "global COPS_COMMENT_TEST"
    "COPS_COMMENT_TEST.drawn{end+1}=text;"
    "end"]);
writeMock(folder,'KbQueueCreate',[
    "function KbQueueCreate(device)"
    "global COPS_COMMENT_TEST"
    "COPS_COMMENT_TEST.device=device; COPS_COMMENT_TEST.created=true;"
    "end"]);
writeMock(folder,'KbQueueStart',[
    "function KbQueueStart(varargin)"
    "global COPS_COMMENT_TEST"
    "assert(~COPS_COMMENT_TEST.failStart,'CommentTest:Keyboard','Keyboard failed.');"
    "end"]);
writeMock(folder,'KbQueueRelease',[
    "function KbQueueRelease(varargin)"
    "global COPS_COMMENT_TEST"
    "COPS_COMMENT_TEST.released=true;"
    "end"]);
writeMock(folder,'ListenChar',[
    "function ListenChar(flag)"
    "global COPS_COMMENT_TEST"
    "COPS_COMMENT_TEST.listen(end+1)=flag;"
    "end"]);
writeMock(folder,'KbEventGet',[
    "function event=KbEventGet(device)"
    "global COPS_COMMENT_TEST"
    "COPS_COMMENT_TEST.reads=COPS_COMMENT_TEST.reads+1;"
    "i=COPS_COMMENT_TEST.reads;"
    "assert(i<=numel(COPS_COMMENT_TEST.keys)+5,'CommentTest:Timeout','Feedback did not finish.');"
    "if i>numel(COPS_COMMENT_TEST.keys), event=[]; return; end"
    "event=struct('Pressed',~ismember(i,COPS_COMMENT_TEST.releases),'CookedKey',COPS_COMMENT_TEST.keys(i), ..."
    "    'QuitRequested',ismember(i,COPS_COMMENT_TEST.quitEvents));"
    "end"]);
writeMock(folder,'KbName',[
    "function key=KbName(name)"
    "if strcmp(name,'F4'), key=4; else, key=[]; end"
    "end"]);
writeMock(folder,'readCoPsKeyboardx',[
    "function [keys,space]=readCoPsKeyboardx(setup)"
    "global COPS_COMMENT_TEST"
    "COPS_COMMENT_TEST.polls=COPS_COMMENT_TEST.polls+1;"
    "keys=false(1,256); keys(4)=ismember(COPS_COMMENT_TEST.polls,COPS_COMMENT_TEST.quitAt); space=false;"
    "end"]);
writeMock(folder,'WaitSecs',["function WaitSecs(varargin)";"end"]);
writeMock(folder,'IsLinux',[
    "function yes=IsLinux"
    "global COPS_COMMENT_TEST"
    "yes=COPS_COMMENT_TEST.linux;"
    "end"]);
writeMock(folder,'refreshCoPsPreviewWindowx',[
    "function changed=refreshCoPsPreviewWindowx(varargin)"
    "changed=false;"
    "end"]);
addpath(fileparts(mfilename('fullpath')),folder,'-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear Screen DrawFormattedText KbQueueCreate KbQueueStart KbQueueRelease ListenChar KbEventGet KbName readCoPsKeyboardx WaitSecs refreshCoPsPreviewWindowx IsLinux
rmdir(testCase.TestData.folder,'s');
clear global COPS_COMMENT_TEST
end

function setup(~)
global COPS_COMMENT_TEST
COPS_COMMENT_TEST=struct('textSize',48,'keys',13,'reads',0,'polls',0, ...
    'releases',[],'quitAt',[],'drawn',{{}},'flips',0,'failFlip',Inf, ...
    'created',false,'released',false,'device',[],'listen',[],'checkpoint','', ...
    'quitEvents',[],'failStart',false,'linux',false);
end

function testSubmissionIsCheckpointedAfterPayoutAndOnlyCollectedOnce(testCase)
global COPS_COMMENT_TEST
COPS_COMMENT_TEST.keys=[double('Clear instructions, thanks!') 13];
ex=fixture(); before=ex;
ex.setup.keyboards=struct('separate',true,'participantIndex',7,'experimenterIndex',9);
ex=finalize(testCase,ex);
verifyEqual(testCase,ex.ParticipantFeedback.text,'Clear instructions, thanks!');
verifySubstring(testCase,ex.ParticipantFeedback.prompt, ...
    'Did you notice anything about the task that wasn''t explicitly explained?');
verifyTrue(testCase,ex.ParticipantFeedback.submitted);
verifyFalse(testCase,ex.ParticipantFeedback.skipped);
verifyGreaterThan(testCase,ex.ParticipantFeedback.off,ex.ParticipantFeedback.on);
verifyEqual(testCase,COPS_COMMENT_TEST.device,7);
verifyTrue(testCase,COPS_COMMENT_TEST.released);
verifyEqual(testCase,COPS_COMMENT_TEST.listen,[-1 0]);
verifyEqual(testCase,COPS_COMMENT_TEST.textSize,48);
verifyEqual(testCase,ex.Trials,before.Trials);
verifyEqual(testCase,[ex.j ex.finish ex.quit],[2 1 0]);
saved=load(COPS_COMMENT_TEST.checkpoint,'ex');
verifyEqual(testCase,saved.ex.ParticipantFeedback,ex.ParticipantFeedback);
flips=COPS_COMMENT_TEST.flips;
again=finalize(testCase,ex);
verifyEqual(testCase,again.ParticipantFeedback,ex.ParticipantFeedback);
verifyEqual(testCase,COPS_COMMENT_TEST.flips,flips);
end

function testSpacesQuestionKeyBackspaceAndKeyReleasesAreText(testCase)
global COPS_COMMENT_TEST
COPS_COMMENT_TEST.keys=[double('Q az') 8 double('!') double('x') 13];
COPS_COMMENT_TEST.releases=7;
ex=finalize(testCase,fixture());
verifyEqual(testCase,ex.ParticipantFeedback.text,'Q a!');
verifyTrue(testCase,ex.ParticipantFeedback.submitted);
end

function testEscapeKeepsDraftAndRecordsSkip(testCase)
global COPS_COMMENT_TEST
COPS_COMMENT_TEST.keys=[double('Too fast') 27];
ex=finalize(testCase,fixture());
verifyEqual(testCase,ex.ParticipantFeedback.text,'Too fast');
verifyFalse(testCase,ex.ParticipantFeedback.submitted);
verifyTrue(testCase,ex.ParticipantFeedback.skipped);
end

function testBlankResponseCanBeSubmitted(testCase)
ex=finalize(testCase,fixture());
verifyEqual(testCase,ex.ParticipantFeedback.text,'');
verifyTrue(testCase,ex.ParticipantFeedback.submitted);
end

function testHeldOperatorF4RequiresReleaseAndNewPress(testCase)
global COPS_COMMENT_TEST
COPS_COMMENT_TEST.keys=double('abc');
COPS_COMMENT_TEST.quitAt=[1 2 4];
ex=finalize(testCase,fixture());
verifyEqual(testCase,ex.ParticipantFeedback.text,'ab');
verifyTrue(testCase,ex.ParticipantFeedback.skipped);
verifyEqual(testCase,COPS_COMMENT_TEST.polls,4);
end

function testCapturedF4RequiresFreshPressAndSkipsFeedback(testCase)
global COPS_COMMENT_TEST
COPS_COMMENT_TEST.keys=[-1 double('a') -1];
COPS_COMMENT_TEST.quitEvents=[1 3];
COPS_COMMENT_TEST.quitAt=[1 2];
ex=finalize(testCase,fixture());
verifyEqual(testCase,ex.ParticipantFeedback.text,'a');
verifyTrue(testCase,ex.ParticipantFeedback.skipped);
end

function testIsolatedLinuxParticipantKeepsItsOwnQueue(testCase)
global COPS_COMMENT_TEST
COPS_COMMENT_TEST.linux=true;
ex=fixture();
ex.setup.keyboards=struct('separate',true,'participantIndex',7,'osKeysIsolated',true);
ex=finalize(testCase,ex);
verifyTrue(testCase,ex.ParticipantFeedback.submitted);
verifyEqual(testCase,COPS_COMMENT_TEST.device,7);
verifyTrue(testCase,COPS_COMMENT_TEST.released);
end

function testLongFeedbackScrollsWithoutTruncatingSavedText(testCase)
global COPS_COMMENT_TEST
text=repmat('Long feedback with spaces. ',1,20);
COPS_COMMENT_TEST.keys=[double(text) 13];
ex=finalize(testCase,fixture());
verifyEqual(testCase,ex.ParticipantFeedback.text,text);
verifyTrue(testCase,ex.ParticipantFeedback.submitted);
end

function testDisabledUnattendedRecordingAndErrorRunsDoNotCollectText(testCase)
global COPS_COMMENT_TEST
for mode={'disabled','unattended','recording','error','dismissed'}
    ex=fixture();
    switch mode{1}
        case 'disabled', ex.exp.CoPs.fbOn=false;
        case 'unattended', ex.setup.showEndScreen=false;
        case 'recording', ex.setup.recording=struct('enabled',true);
        case 'error', ex.lastError=MException('CommentTest:TrialError','Trial failed.');
        case 'dismissed', ex.Outro.acknowledged=false;
    end
    ex=finalize(testCase,ex);
    verifyFalse(testCase,isfield(ex,'ParticipantFeedback'));
    verifyFalse(testCase,COPS_COMMENT_TEST.created);
    verifyEqual(testCase,COPS_COMMENT_TEST.flips,0);
end
end

function testTaskFlagOverridesLegacySetupFlag(testCase)
global COPS_COMMENT_TEST
ex=fixture(); ex.exp.CoPs.fbOn=false; ex.setup.participantFeedback=true;
ex=finalize(testCase,ex);
verifyFalse(testCase,isfield(ex,'ParticipantFeedback'));
verifyFalse(testCase,COPS_COMMENT_TEST.created);
ex=fixture(); ex.exp.CoPs.fbOn=true; ex.setup.participantFeedback=false;
ex=finalize(testCase,ex);
verifyTrue(testCase,ex.ParticipantFeedback.submitted);
end

function testKeyboardStartFailureReleasesResourcesAndSavesSession(testCase)
global COPS_COMMENT_TEST
COPS_COMMENT_TEST.failStart=true;
state=warning('off','CoPs:ParticipantFeedbackFailed');
cleanup=onCleanup(@() warning(state)); %#ok<NASGU>
ex=finalize(testCase,fixture());
verifyEqual(testCase,ex.participantFeedbackError.identifier,'CommentTest:Keyboard');
verifyTrue(testCase,COPS_COMMENT_TEST.released);
verifyEqual(testCase,COPS_COMMENT_TEST.listen,[-1 0]);
end

function testDisplayErrorReleasesKeyboardAndKeepsSavedSession(testCase)
global COPS_COMMENT_TEST
COPS_COMMENT_TEST.keys=[double('a') 13]; COPS_COMMENT_TEST.failFlip=2;
state=warning('off','CoPs:ParticipantFeedbackFailed');
cleanup=onCleanup(@() warning(state)); %#ok<NASGU>
ex=finalize(testCase,fixture());
verifyEqual(testCase,ex.participantFeedbackError.identifier,'CommentTest:Display');
verifyTrue(testCase,COPS_COMMENT_TEST.released);
verifyEqual(testCase,COPS_COMMENT_TEST.listen,[-1 0]);
saved=load(COPS_COMMENT_TEST.checkpoint,'ex');
verifyEqual(testCase,saved.ex.Payout.nTrials,1);
verifyEqual(testCase,saved.ex.Trials,ex.Trials);
end

function ex=fixture()
ex=struct('j',2,'finish',1,'quit',0);
ex.setup=struct('window',101,'participantFeedback',true,'showEndScreen',true, ...
    'keyboards',struct('separate',false),'recording',false);
ex.exp.CoPs.pay=resolveCoPsPayx();
ex.exp.CoPs.fbOn=true;
ex.idx=struct('bg_lum',128,'white',255);
ex.Trials=struct('trialCompleted',true,'times',struct('reward',1:3));
ex.Outro=struct('on',90,'off',91,'acknowledged',true);
end

function ex=finalize(testCase,ex)
global COPS_COMMENT_TEST
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
COPS_COMMENT_TEST.checkpoint=fullfile(testCase.TestData.folder,'session.mat');
ex=finalizeCoPsSessionx(ex,COPS_COMMENT_TEST.checkpoint);
end

function writeMock(folder,name,lines)
fid=fopen(fullfile(folder,[name '.m']),'w');
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',lines);
end
