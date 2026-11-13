function out = plotTraj(ex, trialNo, axisName, opts)
% plotTraj  Plot gaze and target trajectories for one trial.
%
%   plotTraj(ex, 10)
%   plotTraj(ex, 10, 'x')
%   plotTraj(ex, 10, 'y')
%   plotTraj(ex, 10, 'x_only')
%   plotTraj(ex, 10, 'y_only')
%   plotTraj(ex, 10, '2d_only')
%   plotTraj(ex, 10, 'xy_only')
%   plotTraj(ex, 10, 'xy')
%   plotTraj(ex, 10, 'all')
%
% Inputs
%   ex       : experiment struct containing ex.Trials
%   trialNo  : trial number in ex.Trials
%   axisName : 'x', 'y', 'x_only', 'y_only', '2d_only', 'xy_only', 'xy', or 'all' (default).
%   opts     : optional struct with fields:
%       .onlyGoState   (default true)
%       .useEyeTime    (default false)
%       .showRew       (default false) show the reward location; uses a
%                      black + in 2-D and a dashed black line otherwise
%       .lowpassHz     (default 5) zero-phase low-pass cutoff for gaze
%       .interpBlinkSec (default 0.15) linearly interpolate short missing
%                       gaze gaps after masking samples outside the texture
%       .newFigure     (default true)
%       .gazeColor     (default [0 0.45 0.74])
%       .target1Color  (default [0 0 0])
%       .target2Color  (default [0.85 0.33 0.10])
%       .lineWidth     (default 1.25)
%       .ccg           (default true) add velocity cross-correlograms
%                       below x and y panels
%       .ccgWindowSec  (default [-0.05 5]) lag window for CCG display
%       .truncateTrialFromStep (default 0) if >0, keep only samples from
%                      steps >= this value before plotting / CCG
%
% Output
%   out.trialTable : sample-level table used for plotting
%   out.trialNo    : plotted trial number
%   out.axisName   : plotted mode

if nargin < 2 || isempty(trialNo)
    error('plotTraj:MissingTrialNo', 'trialNo is required.');
end
if nargin < 3 || isempty(axisName)
    axisName = 'all';
end
if nargin < 4 || isempty(opts)
    opts = struct();
elseif isstruct(axisName)
    opts = axisName;
    axisName = 'all';
end

axisName = validatestring(char(string(axisName)), {'x', 'y', 'x_only', 'y_only', '2d_only', 'xy_only', 'xy', 'all'});

defaults = struct( ...
    'onlyGoState', true, ...
    'useEyeTime', true, ...
    'showRew', false, ...
    'lowpassHz', 5, ...
    'interpBlinkSec', 0.15, ...
    'newFigure', true, ...
    'gazeColor', [0 0.45 0.74], ...
    'target1Color', [0 0 0], ...
    'target2Color', [0.85 0.33 0.10], ...
    'lineWidth', 1.25, ...
    'ccg', true, ...
    'ccgWindowSec', [-0.05 5], ...
    'truncateTrialFromStep', 0);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field)
        opts.(field) = defaults.(field);
    end
end

if ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('plotTraj:NoTrials', 'Input ex has no trials in ex.Trials.');
end

trialNo = double(trialNo);
if ~isscalar(trialNo) || ~isfinite(trialNo) || trialNo < 1 || trialNo > numel(ex.Trials) || trialNo ~= round(trialNo)
    error('plotTraj:BadTrialNo', 'trialNo must be a valid integer index into ex.Trials.');
end

T = ex.Trials(trialNo);
[xPx, yPx, tRel, tAbs, valid] = reconstructEyePx(ex, T, opts.useEyeTime, opts);
[targetX, targetY, target2X, target2Y, stepIdx] = mapTargetsByStep(ex, T, tRel);

goMask = true(size(tRel));
if opts.onlyGoState && isfield(T, 'times') && isfield(T.times, 'stimOn') && isfield(T, 'TrialEnd')
    goMask = tAbs >= T.times.stimOn & tAbs <= T.TrialEnd;
end

xPx = xPx(goMask);
yPx = yPx(goMask);
tRel = tRel(goMask);
tAbs = tAbs(goMask);
valid = valid(goMask);
targetX = targetX(goMask);
targetY = targetY(goMask);
target2X = target2X(goMask);
target2Y = target2Y(goMask);
stepIdx = stepIdx(goMask);

truncateFromStep = double(localFirstScalar(opts.truncateTrialFromStep));
if isfinite(truncateFromStep) && truncateFromStep > 0
    keepMask = isfinite(stepIdx) & stepIdx >= truncateFromStep;
    xPx = xPx(keepMask);
    yPx = yPx(keepMask);
    tRel = tRel(keepMask);
    tAbs = tAbs(keepMask);
    valid = valid(keepMask);
    targetX = targetX(keepMask);
    targetY = targetY(keepMask);
    target2X = target2X(keepMask);
    target2Y = target2Y(keepMask);
    stepIdx = stepIdx(keepMask);
end

[texBounds, textureMask] = localTextureBounds(ex.setup.screenRect, ex.exp.CoPs.graph);
insideTexture = xPx >= texBounds.xMin & xPx <= texBounds.xMax & ...
    yPx >= texBounds.yMin & yPx <= texBounds.yMax;
xPx(~insideTexture) = NaN;
yPx(~insideTexture) = NaN;
valid = valid & insideTexture;

interpBlinkSec = localFirstScalar(opts.interpBlinkSec);
if isfinite(interpBlinkSec) && interpBlinkSec > 0
    dtSec = 1 / inferFs(ex);
    maxGapSamples = max(1, round(interpBlinkSec / dtSec));
    xPx = localInterpShortNaNGaps(xPx, maxGapSamples);
    yPx = localInterpShortNaNGaps(yPx, maxGapSamples);
end

if isfinite(localFirstScalar(opts.lowpassHz)) && localFirstScalar(opts.lowpassHz) > 0
    dtSec = 1 / inferFs(ex);
    xPx = localZeroPhaseLowpassTrace(xPx, valid, dtSec, localFirstScalar(opts.lowpassHz));
    yPx = localZeroPhaseLowpassTrace(yPx, valid, dtSec, localFirstScalar(opts.lowpassHz));
end

plotTable = table(tRel(:), tAbs(:), xPx(:), yPx(:), valid(:), stepIdx(:), ...
    targetX(:), targetY(:), target2X(:), target2Y(:), ...
    'VariableNames', {'tRelSec','tAbsSec','xPx','yPx','valid','step','targetX','targetY','target2X','target2Y'});

[plotData, textureMaskDeg] = localPlotDataInDeg(ex, plotTable, textureMask);

hasTarget2 = any(isfinite(target2X) & isfinite(target2Y));
if ismember(axisName, {'x_only', 'y_only', '2d_only', 'xy_only'})
    ccgX = localConvertCcgRow([]);
    ccgY = localConvertCcgRow([]);
else
    [ccgX, ccgY] = localComputeVelocityCcg(plotTable, ex, opts);
end

if opts.newFigure
    figure;
end

    switch axisName
    case 'x_only'
        tiledlayout(1, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
        nexttile;
        localPlotAxis(plotData.tRelSec, plotData.xDeg, plotData.targetXDeg, plotData.target2XDeg, ...
            hasTarget2, 'X Position (deg)', opts);
        xlabel('Trial Time (s)');
        title(sprintf('Trial %d Trajectories (x)', trialNo), 'Interpreter', 'none');

    case 'y_only'
        tiledlayout(1, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
        nexttile;
        localPlotAxis(plotData.tRelSec, plotData.yDeg, plotData.targetYDeg, plotData.target2YDeg, ...
            hasTarget2, 'Y Position (deg)', opts);
        xlabel('Trial Time (s)');
        title(sprintf('Trial %d Trajectories (y)', trialNo), 'Interpreter', 'none');

    case '2d_only'
        tiledlayout(1, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
        nexttile;
        localPlotPlane(plotData.xDeg, plotData.yDeg, plotData.targetXDeg, plotData.targetYDeg, ...
            plotData.target2XDeg, plotData.target2YDeg, hasTarget2, textureMaskDeg, opts);
        if opts.showRew
            localPlotRewardPeak(localRewardPeakInDeg(ex, T));
        end
        xlabel('X Position (deg)');
        ylabel('Y Position (deg)');
        title(sprintf('Trial %d Trajectories (xy)', trialNo), 'Interpreter', 'none');

    case 'xy_only'
        tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

        rewardPeakDeg = localRewardPeakInDeg(ex, T);

        nexttile;
        localPlotAxis(plotData.tRelSec, plotData.xDeg, plotData.targetXDeg, plotData.target2XDeg, ...
            hasTarget2, 'X Position (deg)', opts);
        if opts.showRew
            localPlotRewardAxis(rewardPeakDeg(1));
        end
        xlabel('Trial Time (s)');
        title('x', 'Interpreter', 'none');

        nexttile;
        localPlotAxis(plotData.tRelSec, plotData.yDeg, plotData.targetYDeg, plotData.target2YDeg, ...
            hasTarget2, 'Y Position (deg)', opts);
        if opts.showRew
            localPlotRewardAxis(rewardPeakDeg(2));
        end
        xlabel('Trial Time (s)');
        title('y', 'Interpreter', 'none');

        sgtitle(sprintf('Trial %d Trajectories', trialNo), 'Interpreter', 'none');

    case 'x'
        if opts.ccg
            tiledlayout(2, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
            nexttile;
        end
        localPlotAxis(plotData.tRelSec, plotData.xDeg, plotData.targetXDeg, plotData.target2XDeg, ...
            hasTarget2, 'X Position (deg)', opts);
        if opts.showRew
            rewardPeakDeg = localRewardPeakInDeg(ex, T);
            localPlotRewardAxis(rewardPeakDeg(1));
        end
        xlabel('Trial Time (s)');
        title(sprintf('Trial %d Trajectories (x)', trialNo), 'Interpreter', 'none');
        if opts.ccg
            nexttile;
            localPlotCcg(ccgX.lagSec, ccgX.xcorr, 'X Velocity CCG');
        end
    case 'y'
        if opts.ccg
            tiledlayout(2, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
            nexttile;
        end
        localPlotAxis(plotData.tRelSec, plotData.yDeg, plotData.targetYDeg, plotData.target2YDeg, ...
            hasTarget2, 'Y Position (deg)', opts);
        if opts.showRew
            rewardPeakDeg = localRewardPeakInDeg(ex, T);
            localPlotRewardAxis(rewardPeakDeg(2));
        end
        xlabel('Trial Time (s)');
        title(sprintf('Trial %d Trajectories (y)', trialNo), 'Interpreter', 'none');
        if opts.ccg
            nexttile;
            localPlotCcg(ccgY.lagSec, ccgY.xcorr, 'Y Velocity CCG');
        end
    case 'xy'
        localPlotPlane(plotData.xDeg, plotData.yDeg, plotData.targetXDeg, plotData.targetYDeg, ...
            plotData.target2XDeg, plotData.target2YDeg, hasTarget2, textureMaskDeg, opts);
        if opts.showRew
            localPlotRewardPeak(localRewardPeakInDeg(ex, T));
        end
        xlabel('X Position (deg)');
        ylabel('Y Position (deg)');
        title(sprintf('Trial %d Trajectories (xy)', trialNo), 'Interpreter', 'none');
    case 'all'
        if opts.ccg
            tiledlayout(2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');
        else
            tiledlayout(1, 3, 'Padding', 'compact', 'TileSpacing', 'compact');
        end

        nexttile;
        localPlotAxis(plotData.tRelSec, plotData.xDeg, plotData.targetXDeg, plotData.target2XDeg, ...
            hasTarget2, 'X Position (deg)', opts);
        xlabel('Trial Time (s)');
        title('x', 'Interpreter', 'none');

        nexttile;
        localPlotAxis(plotData.tRelSec, plotData.yDeg, plotData.targetYDeg, plotData.target2YDeg, ...
            hasTarget2, 'Y Position (deg)', opts);
        xlabel('Trial Time (s)');
        title('y', 'Interpreter', 'none');

        nexttile;
        localPlotPlane(plotData.xDeg, plotData.yDeg, plotData.targetXDeg, plotData.targetYDeg, ...
            plotData.target2XDeg, plotData.target2YDeg, hasTarget2, textureMaskDeg, opts);
        if opts.showRew
            localPlotRewardPeak(localRewardPeakInDeg(ex, T));
        end
        xlabel('X Position (deg)');
        ylabel('Y Position (deg)');
        title('xy', 'Interpreter', 'none');

        if opts.ccg
            nexttile;
            localPlotCcg(ccgX.lagSec, ccgX.xcorr, 'X Velocity CCG');

            nexttile;
            localPlotCcg(ccgY.lagSec, ccgY.xcorr, 'Y Velocity CCG');

            nexttile;
            axis off
        end

        sgtitle(sprintf('Trial %d Trajectories', trialNo), 'Interpreter', 'none');
end

out = struct();
out.trialTable = plotTable;
out.trialNo = trialNo;
out.axisName = axisName;
out.ccg = struct('x', ccgX, 'y', ccgY);
end


function [plotData, textureMaskDeg] = localPlotDataInDeg(ex, plotTable, textureMaskPx)
[x0, y0] = localReferenceCenterPx(ex);
plotData = struct();
plotData.tRelSec = plotTable.tRelSec;
plotData.xDeg = px2deg(plotTable.xPx - x0, ex.setup);
plotData.yDeg = px2deg(plotTable.yPx - y0, ex.setup);
plotData.targetXDeg = px2deg(plotTable.targetX - x0, ex.setup);
plotData.targetYDeg = px2deg(plotTable.targetY - y0, ex.setup);
plotData.target2XDeg = px2deg(plotTable.target2X - x0, ex.setup);
plotData.target2YDeg = px2deg(plotTable.target2Y - y0, ex.setup);
textureMaskDeg = struct( ...
    'xMin', px2deg(textureMaskPx.xMin - x0, ex.setup), ...
    'xMax', px2deg(textureMaskPx.xMax - x0, ex.setup), ...
    'yMin', px2deg(textureMaskPx.yMin - y0, ex.setup), ...
    'yMax', px2deg(textureMaskPx.yMax - y0, ex.setup));
end


function peakDeg = localRewardPeakInDeg(ex, T)
peakDeg = [NaN, NaN];
peakPx = getGaussianCenterPx(ex, T);
if numel(peakPx) < 2 || any(~isfinite(peakPx(1:2)))
    return
end
[x0, y0] = localReferenceCenterPx(ex);
peakDeg = [px2deg(peakPx(1) - x0, ex.setup), px2deg(peakPx(2) - y0, ex.setup)];
end


function [x0, y0] = localReferenceCenterPx(ex)
if isfield(ex, 'fix') && isfield(ex.fix, 'PCtr') && numel(ex.fix.PCtr) >= 2 && all(isfinite(ex.fix.PCtr(1:2)))
    x0 = double(ex.fix.PCtr(1));
    y0 = double(ex.fix.PCtr(2));
    return
end
if isfield(ex, 'setup') && isfield(ex.setup, 'screenRect') && numel(ex.setup.screenRect) >= 4
    rect = double(ex.setup.screenRect);
    x0 = mean(rect([1 3]));
    y0 = mean(rect([2 4]));
    return
end
x0 = 0;
y0 = 0;
end


function localPlotAxis(tSec, gazePos, target1Pos, target2Pos, hasTarget2, yLabelText, opts)
plot(tSec, target1Pos, 'Color', opts.target1Color, 'LineWidth', opts.lineWidth);
hold on
if hasTarget2
    plot(tSec, target2Pos, '--', 'Color', opts.target2Color, 'LineWidth', opts.lineWidth);
end
plot(tSec, gazePos, 'Color', opts.gazeColor, 'LineWidth', opts.lineWidth);
ylabel(yLabelText);
if hasTarget2
    legend({'Target 1', 'Target 2', 'Gaze'}, 'Location', 'best');
else
    legend({'Target', 'Gaze'}, 'Location', 'best');
end
box off
end


function localPlotPlane(gazeX, gazeY, target1X, target1Y, target2X, target2Y, hasTarget2, textureMask, opts)
plot(target1X, target1Y, 'Color', opts.target1Color, 'LineWidth', opts.lineWidth);
hold on
if hasTarget2
    plot(target2X, target2Y, '--', 'Color', opts.target2Color, 'LineWidth', opts.lineWidth);
end
plot(gazeX, gazeY, 'Color', opts.gazeColor, 'LineWidth', opts.lineWidth);
xlim([textureMask.xMin, textureMask.xMax]);
ylim([textureMask.yMin, textureMask.yMax]);
axis square
set(gca, 'YDir', 'reverse');
if hasTarget2
    legend({'Target 1', 'Target 2', 'Gaze'}, 'Location', 'best');
else
    legend({'Target', 'Gaze'}, 'Location', 'best');
end
box off
end


function localPlotRewardPeak(peakDeg)
if numel(peakDeg) < 2 || any(~isfinite(peakDeg(1:2)))
    return
end
plot(peakDeg(1), peakDeg(2), '+', ...
    'Color', [0 0 0], ...
    'LineWidth', 2, ...
    'MarkerSize', 10, ...
    'HandleVisibility', 'off');
end


function localPlotRewardAxis(rewardDeg)
if ~isfinite(rewardDeg)
    return
end
yline(rewardDeg, '--', ...
    'Color', [0 0 0], ...
    'LineWidth', 1.25, ...
    'HandleVisibility', 'off');
end


function localPlotCcg(lagSec, xc, titleText)
plot(lagSec, xc, 'k', 'LineWidth', 1.25);
hold on
xline(0, ':');
xlabel('Lag (s)');
ylabel('xcorr');
title(titleText, 'Interpreter', 'none');
box off
end


function value = localFirstScalar(x)
value = NaN;
if isempty(x)
    return
end
if isscalar(x) && isfinite(double(x))
    value = double(x);
else
    value = double(x(1));
end
end


function [outX, outY] = localComputeVelocityCcg(plotTable, ex, opts)
dtSec = 1 / inferFs(ex);
[outX, outY] = computeVelocityCcgRowsCoPs( ...
    plotTable.xPx, plotTable.yPx, plotTable.targetX, plotTable.targetY, ...
    plotTable.step, plotTable.tRelSec, true(size(plotTable.step)), dtSec, opts.ccgWindowSec);
outX = localConvertCcgRow(outX);
outY = localConvertCcgRow(outY);
end


function out = localConvertCcgRow(row)
out = struct('lagSec', NaN(0,1), 'lags', NaN(0,1), 'xcorr', NaN(0,1));
if isempty(row)
    return
end
out.lagSec = row.lagSec;
out.lags = row.lagSamples;
out.xcorr = row.corr;
end


function y = localZeroPhaseLowpassTrace(x, valid, dtSec, cutoffHz)
x = x(:);
valid = logical(valid(:)) & isfinite(x);
y = x;
if ~isfinite(cutoffHz) || cutoffHz <= 0 || ~isfinite(dtSec) || dtSec <= 0
    return
end

fs = 1 / dtSec;
nyq = fs / 2;
normCutoff = cutoffHz / nyq;
if ~isfinite(normCutoff) || normCutoff <= 0 || normCutoff >= 1
    return
end

[b, a] = butter(2, normCutoff, 'low');
idx = find(valid);
if isempty(idx)
    return
end

runBreak = [true; diff(idx) > 1];
runStarts = find(runBreak);
runEnds = [runStarts(2:end) - 1; numel(idx)];
for i = 1:numel(runStarts)
    ii = idx(runStarts(i):runEnds(i));
    if numel(ii) < 7
        continue
    end
    y(ii) = filtfilt(b, a, x(ii));
end
end


function x = localInterpShortNaNGaps(x, maxGapSamples)
x = x(:);
if isempty(x) || maxGapSamples < 1
    return
end

nanMask = ~isfinite(x);
if ~any(nanMask)
    return
end

d = diff([false; nanMask; false]);
gapStarts = find(d == 1);
gapEnds = find(d == -1) - 1;
for i = 1:numel(gapStarts)
    g0 = gapStarts(i);
    g1 = gapEnds(i);
    gapLen = g1 - g0 + 1;
    if gapLen > maxGapSamples || g0 <= 1 || g1 >= numel(x)
        continue
    end
    if ~isfinite(x(g0 - 1)) || ~isfinite(x(g1 + 1))
        continue
    end
    fillVals = linspace(x(g0 - 1), x(g1 + 1), gapLen + 2);
    x(g0:g1) = fillVals(2:end-1);
end
end


function [bounds, mask] = localTextureBounds(screenRect, graph)
texDimPx = graph.texture_dims(1) * graph.size_mult;
xShift = (screenRect(3) - texDimPx) / 2;
yShift = (screenRect(4) - texDimPx) / 2;
bounds = struct( ...
    'xMin', xShift, ...
    'xMax', xShift + texDimPx, ...
    'yMin', yShift, ...
    'yMax', yShift + texDimPx);
mask = bounds;
end
