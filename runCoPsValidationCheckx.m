function validation = runCoPsValidationCheckx(ex, outputDir)
% Six ordinary validation trials using the same frozen manual calibration.
% Centre, the four outer corners of validation grid 1, then centre again.
% Called from runEx('t', calibrationValidationCheck=true), not standalone.

frozenEyeCal = ex.eyeCal;
edge = max(abs(ex.valid.offsetsDeg(:))) * ex.valid.distance_scaling;
corners = edge * [-1 -1; 1 -1; -1 1; 1 1];
offsetsDeg = [0 0; corners(randperm(4), :); 0 0];
offsetsPx = round(visualDegToPx(offsetsDeg, ex.setup));
ex.fix.duration = ex.valid.fixDur;
ex.reward.time = ex.valid.rewTime;
ex.stim.type = 'blank';
ex.targ.WinW = ex.valid.targetWin(1);
ex.targ.WinH = ex.valid.targetWin(2);
ex.targ.Pos(2, :) = [1000 1000];
ex.valid.recenterFirst = false;
ex.valid.onlineUpdate = false;
ex.valid.update = false;
ex.valid.freezeCalibration = true; % also disables the Z+X recenter shortcut
ex.valid.plot = false;
ex.valid.plot_summary = false;
ex.j = 1;
ex.goodtrial = 0;
ex.quit = 0;
ex.finish = size(offsetsPx, 1);
ex.loopcnt = zeros(1, ex.finish);
if isfield(ex, 'Trials'), ex = rmfield(ex, 'Trials'); end
ex.Header.onlineDirName = outputDir;
ex.Header.onlineFileName = 'validation.mat';
ex.Header.fileID = fix(clock);
validation = struct('status', 'running', 'file', fullfile(outputDir, 'validation.mat'), ...
    'targetOffsetsDeg', offsetsDeg, 'targetOffsetsPx', offsetsPx, ...
    'frozenEyeCal', frozenEyeCal, 'nTrials', 0, 'summary', table());
save(validation.file, 'ex', 'validation');
fprintf('\nSix normal validation trials follow, with normal rewards.\n');
fprintf('Calibration stays fixed. Keep MATLAB focused; F4 stops the check.\n');
sendStrobes([ex.strobe.FILE_ID, ex.Header.fileID, ex.strobe.EXPERIMENT_START]);
try
    for k = 1:ex.finish
        HideCursor;
        resetAdcBuffer(ex);
        ex.targ.Pos(1, :) = offsetsPx(k, :);
        fprintf('Validation check %d/%d: target [%g %g] degrees.\n', ...
            k, ex.finish, offsetsDeg(k, 1), offsetsDeg(k, 2));
        ex = runTrialFixTargx(ex);
        validation.nTrials = numel(ex.Trials);
        assert(isequaln(ex.eyeCal, frozenEyeCal), 'CoPs:DiagnosticCalibrationChanged', ...
            'Calibration changed during the diagnostic; this trial is not a frozen-fit comparison.');
        validation.summary = summarizeCoPsValidationCheckx(ex);
        writetable(validation.summary, fullfile(outputDir, 'validation_summary.csv'));
        save(validation.file, 'ex', 'validation');
        if ex.quit ~= 0, break; end
        WaitSecs(ex.valid.iti);
    end
    validation.status = 'aborted';
    if ex.quit == 0 && validation.nTrials == size(offsetsPx, 1)
        validation.status = 'complete';
    end
    save(validation.file, 'ex', 'validation');
catch err
    validation.status = 'error';
    validation.error = struct('identifier', err.identifier, 'message', err.message);
    save(validation.file, 'ex', 'validation');
    rethrow(err)
end
fprintf('Validation diagnostic %s: %d trials saved.\n', validation.status, validation.nTrials);
end
