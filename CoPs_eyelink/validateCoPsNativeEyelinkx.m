function ex = validateCoPsNativeEyelinkx(ex)
% Validate the tracker's pixel gaze with the legacy setDefaultsValid grids.
% Optional valid.update fits a separate CoPs pixel correction after collection.
ex = resolveCalibrationValidationDisplaySizes(ex);
val = ex.valid;
if val.onlineUpdate || val.recenterFirst
    error('CoPs:NativeValidationUpdate', ...
        'Native validation supports an end-of-run update; onlineUpdate and recenterFirst must be false.');
end
validateattributes(val.fixDur, {'numeric'}, {'scalar','finite','>=',.15});
validateattributes(val.nRepeat, {'numeric'}, {'scalar','integer','positive'});
plan = makeCoPsNativeValidationPlanx(ex);
validation = struct('source', 'eyelink', 'mode', 'measureOnly', ...
    'settings', val, 'plan', plan, 'completed', false, ...
    'Trials', struct([]), 'summary', struct([]));
ex.eyeCal.validation = validation;
% Validation stores native gaze only; ADC is reserved for task sync signals.
inputEx = ex;
inputEx.setup.dependencies.adcOn = false;
if isfield(inputEx.eyeCal,'correction')
    inputEx.eyeCal.correction.enabled = false;
end
texture = [];
if ~isempty(val.img)
    texture = Screen('MakeTexture', ex.setup.window, imread(val.img));
end
cleanup = onCleanup(@() cleanupLocal(ex, texture)); %#ok<NASGU>
HideCursor;
fprintf('Native EyeLink validation: %d targets. F4 or Escape stops.\n', numel(plan));
for i = 1:numel(plan)
    if ex.quit == 4, break; end
    Trial = runPointLocal(inputEx, plan(i), texture);
    summary = summarizeCoPsNativeValidationx(Trial, ex.setup, ex.fix.PCtr);
    if i == 1
        ex.eyeCal.validation.Trials = Trial;
        ex.eyeCal.validation.summary = summary;
    else
        ex.eyeCal.validation.Trials(i) = Trial;
        ex.eyeCal.validation.summary(i) = summary;
    end
    if Trial.aborted
        ex.quit = 4;
    end
    % Save every point, including failures/aborts, before advancing.
    ex = saveCoPsNativeEyeCalx(ex);
    fprintf('Validation %d/%d: pass %d, fixation %d\n', ...
        i, numel(plan), Trial.pass, Trial.Reward);
    WaitSecs(val.iti);
end
ex.eyeCal.validation.completed = ex.quit ~= 4 && ...
    numel(ex.eyeCal.validation.Trials) == numel(plan);
if val.update && ex.eyeCal.validation.completed
    ex.eyeCal.correction = fitCoPsNativeEyeCorrectionx( ...
        ex.eyeCal.validation.summary, ex.fix.PCtr);
    ex.eyeCal.validation.mode = 'fitCorrection';
    fprintf('CoPs pixel correction fitted for %d of 4 eye axes. Raw EyeLink samples are preserved.\n', ...
        nnz(ex.eyeCal.correction.fitted));
end
ex = saveCoPsNativeEyeCalx(ex);
if val.plot_summary && ~isempty(ex.eyeCal.validation.summary)
    plotSummaryLocal(ex.eyeCal.validation.summary);
end
end

function Trial = runPointLocal(ex, point, texture)
val = ex.valid;
drawLocal(ex, point.targetPx, texture, 0, zeros(0,2));
onset = Screen('Flip', ex.setup.window);
presentCoPsOverlayx(ex);
before = GetSecs;
trackerStart = Eyelink('TrackerTime'); % already seconds
after = GetSecs;
E = struct('v', zeros(6,0), 't', zeros(1,0), 'n', 0, 'sacc', [], ...
    'source', 'eyelink', 'units', 'pixels', 'timebase', 'eyelink_seconds', ...
    'trackerStart', trackerStart, 'ptbStart', (before+after)/2);
holdStart = NaN; holdEnd = NaN; lastSample = -Inf;
aborted = false;
lastDraw = onset;
rewardTime = NaN; rewardSize = 0;
Eyelink('Message', sprintf('COPS_VALIDATION_TARGET %d %d %.3f %.3f', ...
    point.pass, point.repeat, point.targetPx(1), point.targetPx(2)));
while GetSecs - onset < ex.fix.waitstop + val.fixDur
    nBefore = E.n;
    [~, E, P] = checkCoPsEyelinkx(E, ex, true, 1);
    if E.n > nBefore
        sampleAge = GetSecs - (E.ptbStart + E.t(end) - E.trackerStart);
        if sampleAge <= .1
            [holdStart, holdEnd, lastSample] = updateCoPsNativeValidationHoldx( ...
                E.v(:,nBefore+1:end), E.t(nBefore+1:end), ...
                point.targetPx, point.targetWinPx, val.fixDur, holdStart, lastSample);
        else
            holdStart = NaN;
            lastSample = E.t(end);
        end
    elseif GetSecs - (E.ptbStart + lastSample - E.trackerStart) > .1
        holdStart = NaN;
    end
    [down, ~, keys] = KbCheck;
    if down && (keys(KbName('F4')) || keys(KbName('ESCAPE')))
        aborted = true;
        holdEnd = NaN;
        break
    end
    if isfinite(holdEnd)
        if ex.setup.dependencies.rewOn
            % Always switch the valve off if interrupted during reward.
            rewardCleanup = onCleanup(@stopRewardLocal); %#ok<NASGU>
            rewardTime = GetSecs;
            Datapixx('SetDoutValues',1);
            Datapixx('RegWr');
            WaitSecs(val.rewTime);
            clear rewardCleanup
            rewardSize = val.rewTime;
        end
        break
    end
    if GetSecs - lastDraw >= 1/ex.setup.refreshRate
        drawLocal(ex, point.targetPx, texture, GetSecs-onset, P);
        Screen('Flip',ex.setup.window);
        presentCoPsOverlayx(ex);
        lastDraw = GetSecs;
    end
    WaitSecs('YieldSecs', .001);
end
Trial = struct('pass', point.pass, 'repeat', point.repeat, ...
    'targ', struct('Pos', point.targetOffsetPx), 'targetPx', point.targetPx, ...
    'targetWinPx', point.targetWinPx, 'TrialStart', onset, 'TrialEnd', GetSecs, ...
    'Eye', E, 'inputSource', 'eyelink', 'Reward', double(isfinite(holdEnd)), ...
    'RewardSize', rewardSize, 'aborted', aborted, ...
    'fixationCompleteTrackerSec', holdEnd);
Trial.times = struct('fpOn', onset, ...
    'startFixation', E.ptbStart + holdStart - E.trackerStart, ...
    'fixationComplete', E.ptbStart + holdEnd - E.trackerStart, ...
    'reward', rewardTime);
if val.plot
    figure('Name','Native EyeLink validation trace');
    plot(E.t - E.trackerStart, E.v([1 2 4 5],:)');
    xlabel('Tracker seconds from point start'); ylabel('Display pixels');
    legend('RX','RY','LX','LY'); drawnow;
end
Screen('FillRect', ex.setup.window, val.background_color);
Screen('Flip', ex.setup.window);
end

function drawLocal(ex, target, texture, elapsed, eyes)
Screen('FillRect', ex.setup.window, ex.valid.background_color);
if isempty(texture)
    Screen('DrawDots', ex.setup.window, target', ex.calib.Psz, ex.idx.white, [], 2);
else
    sizePx = ex.calib.Psz + 200; % legacy image target size
    rect = CenterRectOnPointd([0 0 sizePx sizePx], target(1), target(2));
    Screen('DrawTexture', ex.setup.window, texture, [], rect, ...
        mod(elapsed * ex.valid.rotSpeedDegPerSec, 360));
end
if isfield(ex.setup,'overlayIsSeparate') && ex.setup.overlayIsSeparate
    Screen('FillRect', ex.setup.overlay, ex.valid.background_color);
    Screen('DrawDots', ex.setup.overlay, target', ex.calib.Psz, ex.idx.white, [], 2);
    eyes = eyes(all(isfinite(eyes),2),:);
    if ~isempty(eyes)
        Screen('DrawDots', ex.setup.overlay, eyes', ex.setup.eyePSz, [255 0 0], [], 2);
    end
    if ex.valid.showMouseTrace
        [mx,my] = GetMouse(ex.setup.window);
        Screen('DrawDots', ex.setup.overlay, [mx;my], 3, [0 255 0], [], 2);
    end
end
end

function stopRewardLocal()
Datapixx('SetDoutValues',0);
Datapixx('RegWr');
end

function cleanupLocal(ex, texture)
if ~isempty(texture), Screen('Close',texture); end
Screen('FillRect',ex.setup.window,ex.valid.background_color);
Screen('Flip',ex.setup.window);
ShowCursor;
end

function plotSummaryLocal(summary)
target = vertcat(summary.targetDeg);
figure('Name','Native EyeLink validation');
for eye = 1:2
    gaze = arrayfun(@(s) s.gazeDeg(eye,:),summary,'UniformOutput',false);
    gaze = vertcat(gaze{:});
    err = arrayfun(@(s) s.radialErrorDeg(eye),summary);
    subplot(1,2,eye); hold on;
    plot(target(:,1),target(:,2),'ko');
    plot(gaze(:,1),gaze(:,2),'r.');
    axis equal; xlabel('X (deg)'); ylabel('Y (deg, down positive)');
    names = {'Right','Left'};
    title(sprintf('%s: mean error %.2f deg, max %.2f deg', ...
        names{eye}, mean(err,'omitnan'), max(err,[],'omitnan')));
    legend('Target','Native gaze');
end
drawnow;
end
