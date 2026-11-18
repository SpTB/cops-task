function ex = showCoPsInstructionsx(ex,stage)
% Show and log one instruction page outside the recorded trial interval.
if nargin < 2, stage = 'welcome'; end
if ~ex.exp.CoPs.instrOn, return; end
stage = validatestring(stage,{'welcome','dynamic','ready'});
ex.exp.CoPs.pay = resolveCoPsPayx(ex.exp.CoPs.pay);
ctl = struct();
if isfield(ex.exp.CoPs,'ctl'), ctl = ex.exp.CoPs.ctl; end
info = getCoPsTrialBlockInfox(ex);
nPaidTrials = info.totalN-info.instructionN;
[body,prompt,cap] = formatCoPsInstructionTextx(ex.exp.CoPs.pay,stage,ctl,nPaidTrials);
window = ex.setup.window;
oldSize = Screen('TextSize',window);
oldStyle = Screen('TextStyle',window);
cleanup = onCleanup(@() restoreTextLocal(window,oldSize,oldStyle)); %#ok<NASGU>
page = struct('stage',stage,'body',body,'prompt',prompt, ...
    'max_bonus_dollar',cap.maxBonusDollars, ...
    'hourly_max_bonus_dollar',ex.exp.CoPs.pay.max_bonus_dollar, ...
    'trials_per_hour',ex.exp.CoPs.pay.trials_per_hour,'planned_paid_trials',nPaidTrials, ...
    'on',NaN,'off',NaN,'acknowledged',false,'questionRequests',struct('time',{},'target',{}));
refreshCoPsPreviewWindowx(ex.setup);
drawPage();
page.on = Screen('Flip',window);
allowCalibration = isfield(ex.setup,'inputMode') && ismember(ex.setup.inputMode,{'eyelink','eye'});
[quitRequested,page.questionRequests,recalibrate] = waitCoPsSpacex( ...
    ex.setup,@redrawPage,@() notifyCoPsQuestionx(ex),allowCalibration);
if recalibrate
    ex = requestCoPsRecalibrationx(ex,ex.j,['instructions:' stage]);
end
Screen('FillRect',window,ex.idx.bg_lum);
drawCoPsIdleSyncx(ex);
refreshCoPsPreviewWindowx(ex.setup);
page.off = Screen('Flip',window);
page.acknowledged = ~quitRequested;
if ~isfield(ex,'Instructions') || strcmp(stage,'welcome')
    ex.Instructions = page; % preserve the original welcome-page fields
    ex.Instructions.pages = page;
else
    ex.Instructions.pages(end+1) = page;
end
if quitRequested, ex.quit = 4; end

    function redrawPage
        drawPage();
        Screen('Flip',window);
    end

    function drawPage
        r = ex.setup.screenRect;
        width = r(3)-r(1); height = r(4)-r(2);
        margin = round(0.08*min(width,height));
        textRect = [r(1)+margin r(2) r(3)-margin r(4)];
        sizePx = max(12,min(36,floor(height/28)));
        % Measure on the backbuffer and shrink before presenting, if needed.
        while true
            Screen('FillRect',window,ex.idx.bg_lum);
            Screen('TextSize',window,sizePx);
            Screen('TextStyle',window,0);
            wrap = max(20,floor((width-2*margin)/(sizePx*0.6)));
            [~,~,bodyBox] = DrawFormattedText(window,body,'center',r(2),ex.idx.white,wrap,[],[],1.25,[],textRect);
            Screen('TextStyle',window,1);
            [~,~,promptBox] = DrawFormattedText(window,prompt,'center',r(2),ex.idx.white,[],[],[],1.25,[],textRect);
            bodyHeight = bodyBox(4)-bodyBox(2);
            promptHeight = promptBox(4)-promptBox(2);
            totalHeight = bodyHeight+2*sizePx+promptHeight;
            if (totalHeight <= height-2*margin && ...
                    max(bodyBox(3)-bodyBox(1),promptBox(3)-promptBox(1)) <= width-2*margin) || sizePx <= 12
                break
            end
            sizePx = sizePx-1;
        end
        Screen('FillRect',window,ex.idx.bg_lum);
        top = r(2)+(height-totalHeight)/2;
        Screen('TextStyle',window,0);
        DrawFormattedText(window,body,'center',top-bodyBox(2)+r(2),ex.idx.white,wrap,[],[],1.25,[],textRect);
        Screen('TextStyle',window,1);
        DrawFormattedText(window,prompt,'center',top+bodyHeight+2*sizePx-promptBox(2)+r(2),ex.idx.white,[],[],[],1.25,[],textRect);
        Screen('TextStyle',window,0);
        drawCoPsIdleSyncx(ex);
    end
end

function restoreTextLocal(window,oldSize,oldStyle)
Screen('TextSize',window,oldSize);
Screen('TextStyle',window,oldStyle);
end
