function tests = testCoPsKeyboardSelectionx
% Named defaults must never select a virtual/control device or a stale index.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
folder=tempname;mkdir(folder);
testCase.TestData.folder=folder;testCase.TestData.originalPath=path;
fid=fopen(fullfile(folder,'GetKeyboardIndices.m'),'w');
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',[
 "function [indices,names]=GetKeyboardIndices"
 "global COPS_KEYBOARD_SELECTION_TEST"
 "COPS_KEYBOARD_SELECTION_TEST.calls=COPS_KEYBOARD_SELECTION_TEST.calls+1;"
 "indices=COPS_KEYBOARD_SELECTION_TEST.indices;names=COPS_KEYBOARD_SELECTION_TEST.names;"
 "end"]);
addpath(fileparts(mfilename('fullpath')));addpath(folder,'-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);clear GetKeyboardIndices
rmdir(testCase.TestData.folder,'s');clear global COPS_KEYBOARD_SELECTION_TEST
end

function setup(~)
global COPS_KEYBOARD_SELECTION_TEST
COPS_KEYBOARD_SELECTION_TEST=struct('indices',[3 4 15 17], ...
 'names',{{'Virtual core XTEST keyboard','Mitsumi Electric Apple Extended USB Keyboard', ...
 'Dell KB216 Wired Keyboard Consumer Control','Dell KB216 Wired Keyboard'}},'calls',0);
end

function testNormalProfilesSelectPhysicalDevicesByExactName(testCase)
for profile={'h','t'}
 [p,e,mode]=select(testCase,rigSetup(),profile{1},'auto');
 verifyEqual(testCase,p,17);verifyEqual(testCase,e,4);verifyEqual(testCase,mode,'separate');
end
end

function testReconnectedDevicesUseCurrentIndices(testCase)
global COPS_KEYBOARD_SELECTION_TEST
COPS_KEYBOARD_SELECTION_TEST.indices=[2 19 7 23];
[p,e]=select(testCase,rigSetup(),'h','auto');
verifyEqual(testCase,p,23);verifyEqual(testCase,e,19);
end

function testPortablePreviewsRemainSharedByDefault(testCase)
global COPS_KEYBOARD_SELECTION_TEST
for profile={'test1','mouse_mini'}
 [p,e,mode]=select(testCase,rigSetup(),profile{1},'auto');
 verifyEmpty(testCase,p);verifyEmpty(testCase,e);verifyEqual(testCase,mode,'shared');
end
verifyEqual(testCase,COPS_KEYBOARD_SELECTION_TEST.calls,0);
end

function testOtherHostsStaySharedWithoutConfiguration(testCase)
global COPS_KEYBOARD_SELECTION_TEST
[p,e,mode]=select(testCase,struct(),'h','auto');
verifyEmpty(testCase,p);verifyEmpty(testCase,e);verifyEqual(testCase,mode,'shared');
verifyEqual(testCase,COPS_KEYBOARD_SELECTION_TEST.calls,0);
end

function testSharedOverrideDoesNotEnumerateDevices(testCase)
global COPS_KEYBOARD_SELECTION_TEST
[p,e,mode]=select(testCase,rigSetup(),'h','shared');
verifyEmpty(testCase,p);verifyEmpty(testCase,e);verifyEqual(testCase,mode,'shared');
verifyEqual(testCase,COPS_KEYBOARD_SELECTION_TEST.calls,0);
end

function testExplicitIndicesOverrideDefaultsAndPreviewProfile(testCase)
global COPS_KEYBOARD_SELECTION_TEST
[p,e,mode]=select(testCase,rigSetup(),'mouse_mini','auto',8,11);
verifyEqual(testCase,p,8);verifyEqual(testCase,e,11);verifyEqual(testCase,mode,'separate');
verifyEqual(testCase,COPS_KEYBOARD_SELECTION_TEST.calls,0);
end

function testPartialIndicesAreNotSilentlyFilledFromDefaults(testCase)
[p,e,mode]=select(testCase,rigSetup(),'h','auto',8,[]);
verifyEqual(testCase,p,8);verifyEmpty(testCase,e);verifyEqual(testCase,mode,'separate');
end

function testSeparateOverrideCanUseRigNamesInPreview(testCase)
[p,e,mode]=select(testCase,rigSetup(),'test1','separate');
verifyEqual(testCase,p,17);verifyEqual(testCase,e,4);verifyEqual(testCase,mode,'separate');
end

function testSharedModeRejectsConflictingIndices(testCase)
verifyError(testCase,@() select(testCase,rigSetup(),'h','shared',17,4),'CoPs:KeyboardModeConflict');
end

function testSeparateModeWithoutNamesOrIndicesFails(testCase)
verifyError(testCase,@() select(testCase,struct(),'h','separate'),'CoPs:KeyboardDefaultsMissing');
end

function testMissingPhysicalKeyboardStopsInsteadOfFallingBack(testCase)
global COPS_KEYBOARD_SELECTION_TEST
COPS_KEYBOARD_SELECTION_TEST.names{4}='Different USB keyboard';
verifyError(testCase,@() select(testCase,rigSetup(),'h','auto'),'CoPs:DefaultKeyboardUnavailable');
end

function testDuplicateDeviceNamesRequireExplicitIndices(testCase)
global COPS_KEYBOARD_SELECTION_TEST
COPS_KEYBOARD_SELECTION_TEST.names{3}=COPS_KEYBOARD_SELECTION_TEST.names{4};
verifyError(testCase,@() select(testCase,rigSetup(),'h','auto'),'CoPs:DefaultKeyboardAmbiguous');
end

function s=rigSetup()
s=struct('keyboardDefaults',struct('mode','separate', ...
 'participantName','Dell KB216 Wired Keyboard', ...
 'experimenterName','Mitsumi Electric Apple Extended USB Keyboard'));
end

function varargout=select(testCase,varargin)
original=pwd;cd(testCase.TestData.folder);cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
[varargout{1:nargout}]=resolveCoPsKeyboardSelectionx(varargin{:});
end
