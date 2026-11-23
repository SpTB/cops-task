function tests=testCoPsSyncOptionsx
% Check photodiode options before opening a display or accessing hardware.
tests=functiontests(localfunctions);
end

function setupOnce(testCase)
folder=tempname; mkdir(folder);
testCase.TestData.folder=folder;
testCase.TestData.originalPath=path;
writeMock(folder,'initDisplayx',[
    "function ex=initDisplayx(ex)"
    "global COPS_SYNC_OPTIONS_TEST"
    "COPS_SYNC_OPTIONS_TEST=ex;"
    "error('SyncOptionsTest:DisplayCaptured','Stopped before opening a display.');"
    "end"]);
writeMock(folder,'closeCoPsDisplayx',["function closeCoPsDisplayx"; "end"]);
writeMock(folder,'getDefaultSettingsx',[
    "function ex=getDefaultSettingsx(ex,varargin)"
    "ex.setup.adc=struct('Rate',500,'Channels',6);"
    "end"]);
for name={'Datapixx','Eyelink'}
    writeMock(folder,name{1},[
        "function varargout="+name{1}+"(varargin)"
        "error('SyncOptionsTest:UnexpectedHardware','Hardware must remain disabled.');"
        "end"]);
end
addpath(fileparts(mfilename('fullpath')),'-begin');
addpath(folder,'-begin'); clearMocks();
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath); clearMocks();
folder=testCase.TestData.folder;
assert(strcmp(fileparts(folder),fileparts(tempname)));
rmdir(folder,'s');
clear global COPS_SYNC_OPTIONS_TEST
end

function testDefaultsPreserveLegacyGoPulse(testCase)
ex=captureBeforeDisplay(testCase,'test1');
verifyEqual(testCase,string(ex.exp.CoPs.sync.mode),"goPulse");
verifyEqual(testCase,ex.exp.CoPs.sync.framesPerBit,1);
verifyFalse(testCase,ex.setup.dependencies.datapixxOn);
verifyFalse(testCase,ex.setup.dependencies.eyelinkOn);
end

function testBinaryOptionsReachBothProfilesWithoutEnablingHardware(testCase)
bits=logical([1 0 0 1 1 0 1 0]);
for profile={'t','test1'}
    ex=captureBeforeDisplay(testCase,profile{1},false,false,false,false, ...
        syncMode='binary',syncFramesPerBit=3,syncSequence=bits);
    verifyEqual(testCase,string(ex.exp.CoPs.sync.mode),"binary");
    verifyEqual(testCase,ex.exp.CoPs.sync.framesPerBit,3);
    verifyEqual(testCase,logical(ex.exp.CoPs.sync.sequence(:)'),bits);
    verifyFalse(testCase,ex.setup.dependencies.pixOn);
    verifyFalse(testCase,ex.setup.dependencies.eyeOn);
    verifyFalse(testCase,ex.setup.dependencies.rewOn);
    verifyFalse(testCase,ex.setup.dependencies.datapixxOn);
    verifyFalse(testCase,ex.setup.dependencies.eyelinkOn);
end
end

function testDocumentedDefaultHardwareCallsParseBinaryOptions(testCase)
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
clearMocks();
% Reaching the fake hardware proves these calls passed argument parsing.
% The mock always raises before any real device can be touched.
verifyError(testCase,@() runEx('t',syncMode='binary'), ...
    'SyncOptionsTest:UnexpectedHardware');
verifyError(testCase,@() runEx(syncMode='binary'), ...
    'SyncOptionsTest:UnexpectedHardware');
end

function testOffAndGoPulseAreExplicitlySelectable(testCase)
for mode={'off','goPulse'}
    ex=captureBeforeDisplay(testCase,'test1',syncMode=mode{1});
    verifyEqual(testCase,string(ex.exp.CoPs.sync.mode),string(mode{1}));
end
end

function testInvalidModeFailsBeforeDisplay(testCase)
global COPS_SYNC_OPTIONS_TEST
COPS_SYNC_OPTIONS_TEST=[];
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
caught=[];
try
    evalc('runEx(''test1'',syncMode=''invalid'');');
catch err
    caught=err;
end
verifyNotEmpty(testCase,caught);
verifyEmpty(testCase,COPS_SYNC_OPTIONS_TEST);
if ~isempty(caught)
    verifyNotEqual(testCase,caught.identifier,'SyncOptionsTest:UnexpectedHardware');
end
end

function ex=captureBeforeDisplay(testCase,varargin)
global COPS_SYNC_OPTIONS_TEST
COPS_SYNC_OPTIONS_TEST=[];
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
clearMocks(); caught=[];
try
    evalc('runEx(varargin{:});');
catch err
    caught=err;
end
assertNotEmpty(testCase,caught,'Display capture was not reached.');
assertEqual(testCase,caught.identifier,'SyncOptionsTest:DisplayCaptured',caught.message);
ex=COPS_SYNC_OPTIONS_TEST;
assertNotEmpty(testCase,ex);
end

function clearMocks()
clear initDisplayx closeCoPsDisplayx getDefaultSettingsx Datapixx Eyelink
end

function writeMock(folder,name,lines)
fid=fopen(fullfile(folder,[name '.m']),'w');
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',lines);
end
