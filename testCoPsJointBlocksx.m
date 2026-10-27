function tests = testCoPsJointBlocksx
% Hardware-free regression tests for the rewSwitches joint-block variant.
tests = functiontests(localfunctions);
end


function setup(testCase)
testCase.TestData.originalRng = rng;
rng(314159, 'twister');
end


function teardown(testCase)
rng(testCase.TestData.originalRng);
end


function testFixedBlocksDefineMainLength(testCase)
ex = localMinimalExperiment();
ex.exp.CoPs.ctl.numBlocks = 4;
ex.exp.CoPs.ctl.blockMeanTrials = 7;
ex.exp.CoPs.ctl.blockTransRange = 0;
ex = prepareCoPsJointBlocksx(ex);

verifyEqual(testCase, ex.exp.nreps, 28);
verifyEqual(testCase, ex.exp.CoPs.ctl.jointBlockLengths, [7 7 7 7]);
verifyEqual(testCase, ex.exp.CoPs.ctl.jointBlockStartMainTrials, [1 8 15 22]);
verifyEqual(testCase, ex.exp.CoPs.ctl.jointBlockEndMainTrials, [7 14 21 28]);
verifyTrue(testCase, ex.exp.CoPs.rew.gauss_center_free);
verifyEqual(testCase, ex.exp.CoPs.rew.gauss_center_coords, ...
    ex.exp.CoPs.ctl.jointBlockCenters(1, :));
end


function testJitteredBlocksStayWithinIntegerRange(testCase)
ex = localMinimalExperiment();
ex.exp.CoPs.ctl.numBlocks = 40;
ex.exp.CoPs.ctl.blockMeanTrials = 30;
ex.exp.CoPs.ctl.blockTransRange = 6;
ex = prepareCoPsJointBlocksx(ex);
ctl = ex.exp.CoPs.ctl;

verifySize(testCase, ctl.jointBlockLengths, [1 40]);
verifyGreaterThanOrEqual(testCase, ctl.jointBlockLengths, 24);
verifyLessThanOrEqual(testCase, ctl.jointBlockLengths, 36);
verifyEqual(testCase, mod(ctl.jointBlockLengths, 1), zeros(1, 40));
verifyGreaterThan(testCase, numel(unique(ctl.jointBlockLengths)), 1);
verifyEqual(testCase, ctl.jointBlockStartMainTrials(1), 1);
verifyEqual(testCase, ctl.jointBlockStartMainTrials(2:end), ...
    ctl.jointBlockEndMainTrials(1:end-1) + 1);
verifyEqual(testCase, ctl.jointBlockEndMainTrials - ...
    ctl.jointBlockStartMainTrials + 1, ctl.jointBlockLengths);
verifyEqual(testCase, ex.exp.nreps, sum(ctl.jointBlockLengths));
end


function testRewardCentersRespectEccentricityAndSwitchDistance(testCase)
ex = localMinimalExperiment();
ex.exp.CoPs.ctl.numBlocks = 20;
ex.exp.CoPs.ctr.min_peak_dist_deg = 2;
ex.exp.CoPs.ctr.max_peak_dist_deg = 8;
ex.exp.CoPs.ctl.rewPeakDistFromPrev = 5;
ex = prepareCoPsJointBlocksx(ex);
centers = ex.exp.CoPs.ctl.jointBlockCenters;
degreesPerNorm = localDegreesPerNorm(ex);
eccentricityDeg = sqrt(sum((centers - [0.5 0.5]).^2, 2)) * degreesPerNorm;
switchDistanceDeg = sqrt(sum(diff(centers, 1, 1).^2, 2)) * degreesPerNorm;

verifySize(testCase, centers, [20 2]);
verifyTrue(testCase, all(isfinite(centers(:))));
verifyGreaterThanOrEqual(testCase, centers, 0);
verifyLessThanOrEqual(testCase, centers, 1);
verifyGreaterThanOrEqual(testCase, eccentricityDeg, 2 - 1e-10);
verifyLessThanOrEqual(testCase, eccentricityDeg, 8 + 1e-10);
verifyGreaterThanOrEqual(testCase, switchDistanceDeg, 5 - 1e-10);
end


function testPreparationReproducibleFromRandomSeed(testCase)
ex = localMinimalExperiment();
ex.exp.CoPs.ctl.blockTransRange = 2;
rng(712, 'twister');
first = prepareCoPsJointBlocksx(ex);
rng(712, 'twister');
second = prepareCoPsJointBlocksx(ex);
verifyEqual(testCase, first, second);
end


function testDisabledAndMissingVariantAreNoOps(testCase)
ex = localMinimalExperiment();
ex.exp.CoPs.ctl.jointBlocks = false;
ex = rmfield(ex, 'setup');
verifyEqual(testCase, prepareCoPsJointBlocksx(ex), ex);

ex.exp.CoPs.ctl = rmfield(ex.exp.CoPs.ctl, 'jointBlocks');
verifyEqual(testCase, prepareCoPsJointBlocksx(ex), ex);
verifyEqual(testCase, prepareCoPsJointBlocksx(struct()), struct());
end


function testInvalidBlockSettingsRejected(testCase)
ex = localMinimalExperiment();
badSettings = { ...
    'numBlocks', 0, 'prepareCoPsJointBlocksx:BadPositiveInteger'; ...
    'numBlocks', 1.5, 'prepareCoPsJointBlocksx:BadPositiveInteger'; ...
    'blockMeanTrials', 0, 'prepareCoPsJointBlocksx:BadPositiveInteger'; ...
    'blockTransRange', -1, 'prepareCoPsJointBlocksx:BadNonnegativeInteger'; ...
    'blockTransRange', 0.5, 'prepareCoPsJointBlocksx:BadNonnegativeInteger'; ...
    'rewPeakDistFromPrev', -1, 'prepareCoPsJointBlocksx:BadNonnegativeScalar'; ...
    'numBlocks', NaN, 'prepareCoPsJointBlocksx:BadSetting'; ...
    'blockMeanTrials', [2 3], 'prepareCoPsJointBlocksx:BadSetting'};
for i = 1:size(badSettings, 1)
    bad = ex;
    bad.exp.CoPs.ctl.(badSettings{i, 1}) = badSettings{i, 2};
    verifyError(testCase, @() prepareCoPsJointBlocksx(bad), badSettings{i, 3});
end

bad = ex;
bad.exp.CoPs.ctl = rmfield(bad.exp.CoPs.ctl, 'numBlocks');
verifyError(testCase, @() prepareCoPsJointBlocksx(bad), ...
    'prepareCoPsJointBlocksx:BadSetting');
bad = ex;
bad.exp.CoPs.ctl.blockTransRange = bad.exp.CoPs.ctl.blockMeanTrials;
verifyError(testCase, @() prepareCoPsJointBlocksx(bad), ...
    'prepareCoPsJointBlocksx:BadBlockLengthRange');
end


function testImpossibleRewardSwitchDistanceRejected(testCase)
ex = localMinimalExperiment();
ex.exp.CoPs.ctl.numBlocks = 2;
ex.exp.CoPs.ctr.max_peak_dist_deg = 0;
ex.exp.CoPs.ctl.rewPeakDistFromPrev = 1;
verifyError(testCase, @() prepareCoPsJointBlocksx(ex), ...
    'prepareCoPsJointBlocksx:NoFeasibleCenter');
end


function testCentersAndBlockIndicesStayStableWithinMainBlocks(testCase)
ex = prepareCoPsJointBlocksx(localMinimalExperiment());
blockInfo = getCoPsTrialBlockInfox(ex);
ctl = ex.exp.CoPs.ctl;
expectedBlocks = repelem(1:ctl.numBlocks, ctl.jointBlockLengths);
originalReward = ex.exp.CoPs.rew;
originalReward.gauss_center_free = false;
originalReward.gauss_center_coords = [0.1 0.2];

for mainTrial = 1:ex.exp.nreps
    ex.j = blockInfo.mainIdx(mainTrial);
    [rew, blockIdx, blockTrialIdx] = applyCoPsJointBlockx(ex, originalReward);
    expectedBlock = expectedBlocks(mainTrial);
    verifyEqual(testCase, blockIdx, expectedBlock);
    verifyEqual(testCase, blockTrialIdx, ...
        mainTrial - ctl.jointBlockStartMainTrials(expectedBlock) + 1);
    verifyTrue(testCase, rew.gauss_center_free);
    verifyEqual(testCase, rew.gauss_center_coords, ...
        ctl.jointBlockCenters(expectedBlock, :));
    verifyEqual(testCase, rew.threshold, originalReward.threshold);
end
end


function testSpecialPhasesDoNotConsumeRewardBlocks(testCase)
for pursuitPriority = [true false]
    ex = localMinimalExperiment();
    ex.exp.CoPs.tut.nreps = 2;
    ex.exp.CoPs.pre.nreps = 3;
    ex.exp.CoPs.pur.nreps = 2;
    ex.exp.CoPs.pur.priority = pursuitPriority;
    ex = prepareCoPsJointBlocksx(ex);
    info = getCoPsTrialBlockInfox(ex);
    verifyEqual(testCase, getCoPsTotalRepsx(ex), ex.exp.nreps + 7);
    verifyEqual(testCase, info.mainIdx(1), 6 + 2 * double(pursuitPriority));

    for j = [info.tutorialIdx info.preIdx info.pursuitIdx]
        ex.j = j;
        [rew, idx, withinBlock] = applyCoPsJointBlockx(ex, ex.exp.CoPs.rew, info);
        verifyEqual(testCase, rew, ex.exp.CoPs.rew);
        verifyTrue(testCase, isnan(idx));
        verifyTrue(testCase, isnan(withinBlock));
    end

    ex.j = info.mainIdx(1);
    [rew, idx, withinBlock] = applyCoPsJointBlockx(ex, ex.exp.CoPs.rew, info);
    verifyEqual(testCase, idx, 1);
    verifyEqual(testCase, withinBlock, 1);
    verifyEqual(testCase, rew.gauss_center_coords, ex.exp.CoPs.ctl.jointBlockCenters(1, :));
end
end


function testDisabledRewardApplicationPreservesConfiguredCenter(testCase)
ex = localMinimalExperiment();
ex.exp.CoPs.ctl.jointBlocks = false;
ex.j = 1;
[rew, idx, withinBlock] = applyCoPsJointBlockx(ex, ex.exp.CoPs.rew);
verifyEqual(testCase, rew, ex.exp.CoPs.rew);
verifyTrue(testCase, isnan(idx));
verifyTrue(testCase, isnan(withinBlock));
end


function testUnpreparedMainTrialRejectedButSpecialPhaseAllowed(testCase)
ex = localMinimalExperiment();
ex.j = 1;
verifyError(testCase, @() applyCoPsJointBlockx(ex, ex.exp.CoPs.rew), ...
    'applyCoPsJointBlockx:JointBlocksNotPrepared');

ex.exp.CoPs.tut.nreps = 1;
[rew, idx, withinBlock] = applyCoPsJointBlockx(ex, ex.exp.CoPs.rew);
verifyEqual(testCase, rew, ex.exp.CoPs.rew);
verifyTrue(testCase, isnan(idx));
verifyTrue(testCase, isnan(withinBlock));
end


function testUncoveredMainTrialAndInvalidCenterRejected(testCase)
ex = prepareCoPsJointBlocksx(localMinimalExperiment());
ex.j = ex.exp.nreps;
ex.exp.CoPs.ctl.jointBlockEndMainTrials(end) = ex.exp.nreps - 1;
verifyError(testCase, @() applyCoPsJointBlockx(ex, ex.exp.CoPs.rew), ...
    'applyCoPsJointBlockx:BadJointBlockPlan');

ex = prepareCoPsJointBlocksx(localMinimalExperiment());
ex.j = 1;
ex.exp.CoPs.ctl.jointBlockCenters(1, 1) = NaN;
verifyError(testCase, @() applyCoPsJointBlockx(ex, ex.exp.CoPs.rew), ...
    'applyCoPsJointBlockx:BadJointBlockPlan');
end


function testPortableProfilePreservesRequestedTrialCount(testCase)
ex = setDefaultsCoPs(struct());
verifyTrue(testCase, ex.exp.CoPs.ctl.jointBlocks);
ex.setup = localSetup();
ex.setup.stereo = struct('Display', true, 'Mode', 8, 'Multisampling', 8);
ex.setup.fullscreen = false;
ex.setup.windowSizePx = [1280 720];
[ex, config] = configureCoPsTestRunx(ex, 4);
verifyFalse(testCase, ex.exp.CoPs.ctl.jointBlocks);
ex = prepareCoPsJointBlocksx(ex);
verifyEqual(testCase, ex.exp.nreps, 4);
verifyEqual(testCase, getCoPsTotalRepsx(ex), 4);
verifyEqual(testCase, config.nTrials, 4);
end


function ex = localMinimalExperiment()
ex = struct();
ex.setup = localSetup();
ex.exp.nreps = 9;
ex.exp.CoPs.ctl = struct('jointBlocks', true, 'numBlocks', 4, ...
    'blockMeanTrials', 5, 'blockTransRange', 0, 'rewPeakDistFromPrev', 5);
ex.exp.CoPs.ctr = struct('max_peak_dist_deg', 10);
ex.exp.CoPs.rew = struct('gauss_center_free', false, ...
    'gauss_center_coords', [0.5 0.5], 'threshold', 250);
ex.exp.CoPs.graph = struct('texture_dims', [320 320], 'size_mult', 3, 'imgs', []);
ex.exp.CoPs.dirs.all = fullfile(fileparts(mfilename('fullpath')), 'test_data', 'test_stim');
ex.exp.CoPs.pre.nreps = 0;
ex.exp.CoPs.tut.nreps = 0;
ex.exp.CoPs.pur = struct('nreps', 0, 'priority', true);
end


function setup = localSetup()
setup = struct('screenRect', [0 0 1920 1080], ...
    'monitorWidth', 47, 'viewingDistance', 58);
end


function degreesPerNorm = localDegreesPerNorm(ex)
setup = ex.setup;
degreesPerPixel = atan((setup.monitorWidth / 2) / setup.viewingDistance) * ...
    180 / pi / (setup.screenRect(3) / 2);
graph = ex.exp.CoPs.graph;
degreesPerNorm = (graph.texture_dims(1) * graph.size_mult - 1) * degreesPerPixel;
end
