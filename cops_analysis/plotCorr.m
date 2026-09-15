function out = plotCorr(trackingTable, axisName, opts)
% plotCorr  Cross-correlogram across tracked intervals.
%
% This can operate either on the raw sample sequence or on values
% collapsed to one row per target-motion step.
%
% out = plotCorr(t)
% out = plotCorr(t, 'x')
% out = plotCorr(t, 'y', opts)
%
% Inputs
%   trackingTable : out.tracking from processCoPsEye
%   axisName      : 'x' (default) or 'y'
%   opts          : optional struct with fields:
%       .stepHz          (default 30)
%       .sampleHz        (default 500)
%       .maxLagSec       (default 0.5)
%       .minSamples      (default 4) minimum number of step-level samples
%                        after any differencing
%       .minDurationSec  (default 0.2)
%       .mode            (default 'delta') one of:
%                        'delta' or 'position'
%       .timebase        (default 'sample') one of:
%                        'step' or 'sample'
%       .allign          (default false) if true, discard tracking rows
%                        before the first target step switch that occurs
%                        after tracking onset within each interval
%       .intervalVars    (default {'trial','intervalNo'})
%       .demean          (default true)
%       .plotSE          (default true)
%       .lineColor       (default [0 0 0])
%       .shadeColor      (default [0.75 0.75 0.75])
%       .newFigure       (default true)
%
% Output
%   out.lagsSec       : lag axis in seconds
%   out.lagsSteps     : lag axis in steps
%   out.meanCorr      : mean cross-correlation across intervals
%   out.seCorr        : standard error across intervals
%   out.corrByInt     : one row per interval
%   out.intervalInfo  : interval IDs used in the average
%   out.stepHz        : step rate used for the lag axis
%   out.mode          : signal mode used ('delta' or 'position')

if nargin < 2 || isempty(axisName)
    axisName = 'x';
end
if nargin < 3 || isempty(opts)
    opts = struct();
elseif isstruct(axisName)
    opts = axisName;
    axisName = 'x';
end

axisName = validatestring(char(string(axisName)), {'x', 'y'});

defaults = struct( ...
    'stepHz', 30, ...
    'sampleHz', 500, ...
    'maxLagSec', 0.5, ...
    'minSamples', 4, ...
    'minDurationSec', 0.05, ...
    'mode', 'delta', ...
    'timebase', 'step', ... % step vs sample
    'allign', false, ...
    'intervalVars', {{'trial', 'intervalNo'}}, ...
    'demean', true, ...
    'plotSE', true, ...
    'lineColor', [0 0 0], ...
    'shadeColor', [0.75 0.75 0.75], ...
    'newFigure', true);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field)
        opts.(field) = defaults.(field);
    end
end

if ~istable(trackingTable) || isempty(trackingTable)
    error('plotCorr:InvalidTrackingTable', ...
        'trackingTable must be a non-empty table, typically out.tracking.');
end

opts.mode = validatestring(char(string(opts.mode)), {'delta', 'position'});
opts.timebase = validatestring(char(string(opts.timebase)), {'step', 'sample'});
opts.allign = logical(opts.allign);
stepHz = double(opts.stepHz);
sampleHz = double(opts.sampleHz);
if ~isfinite(stepHz) || stepHz <= 0 || stepHz > 1000
    error('plotCorr:BadStepRate', ...
        'opts.stepHz must be a finite positive step rate; got %.3f Hz.', stepHz);
end
if ~isfinite(sampleHz) || sampleHz <= 0 || sampleHz > 5000
    error('plotCorr:BadSampleRate', ...
        'opts.sampleHz must be a finite positive sample rate; got %.3f Hz.', sampleHz);
end

targetVar = 'trackedTargetX';
gazeVar = 'xPx';
if strcmp(axisName, 'y')
    targetVar = 'trackedTargetY';
    gazeVar = 'yPx';
end

requiredVars = unique([{targetVar, gazeVar, 'isTracking'}, opts.intervalVars(:)', {'step'}], 'stable');
missingVars = setdiff(requiredVars, trackingTable.Properties.VariableNames, 'stable');
if ~isempty(missingVars)
    error('plotCorr:MissingVars', ...
        'Missing required tracking columns: %s', strjoin(missingVars, ', '));
end

if strcmp(opts.timebase, 'step')
    corrHz = stepHz;
else
    corrHz = sampleHz;
end

maxLagSteps = max(1, round(opts.maxLagSec * corrHz));
[groupIdx, intervalInfo] = findgroups(trackingTable(:, opts.intervalVars));
nIntervals = max(groupIdx);
corrByInt = NaN(nIntervals, 2 * maxLagSteps + 1);
used = false(nIntervals, 1);
lags = [];

for i = 1:nIntervals
    m = (groupIdx == i);
    T = trackingTable(m, :);
    if isempty(T)
        continue
    end

    if ismember('sampleIdx', T.Properties.VariableNames)
        [~, order] = sort(double(T.sampleIdx), 'ascend');
        T = T(order, :);
    elseif ismember('tRelSec', T.Properties.VariableNames)
        [~, order] = sort(double(T.tRelSec), 'ascend');
        T = T(order, :);
    end

    trackingMask = double(T.isTracking) >= 1;
    trackingMask = trackingMask & isfinite(double(T.step));
    if opts.allign
        firstTrackedIdx = find(trackingMask, 1, 'first');
        if isempty(firstTrackedIdx)
            continue
        end
        onsetStep = double(T.step(firstTrackedIdx));
        postOnsetStep = double(T.step);
        firstSwitchIdx = find((1:height(T))' > firstTrackedIdx & isfinite(postOnsetStep) & postOnsetStep ~= onsetStep, 1, 'first');
        if isempty(firstSwitchIdx)
            continue
        end
        trackingMask(1:firstSwitchIdx-1) = false;
    end
    T = T(trackingMask, :);
    if isempty(T)
        continue
    end

    if ismember('durationSec', T.Properties.VariableNames)
        intervalDurationSec = max(double(T.durationSec(1)), 0);
    else
        intervalDurationSec = NaN;
    end
    if isfinite(intervalDurationSec) && intervalDurationSec < opts.minDurationSec
        continue
    end

    if strcmp(opts.timebase, 'step')
        levelTable = collapseIntervalToSteps(T, targetVar, gazeVar);
        if height(levelTable) < 2
            continue
        end
        x = double(levelTable.targetVal);
        y = double(levelTable.gazeVal);
    else
        x = double(T.(targetVar));
        y = double(T.(gazeVar));
    end

    good = isfinite(x) & isfinite(y);
    x = x(good);
    y = y(good);

    if strcmp(opts.mode, 'delta')
        x = diff(x);
        y = diff(y);
    end

    if numel(x) < opts.minSamples || numel(y) < opts.minSamples
        continue
    end

    if opts.demean
        x = x - mean(x, 'omitnan');
        y = y - mean(y, 'omitnan');
    end

    [c, lags] = xcorr(x, y, maxLagSteps, 'coeff');
    corrByInt(i, :) = c(:)';
    used(i) = true;
end

corrByInt = corrByInt(used, :);
intervalInfo = intervalInfo(used, :);
if isempty(corrByInt)
    error('plotCorr:NoUsableIntervals', ...
        'No intervals had at least %d usable step-level samples for %s vs %s.', ...
        opts.minSamples, targetVar, gazeVar);
end

meanCorr = mean(corrByInt, 1, 'omitnan');
if size(corrByInt, 1) == 1
    seCorr = zeros(size(meanCorr));
else
    seCorr = std(corrByInt, 0, 1, 'omitnan') ./ sqrt(sum(isfinite(corrByInt), 1));
end
lagsSteps = lags(:);
lagsSec = lagsSteps / stepHz;
lagsSec = lagsSteps / corrHz;

if opts.newFigure
    figure;
end
hold on
if opts.plotSE
    xx = [lagsSec; flipud(lagsSec)];
    yy = [meanCorr(:) - seCorr(:); flipud(meanCorr(:) + seCorr(:))];
    fill(xx, yy, opts.shadeColor, 'FaceAlpha', 0.35, 'EdgeColor', 'none');
end
plot(lagsSec, meanCorr, 'Color', opts.lineColor, 'LineWidth', 1.5);
xline(0, ':', 'Color', [0.4 0.4 0.4]);
yline(0, ':', 'Color', [0.4 0.4 0.4]);
xlabel('Lag (s)');
ylabel('Cross-correlation');
title(sprintf('%s/%s mode: %s vs %s (n intervals = %d)', opts.timebase, opts.mode, gazeVar, targetVar, size(corrByInt, 1)), ...
    'Interpreter', 'none');
box off

out = struct();
out.lagsSec = lagsSec;
out.lagsSteps = lagsSteps;
out.meanCorr = meanCorr(:);
out.seCorr = seCorr(:);
out.corrByInt = corrByInt;
out.intervalInfo = intervalInfo;
out.stepHz = stepHz;
out.sampleHz = sampleHz;
out.corrHz = corrHz;
out.mode = opts.mode;
out.timebase = opts.timebase;
out.axisName = axisName;
end


function stepTable = collapseIntervalToSteps(T, targetVar, gazeVar)
stepTable = table();
if isempty(T) || ~ismember('step', T.Properties.VariableNames)
    return
end

stepVals = double(T.step);
goodStep = isfinite(stepVals);
if ~any(goodStep)
    return
end
uSteps = unique(stepVals(goodStep));
nSteps = numel(uSteps);
targetVal = NaN(nSteps, 1);
gazeVal = NaN(nSteps, 1);
for k = 1:nSteps
    m = goodStep & (stepVals == uSteps(k));
    targetVal(k) = mean(double(T.(targetVar)(m)), 'omitnan');
    gazeVal(k) = mean(double(T.(gazeVar)(m)), 'omitnan');
end
stepTable = table(uSteps(:), targetVal, gazeVal, ...
    'VariableNames', {'step', 'targetVal', 'gazeVal'});
end
