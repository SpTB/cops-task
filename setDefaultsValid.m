function valid = setDefaultsValid()

valid = struct();
valid.nRepeat = 1;
valid.passes = 1%[1,2]; % native validation: 2 = offsetsDeg2 only; [1 2] = both grids
valid.targetWin = [3.5 3.5]; % 3.166152 visual degrees; old [160 160] px at 38.5 cm
valid.targetWinUnits = 'Deg';
valid.targetWin2 = [2.0 2.0]; % 2.177898 visual degrees; old [110 110] px at 38.5 cm
valid.targetWin2Units = 'Deg';
valid.fixDur = .35; % fixation duration
valid.rewTime = .25; %   
valid.background_color = 80;%128; % 
valid.offsetsDeg = [-8:4:8];
valid.offsetsDeg2 = [-11.5:5.75:11.5]; % second validation grid; [] reuses offsetsDeg
% also use the scaling par instead (below)
valid.distance_scaling = 1;
valid.iti = .1;
valid.plot = 0;
valid.plot_summary = 1;
valid.showMouseTrace = false; % show mouse-position overlay during validation
valid.recenterFirst = 0; % recenters on first validation trial
valid.onlineUpdate = 0; % apply validation updates during validation (seems to work w/Kaki, but no Lychee)
valid.update = 0; % 1: refit after validation (native: separate pixel correction; analog: gains/offsets)
valid.img=''%'/home/vpixx/Downloads/butt.jpg';
%valid.img = '/home/vpixx/Downloads/rhe1.jpg'; % reuses calib setting
valid.rotSpeedDegPerSec = 0;%120; % reuses calib setting, but can be set
%independently as well

end
