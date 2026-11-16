function tests = testCoPsKeyboardSetupx
% All OS calls are mocked; these tests never detach a real input device.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
folder = tempname;
mkdir(folder);
testCase.TestData.folder = folder;
testCase.TestData.path = path;
writeMock(folder, 'IsLinux', ["function result = IsLinux"; "global COPS_KEYBOARD_SETUP_TEST"; "COPS_KEYBOARD_SETUP_TEST.platformCalls = COPS_KEYBOARD_SETUP_TEST.platformCalls + 1;"; "result = COPS_KEYBOARD_SETUP_TEST.linux;"; "end"]);
writeMock(folder, 'getenv', ["function result = getenv(name)"; "global COPS_KEYBOARD_SETUP_TEST"; "if isstruct(COPS_KEYBOARD_SETUP_TEST) && strcmp(name, 'DISPLAY'), result = COPS_KEYBOARD_SETUP_TEST.display; elseif isstruct(COPS_KEYBOARD_SETUP_TEST) && strcmp(name, 'XDG_SESSION_TYPE'), result = COPS_KEYBOARD_SETUP_TEST.session; else, result = builtin('getenv', name); end"; "end"]);
writeMock(folder, 'GetKeyboardIndices', ["function [indices, names, infos] = GetKeyboardIndices"; "global COPS_KEYBOARD_SETUP_TEST"; "indices = [4 5]; names = {'Participant USB', 'Experimenter USB'};"; "infos = COPS_KEYBOARD_SETUP_TEST.infos;"; "end"]);
writeMock(folder, 'KbCheck', ["function varargout = KbCheck(index)"; "global COPS_KEYBOARD_SETUP_TEST"; "COPS_KEYBOARD_SETUP_TEST.warmed(end+1) = index;"; "varargout = {index == 4 && COPS_KEYBOARD_SETUP_TEST.participantHeld};"; "end"]);
writeMock(folder, 'system', [
    "function [status, result] = system(command)"
    "global COPS_KEYBOARD_SETUP_TEST"
    "COPS_KEYBOARD_SETUP_TEST.commands{end+1} = command; status = 0; result = '';"
    "if strcmp(command, 'command -v xinput'), result = '/usr/bin/xinput';"
    "elseif startsWith(command, 'LC_ALL=C xinput list --short ')"
    "    id = sscanf(command, 'LC_ALL=C xinput list --short %d');"
    "    if id == 12 && COPS_KEYBOARD_SETUP_TEST.floating, result = 'Participant id=12 [floating slave]';"
    "    elseif id == 12, result = 'Participant id=12 [slave keyboard (3)]';"
    "    else, result = 'Experimenter id=13 [slave keyboard (3)]'; end"
    "elseif strcmp(command, 'xinput float 12')"
    "    if COPS_KEYBOARD_SETUP_TEST.failFloat, status = 1; result = 'float failed';"
    "    else, COPS_KEYBOARD_SETUP_TEST.floating = true; end"
    "elseif strcmp(command, 'xinput reattach 12 3'), COPS_KEYBOARD_SETUP_TEST.floating = false;"
    "else, error('KeyboardTest:UnexpectedCommand', 'Unexpected OS command: %s', command); end"
    "end"]);
addpath(fileparts(mfilename('fullpath')), '-begin');
addpath(folder, '-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.path);
clear IsLinux getenv GetKeyboardIndices KbCheck system
folder = testCase.TestData.folder;
assert(strcmp(fileparts(folder), fileparts(tempname)));
rmdir(folder, 's');
clear global COPS_KEYBOARD_SETUP_TEST
end

function setup(~)
global COPS_KEYBOARD_SETUP_TEST
COPS_KEYBOARD_SETUP_TEST = struct('commands', {{}}, 'platformCalls', 0, ...
    'linux', true, 'display', ':0', 'session', 'x11', 'floating', false, ...
    'failFloat', false, 'participantHeld', false, 'warmed', [], 'infos', {{ ...
    struct('interfaceID', 12, 'locationID', 3), struct('interfaceID', 13, 'locationID', 3)}});
end

function testSharedModeDoesNotQueryOrChangeDevices(testCase)
global COPS_KEYBOARD_SETUP_TEST
[keyboard, cleanup] = initialize(testCase);
verifyFalse(testCase, keyboard.separate);
verifyFalse(testCase, keyboard.osKeysIsolated);
verifyEqual(testCase, keyboard.isolation, 'shared-unprotected');
verifyEmpty(testCase, cleanup);
verifyEmpty(testCase, COPS_KEYBOARD_SETUP_TEST.commands);
verifyEqual(testCase, COPS_KEYBOARD_SETUP_TEST.platformCalls, 0);
end

function testSelectedParticipantIsIsolatedAndRestored(testCase)
global COPS_KEYBOARD_SETUP_TEST
[keyboard, cleanup] = initialize(testCase, 4, 5);
verifyTrue(testCase, keyboard.separate);
verifyTrue(testCase, keyboard.osKeysIsolated);
verifyEqual(testCase, keyboard.participantIndex, 4);
verifyEqual(testCase, keyboard.experimenterIndex, 5);
verifyEqual(testCase, COPS_KEYBOARD_SETUP_TEST.warmed, [4 5]);
verifyTrue(testCase, COPS_KEYBOARD_SETUP_TEST.floating);
clear cleanup
verifyFalse(testCase, COPS_KEYBOARD_SETUP_TEST.floating);
verifyEqual(testCase, COPS_KEYBOARD_SETUP_TEST.commands{end}, 'xinput reattach 12 3');
verifyFalse(testCase, any(strcmp(COPS_KEYBOARD_SETUP_TEST.commands, 'xinput float 13')));
end

function testInvalidRolesFailBeforeAnyDeviceChange(testCase)
global COPS_KEYBOARD_SETUP_TEST
verifyError(testCase, @() initialize(testCase, 4, []), 'initCoPsKeyboardsx:MissingKeyboard');
verifyError(testCase, @() initialize(testCase, 4, 4), 'initCoPsKeyboardsx:SameKeyboard');
verifyError(testCase, @() initialize(testCase, 4, 99), 'initCoPsKeyboardsx:KeyboardUnavailable');
verifyEmpty(testCase, COPS_KEYBOARD_SETUP_TEST.commands);
end

function testSamePhysicalDeviceCannotHaveBothRoles(testCase)
global COPS_KEYBOARD_SETUP_TEST
COPS_KEYBOARD_SETUP_TEST.infos{2}.interfaceID = 12;
verifyError(testCase, @() initialize(testCase, 4, 5), 'initCoPsKeyboardsx:SameKeyboard');
verifyEmpty(testCase, COPS_KEYBOARD_SETUP_TEST.commands);
end

function testUnsupportedPlatformsAreExplicit(testCase)
global COPS_KEYBOARD_SETUP_TEST
COPS_KEYBOARD_SETUP_TEST.linux = false;
verifyError(testCase, @() initialize(testCase, 4, 5), 'initCoPsKeyboardsx:UnsupportedPlatform');
COPS_KEYBOARD_SETUP_TEST.linux = true;
COPS_KEYBOARD_SETUP_TEST.session = 'wayland';
verifyError(testCase, @() initialize(testCase, 4, 5), 'initCoPsKeyboardsx:UnsupportedPlatform');
COPS_KEYBOARD_SETUP_TEST.session = 'x11';
COPS_KEYBOARD_SETUP_TEST.display = '';
verifyError(testCase, @() initialize(testCase, 4, 5), 'initCoPsKeyboardsx:UnsupportedPlatform');
verifyEmpty(testCase, COPS_KEYBOARD_SETUP_TEST.commands);
end

function testStaleAttachmentIsRejected(testCase)
global COPS_KEYBOARD_SETUP_TEST
COPS_KEYBOARD_SETUP_TEST.infos{1}.locationID = 7;
verifyError(testCase, @() initialize(testCase, 4, 5), 'initCoPsKeyboardsx:StaleDevice');
verifyFalse(testCase, any(strcmp(COPS_KEYBOARD_SETUP_TEST.commands, 'xinput float 12')));
end

function testFailedDetachAttemptsRestore(testCase)
global COPS_KEYBOARD_SETUP_TEST
COPS_KEYBOARD_SETUP_TEST.failFloat = true;
verifyError(testCase, @() initialize(testCase, 4, 5), 'initCoPsKeyboardsx:IsolationFailed');
verifyEqual(testCase, COPS_KEYBOARD_SETUP_TEST.commands{end}, 'xinput reattach 12 3');
end

function testHeldParticipantKeysPreventDetaching(testCase)
global COPS_KEYBOARD_SETUP_TEST
COPS_KEYBOARD_SETUP_TEST.participantHeld = true;
verifyError(testCase, @() initialize(testCase, 4, 5), 'initCoPsKeyboardsx:KeysHeld');
verifyFalse(testCase, any(strcmp(COPS_KEYBOARD_SETUP_TEST.commands, 'xinput float 12')));
end

function [keyboard, cleanup] = initialize(testCase, varargin)
originalFolder = pwd;
cd(testCase.TestData.folder);
restoreFolder = onCleanup(@() cd(originalFolder)); %#ok<NASGU>
clear IsLinux getenv GetKeyboardIndices KbCheck system
[keyboard, cleanup] = initCoPsKeyboardsx(varargin{:});
end

function writeMock(folder, name, lines)
fid = fopen(fullfile(folder, [name '.m']), 'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', lines);
end
