function tests = testCoPsSubjectInputx
% Exercise subject entry in the real settings questionnaire without GUI/hardware.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
mockDir = tempname;
mkdir(mockDir);
testCase.TestData.mockDir = mockDir;
testCase.TestData.originalPath = path;
writeMock(mockDir, 'getComputerName', [
    "function name = getComputerName"
    "name = 'cops-subject-input-test';"
    "end"]);
writeMock(mockDir, 'getExperimenterInitialsVS', [
    "function initials = getExperimenterInitialsVS(varargin)"
    "initials = 'xx';"
    "end"]);
writeMock(mockDir, 'inputdlg', [
    "function answer = inputdlg(varargin)"
    "global COPS_SUBJECT_INPUT_TEST"
    "COPS_SUBJECT_INPUT_TEST.inputCalls = COPS_SUBJECT_INPUT_TEST.inputCalls + 1;"
    "answer = COPS_SUBJECT_INPUT_TEST.answer;"
    "end"]);
writeMock(mockDir, 'questdlg', [
    "function answer = questdlg(question, varargin)"
    "global COPS_SUBJECT_INPUT_TEST"
    "COPS_SUBJECT_INPUT_TEST.questions{end+1} = question;"
    "if contains(question, 'recording neural'), answer = 'no';"
    "elseif contains(question, 'monocular or binocular'), answer = 'binocular';"
    "elseif contains(question, 'motion detector'), answer = 'no';"
    "else, error('CoPsSubjectTest:UnexpectedQuestion', 'Unexpected questionnaire prompt.'); end"
    "end"]);
writeMock(mockDir, 'resetAdcBuffer', [
    "function resetAdcBuffer(varargin)"
    "error('CoPsSubjectTest:UnexpectedHardware', 'ADC initialization must remain off.');"
    "end"]);
addpath(fileparts(mfilename('fullpath')), '-begin');
addpath(mockDir, '-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear getDefaultSettingsx getComputerName getExperimenterInitialsVS inputdlg questdlg resetAdcBuffer
mockDir = testCase.TestData.mockDir;
assert(strcmp(fileparts(mockDir), fileparts(tempname)), ...
    'Refusing to remove a mock directory outside the temporary folder.');
rmdir(mockDir, 's');
clear global COPS_SUBJECT_INPUT_TEST
end

function setup(~)
global COPS_SUBJECT_INPUT_TEST
COPS_SUBJECT_INPUT_TEST = struct('answer', {{' P001 '}}, ...
    'inputCalls', 0, 'questions', {{}});
end

function testFullHumanSubjectPrefixSurvivesQuestionnaire(testCase)
global COPS_SUBJECT_INPUT_TEST
ex = collectSettings(testCase);
verifyEqual(testCase, ex.Header.subjectID, 'P001');
verifyEqual(testCase, ex.setup.filePrefix, 'P001');
verifyEqual(testCase, ex.Header.animal, 'test');
verifyEqual(testCase, ex.Header.experimenter, 'xx');
verifyFalse(testCase, logical(ex.setup.recording));
verifyEqual(testCase, ex.setup.el.binoc, 1);
verifyFalse(testCase, logical(ex.setup.motionDetector.on));
verifyEqual(testCase, COPS_SUBJECT_INPUT_TEST.inputCalls, 1);
verifyNumElements(testCase, COPS_SUBJECT_INPUT_TEST.questions, 3);
end

function testFullPrefixKeepsLegacyAnimalFolderMapping(testCase)
global COPS_SUBJECT_INPUT_TEST
COPS_SUBJECT_INPUT_TEST.answer = {' kakiLong '};
ex = collectSettings(testCase);
verifyEqual(testCase, ex.Header.subjectID, 'kakiLong');
verifyEqual(testCase, ex.setup.filePrefix, 'kakiLong');
verifyEqual(testCase, ex.Header.animal, 'kaki');
verifyEqual(testCase, COPS_SUBJECT_INPUT_TEST.inputCalls, 1);
end

function ex = collectSettings(testCase)
evalc('ex = setDefaultsCoPs(struct());');
ex.setup = struct('testMode', true, 'viewingDistance', 55, 'monitorWidth', 54);
originalFolder = pwd;
cd(testCase.TestData.mockDir);
restoreFolder = onCleanup(@() cd(originalFolder)); %#ok<NASGU>
clear getDefaultSettingsx getComputerName getExperimenterInitialsVS inputdlg questdlg resetAdcBuffer
evalc('ex = getDefaultSettingsx(ex, false, initializeAdc=false);');
end

function writeMock(folder, name, lines)
fid = fopen(fullfile(folder, [name '.m']), 'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', lines);
end
