function ex = showCoPsTrialFeedbackx(ex, backgroundColor)
% Show a scheduled trial pause or the final participant acknowledgement.
ctl = ex.exp.CoPs.ctl;
rew = ex.exp.CoPs.rew;
isFinalTrial = ex.j == ex.finish;
pausesEnabled = ~isfield(ctl, 'advance_trial_with_space') || ctl.advance_trial_with_space;
pauseScheduled = pausesEnabled && ~isFinalTrial && ...
    ex.exp.CoPs.pauseSchedule.afterTrial(ex.j);
ex.Trials(ex.j).pointsFeedbackOn = NaN;
ex.Trials(ex.j).pointsFeedbackOff = NaN;
ex.Trials(ex.j).trialAdvanceWaitOn = NaN;
ex.Trials(ex.j).trialAdvanceWaitOff = NaN;
ex.Trials(ex.j).betweenTrialPauseScheduled = pauseScheduled;
ex.Trials(ex.j).betweenTrialBackgroundGray = backgroundColor;
ex.Trials(ex.j).endScreenOn = NaN;
ex.Trials(ex.j).endScreenOff = NaN;
ex.Trials(ex.j).endScreenAcknowledged = false;
if ex.quit ~= 0 || (~pauseScheduled && ~isFinalTrial)
    return
end

showPoints = ~isFinalTrial && rew.points_feedback_on && ex.Trials(ex.j).trialScored;
textSize = double(rew.points_feedback_text_size);
if ~isscalar(textSize) || ~isfinite(textSize) || textSize <= 0
    textSize = 48;
end
textSize = round(textSize);
decimals = double(rew.points_feedback_decimals);
if ~isscalar(decimals) || ~isfinite(decimals) || decimals < 0
    decimals = 1;
end
decimals = min(6, round(decimals));
numberFormat = ['%.' num2str(decimals) 'f'];
if isFinalTrial || showPoints
    % Only accepted threshold crossings earn displayed points. Fractional
    % evidence resets each trial and must not add up to an unearned point.
    earnedPoints = arrayfun(@(trial) nnz(isfinite(trial.times.reward)), ex.Trials(1:ex.j));
    trialPoints = earnedPoints(end);
    totalPoints = sum(earnedPoints);
end
if isFinalTrial
    feedbackText = sprintf(['The session is complete.\n\nTotal: ' numberFormat ...
        ' points\n\nPress SPACE to finish.\n\nPlease inform the experimenter.'], totalPoints);
elseif showPoints
    feedbackText = sprintf(['Previous trial: ' numberFormat ' points\n\nTotal: ' numberFormat ...
        ' points\n\nPress SPACE to continue'], ...
        trialPoints, totalPoints);
else
    feedbackText = 'Press SPACE to start the next trial';
end

setup = ex.setup;
window = setup.window;
oldTextSize = Screen('TextSize', window);
Screen('TextSize', window, textSize);
Screen('FillRect', window, backgroundColor);
DrawFormattedText(window, feedbackText, 'center', 'center', ex.idx.white, [], [], [], 1.5);
drawIdleSyncLocal(ex);
refreshCoPsPreviewWindowx(setup);
feedbackOn = Screen('Flip', window);
Screen('TextSize', window, oldTextSize);

% Discard a held SPACE, then require a fresh press and release.
KbName('UnifyKeyNames');
quitKey = KbName('F4');
[~, spaceDown] = readCoPsKeyboardx(setup);
spaceReady = ~spaceDown;
waitingForSpaceRelease = false;
quitRequested = false;
separateKeyboards = isfield(setup, 'keyboards') && setup.keyboards.separate;
while true
    if refreshCoPsPreviewWindowx(setup)
        Screen('FillRect', window, backgroundColor);
        Screen('TextSize', window, textSize);
        DrawFormattedText(window, feedbackText, 'center', 'center', ex.idx.white, [], [], [], 1.5);
        drawIdleSyncLocal(ex);
        Screen('TextSize', window, oldTextSize);
        Screen('Flip', window);
    end
    [keyCode, spaceDown] = readCoPsKeyboardx(setup);
    focused = true;
    if isfield(setup, 'guiWindow') && setup.guiWindow && ~separateKeyboards
        [~, ~, ~, focused] = GetMouse(window);
    end
    if ~focused
        spaceReady = false;
        waitingForSpaceRelease = false;
        WaitSecs('YieldSecs', 0.01);
        continue
    end
    if any(keyCode(quitKey))
        quitRequested = true;
        break
    elseif ~spaceDown
        if waitingForSpaceRelease
            break
        end
        spaceReady = true;
    elseif spaceReady
        waitingForSpaceRelease = true;
    end
    WaitSecs('YieldSecs', 0.01);
end

Screen('FillRect', window, backgroundColor);
drawIdleSyncLocal(ex);
refreshCoPsPreviewWindowx(setup);
feedbackOff = Screen('Flip', window);
if isFinalTrial
    ex.Trials(ex.j).endScreenOn = feedbackOn;
    ex.Trials(ex.j).endScreenOff = feedbackOff;
    ex.Trials(ex.j).endScreenAcknowledged = ~quitRequested;
else
    ex.Trials(ex.j).trialAdvanceWaitOn = feedbackOn;
    ex.Trials(ex.j).trialAdvanceWaitOff = feedbackOff;
    if showPoints
        ex.Trials(ex.j).pointsFeedbackOn = feedbackOn;
        ex.Trials(ex.j).pointsFeedbackOff = feedbackOff;
    end
end
if quitRequested
    ex.quit = 4;
end
end

function drawIdleSyncLocal(ex)
if isfield(ex.exp.CoPs, 'sync') && strcmp(ex.exp.CoPs.sync.mode, 'binary')
    sz = ex.synch.PSz;
    r = ex.setup.screenRect;
    Screen('FillRect', ex.setup.window, ex.idx.black, [r(3)-sz r(2) r(3) r(2)+sz]);
end
end
