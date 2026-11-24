function results = runCoPsCalibrationTransitionCheckx(ex)
% Compare a frozen calibration before/after the normal EyeLink file restart.
% Called by runEx('t', calibrationTransitionCheck=true) after manual fitting.
% K accepts the last 250 ms after at least one second of fresh data.
% ESC/F4 cancels the centre checks. Optional validation uses normal rewards.

if Eyelink('IsConnected') ~= 1
    error('CoPs:TransitionTrackerDisconnected', 'The EyeLink must be connected.');
end
root = fileparts(mfilename('fullpath'));
outputDir = fullfile(root, 'test_data', 'output', 'calibration_transition', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS')));
mkdir(outputDir);
results = struct('outputDir', outputDir, 'status', 'started', ...
    'frozenEyeCal', ex.eyeCal, 'setup', ex.setup, 'fix', ex.fix, ...
    'calib', ex.calib, 'valid', ex.valid, 'before', [], 'after', [], ...
    'windowSec', 0.25, 'edfFile', '', 'restartGetSecs', [], ...
    'restartReturnCodes', [], 'summary', table());
for name = {'runEx', 'calibrateEye2vx', 'checkEyexx', 'initEyelink', ...
        'resetAdcBuffer', 'runTrialFixTargx', 'makeStimulus', 'closeStimulus'}
    results.sources.(name{1}) = which(name{1});
end
% Use the same background, target, mapping and ADC reader on both sides.
ex.calib.background_color = ex.valid.background_color;
cleanup = onCleanup(@finishCapture); %#ok<NASGU>
save(fullfile(outputDir, 'check.mat'), 'results');
fprintf('\nCentre check: K while fixating centre; ESC/F4 cancels.\n');
fprintf('The fitted calibration stays fixed. Output: %s\n', outputDir);
try
    results.before = captureCentre(ex, 'BEFORE restart', results.windowSec);
    results.status = 'before_saved';
    save(fullfile(outputDir, 'check.mat'), 'results');
    if results.before.accepted
        % Match the existing manual-calibration -> validation transition.
        % The centre target remains on the screen throughout the restart.
        results.restartGetSecs(1) = GetSecs;
        Eyelink('SetOfflineMode');
        Eyelink('CloseFile');
        results.edfFile = sprintf('c%07x.edf', mod(floor(GetSecs * 1000), 2^28));
        openStatus = Eyelink('OpenFile', results.edfFile);
        results.restartReturnCodes = openStatus;
        if openStatus ~= 0
            error('CoPs:TransitionOpenFile', 'EyeLink OpenFile returned %g.', openStatus);
        end
        Eyelink('Message', 'CoPs calibration transition check');
        startStatus = Eyelink('StartRecording');
        results.restartReturnCodes(2) = startStatus;
        if startStatus ~= 0
            error('CoPs:TransitionStartRecording', 'EyeLink StartRecording returned %g.', startStatus);
        end
        results.restartGetSecs(2) = GetSecs;
        save(fullfile(outputDir, 'check.mat'), 'results');
        results.after = captureCentre(ex, 'AFTER restart', results.windowSec);
        results.status = 'aborted';
        if results.after.accepted
            results.status = 'complete';
            results.summary = compareWindows(results.before, results.after);
            writetable(results.summary, fullfile(outputDir, 'summary.csv'));
            disp(results.summary);
            save(fullfile(outputDir, 'check.mat'), 'results');
            if isfield(ex.calib, 'validationCheck') && ex.calib.validationCheck
                ex.Header.edfFileName = results.edfFile;
                results.validation = runCoPsValidationCheckx(ex, outputDir);
                results.status = results.validation.status;
            end
        end
    else
        results.status = 'aborted';
    end
    save(fullfile(outputDir, 'check.mat'), 'results');
catch err
    results.status = 'error';
    results.error = struct('identifier', err.identifier, 'message', err.message);
    save(fullfile(outputDir, 'check.mat'), 'results');
    rethrow(err)
end
clear cleanup
if ~isempty(results.edfFile)
    received = Eyelink('ReceiveFile', results.edfFile, outputDir, 1);
    results.edfReceivedBytes = received;
    save(fullfile(outputDir, 'check.mat'), 'results');
end
end

function phase = captureCentre(ex, label, windowSec)
fprintf('\n%s: look at centre, then press K (minimum 1 s).\n', label);
KbName('UnifyKeyNames');
acceptKey = KbName('k');
escape = KbName('ESCAPE');
f4 = KbName('F4');
trEye = struct('v', zeros(numel(ex.setup.adc.Channels), 0), ...
    't', zeros(1, 0), 'n', 0);
nEyes = 1 + double(~isempty(ex.eyeCal.LXPos));
lastEyePos = nan(nEyes, 2);
phase = struct('label', label, 'accepted', false, 'stopReason', '', ...
    'startGetSecs', GetSecs, 'endGetSecs', NaN, 'Eye', [], ...
    'windowIndices', [], 'windowSummary', table());
% A held key cannot accept the next phase, and buffered samples are discarded.
keyReleased = false;
resetAdcBuffer(ex);
while GetSecs - phase.startGetSecs < 60
    [~, trEye, lastEyePos] = checkEyexx(trEye, ex, [], 0, lastEyePos, 0);
    drawCentre(ex, lastEyePos);
    [~, ~, keys] = KbCheck;
    if keys(escape) || keys(f4)
        phase.stopReason = 'operator_cancelled';
        break
    end
    if ~keys(acceptKey)
        keyReleased = true;
    elseif keyReleased
        % Require a complete new observation, not the previous target's data.
        keyReleased = false;
        if trEye.n > 0 && trEye.t(end) - trEye.t(1) >= 1
            phase.accepted = true;
            phase.stopReason = 'operator_accepted';
            break
        end
    end
end
if isempty(phase.stopReason), phase.stopReason = 'timeout'; end
phase.endGetSecs = GetSecs;
phase.Eye = trEye;
if trEye.n > 0
    phase.windowIndices = find(trEye.t >= trEye.t(end) - windowSec);
end
if phase.accepted && numel(phase.windowIndices) >= 20
    phase.windowSummary = summarizeWindow(ex, trEye.v(:, phase.windowIndices));
elseif phase.accepted
    phase.accepted = false;
    phase.stopReason = 'insufficient_samples';
end
end

function drawCentre(ex, eyePos)
clearCoPsCalibrationBackgroundx(ex, ex.valid.background_color);
if ~isempty(ex.setup.overlay) && all(isfinite(eyePos(:)))
    dots = [eyePos; mean(eyePos, 1)]';
    colour = ex.idx.overlay;
    if isscalar(colour), colour = repmat(colour, 3, size(dots, 2)); end
    Screen('DrawDots', ex.setup.overlay, dots, ex.setup.eyePSz / 2, colour, [], 2);
end
buffers = 0;
if ex.setup.stereo.Display, buffers = 0:1; end
for eye = buffers
    if ex.setup.stereo.Display
        Screen('SelectStereoDrawBuffer', ex.setup.window, eye);
    end
    Screen('DrawDots', ex.setup.window, ex.fix.PCtr(:), ex.calib.Psz, ex.idx.white);
end
Screen('Flip', ex.setup.window);
end

function summary = summarizeWindow(ex, v)
% Eye.v uses exactly the task's convention: horizontal sign already applied.
labels = {'RX'; 'RY'; 'LX'; 'LY'};
rows = [1 2 4 5];
if isempty(ex.eyeCal.LXPos), labels = labels(1:2); rows = rows(1:2); end
count = numel(rows);
medianV = nan(count, 1); sdV = medianV; errorPx = medianV; sdPx = medianV;
for k = 1:count
    prefix = labels{k};
    delta = ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).([prefix '0']);
    samples = v(rows(k), :);
    medianV(k) = median(samples, 'omitnan');
    sdV(k) = std(samples, 'omitnan');
    errorPx(k) = (medianV(k) - ex.eyeCal.([prefix '0']) - delta) * ex.eyeCal.([prefix 'Gain']);
    sdPx(k) = sdV(k) * abs(ex.eyeCal.([prefix 'Gain']));
end
summary = table(labels, medianV, sdV, errorPx, sdPx, ...
    'VariableNames', {'channel', 'medianV', 'sdV', 'centreErrorPx', 'sdPx'});
end

function summary = compareWindows(before, after)
a = before.windowSummary; b = after.windowSummary;
summary = table(a.channel, a.medianV, b.medianV, b.medianV - a.medianV, ...
    a.centreErrorPx, b.centreErrorPx, b.centreErrorPx - a.centreErrorPx, a.sdPx, b.sdPx, ...
    'VariableNames', {'channel', 'beforeV', 'afterV', 'changeV', ...
    'beforeErrorPx', 'afterErrorPx', 'changePx', 'beforeSDPx', 'afterSDPx'});
end

function finishCapture()
try
    Eyelink('StopRecording');
    Eyelink('SetOfflineMode');
    Eyelink('CloseFile');
catch
end
try
    Datapixx('StopAdcSchedule');
    Datapixx('RegWrRd');
catch
end
end
