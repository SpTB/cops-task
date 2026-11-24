function [quitRequested,requests,recalibrate,repeatPractice] = waitCoPsSpacex(setup, redraw, onQuestion, allowCalibration, requireFreshQuit, allowRepeat)
% Pause controls: participant SPACE/Q, operator F4/F6. Require fresh presses.
if nargin < 3, onQuestion = []; end
if nargin < 4, allowCalibration = false; end
if nargin < 5, requireFreshQuit = false; end
if nargin < 6, allowRepeat = false; end
requests = struct('time',{},'target',{});
notificationCleanup = []; %#ok<NASGU> Keep the latest popup alive until this screen ends.
notificationPoll = [];
KbName('UnifyKeyNames');
quitKey = KbName('F4');
calibrationKey = [];
if allowCalibration, calibrationKey = KbName('F6'); end
questionDown = false;
enterDown = false;
if allowRepeat
    [keys,spaceDown,~,questionDown,enterDown] = readCoPsKeyboardx(setup);
elseif isempty(onQuestion)
    [keys,spaceDown] = readCoPsKeyboardx(setup);
else
    [keys,spaceDown,~,questionDown] = readCoPsKeyboardx(setup);
end
questionReady = ~questionDown;
quitReady = ~requireFreshQuit || ~any(keys(quitKey));
calibrationReady = ~any(keys(calibrationKey));
waitingForCalibrationRelease = false;
spaceReady = ~spaceDown;
waitingForSpaceRelease = false;
quitRequested = false;
recalibrate = false;
repeatPractice = false;
enterReady = ~enterDown;
waitingForEnterRelease = false;
while true
    if refreshCoPsPreviewWindowx(setup), redraw(); end
    if allowRepeat
        [keys,spaceDown,~,questionDown,enterDown] = readCoPsKeyboardx(setup);
    elseif isempty(onQuestion)
        [keys,spaceDown] = readCoPsKeyboardx(setup);
    else
        [keys,spaceDown,~,questionDown] = readCoPsKeyboardx(setup);
    end
    if ~isempty(notificationPoll), notificationPoll(); end
    % Psychtoolbox polls keyboard state independently of desktop focus.
    % A window-manager focus report must not disable pause controls.
    if ~any(keys(quitKey))
        quitReady = true;
    elseif quitReady
        quitRequested = true;
        return
    end
    if ~isempty(onQuestion)
        if questionDown && questionReady
            % Close the old alert before opening another one. Screen handles
            % can be reused when an experimenter closes a popup manually.
            notificationPoll = [];
            notificationCleanup = []; %#ok<NASGU>
            [request,notificationCleanup,notificationPoll] = onQuestion(); %#ok<NASGU>
            requests(end+1) = request; %#ok<AGROW>
            questionReady = false;
            spaceReady = false;
            waitingForSpaceRelease = false;
            calibrationReady = false;
            waitingForCalibrationRelease = false;
            enterReady = false;
            waitingForEnterRelease = false;
        elseif ~questionDown
            questionReady = true;
        end
    end
    if allowCalibration
        calibrationDown = any(keys(calibrationKey));
        if ~calibrationDown
            if waitingForCalibrationRelease
                recalibrate = true;
                return
            end
            calibrationReady = true;
        elseif calibrationReady
            waitingForCalibrationRelease = true;
        end
        if waitingForCalibrationRelease
            WaitSecs('YieldSecs',0.01);
            continue
        end
    end
    if allowRepeat
        if ~enterDown
            if waitingForEnterRelease
                repeatPractice = true;
                return
            end
            enterReady = true;
        elseif enterReady
            waitingForEnterRelease = true;
        end
        if waitingForEnterRelease
            WaitSecs('YieldSecs',0.01);
            continue
        end
    end
    if ~spaceDown
        if waitingForSpaceRelease, return; end
        spaceReady = true;
    elseif spaceReady
        waitingForSpaceRelease = true;
    end
    WaitSecs('YieldSecs',0.01);
end
end
