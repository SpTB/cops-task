function eyeCal = makeCoPsMouseEyeCalx()
% Minimal calibration-shaped value for configurations using mouse input.
%
% Mouse coordinates are already in screen pixels, so these gains and
% offsets are compatibility metadata rather than a coordinate transform.

eyeCal = struct();
eyeCal.RX0 = 0;
eyeCal.RY0 = 0;
eyeCal.LX0 = [];
eyeCal.LY0 = [];
eyeCal.RXPos = [];
eyeCal.RYPos = [];
eyeCal.LXPos = [];
eyeCal.LYPos = [];
eyeCal.RXGain = 1;
eyeCal.RYGain = 1;
eyeCal.LXGain = [];
eyeCal.LYGain = [];
eyeCal.Delta = struct( ...
    'cnt', 1, ...
    'RX0', 0, ...
    'RY0', 0, ...
    'LX0', 0, ...
    'LY0', 0, ...
    'TrialNo', [], ...
    'Time', []);
end
