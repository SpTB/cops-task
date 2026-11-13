function R = testCcgLagConvention(opts)
% testCcgLagConvention  Synthetic sanity check for ccg() lag convention.
%
%   R = testCcgLagConvention
%   R = testCcgLagConvention(struct('delaySteps', -2:2, 'dtSec', 0.1))
%
% Positive delaySteps means gaze lags the target:
%   gaze(step k) = target(step k - delaySteps)
%
% With the current ccg() xcorr convention, a delayed gaze trace should peak
% at a positive lag. The zero-delay condition should peak at 0 sec.

if nargin < 1 || isempty(opts)
    opts = struct();
end

defaults = struct( ...
    'nTrials', 20, ...
    'nSteps', 300, ...
    'dtSec', 0.1, ...
    'delaySteps', -3:3, ...
    'stepSigmaPx', 40, ...
    'gazeNoisePx', 0, ...
    'seed', 1, ...
    'ccgWindowSec', [-0.8 0.8], ...
    'plot', true);
opts = localApplyDefaults(opts, defaults);

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);
addpath(fullfile(thisDir, 'helpers'));

localSetRandomSeed(opts.seed);
delaySteps = double(opts.delaySteps(:)');
nDelay = numel(delaySteps);
runs = cell(nDelay, 1);

peakLagX = NaN(nDelay, 1);
peakLagY = NaN(nDelay, 1);
expectedLagSec = delaySteps(:) .* double(opts.dtSec);
zeroLagX = NaN(nDelay, 1);
zeroLagY = NaN(nDelay, 1);
peakX = NaN(nDelay, 1);
peakY = NaN(nDelay, 1);

ccgOpts = struct();
ccgOpts.ccgWindowSec = opts.ccgWindowSec;
ccgOpts.lowpassHz = [];
ccgOpts.interpBlinkSec = 0;
ccgOpts.useTrackingOnly = true;
ccgOpts.aggregateMode = 'chunk';
ccgOpts.plot = false;

for iDelay = 1:nDelay
    T = localSyntheticTrackingTable(delaySteps(iDelay), opts);
    out = ccg(T, [], ccgOpts);
    runs{iDelay} = out;

    lagSec = double(out.lagSec(:));
    if isempty(lagSec) || isempty(out.groups) || isempty(out.groups{1})
        continue
    end

    x = double(out.groups{1}.aggregateX(:));
    y = double(out.groups{1}.aggregateY(:));
    [peakLagX(iDelay), peakX(iDelay), zeroLagX(iDelay)] = localPeakAndZero(lagSec, x);
    [peakLagY(iDelay), peakY(iDelay), zeroLagY(iDelay)] = localPeakAndZero(lagSec, y);
end

summary = table( ...
    delaySteps(:), expectedLagSec(:), ...
    peakLagX, peakLagX - expectedLagSec(:), peakX, zeroLagX, ...
    peakLagY, peakLagY - expectedLagSec(:), peakY, zeroLagY, ...
    'VariableNames', {'delaySteps','expectedLagSec', ...
    'peakLagX','lagErrorX','peakCorrX','zeroLagCorrX', ...
    'peakLagY','lagErrorY','peakCorrY','zeroLagCorrY'});

R = struct();
R.summary = summary;
R.runs = runs;
R.opts = opts;

disp(summary);
fprintf(['Positive delaySteps means synthetic gaze lags target. ', ...
    'For a correct lag convention, peakLag should match expectedLagSec; ', ...
    'delaySteps=0 should peak at 0 sec.\n']);

if logical(opts.plot)
    localPlotSummary(runs, summary);
end
end


function T = localSyntheticTrackingTable(delaySteps, opts)
nTrials = double(opts.nTrials);
nSteps = double(opts.nSteps);
dtSec = double(opts.dtSec);
stepSigmaPx = double(opts.stepSigmaPx);
gazeNoisePx = double(opts.gazeNoisePx);

trial = [];
intervalNo = [];
sampleIdx = [];
tFromTrackingOnsetSec = [];
step = [];
xPx = [];
yPx = [];
trackedTargetX = [];
trackedTargetY = [];
isTracking = [];

for iTrial = 1:nTrials
    targetX = cumsum(stepSigmaPx .* randn(nSteps, 1));
    targetY = cumsum(stepSigmaPx .* randn(nSteps, 1));
    gazeX = localShiftBySteps(targetX, delaySteps);
    gazeY = localShiftBySteps(targetY, delaySteps);
    if gazeNoisePx > 0
        gazeX = gazeX + gazeNoisePx .* randn(size(gazeX));
        gazeY = gazeY + gazeNoisePx .* randn(size(gazeY));
    end

    idx = (1:nSteps)';
    trial = [trial; repmat(iTrial, nSteps, 1)]; %#ok<AGROW>
    intervalNo = [intervalNo; ones(nSteps, 1)]; %#ok<AGROW>
    sampleIdx = [sampleIdx; idx]; %#ok<AGROW>
    tFromTrackingOnsetSec = [tFromTrackingOnsetSec; (idx - 1) .* dtSec]; %#ok<AGROW>
    step = [step; idx]; %#ok<AGROW>
    xPx = [xPx; gazeX]; %#ok<AGROW>
    yPx = [yPx; gazeY]; %#ok<AGROW>
    trackedTargetX = [trackedTargetX; targetX]; %#ok<AGROW>
    trackedTargetY = [trackedTargetY; targetY]; %#ok<AGROW>
    isTracking = [isTracking; true(nSteps, 1)]; %#ok<AGROW>
end

T = table( ...
    trial, intervalNo, sampleIdx, tFromTrackingOnsetSec, step, ...
    xPx, yPx, trackedTargetX, trackedTargetY, isTracking, ...
    'VariableNames', {'trial','intervalNo','sampleIdx','tFromTrackingOnsetSec','step', ...
    'xPx','yPx','trackedTargetX','trackedTargetY','isTracking'});
end


function y = localShiftBySteps(x, delaySteps)
% delaySteps > 0: y lags x; delaySteps < 0: y leads x.
x = double(x(:));
y = NaN(size(x));
d = round(double(delaySteps));
if d >= 0
    y((d + 1):end) = x(1:(end - d));
else
    lead = abs(d);
    y(1:(end - lead)) = x((lead + 1):end);
end
end


function [peakLag, peakValue, zeroValue] = localPeakAndZero(lagSec, x)
peakLag = NaN;
peakValue = NaN;
zeroValue = NaN;
if isempty(lagSec) || isempty(x) || numel(lagSec) ~= numel(x)
    return
end
finiteMask = isfinite(lagSec) & isfinite(x);
if ~any(finiteMask)
    return
end
[peakValue, relIdx] = max(x(finiteMask));
lagFinite = lagSec(finiteMask);
peakLag = lagFinite(relIdx);
[~, zeroIdx] = min(abs(lagSec));
if ~isempty(zeroIdx) && isfinite(x(zeroIdx))
    zeroValue = x(zeroIdx);
end
end


function localPlotSummary(runs, summary)
figure;
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
hold on
colors = lines(height(summary));
for i = 1:height(summary)
    out = runs{i};
    if isempty(out.lagSec) || isempty(out.groups) || isempty(out.groups{1})
        continue
    end
    plot(out.lagSec, out.groups{1}.aggregateX, ...
        'Color', colors(i, :), 'LineWidth', 1.25);
end
xline(0, ':');
yline(0, ':');
xlabel('Lag (s)');
ylabel('X velocity xcorr');
legend("delay " + string(summary.expectedLagSec) + " s", 'Location', 'best');
title('Synthetic CCG curves');
box off

nexttile;
hold on
plot(summary.expectedLagSec, summary.peakLagX, 'ko', 'MarkerFaceColor', 'k');
lims = [min([summary.expectedLagSec; summary.peakLagX], [], 'omitnan'), ...
    max([summary.expectedLagSec; summary.peakLagX], [], 'omitnan')];
if all(isfinite(lims)) && diff(lims) > 0
    pad = 0.05 * diff(lims);
    lims = lims + [-pad pad];
    plot(lims, lims, 'k:');
    xlim(lims);
    ylim(lims);
end
xlabel('Expected lag (s)');
ylabel('Observed peak lag (s)');
title('Peak lag check');
axis square
box off
end


function opts = localApplyDefaults(opts, defaults)
fields = fieldnames(defaults);
for i = 1:numel(fields)
    f = fields{i};
    if ~isfield(opts, f) || isempty(opts.(f))
        opts.(f) = defaults.(f);
    end
end
end


function localSetRandomSeed(seed)
seed = double(seed);
if ~isfinite(seed)
    return
end
if exist('rng', 'builtin') || exist('rng', 'file')
    rng(seed);
else
    rand('seed', seed); %#ok<RAND>
    randn('seed', seed); %#ok<RAND>
end
end
