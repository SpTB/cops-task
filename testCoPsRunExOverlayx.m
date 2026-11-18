function tests = testCoPsRunExOverlayx
% Check runEx overlay arguments before opening a display or touching hardware.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
mockDir = tempname;
mkdir(mockDir);
testCase.TestData.mockDir = mockDir;
testCase.TestData.originalPath = path;
writeMock(mockDir, 'initDisplayx', [
    "function ex = initDisplayx(ex)"
    "global COPS_RUNEX_OVERLAY_TEST"
    "COPS_RUNEX_OVERLAY_TEST = ex;"
    "error('CoPsOverlayTest:DisplayCaptured', 'Stopped before opening a display.');"
    "end"]);
writeMock(mockDir, 'closeCoPsDisplayx', ["function closeCoPsDisplayx"; "end"]);
writeMock(mockDir, 'getDefaultSettingsx', [
    "function ex = getDefaultSettingsx(ex, varargin)"
    "global COPS_RUNEX_SUBJECT_TEST"
    "ex.setup.adc = struct('Rate',500,'Channels',6,'DiffChannels',0,'BufferBaseAddress',0);"
    "if ~isempty(COPS_RUNEX_SUBJECT_TEST.existingSubjectID)"
    "    ex.Header.subjectID = COPS_RUNEX_SUBJECT_TEST.existingSubjectID;"
    "    ex.setup.filePrefix = COPS_RUNEX_SUBJECT_TEST.existingSubjectID;"
    "end"
    "end"]);
writeMock(mockDir, 'inputdlg', [
    "function answer = inputdlg(varargin)"
    "global COPS_RUNEX_SUBJECT_TEST"
    "COPS_RUNEX_SUBJECT_TEST.calls = COPS_RUNEX_SUBJECT_TEST.calls + 1;"
    "answer = COPS_RUNEX_SUBJECT_TEST.answer;"
    "end"]);
writeMock(mockDir,'Datapixx',[
    "function varargout = Datapixx(command,varargin)"
    "global COPS_RUNEX_ADC_TEST"
    "if ~COPS_RUNEX_ADC_TEST.enabled, error('CoPsOverlayTest:UnexpectedHardware','Hardware must remain disabled.'); end"
    "COPS_RUNEX_ADC_TEST.calls{end+1} = command;"
    "if strcmp(command,'Open'), varargout = {true}; end"
    "end"]);
writeMock(mockDir,'resetAdcBuffer',[
    "function resetAdcBuffer(ex)"
    "global COPS_RUNEX_ADC_TEST"
    "if ~COPS_RUNEX_ADC_TEST.enabled, error('CoPsOverlayTest:UnexpectedHardware','Hardware must remain disabled.'); end"
    "COPS_RUNEX_ADC_TEST.resetSetup = ex.setup;"
    "end"]);
writeMock(mockDir,'Eyelink',[
    "function varargout = Eyelink(varargin)"
    "error('CoPsOverlayTest:UnexpectedHardware','EyeLink must remain disabled.');"
    "end"]);
addpath(fileparts(mfilename('fullpath')), '-begin');
addpath(mockDir, '-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear initDisplayx closeCoPsDisplayx getDefaultSettingsx inputdlg Datapixx Eyelink resetAdcBuffer
mockDir = testCase.TestData.mockDir;
% Delete only the direct temporary directory created by this test fixture.
assert(strcmp(fileparts(mockDir), fileparts(tempname)), ...
    'Refusing to remove a mock directory outside the temporary folder.');
rmdir(mockDir, 's');
clear global COPS_RUNEX_OVERLAY_TEST
clear global COPS_RUNEX_SUBJECT_TEST
clear global COPS_RUNEX_ADC_TEST
end

function setup(~)
global COPS_RUNEX_SUBJECT_TEST
global COPS_RUNEX_ADC_TEST
COPS_RUNEX_SUBJECT_TEST = struct('answer', {{'test'}}, 'calls', 0, 'existingSubjectID', '');
COPS_RUNEX_ADC_TEST = struct('enabled',false,'calls',{{}},'resetSetup',struct());
end

function testMouseProfileDisplayDefaults(testCase)
for profile = {'test1', 'mouse_mini'}
    ex = captureBeforeDisplay(testCase, profile{1});
    isFullscreen = strcmp(profile{1}, 'test1');
    verifyFalse(testCase, ex.setup.showExperimenterOverlay);
    verifyEqual(testCase, ex.setup.fullscreen, isFullscreen);
    verifyTrue(testCase, ex.setup.soundOn);
    verifyTrue(testCase, ex.exp.CoPs.rew.soundOn);
    verifyFalse(testCase, ex.setup.keyboards.separate);
    verifyFalse(testCase, ex.setup.keyboards.osKeysIsolated);
    verifyMouseOnly(testCase, ex);
end
end

function testRecordingOverridesReachTheRealRunExSetup(testCase)
cfg=struct('length',5,'targetNum',1,'visibility',0.4,'background',-1);
ex=captureBeforeDisplay(testCase,'mouse_mini',recording=cfg,testTrials=1, ...
    instrOn=false,filePrefix="demo",soundOn=false,syncMode='off');
verifyMouseOnly(testCase,ex);
verifyTrue(testCase,ex.setup.recording.enabled);
verifyEqual(testCase,ex.exp.CoPs.ctl.nsteps,150);
verifyEqual(testCase,ex.exp.CoPs.ctl.target_numNULL,1);
verifyEqual(testCase,ex.exp.CoPs.graph.targetVisibilityNull,0.4);
verifyEqual(testCase,ex.exp.CoPs.graph.background_noise_lvl,-1);
verifyFalse(testCase,ex.exp.CoPs.instrOn);
verifyEqual(testCase,ex.exp.CoPs.ctl.gauss_scalar,1);
verifyEqual(testCase,ex.setup.recording.rewardLandscape,0);
verifyEmpty(testCase,ex.MovieFiles);
end

function testRecordingCornerOverridesTheNormalFreeCenter(testCase)
cfg=struct('length',5,'targetNum',2,'visibility',1,'background',-1,'rewardLandscape',4);
ex=captureBeforeDisplay(testCase,'mouse_mini',recording=cfg,testTrials=1, ...
    instrOn=false,filePrefix="demo",soundOn=false,syncMode='off');
verifyFalse(testCase,ex.exp.CoPs.rew.gauss_center_free);
[~,center]=selectGaussRewardCenterCoPsx(ex.exp.CoPs.rew,101,0);
verifyEqual(testCase,center,[0.75 0.75]);
verifyGreaterThan(testCase,ex.exp.CoPs.ctl.gauss_scalar,1);
end

function testExplicitStimulusBankOverridesBundledTestBank(testCase)
for profile={'test1','mouse_mini'}
    bank=testCase.TestData.mockDir;
    ex=captureBeforeDisplay(testCase,profile{1},stimulusDir=string(bank));
    verifyEqual(testCase,ex.exp.CoPs.dirs.all,[bank filesep]);
    verifyEqual(testCase,ex.exp.CoPs.graph.texture_folder_resolved,[bank filesep]);
    verifyEqual(testCase,ex.setup.testConfig.stimulusRoot,bank);
    verifyMouseOnly(testCase,ex);
end
end

function testInvalidStimulusDirectoryFailsBeforeHardwareOrDisplay(testCase)
missing=string(fullfile(testCase.TestData.mockDir,'does_not_exist'));
verifyError(testCase,@() runEx('mouse_mini',stimulusDir=missing),'CoPs:StimulusDirectory');
end

function testBinarySyncOptionsReachDisplayWithoutAcquisition(testCase)
for profile = {'test1', 'mouse_mini'}
    ex = captureBeforeDisplay(testCase, profile{1}, syncMode='binary', ...
        syncFramesPerBit=2, syncSequence=[1 0 0 1]);
    verifyEqual(testCase, ex.exp.CoPs.sync.mode, 'binary');
    verifyEqual(testCase, ex.exp.CoPs.sync.framesPerBit, 2);
    verifyEqual(testCase, ex.exp.CoPs.sync.sequence, [1 0 0 1]);
    verifyMouseOnly(testCase, ex);
end
end

function testInstructionFlagReachesBothMouseProfiles(testCase)
for profile = {'test1','mouse_mini'}
    ex = captureBeforeDisplay(testCase,profile{1},instrOn=true);
    verifyTrue(testCase,ex.exp.CoPs.instrOn);
    verifyEqual(testCase,ex.exp.CoPs.pay.max_bonus_dollar,25);
    verifyEqual(testCase,getCoPsTotalRepsx(ex),5);
    ex = captureBeforeDisplay(testCase,profile{1},instrOn=false);
    verifyFalse(testCase,ex.exp.CoPs.instrOn);
    verifyEqual(testCase,getCoPsTotalRepsx(ex),3);
end
end

function testSoundCanBeDisabledIndependentlyOfOverlay(testCase)
for profile = {'test1', 'mouse_mini'}
    ex = captureBeforeDisplay(testCase, profile{1}, overlayOn=true, soundOn=false);
    verifyFalse(testCase, ex.setup.soundOn);
    verifyFalse(testCase, ex.exp.CoPs.rew.soundOn);
    verifyTrue(testCase, ex.setup.showExperimenterOverlay);
    verifyMouseOnly(testCase, ex);
end
end

function testPhotodiodeAdcRateDoesNotChangeBehavioralPolling(testCase)
global COPS_RUNEX_ADC_TEST
COPS_RUNEX_ADC_TEST.enabled = true;
ex = captureBeforeDisplay(testCase,'mouse_mini',syncMode='binary', ...
    photodiodeRecord=true,photodiodeSampleRate=2000);
verifyEqual(testCase,ex.setup.inputSampleRate,500);
verifyEqual(testCase,ex.setup.adc.Rate,2000);
verifyEqual(testCase,COPS_RUNEX_ADC_TEST.resetSetup.adc.Rate,2000);
verifyEqual(testCase,COPS_RUNEX_ADC_TEST.resetSetup.adc.NumBufferFrames,900000);
verifyTrue(testCase,ex.setup.dependencies.adcOn);
verifyFalse(testCase,ex.setup.dependencies.eyeOn);
verifyFalse(testCase,ex.setup.dependencies.pixOn);
verifyFalse(testCase,ex.setup.dependencies.rewOn);
verifyTrue(testCase,ismember('StopAdcSchedule',COPS_RUNEX_ADC_TEST.calls));
end

function testKeyboardRolesAreValidatedBeforeDisplay(testCase)
global COPS_RUNEX_OVERLAY_TEST
COPS_RUNEX_OVERLAY_TEST = [];
originalFolder = pwd;
cd(testCase.TestData.mockDir);
restoreFolder = onCleanup(@() cd(originalFolder)); %#ok<NASGU>
clear initDisplayx closeCoPsDisplayx getDefaultSettingsx inputdlg
verifyError(testCase, @() runEx('mouse_mini', participantKeyboard=7), ...
    'initCoPsKeyboardsx:MissingKeyboard');
verifyError(testCase, @() runEx('mouse_mini', participantKeyboard=7, experimenterKeyboard=7), ...
    'initCoPsKeyboardsx:SameKeyboard');
verifyEmpty(testCase, COPS_RUNEX_OVERLAY_TEST);
end

function testMouseProfilesAcceptPositionalOverlayToggle(testCase)
for profile = {'test1', 'mouse_mini'}
    for overlayOn = [false true]
        ex = captureBeforeDisplay(testCase, profile{1}, overlayOn);
        verifyEqual(testCase, ex.setup.showExperimenterOverlay, overlayOn);
        verifyEqual(testCase, ex.setup.fullscreen, strcmp(profile{1}, 'test1'));
        verifyMouseOnly(testCase, ex);
    end
end
end

function testMouseProfilesAcceptNamedOverlayToggle(testCase)
for profile = {'test1', 'mouse_mini'}
    for overlayOn = [false true]
        ex = captureBeforeDisplay(testCase, profile{1}, overlayOn=overlayOn);
        verifyEqual(testCase, ex.setup.showExperimenterOverlay, overlayOn);
        verifyEqual(testCase, ex.setup.fullscreen, strcmp(profile{1}, 'test1'));
        verifyMouseOnly(testCase, ex);
    end
end
end

function testMouseProfilesForwardOverlayDisplayOptions(testCase)
for profile = {'test1', 'mouse_mini'}
    ex = captureBeforeDisplay(testCase, profile{1}, overlayOn=true, ...
        overlayScreen=0, overlayWindowSizePx=[800 450]);
    verifyTrue(testCase, ex.setup.showExperimenterOverlay);
    verifyEqual(testCase, ex.setup.overlayScreen, 0);
    verifyEqual(testCase, ex.setup.overlayWindowSizePx, [800 450]);
    verifyMouseOnly(testCase, ex);
end
end

function testNamedOverlayToggleTakesPrecedence(testCase)
for profile = {'test1', 'mouse_mini'}
    ex = captureBeforeDisplay(testCase, profile{1}, false, overlayOn=true);
    verifyTrue(testCase, ex.setup.showExperimenterOverlay);
    ex = captureBeforeDisplay(testCase, profile{1}, true, overlayOn=false);
    verifyFalse(testCase, ex.setup.showExperimenterOverlay);
end
end

function testCalibrationProfileUsesSameOverlayArguments(testCase)
for overlayOn = [false true]
    % Keep all hardware flags off while exercising the calibration profile.
    positional = captureBeforeDisplay(testCase, 't', overlayOn, false, false, false);
    named = captureBeforeDisplay(testCase, 't', false, false, false, false, ...
        overlayOn=overlayOn);
    verifyEqual(testCase, positional.setup.showExperimenterOverlay, overlayOn);
    verifyEqual(testCase, named.setup.showExperimenterOverlay, overlayOn);
    verifyMouseOnly(testCase, positional);
    verifyMouseOnly(testCase, named);
end
end

function testMouseProfilesUseFullEnteredSubjectPrefix(testCase)
global COPS_RUNEX_SUBJECT_TEST
COPS_RUNEX_SUBJECT_TEST.answer = {' P001 '};
for profile = {'test1', 'mouse_mini'}
    ex = captureBeforeDisplay(testCase, profile{1});
    verifyEqual(testCase, ex.setup.filePrefix, 'P001');
    verifyEqual(testCase, ex.Header.subjectID, 'P001');
    verifyEqual(testCase, ex.Header.animal, 'test');
end
verifyEqual(testCase, COPS_RUNEX_SUBJECT_TEST.calls, 2);
end

function testExplicitFilePrefixBypassesSubjectPrompt(testCase)
global COPS_RUNEX_SUBJECT_TEST
for profile = {'test1', 'mouse_mini'}
    ex = captureBeforeDisplay(testCase, profile{1}, filePrefix="P001");
    verifyEqual(testCase, ex.setup.filePrefix, 'P001');
    verifyEqual(testCase, ex.Header.subjectID, 'P001');
    verifyEqual(testCase, ex.Header.animal, 'test');
end
verifyEqual(testCase, COPS_RUNEX_SUBJECT_TEST.calls, 0);
end

function testMouseProfilesReuseQuestionnaireSubjectWithoutSecondPrompt(testCase)
global COPS_RUNEX_SUBJECT_TEST
COPS_RUNEX_SUBJECT_TEST.existingSubjectID = 'P001';
for profile = {'test1', 'mouse_mini'}
    ex = captureBeforeDisplay(testCase, profile{1});
    verifyEqual(testCase, ex.setup.filePrefix, 'P001');
    verifyEqual(testCase, ex.Header.subjectID, 'P001');
    verifyEqual(testCase, ex.Header.animal, 'test');
end
verifyEqual(testCase, COPS_RUNEX_SUBJECT_TEST.calls, 0);
end

function testCancelledSubjectPromptReturnsBeforeDisplay(testCase)
global COPS_RUNEX_OVERLAY_TEST COPS_RUNEX_SUBJECT_TEST
COPS_RUNEX_SUBJECT_TEST.answer = {};
originalFolder = pwd;
cd(testCase.TestData.mockDir);
restoreFolder = onCleanup(@() cd(originalFolder)); %#ok<NASGU>
clear initDisplayx closeCoPsDisplayx getDefaultSettingsx inputdlg Datapixx Eyelink resetAdcBuffer
for profile = {'test1', 'mouse_mini'}
    COPS_RUNEX_OVERLAY_TEST = [];
    evalc('ex = runEx(profile{1});');
    verifyEqual(testCase, ex.quit, 4);
    verifyEmpty(testCase, COPS_RUNEX_OVERLAY_TEST);
end
verifyEqual(testCase, COPS_RUNEX_SUBJECT_TEST.calls, 2);
end

function ex = captureBeforeDisplay(testCase, varargin)
global COPS_RUNEX_OVERLAY_TEST
COPS_RUNEX_OVERLAY_TEST = [];
originalFolder = pwd;
cd(testCase.TestData.mockDir);
restoreFolder = onCleanup(@() cd(originalFolder)); %#ok<NASGU>
clear initDisplayx closeCoPsDisplayx getDefaultSettingsx inputdlg Datapixx Eyelink resetAdcBuffer
capturedError = [];
try
    evalc('runEx(varargin{:});');
catch err
    capturedError = err;
end
assertNotEmpty(testCase, capturedError, 'Display capture was not reached.');
assertEqual(testCase, capturedError.identifier, 'CoPsOverlayTest:DisplayCaptured', ...
    capturedError.message);
ex = COPS_RUNEX_OVERLAY_TEST;
assertNotEmpty(testCase, ex);
end

function verifyMouseOnly(testCase, ex)
verifyEqual(testCase, ex.setup.inputMode, 'mouse');
deps = ex.setup.dependencies;
verifyFalse(testCase, deps.pixOn);
verifyFalse(testCase, deps.eyeOn);
verifyFalse(testCase, deps.rewOn);
verifyFalse(testCase, deps.adcOn);
verifyFalse(testCase, deps.datapixxOn);
verifyFalse(testCase, deps.eyelinkOn);
end

function writeMock(folder, name, lines)
fid = fopen(fullfile(folder, [name '.m']), 'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', lines);
end
