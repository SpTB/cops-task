function tests = testCoPsStimulusFieldx
% Physical angular field size and reward coordinates must survive resolution changes.
tests = functiontests(localfunctions);
end

function testHumanDefaultsUse26DegreeField(testCase)
evalc('ex = setDefaultsCoPs(struct());');
setup = geometry([1920 1080], 54, 65);
graph = resolveCoPsStimulusFieldx(ex.exp.CoPs.graph, setup);
verifyEqual(testCase, graph.fieldSizeDeg, 26);
verifyEqual(testCase, graph.fieldSizePx, 1067);
verifyEqual(testCase, graph.size_mult, 1067 / graph.texture_dim);
verifyEqual(testCase, graph.fieldSizeActualDeg, 26, 'AbsTol', 0.012);
end

function testHumanFieldKeepsAngleAcrossResolutions(testCase)
evalc('ex = setDefaultsCoPs(struct());');
widths = [1280 1920 2560 3840];
expectedSides = [711 1067 1423 2134];
for index = 1:numel(widths)
    width = widths(index);
    setup = geometry([width width * 9/16], 54, 65);
    graph = resolveCoPsStimulusFieldx(ex.exp.CoPs.graph, setup);
    verifyEqual(testCase, graph.fieldSizePx, expectedSides(index));
    sideCm = graph.fieldSizePx / width * 54;
    fullAngle = 2 * atand(sideCm / (2 * 65));
    % The only deviation allowed is rounding to the nearest display pixel.
    onePixelAngle = 2 * atand((54 / width) / (2 * 65));
    verifyEqual(testCase, fullAngle, ex.exp.CoPs.graph.fieldSizeDeg, ...
        'AbsTol', onePixelAngle / 2);
    verifyEqual(testCase, graph.radiusDeg, ex.exp.CoPs.graph.radiusDeg);
    verifyLessThanOrEqual(testCase, graph.fieldSizePx, min(setup.screenRect(3:4)));
end
end

function testTextureDimensionsAndRepeatedResolutionDoNotChangeField(testCase)
evalc('ex = setDefaultsCoPs(struct());');
setup = geometry([2560 1440], 54, 65);
for dimension = [192 288 320 512]
    graph = ex.exp.CoPs.graph;
    graph.texture_dims = [dimension dimension];
    graph = resolveCoPsStimulusFieldx(graph, setup);
    verifyEqual(testCase, graph.texture_dims * graph.size_mult, ...
        [1423 1423], 'AbsTol', 1e-10);
    verifyEqual(testCase, resolveCoPsStimulusFieldx(graph, setup), graph);
end
end

function testRewardPlanningUsesTheResolvedField(testCase)
evalc('ex = setDefaultsCoPs(struct());');
ex.setup = geometry([2560 1440], 54, 65);
ex.exp.CoPs.ctl.numBlocks = 2;
originalRng = rng;
cleanup = onCleanup(@() rng(originalRng)); %#ok<NASGU>
ex = prepareCoPsJointBlocksx(ex);
verifyEqual(testCase, ex.exp.CoPs.graph.fieldSizePx, 1423);
[~, info] = drawRewPeak(ex);
verifyEqual(testCase, info.gauss_dim, ex.exp.CoPs.graph.fieldSizePx);
verifyLessThanOrEqual(testCase, info.distance_deg, ex.exp.CoPs.ctr.max_peak_dist_deg);
% The resolved dimension must also be valid for flat and Gaussian reward maps.
verifySize(testCase, ones(info.gauss_dim), [1423 1423]);
verifySize(testCase, gauss_rew_land(info.gauss_dim, [712 712], 100), [1423 1423]);
end

function testOversizedFieldIsRejectedWithoutShrinking(testCase)
evalc('ex = setDefaultsCoPs(struct());');
setup = geometry([1920 1080], 30, 65);
verifyError(testCase, @() resolveCoPsStimulusFieldx(ex.exp.CoPs.graph, setup), ...
    'resolveCoPsStimulusFieldx:FieldDoesNotFit');
end

function testLegacyOrDisabledAngularFieldRetainsPixelSettings(testCase)
graph = struct('texture_dims', [320 320], 'size_mult', 1080/320);
verifyEqual(testCase, resolveCoPsStimulusFieldx(graph, struct()), graph);
graph.fieldSizeDeg = [];
verifyEqual(testCase, resolveCoPsStimulusFieldx(graph, struct()), graph);
end

function setup = geometry(sizePx, widthCm, distanceCm)
setup = struct('screenRect', [0 0 sizePx], ...
    'monitorWidth', widthCm, 'viewingDistance', distanceCm);
end
