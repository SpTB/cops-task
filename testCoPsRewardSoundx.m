function tests = testCoPsRewardSoundx
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
folder = tempname;
mkdir(folder);
testCase.TestData.folder = folder;
testCase.TestData.originalPath = path;
writeMock(folder, 'InitializePsychSound', [
    "function InitializePsychSound(varargin)"
    "global COPS_SOUND_TEST"
    "COPS_SOUND_TEST.initializations = COPS_SOUND_TEST.initializations + 1;"
    "end"]);
writeMock(folder, 'PsychPortAudio', [
    "function varargout = PsychPortAudio(varargin)"
    "global COPS_SOUND_TEST"
    "COPS_SOUND_TEST.calls{end+1} = varargin;"
    "switch lower(varargin{1})"
    "case 'open'"
    "    if COPS_SOUND_TEST.failOpen, error('SoundTest:OpenFailed', 'No device'); end"
    "    varargout = {71};"
    "case 'getstatus', varargout = {struct('SampleRate', 48000, 'Active', COPS_SOUND_TEST.active)};"
    "case 'fillbuffer'"
    "    if COPS_SOUND_TEST.failFill, error('SoundTest:FillFailed', 'Buffer failed'); end"
    "    COPS_SOUND_TEST.buffer = varargin{3};"
    "case 'start', COPS_SOUND_TEST.active = true;"
    "end"
    "end"]);
addpath(fileparts(mfilename('fullpath')), '-begin');
addpath(folder, '-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear PsychPortAudio InitializePsychSound
folder = testCase.TestData.folder;
assert(strcmp(fileparts(folder), fileparts(tempname)));
rmdir(folder, 's');
clear global COPS_SOUND_TEST
end

function setup(~)
global COPS_SOUND_TEST
COPS_SOUND_TEST = struct('calls', {{}}, 'initializations', 0, ...
    'active', false, 'buffer', [], 'failOpen', false, 'failFill', false);
end

function testDisabledSoundDoesNotTouchAudioDevice(testCase)
global COPS_SOUND_TEST
[audio, cleanup] = initCoPsRewardSoundx(false);
verifyFalse(testCase, audio.enabled);
verifyEmpty(testCase, cleanup);
verifyFalse(testCase, playCoPsRewardSoundx(audio));
verifyEmpty(testCase, COPS_SOUND_TEST.calls);
verifyEqual(testCase, COPS_SOUND_TEST.initializations, 0);
end

function testPreloadedToneAndCleanup(testCase)
global COPS_SOUND_TEST
[audio, cleanup] = initCoPsRewardSoundx(true);
verifyEqual(testCase, COPS_SOUND_TEST.initializations, 1);
verifyEqual(testCase, audio.sampleRate, 48000);
tone = COPS_SOUND_TEST.buffer;
verifySize(testCase, tone, [2 1440]);
verifyEqual(testCase, tone(1,:), tone(2,:));
verifyEqual(testCase, tone(:,[1 end]), zeros(2), 'AbsTol', 1e-12);
verifyLessThanOrEqual(testCase, max(abs(tone(:))), 0.1);
verifyGreaterThan(testCase, max(abs(tone(:))), 0.09);
clear cleanup
verifyEqual(testCase, COPS_SOUND_TEST.calls{end}, {'Close', 71});
end

function testPlaybackDoesNotWaitOrRepeatWhileActive(testCase)
global COPS_SOUND_TEST
[audio, cleanup] = initCoPsRewardSoundx(true); %#ok<ASGLU>
verifyTrue(testCase, playCoPsRewardSoundx(audio));
verifyFalse(testCase, playCoPsRewardSoundx(audio));
calls = COPS_SOUND_TEST.calls;
starts = calls(cellfun(@(c) strcmp(c{1}, 'Start'), calls));
verifyEqual(testCase, starts, {{'Start', 71, 1, 0, 0}});
COPS_SOUND_TEST.active = false;
verifyTrue(testCase, playCoPsRewardSoundx(audio));
verifyEqual(testCase, nnz(cellfun(@(c) strcmp(c{1}, 'FillBuffer'), COPS_SOUND_TEST.calls)), 1);
end

function testInitializationFailureReleasesOpenedDevice(testCase)
global COPS_SOUND_TEST
COPS_SOUND_TEST.failFill = true;
verifyError(testCase, @() initCoPsRewardSoundx(true), 'SoundTest:FillFailed');
verifyEqual(testCase, COPS_SOUND_TEST.calls{end}, {'Close', 71});
end

function testUnavailableDeviceHasClearError(testCase)
global COPS_SOUND_TEST
COPS_SOUND_TEST.failOpen = true;
verifyError(testCase, @() initCoPsRewardSoundx(true), 'initCoPsRewardSoundx:OpenFailed');
end

function writeMock(folder, name, lines)
fid = fopen(fullfile(folder, [name '.m']), 'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', lines);
end
