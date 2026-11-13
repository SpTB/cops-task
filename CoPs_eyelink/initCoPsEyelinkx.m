function ex = initCoPsEyelinkx(ex)
% initialize native display-pixel and run th tracker calibration UI
elConfig = ex.setup.el;
if ~EyelinkInit()
    error('initCoPsEyelinkx:Connection', 'Eyelink cannot be initalized');
end
ex.setup.el = EyelinkInitDefaults(ex.setup.window);
ex.setup.el.edfFileName = elConfig.edfFileName;
ex.setup.el.binoc = elConfig.binoc;
ex.setup.el.Cmd_SampleData = elConfig.Cmd_SampleData;
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
if EyelinkDoTrackerSetup(ex.setup.el) ~=0
    error('InitCoPsEyelinkx:Calibration', 'Eyelink tracker setup did not complete.');
end
if Eyelink('StartRecording') ~= 0
    error('initCoPsEyelinkx:Recording', 'Eyelink recording did not start');
end

WaitSecs(0.1);
ex.setup.eyeTracker = 'Eyelink';
% retained for legacy display/metadata consumers; native gaze bypasses
% gains
ex.eyeCal = makeCoPsMouseEyeCalx();
end

