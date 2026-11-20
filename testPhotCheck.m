function tests = testPhotCheck
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
folder=tempname; mkdir(folder);
testCase.TestData.folder=folder;
testCase.TestData.originalPath=path;
fid=fopen(fullfile(folder,'runEx.m'),'w');
fprintf(fid,'%s\n',[
    "function ex=runEx(profile,varargin)"
    "global COPS_PHOTCHECK_TEST"
    "COPS_PHOTCHECK_TEST.profile=profile;"
    "COPS_PHOTCHECK_TEST.args=struct(varargin{:});"
    "ex=COPS_PHOTCHECK_TEST.ex;"
    "end"]);
fclose(fid);
addpath(fileparts(mfilename('fullpath')),folder,'-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath); clear runEx
folder=testCase.TestData.folder;
assert(strcmp(fileparts(folder),fileparts(tempname)));
rmdir(folder,'s');
clear global COPS_PHOTCHECK_TEST
end

function setup(~)
global COPS_PHOTCHECK_TEST
trial.sync=prepareCoPsSyncx(struct('mode','binary'),1/120);
trial.syncClock=struct('ptbSec',100,'datapixxSec',5000,'uncertaintySec',.0001);
trial.Analog=struct('n',4,'t',5000+[0 .0005 .001 .0015], ...
    'v',[8 8 8 8;19.9 .1 2 .6]);
trial.adcChannels=[6 0];
trial.flip_info=[99.9 0 0 0;100 0 0 0;100+1/120 0 0 0;NaN NaN NaN NaN];
trial.frameSyncBit=[0;1;0;NaN];
trial.frameSyncPhase=uint8([0;1;3;0]);
trial.syncOffTime=100+2/120;
trial.trialCompleted=true;
COPS_PHOTCHECK_TEST=struct('ex',struct('Trials',trial),'args',struct(),'profile','');
end

function testSingleTrialUsesOnlyExplicitMouseSimulationAndAdc(testCase)
global COPS_PHOTCHECK_TEST
[~,pd]=invoke(testCase,showPlot=false);
a=COPS_PHOTCHECK_TEST.args;
verifyEqual(testCase,COPS_PHOTCHECK_TEST.profile,'mouse_mini');
verifyEqual(testCase,a.testTrials,1);
verifyFalse(testCase,a.instrOn);
verifyFalse(testCase,a.jointBlocks);
verifyFalse(testCase,a.showEndScreen);
verifyFalse(testCase,a.overlayOn);
verifyFalse(testCase,a.soundOn);
verifyTrue(testCase,a.fullscreen);
verifyTrue(testCase,a.photodiodeRecord);
verifyEqual(testCase,a.photodiodeChannel,0);
verifyEqual(testCase,a.photodiodeSampleRate,2000);
verifyEqual(testCase,a.syncMode,'binary');
verifyEqual(testCase,a.syncFramesPerBit,1);
verifyEqual(testCase,a.photodiodeTailSecs,.1);
verifyFalse(testCase,pd.timing.tailComplete);
verifyFalse(testCase,pd.timing.passed);
verifyEqual(testCase,pd.voltage,[-.1 .1 2 .6],'AbsTol',1e-12);
verifyEqual(testCase,pd.time,[.1 .1005 .101 .1015],'AbsTol',1e-9);
verifyEqual(testCase,pd.frameTime,[0;.1;.1+1/120],'AbsTol',1e-9);
verifyEqual(testCase,pd.frameBit,[0;1;0]);
end

function testCustomChannelRateAndHeldBits(testCase)
global COPS_PHOTCHECK_TEST
[~,pd]=invoke(testCase,channel=6,sampleRate=5000,framesPerBit=2,tailSecs=.2,showPlot=false);
a=COPS_PHOTCHECK_TEST.args;
verifyEqual(testCase,[a.photodiodeChannel a.photodiodeSampleRate a.syncFramesPerBit],[6 5000 2]);
verifyEqual(testCase,pd.voltage,[8 8 8 8]);
verifyEqual(testCase,a.photodiodeTailSecs,.2);
end

function testEarlyExitWithoutTraceReturnsExperiment(testCase)
global COPS_PHOTCHECK_TEST
COPS_PHOTCHECK_TEST.ex=struct('quit',4);
verifyWarning(testCase,@() invoke(testCase,showPlot=false),'photCheck:NoRecording');
end

function testInvalidChannelFailsBeforeStartingTask(testCase)
global COPS_PHOTCHECK_TEST
verifyError(testCase,@() invoke(testCase,channel=16),'MATLAB:validators:mustBeLessThanOrEqual');
verifyEmpty(testCase,COPS_PHOTCHECK_TEST.profile);
end

function varargout=invoke(testCase,varargin)
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
clear runEx
[varargout{1:nargout}]=photCheck(varargin{:});
end
