ex=mergeCoPsHmmStruct('ka', 'aug11')

opts = struct();
opts.hmmMethod = 'smoothed';
opts.makePlot = true;

%opts.minEventSeparationSec = 2.5;
%opts.preSec = 2.5;
%opts.baselineWindowSec = [];

%opts.baselineWindowSec =[-1.5 -.5];
%opts.baselineWindowSec =[-2.5 -2.0];

pupilOut = pupilHmmTransitions(ex, opts);

pupilOut.events
pupilOut.summary


%% Looking at individual traces
%pupilOut.traces.combined <- pupilOut.traces.combinedUncorrectedZ


% eventType = "nonTracking_to_tracking";
% sel = pupilOut.events.eventType == eventType;

eventCategory = "nonTracking_to_tracking";
sel = string(pupilOut.events.eventCategory) == eventCategory;

t = pupilOut.timeSec;
traces = pupilOut.traces.combined(sel, :);
tracesRaw = pupilOut.traces.combinedUncorrectedZ(sel, :);

meanTrace = mean(traces, 1, 'omitnan');
n = sum(isfinite(traces), 1);
semTrace = std(traces, 0, 1, 'omitnan') ./ sqrt(n);

figure;
hold on;

fill( ...
    [t, fliplr(t)], ...
    [meanTrace-semTrace, fliplr(meanTrace+semTrace)], ...
    [0.85 0.45 0.15], ...
    'FaceAlpha', 0.2, ...
    'EdgeColor', 'none');

plot(t, meanTrace, ...
    'Color', [0.85 0.35 0.05], ...
    'LineWidth', 2);

xline(0, 'k--', 'HMM transition');
yline(0, 'Color', [0.5 0.5 0.5]);

xlabel('Time from transition (s)');
ylabel('\Delta pupil (session-eye SD)');
title(sprintf('Closer to farther, n=%d', sum(sel)));
grid on;

%% across days
opts = struct();
opts.minTrials = 200;
opts.type = 'dayMean'; %each day contributes equally

out = pupilHmmTransitionsDays('ka', 'jun02', [], opts);
out = pupilHmmTransitionsDays('ly', 'jun02', [], opts);

opts.type = 'eventAgg';
out = pupilHmmTransitionsDays('ka', 'jun02', [], opts);
out = pupilHmmTransitionsDays('ly', 'jun02', [], opts);

%% blink controls
ex=mergeCoPsHmmStruct('ly', 'aug11')

blinkOut = blinkHmmTransitions(ex);
rewardOut = rewardHmmTransitions(ex);
blinkRewardOut = blinkRew(ex)% doesn't work?

out=blinkHmmTransitionsDays('ka','jun02')
out=blinkHmmTransitionsDays('ly','jun02')


% control blinks
opts.blinkWindowSec = [-0.5 2.0];
opts.blinkEvents = 'exclude';
pupilOut = pupilHmmTransitionsDays('ly','jun02', [],opts);
opts.blinkEvents = 'blink-only';
pupilOut = pupilHmmTransitionsDays('ly','jun02', [],opts);

%% control ecc
ecOut= eccentricityHmmTransitions(ex);
o=[];
o.metric = 'trackedTargetResidual';
eccResidual = eccentricityHmmTransitions(ex, o); % gaze - target pos: shows if target pos explains ecc diff fully or not

out= eccentricityHmmTransitionsDays('ka','jun02')
out= eccentricityHmmTransitionsDays('ly','jul02')

eccOut = compareTargetEccentricity(ex);

% correction:
cal = fitPupilPositionBias('ly', 'aug11');
[exCorrected, report] = applyPupilPositionBias(ex, cal);
pupilOut = pupilHmmTransitions(exCorrected);

o = struct();
o.posCorrected = true;
pupilDays = pupilHmmTransitionsDays('ka', 'Jun02',[], o);
pupilDays = pupilHmmTransitionsDays('ly', 'Jun02',[], o);

%% correcting for saccades (!)
saccPupil = pupilEyeCalSaccades('ka', 'Aug11');
o=[];
o.sacCor=true
pupilHmmTransitions(ex,o)
%% in-dataset correction for eccentricity and saccades
o = struct();

% Experimental eccentricity correction
o.posCorrected = true;
o.posCorrectionSource = 'experimental';

% Experimental saccade-kernel correction
o.sacCor = true;
o.sacCorrectionSource = 'experimental';
o.correctionScope='session';
pupilOut = pupilHmmTransitions(ex, o);
%check kernel
opts=[]
opts.makePlot = true;
opts.preSec = 0.5;
opts.postSec = 1.0;
opts.baselineWindowSec = [-0.5 -0.2];
kernelOut = fitPupilExperimentalSaccadeKernel(ex, opts);

%by deconvolution:
ex=mergeCoPsHmmStruct('ka', 'aug11')
o=[]
o.corMethod = 'deconvolution' % 'subtraction'
o.deconvBinSec = 0.05;                 % 50-ms FIR resolution
o.deconvSaccadeWindowSec = [-0.5 1];
o.deconvBlinkWindowSec = [-0.5 2];
o.deconvRewardWindowSec = [-1.5 3];
o.deconvDriftOrder = 3;
o.deconvRidge = 1;
pupilOut = pupilHmmTransitions(ex, o);

out= pupilHmmTransitionsDays('ka','jul02',o)
out2= pupilHmmTransitionsDays('ly','jul02',o)

%% ecc correction cont'd
T = cal.fixations;

Xspatial = [
    T.xDeg, ...
    T.yDeg, ...
    T.xDeg.^2, ...
    T.yDeg.^2, ...
    T.xDeg .* T.yDeg
];

rightBias = Xspatial * cal.right.spatialBeta;
leftBias  = Xspatial * cal.left.spatialBeta;

figure;
tiledlayout(1,2);

nexttile;
scatter(T.eccentricityDeg, rightBias, 35, T.xDeg, 'filled');
yline(0, 'k--');
xlabel('Gaze eccentricity (deg)');
ylabel('Estimated pupil bias from screen center');
title('Right eye');
colorbar;
grid on;

nexttile;
scatter(T.eccentricityDeg, leftBias, 35, T.xDeg, 'filled');
yline(0, 'k--');
xlabel('Gaze eccentricity (deg)');
ylabel('Estimated pupil bias from screen center');
title('Left eye');
colorbar;
grid on;

%% state means (tonic)
pupilState = pupilHmmStateMeans(ex, opts); 
pupilState.comparison
pupilState.summary

o=[]
o.pairedOnly=true % compare only trials that have both
pupilState = pupilHmmStateMeans(ex, o);
pupilState.comparison
pupilState.summary

%% tonic summaries
opts = struct();
opts.minTrials = 60;
opts.aggBy='session'
opts.type = 'dayMean';

out = pupilHmmStateMeansDays('ka', 'jun02', [],opts);
out = pupilHmmStateMeansDays('ly', 'jun02', [],opts);

%% reward effects
opts = struct();
opts.preSec = 1.5;
opts.postSec = 3;
opts.baselineWindowSec = [-1.5 -1];
opts.minRewardSeparationSec = 0.5;

opts.smoothWindowSec = 0.0;
pupRew(ex, opts)

%% rew learning...
%A = plotGazeRewDistDays('ka', '2026.07.01');

M = A.meanTable;

figure;
hold on;

x = M.sessionTrialCenter;
y = M.meanExcessDistDeg;
se = M.semExcessDistDeg;

fill([x; flipud(x)], ...
     [y-se; flipud(y+se)], ...
     [0.10 0.35 0.80], ...
     'FaceAlpha', 0.18, ...
     'EdgeColor', 'none');

plot(x, y, '-o', ...
    'Color', [0.10 0.35 0.80], ...
    'LineWidth', 2.5);

yline(0, ':');
xlim([1 130]);

xlabel('trial within reward-center session');
ylabel('excess distance over reward-closer target (deg)');
box off;