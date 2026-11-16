function tests = testCoPsFilenamesx
% Check subject prefixes and output reservation without changing saved data.

tests = functiontests(localfunctions);
end


function setupOnce(testCase)
mockDir = tempname;
mkdir(mockDir);
testCase.TestData.mockDir = mockDir;
testCase.TestData.originalPath = path;
fid = fopen(fullfile(mockDir, 'now.m'), 'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, 'function timestamp = now\ntimestamp = datenum(2026, 11, 16, 13, 45, 0);\nend\n');
addpath(fileparts(mfilename('fullpath')), '-begin');
addpath(mockDir, '-begin');
clear now
end


function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear now
localRemoveTemporaryDirectory(testCase.TestData.mockDir);
end


function setup(testCase)
outputRoot = tempname;
mkdir(outputRoot);
testCase.TestData.outputRoot = outputRoot;
end


function teardown(testCase)
localRemoveTemporaryDirectory(testCase.TestData.outputRoot);
end


function testFullEnteredIdentifierStartsFilename(testCase)
ex = fixture(testCase, 'test');
ex.setup.filePrefix = 'P_Ab12';
originalFolder = pwd;
[fname, dayDir, trialDir] = makeFilenameAndDirx(ex, 't3_noiseNull');
verifyEqual(testCase, fname, 'P_Ab12_13.45.t3_noiseNull.mat');
verifyEqual(testCase, dayDir, fullfile(ex.setup.dirRoot, 'test', '2026.11.16'));
verifyEqual(testCase, trialDir, fullfile(dayDir, 'P_Ab12_13.45.t3_noiseNull'));
verifyEqual(testCase, exist(trialDir, 'dir'), 7);
verifyEqual(testCase, pwd, originalFolder);
end


function testExplicitSubjectIdentifierWithoutAnimalDoesNotPrompt(testCase)
for identifier = {'Participant22', 'ka'}
    ex = fixture(testCase, 'test');
    ex.Header = struct('subjectID', identifier{1});
    ex.setup.filePrefix = identifier{1};
    [fname, dayDir] = makeFilenameAndDirx(ex, 'CoPs');
    verifyEqual(testCase, fname, [identifier{1} '_13.45.CoPs.mat']);
    folder = 'test';
    if strcmp(identifier{1}, 'ka'), folder = 'kaki'; end
    verifyEqual(testCase, dayDir, fullfile(ex.setup.dirRoot, folder, '2026.11.16'));
end
end


function testLegacyAnimalFoldersAndPrefixesRemainCompatible(testCase)
animals = {'kiwi', 'mango', 'kaki', 'lychee', 'lemieux', ...
    'tempura', 'hummus', 'shocktop', 'barnum', 'jocamo', 'test'};
prefixes = {'ki', 'ma', 'ka', 'ly', 'le', 'te', 'hu', 'sh', 'ba', 'jo', 't'};
for idx = 1:numel(animals)
    ex = fixture(testCase, animals{idx});
    [fname, dayDir, calibrationDir] = makeFilenameAndDirx(ex, 'EyeCal');
    verifyEqual(testCase, fname, [prefixes{idx} '_13.45.EyeCal.mat']);
    verifyEqual(testCase, dayDir, fullfile(ex.setup.dirRoot, animals{idx}, '2026.11.16'));
    verifyEqual(testCase, calibrationDir, fullfile(dayDir, [prefixes{idx} '_13.45.EyeCal']));
    verifyEqual(testCase, exist(calibrationDir, 'dir'), 7);
end
end


function testExplicitPrefixDoesNotChangeAnimalFolder(testCase)
ex = fixture(testCase, 'kaki');
ex.setup.filePrefix = 'KakiFollowup';
[fname, dayDir] = makeFilenameAndDirx(ex, 'EyeCal');
verifyEqual(testCase, fname, 'KakiFollowup_13.45.EyeCal.mat');
verifyEqual(testCase, dayDir, fullfile(ex.setup.dirRoot, 'kaki', '2026.11.16'));
end


function testSessionIdentifierIsPreserved(testCase)
ex = fixture(testCase, 'test');
ex.setup.filePrefix = "P001";
ex.Header.SessionID = "RunA";
[fname, ~, trialDir] = makeFilenameAndDirx(ex, 'CoPs');
verifyEqual(testCase, fname, 'P001_RunA_13.45.CoPs.mat');
verifyTrue(testCase, endsWith(trialDir, 'P001_RunA_13.45.CoPs'));
end


function testSameMinuteSessionsGetSeparateDirectories(testCase)
ex = fixture(testCase, 'test');
ex.setup.filePrefix = 'P001';
[firstName, dayDir, firstDir] = makeFilenameAndDirx(ex, 'CoPs');
marker = fullfile(firstDir, 'keep.txt');
localWriteText(marker, 'original session');
[secondName, secondDay, secondDir] = makeFilenameAndDirx(ex, 'CoPs');
verifyEqual(testCase, firstName, 'P001_13.45.CoPs.mat');
verifyEqual(testCase, secondName, 'P001_13.45_02.CoPs.mat');
verifyEqual(testCase, secondDay, dayDir);
verifyNotEqual(testCase, secondDir, firstDir);
verifyEqual(testCase, fileread(marker), 'original session');
end


function testExistingSessionMatsAreNotOverwritten(testCase)
ex = fixture(testCase, 'test');
ex.setup.filePrefix = 'P001';
dayDir = fullfile(ex.setup.dirRoot, 'test', '2026.11.16');
mkdir(fullfile(dayDir, 'experimental'));
rootFile = fullfile(dayDir, 'P001_13.45.CoPs.mat');
finalFile = fullfile(dayDir, 'experimental', 'P001_13.45_02.CoPs.mat');
localWriteText(rootFile, 'root original');
localWriteText(finalFile, 'experimental original');
[fname, ~, trialDir] = makeFilenameAndDirx(ex, 'CoPs');
verifyEqual(testCase, fname, 'P001_13.45_03.CoPs.mat');
verifyEqual(testCase, exist(trialDir, 'dir'), 7);
verifyEqual(testCase, fileread(rootFile), 'root original');
verifyEqual(testCase, fileread(finalFile), 'experimental original');
end


function testPrefixSanitizationPreventsPathComponents(testCase)
verifyEqual(testCase, sanitizeCoPsFilePrefixx('  P 01/A:B.C  '), 'P_01_A_B_C');
verifyEqual(testCase, sanitizeCoPsFilePrefixx("Ab_01-Z"), 'Ab_01-Z');
verifyEqual(testCase, sanitizeCoPsFilePrefixx(['P' char(9) '2']), 'P_2');
verifyEqual(testCase, sanitizeCoPsFilePrefixx(char([197 66 48 49])), char([197 66 48 49]));
ex = fixture(testCase, 'test');
ex.setup.filePrefix = '../P 01';
[fname, dayDir] = makeFilenameAndDirx(ex, 'CoPs');
verifyEqual(testCase, fname, '___P_01_13.45.CoPs.mat');
verifyEqual(testCase, dayDir, fullfile(ex.setup.dirRoot, 'test', '2026.11.16'));
end


function testInvalidPrefixDoesNotCreateOutput(testCase)
ex = fixture(testCase, 'test');
ex.setup.filePrefix = '../?';
verifyError(testCase, @() makeFilenameAndDirx(ex, 'CoPs'), 'sanitizeCoPsFilePrefixx:InvalidPrefix');
verifyError(testCase, @() sanitizeCoPsFilePrefixx('   '), 'sanitizeCoPsFilePrefixx:InvalidPrefix');
verifyError(testCase, @() sanitizeCoPsFilePrefixx(["P1" "P2"]), 'sanitizeCoPsFilePrefixx:InvalidPrefix');
entries = dir(fullfile(ex.setup.dirRoot, '*'));
verifyTrue(testCase, all(ismember({entries.name}, {'.', '..'})));
end


function ex = fixture(testCase, animal)
ex = struct('Header', struct('animal', animal), ...
    'setup', struct('dirRoot', testCase.TestData.outputRoot));
end


function localWriteText(file, value)
fid = fopen(file, 'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s', value);
end


function localRemoveTemporaryDirectory(directory)
assert(strcmp(fileparts(directory), fileparts(tempname)), ...
    'Refusing to remove a directory outside the temporary folder.');
rmdir(directory, 's');
end
