function tests = testCoPsKeyboardRoutingx
% Exercise keyboard roles without reading or grabbing physical devices.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
folder = tempname;
mkdir(folder);
testCase.TestData.folder = folder;
testCase.TestData.originalPath = path;
writeMock(folder, 'KbName', [
    "function value = KbName(name)"
    "names = {'space','F1','F2','F3','F4','F6','F7','F8','F9','c','Control_L','q','Return'};"
    "if strcmp(name, 'UnifyKeyNames'), value = []; return; end"
    "value = find(strcmp(name, names), 1);"
    "if isempty(value), error('CoPsKeyboardTest:UnknownKey', 'Unknown key.'); end"
    "end"]);
writeMock(folder, 'KbCheck', [
    "function [down, timestamp, keys] = KbCheck(varargin)"
    "global COPS_KEYBOARD_TEST"
    "COPS_KEYBOARD_TEST.calls{end+1} = varargin;"
    "if isempty(varargin), device = 3; else, device = varargin{1}; end"
    "if device == -1"
    "    keys = any(vertcat(COPS_KEYBOARD_TEST.states{:}), 1); device = 3;"
    "else"
    "    keys = COPS_KEYBOARD_TEST.states{device};"
    "end"
    "down = any(keys); timestamp = device * 11;"
    "end"]);
addpath(fileparts(mfilename('fullpath')), '-begin');
addpath(folder, '-begin');
clear readCoPsKeyboardx KbName KbCheck
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear readCoPsKeyboardx KbName KbCheck
folder = testCase.TestData.folder;
assert(strcmp(fileparts(folder), fileparts(tempname)), ...
    'Refusing to remove a directory outside the temporary folder.');
rmdir(folder, 's');
clear global COPS_KEYBOARD_TEST
end

function setup(~)
global COPS_KEYBOARD_TEST
COPS_KEYBOARD_TEST = struct('states', {{false(1, 256), false(1, 256), false(1, 256)}}, ...
    'calls', {{}});
end

function testParticipantKeysCannotBecomeOperatorShortcuts(testCase)
global COPS_KEYBOARD_TEST
COPS_KEYBOARD_TEST.states{1}(:) = true;
[operator, space] = readCoPsKeyboardx(separateSetup());
verifyFalse(testCase, any(operator));
verifyTrue(testCase, space);
end

function testParticipantNonSpaceKeysHaveNoTaskAction(testCase)
global COPS_KEYBOARD_TEST
COPS_KEYBOARD_TEST.states{1}(:) = true;
COPS_KEYBOARD_TEST.states{1}(1) = false;
[operator, space] = readCoPsKeyboardx(separateSetup());
verifyFalse(testCase, any(operator));
verifyFalse(testCase, space);
end

function testOperatorQuitWorksWhileParticipantHoldsKeys(testCase)
global COPS_KEYBOARD_TEST
COPS_KEYBOARD_TEST.states{1}([1 10 11]) = true; % SPACE, C, Control
COPS_KEYBOARD_TEST.states{2}(5) = true; % F4
[operator, space, timestamp] = readCoPsKeyboardx(separateSetup());
verifyEqual(testCase, find(operator), 5);
verifyTrue(testCase, space);
verifyEqual(testCase, timestamp, 22);
verifyEqual(testCase, COPS_KEYBOARD_TEST.calls, {{2}, {1}});
end

function testOperatorSpaceDoesNotAdvanceParticipantTrial(testCase)
global COPS_KEYBOARD_TEST
COPS_KEYBOARD_TEST.states{2}(1) = true;
[operator, space] = readCoPsKeyboardx(separateSetup());
verifyFalse(testCase, any(operator));
verifyFalse(testCase, space);
end

function testAllOperatorShortcutsAreAvailableAndOtherKeysFiltered(testCase)
global COPS_KEYBOARD_TEST
COPS_KEYBOARD_TEST.states{2}(:) = true;
[operator, space] = readCoPsKeyboardx(separateSetup());
verifyEqual(testCase, find(operator), 2:9);
verifyFalse(testCase, space);
end

function testSharedKeyboardPreservesSpaceAndQuit(testCase)
global COPS_KEYBOARD_TEST
COPS_KEYBOARD_TEST.states{3}([1 5 10 11]) = true;
for options = {struct(), struct('keyboards', struct('separate', false))}
    [operator, space, timestamp] = readCoPsKeyboardx(options{1});
    verifyEqual(testCase, find(operator), 5);
    verifyTrue(testCase, space);
    verifyEqual(testCase, timestamp, 33);
end
verifyEqual(testCase, COPS_KEYBOARD_TEST.calls, {{-1}, {-1}});
end

function testSharedModeReadsNonDefaultKeyboard(testCase)
global COPS_KEYBOARD_TEST
COPS_KEYBOARD_TEST.states{1}([1 12]) = true; % SPACE/Q on USB keyboard
COPS_KEYBOARD_TEST.states{2}(5) = true; % F4 on another keyboard
[operator, space, ~, question] = readCoPsKeyboardx(struct());
verifyTrue(testCase, space);
verifyTrue(testCase, question);
verifyEqual(testCase, find(operator), 5);
verifyEqual(testCase, COPS_KEYBOARD_TEST.calls, {{-1}});
end

function testRepeatEnterComesOnlyFromParticipantKeyboard(testCase)
global COPS_KEYBOARD_TEST
COPS_KEYBOARD_TEST.states{2}(13)=true;
[~,~,~,~,enter]=readCoPsKeyboardx(separateSetup());
verifyFalse(testCase,enter);
COPS_KEYBOARD_TEST.states{1}(13)=true;
[operator,space,~,question,enter]=readCoPsKeyboardx(separateSetup());
verifyTrue(testCase,enter);
verifyFalse(testCase,space);
verifyFalse(testCase,question);
verifyFalse(testCase,any(operator));
end

function testSharedKeyboardRepeatEnter(testCase)
global COPS_KEYBOARD_TEST
COPS_KEYBOARD_TEST.states{3}(13)=true;
[operator,space,~,~,enter]=readCoPsKeyboardx(struct());
verifyTrue(testCase,enter);
verifyFalse(testCase,space);
verifyFalse(testCase,any(operator));
end

function value = separateSetup()
value = struct('keyboards', struct('separate', true, ...
    'participantIndex', 1, 'experimenterIndex', 2));
end

function testQuestionComesOnlyFromParticipantKeyboard(testCase)
global COPS_KEYBOARD_TEST
COPS_KEYBOARD_TEST.states{2}(12)=true;
[~,~,~,question]=readCoPsKeyboardx(separateSetup());
verifyFalse(testCase,question);
COPS_KEYBOARD_TEST.states{1}(12)=true;
[operator,space,~,question]=readCoPsKeyboardx(separateSetup());
verifyTrue(testCase,question);
verifyFalse(testCase,space);
verifyFalse(testCase,any(operator));
end

function testSharedKeyboardQuestionIsAnOptionalFourthOutput(testCase)
global COPS_KEYBOARD_TEST
COPS_KEYBOARD_TEST.states{3}(12)=true;
[operator,space,~,question]=readCoPsKeyboardx(struct());
verifyTrue(testCase,question);
verifyFalse(testCase,space);
verifyFalse(testCase,any(operator));
end

function writeMock(folder, name, lines)
fid = fopen(fullfile(folder, [name '.m']), 'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', lines);
end
