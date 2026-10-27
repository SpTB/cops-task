function [ex, testConfig] = configureCoPsTestRunx(ex, nTrials)
% Apply the portable, Psychtoolbox-only CoPs test configuration.

arguments
    ex struct
    nTrials (1,1) double {mustBeInteger, mustBePositive} = 1
end

repoRoot = fileparts(mfilename('fullpath'));
testDataRoot = fullfile(repoRoot, 'test_data');
eyeCalFile = fullfile(testDataRoot, 'eyecal_test.mat');
stimulusRoot = fullfile(testDataRoot, 'test_stim');
outputRoot = fullfile(testDataRoot, 'output');

if exist(eyeCalFile, 'file') ~= 2
    error('configureCoPsTestRunx:MissingEyeCalibration', ...
        'Test eye-calibration file does not exist: %s', eyeCalFile);
end
if exist(stimulusRoot, 'dir') ~= 7
    error('configureCoPsTestRunx:MissingStimuli', ...
        'Test stimulus folder does not exist: %s', stimulusRoot);
end

loaded = load(eyeCalFile);
if isfield(loaded, 'eyeCal')
    eyeCal = loaded.eyeCal;
elseif isfield(loaded, 'ex') && isstruct(loaded.ex) && isfield(loaded.ex, 'eyeCal')
    eyeCal = loaded.ex.eyeCal;
else
    error('configureCoPsTestRunx:MissingEyeCalField', ...
        'Expected eyeCal or ex.eyeCal in %s.', eyeCalFile);
end

requiredEyeCalFields = {'RX0','RY0','RXGain','RYGain','LXPos','Delta'};
missingFields = requiredEyeCalFields(~isfield(eyeCal, requiredEyeCalFields));
if ~isempty(missingFields)
    error('configureCoPsTestRunx:IncompleteEyeCalibration', ...
        'Test calibration is missing fields: %s', strjoin(missingFields, ', '));
end

if exist(outputRoot, 'dir') ~= 7
    mkdir(outputRoot);
end
testOutputRoot = fullfile(outputRoot, 'test');
if exist(testOutputRoot, 'dir') ~= 7
    mkdir(testOutputRoot);
end

ex.eyeCal = eyeCal;
ex.setup.testMode = true;
ex.setup.inputMode = 'mouse';
ex.setup.eyeTracker = 'none';
ex.setup.stereo.Display = false;
ex.setup.stereo.Mode = NaN;
ex.setup.stereo.Multisampling = 0;
ex.setup.dirRoot = outputRoot;

ex.exp.nreps = nTrials;
ex.exp.CoPs.ctl.jointBlocks = false; % keep testTrials independent of session block defaults
ex.finish = nTrials;
ex.exp.CoPs.pre.nreps = 0;
ex.exp.CoPs.tut.nreps = 0;
ex.exp.CoPs.pur.nreps = 0;
ex.exp.CoPs.dirs.all = localTrailingSeparator(stimulusRoot);
ex.exp.CoPs.graph.texture_root = testDataRoot;
ex.exp.CoPs.graph.texture_folder = 'test_stim';
ex.exp.CoPs.graph.texture_folder_resolved = ex.exp.CoPs.dirs.all;
ex.exp.CoPs.graph.background_noise_lvl = 1;
ex.exp.CoPs.graph.target_visibility = 1;
ex.exp.CoPs.graph.shuffleStimulusSchedule = false;
ex.exp.CoPs.ctl.coherence = 1;

testConfig = struct( ...
    'profile', 'test1', ...
    'nTrials', nTrials, ...
    'viewingDistanceCm', ex.setup.viewingDistance, ...
    'monitorWidthCm', ex.setup.monitorWidth, ...
    'fullscreen', ex.setup.fullscreen, ...
    'windowSizePx', ex.setup.windowSizePx, ...
    'eyeCalFile', eyeCalFile, ...
    'stimulusRoot', stimulusRoot, ...
    'outputRoot', outputRoot, ...
    'inputMode', 'mouse');
ex.setup.testConfig = testConfig;
end


function pathText = localTrailingSeparator(pathText)
pathText = char(pathText);
if isempty(pathText) || pathText(end) ~= filesep
    pathText = [pathText filesep];
end
end
