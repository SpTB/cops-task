function tests = testCoPsInputSafetyx
% Exercise real gaze decoding and sampling without tracker/display hardware.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
folder = tempname; mkdir(folder);
testCase.TestData.folder = folder;
testCase.TestData.originalPath = path;
repo = fileparts(mfilename('fullpath'));
addpath(repo,fullfile(repo,'CoPs_eyelink'));
writeMock(folder,'GetSecs',[
    "function t=GetSecs"
    "global COPS_INPUT_TEST"
    "t=COPS_INPUT_TEST.now;"
    "end"]);
writeMock(folder,'GetMouse',[
    "function [x,y,buttons]=GetMouse(varargin)"
    "global COPS_INPUT_TEST"
    "COPS_INPUT_TEST.mouseReads=COPS_INPUT_TEST.mouseReads+1;"
    "x=COPS_INPUT_TEST.mouse(1); y=COPS_INPUT_TEST.mouse(2); buttons=false(1,3);"
    "end"]);
writeMock(folder,'Eyelink',[
    "function [samples,events,drained]=Eyelink(command)"
    "global COPS_INPUT_TEST"
    "if strcmp(command,'Shutdown')"
    "    COPS_INPUT_TEST.shutdowns=COPS_INPUT_TEST.shutdowns+1; samples=[]; events=[]; drained=true; return;"
    "end"
    "assert(strcmp(command,'GetQueuedData'));"
    "samples=COPS_INPUT_TEST.queue; events=[]; drained=true;"
    "COPS_INPUT_TEST.queue=zeros(31,0);"
    "end"]);
writeMock(folder,'EyelinkInit',[
    "function [initialized,dummy]=EyelinkInit(varargin)"
    "global COPS_INPUT_TEST"
    "initialized=COPS_INPUT_TEST.initialized; dummy=COPS_INPUT_TEST.dummy;"
    "end"]);
writeMock(folder,'EyelinkInitDefaults',[
    "function el=EyelinkInitDefaults(varargin)"
    "error('CoPsInputTest:NativeInitializationReached','Stopped before real tracker/display initialization');"
    "end"]);
writeMock(folder,'checkEyex',[
    "function [pass,E,position]=checkEyex(E,ex,varargin)"
    "global COPS_INPUT_TEST"
    "E.n=E.n+double(COPS_INPUT_TEST.analogNew);"
    "position=COPS_INPUT_TEST.analogGaze; pass=true;"
    "end"]);
addpath(folder,'-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear GetSecs GetMouse Eyelink EyelinkInit EyelinkInitDefaults checkEyex
folder=testCase.TestData.folder;
assert(strcmp(fileparts(folder),fileparts(tempname)));
rmdir(folder,'s');
clear global COPS_INPUT_TEST
end

function setup(~)
global COPS_INPUT_TEST
COPS_INPUT_TEST=struct('now',50.002,'queue',zeros(31,0), ...
    'mouse',[960 540],'mouseReads',0,'analogNew',false,'analogGaze',[960 540], ...
    'initialized',true,'dummy',false,'shutdowns',0);
end

function testNativeStartupRejectsDummyTracker(testCase)
global COPS_INPUT_TEST
COPS_INPUT_TEST.dummy=true;
verifyNativeStartup(testCase,'initCoPsEyelinkx:DummyMode');
verifyEqual(testCase,COPS_INPUT_TEST.shutdowns,1);
end

function testNativeStartupRejectsConnectionFailure(testCase)
global COPS_INPUT_TEST
COPS_INPUT_TEST.initialized=false;
verifyNativeStartup(testCase,'initCoPsEyelinkx:Connection');
verifyEqual(testCase,COPS_INPUT_TEST.shutdowns,0);
end

function testRealTrackerContinuesToNativeInitialization(testCase)
verifyNativeStartup(testCase,'CoPsInputTest:NativeInitializationReached');
end

function testMissingEyeCoordinatesEarnZeroCloseness(testCase)
for position = [NaN NaN; NaN 540; 960 NaN; Inf 540; 960 -Inf]'
    verifyEqual(testCase,calc_closeness(position,[960 540],100),0);
end
end

function testValidClosenessIsUnchanged(testCase)
verifyEqual(testCase,calc_closeness([960 540],[960 540],100),1);
verifyEqual(testCase,calc_closeness([1010 540],[960 540],100),0.5);
verifyEqual(testCase,calc_closeness([1100 540],[960 540],100),0);
end

function testInvalidTargetOrDistanceEarnsZeroCloseness(testCase)
verifyEqual(testCase,calc_closeness([960 540],[NaN 540],100),0);
for distance = [0 -1 NaN Inf]
    verifyEqual(testCase,calc_closeness([960 540],[960 540],distance),0);
end
end

function testNoEyeSamplesNeverUsesMouse(testCase)
[pass,~,position,sample]=sampleInput(testCase,'eyelink',eyeBuffer());
verifyMissing(testCase,pass,position,sample);
end

function testBlinkDoesNotPassEvenWithFreeViewingAndPassOn(testCase)
global COPS_INPUT_TEST
COPS_INPUT_TEST.queue=trackerSample([960 540 0 960 540 0]);
[pass,E,position,sample]=sampleInput(testCase,'eyelink',eyeBuffer());
verifyEqual(testCase,E.n,1);
verifyMissing(testCase,pass,position,sample);
end

function testMissingDataSentinelNeverUsesMouse(testCase)
global COPS_INPUT_TEST
COPS_INPUT_TEST.queue=trackerSample(repmat(-32768,1,6));
[pass,~,position,sample]=sampleInput(testCase,'eyelink',eyeBuffer());
verifyMissing(testCase,pass,position,sample);
end

function testStaleGazeCannotKeepEarningPoints(testCase)
global COPS_INPUT_TEST
E=eyeBuffer(); E.n=1; E.v=[960;540;30;960;540;30]; E.t=10;
COPS_INPUT_TEST.now=50.2;
[pass,~,position,sample]=sampleInput(testCase,'eyelink',E);
verifyMissing(testCase,pass,position,sample);
end

function testValidNativeEyesAreIndependentOfMouse(testCase)
global COPS_INPUT_TEST
COPS_INPUT_TEST.queue=trackerSample([200 300 30 400 500 30]);
[pass,~,~,sample]=sampleInput(testCase,'eyelink',eyeBuffer());
verifyTrue(testCase,pass);
verifyTrue(testCase,sample.inBounds);
verifyEqual(testCase,sample.position,[300 400]);
verifyEqual(testCase,COPS_INPUT_TEST.mouseReads,0);
verifyTrue(testCase,all(isnan(sample.pointerPosition)));
end

function testOneValidEyeStillSuppliesGaze(testCase)
global COPS_INPUT_TEST
COPS_INPUT_TEST.queue=trackerSample([NaN NaN NaN 400 500 30]);
[pass,~,~,sample]=sampleInput(testCase,'eyelink',eyeBuffer());
verifyTrue(testCase,pass);
verifyTrue(testCase,sample.inBounds);
verifyEqual(testCase,sample.position,[400 500]);
verifyEqual(testCase,COPS_INPUT_TEST.mouseReads,0);
end

function testValidGazeRecoversAfterMissingSamples(testCase)
global COPS_INPUT_TEST
COPS_INPUT_TEST.queue=trackerSample(repmat(NaN,1,6));
[~,E]=sampleInput(testCase,'eyelink',eyeBuffer());
COPS_INPUT_TEST.queue=trackerSample([200 300 30 400 500 30]);
[pass,E,~,sample]=sampleInput(testCase,'eyelink',E);
verifyTrue(testCase,pass);
verifyTrue(testCase,sample.inBounds);
verifyEqual(testCase,E.n,2);
verifyEqual(testCase,sample.position,[300 400]);
end

function testEmptyAnalogBufferCannotReusePreviousGaze(testCase)
E=struct('n',5);
[pass,~,position,sample]=sampleInput(testCase,'eye',E);
verifyMissing(testCase,pass,position,sample);
end

function testFreshAnalogDataNeverUsesMouse(testCase)
global COPS_INPUT_TEST
COPS_INPUT_TEST.analogNew=true;
COPS_INPUT_TEST.analogGaze=[350 400;450 500];
[pass,~,~,sample]=sampleInput(testCase,'eye',struct('n',0));
verifyTrue(testCase,pass);
verifyTrue(testCase,sample.inBounds);
verifyEqual(testCase,sample.position,[400 450]);
verifyEqual(testCase,COPS_INPUT_TEST.mouseReads,0);
end

function testInvalidAnalogCoordinatesNeverUsesMouse(testCase)
global COPS_INPUT_TEST
COPS_INPUT_TEST.analogNew=true;
COPS_INPUT_TEST.analogGaze=[NaN NaN];
[pass,~,position,sample]=sampleInput(testCase,'eye',struct('n',0));
verifyMissing(testCase,pass,position,sample);
end

function testDisabledEyeInputProvidesNoBehavioralSignal(testCase)
[pass,~,position,sample]=sampleInput(testCase,'none',struct());
verifyMissing(testCase,pass,position,sample);
end

function testExplicitMouseSimulationUsesMouse(testCase)
global COPS_INPUT_TEST
[pass,~,position,sample]=sampleInput(testCase,'mouse',struct());
verifyTrue(testCase,pass);
verifyTrue(testCase,sample.inBounds);
verifyEqual(testCase,position,COPS_INPUT_TEST.mouse);
verifyEqual(testCase,sample.position,COPS_INPUT_TEST.mouse);
verifyEqual(testCase,COPS_INPUT_TEST.mouseReads,1);
end

function [pass,E,position,sample]=sampleInput(testCase,mode,E)
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
ex.setup=struct('window',7,'screenRect',[0 0 1920 1080], ...
    'el',struct('SAMPLE_TYPE',200,'MISSING_DATA',-32768), ...
    'dependencies',struct('adcOn',false));
ex.eyeCal=struct(); ex.passOn=true;
ex.fix=struct('PCtr',[960 540],'WinW',50,'WinH',50);
[pass,E,position,sample]=sampleCoPsInputx(mode,E,ex,true,true,[960 540]);
end

function E=eyeBuffer()
E=struct('n',0,'v',zeros(6,0),'t',[],'trackerStart',10,'ptbStart',50);
end

function samples=trackerSample(values)
samples=zeros(31,1);
samples(1)=10002; samples(2)=200;
samples([15 17 13 14 16 12])=values;
end

function verifyNativeStartup(testCase,expectedError)
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
ex.setup=struct('window',7,'el',struct());
verifyError(testCase,@() initCoPsEyelinkx(ex),expectedError);
end

function verifyMissing(testCase,pass,position,sample)
global COPS_INPUT_TEST
verifyFalse(testCase,pass);
verifyFalse(testCase,sample.inBounds);
verifyTrue(testCase,all(isnan(position(:))));
verifyTrue(testCase,all(isnan(sample.position)));
verifyTrue(testCase,all(isnan(sample.pointerPosition)));
verifyEqual(testCase,COPS_INPUT_TEST.mouseReads,0);
verifyEqual(testCase,calc_closeness(sample.position,[960 540],100),0);
end

function writeMock(folder,name,lines)
fid=fopen(fullfile(folder,[name '.m']),'w');
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',lines);
end
