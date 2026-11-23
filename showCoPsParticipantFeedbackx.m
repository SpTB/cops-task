function ex = showCoPsParticipantFeedbackx(ex)
% Optional text entry after the payout acknowledgement, outside trial timing.
if ~isCoPsParticipantFeedbackEnabledx(ex) || ...
        (isfield(ex.setup,'showEndScreen') && ~ex.setup.showEndScreen) || ...
        isCoPsMovieRecordingx(ex) || isfield(ex,'ParticipantFeedback')
    return
end
device = [];
if isfield(ex.setup,'keyboards') && ex.setup.keyboards.separate
    device = ex.setup.keyboards.participantIndex;
end
window = ex.setup.window;
color = ex.idx.bg_lum;
if ~isempty(ex.Trials) && isfield(ex.Trials,'betweenTrialBackgroundGray') && ...
        ~isempty(ex.Trials(end).betweenTrialBackgroundGray)
    color = ex.Trials(end).betweenTrialBackgroundGray;
end
prompt = sprintf(['What worked well? What was confusing, difficult, or uncomfortable?\n\n' ...
    'Did you notice anything about the task that wasn''t explicitly explained?']);
response = struct('prompt',prompt,'text','','submitted',false,'skipped',false, ...
    'on',NaN,'off',NaN,'keyboardDevice',device);
oldSize = Screen('TextSize',window);
textCleanup = onCleanup(@() restoreTextLocal(window,oldSize)); %#ok<NASGU>
KbName('UnifyKeyNames');
quitKey = KbName('F4');
[operatorKeys,~] = readCoPsKeyboardx(ex.setup);
quitReady = ~any(operatorKeys(quitKey));
[nextEvent,inputCleanup] = startCoPsFeedbackInputx(ex.setup); %#ok<NASGU>
refreshCoPsPreviewWindowx(ex.setup);
drawLocal(ex,color,response);
response.on = Screen('Flip',window);
done = false;
while ~done
    changed = refreshCoPsPreviewWindowx(ex.setup);
    [operatorKeys,~] = readCoPsKeyboardx(ex.setup);
    if ~any(operatorKeys(quitKey))
        quitReady = true;
    elseif quitReady
        response.skipped = true;
        break
    end
    event = nextEvent();
    if ~isempty(event) && event.Pressed
        key = event.CookedKey;
        if isfield(event,'QuitRequested') && event.QuitRequested
            if quitReady
                response.skipped = true;
                done = true;
            end
        elseif ismember(key,[10 13])
            response.submitted = true;
            done = true;
        elseif key == 27
            response.skipped = true;
            done = true;
        elseif ismember(key,[8 127])
            if ~isempty(response.text), response.text(end) = []; end
            changed = true;
        elseif key >= 32 && key <= 65535
            response.text(end+1) = char(key);
            changed = true;
        end
    end
    if changed && ~done
        drawLocal(ex,color,response);
        Screen('Flip',window);
    end
    if ~done, WaitSecs('YieldSecs',0.01); end
end
Screen('FillRect',window,color);
drawCoPsIdleSyncx(ex);
response.off = Screen('Flip',window);
ex.ParticipantFeedback = response;
end

function drawLocal(ex,color,response)
window = ex.setup.window;
r = Screen('Rect',window);
w = r(3)-r(1); h = r(4)-r(2);
sizePx = max(16,min(32,round(w/60)));
box = r([1 2 1 2]) + [0.12*w 0.43*h 0.88*w 0.81*h];
padding = sizePx;
Screen('FillRect',window,color);
Screen('TextSize',window,round(sizePx*1.4));
DrawFormattedText(window,'Participant feedback','center',r(2)+0.07*h,ex.idx.white);
Screen('TextSize',window,sizePx);
DrawFormattedText(window,[response.prompt sprintf('\nYour feedback is optional.')], ...
    box(1),r(2)+0.17*h,ex.idx.white,65);
Screen('FillRect',window,32,box);
Screen('FrameRect',window,ex.idx.white,box,2);
bounds = Screen('TextBounds',window,'W');
columns = max(1,floor((box(3)-box(1)-2*padding)/max(1,bounds(3)-bounds(1))));
rows = max(1,floor((box(4)-box(2)-2*padding)/(sizePx*1.5)));
lines = wrapLocal([response.text '|'],columns);
visible = strjoin(lines(max(1,end-rows+1):end),sprintf('\n'));
DrawFormattedText(window,visible,box(1)+padding,box(2)+padding,ex.idx.white,[],[],[],1.5);
DrawFormattedText(window,'ENTER: Submit and finish     ESC: Skip', ...
    'center',r(2)+0.88*h,ex.idx.white);
drawCoPsIdleSyncx(ex);
end

function lines = wrapLocal(text,columns)
% Wrap long words too; scroll only the display, retaining the complete response.
lines = {};
while numel(text) > columns
    split = find(text(1:columns)==' ',1,'last');
    if isempty(split), split = columns; end
    lines{end+1} = text(1:split); %#ok<AGROW>
    text = text(split+1:end);
end
lines{end+1} = text;
end

function restoreTextLocal(window,sizePx)
try
    Screen('TextSize',window,sizePx);
catch
    % Preserve the original error if the display has closed.
end
end
