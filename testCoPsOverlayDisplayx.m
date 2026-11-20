function tests = testCoPsOverlayDisplayx
% Exercise display routing without opening windows or touching hardware.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
mockDir = tempname;
mkdir(mockDir);
testCase.TestData.mockDir = mockDir;
writeMock(mockDir, 'Screen', [
    "function varargout = Screen(varargin)"
    "global COPS_DISPLAY_TEST"
    "COPS_DISPLAY_TEST.screenCalls{end+1} = varargin;"
    "switch lower(varargin{1})"
    "case 'screens', varargout = {COPS_DISPLAY_TEST.screens};"
    "case 'rect'"
    "    if varargin{2} <= 1"
    "        rect = COPS_DISPLAY_TEST.rects{varargin{2}+1};"
    "    elseif varargin{2} == 101"
    "        rect = COPS_DISPLAY_TEST.stimulusRect;"
    "    else, rect = [0 0 960 540]; end"
    "    varargout = {rect};"
    "case 'windowsize', varargout = {COPS_DISPLAY_TEST.physicalSize(1), COPS_DISPLAY_TEST.physicalSize(2)};"
    "case 'panelfitter'"
    "    if numel(varargin) > 2, COPS_DISPLAY_TEST.fitterParameters = varargin{3};"
    "    else, varargout = {COPS_DISPLAY_TEST.fitterParameters}; end"
    "case 'openwindow'"
    "    COPS_DISPLAY_TEST.openVRAM = COPS_DISPLAY_TEST.ConserveVRAM;"
    "    COPS_DISPLAY_TEST.openSkip = COPS_DISPLAY_TEST.SkipSyncTests;"
    "    varargout = {102, [0 0 960 540]};"
    "case 'openoffscreenwindow', varargout = {201};"
    "case 'preference'"
    "    key = varargin{2};"
    "    if ismember(key, {'ConserveVRAM','SkipSyncTests'})"
    "        old = COPS_DISPLAY_TEST.(key);"
    "        if numel(varargin)>2, COPS_DISPLAY_TEST.(key) = varargin{3}; end"
    "        varargout = {old};"
    "    end"
    "otherwise, varargout = cell(1,nargout);"
    "end"
    "end"]);
writeMock(mockDir, 'PsychImaging', [
    "function varargout = PsychImaging(varargin)"
    "global COPS_DISPLAY_TEST"
    "COPS_DISPLAY_TEST.imagingCalls{end+1} = varargin;"
    "switch lower(varargin{1})"
    "case 'prepareconfiguration', COPS_DISPLAY_TEST.panelFitterSize = [];"
    "case 'addtask'"
    "    if strcmp(varargin{3}, 'UsePanelFitter'), COPS_DISPLAY_TEST.panelFitterSize = varargin{4}; end"
    "case 'openwindow'"
    "    rect = [];"
    "    if numel(varargin) >= 4, rect = varargin{4}; end"
    "    if isempty(rect), rect = COPS_DISPLAY_TEST.rects{varargin{2}+1}; end"
    "    windowSize = rect(3:4)-rect(1:2);"
    "    physicalSize = windowSize;"
    "    if ~isempty(COPS_DISPLAY_TEST.panelFitterSize), windowSize = COPS_DISPLAY_TEST.panelFitterSize; end"
    "    COPS_DISPLAY_TEST.stimulusRect = [0 0 windowSize];"
    "    COPS_DISPLAY_TEST.physicalSize = physicalSize;"
    "    COPS_DISPLAY_TEST.fitterParameters = [0 0 windowSize 0 0 physicalSize 0 0 0];"
    "    varargout = {101, [0 0 physicalSize]};"
    "otherwise, varargout = cell(1,nargout);"
    "end"
    "end"]);
writeMock(mockDir, 'CenterRect', [
    "function rect = CenterRect(rect, bounds)"
    "offset = (bounds(1:2) + bounds(3:4) - rect(1:2) - rect(3:4)) / 2;"
    "rect = rect + [offset offset];"
    "end"]);
writeMock(mockDir, 'FrameRate', ["function r = FrameRate(varargin)"; "r = 120;"; "end"]);
writeMock(mockDir, 'Datapixx', [
    "function r = Datapixx(varargin)"
    "global COPS_DISPLAY_TEST"
    "COPS_DISPLAY_TEST.datapixxCalls{end+1} = varargin;"
    "r = 1;"
    "end"]);
writeMock(mockDir, 'GL_SRC_ALPHA', ["function r = GL_SRC_ALPHA"; "r = 770;"; "end"]);
writeMock(mockDir, 'GL_ONE_MINUS_SRC_ALPHA', ["function r = GL_ONE_MINUS_SRC_ALPHA"; "r = 771;"; "end"]);
writeMock(mockDir, 'GetSecs', ["function r = GetSecs"; "global COPS_DISPLAY_TEST"; "r = COPS_DISPLAY_TEST.now;"; "end"]);
writeMock(mockDir, 'GetMouse', [
    "function [x, y] = GetMouse(window)"
    "global COPS_DISPLAY_TEST"
    "COPS_DISPLAY_TEST.mouseWindow = window;"
    "x = COPS_DISPLAY_TEST.mousePosition(1);"
    "y = COPS_DISPLAY_TEST.mousePosition(2);"
    "end"]);
writeMock(mockDir, 'RemapMouse', [
    "function [x, y] = RemapMouse(varargin)"
    "global COPS_DISPLAY_TEST"
    "COPS_DISPLAY_TEST.remapCalls{end+1} = varargin;"
    "point = COPS_DISPLAY_TEST.remappedMousePosition;"
    "if isempty(point), point = [varargin{3} varargin{4}]; end"
    "x = point(1); y = point(2);"
    "end"]);
addpath(mockDir, '-begin');
end

function teardownOnce(testCase)
rmpath(testCase.TestData.mockDir);
rmdir(testCase.TestData.mockDir, 's');
clear global COPS_DISPLAY_TEST
end

function setup(~)
global COPS_DISPLAY_TEST
COPS_DISPLAY_TEST = struct('screens', [0 1], ...
    'rects', {{[0 0 1920 1200], [0 0 2560 1440]}}, ...
    'screenCalls', {{}}, 'imagingCalls', {{}}, 'datapixxCalls', {{}}, ...
    'panelFitterSize', [], 'remapCalls', {{}}, 'remappedMousePosition', [], ...
    'ConserveVRAM', 64, 'SkipSyncTests', 0, 'now', 1);
clear presentCoPsOverlayx
end

function testDesktopWindowAndAspectRatio(testCase)
global COPS_DISPLAY_TEST
ex = configureCoPsOverlayDisplayx(fixture());
verifyEqual(testCase, ex.setup.overlayScreen, 0);
verifyEqual(testCase, ex.setup.overlayWindowRect, [480 330 1440 870]);
verifyEmpty(testCase, COPS_DISPLAY_TEST.imagingCalls);
end

function testWindowStaysInsideDesktop(testCase)
global COPS_DISPLAY_TEST
COPS_DISPLAY_TEST.rects{1} = [0 0 320 200];
ex = configureCoPsOverlayDisplayx(fixture());
rect = ex.setup.overlayWindowRect;
verifyGreaterThan(testCase, rect(1:2), [0 0]);
verifyLessThan(testCase, rect(3:4), [320 200]);
verifyEqual(testCase, rect(3:4) - rect(1:2), [256 144]);
end

function testExplicitScreenAndSize(testCase)
ex = fixture();
ex.setup.overlayScreen = 0;
ex.setup.overlayWindowSizePx = [800 800];
ex = configureCoPsOverlayDisplayx(ex);
rect = ex.setup.overlayWindowRect;
verifyEqual(testCase, rect(3:4) - rect(1:2), [800 450]);
end

function testRejectsStimulusScreenAndMissingMonitor(testCase)
global COPS_DISPLAY_TEST
ex = fixture();
ex.setup.overlayScreen = 1;
verifyError(testCase, @() configureCoPsOverlayDisplayx(ex), ...
    'configureCoPsOverlayDisplayx:InvalidScreen');
ex.setup.overlayScreen = 2;
verifyError(testCase, @() configureCoPsOverlayDisplayx(ex), ...
    'configureCoPsOverlayDisplayx:InvalidScreen');
COPS_DISPLAY_TEST.screens = 1;
ex.setup.overlayScreen = [];
verifyError(testCase, @() configureCoPsOverlayDisplayx(ex), ...
    'configureCoPsOverlayDisplayx:NoSeparateScreen');
end

function testBothInitializersUseSeparateOverlay(testCase)
global COPS_DISPLAY_TEST
for initializer = {@initDisplayx, @(ex) initDisplayxx(ex, true)}
    COPS_DISPLAY_TEST.imagingCalls = {};
    ex = initializer{1}(fixture());
    verifyEqual(testCase, ex.setup.screenNum, 1);
    verifyEqual(testCase, ex.setup.window, 101);
    verifyEqual(testCase, ex.synch.Pos, [2550;1430]); % bottom-right, 20 px patch
    verifyEqual(testCase, ex.setup.overlay, 201);
    verifyTrue(testCase, ex.setup.overlayIsSeparate);
    verifyEqual(testCase, ex.setup.overlayWindow, 102);
    calls = COPS_DISPLAY_TEST.imagingCalls;
    opens = calls(cellfun(@(c) strcmp(c{1}, 'OpenWindow'), calls));
    verifyEqual(testCase, opens{1}{2}, 1);
    verifyEmpty(testCase, opens{1}{4}); % Main stimulus window stays fullscreen.
end
calls = COPS_DISPLAY_TEST.screenCalls;
verifyTrue(testCase, any(cellfun(@(c) isequal(c, {'Preference', 'SkipSyncTests', 0}), calls)));
end

function testOverlayOffDoesNotOpenDesktopWindow(testCase)
global COPS_DISPLAY_TEST
ex = fixture();
ex.setup.showExperimenterOverlay = false;
ex = initDisplayx(ex);
verifyEmpty(testCase, ex.setup.overlay);
calls = COPS_DISPLAY_TEST.imagingCalls;
verifyFalse(testCase, any(cellfun(@(c) strcmp(c{1}, 'AddTask'), calls)));
end

function testPortableWindowIsCenteredOnSingleDisplay(testCase)
global COPS_DISPLAY_TEST
COPS_DISPLAY_TEST.screens = 0;
ex = initDisplayx(portableFixture());
calls = COPS_DISPLAY_TEST.imagingCalls;
opens = calls(cellfun(@(c) strcmp(c{1}, 'OpenWindow'), calls));
verifyEqual(testCase, opens{1}{2}, 0);
verifyEqual(testCase, opens{1}{4}, [320 240 1600 960]);
verifyEqual(testCase, ex.setup.windowRectPx, opens{1}{4});
verifyTrue(testCase, ex.setup.panelFitterOn);
verifyTrue(testCase, ex.setup.guiWindow);
verifyEqual(testCase, opens{1}{10}, kPsychGUIWindow);
verifyEqual(testCase, ex.setup.virtualDisplaySizePx, [1920 1200]);
verifyEqual(testCase, ex.setup.screenRect, [0 0 1920 1200]);
verifyEqual(testCase, ex.fix.PCtr, [960 600]);
verifyTrue(testCase, any(cellfun(@(c) isequal(c, ...
    {'AddTask', 'General', 'UsePanelFitter', [1920 1200], 'Aspect'}), calls)));
verifyEmpty(testCase, ex.setup.overlay);
verifyEmpty(testCase, COPS_DISPLAY_TEST.datapixxCalls);
end

function testPortableWindowIsClampedToDisplay(testCase)
global COPS_DISPLAY_TEST
COPS_DISPLAY_TEST.screens = 0;
COPS_DISPLAY_TEST.rects{1} = [100 50 1700 950];
ex = portableFixture();
ex.setup.windowSizePx = [2560 1440];
ex = initDisplayx(ex);
calls = COPS_DISPLAY_TEST.imagingCalls;
opens = calls(cellfun(@(c) strcmp(c{1}, 'OpenWindow'), calls));
verifyEqual(testCase, opens{1}{4}, [260 140 1540 860]);
verifyEqual(testCase, ex.setup.windowRectPx, opens{1}{4});
verifyEqual(testCase, ex.setup.screenRect, [0 0 1600 900]);
end

function testPortableLowResolutionDisplayFitsFullStimulus(testCase)
global COPS_DISPLAY_TEST
COPS_DISPLAY_TEST.screens = 0;
COPS_DISPLAY_TEST.rects{1} = [0 0 1280 720];
ex = portableFixture();
ex.exp.CoPs.graph.texture_dims = [320 320];
ex.exp.CoPs.graph.size_mult = 1080 / 320;
ex = initDisplayx(ex);
verifyEqual(testCase, ex.setup.virtualDisplaySizePx, [1920 1080]);
verifyEqual(testCase, ex.setup.screenRect, [0 0 1920 1080]);
verifyEqual(testCase, ex.setup.windowRectPx(3:4) - ex.setup.windowRectPx(1:2), [1024 576]);
stimulusSize = ex.exp.CoPs.graph.texture_dims * ex.exp.CoPs.graph.size_mult;
verifyGreaterThanOrEqual(testCase, ex.setup.screenRect(3:4), stimulusSize);
calls = COPS_DISPLAY_TEST.imagingCalls;
verifyTrue(testCase, any(cellfun(@(c) isequal(c, ...
    {'AddTask', 'General', 'UsePanelFitter', [1920 1080], 'Aspect'}), calls)));
end

function testMiniWindowContainsFullTaskCanvas(testCase)
global COPS_DISPLAY_TEST
COPS_DISPLAY_TEST.screens = 0;
COPS_DISPLAY_TEST.rects{1} = [0 0 1920 1080];
ex = portableFixture();
ex.setup.windowSizePx = [960 540];
ex.exp.CoPs.graph.texture_dims = [320 320];
ex.exp.CoPs.graph.size_mult = 1080 / 320;
ex = initDisplayx(ex);
verifyEqual(testCase, ex.setup.windowRectPx, [480 270 1440 810]);
verifyEqual(testCase, ex.setup.screenRect, [0 0 1920 1080]);
verifyEqual(testCase, ex.setup.virtualDisplaySizePx, [1920 1080]);
verifyTrue(testCase, ex.setup.panelFitterOn);
end

function testPortableFullscreenUsesWholeDisplay(testCase)
global COPS_DISPLAY_TEST
ex = portableFixture();
ex.setup.fullscreen = true;
ex = initDisplayx(ex);
calls = COPS_DISPLAY_TEST.imagingCalls;
opens = calls(cellfun(@(c) strcmp(c{1}, 'OpenWindow'), calls));
verifyEmpty(testCase, opens{1}{4});
verifyEqual(testCase, ex.setup.screenRect, [0 0 2560 1440]);
verifyFalse(testCase, ex.setup.panelFitterOn);
verifyFalse(testCase, ex.setup.guiWindow);
verifyLessThan(testCase, numel(opens{1}), 10);
verifyEmpty(testCase, ex.setup.virtualDisplaySizePx);
verifyFalse(testCase, any(cellfun(@(c) strcmp(c{1}, 'AddTask'), calls)));
end

function testWindowedMouseMapsToFullDisplayCoordinates(testCase)
global COPS_DISPLAY_TEST
COPS_DISPLAY_TEST.screens = 0;
ex = initDisplayx(portableFixture());
ex.fix.WinW = 20;
ex.fix.WinH = 20;
COPS_DISPLAY_TEST.mousePosition = [640 360];
COPS_DISPLAY_TEST.remappedMousePosition = [960 600];
[passEye, ~, lastEyePos, sample] = sampleCoPsInputx( ...
    'mouse', struct(), ex, false, false, [NaN NaN]);
verifyEqual(testCase, COPS_DISPLAY_TEST.mouseWindow, ex.setup.window);
verifyEqual(testCase, COPS_DISPLAY_TEST.remapCalls, ...
    {{ex.setup.window, 'AllViews', 640, 360}});
verifyTrue(testCase, passEye);
verifyTrue(testCase, sample.inBounds);
verifyEqual(testCase, sample.position, ex.fix.PCtr);
verifyEqual(testCase, lastEyePos, [960 600]);
verifyEqual(testCase, sample.pointerPosition, sample.position);
end

function testWindowedLetterboxMousePositionIsOutOfBounds(testCase)
global COPS_DISPLAY_TEST
ex = portableFixture();
ex.setup.windowSizePx = [800 600];
ex = initDisplayx(ex);
ex.fix.WinW = 20;
ex.fix.WinH = 20;
COPS_DISPLAY_TEST.mousePosition = [400 20];
COPS_DISPLAY_TEST.remappedMousePosition = [1280 -176];
[passEye, ~, lastEyePos, sample] = sampleCoPsInputx( ...
    'mouse', struct(), ex, false, false, [NaN NaN]);
verifyFalse(testCase, passEye);
verifyFalse(testCase, sample.inBounds);
verifyEqual(testCase, lastEyePos, [1280 -176]);
verifyEqual(testCase, COPS_DISPLAY_TEST.remapCalls, ...
    {{ex.setup.window, 'AllViews', 400, 20}});
end

function testFullscreenMouseDoesNotRemapCoordinates(testCase)
global COPS_DISPLAY_TEST
ex = portableFixture();
ex.setup.fullscreen = true;
ex = initDisplayx(ex);
ex.fix.WinW = 20;
ex.fix.WinH = 20;
COPS_DISPLAY_TEST.mousePosition = [1280 720];
COPS_DISPLAY_TEST.remappedMousePosition = [-100 -100];
[passEye, ~, lastEyePos, sample] = sampleCoPsInputx( ...
    'mouse', struct(), ex, false, false, [NaN NaN]);
verifyTrue(testCase, passEye);
verifyTrue(testCase, sample.inBounds);
verifyEqual(testCase, lastEyePos, [1280 720]);
verifyEmpty(testCase, COPS_DISPLAY_TEST.remapCalls);
end

function testWindowedOverlayUsesFullDisplayAspectRatio(testCase)
global COPS_DISPLAY_TEST
ex = portableFixture();
ex.setup.windowSizePx = [800 600];
ex.setup.showExperimenterOverlay = true;
ex.setup.overlayScreen = 0;
ex = initDisplayx(ex);
verifyEqual(testCase, ex.setup.windowRectPx(3:4) - ex.setup.windowRectPx(1:2), [800 600]);
verifyEqual(testCase, ex.setup.screenRect, [0 0 2560 1440]);
verifyEqual(testCase, ex.setup.overlayWindowRect, [480 330 1440 870]);
verifyTrue(testCase, ex.setup.overlayIsSeparate);
calls = COPS_DISPLAY_TEST.screenCalls;
opens = calls(cellfun(@(c) strcmp(c{1}, 'OpenWindow'), calls));
verifyEqual(testCase, opens{1}{2}, 0);
verifyEqual(testCase, opens{1}{4}, ex.setup.overlayWindowRect);
canvases = calls(cellfun(@(c) strcmp(c{1}, 'OpenOffscreenWindow'), calls));
verifyEqual(testCase, canvases{1}{4}, [0 0 2560 1440]);
verifyEmpty(testCase, COPS_DISPLAY_TEST.datapixxCalls);
end

function testOverlayDoesNotChangeMainDisplayModeOrMapping(testCase)
global COPS_DISPLAY_TEST
for explicitMapping = [false true]
    mainCalls = cell(1, 2);
    mappingCalls = cell(1, 2);
    for overlayOn = [false true]
        COPS_DISPLAY_TEST.screenCalls = {};
        COPS_DISPLAY_TEST.imagingCalls = {};
        ex = fixture();
        if ~explicitMapping
            ex.setup = rmfield(ex.setup, 'screenToHead');
        end
        ex.setup.showExperimenterOverlay = overlayOn;
        ex = initDisplayx(ex);
        verifyFalse(testCase, ex.setup.stereo.Display);
        verifyEqual(testCase, ex.setup.stereo.Mode, 0);
        mainCalls{overlayOn+1} = COPS_DISPLAY_TEST.imagingCalls;
        calls = COPS_DISPLAY_TEST.screenCalls;
        mappingCalls{overlayOn+1} = calls(cellfun(@(c) ...
            strcmp(c{1}, 'Preference') && strcmp(c{2}, 'ScreenToHead'), calls));
    end
    verifyEqual(testCase, mainCalls{1}, mainCalls{2});
    verifyEqual(testCase, mappingCalls{1}, mappingCalls{2});
end
% An independent desktop overlay must never activate the stereo hardware path.
verifyEmpty(testCase, COPS_DISPLAY_TEST.datapixxCalls);
end

function testIndependentContextsAndPreferencesAreRestored(testCase)
global COPS_DISPLAY_TEST
ex = fixture();
ex.setup.screenRect = [0 0 2560 1440];
ex = configureCoPsOverlayDisplayx(ex);
ex = openCoPsOverlayDisplayx(ex);
verifyEqual(testCase, COPS_DISPLAY_TEST.openVRAM, 96); % 64 | disable context sharing.
verifyEqual(testCase, COPS_DISPLAY_TEST.openSkip, 2); % Informational GUI only.
verifyEqual(testCase, COPS_DISPLAY_TEST.ConserveVRAM, 64);
verifyEqual(testCase, COPS_DISPLAY_TEST.SkipSyncTests, 0);
calls = COPS_DISPLAY_TEST.screenCalls;
offscreen = calls(cellfun(@(c) strcmp(c{1}, 'OpenOffscreenWindow'), calls));
verifyEqual(testCase, offscreen{1}{2}, ex.setup.overlayWindow);
verifyEqual(testCase, offscreen{1}{4}, [0 0 2560 1440]);
end

function testPresentationIsScaledThrottledAndDoesNotWaitForVBL(testCase)
global COPS_DISPLAY_TEST
ex = fixture();
ex.setup.overlay = 201;
ex.setup.overlayWindow = 102;
ex.setup.overlayIsSeparate = true;
ex.setup.overlayDisplayRateHz = 30;
presentCoPsOverlayx(ex);
calls = COPS_DISPLAY_TEST.screenCalls;
verifyEqual(testCase, calls{end-1}, {'DrawTexture', 102, 201, [], [0 0 960 540]});
verifyEqual(testCase, calls{end}, {'Flip', 102, 0, 0, 2});
count = numel(calls);
COPS_DISPLAY_TEST.now = 1.01;
presentCoPsOverlayx(ex);
verifyNumElements(testCase, COPS_DISPLAY_TEST.screenCalls, count);
COPS_DISPLAY_TEST.now = 1.04;
presentCoPsOverlayx(ex);
verifyNumElements(testCase, COPS_DISPLAY_TEST.screenCalls, count+3);
end

function ex = fixture()
ex.setup = struct('screenNum', 1, 'screenToHead', [1 0 2], ...
    'showExperimenterOverlay', true, ...
    'stereo', struct('Display', true, 'Mode', 8, 'Multisampling', 8));
ex.idx.bg = 128;
ex.synch.PSz = 20;
end

function ex = portableFixture()
ex = fixture();
ex.setup = rmfield(ex.setup, 'screenToHead');
ex.setup.testMode = true;
ex.setup.fullscreen = false;
ex.setup.windowSizePx = [1280 720];
ex.setup.showExperimenterOverlay = false;
end

function writeMock(folder, name, lines)
fid = fopen(fullfile(folder, [name '.m']), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', lines);
end
