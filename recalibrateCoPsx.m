function ex = recalibrateCoPsx(ex)
% Repeat calibration/validation without replacing task trials or the task EDF.
request = ex.Recalibration.pending;
entry = struct('requestedAt',request.requestedAt,'nextTrial',request.nextTrial, ...
    'source',request.source,'on',GetSecs,'off',NaN,'completed',false, ...
    'eyeCalBefore',ex.eyeCal,'eyeCalAfter',[],'errorIdentifier','','errorMessage','');
ex.Recalibration.pending = [];
randomState = rng;
randomCleanup = onCleanup(@() rng(randomState)); %#ok<NASGU>
try
    mode = ex.setup.inputMode;
    switch mode
        case 'eyelink'
            % Keep the session EDF open. Tracker setup runs offline; validation
            % and subsequent trials append to the same recording.
            Eyelink('Message','COPS_RECALIBRATION_BEGIN NEXT_TRIAL %d',request.nextTrial);
            Eyelink('StopRecording');
            Eyelink('SetOfflineMode');
            el = ex.setup.el;
            % Reward audio owns the device during the task. Calibration visuals
            % remain active, without opening a second audio device for its tones.
            el.targetbeep = 0;
            el.feedbackbeep = 0;
            EyelinkUpdateDefaults(el);
            status = EyelinkDoTrackerSetup(el);
            if status ~= 0
                error('CoPs:RecalibrationSetup','EyeLink tracker setup failed (status %g).',status);
            end
            [result,message] = Eyelink('CalMessage');
            calibration = ex;
            calibration.setup.el.edfFileName = ex.Header.edfFileName;
            calibration.eyeCal = makeCoPsNativeEyeCalx(calibration.setup,status,result,message,GetSecs);
            % These validation snapshots reference the session EDF; never close
            % or receive that file through saveCoPsNativeEyeCalx(closeEdf=true).
            calibration.eyeCal.native.edfFile = fullfile(ex.Header.onlineEdfDirName,ex.Header.edfFileName);
            calibration.eyeCal.native.edfSharedWithSession = true;
            calibration = saveCoPsNativeEyeCalx(calibration);
            if Eyelink('StartRecording') ~= 0
                error('CoPs:RecalibrationRecording','EyeLink recording did not restart.');
            end
            WaitSecs(0.1);
            calibration = validateCoPsNativeEyelinkx(calibration);
            ex.eyeCal = calibration.eyeCal;
            if calibration.quit == 4 || ~ex.eyeCal.validation.completed
                ex.quit = 4;
            else
                entry.completed = true;
            end
            Eyelink('Message','COPS_RECALIBRATION_END COMPLETED %d',entry.completed);
        case 'eye'
            % The legacy routine replaces counters, Trials and file metadata.
            % Run on a copy and return only its calibration, keeping its own
            % validation trials in the EyeCal MAT, outside task scoring.
            calibration = ex;
            calibration.setup.inTaskRecalibration = true;
            calibration.calib.file = '';
            calibration.calib.validate = true;
            calibration.eyeCal = [];
            calibration = calibrateEye2vx(calibration);
            ex.eyeCal = calibration.eyeCal;
            ex.quit = calibration.quit;
            entry.completed = ex.quit ~= 4;
        otherwise
            error('CoPs:RecalibrationInput','Gaze calibration requires eye input; current mode is %s.',mode);
    end
    if ~ex.setup.el.binoc
        ex.eyeCal.LX0 = []; ex.eyeCal.LY0 = [];
        ex.eyeCal.LXGain = []; ex.eyeCal.LYGain = [];
    end
    if ex.quit == 4, entry.completed = false; end
catch err
    % Return the completed trial data and the failed attempt to runEx for saving.
    % Never start another trial after an incomplete hardware setup.
    ex.quit = 4;
    entry.completed = false;
    entry.errorIdentifier = err.identifier;
    entry.errorMessage = err.message;
    warning('CoPs:RecalibrationFailed','Calibration/validation failed; ending session: %s',err.message);
end
entry.off = GetSecs;
entry.eyeCalAfter = ex.eyeCal;
if ~isfield(ex.Recalibration,'history') || isempty(ex.Recalibration.history)
    ex.Recalibration.history = entry;
else
    ex.Recalibration.history(end+1) = entry;
end
if entry.completed
    fprintf('Calibration + validation complete. Continuing with trial %d.\n',request.nextTrial);
end
end
