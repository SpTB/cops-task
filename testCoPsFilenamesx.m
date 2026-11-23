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
ex.Header.subjectID = 'P_Ab12';
originalFolder = pwd;
[fname, dayDir, trialDir] = makeFilenameAndDirx(ex, 't3_noiseNull');
verifyEqual(testCase, fname, 'P_Ab012_13.45.t3_noiseNull.mat');
verifyEqual(testCase, dayDir, fullfile(ex.setup.dirRoot, 'P_Ab012', '2026.11.16'));
verifyEqual(testCase, trialDir, fullfile(dayDir, 'P_Ab012_13.45.t3_noiseNull'));
verifyEqual(testCase, exist(trialDir, 'dir'), 7);
verifyEqual(testCase, pwd, originalFolder);
end


function testExplicitSubjectIdentifierWithoutAnimalDoesNotPrompt(testCase)
identifiers = {'Participant22', 'ka'};
expected = {'Participant022', 'ka'};
for idx = 1:numel(identifiers)
    ex = fixture(testCase, 'test');
    ex.Header = struct('subjectID', identifiers{idx});
    ex.setup.filePrefix = identifiers{idx};
    [fname, dayDir] = makeFilenameAndDirx(ex, 'CoPs');
    verifyEqual(testCase, fname, [expected{idx} '_13.45.CoPs.mat']);
    verifyEqual(testCase, dayDir, fullfile(ex.setup.dirRoot, expected{idx}, '2026.11.16'));
end
end


function testSubjectIdentifierWithoutPrefixDoesNotPrompt(testCase)
ex = fixture(testCase, 'test');
ex.Header.subjectID = 'Participant22';
[fname, dayDir] = makeFilenameAndDirx(ex, 'EyeCal');
verifyEqual(testCase, fname, 'Participant022_13.45.EyeCal.mat');
verifyEqual(testCase, dayDir, fullfile(ex.setup.dirRoot, 'Participant022', '2026.11.16'));
end


function testParticipantFoldersOverrideLegacyAnimalMetadata(testCase)
dayDirs = cell(1,3);
identifiers = {'P001','P002','ka'};
for idx = 1:numel(identifiers)
    ex = fixture(testCase, 'test');
    if strcmp(identifiers{idx}, 'ka'), ex.Header.animal = 'kaki'; end
    ex.Header.subjectID = identifiers{idx};
    ex.setup.filePrefix = identifiers{idx};
    [~, dayDirs{idx}] = makeFilenameAndDirx(ex, 'CoPs');
    verifyEqual(testCase, dayDirs{idx}, ...
        fullfile(ex.setup.dirRoot, identifiers{idx}, '2026.11.16'));
end
verifyNumElements(testCase, unique(dayDirs), numel(identifiers));
end


function testCalibrationAndSessionShareParticipantDayFolder(testCase)
ex = fixture(testCase, 'test');
ex.Header.subjectID = 'P001';
ex.setup.filePrefix = 'P001';
[~, calibrationDay, calibrationDir] = makeFilenameAndDirx(ex, 'EyeCal');
[~, sessionDay, sessionDir] = makeFilenameAndDirx(ex, 'CoPs');
verifyEqual(testCase, calibrationDay, fullfile(ex.setup.dirRoot, 'P001', '2026.11.16'));
verifyEqual(testCase, sessionDay, calibrationDay);
verifyNotEqual(testCase, sessionDir, calibrationDir);
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
ex.Header.SessionID = "Run4";
[fname, ~, trialDir] = makeFilenameAndDirx(ex, 'CoPs');
verifyEqual(testCase, fname, 'P001_Run4_13.45.CoPs.mat');
verifyTrue(testCase, endsWith(trialDir, 'P001_Run4_13.45.CoPs'));
end


function testSameMinuteSessionsGetSeparateDirectories(testCase)
ex = fixture(testCase, 'test');
ex.setup.filePrefix = 'P001';
ex.Header.subjectID = 'P001';
[firstName, dayDir, firstDir] = makeFilenameAndDirx(ex, 'CoPs');
marker = fullfile(firstDir, 'keep.txt');
localWriteText(marker, 'original session');
[secondName, secondDay, secondDir] = makeFilenameAndDirx(ex, 'CoPs');
verifyEqual(testCase, firstName, 'P001_13.45.CoPs.mat');
verifyEqual(testCase, secondName, 'P001_13.45_02.CoPs.mat');
verifyEqual(testCase, secondDay, dayDir);
verifyEqual(testCase, dayDir, fullfile(ex.setup.dirRoot, 'P001', '2026.11.16'));
verifyNotEqual(testCase, secondDir, firstDir);
verifyEqual(testCase, fileread(marker), 'original session');
end


function testExistingSessionMatsAreNotOverwritten(testCase)
ex = fixture(testCase, 'test');
ex.setup.filePrefix = 'P001';
ex.Header.subjectID = 'P001';
dayDir = fullfile(ex.setup.dirRoot, 'P001', '2026.11.16');
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
ex.Header.subjectID = '../P 01';
[fname, dayDir] = makeFilenameAndDirx(ex, 'CoPs');
verifyEqual(testCase, fname, '___P_001_13.45.CoPs.mat');
verifyEqual(testCase, dayDir, fullfile(ex.setup.dirRoot, '___P_001', '2026.11.16'));
end


function testSubjectNumberPaddingAndNormalizationAreIdempotent(testCase)
cases = {
    '4', '004'; '04', '004'; '004', '004';
    '0', '000'; '00', '000'; '000', '000';
    't4', 't004'; 't04', 't004'; 't004', 't004';
    'P12', 'P012'; 'P_Ab12', 'P_Ab012'; 'Participant22', 'Participant022';
    ' Ab-4 ', 'Ab-004'; '../P 01', '___P_001';
    'ka', 'ka'; 'Participant', 'Participant'; 'T4_A', 'T4_A';
    'P1234', 'P1234'; '0004', '0004';
    'P9007199254740993', 'P9007199254740993';
    'P0000000000000000004', 'P0000000000000000004'};
for idx = 1:size(cases,1)
    actual = normalizeCoPsSubjectIDx(cases{idx,1});
    verifyEqual(testCase, actual, cases{idx,2});
    verifyEqual(testCase, normalizeCoPsSubjectIDx(actual), actual);
end
verifyEqual(testCase, normalizeCoPsSubjectIDx("Ab_01-Z"), 'Ab_01-Z');
end


function testEquivalentSubjectEntriesShareFolderAndReserveDistinctFiles(testCase)
groups = {{'4','04','004'}, {'t4','t04','t004'}};
expected = {'004','t004'};
for groupIdx = 1:numel(groups)
    variants = groups{groupIdx};
    dayDirs = cell(1,numel(variants));
    trialDirs = cell(1,numel(variants));
    for idx = 1:numel(variants)
        ex = fixture(testCase, 'test');
        ex.Header.subjectID = variants{idx};
        ex.setup.filePrefix = variants{idx};
        [fname, dayDirs{idx}, trialDirs{idx}] = makeFilenameAndDirx(ex, 'CoPs');
        suffix = '';
        if idx>1, suffix = sprintf('_%02d',idx); end
        verifyEqual(testCase, fname, [expected{groupIdx} '_13.45' suffix '.CoPs.mat']);
        verifyEqual(testCase, dayDirs{idx}, ...
            fullfile(ex.setup.dirRoot,expected{groupIdx},'2026.11.16'));
    end
    verifyNumElements(testCase, unique(dayDirs), 1);
    verifyNumElements(testCase, unique(trialDirs), numel(variants));
end
end


function testInvalidSubjectIdentifierDoesNotCreateOutput(testCase)
ex = fixture(testCase, 'test');
ex.setup.filePrefix = 'P001';
ex.Header.subjectID = '../?';
verifyError(testCase, @() makeFilenameAndDirx(ex, 'CoPs'), 'sanitizeCoPsFilePrefixx:InvalidPrefix');
entries = dir(fullfile(ex.setup.dirRoot, '*'));
verifyTrue(testCase, all(ismember({entries.name}, {'.', '..'})));
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
