function calib = setDefaultsCalib()

calib = struct();
calib.Psz = 0.4; % visual degrees; old 22 px at 38.5 cm display width
calib.PszUnits = 'Deg';
calib.sampleDur = 0.25; % seconds of recent eye data averaged when accepting a calibration point
calib.sampleEstimator = 'median'; % 'mean' or 'median' for accepted calibration windows
calib.sampleRejectThresh = 100; % max within-window SD in calibrated screen pixels; Inf disables rejection
calib.plot = false; % plot eye traces after each point?
calib.signedGain = true; % false restores legacy abs(target)/abs(raw delta) gain
calib.distance_scaling = 1; % target locations
calib.initGain = 400; %'kaki':300; 'fullNew': 500
calib.avgain = 0; % whether to average gain vals across the two eyes
calib.yOffset = 0; % how much to add to RY0 and LY0 at the end
calib.background_color = 0; % 0: black, 255: white (useless)
calib.validate = 1; % whether to follow calibration with validation
calib.file ='/home/vpixx/Desktop/ly.mat' % only validates if file provided
%'/home/vpixx/data/lychee/2026.03.18/ly_15.33.EyeCal/ly_15.33.EyeCal.mat'
%'/home/vpixx/data/lychee/2026.03.13/ly_14.39.EyeCal/ly_14.39.EyeCal.mat'%'/home/vpixx/data/lychee/2026.03.11/ly_15.21.EyeCal/ly_15.21.EyeCal.mat'
%mouse:%'/home/vpixx/data/test/2026.03.09/t_12.19.EyeCal/t_12.19.EyeCal.mat' ;% path to calibration file (leave empty if want to run calibration)
%kaki: %'/home/vpixx/data/kaki/2026.03.11/ka_12.22.EyeCal/ka_12.22.EyeCal.mat' 
%lychee: ''
calib.img =''%'/home/vpixx/Downloads/rhe1.jpg'
calib.rotSpeedDegPerSec = 0;%120;%5;
end 
