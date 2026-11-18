function ex = showCoPsOutrox(ex,backgroundColor,endedEarly,trialIndex)
% Shared normal/early outro. The caller supplies the calculated ex.Payout.
if nargin < 3, endedEarly = false; end
if nargin < 4, trialIndex = numel(ex.Trials); end
rew = ex.exp.CoPs.rew;
sizePx = double(rew.points_feedback_text_size);
if ~isscalar(sizePx) || ~isfinite(sizePx) || sizePx <= 0, sizePx = 48; end
sizePx = round(sizePx);
decimals = double(rew.points_feedback_decimals);
if ~isscalar(decimals) || ~isfinite(decimals) || decimals < 0, decimals = 1; end
decimals = min(6,round(decimals));
heading = 'The session is complete.';
if endedEarly, heading = 'The session has ended.'; end
p = ex.Payout;
averageDisplayed = floor(100*p.totalPoints/max(1,p.nTrials))/100;
message = sprintf(['%s\n\nTotal: %.' num2str(decimals) ...
    'f points\nAverage: %.2f points per trial\nBonus earned: $%.2f\n\n' ...
    'Press SPACE to finish.\n\nPlease inform the experimenter.'], ...
    heading,p.totalPoints,averageDisplayed,p.bonusDollars);
ex.Outro = struct('text',message,'on',NaN,'off',NaN, ...
    'acknowledged',false,'endedEarly',logical(endedEarly));
window = ex.setup.window;
oldSize = Screen('TextSize',window);
textCleanup = onCleanup(@() restoreTextSizeLocal(window,oldSize)); %#ok<NASGU>
refreshCoPsPreviewWindowx(ex.setup);
drawLocal(ex,backgroundColor,message,sizePx);
ex.Outro.on = Screen('Flip',window);
Screen('TextSize',window,oldSize);
% F4 may still be held from the stop request: require its release before
% accepting a second F4 to dismiss this page. SPACE also needs a fresh press.
[quitRequested,requests] = waitCoPsSpacex(ex.setup, ...
    @() redrawLocal(ex,backgroundColor,message,sizePx,oldSize), ...
    @() notifyCoPsQuestionx(ex),false,true);
Screen('FillRect',window,backgroundColor);
drawCoPsIdleSyncx(ex);
refreshCoPsPreviewWindowx(ex.setup);
ex.Outro.off = Screen('Flip',window);
ex.Outro.acknowledged = ~quitRequested;
ex.Outro.questionRequests = requests;
if trialIndex > 0
    ex.Trials(trialIndex).payout = p;
    ex.Trials(trialIndex).endScreenOn = ex.Outro.on;
    ex.Trials(trialIndex).endScreenOff = ex.Outro.off;
    ex.Trials(trialIndex).endScreenAcknowledged = ex.Outro.acknowledged;
    ex.Trials(trialIndex).pauseQuestionRequests = requests;
    ex.Trials(trialIndex).pauseCalibrationRequested = false;
end
if quitRequested, ex.quit = 4; end
end

function drawLocal(ex,color,message,sizePx)
Screen('FillRect',ex.setup.window,color);
Screen('TextSize',ex.setup.window,sizePx);
DrawFormattedText(ex.setup.window,message,'center','center',ex.idx.white,[],[],[],1.5);
drawCoPsIdleSyncx(ex);
end

function redrawLocal(ex,color,message,sizePx,oldSize)
drawLocal(ex,color,message,sizePx);
Screen('TextSize',ex.setup.window,oldSize);
Screen('Flip',ex.setup.window);
end

function restoreTextSizeLocal(window,sizePx)
try
    Screen('TextSize',window,sizePx);
catch
    % The window may itself have failed; retain the original display error.
end
end
