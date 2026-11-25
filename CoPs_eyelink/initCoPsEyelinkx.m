function ex = initCoPsEyelinkx(ex)
% initialize native display-pixel and run th tracker calibration UI
elConfig = ex.setup.el;
[initialized,dummy] = EyelinkInit();
if ~initialized
    error('initCoPsEyelinkx:Connection', 'Eyelink cannot be initalized');
end
if dummy
    Eyelink('Shutdown');
    error('initCoPsEyelinkx:DummyMode', ...
        'Ordinary CoPs runs require a real EyeLink connection. Use runEx(''mouse_mini'') for mouse simulation.');
end
ex.setup.el = EyelinkInitDefaults(ex.setup.window);
ex.setup.el.edfFileName = elConfig.edfFileName;
ex.setup.el.binoc = elConfig.binoc;
ex.setup.el.Cmd_SampleData = elConfig.Cmd_SampleData;
ex.setup.el.backgroundcolour = ex.idx.bg_lum;
% EyeLink tone vectors are [frequencyHz amplitude durationSecs]. Keep their
% pitches/durations, with a gain comparable to the task cue (default 0.1).
beepVolume = 0.1;
if isfield(elConfig, 'calibrationBeepVolume')
    beepVolume = elConfig.calibrationBeepVolume;
end
validateattributes(beepVolume, {'double'}, {'scalar','real','finite','>=',0,'<=',1});
ex.setup.el.calibrationBeepVolume = beepVolume;
beepFields = {'cal_target_beep', 'drift_correction_target_beep', ...
    'calibration_failed_beep', 'calibration_success_beep', ...
    'drift_correction_failed_beep', 'drift_correction_success_beep'};
for i = 1:numel(beepFields)
    ex.setup.el.(beepFields{i})(2) = beepVolume;
end
if isfield(ex.setup, 'keyboards') && ex.setup.keyboards.separate
    ex.setup.el.devicenumber = ex.setup.keyboards.experimenterIndex;
    [~, ~, ex.setup.el.lastKeyCodes] = KbCheck(ex.setup.el.devicenumber);
end
% Pass display, tone, and keyboard settings to callback-based tracker setup.
% EyelinkUpdateDefaults can auto-open a protected calibration audio stream;
% updating the callback directly preserves the normal Snd audio lifecycle.
if ~isempty(ex.setup.el.callback)
    if strcmp(ex.setup.el.callback, 'PsychEyelinkDispatchCallback')
        % PTB caches tone waveforms; regenerate them for this session's gain.
        clear PsychEyelinkDispatchCallback
    end
    feval(ex.setup.el.callback, ex.setup.el);
end
Eyelink('SetofflineMode');
rect = ex.setup.screenRect;
coords = [0 0 rect(3)-rect(1)-1 rect(4)-rect(2)-1];
Eyelink('Command', sprintf('screen_pixel_coords = %d %d %d %d', coords));
Eyelink('Command', 'calibration_type = HV9');
% keep the tasks existing 500hz polling/fixation cadence
if Eyelink('Command', 'sample_rate = 500') ~=0
    error ('initCoPsEyelinkx:SampleRate', 'Eyelink could not set the 500 Hz sample rate');
end
Eyelink('Command', elConfig.Cmd_SampleData);
Eyelink('Command', 'file_sample_data = LEFT,RIGHT,GAZE,AREA,INPUT,HTARGET');
if Eyelink('OpenFile', elConfig.edfFileName) ~= 0
    error('initCoPsEyelinkx:File', 'Cannot open the Eyelink EDF file.');
end
Eyelink('Message', sprintf('DISPLAY_COORDS %d %d %d %d', coords));
setupStatus = EyelinkDoTrackerSetup(ex.setup.el);
if setupStatus ~=0
    error('InitCoPsEyelinkx:Calibration', 'Eyelink tracker setup did not complete.');
end
[calResult, calMessage] = Eyelink('CalMessage');
ex.eyeCal = makeCoPsNativeEyeCalx(ex.setup, setupStatus, ...
    calResult, calMessage, GetSecs);
if Eyelink('StartRecording') ~= 0
    error('initCoPsEyelinkx:Recording', 'Eyelink recording did not start');
end

WaitSecs(0.1);
ex.setup.eyeTracker = 'Eyelink';
end

