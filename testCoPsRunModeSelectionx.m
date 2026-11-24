function tests = testCoPsRunModeSelectionx
% Capture dispatch before runEx initializes hardware or opens windows.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.TestData.originalPath=path;
folder=tempname; mkdir(folder);
testCase.TestData.folder=folder;
addpath(fileparts(mfilename('fullpath')),'-begin');
fid=fopen(fullfile(folder,'resolveCoPsRunDependenciesx.m'),'w');
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',[
    "function deps=resolveCoPsRunDependenciesx(profile,varargin)"
    "global COPS_RUN_MODE_TEST"
    "COPS_RUN_MODE_TEST=profile;"
    "error('RunModeTest:Captured','Captured mode before hardware initialization');"
    "end"]);
addpath(folder,'-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear resolveCoPsRunDependenciesx
rmdir(testCase.TestData.folder,'s');
clear global COPS_RUN_MODE_TEST
end

function testDefaultRunUsesHumanMode(testCase)
verifyMode(testCase,'h');
end

function testExplicitModesRemainDistinct(testCase)
for profile={'h','t','test1','mouse_mini'}
    verifyMode(testCase,profile{1},profile{1});
end
end

function verifyMode(testCase,expected,varargin)
global COPS_RUN_MODE_TEST
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
clear resolveCoPsRunDependenciesx
COPS_RUN_MODE_TEST='';
verifyError(testCase,@() runEx(varargin{:}),'RunModeTest:Captured');
verifyEqual(testCase,COPS_RUN_MODE_TEST,expected);
end
