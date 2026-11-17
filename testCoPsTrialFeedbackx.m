function tests = testCoPsTrialFeedbackx
% Exercise feedback decisions and key handling without opening a display.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
mockDir = tempname;
mkdir(mockDir);
testCase.TestData.mockDir = mockDir;
testCase.TestData.originalPath = path;
writeMock(mockDir, 'Screen', [
    "function varargout = Screen(command, varargin)"
    "global COPS_FEEDBACK_TEST"
    "switch lower(command)"
    "case 'textsize'"
    "    varargout = {COPS_FEEDBACK_TEST.textSize};"
    "    if numel(varargin) > 1, COPS_FEEDBACK_TEST.textSize = varargin{2}; end"
    "case 'fillrect'"
    "    COPS_FEEDBACK_TEST.backgrounds(end+1) = varargin{2};"
    "case 'flip'"
    "    COPS_FEEDBACK_TEST.flips = COPS_FEEDBACK_TEST.flips + 1;"
    "    varargout = {100 + COPS_FEEDBACK_TEST.flips};"
    "otherwise, error('CoPsFeedbackTest:UnexpectedScreenCall', 'Unexpected Screen command.');"
    "end"
    "end"]);
writeMock(mockDir, 'DrawFormattedText', [
    "function DrawFormattedText(window, message, varargin)"
    "global COPS_FEEDBACK_TEST"
    "COPS_FEEDBACK_TEST.messages{end+1} = message;"
    "end"]);
writeMock(mockDir, 'refreshCoPsPreviewWindowx', [
    "function changed = refreshCoPsPreviewWindowx(setup)"
    "global COPS_FEEDBACK_TEST"
    "COPS_FEEDBACK_TEST.refreshes = COPS_FEEDBACK_TEST.refreshes + 1;"
    "changed = ismember(COPS_FEEDBACK_TEST.refreshes, COPS_FEEDBACK_TEST.resizeAt);"
    "end"]);
writeMock(mockDir, 'readCoPsKeyboardx', [
    "function [keys, spaceDown, timestamp, question] = readCoPsKeyboardx(setup)"
    "global COPS_FEEDBACK_TEST"
    "COPS_FEEDBACK_TEST.polls = COPS_FEEDBACK_TEST.polls + 1;"
    "i = COPS_FEEDBACK_TEST.polls;"
    "assert(i <= numel(COPS_FEEDBACK_TEST.spaces), 'Feedback did not finish with the supplied key sequence.');"
    "keys = false(1, 256);"
    "keys(4) = ismember(i, COPS_FEEDBACK_TEST.quitAt);"
    "keys(6) = ismember(i, COPS_FEEDBACK_TEST.calibrationAt);"
    "spaceDown = COPS_FEEDBACK_TEST.spaces(i);"
    "timestamp = 200+i/100; question = ismember(i,COPS_FEEDBACK_TEST.questionAt);"
    "COPS_FEEDBACK_TEST.keyboardSetups{end+1} = setup;"
    "end"]);
writeMock(mockDir, 'KbName', [
    "function key = KbName(name)"
    "if strcmp(name, 'F4'), key = 4; elseif strcmp(name,'F6'), key = 6; else, key = []; end"
    "end"]);
writeMock(mockDir,'notifyCoPsQuestionx',[
    "function [request,cleanup] = notifyCoPsQuestionx(ex)"
    "global COPS_FEEDBACK_TEST"
    "COPS_FEEDBACK_TEST.questions = COPS_FEEDBACK_TEST.questions+1;"
    "request = struct('time',200,'target','experimenterPopup'); cleanup=[];"
    "end"]);
writeMock(mockDir, 'WaitSecs', ["function WaitSecs(varargin)"; "end"]);
writeMock(mockDir, 'GetMouse', [
    "function [x, y, buttons, focused] = GetMouse(varargin)"
    "global COPS_FEEDBACK_TEST"
    "x = 0; y = 0; buttons = [];"
    "i = min(COPS_FEEDBACK_TEST.polls, numel(COPS_FEEDBACK_TEST.focus));"
    "focused = COPS_FEEDBACK_TEST.focus(i);"
    "COPS_FEEDBACK_TEST.focusQueries = COPS_FEEDBACK_TEST.focusQueries + 1;"
    "end"]);
addpath(fileparts(mfilename('fullpath')), '-begin');
addpath(mockDir, '-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear Screen DrawFormattedText refreshCoPsPreviewWindowx readCoPsKeyboardx KbName WaitSecs GetMouse notifyCoPsQuestionx
mockDir = testCase.TestData.mockDir;
assert(strcmp(fileparts(mockDir), fileparts(tempname)), ...
    'Refusing to remove a mock directory outside the temporary folder.');
rmdir(mockDir, 's');
clear global COPS_FEEDBACK_TEST
end

function setup(~)
global COPS_FEEDBACK_TEST
COPS_FEEDBACK_TEST = struct('textSize', 24, 'backgrounds', [], 'flips', 0, ...
    'messages', {{}}, 'refreshes', 0, 'resizeAt', [], 'polls', 0, ...
    'spaces', [false true false], 'quitAt', [], 'keyboardSetups', {{}}, ...
    'focus', true, 'focusQueries', 0, 'questionAt', [], 'calibrationAt', [], 'questions', 0);
end

function testFinalScreenIgnoresPauseAndPointsSettings(testCase)
global COPS_FEEDBACK_TEST
ex = fixture();
ex.exp.CoPs.ctl.advance_trial_with_space = false;
ex.exp.CoPs.rew.points_feedback_on = false;
ex.Trials(end).trialScored = false;
ex = showFeedback(testCase, ex);
verifyEqual(testCase, COPS_FEEDBACK_TEST.messages, {sprintf(['The session is complete.\n\n' ...
    'Total: 6 points\nAverage: 2.00 points per trial\nBonus earned: $0.00\n\n' ...
    'Press SPACE to finish.\n\nPlease inform the experimenter.'])});
verifyEqual(testCase, COPS_FEEDBACK_TEST.backgrounds, [127 127]);
verifyEqual(testCase, COPS_FEEDBACK_TEST.textSize, 24);
verifyEqual(testCase, [ex.Trials(end).endScreenOn ex.Trials(end).endScreenOff], [101 102]);
verifyTrue(testCase, ex.Trials(end).endScreenAcknowledged);
verifyFalse(testCase, ex.Trials(end).betweenTrialPauseScheduled);
verifyTrue(testCase, isnan(ex.Trials(end).trialAdvanceWaitOn));
verifyEqual(testCase, ex.quit, 0);
verifyEqual(testCase, COPS_FEEDBACK_TEST.keyboardSetups{end}, ex.setup);
verifyEqual(testCase,ex.Payout.bonusDollars,0);
verifyEqual(testCase,ex.Payout.nTrials,3);
verifyTrue(testCase,ex.Outro.acknowledged);
end

function testHeldSpaceRequiresReleaseThenANewPressAndRelease(testCase)
global COPS_FEEDBACK_TEST
COPS_FEEDBACK_TEST.spaces = [true true false false true true false];
ex = showFeedback(testCase, fixture());
verifyTrue(testCase, ex.Trials(end).endScreenAcknowledged);
verifyEqual(testCase, COPS_FEEDBACK_TEST.polls, 7);
end

function testUnscheduledMiddleTrialDoesNotWait(testCase)
global COPS_FEEDBACK_TEST
ex = fixture();
ex.j = 2;
ex = showFeedback(testCase, ex);
verifyEmpty(testCase, COPS_FEEDBACK_TEST.messages);
verifyEqual(testCase, COPS_FEEDBACK_TEST.polls, 0);
verifyFalse(testCase, ex.Trials(2).endScreenAcknowledged);
end

function testAbortedFinalTrialDoesNotShowCompletion(testCase)
global COPS_FEEDBACK_TEST
ex = fixture();
ex.quit = 4;
ex = showFeedback(testCase, ex);
verifyEmpty(testCase, COPS_FEEDBACK_TEST.messages);
verifyFalse(testCase, ex.Trials(end).endScreenAcknowledged);
verifyTrue(testCase, isnan(ex.Trials(end).endScreenOn));
end

function testOperatorCanAbortTheEndScreen(testCase)
global COPS_FEEDBACK_TEST
COPS_FEEDBACK_TEST.spaces = [false false];
COPS_FEEDBACK_TEST.quitAt = 2;
ex = showFeedback(testCase, fixture());
verifyEqual(testCase, ex.quit, 4);
verifyFalse(testCase, ex.Trials(end).endScreenAcknowledged);
verifyEqual(testCase, ex.Trials(end).endScreenOff, 102);
end

function testScheduledPointsPauseKeepsLabelsAndSpacing(testCase)
global COPS_FEEDBACK_TEST
ex = fixture();
ex.j = 2;
ex.totalPoints = 4;
ex.exp.CoPs.pauseSchedule.afterTrial(2) = true;
ex = showFeedback(testCase, ex);
verifyEqual(testCase, COPS_FEEDBACK_TEST.messages, ...
    {sprintf(['Previous trial: 2 points\n\nTotal: 4 points\n\nPress SPACE to continue\n\n' ...
    'To ask a question, press Q and keep your head still.'])});
verifyEqual(testCase, [ex.Trials(2).pointsFeedbackOn ex.Trials(2).pointsFeedbackOff], [101 102]);
verifyFalse(testCase, ex.Trials(2).endScreenAcknowledged);
end

function testFinalTotalExcludesFractionalProgress(testCase)
global COPS_FEEDBACK_TEST
ex = fixture();
ex.totalPoints = 58.77634674819162;
ex.Trials(1).pointsEarned = 18.184030699196118;
ex.Trials(2).pointsEarned = 22.228749550949445;
ex.Trials(3).pointsEarned = 18.363566498046062;
ex.Trials(1).times.reward = 1:18;
ex.Trials(2).times.reward = 1:22;
ex.Trials(3).times.reward = 1:18;
rawTotal = ex.totalPoints;
rawTrials = [ex.Trials.pointsEarned];
ex = showFeedback(testCase, ex);
verifySubstring(testCase, COPS_FEEDBACK_TEST.messages{1}, 'Total: 58 points');
verifyEqual(testCase, ex.totalPoints, rawTotal);
verifyEqual(testCase, [ex.Trials.pointsEarned], rawTrials);
end

function testPauseDoesNotCombinePartialProgressAcrossTrials(testCase)
global COPS_FEEDBACK_TEST
ex = fixture();
ex.j = 2;
ex.exp.CoPs.pauseSchedule.afterTrial(2) = true;
ex.totalPoints = 5.8;
ex.Trials(1).pointsEarned = 2.9;
ex.Trials(2).pointsEarned = 2.9;
ex = showFeedback(testCase, ex);
verifyEqual(testCase, COPS_FEEDBACK_TEST.messages, ...
    {sprintf(['Previous trial: 2 points\n\nTotal: 4 points\n\nPress SPACE to continue\n\n' ...
    'To ask a question, press Q and keep your head still.'])});
verifyEqual(testCase, ex.totalPoints, 5.8);
end

function testNoAcceptedCrossingDisplaysZero(testCase)
global COPS_FEEDBACK_TEST
ex = fixture();
ex.j = 1;
ex.finish = 1;
ex.totalPoints = 1;
ex.Trials(1).pointsEarned = 1;
% The reward condition is strictly greater than the threshold.
ex.Trials(1).times.reward = NaN;
ex = showFeedback(testCase, ex);
verifySubstring(testCase, COPS_FEEDBACK_TEST.messages{1}, 'Total: 0 points');
end

function testResizeRedrawsTheEndMessage(testCase)
global COPS_FEEDBACK_TEST
COPS_FEEDBACK_TEST.resizeAt = 2;
ex = showFeedback(testCase, fixture());
verifyNumElements(testCase, COPS_FEEDBACK_TEST.messages, 2);
verifyEqual(testCase, COPS_FEEDBACK_TEST.messages{1}, COPS_FEEDBACK_TEST.messages{2});
verifyEqual(testCase, ex.Trials(end).endScreenOff, 103);
end

function testUnfocusedSharedWindowCannotAcknowledge(testCase)
global COPS_FEEDBACK_TEST
COPS_FEEDBACK_TEST.spaces = [false true false true true false true false];
COPS_FEEDBACK_TEST.focus = [true false false true true true true true];
ex = fixture();
ex.setup.guiWindow = true;
ex = showFeedback(testCase, ex);
% SPACE pressed while unfocused must be released before a new press works.
verifyTrue(testCase, ex.Trials(end).endScreenAcknowledged);
verifyEqual(testCase, COPS_FEEDBACK_TEST.polls, 8);
end

function testDedicatedDevicesWorkWithoutDesktopWindowFocus(testCase)
global COPS_FEEDBACK_TEST
COPS_FEEDBACK_TEST.focus = false;
ex = fixture();
ex.setup.guiWindow = true;
ex.setup.keyboards.separate = true;
ex = showFeedback(testCase, ex);
verifyTrue(testCase, ex.Trials(end).endScreenAcknowledged);
verifyEqual(testCase, COPS_FEEDBACK_TEST.focusQueries, 0);
end

function testBinaryPatchStaysBlackOnFinalFeedback(testCase)
global COPS_FEEDBACK_TEST
ex = fixture();
ex.exp.CoPs.sync.mode = 'binary';
ex.synch.PSz = 120;
ex.idx.black = 0;
ex.setup.screenRect = [0 0 1920 1080];
showFeedback(testCase,ex);
verifyEqual(testCase,COPS_FEEDBACK_TEST.backgrounds,[127 0 127 0]);
end

function testPracticeFeedbackIsSeparateAndAlwaysWaits(testCase)
global COPS_FEEDBACK_TEST
ex = fixture();
ex.j = 1;
ex.Trials(1).isInstructionTutorial = true;
ex.exp.CoPs.ctl.advance_trial_with_space = false;
ex.exp.CoPs.rew.points_feedback_on = false;
ex = showFeedback(testCase,ex);
verifyEqual(testCase,COPS_FEEDBACK_TEST.messages,{sprintf(['Practice trial: 2 points\n\n' ...
    'Practice points do not count toward your winnings.\n\nPress SPACE to continue\n\n' ...
    'To ask a question, press Q and keep your head still.'])});
verifyEqual(testCase,ex.Trials(1).trialAdvanceWaitOn,101);
end

function testFinalTotalDoesNotIncludePracticeCrossings(testCase)
global COPS_FEEDBACK_TEST
ex = fixture();
ex.Trials(1).isInstructionTutorial = true;
showFeedback(testCase,ex);
verifySubstring(testCase,COPS_FEEDBACK_TEST.messages{1},'Total: 4 points');
end

function testFinalTotalExcludesBothPracticeTrials(testCase)
global COPS_FEEDBACK_TEST
ex=fixture();
ex.Trials(1).isInstructionTutorial=true;
ex.Trials(2).isInstructionTutorial=true;
showFeedback(testCase,ex);
verifySubstring(testCase,COPS_FEEDBACK_TEST.messages{1},'Total: 2 points');
end

function testOutroShowsAndSavesCashBonusFromPaidTrialsOnly(testCase)
global COPS_FEEDBACK_TEST
ex=fixture();
ex.j=4; ex.finish=4;
ex.Trials(4)=ex.Trials(3);
for k=1:4, ex.Trials(k).times.reward=1:14; end
ex.Trials(1).isInstructionTutorial=true;
ex.Trials(2).isInstructionTutorial=true;
ex=showFeedback(testCase,ex);
verifySubstring(testCase,COPS_FEEDBACK_TEST.messages{1},'Total: 28 points');
verifySubstring(testCase,COPS_FEEDBACK_TEST.messages{1},'Average: 14.00 points per trial');
verifySubstring(testCase,COPS_FEEDBACK_TEST.messages{1},'Bonus earned: $12.50');
verifyEqual(testCase,ex.Payout.nTrials,2);
verifyEqual(testCase,ex.Payout.bonusDollars,12.5);
verifyEqual(testCase,ex.Trials(end).payout,ex.Payout);
verifyEqual(testCase,ex.Outro.text,COPS_FEEDBACK_TEST.messages{1});
verifyEqual(testCase,[ex.Outro.on ex.Outro.off],[101 102]);
end

function testQIsAvailableOnEveryFeedbackScreen(testCase)
global COPS_FEEDBACK_TEST
for kind={'points','blank','practice','outro'}
    setup(testCase);
    COPS_FEEDBACK_TEST.spaces=[false false false true false];
    COPS_FEEDBACK_TEST.questionAt=[2 3];
    ex=fixture();
    if ~strcmp(kind{1},'outro')
        ex.j=1; ex.exp.CoPs.pauseSchedule.afterTrial(1)=true;
    end
    if strcmp(kind{1},'blank'), ex.exp.CoPs.rew.points_feedback_on=false; end
    if strcmp(kind{1},'practice'), ex.Trials(1).isInstructionTutorial=true; end
    ex=showFeedback(testCase,ex);
    verifyEqual(testCase,COPS_FEEDBACK_TEST.questions,1);
    verifyNumElements(testCase,ex.Trials(ex.j).pauseQuestionRequests,1);
    if strcmp(kind{1},'outro')
        verifyFalse(testCase,contains(COPS_FEEDBACK_TEST.messages{1},'To ask a question'));
        verifyEqual(testCase,ex.Outro.questionRequests,ex.Trials(ex.j).pauseQuestionRequests);
    else
        verifySubstring(testCase,COPS_FEEDBACK_TEST.messages{1},'press Q and keep your head still');
    end
end
end

function testF6QueuesNextTrialAfterReleaseWithoutSpace(testCase)
global COPS_FEEDBACK_TEST
COPS_FEEDBACK_TEST.spaces=false(1,4);
COPS_FEEDBACK_TEST.calibrationAt=[2 3];
ex=fixture(); ex.j=2; ex.setup.inputMode='eyelink';
ex.exp.CoPs.pauseSchedule.afterTrial(2)=true;
ex=showFeedback(testCase,ex);
verifyTrue(testCase,ex.Trials(2).pauseCalibrationRequested);
verifyEqual(testCase,ex.Recalibration.pending.nextTrial,3);
verifyEqual(testCase,ex.quit,0);
verifyEqual(testCase,COPS_FEEDBACK_TEST.polls,4);
end

function testHeldF6NeedsAReleaseAndFreshPress(testCase)
global COPS_FEEDBACK_TEST
COPS_FEEDBACK_TEST.spaces=false(1,6);
COPS_FEEDBACK_TEST.calibrationAt=[1 2 4 5];
ex=fixture(); ex.j=2; ex.setup.inputMode='eye';
ex.exp.CoPs.pauseSchedule.afterTrial(2)=true;
ex=showFeedback(testCase,ex);
verifyTrue(testCase,ex.Trials(2).pauseCalibrationRequested);
verifyEqual(testCase,COPS_FEEDBACK_TEST.polls,6);
end

function testF6DoesNotCalibrateMouseOrCompletedSession(testCase)
global COPS_FEEDBACK_TEST
for mode={'mouse','eyelink'}
    setup(testCase);
    COPS_FEEDBACK_TEST.spaces=[false false false true false];
    COPS_FEEDBACK_TEST.calibrationAt=2;
    ex=fixture(); ex.setup.inputMode=mode{1};
    if strcmp(mode{1},'mouse'), ex.j=2; ex.exp.CoPs.pauseSchedule.afterTrial(2)=true; end
    ex=showFeedback(testCase,ex);
    verifyFalse(testCase,ex.Trials(ex.j).pauseCalibrationRequested);
    verifyFalse(testCase,isfield(ex,'Recalibration'));
end
end

function testF4TakesPriorityOverCalibration(testCase)
global COPS_FEEDBACK_TEST
COPS_FEEDBACK_TEST.spaces=[false false];
COPS_FEEDBACK_TEST.calibrationAt=2; COPS_FEEDBACK_TEST.quitAt=2;
ex=fixture(); ex.j=2; ex.setup.inputMode='eyelink';
ex.exp.CoPs.pauseSchedule.afterTrial(2)=true;
ex=showFeedback(testCase,ex);
verifyEqual(testCase,ex.quit,4);
verifyFalse(testCase,ex.Trials(2).pauseCalibrationRequested);
end

function ex = showFeedback(testCase, ex)
originalFolder = pwd;
cd(testCase.TestData.mockDir);
restoreFolder = onCleanup(@() cd(originalFolder)); %#ok<NASGU>
clear Screen DrawFormattedText refreshCoPsPreviewWindowx readCoPsKeyboardx KbName WaitSecs GetMouse notifyCoPsQuestionx
ex = showCoPsTrialFeedbackx(ex, 127);
end

function ex = fixture()
ex = struct('j', 3, 'finish', 3, 'quit', 0, 'totalPoints', 6);
ex.exp.CoPs.ctl.advance_trial_with_space = true;
ex.exp.CoPs.pay = resolveCoPsPayx();
ex.exp.CoPs.rew = struct('points_feedback_on', true, ...
    'points_feedback_text_size', 48, 'points_feedback_decimals', 0);
ex.exp.CoPs.pauseSchedule.afterTrial = false(1, 3);
ex.setup = struct('window', 101, 'guiWindow', false, 'keyboards', struct('separate', false));
ex.idx.white = 255;
ex.Trials = repmat(struct('pointsEarned', 2, 'trialScored', true, ...
    'times', struct('reward', [0.25 0.5])), 1, 3);
end

function writeMock(folder, name, lines)
fid = fopen(fullfile(folder, [name '.m']), 'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', lines);
end
