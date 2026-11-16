function tests = testCoPsPreviewResizex
% Exercise native preview resizing without creating onscreen windows.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
mockDir = tempname;
mkdir(mockDir);
testCase.TestData.mockDir = mockDir;
testCase.TestData.originalPath = path;
writeMock(mockDir, 'Screen', [
    "function varargout = Screen(command, varargin)"
    "global COPS_PREVIEW_RESIZE_TEST"
    "COPS_PREVIEW_RESIZE_TEST.calls{end+1} = [{command} varargin];"
    "switch lower(command)"
    "case 'windowsize'"
    "    varargout = {COPS_PREVIEW_RESIZE_TEST.size(1), COPS_PREVIEW_RESIZE_TEST.size(2)};"
    "case 'panelfitter'"
    "    if numel(varargin) > 1"
    "        COPS_PREVIEW_RESIZE_TEST.parameters = varargin{2};"
    "        COPS_PREVIEW_RESIZE_TEST.updates = COPS_PREVIEW_RESIZE_TEST.updates + 1;"
    "    else, varargout = {COPS_PREVIEW_RESIZE_TEST.parameters}; end"
    "otherwise, error('CoPsResizeTest:UnexpectedScreenCall', 'Unexpected Screen command.');"
    "end"
    "end"]);
addpath(fileparts(mfilename('fullpath')), '-begin');
addpath(mockDir, '-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear Screen
mockDir = testCase.TestData.mockDir;
assert(strcmp(fileparts(mockDir), fileparts(tempname)), ...
    'Refusing to remove a mock directory outside the temporary folder.');
rmdir(mockDir, 's');
clear global COPS_PREVIEW_RESIZE_TEST
end

function setup(~)
global COPS_PREVIEW_RESIZE_TEST
COPS_PREVIEW_RESIZE_TEST = struct('size', [960 540], 'parameters', ...
    [0 0 1920 1080 0 0 960 540 0 25 30 999], 'calls', {{}}, 'updates', 0);
end

function testUnchangedPreviewDoesNotResetFitter(testCase)
global COPS_PREVIEW_RESIZE_TEST
changed = refreshPreview(testCase, fixture());
verifyFalse(testCase, changed);
verifyEqual(testCase, COPS_PREVIEW_RESIZE_TEST.updates, 0);
verifyEqual(testCase, COPS_PREVIEW_RESIZE_TEST.calls{1}, {'WindowSize', 101, 1});
end

function testSmallerWindowFitsTheCompleteLogicalDisplay(testCase)
global COPS_PREVIEW_RESIZE_TEST
COPS_PREVIEW_RESIZE_TEST.size = [480 270];
changed = refreshPreview(testCase, fixture());
verifyTrue(testCase, changed);
verifyEqual(testCase, COPS_PREVIEW_RESIZE_TEST.parameters, ...
    [0 0 1920 1080 0 0 480 270 0 25 30 999]);
verifyEqual(testCase, COPS_PREVIEW_RESIZE_TEST.updates, 1);
end

function testNewAspectRatioCentersFullCanvasAndPreservesExtraParameters(testCase)
global COPS_PREVIEW_RESIZE_TEST
COPS_PREVIEW_RESIZE_TEST.size = [800 600];
changed = refreshPreview(testCase, fixture());
verifyTrue(testCase, changed);
verifyEqual(testCase, COPS_PREVIEW_RESIZE_TEST.parameters, ...
    [0 0 1920 1080 0 75 800 525 0 25 30 999]);
end

function testPortraitWindowCentersFullDisplay(testCase)
global COPS_PREVIEW_RESIZE_TEST
COPS_PREVIEW_RESIZE_TEST.size = [400 800];
refreshPreview(testCase, fixture());
p = COPS_PREVIEW_RESIZE_TEST.parameters;
verifyEqual(testCase, p(1:8), [0 0 1920 1080 0 288 400 513]);
verifyGreaterThanOrEqual(testCase, p(5:6), [0 0]);
verifyLessThanOrEqual(testCase, p(7:8), [400 800]);
end

function testTinyPositiveWindowKeepsNonzeroDestination(testCase)
global COPS_PREVIEW_RESIZE_TEST
COPS_PREVIEW_RESIZE_TEST.size = [1 1];
refreshPreview(testCase, fixture());
verifyEqual(testCase, COPS_PREVIEW_RESIZE_TEST.parameters(5:8), [0 0 1 1]);
end

function testUpdatedFitterMapsMouseCenterAndBordersToLogicalCanvas(testCase)
global COPS_PREVIEW_RESIZE_TEST
COPS_PREVIEW_RESIZE_TEST.size = [800 600];
refreshPreview(testCase, fixture());
p = COPS_PREVIEW_RESIZE_TEST.parameters;
physical = [400 300; 0 75; 800 525; 400 20];
logical = (physical - p(5:6)) ./ (p(7:8) - p(5:6)) .* ...
    (p(3:4) - p(1:2)) + p(1:2);
verifyEqual(testCase, logical(1:3, :), [960 540; 0 0; 1920 1080], 'AbsTol', 1e-10);
verifyLessThan(testCase, logical(4, 2), 0);
end

function testMinimizedWindowLeavesFitterIntact(testCase)
global COPS_PREVIEW_RESIZE_TEST
before = COPS_PREVIEW_RESIZE_TEST.parameters;
for size = {[0 0], [0 540], [960 0]}
    COPS_PREVIEW_RESIZE_TEST.size = size{1};
    COPS_PREVIEW_RESIZE_TEST.calls = {};
    verifyFalse(testCase, refreshPreview(testCase, fixture()));
    verifyEqual(testCase, COPS_PREVIEW_RESIZE_TEST.parameters, before);
    verifyNumElements(testCase, COPS_PREVIEW_RESIZE_TEST.calls, 1);
end
end

function testFullscreenAndOtherWindowsDoNotQueryScreen(testCase)
global COPS_PREVIEW_RESIZE_TEST
options = fixture();
for guiWindow = [false true]
    options.guiWindow = guiWindow;
    options.panelFitterOn = ~guiWindow;
    verifyFalse(testCase, refreshPreview(testCase, options));
end
verifyFalse(testCase, refreshPreview(testCase, rmfield(options, 'guiWindow')));
verifyEmpty(testCase, COPS_PREVIEW_RESIZE_TEST.calls);
end

function changed = refreshPreview(testCase, options)
originalFolder = pwd;
cd(testCase.TestData.mockDir);
restoreFolder = onCleanup(@() cd(originalFolder)); %#ok<NASGU>
clear Screen
changed = refreshCoPsPreviewWindowx(options);
end

function options = fixture()
options = struct('guiWindow', true, 'panelFitterOn', true, ...
    'window', 101, 'screenRect', [0 0 1920 1080]);
end

function writeMock(folder, name, lines)
fid = fopen(fullfile(folder, [name '.m']), 'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', lines);
end
