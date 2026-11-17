function tests = testCoPsMiniStimulusBoundsx
% Exercise real stimulus positions in the full canvas used by mini previews.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(mfilename('fullpath'));
mockDir = tempname;
mkdir(mockDir);
testCase.TestData.mockDir = mockDir;
testCase.TestData.repoRoot = repoRoot;
testCase.TestData.originalPath = path;
writeMock(mockDir, 'Screen', [
    "function varargout = Screen(command, varargin)"
    "global COPS_MINI_STIMULUS_TEST"
    "global COPS_MINI_PIXELS_TEST"
    "switch lower(command)"
    "case 'maketexture'"
    "    COPS_MINI_STIMULUS_TEST = COPS_MINI_STIMULUS_TEST + 1;"
    "    COPS_MINI_PIXELS_TEST(end+1) = double(varargin{2}(1,end));"
    "    varargout = {COPS_MINI_STIMULUS_TEST};"
    "case 'preloadtextures'"
    "    varargout = {true, true(size(varargin{2}))};"
    "otherwise"
    "    error('CoPsMiniTest:UnexpectedScreenCall', 'Unexpected Screen command: %s', command);"
    "end"
    "end"]);
% Image clipping is independent of the geometry under test.
writeMock(mockDir, 'clip', [
    "function values = clip(values, lowerBound, upperBound)"
    "values = min(max(values, lowerBound), upperBound);"
    "end"]);
addpath(repoRoot, '-begin');
addpath(mockDir, '-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear Screen clip makeStimulusCoPsx
mockDir = testCase.TestData.mockDir;
assert(strcmp(fileparts(mockDir), fileparts(tempname)), ...
    'Refusing to remove a mock directory outside the temporary folder.');
rmdir(mockDir, 's');
clear global COPS_MINI_STIMULUS_TEST
clear global COPS_MINI_PIXELS_TEST
end

function setup(~)
global COPS_MINI_STIMULUS_TEST
global COPS_MINI_PIXELS_TEST
COPS_MINI_STIMULUS_TEST = 0;
COPS_MINI_PIXELS_TEST = [];
end

function testFullHdCanvasContainsSingleAndPairedTargets(testCase)
verifyStimulusBounds(testCase, [0 0 1920 1080]);
end

function testLargerCanvasContainsSingleAndPairedTargets(testCase)
verifyStimulusBounds(testCase, [0 0 2560 1440]);
end

function testPracticeHasConstantGrayAcrossGeneratedTextures(testCase)
global COPS_MINI_PIXELS_TEST
verifyStimulusBounds(testCase,[0 0 1920 1080],true);
verifyEqual(testCase,COPS_MINI_PIXELS_TEST,128*ones(size(COPS_MINI_PIXELS_TEST)));
end

function testSecondPracticeGeneratesChangingBackgroundTextures(testCase)
global COPS_MINI_PIXELS_TEST
verifyStimulusBounds(testCase,[0 0 1920 1080],2);
% The sampled corner is outside the target masks. Check the first target-count
% run alone so changes cannot come from switching between one and two targets.
verifyGreaterThan(testCase,numel(unique(COPS_MINI_PIXELS_TEST(1:5))),1);
end

function verifyStimulusBounds(testCase, logicalRect, practice)
if nargin < 3, practice = false; end
repoRoot = testCase.TestData.repoRoot;
stimulusDir = fullfile(repoRoot, 'test_data', 'test_stim', 'face_fn_0021_sample_03');
reference = load(fullfile(stimulusDir, 'noise1', 'full', 'full_0001.mat'), 'full_tp');
sourceDims = size(reference.full_tp);
evalc('ex = setDefaultsCoPs(struct());');
graph = ex.exp.CoPs.graph;
graph.texture_dims = sourceDims(1:2);
graph.texture_dim = sourceDims(1);
graph.size_mult = 1080 / sourceDims(1);
graph.radius = 15 * (sourceDims(1) / 192);
graph.background_noise_lvl = -1;
if practice == 1, graph.nullBackgroundGray = 128; end
graph.target_visibility = 1;
if practice == 2
    graph.background_noise_lvl = 1;
    graph.target_visibility = 0.35;
end
graph.scaleTextureOnDraw = true;
ctl = ex.exp.CoPs.ctl;
ctl.nsteps = 4;
ctl.circle_target_loc = false;
ctl.targetHiddenBoundsFrac = 0.2;
% Cover both normalized corners and the deliberately allowed partial hiding.
positionBound = 1 + (2 * graph.radius * ctl.targetHiddenBoundsFrac) / ...
    (min(sourceDims(1:2)) / 2 - graph.radius);
coordinates = [-1 1 -positionBound positionBound];
posT = struct('x1', coordinates, 'y1', coordinates, ...
    'x2', -coordinates, 'y2', -coordinates);
setup = struct('window', 10001, 'screenRect', logicalRect);

drawnSize = fliplr(graph.texture_dims) * graph.size_mult;
logicalSize = logicalRect(3:4) - logicalRect(1:2);
stimulusRect = [(logicalSize - drawnSize) / 2, (logicalSize + drawnSize) / 2];
verifyGreaterThanOrEqual(testCase, stimulusRect(1:2), [0 0]);
verifyLessThanOrEqual(testCase, stimulusRect(3:4), logicalSize);

for targetCount = 1:2
    ctl.target_num = targetCount;
    originalFolder = pwd;
    cd(testCase.TestData.mockDir);
    restoreFolder = onCleanup(@() cd(originalFolder)); %#ok<NASGU>
    clear Screen clip
    [textures, positions, timing] = makeStimulusCoPsx( ...
        setup, ctl, stimulusDir, posT, graph, 1);
    clear restoreFolder
    verifyClass(testCase, textures, 'double');
    verifyNumElements(testCase, textures, ctl.nsteps + 1);
    verifyEqual(testCase, timing.nTextures, ctl.nsteps + 1);
    expectedGray = round(min(254, max(1, mean(double(reference.full_tp(:)), 'omitnan'))));
    if practice == 1, expectedGray = 128; end
    verifyEqual(testCase, positions(1).nullBackgroundGray, expectedGray);
    for target = 1:targetCount
        targetName = sprintf('targ%d', target);
        centers = zeros(numel(positions), 2);
        for step = 1:numel(positions)
            centers(step, :) = positions(step).(targetName).pos_abs;
        end
        verifyGreaterThanOrEqual(testCase, centers, zeros(size(centers)));
        verifyLessThanOrEqual(testCase, centers, repmat(logicalSize, size(centers, 1), 1));
        % The complete full-display canvas fits the 960x540 physical preview.
        previewSize = [960 540];
        scale = min(previewSize ./ logicalSize);
        offset = (previewSize - logicalSize * scale) / 2;
        previewCenters = centers * scale + offset;
        verifyGreaterThanOrEqual(testCase, previewCenters, zeros(size(previewCenters)));
        verifyLessThanOrEqual(testCase, previewCenters, ...
            repmat(previewSize, size(previewCenters, 1), 1));
    end
end
end

function writeMock(folder, name, lines)
fid = fopen(fullfile(folder, [name '.m']), 'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', lines);
end
