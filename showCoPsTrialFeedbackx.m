function ex = showCoPsTrialFeedbackx(ex, backgroundColor)
% Show a scheduled trial pause or the final participant acknowledgement.
if isfield(ex.setup,'recording') && ex.setup.recording.enabled, return; end
ctl = ex.exp.CoPs.ctl;
rew = ex.exp.CoPs.rew;
isFinalTrial = ex.j == ex.finish;
isPractice = isPracticeLocal(ex.Trials(ex.j));
pausesEnabled = ~isfield(ctl, 'advance_trial_with_space') || ctl.advance_trial_with_space;
pauseScheduled = ~isFinalTrial && (isPractice || (pausesEnabled && ...
    ex.exp.CoPs.pauseSchedule.afterTrial(ex.j)));
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
if isFinalTrial
    ex.Payout = calculateCoPsPayoutx(ex.Trials(1:ex.j),ex.exp.CoPs.pay);
    ex = showCoPsOutrox(ex,backgroundColor,false,ex.j);
    return
end

showPoints = isPractice || (rew.points_feedback_on && ex.Trials(ex.j).trialScored);
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
if showPoints
    % Only accepted threshold crossings earn displayed points. Fractional
    % evidence resets each trial and must not add up to an unearned point.
    [totalPoints,earnedPoints] = getCoPsEarnedPointsx(ex.Trials(1:ex.j));
    trialPoints = earnedPoints(end);
end
if isPractice
    feedbackText = sprintf(['Practice trial: ' numberFormat ' points\n\n' ...
        'Practice points do not count toward your winnings.\n\nPress SPACE to continue'],trialPoints);
elseif showPoints
    feedbackText = sprintf(['Previous trial: ' numberFormat ' points\n\nTotal: ' numberFormat ...
        ' points\n\nPress SPACE to continue'], ...
        trialPoints, totalPoints);
else
    feedbackText = 'Press SPACE to start the next trial';
end
feedbackText = sprintf('%s\n\nTo ask a question, press Q and keep your head still.',feedbackText);

setup = ex.setup;
window = setup.window;
oldTextSize = Screen('TextSize', window);
Screen('TextSize', window, textSize);
Screen('FillRect', window, backgroundColor);
DrawFormattedText(window, feedbackText, 'center', 'center', ex.idx.white, [], [], [], 1.5);
drawCoPsIdleSyncx(ex);
refreshCoPsPreviewWindowx(setup);
feedbackOn = Screen('Flip', window);
Screen('TextSize', window, oldTextSize);

allowCalibration = isfield(setup,'inputMode') && ismember(setup.inputMode,{'eyelink','eye'});
[quitRequested,questionRequests,recalibrate] = waitCoPsSpacex(setup, ...
    @() redrawLocal(ex,backgroundColor,feedbackText,textSize,oldTextSize), ...
    @() notifyCoPsQuestionx(ex),allowCalibration);
ex.Trials(ex.j).pauseQuestionRequests = questionRequests;
ex.Trials(ex.j).pauseCalibrationRequested = recalibrate;
if recalibrate
    ex = requestCoPsRecalibrationx(ex,ex.j+1,'trialFeedback');
end

Screen('FillRect', window, backgroundColor);
drawCoPsIdleSyncx(ex);
refreshCoPsPreviewWindowx(setup);
feedbackOff = Screen('Flip', window);
ex.Trials(ex.j).trialAdvanceWaitOn = feedbackOn;
ex.Trials(ex.j).trialAdvanceWaitOff = feedbackOff;
if showPoints
    ex.Trials(ex.j).pointsFeedbackOn = feedbackOn;
    ex.Trials(ex.j).pointsFeedbackOff = feedbackOff;
end
if quitRequested
    ex.quit = 4;
end
end

function tf = isPracticeLocal(trial)
tf = isfield(trial,'isInstructionTutorial') && ~isempty(trial.isInstructionTutorial) && trial.isInstructionTutorial;
end

function redrawLocal(ex,backgroundColor,feedbackText,textSize,oldTextSize)
window = ex.setup.window;
Screen('FillRect',window,backgroundColor);
Screen('TextSize',window,textSize);
DrawFormattedText(window,feedbackText,'center','center',ex.idx.white,[],[],[],1.5);
drawCoPsIdleSyncx(ex);
Screen('TextSize',window,oldTextSize);
Screen('Flip',window);
end
