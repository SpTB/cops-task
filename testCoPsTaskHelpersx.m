function tests = testCoPsTaskHelpersx
% Verify live diagnostics use only the task's retained local dependencies.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.TestData.originalPath = path;
testCase.TestData.root = fileparts(mfilename('fullpath'));
restoredefaultpath;
addpath(testCase.TestData.root, fullfile(testCase.TestData.root, 'helpers'), '-begin');
clearTaskHelpers;
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clearTaskHelpers;
end

function testHelpersResolveInsideTask(testCase)
names = {'gazeHeat','getGaussianCenterPx','mapTargetsByStep','px2deg', ...
    'reconstructEyePx','computeStepIndices','getfieldOrNaN','inferFs','safeDeltaField','clip'};
for index = 1:numel(names)
    expected = fullfile(testCase.TestData.root, 'helpers', [names{index} '.m']);
    verifyEqual(testCase, lower(which(names{index})), lower(expected));
end
end

function testRealGazeHeatRunsWithoutAnalysisTreeOrHardware(testCase)
ex.setup = struct('screenRect', [0 0 800 600], 'monitorWidth', 40, ...
    'viewingDistance', 60, 'horEyeSign', 1, 'adc', struct('Rate', 1000));
ex.fix.PCtr = [400 300];
ex.eyeCal = struct('RX0', 0, 'RY0', 0, 'RXGain', 1, 'RYGain', 1);
ex.exp.CoPs.graph = struct('texture_dims', [600 600], 'size_mult', 1);
ex.exp.CoPs.rew = struct('gauss_center_positions_norm', [.5 .5], ...
    'gauss_sigma', 30);
ex.exp.CoPs.timing = struct('waitHz', 100);
ex.exp.CoPs.analysis = struct('targetStimOnMode', 'matlab', ...
    'targetStepTimingMode', 'ideal', 'firstGoStep', 1);
target = struct('targ1', struct('pos_abs', [400 300]), ...
    'targ2', struct('pos_abs', [410 300]));
trial = struct('TrialStart', 10, 'TrialEnd', 10.019, ...
    'times', struct('stimOn', 10), 'nsteps', 3, ...
    'targetPositions', repmat(target, 1, 3), ...
    'Eye', struct('v', zeros(3, 20), 'n', 20));
ex.Trials = trial;
out = gazeHeat(ex, 1, struct('plot', false, 'useEyeTime', false));
verifyNumElements(testCase, out.xDeg, 20);
verifyEqual(testCase, out.xDeg, zeros(20, 1), 'AbsTol', 1e-12);
verifyEqual(testCase, sum(out.counts(:)), 20);
verifyEqual(testCase, sum(out.targetCounts(:)), 40);
verifyEqual(testCase, out.rewardPeakDeg, [0 0], 'AbsTol', .1);
verifyTrue(testCase, all(isfinite(out.density(:))));
end

function clearTaskHelpers
clear gazeHeat getGaussianCenterPx mapTargetsByStep px2deg ...
    reconstructEyePx computeStepIndices getfieldOrNaN inferFs safeDeltaField clip
end
