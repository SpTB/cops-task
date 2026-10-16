function tests = testCoPsTestProfilex
% Non-display tests for the portable CoPs test profile.
tests = functiontests(localfunctions);
end


function testDependencyProfileDisablesHardware(testCase)
deps = resolveCoPsRunDependenciesx('test1', true, true, true);
verifyFalse(testCase, deps.pixOn);
verifyFalse(testCase, deps.eyeOn);
verifyFalse(testCase, deps.rewOn);
verifyFalse(testCase, deps.datapixxOn);
verifyFalse(testCase, deps.eyelinkOn);
verifyEqual(testCase, deps.inputMode, 'mouse');
end


function testNonTestDependencySwitchesRemainIndependent(testCase)
deps = resolveCoPsRunDependenciesx('t', true, false, true);
verifyTrue(testCase, deps.pixOn);
verifyFalse(testCase, deps.eyeOn);
verifyTrue(testCase, deps.rewOn);
verifyTrue(testCase, deps.datapixxOn);
verifyFalse(testCase, deps.eyelinkOn);
verifyEqual(testCase, deps.inputMode, 'mouse');
end


function testFixtureProfileDefaultsToOneTrial(testCase)
ex = localMinimalDefaults();
[ex, config] = configureCoPsTestRunx(ex);
verifyEqual(testCase, ex.exp.nreps, 1);
verifyEqual(testCase, getCoPsTotalRepsx(ex), 1);
verifyEqual(testCase, config.nTrials, 1);
verifyEqual(testCase, config.viewingDistanceCm, 100);
verifyEqual(testCase, config.monitorWidthCm, 50);
verifyFalse(testCase, config.fullscreen);
verifyEqual(testCase, config.windowSizePx, [1280 720]);
verifyEqual(testCase, ex.setup.inputMode, 'mouse');
verifyEqual(testCase, exist(config.eyeCalFile, 'file'), 2);
verifyEqual(testCase, exist(config.stimulusRoot, 'dir'), 7);
end


function testFixtureProfileAllowsMoreTrials(testCase)
ex = localMinimalDefaults();
[ex, config] = configureCoPsTestRunx(ex, 4);
verifyEqual(testCase, ex.exp.nreps, 4);
verifyEqual(testCase, getCoPsTotalRepsx(ex), 4);
verifyEqual(testCase, config.nTrials, 4);
end


function ex = localMinimalDefaults()
ex = setDefaultsCoPs(struct());
ex.setup = struct();
ex.setup.stereo = struct('Display', true, 'Mode', 8, 'Multisampling', 8);
ex.setup.viewingDistance = 100;
ex.setup.monitorWidth = 50;
ex.setup.fullscreen = false;
ex.setup.windowSizePx = [1280 720];
end
