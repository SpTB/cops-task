function tests = testCoPsSyncHardwarex
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
folder = tempname; mkdir(folder);
testCase.TestData.folder = folder;
testCase.TestData.originalPath = path;
writeMock(folder,'Screen',[
    "function varargout = Screen(varargin)"
    "global COPS_SYNC_HARDWARE_TEST"
    "COPS_SYNC_HARDWARE_TEST.calls{end+1} = varargin;"
    "if strcmp(varargin{1},'Flip'), varargout = {10,10.001,10.002,-0.001}; end"
    "end"]);
writeMock(folder,'Datapixx',[
    "function varargout = Datapixx(command,varargin)"
    "global COPS_SYNC_HARDWARE_TEST"
    "COPS_SYNC_HARDWARE_TEST.calls{end+1} = [{command} varargin];"
    "switch command"
    "case 'GetAdcStatus', varargout = {struct('newBufferFrames',COPS_SYNC_HARDWARE_TEST.count,'numStreamOverflows',COPS_SYNC_HARDWARE_TEST.overflow)};"
    "case 'ReadAdcBuffer', varargout = {[1 2;3 4],[50 50.002],COPS_SYNC_HARDWARE_TEST.underflow,COPS_SYNC_HARDWARE_TEST.readOverflow};"
    "end"
    "end"]);
addpath(fileparts(mfilename('fullpath')),'-begin'); addpath(folder,'-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear Screen Datapixx
folder = testCase.TestData.folder;
assert(strcmp(fileparts(folder),fileparts(tempname)));
rmdir(folder,'s');
clear global COPS_SYNC_HARDWARE_TEST
end

function setup(~)
global COPS_SYNC_HARDWARE_TEST
COPS_SYNC_HARDWARE_TEST = struct('calls',{{}},'count',2,'overflow',false,'underflow',false,'readOverflow',false);
end

function testPatchAndStimulusShareOneScheduledFlip(testCase)
global COPS_SYNC_HARDWARE_TEST
cleanup = useMocks(testCase); %#ok<NASGU>
sync = prepareCoPsSyncx(struct('mode','binary','sequence',[0 1]),1/60);
sync.patchRect = [1800 0 1920 120];
[info,cursor,bit,index,phase] = flipCoPsSyncFramex(sync,0,true,struct('window',7),struct('white',255,'black',0),9);
verifyEqual(testCase,COPS_SYNC_HARDWARE_TEST.calls, ...
    {{'FillRect',7,255,sync.patchRect},{'DrawingFinished',7},{'Flip',7,9+0.5/60}});
verifyEqual(testCase,info,[10 10.001 10.002 -0.001]);
verifyEqual(testCase,[cursor bit double(phase)],[1 1 1]);
verifyTrue(testCase,isnan(index));
end

function testZeroBitIsExplicitlyBlackAndUnscheduledFirstFlip(testCase)
global COPS_SYNC_HARDWARE_TEST
cleanup = useMocks(testCase); %#ok<NASGU>
sync = prepareCoPsSyncx(struct('mode','binary','sequence',[0 1]),1/60);
sync.patchRect = [1800 0 1920 120];
cursor = sync.preambleFrames+sync.gapFrames;
[~,~,bit,index,phase] = flipCoPsSyncFramex(sync,cursor,true,struct('window',7),struct('white',255,'black',0),NaN);
verifyEqual(testCase,COPS_SYNC_HARDWARE_TEST.calls{1},{'FillRect',7,0,sync.patchRect});
verifyEqual(testCase,COPS_SYNC_HARDWARE_TEST.calls{end},{'Flip',7,0});
verifyEqual(testCase,[bit index double(phase)],[0 1 3]);
end

function testIndependentAnalogDrainAndEmptyBuffer(testCase)
global COPS_SYNC_HARDWARE_TEST
cleanup = useMocks(testCase); %#ok<NASGU>
a = readCoPsAnalogx(struct('v',[],'t',[],'n',0));
verifyEqual(testCase,a,struct('v',[1 2;3 4],'t',[50 50.002],'n',2));
COPS_SYNC_HARDWARE_TEST.count = 0;
verifyEqual(testCase,readCoPsAnalogx(a),a);
stopCoPsAnalogx;
verifyEqual(testCase,COPS_SYNC_HARDWARE_TEST.calls{end-1},{'StopAdcSchedule'});
end

function testOverflowStopsRecordingWithClearError(testCase)
global COPS_SYNC_HARDWARE_TEST
cleanup = useMocks(testCase); %#ok<NASGU>
COPS_SYNC_HARDWARE_TEST.overflow = true;
verifyError(testCase,@() readCoPsAnalogx(struct('v',[],'t',[],'n',0)), 'readCoPsAnalogx:Overflow');
end

function testReadErrorsAreNotSilentlySaved(testCase)
global COPS_SYNC_HARDWARE_TEST
cleanup = useMocks(testCase); %#ok<NASGU>
COPS_SYNC_HARDWARE_TEST.readOverflow = true;
verifyError(testCase,@() readCoPsAnalogx(struct('v',[],'t',[],'n',0)), 'readCoPsAnalogx:Overflow');
COPS_SYNC_HARDWARE_TEST.readOverflow = false;
COPS_SYNC_HARDWARE_TEST.underflow = true;
verifyError(testCase,@() readCoPsAnalogx(struct('v',[],'t',[],'n',0)), 'readCoPsAnalogx:Underflow');
end

function cleanup = useMocks(testCase)
original = pwd; cd(testCase.TestData.folder);
cleanup = onCleanup(@() cd(original));
clear Screen Datapixx
end

function writeMock(folder,name,lines)
fid = fopen(fullfile(folder,[name '.m']),'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',lines);
end
