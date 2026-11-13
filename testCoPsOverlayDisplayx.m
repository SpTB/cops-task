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
    "    if varargin{2} <= 1, rect = COPS_DISPLAY_TEST.rects{varargin{2}+1}; else, rect = [0 0 960 540]; end"
    "    varargout = {rect};"
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
    "case 'openwindow', varargout = {101, [0 0 2560 1440]};"
    "otherwise, varargout = cell(1,nargout);"
    "end"
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

function writeMock(folder, name, lines)
fid = fopen(fullfile(folder, [name '.m']), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', lines);
end
