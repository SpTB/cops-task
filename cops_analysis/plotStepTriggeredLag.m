function out = plotStepTriggeredLag(trackingTable, axisName, opts)
% plotStepTriggeredLag  Align gaze response to tracked-target step changes.
%
% This version assumes out.tracking includes a short pre-tracking window
% for each interval, so step changes just before tracking onset can still
% contribute to the estimate.
%
% out = plotStepTriggeredLag(t)
% out = plotStepTriggeredLag(t, 'x')
% out = plotStepTriggeredLag(t, 'y', opts)
%
% Inputs
%   trackingTable : out.tracking or out.samples from processCoPsEye
%   axisName      : 'x' (default) or 'y'
%   opts          : optional struct with fields:
%       .fsHz             (default 500)
%       .windowSec        (default [-0.1 0.2])
%       .minPreSec        (default 0.05)
%       .minPostSec       (default 0.10)
%       .minJumpPx        (default 1)
%       .signalMode       (default 'position') 'position' plots baseline-
%                         subtracted displacement; 'velocity' plots
%                         sample velocity in px/s
%       .alignSign        (default true) flip each event so positive means
%                         motion in the same direction as the target jump
%       .intervalVars     (default {'trial','intervalNo'})
%       .lineColorTarget  (default [0.2 0.2 0.2])
%       .lineColorGaze    (default [0.8 0 0])
%       .plotTarget       (default true)
%       .separateAxes     (default false) plot target and gaze on separate
%                         y-axes; useful for velocity mode
%       .newFigure        (default true)
%
% Output
%   out.tSec            : aligned time axis
%   out.meanTargetDelta : mean target displacement around step change
%   out.meanGazeDelta   : mean gaze displacement around step change
%   out.seTargetDelta   : SE across events
%   out.seGazeDelta     : SE across events
%   out.targetMat       : one row per event
%   out.gazeMat         : one row per event
%   out.eventTable      : source event metadata

if nargin < 2 || isempty(axisName)
    axisName = 'x';
end
if nargin < 3 || isempty(opts)
    opts = struct();
end

axisName = validatestring(char(string(axisName)), {'x', 'y'});
userProvidedIntervalVars = isfield(opts, 'intervalVars');

defaults = struct( ...
    'fsHz', 500, ...
    'windowSec', [-0.1 0.2], ...
    'minPreSec', 0.05, ...
    'minPostSec', 0.10, ...
    'minJumpPx', 1, ...
    'signalMode', 'position', ...
    'alignSign', true, ...
    'intervalVars', {{'trial', 'intervalNo'}}, ...
    'lineColorTarget', [0.2 0.2 0.2], ...
    'lineColorGaze', [0.8 0 0], ...
    'plotTarget', true, ...
    'separateAxes', false, ...
    'newFigure', true);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field)
        opts.(field) = defaults.(field);
    end
end
opts.signalMode = validatestring(char(string(opts.signalMode)), {'position', 'velocity'});

if ~istable(trackingTable) || isempty(trackingTable)
    error('plotStepTriggeredLag:InvalidTrackingTable', ...
        'trackingTable must be a non-empty table, typically out.tracking.');
end

[targetVar, gazeVar, timeVar, opts.intervalVars] = localResolveInputVars( ...
    trackingTable, axisName, opts.intervalVars, userProvidedIntervalVars);
hasSampleIdx = ismember('sampleIdx', trackingTable.Properties.VariableNames);

requiredVars = unique([opts.intervalVars(:)', ...
    {'step', timeVar, targetVar, gazeVar}], 'stable');
if hasSampleIdx
    requiredVars = unique([requiredVars, {'sampleIdx'}], 'stable');
end
missingVars = setdiff(requiredVars, trackingTable.Properties.VariableNames, 'stable');
if ~isempty(missingVars)
    error('plotStepTriggeredLag:MissingVars', ...
        'Missing required tracking columns: %s', strjoin(missingVars, ', '));
end

fsHz = double(opts.fsHz);
if ~isfinite(fsHz) || fsHz <= 0
    error('plotStepTriggeredLag:BadFs', ...
        'opts.fsHz must be a finite positive sampling rate.');
end

offsetSamp = (round(opts.windowSec(1) * fsHz):round(opts.windowSec(2) * fsHz))';
tAxis = offsetSamp / fsHz;
nWin = numel(offsetSamp);
preNeed = round(opts.minPreSec * fsHz);
postNeed = round(opts.minPostSec * fsHz);

[groupIdx, intervalInfo] = findgroups(trackingTable(:, opts.intervalVars));
nIntervals = max(groupIdx);
targetCells = cell(0, 1);
gazeCells = cell(0, 1);
eventRows = struct([]);

for i = 1:nIntervals
    m = (groupIdx == i);
    T = trackingTable(m, :);
    if hasSampleIdx
        [~, ord] = sort(T.sampleIdx);
    else
        [~, ord] = sort(T.(timeVar));
    end
    T = T(ord, :);

    stepVals = double(T.step);
    targetVals = double(T.(targetVar));
    gazeVals = double(T.(gazeVar));
    if hasSampleIdx
        sampleIdx = double(T.sampleIdx);
    else
        sampleIdx = (1:height(T))';
    end
    timeVals = double(T.(timeVar));
    good = isfinite(stepVals) & isfinite(targetVals) & isfinite(gazeVals) & ...
        isfinite(sampleIdx) & isfinite(timeVals);
    if nnz(good) < 3
        continue
    end
    stepVals = stepVals(good);
    targetVals = targetVals(good);
    gazeVals = gazeVals(good);
    sampleIdx = sampleIdx(good);
    timeVals = timeVals(good);
    [targetVel, gazeVel] = localSampleVelocity(targetVals, gazeVals, timeVals, sampleIdx, fsHz);

    rowPosChange = find(diff(stepVals) ~= 0) + 1;
    for j = 1:numel(rowPosChange)
        idx0 = rowPosChange(j);
        prevIdx = idx0 - 1;
        jumpPx = targetVals(idx0) - targetVals(prevIdx);
        if ~isfinite(jumpPx) || abs(jumpPx) < opts.minJumpPx
            continue
        end

        eventTime = timeVals(idx0);
        relSamp = round((timeVals - eventTime) .* fsHz);
        preCount = sum(relSamp >= offsetSamp(1) & relSamp < 0);
        postCount = sum(relSamp >= 0 & relSamp <= offsetSamp(end));
        if preCount < preNeed || postCount < postNeed
            continue
        end

        targetTrace = NaN(nWin, 1);
        gazeTrace = NaN(nWin, 1);
        use = relSamp >= offsetSamp(1) & relSamp <= offsetSamp(end);
        if ~any(use)
            continue
        end
        relUse = relSamp(use);
        slot = relUse - offsetSamp(1) + 1;
        switch opts.signalMode
            case 'position'
                targetTrace(slot) = targetVals(use);
                gazeTrace(slot) = gazeVals(use);

                targetBase = targetVals(prevIdx);
                gazeBase = gazeVals(prevIdx);
                targetTrace = targetTrace - targetBase;
                gazeTrace = gazeTrace - gazeBase;
            case 'velocity'
                targetTrace(slot) = targetVel(use);
                gazeTrace(slot) = gazeVel(use);
        end
        if opts.alignSign
            targetTrace = sign(jumpPx) .* targetTrace;
            gazeTrace = sign(jumpPx) .* gazeTrace;
        end

        targetCells{end+1, 1} = targetTrace(:)'; %#ok<AGROW>
        gazeCells{end+1, 1} = gazeTrace(:)'; %#ok<AGROW>

        row = table2struct(intervalInfo(i, :));
        row.eventSampleIdx = sampleIdx(idx0);
        row.eventTimeSec = eventTime;
        if strcmp(timeVar, 'tFromTrackingOnsetSec')
            row.eventTimeFromTrackingOnsetSec = eventTime;
        elseif strcmp(timeVar, 'tRelSec')
            row.eventTimeRelSec = eventTime;
        end
        row.stepBefore = stepVals(prevIdx);
        row.stepAfter = stepVals(idx0);
        row.jumpPx = jumpPx;
        eventRows = appendStructRowLocal(eventRows, row);
    end
end

if isempty(targetCells)
    error('plotStepTriggeredLag:NoUsableEvents', ...
        'No usable step-change events were found for axis %s.', axisName);
end

targetMat = vertcat(targetCells{:});
gazeMat = vertcat(gazeCells{:});
meanTargetDelta = mean(targetMat, 1, 'omitnan');
meanGazeDelta = mean(gazeMat, 1, 'omitnan');
if size(targetMat, 1) == 1
    seTargetDelta = zeros(size(meanTargetDelta));
    seGazeDelta = zeros(size(meanGazeDelta));
else
    seTargetDelta = std(targetMat, 0, 1, 'omitnan') ./ sqrt(sum(isfinite(targetMat), 1));
    seGazeDelta = std(gazeMat, 0, 1, 'omitnan') ./ sqrt(sum(isfinite(gazeMat), 1));
end

if opts.newFigure
    figure;
end
hold on
if logical(opts.separateAxes) && logical(opts.plotTarget)
    yyaxis left
    fillBandLocal(tAxis, meanTargetDelta, seTargetDelta, opts.lineColorTarget);
    plot(tAxis, meanTargetDelta, 'Color', opts.lineColorTarget, 'LineWidth', 1.5);
    ylabel(localSignalYLabel(opts.signalMode, opts.alignSign, "target"));
    yyaxis right
    fillBandLocal(tAxis, meanGazeDelta, seGazeDelta, opts.lineColorGaze);
    plot(tAxis, meanGazeDelta, 'Color', opts.lineColorGaze, 'LineWidth', 1.5);
    ylabel(localSignalYLabel(opts.signalMode, opts.alignSign, "gaze"));
else
    if logical(opts.plotTarget)
        fillBandLocal(tAxis, meanTargetDelta, seTargetDelta, opts.lineColorTarget);
    end
    fillBandLocal(tAxis, meanGazeDelta, seGazeDelta, opts.lineColorGaze);
    if logical(opts.plotTarget)
        plot(tAxis, meanTargetDelta, 'Color', opts.lineColorTarget, 'LineWidth', 1.5);
    end
    plot(tAxis, meanGazeDelta, 'Color', opts.lineColorGaze, 'LineWidth', 1.5);
end
xline(0, ':', 'Color', [0.4 0.4 0.4]);
yline(0, ':', 'Color', [0.4 0.4 0.4]);
xlabel('Time from step change (s)');
if ~(logical(opts.separateAxes) && logical(opts.plotTarget))
    ylabel(localSignalYLabel(opts.signalMode, opts.alignSign, ""));
end
if logical(opts.plotTarget)
    legend({'target \pm SE', 'gaze \pm SE', 'target', 'gaze'}, 'Location', 'best');
else
    legend({'gaze \pm SE', 'gaze'}, 'Location', 'best');
end
title(sprintf('Step-triggered %s (%s axis, n events = %d)', opts.signalMode, axisName, size(targetMat, 1)));
box off

eventTable = struct2table(eventRows, 'AsArray', true);

out = struct();
out.tSec = tAxis;
out.meanTargetDelta = meanTargetDelta(:);
out.meanGazeDelta = meanGazeDelta(:);
out.seTargetDelta = seTargetDelta(:);
out.seGazeDelta = seGazeDelta(:);
out.targetMat = targetMat;
out.gazeMat = gazeMat;
out.eventTable = eventTable;
out.alignSign = logical(opts.alignSign);
out.signalMode = opts.signalMode;
end


function [targetVar, gazeVar, timeVar, intervalVars] = localResolveInputVars(T, axisName, intervalVars, userProvidedIntervalVars)
vars = T.Properties.VariableNames;

gazeVar = 'xPx';
targetCandidates = {'trackedTargetX', 'targetX'};
if strcmp(axisName, 'y')
    gazeVar = 'yPx';
    targetCandidates = {'trackedTargetY', 'targetY'};
end
if ~ismember(gazeVar, vars)
    error('plotStepTriggeredLag:MissingVars', ...
        'Missing required gaze column: %s.', gazeVar);
end
targetVar = '';
for i = 1:numel(targetCandidates)
    if ismember(targetCandidates{i}, vars)
        targetVar = targetCandidates{i};
        break
    end
end
if isempty(targetVar)
    error('plotStepTriggeredLag:MissingVars', ...
        'Missing target column for %s axis. Expected one of: %s.', ...
        axisName, strjoin(targetCandidates, ', '));
end

if ismember('tFromTrackingOnsetSec', vars)
    timeVar = 'tFromTrackingOnsetSec';
elseif ismember('tRelSec', vars)
    timeVar = 'tRelSec';
else
    error('plotStepTriggeredLag:MissingVars', ...
        'Missing time column. Expected tFromTrackingOnsetSec or tRelSec.');
end

if ischar(intervalVars) || (isstring(intervalVars) && isscalar(intervalVars))
    intervalVars = {char(string(intervalVars))};
end
intervalVars = intervalVars(:)';
if isempty(intervalVars)
    intervalVars = localDefaultIntervalVars(vars);
elseif ~all(ismember(intervalVars, vars))
    defaultTrackingVars = {'trial', 'intervalNo'};
    if ~userProvidedIntervalVars && isequal(intervalVars, defaultTrackingVars) && ismember('trial', vars)
        intervalVars = {'trial'};
    else
        missing = setdiff(intervalVars, vars, 'stable');
        error('plotStepTriggeredLag:MissingVars', ...
            'Missing interval column(s): %s.', strjoin(missing, ', '));
    end
end
end


function intervalVars = localDefaultIntervalVars(vars)
if ismember('trial', vars) && ismember('intervalNo', vars)
    intervalVars = {'trial', 'intervalNo'};
elseif ismember('trial', vars)
    intervalVars = {'trial'};
else
    intervalVars = {};
end
end


function label = localSignalYLabel(signalMode, alignSign, traceName)
traceName = string(traceName);
prefix = "";
if strlength(traceName) > 0
    prefix = traceName + " ";
end
if alignSign
    if strcmp(signalMode, 'velocity')
        label = char(prefix + "velocity in jump direction (px/s)");
    else
        label = char(prefix + "displacement in jump direction (px)");
    end
else
    if strcmp(signalMode, 'velocity')
        label = char(prefix + "signed velocity (px/s)");
    else
        label = char(prefix + "signed displacement from pre-step baseline (px)");
    end
end
end


function [targetVel, gazeVel] = localSampleVelocity(targetVals, gazeVals, relOnsetT, sampleIdx, fsHz)
targetVals = double(targetVals(:));
gazeVals = double(gazeVals(:));
relOnsetT = double(relOnsetT(:));
sampleIdx = double(sampleIdx(:));
targetVel = NaN(size(targetVals));
gazeVel = NaN(size(gazeVals));
if numel(targetVals) < 2 || numel(gazeVals) ~= numel(targetVals)
    return
end

dt = diff(relOnsetT);
fallbackDt = diff(sampleIdx) ./ fsHz;
badDt = ~isfinite(dt) | dt <= 0;
dt(badDt) = fallbackDt(badDt);
good = isfinite(dt) & dt > 0;
targetDiff = diff(targetVals);
gazeDiff = diff(gazeVals);
assignIdx = find(good) + 1;
targetVel(assignIdx) = targetDiff(good) ./ dt(good);
gazeVel(assignIdx) = gazeDiff(good) ./ dt(good);
end


function fillBandLocal(x, y, se, color)
xx = [x(:); flipud(x(:))];
yy = [y(:) - se(:); flipud(y(:) + se(:))];
fill(xx, yy, color, 'FaceAlpha', 0.20, 'EdgeColor', 'none');
end


function rows = appendStructRowLocal(rows, row)
if isempty(rows)
    rows = row;
else
    rows(end+1, 1) = row; %#ok<AGROW>
end
end
