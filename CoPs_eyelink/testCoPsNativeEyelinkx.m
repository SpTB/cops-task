function tests = testCoPsNativeEyelinkx
tests = functiontests(localfunctions);
end

function testNativeEyelinkDoesNotRequireDatapixx(testCase)
deps = resolveCoPsRunDependenciesx('t', false, true, false);
verifyEqual(testCase, deps.inputMode, 'eyelink');
verifyTrue(testCase, deps.eyelinkOn);
verifyFalse(testCase, deps.adcOn);
verifyFalse(testCase, deps.datapixxOn);
deps = resolveCoPsRunDependenciesx('t', false, true, false, 'analog');
verifyEqual(testCase, deps.inputMode, 'eye');
verifyTrue(testCase, deps.adcOn);
verifyTrue(testCase, deps.datapixxOn);
end

function testQueuedRowsAndBlinkValidity(testCase)
s = zeros(31, 3);
s(1, :) = [1000 1002 1004];
s(2, :) = 200
s([15 17 13 14 16 12], :) = ...
    [100 101 -32768; 200 201 202; 30 0 30; 300 301 302; 400 401 402; 40 40 40];
[v, t] = decodeCoPsEyelinkSamplesx(s, 200, -32768);
verifyEqual(testCase, t, [1 1.002 1.004], 'AbsTol', 1e-12);
verifyEqual(testCase, v(:,1),[100; 200; 30; 300; 400; 40]);
verifyTrue(testCase, all(isnan(v(1:3, 2:3)), 'all'));
verifyEqual(testCase, v(4:6, 3), [302; 402; 40]);
end

function testLostDataIsNotDecodedAsGaze(testCase)
s = zeros(31, 1);
s(2) = 63;
[v, t] = decodeCoPsEyelinkSamplesx(s, 200, -32768);
verifySize(testCase, v, [6 0]);
verifyEmpty(testCase, t);
end

function testNativeAnalysisBypassesAnalogCalibrationAndPreservesGaps(testCase)
testDir = fileparts(mfilename('fullpath'));
helperPath = fullfile(testDir, 'cops_analysis', 'helpers');
originalPath = path;
cleanup = onCleanup(@() path(originalPath)); %#ok<NASGU>
addpath(helperPath);
% omit eyeCal: native analysis must never use voltage gains
ex = struct('setup', struct('horEyeSign', -1));
T = struct('TrialStart', 50);
T.Eye = struct('source', 'eyelink', 'n', 3, ...
    'v', [100 110 NaN; 200 210 NaN; 30 30 NaN; ...
    300 NaN NaN; 400 NaN NaN; 40 NaN NaN], ...
    't', [10 10.002 10.010], 'trackerStart', 10, 'ptbStart', 50);
[x, y, t, ta, valid] = reconstructEyePx(ex, T, false);
verifyEqual(testCase, x(1:2), [200;110]);
verifyEqual(testCase, y(1:2), [300;210]);
verifyEqual(testCase, t, [0; .002; .010], 'AbsTol', 1e-10);
verifyEqual(testCase, ta, 50 + t, 'AbsTol', 1e-10);
verifyEqual(testCase, valid, [true; true; false]);
end
