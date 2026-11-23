function tests = testCoPsEyelinkQueuex
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
folder=tempname; mkdir(folder);
testCase.TestData.folder=folder;
testCase.TestData.originalPath=path;
addpath(fileparts(mfilename('fullpath')));
fid=fopen(fullfile(folder,'Eyelink.m'),'w');
fprintf(fid,'%s\n',[
    "function type=Eyelink(command)"
    "global COPS_QUEUE_TEST"
    "assert(strcmp(command,'GetNextDataType'),'Bulk queue allocation must not be used during discard.');"
    "COPS_QUEUE_TEST.calls=COPS_QUEUE_TEST.calls+1;"
    "if COPS_QUEUE_TEST.neverEmpty, type=200; return; end"
    "type=COPS_QUEUE_TEST.types(1); COPS_QUEUE_TEST.types(1)=[];"
    "end"]);
fclose(fid);
addpath(folder,'-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear Eyelink
rmdir(testCase.TestData.folder,'s');
clear global COPS_QUEUE_TEST
end

function testDiscardsSamplesEventsAndOverflowMarkers(testCase)
global COPS_QUEUE_TEST
COPS_QUEUE_TEST=struct('types',[200 5 63 200 0],'calls',0,'neverEmpty',false);
verifyEqual(testCase,discard(testCase),4);
verifyEqual(testCase,COPS_QUEUE_TEST.calls,5);
verifyEmpty(testCase,COPS_QUEUE_TEST.types);
end

function testEmptyQueueRequiresOneRead(testCase)
global COPS_QUEUE_TEST
COPS_QUEUE_TEST=struct('types',0,'calls',0,'neverEmpty',false);
verifyEqual(testCase,discard(testCase),0);
verifyEqual(testCase,COPS_QUEUE_TEST.calls,1);
end

function testUnendingQueueFailsWithBoundedWork(testCase)
global COPS_QUEUE_TEST
COPS_QUEUE_TEST=struct('types',[],'calls',0,'neverEmpty',true);
verifyError(testCase,@() discard(testCase),'drainCoPsEyelinkQueuex:NotDrained');
verifyEqual(testCase,COPS_QUEUE_TEST.calls,100000);
end

function n=discard(testCase)
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
n=drainCoPsEyelinkQueuex();
end
