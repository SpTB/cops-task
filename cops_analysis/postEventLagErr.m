function out = postEventLagErr(ex, trialNo, opts)
% postEventLagErr  Post-event gaze error against target history.
%
%   out = postEventLagErr(ex)
%   out = postEventLagErr(ex, trialNo)
%   out = postEventLagErr(ex, trialNo, opts)
%
% For each event at time t_s, this computes
%
%   error(tau) = gaze(t_s + opts.postLagSec) - target(t_s - tau)
%
% over the requested target-history lags opts.tauSec. Scalar distance
% traces are nonnegative Euclidean distances. The default X/Y plot shows
% nonnegative absolute component displacement.
%
% Inputs
%   ex      : experiment struct with Trials
%   trialNo : []/'all', numeric trials, named code ('bg','vis','tnum','im'),
%             or combined named code cell like {'bg','vis'}
%   opts    : optional struct with fields:
%       .eventType     (default 'saccade') one of: 'saccade','switch'
%       .tauSec        (default 0:0.01:0.5) target-history lags
%       .tauMs         alias for .tauSec
%       .postLagSec    (default 0) gaze sample time after event
%       .postLagMs     alias for .postLagSec
%       .alignTo       (default 'stop') saccade event time: 'start','stop'
%       .targetMode    (default 'auto') one of:
%                       'auto','t1','t2','assigned','closestPost',
%                       'switchBefore','switchAfter'
%       .targetOrder   (default 'raw') one of: 'raw','canonical'
%       .errField      (default 'distDeg') one of:
%                       'distDeg','distPx','absXDeg','absXPx',
%                       'absYDeg','absYPx','xDeg','xPx','yDeg','yPx'
%       .plotMode      (default 'xy') one of: 'xy','field'
%       .componentUnits (default 'deg') one of: 'deg','px'
%       .componentMetric (default 'abs') one of: 'abs','signed'
%       .stat          (default 'mean') one of: 'mean','median'
%       .onlyGoState   (default true)
%       .useEyeTime    (default false)
%       .lowpassHz     (default [])
%       .interpBlinkSec (default 0.15)
%       .truncateTrialFromStep (default 0)
%       .timeWindowSec (default [])
%       .switchRequireSaccade (default false)
%       .betweenMarginPx (default graph.radius*graph.size_mult/2)
%       .speedThreshDegPerSec (default 10)
%       .minAmpDeg     (default 1)
%       .minDurSec     (default 0.008)
%       .maxDurSec     (default 5)
%       .smoothFrames  (default 5)
%       .plot          (default false)
%       .newFigure     (default true)
%       .showLegend    (default false)
%       .legendMaxGroups (default 12)
%       .labelLineEnds (default true)
%       .lineWidth     (default 1.5)
%       .colors        (default lines(nGroup))
%
% Output
%   out.rows                one row per event x tau
%   out.groups{i}.tauSec
%   out.groups{i}.errTraceX
%   out.groups{i}.errTraceY
%   out.groups{i}.errTrace      selected scalar opts.errField trace
%   out.groups{i}.traces        all scalar/component traces
%   out.groups{i}.nEventsPerTau
%   out.groups{i}.nEvents

if nargin < 2
    trialNo = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
if ~isstruct(ex) || ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('postEventLagErr:BadInput', 'First input must be an ex struct with Trials.');
end
if ~isstruct(opts)
    error('postEventLagErr:BadOpts', 'Third argument must be an opts struct.');
end

defaults = struct( ...
    'eventType', 'saccade', ...
    'tauSec', 0:0.05:2, ...
    'tauMs', [], ...
    'postLagSec', 0, ...
    'postLagMs', [], ...
    'alignTo', 'stop', ...
    'targetMode', 'auto', ...
    'targetOrder', 'raw', ...
    'errField', 'distDeg', ...
    'plotMode', 'xy', ...
    'componentUnits', 'deg', ...
    'componentMetric', 'abs', ...
    'stat', 'mean', ...
    'onlyGoState', true, ...
    'useEyeTime', false, ...
    'lowpassHz', [], ...
    'interpBlinkSec', 0.15, ...
    'truncateTrialFromStep', 0, ...
    'timeWindowSec', [], ...
    'switchRequireSaccade', false, ...
    'betweenMarginPx', [], ...
    'speedThreshDegPerSec', 10, ...
    'minAmpDeg', 1, ...
    'minDurSec', 0.008, ...
    'maxDurSec', 5, ...
    'smoothFrames', 5, ...
    'plot', 1, ...
    'newFigure', true, ...
    'showLegend', false, ...
    'legendMaxGroups', 12, ...
    'labelLineEnds', true, ...
    'lineWidth', 1.5, ...
    'colors', []);
opts = localApplyLegacySaccadeAliases(opts);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field) || isempty(opts.(field))
        opts.(field) = defaults.(field);
    end
end

if ~isempty(opts.tauMs)
    opts.tauSec = double(opts.tauMs(:)') ./ 1000;
end
if ~isempty(opts.postLagMs)
    opts.postLagSec = double(localFirstScalar(opts.postLagMs)) ./ 1000;
end
opts.eventType = localResolveEventType(opts.eventType);
opts.alignTo = validatestring(char(string(opts.alignTo)), {'start', 'stop'});
opts.targetMode = localResolveTargetMode(opts.targetMode);
opts.targetOrder = validatestring(char(string(opts.targetOrder)), {'raw', 'canonical'});
opts.errField = validatestring(char(string(opts.errField)), ...
    {'distDeg','distPx','absXDeg','absXPx','absYDeg','absYPx','xDeg','xPx','yDeg','yPx'});
opts.plotMode = validatestring(char(string(opts.plotMode)), {'xy', 'field'});
opts.componentUnits = validatestring(char(string(opts.componentUnits)), {'deg', 'px'});
opts.componentMetric = validatestring(char(string(opts.componentMetric)), {'abs', 'signed'});
opts.stat = validatestring(char(string(opts.stat)), {'mean', 'median'});
if ismember(char(string(opts.errField)), {'xDeg','xPx','yDeg','yPx'})
    warning('postEventLagErr:SignedErrorField', ...
        'opts.errField=%s is signed gaze-target error. Use ''distDeg'' for nonnegative Euclidean distance error.', ...
        char(string(opts.errField)));
end
opts.tauSec = double(opts.tauSec(:)');
if isempty(opts.tauSec) || any(~isfinite(opts.tauSec)) || any(opts.tauSec < 0)
    error('postEventLagErr:BadTau', 'opts.tauSec must contain finite nonnegative lags.');
end
opts.tauSec = unique(opts.tauSec, 'stable');
opts.postLagSec = double(localFirstScalar(opts.postLagSec));
if ~isfinite(opts.postLagSec)
    error('postEventLagErr:BadPostLag', 'opts.postLagSec must be a finite scalar.');
end
opts.betweenMarginPx = double(localFirstScalar(opts.betweenMarginPx));
if ~isfinite(opts.betweenMarginPx)
    opts.betweenMarginPx = localDefaultBetweenMarginPx(ex);
end

trialGroups = localNormalizeTrialGroups(trialNo, ex);
groupLabels = localBuildGroupLabels(trialNo, trialGroups, ex);
nGroup = numel(trialGroups);
plotFacetSpec = localResolvePlotFacetSpec(trialNo, ex, nGroup);
if isempty(opts.colors)
    if plotFacetSpec.enabled
        baseColors = lines(plotFacetSpec.nLineGroups);
        opts.colors = baseColors(plotFacetSpec.lineGroupIndex, :);
    else
        opts.colors = lines(nGroup);
    end
else
    opts.colors = double(opts.colors);
    if size(opts.colors, 1) < nGroup || size(opts.colors, 2) ~= 3
        error('postEventLagErr:BadColors', 'opts.colors must be an nGroup x 3 RGB array.');
    end
end

groupRows = cell(nGroup, 1);
for g = 1:nGroup
    groupRows{g} = localBuildGroupRows(ex, trialGroups{g}, g, opts);
    if ~isempty(groupRows{g})
        groupRows{g}.groupLabel(:) = groupLabels(g);
    end
end

allRows = vertcat(groupRows{:});
groupOut = cell(nGroup, 1);
for g = 1:nGroup
    if isempty(allRows) || ~ismember('group', allRows.Properties.VariableNames)
        rows = table();
    else
        rows = allRows(double(allRows.group) == g, :);
    end
    groupOut{g} = localAggregateRows(rows, opts);
    groupOut{g}.groupLabel = groupLabels(g);
end

if logical(opts.plot)
    if opts.newFigure
        figure;
    end
    if strcmp(opts.plotMode, 'xy')
        if plotFacetSpec.enabled
            tiledlayout(plotFacetSpec.nRows, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
            for iRow = 1:plotFacetSpec.nRows
                nexttile;
                localPlotComponentGroups(groupOut, opts, 'x', plotFacetSpec.rowGroupIdx{iRow}, ...
                    plotFacetSpec.lineLabels, plotFacetSpec.rowLabels(iRow));
                nexttile;
                localPlotComponentGroups(groupOut, opts, 'y', plotFacetSpec.rowGroupIdx{iRow}, ...
                    plotFacetSpec.lineLabels, plotFacetSpec.rowLabels(iRow));
            end
        else
            tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
            nexttile;
            localPlotComponentGroups(groupOut, opts, 'x', 1:nGroup, cellstr(groupLabels), "");
            nexttile;
            localPlotComponentGroups(groupOut, opts, 'y', 1:nGroup, cellstr(groupLabels), "");
        end
        sgtitle(sprintf('%s-triggered post-event lag error (%s %s components)', ...
            char(string(opts.eventType)), char(string(opts.componentMetric)), ...
            char(string(opts.componentUnits))), 'Interpreter', 'none');
    else
        if plotFacetSpec.enabled
            tiledlayout(plotFacetSpec.nRows, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
            for iRow = 1:plotFacetSpec.nRows
                nexttile;
                localPlotGroups(groupOut, opts, plotFacetSpec.rowGroupIdx{iRow}, ...
                    plotFacetSpec.lineLabels, plotFacetSpec.rowLabels(iRow));
            end
        else
            if opts.newFigure
                axes;
            end
            localPlotGroups(groupOut, opts, 1:nGroup, cellstr(groupLabels), "");
        end
    end
end

out = struct();
out.rows = allRows;
out.groups = groupOut;
out.groupLabels = groupLabels;
out.groupSummary = localBuildGroupSummary(groupOut);
out.trialGroups = trialGroups;
out.trials = localFlattenTrialGroups(trialGroups);
out.tauSec = opts.tauSec(:);
out.eventType = string(opts.eventType);
out.targetMode = string(opts.targetMode);
out.targetOrder = string(opts.targetOrder);
out.postLagSec = opts.postLagSec;
out.alignTo = string(opts.alignTo);
out.errField = string(opts.errField);
out.plotMode = string(opts.plotMode);
out.componentUnits = string(opts.componentUnits);
out.componentMetric = string(opts.componentMetric);
out.stat = string(opts.stat);
out.options = opts;
end


function rows = localBuildGroupRows(ex, trialList, groupNo, opts)
rowCells = cell(numel(trialList), 1);
rowCount = 0;
for i = 1:numel(trialList)
    trialRows = localBuildTrialRows(ex, trialList(i), groupNo, opts);
    if isempty(trialRows)
        continue
    end
    rowCount = rowCount + 1;
    rowCells{rowCount, 1} = trialRows;
end
if rowCount == 0
    rows = table();
else
    rows = vertcat(rowCells{1:rowCount});
end
end


function rows = localBuildTrialRows(ex, trialIdx, groupNo, opts)
T = ex.Trials(trialIdx);
[xPx, yPx, tRel, tAbs, valid] = reconstructEyePx(ex, T, opts.useEyeTime, opts);
[targetX, targetY, target2X, target2Y, stepIdx] = mapTargetsByStep(ex, T, tRel);
if strcmp(opts.targetOrder, 'canonical')
    [targetX, targetY, target2X, target2Y] = localCanonicalizeTargetOrder(targetX, targetY, target2X, target2Y);
end

goMask = true(size(tRel));
if opts.onlyGoState && isfield(T, 'times') && isfield(T.times, 'stimOn') && isfield(T, 'TrialEnd')
    goMask = tAbs >= T.times.stimOn & tAbs <= T.TrialEnd;
end

xPx = xPx(goMask);
yPx = yPx(goMask);
tRel = tRel(goMask);
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
    valid = valid(keepMask);
    targetX = targetX(keepMask);
    targetY = targetY(keepMask);
    target2X = target2X(keepMask);
    target2Y = target2Y(keepMask);
    stepIdx = stepIdx(keepMask);
end

tw = localTimeWindow(opts.timeWindowSec);
if ~isempty(tw)
    keepMask = tRel >= tw(1) & tRel <= tw(2);
    xPx = xPx(keepMask);
    yPx = yPx(keepMask);
    tRel = tRel(keepMask);
    valid = valid(keepMask);
    targetX = targetX(keepMask);
    targetY = targetY(keepMask);
    target2X = target2X(keepMask);
    target2Y = target2Y(keepMask);
    stepIdx = stepIdx(keepMask);
end

if isempty(tRel) || numel(tRel) < 2
    rows = table();
    return
end

[texBounds, ~] = localTextureBounds(ex.setup.screenRect, ex.exp.CoPs.graph);
insideTexture = xPx >= texBounds.xMin & xPx <= texBounds.xMax & ...
    yPx >= texBounds.yMin & yPx <= texBounds.yMax;
xPx(~insideTexture) = NaN;
yPx(~insideTexture) = NaN;
valid = valid & insideTexture;
xPx(~valid) = NaN;
yPx(~valid) = NaN;

dtSec = localResolveSampleDt(tRel, 1 / inferFs(ex));
[xPx, yPx] = preprocessGazeForCcgCoPs(xPx, yPx, dtSec, opts.interpBlinkSec, opts.lowpassHz);
inBounds = insideTexture & isfinite(xPx) & isfinite(yPx);
assignedSample = localAssignedSample(xPx, yPx, targetX, targetY, target2X, target2Y, inBounds, stepIdx, opts);

switch opts.eventType
    case 'saccade'
        events = localBuildSaccadeEvents(xPx, yPx, tRel, dtSec, ex.setup, opts);
    case 'switch'
        events = localBuildSwitchEvents(xPx, yPx, tRel, stepIdx, targetX, targetY, ...
            target2X, target2Y, inBounds, dtSec, ex.setup, opts);
end
if isempty(events.eventIdx)
    rows = table();
    return
end

nTau = numel(opts.tauSec);
nMax = numel(events.eventIdx) * nTau;
group = NaN(nMax, 1);
groupLabel = repmat(string(missing), nMax, 1);
trial = NaN(nMax, 1);
eventNo = NaN(nMax, 1);
eventType = strings(nMax, 1);
eventIdx = NaN(nMax, 1);
eventTimeRelSec = NaN(nMax, 1);
saccStartIdx = NaN(nMax, 1);
saccStopIdx = NaN(nMax, 1);
targetBefore = NaN(nMax, 1);
targetAfter = NaN(nMax, 1);
switchStep = NaN(nMax, 1);
postIdx = NaN(nMax, 1);
postTimeRelSec = NaN(nMax, 1);
tauSec = NaN(nMax, 1);
targetRefIdx = NaN(nMax, 1);
targetRefSec = NaN(nMax, 1);
targetId = NaN(nMax, 1);
gazeXPx = NaN(nMax, 1);
gazeYPx = NaN(nMax, 1);
targetXPx = NaN(nMax, 1);
targetYPx = NaN(nMax, 1);
errXPx = NaN(nMax, 1);
errYPx = NaN(nMax, 1);
errPx = NaN(nMax, 1);
errXDeg = NaN(nMax, 1);
errYDeg = NaN(nMax, 1);
errDeg = NaN(nMax, 1);

rowCount = 0;
for e = 1:numel(events.eventIdx)
    thisEventTime = double(events.eventTimeRelSec(e));
    postSampleIdx = localIndexNearestTime(tRel, thisEventTime + opts.postLagSec);
    if isempty(postSampleIdx) || any(~isfinite([xPx(postSampleIdx), yPx(postSampleIdx)]))
        continue
    end
    postGaze = [double(xPx(postSampleIdx)), double(yPx(postSampleIdx))];
    eventTargetId = localResolveEventTargetId(opts, events, e, postSampleIdx, ...
        assignedSample, targetX, targetY, target2X, target2Y, postGaze);
    if ~isfinite(eventTargetId)
        continue
    end
    for k = 1:nTau
        refTime = thisEventTime - opts.tauSec(k);
        refIdx = localReferenceIndex(tRel, refTime);
        if isempty(refIdx)
            continue
        end
        [tx, ty, resolvedTargetId] = localTargetAtRef(targetX, targetY, target2X, target2Y, ...
            refIdx, eventTargetId, postGaze, opts.targetMode);
        if any(~isfinite([tx, ty]))
            continue
        end

        rowCount = rowCount + 1;
        group(rowCount) = groupNo;
        trial(rowCount) = trialIdx;
        eventNo(rowCount) = events.eventNo(e);
        eventType(rowCount) = string(opts.eventType);
        eventIdx(rowCount) = events.eventIdx(e);
        eventTimeRelSec(rowCount) = thisEventTime;
        saccStartIdx(rowCount) = events.saccStartIdx(e);
        saccStopIdx(rowCount) = events.saccStopIdx(e);
        targetBefore(rowCount) = events.targetBefore(e);
        targetAfter(rowCount) = events.targetAfter(e);
        switchStep(rowCount) = events.switchStep(e);
        postIdx(rowCount) = postSampleIdx;
        postTimeRelSec(rowCount) = double(tRel(postSampleIdx));
        tauSec(rowCount) = opts.tauSec(k);
        targetRefIdx(rowCount) = refIdx;
        targetRefSec(rowCount) = double(tRel(refIdx));
        targetId(rowCount) = resolvedTargetId;
        gazeXPx(rowCount) = postGaze(1);
        gazeYPx(rowCount) = postGaze(2);
        targetXPx(rowCount) = tx;
        targetYPx(rowCount) = ty;
        errXPx(rowCount) = postGaze(1) - tx;
        errYPx(rowCount) = postGaze(2) - ty;
        errPx(rowCount) = hypot(errXPx(rowCount), errYPx(rowCount));
        errXDeg(rowCount) = px2deg(errXPx(rowCount), ex.setup);
        errYDeg(rowCount) = px2deg(errYPx(rowCount), ex.setup);
        errDeg(rowCount) = px2deg(errPx(rowCount), ex.setup);
    end
end

if rowCount == 0
    rows = table();
else
    rows = table(group(1:rowCount), groupLabel(1:rowCount), trial(1:rowCount), ...
        eventNo(1:rowCount), eventType(1:rowCount), eventIdx(1:rowCount), ...
        eventTimeRelSec(1:rowCount), saccStartIdx(1:rowCount), saccStopIdx(1:rowCount), ...
        targetBefore(1:rowCount), targetAfter(1:rowCount), switchStep(1:rowCount), ...
        postIdx(1:rowCount), postTimeRelSec(1:rowCount), ...
        tauSec(1:rowCount), targetRefIdx(1:rowCount), targetRefSec(1:rowCount), targetId(1:rowCount), ...
        gazeXPx(1:rowCount), gazeYPx(1:rowCount), targetXPx(1:rowCount), targetYPx(1:rowCount), ...
        errXPx(1:rowCount), errYPx(1:rowCount), errPx(1:rowCount), ...
        errXDeg(1:rowCount), errYDeg(1:rowCount), errDeg(1:rowCount), ...
        'VariableNames', {'group','groupLabel','trial','eventNo','eventType','eventIdx', ...
        'eventTimeRelSec','saccStartIdx','saccStopIdx','targetBefore','targetAfter','switchStep', ...
        'postIdx','postTimeRelSec','tauSec','targetRefIdx','targetRefSec','targetId', ...
        'gazeXPx','gazeYPx','targetXPx','targetYPx','errXPx','errYPx','errPx', ...
        'errXDeg','errYDeg','errDeg'});
end
end


function groupOut = localAggregateRows(rows, opts)
tau = opts.tauSec(:);
fields = {'distDeg','distPx','absXDeg','absXPx','absYDeg','absYPx','xDeg','xPx','yDeg','yPx'};
traces = struct();
for i = 1:numel(fields)
    traces.(fields{i}) = localAggregateField(rows, tau, fields{i}, opts.stat);
end
errTrace = traces.(char(string(opts.errField))).value;
nEventsPerTau = traces.(char(string(opts.errField))).n;
[xField, yField] = localComponentTraceFields(opts.componentUnits, opts.componentMetric);
errTraceX = traces.(xField).value;
errTraceY = traces.(yField).value;

groupOut = struct();
groupOut.tauSec = tau;
groupOut.errTrace = errTrace;
groupOut.errTraceX = errTraceX;
groupOut.errTraceY = errTraceY;
groupOut.errField = string(opts.errField);
groupOut.errTraceXField = string(xField);
groupOut.errTraceYField = string(yField);
groupOut.plotMode = string(opts.plotMode);
groupOut.componentUnits = string(opts.componentUnits);
groupOut.componentMetric = string(opts.componentMetric);
if strcmp(opts.plotMode, 'xy')
    groupOut.plotFields = [string(xField), string(yField)];
else
    groupOut.plotFields = string(opts.errField);
end
groupOut.traces = traces;
groupOut.nEventsPerTau = nEventsPerTau;
groupOut.nEventsPerTauX = traces.(xField).n;
groupOut.nEventsPerTauY = traces.(yField).n;
groupOut.nEvents = localCountUniqueEvents(rows);
groupOut.nRows = height(rows);
groupOut.errTraceRange = localFiniteRange(errTrace);
groupOut.errTraceXRange = localFiniteRange(errTraceX);
groupOut.errTraceYRange = localFiniteRange(errTraceY);
groupOut.distDegRange = localFiniteRange(traces.distDeg.value);
groupOut.distDegMean = mean(traces.distDeg.value, 'omitnan');
groupOut.diagnostics = localTargetHistoryDiagnostics(rows, tau);
groupOut.rows = rows;
end


function trace = localAggregateField(rows, tau, errField, statName)
values = NaN(size(tau));
n = zeros(size(tau));
if ~isempty(rows)
    rowValue = localRowsErrorValue(rows, errField);
    for i = 1:numel(tau)
        keep = localTauMatch(rows.tauSec, tau(i)) & isfinite(rowValue);
        x = double(rowValue(keep));
        n(i) = numel(x);
        if isempty(x)
            continue
        end
        switch statName
            case 'mean'
                values(i) = mean(x, 'omitnan');
            case 'median'
                values(i) = median(x, 'omitnan');
        end
    end
end
trace = struct();
trace.value = values;
trace.n = n;
end


function r = localFiniteRange(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    r = NaN;
else
    r = max(x) - min(x);
end
end


function diagnostics = localTargetHistoryDiagnostics(rows, tau)
diagnostics = struct();
diagnostics.tauSec = tau(:);
diagnostics.targetChangeFrac = NaN(size(tau(:)));
diagnostics.meanTargetShiftPx = NaN(size(tau(:)));
diagnostics.meanActualRefLagSec = NaN(size(tau(:)));
diagnostics.nEventsWithReference = zeros(size(tau(:)));
diagnostics.baseTauSec = NaN;
if isempty(rows) || ~all(ismember({'trial','eventNo','tauSec','targetXPx','targetYPx','targetRefSec','eventTimeRelSec'}, rows.Properties.VariableNames))
    return
end

tau = tau(:);
diagnostics.baseTauSec = tau(1);
[eventGroup, ~] = findgroups(rows(:, {'trial','eventNo'}));
nEvent = max(eventGroup);
if isempty(nEvent) || ~isfinite(nEvent) || nEvent < 1
    return
end

baseX = NaN(nEvent, 1);
baseY = NaN(nEvent, 1);
for e = 1:nEvent
    idx = find(eventGroup == e & localTauMatch(rows.tauSec, tau(1)), 1, 'first');
    if isempty(idx)
        continue
    end
    baseX(e) = double(rows.targetXPx(idx));
    baseY(e) = double(rows.targetYPx(idx));
end

for i = 1:numel(tau)
    hasRef = false(nEvent, 1);
    changed = false(nEvent, 1);
    shiftPx = NaN(nEvent, 1);
    actualLag = NaN(nEvent, 1);
    for e = 1:nEvent
        idx = find(eventGroup == e & localTauMatch(rows.tauSec, tau(i)), 1, 'first');
        if isempty(idx)
            continue
        end
        tx = double(rows.targetXPx(idx));
        ty = double(rows.targetYPx(idx));
        if any(~isfinite([tx, ty, baseX(e), baseY(e)]))
            continue
        end
        hasRef(e) = true;
        shiftPx(e) = hypot(tx - baseX(e), ty - baseY(e));
        changed(e) = shiftPx(e) > 0;
        actualLag(e) = double(rows.eventTimeRelSec(idx)) - double(rows.targetRefSec(idx));
    end
    diagnostics.nEventsWithReference(i) = nnz(hasRef);
    if any(hasRef)
        diagnostics.targetChangeFrac(i) = mean(changed(hasRef), 'omitnan');
        diagnostics.meanTargetShiftPx(i) = mean(shiftPx(hasRef), 'omitnan');
        diagnostics.meanActualRefLagSec(i) = mean(actualLag(hasRef), 'omitnan');
    end
end
end


function tf = localTauMatch(rowTau, tau)
tf = abs(double(rowTau) - double(tau)) <= max(eps(double(tau)) * 8, 1e-12);
end


function events = localBuildSaccadeEvents(xPx, yPx, tRel, dtSec, setup, opts)
params = localBuildSaccadeParams(dtSec, opts);
[saccStarts, saccStops] = detectTrackingSaccadesCoPs(xPx, yPx, dtSec, setup, params);
if isempty(saccStarts)
    events = localEmptyEvents();
    return
end
if strcmp(opts.alignTo, 'start')
    eventIdx = double(saccStarts(:));
else
    eventIdx = double(saccStops(:));
end
nEvent = numel(eventIdx);
events = struct();
events.eventNo = (1:nEvent)';
events.eventIdx = eventIdx;
events.eventTimeRelSec = double(tRel(eventIdx));
events.saccStartIdx = double(saccStarts(:));
events.saccStopIdx = double(saccStops(:));
events.targetBefore = NaN(nEvent, 1);
events.targetAfter = NaN(nEvent, 1);
events.switchStep = NaN(nEvent, 1);
end


function events = localBuildSwitchEvents(xPx, yPx, tRel, stepIdx, targetX, targetY, target2X, target2Y, inBounds, dtSec, setup, opts)
hasT2 = any(isfinite(target2X(:)) & isfinite(target2Y(:)));
if ~hasT2
    events = localEmptyEvents();
    return
end
distPx1 = computeDistanceToTargets(xPx, yPx, targetX, targetY, inBounds);
distPx2 = computeDistanceToTargets(xPx, yPx, target2X, target2Y, inBounds);
assign = assignTargetIdentityCoPs(distPx1, distPx2, inBounds, opts.betweenMarginPx, stepIdx);
if isempty(assign.step) || isempty(assign.assignedStep)
    events = localEmptyEvents();
    return
end

uStep = double(assign.step(:));
assignedStep = double(assign.assignedStep(:));
stepTimes = NaN(size(uStep));
stepStartIdx = NaN(size(uStep));
for k = 1:numel(uStep)
    idx = find(isfinite(stepIdx) & stepIdx == uStep(k) & isfinite(tRel), 1, 'first');
    if ~isempty(idx)
        stepStartIdx(k) = idx;
        stepTimes(k) = double(tRel(idx));
    end
end

validStep = isfinite(uStep) & isfinite(stepTimes) & assignedStep > 0;
seqAssigned = assignedStep(validStep);
seqTimes = stepTimes(validStep);
seqStartIdx = stepStartIdx(validStep);
seqStep = uStep(validStep);
if numel(seqAssigned) < 2
    events = localEmptyEvents();
    return
end

switchMask = [false; diff(seqAssigned) ~= 0];
if logical(opts.switchRequireSaccade)
    stepHasSaccade = localStepHasSaccade(xPx, yPx, stepIdx, uStep, dtSec, setup, opts);
    seqStepHasSaccade = stepHasSaccade(validStep);
    switchMask = switchMask & seqStepHasSaccade(:);
end
switchIdx = find(switchMask);
if isempty(switchIdx)
    events = localEmptyEvents();
    return
end

nEvent = numel(switchIdx);
events = struct();
events.eventNo = (1:nEvent)';
events.eventIdx = double(seqStartIdx(switchIdx));
events.eventTimeRelSec = double(seqTimes(switchIdx));
events.saccStartIdx = NaN(nEvent, 1);
events.saccStopIdx = NaN(nEvent, 1);
events.targetBefore = double(seqAssigned(switchIdx - 1));
events.targetAfter = double(seqAssigned(switchIdx));
events.switchStep = double(seqStep(switchIdx));
end


function events = localEmptyEvents()
events = struct();
events.eventNo = zeros(0, 1);
events.eventIdx = zeros(0, 1);
events.eventTimeRelSec = zeros(0, 1);
events.saccStartIdx = zeros(0, 1);
events.saccStopIdx = zeros(0, 1);
events.targetBefore = zeros(0, 1);
events.targetAfter = zeros(0, 1);
events.switchStep = zeros(0, 1);
end


function assignedSample = localAssignedSample(xPx, yPx, targetX, targetY, target2X, target2Y, inBounds, stepIdx, opts)
assignedSample = NaN(size(xPx(:)));
if ~any(isfinite(target2X(:)) & isfinite(target2Y(:)))
    assignedSample(:) = 1;
    return
end
distPx1 = computeDistanceToTargets(xPx, yPx, targetX, targetY, inBounds);
distPx2 = computeDistanceToTargets(xPx, yPx, target2X, target2Y, inBounds);
assign = assignTargetIdentityCoPs(distPx1, distPx2, inBounds, opts.betweenMarginPx, stepIdx);
assignedSample = double(assign.assignedSample(:));
assignedSample(assignedSample <= 0) = NaN;
end


function targetId = localResolveEventTargetId(opts, events, eventNo, postIdx, assignedSample, targetX, targetY, target2X, target2Y, postGaze)
switch opts.targetMode
    case 't1'
        targetId = 1;
    case 't2'
        targetId = 2;
    case 'switchbefore'
        targetId = events.targetBefore(eventNo);
    case 'switchafter'
        targetId = events.targetAfter(eventNo);
    case 'closestpost'
        targetId = localClosestTargetId(targetX, targetY, target2X, target2Y, postIdx, postGaze);
    case {'auto', 'assigned'}
        if strcmp(opts.eventType, 'switch') && isfinite(events.targetAfter(eventNo))
            targetId = events.targetAfter(eventNo);
        elseif numel(assignedSample) >= postIdx && isfinite(assignedSample(postIdx))
            targetId = assignedSample(postIdx);
        else
            targetId = localClosestTargetId(targetX, targetY, target2X, target2Y, postIdx, postGaze);
        end
    otherwise
        targetId = NaN;
end
if ~isfinite(targetId)
    targetId = NaN;
end
end


function [tx, ty, targetId] = localTargetAtRef(targetX, targetY, target2X, target2Y, refIdx, targetId, postGaze, targetMode)
if strcmp(targetMode, 'closestpost')
    targetId = localClosestTargetId(targetX, targetY, target2X, target2Y, refIdx, postGaze);
end
if targetId == 2
    tx = double(target2X(refIdx));
    ty = double(target2Y(refIdx));
else
    targetId = 1;
    tx = double(targetX(refIdx));
    ty = double(targetY(refIdx));
end
end


function targetId = localClosestTargetId(targetX, targetY, target2X, target2Y, idx, gazePos)
targetId = NaN;
if isempty(idx) || idx < 1 || idx > numel(targetX) || any(~isfinite(gazePos))
    return
end
d1 = hypot(gazePos(1) - double(targetX(idx)), gazePos(2) - double(targetY(idx)));
d2 = hypot(gazePos(1) - double(target2X(idx)), gazePos(2) - double(target2Y(idx)));
if isfinite(d1) && (~isfinite(d2) || d1 <= d2)
    targetId = 1;
elseif isfinite(d2)
    targetId = 2;
end
end


function stepHasSaccade = localStepHasSaccade(xPx, yPx, stepIdx, steps, dtSec, setup, opts)
stepHasSaccade = false(size(steps(:)));
[~, saccStops] = detectTrackingSaccadesCoPs(xPx, yPx, dtSec, setup, localBuildSaccadeParams(dtSec, opts));
if isempty(saccStops)
    return
end
saccadeStep = stepIdx(saccStops);
for i = 1:numel(steps)
    stepHasSaccade(i) = any(saccadeStep == steps(i));
end
end


function idx = localIndexNearestTime(tRel, queryTime)
idx = [];
if isempty(tRel) || ~isfinite(queryTime)
    return
end
valid = isfinite(tRel);
if ~any(valid)
    return
end
[~, idxValid] = min(abs(double(tRel(valid)) - queryTime));
allIdx = find(valid);
idx = allIdx(idxValid);
end


function idx = localReferenceIndex(tRel, refTime)
idx = find(isfinite(tRel) & double(tRel) <= refTime, 1, 'last');
if isempty(idx)
    idx = find(isfinite(tRel), 1, 'first');
end
end


function value = localRowsErrorValue(rows, errField)
switch errField
    case 'distPx'
        value = rows.errPx;
    case 'distDeg'
        value = rows.errDeg;
    case 'absXPx'
        value = abs(rows.errXPx);
    case 'absXDeg'
        value = abs(rows.errXDeg);
    case 'absYPx'
        value = abs(rows.errYPx);
    case 'absYDeg'
        value = abs(rows.errYDeg);
    case 'xPx'
        value = rows.errXPx;
    case 'xDeg'
        value = rows.errXDeg;
    case 'yPx'
        value = rows.errYPx;
    case 'yDeg'
        value = rows.errYDeg;
end
end


function n = localCountUniqueEvents(rows)
n = 0;
if isempty(rows) || ~all(ismember({'trial','eventNo'}, rows.Properties.VariableNames))
    return
end
[G, ~] = findgroups(rows(:, {'trial','eventNo'}));
n = max(G);
if isempty(n) || ~isfinite(n)
    n = 0;
end
end


function eventType = localResolveEventType(value)
value = lower(strtrim(char(string(value))));
switch value
    case {'sac','sacc','saccade'}
        eventType = 'saccade';
    case {'sw','switch'}
        eventType = 'switch';
    otherwise
        error('postEventLagErr:BadEventType', ...
            'opts.eventType must be ''saccade'' or ''switch''.');
end
end


function targetMode = localResolveTargetMode(value)
value = lower(strtrim(char(string(value))));
switch value
    case {'auto','assigned','t1','t2','closestpost'}
        targetMode = value;
    case {'before','switchbefore','targetbefore'}
        targetMode = 'switchbefore';
    case {'after','switchafter','targetafter'}
        targetMode = 'switchafter';
    otherwise
        error('postEventLagErr:BadTargetMode', ...
            'Unsupported opts.targetMode: %s.', value);
end
end


function [targetX, targetY, target2X, target2Y] = localCanonicalizeTargetOrder(targetX, targetY, target2X, target2Y)
swapMask = isfinite(targetX) & isfinite(targetY) & isfinite(target2X) & isfinite(target2Y) & ...
    ((targetX > target2X) | ((targetX == target2X) & (targetY > target2Y)));
tmpX = targetX(swapMask);
tmpY = targetY(swapMask);
targetX(swapMask) = target2X(swapMask);
targetY(swapMask) = target2Y(swapMask);
target2X(swapMask) = tmpX;
target2Y(swapMask) = tmpY;
end


function params = localBuildSaccadeParams(dtSec, opts)
params = struct();
params.preSaccadeWindowFrames = 3;
params.speedThreshDegPerSec = double(localFirstScalar(opts.speedThreshDegPerSec));
if ~isfinite(params.speedThreshDegPerSec) || params.speedThreshDegPerSec <= 0
    params.speedThreshDegPerSec = 10;
end
params.minAmpDeg = double(localFirstScalar(opts.minAmpDeg));
params.minDurSec = double(localFirstScalar(opts.minDurSec));
params.maxDurSec = double(localFirstScalar(opts.maxDurSec));
params.smoothFrames = max(1, round(double(localFirstScalar(opts.smoothFrames))));
if ~isfinite(dtSec) || dtSec <= 0
    params.preSaccadeWindowFrames = max(1, params.preSaccadeWindowFrames);
    params.minDurFrames = 1;
    params.maxDurFrames = inf;
else
    params.preSaccadeWindowSec = params.preSaccadeWindowFrames * dtSec;
    params.minDurFrames = max(1, round(params.minDurSec / dtSec));
    if isfinite(params.maxDurSec)
        params.maxDurFrames = max(params.minDurFrames, round(params.maxDurSec / dtSec));
    else
        params.maxDurFrames = inf;
    end
end
end


function labels = localBuildGroupLabels(trialNo, trialGroups, ex)
nGroup = numel(trialGroups);
labels = strings(nGroup, 1);
if isempty(trialGroups)
    return
end
if isempty(trialNo)
    labels(:) = "all";
    return
end
if ischar(trialNo) || (isstring(trialNo) && isscalar(trialNo))
    codeList = {char(string(trialNo))};
elseif localIsNamedCodeCell(trialNo)
    codeList = cellfun(@(x) char(string(x)), trialNo, 'UniformOutput', false);
else
    for i = 1:nGroup
        labels(i) = "group " + string(i);
    end
    return
end
for i = 1:nGroup
    tr = trialGroups{i}(1);
    T = ex.Trials(tr);
    parts = strings(0, 1);
    for k = 1:numel(codeList)
        code = lower(strtrim(codeList{k}));
        switch code
            case 'all'
                parts(end+1,1) = "all"; %#ok<AGROW>
            case 'bg'
                parts(end+1,1) = "bg: " + string(localTrialBackgroundNoiseLevel(T)); %#ok<AGROW>
            case 'vis'
                parts(end+1,1) = "vis: " + string(localTrialTargetVisibility(ex, T)); %#ok<AGROW>
            case 'tnum'
                parts(end+1,1) = "tnum: " + string(localTrialTargetNum(ex, T)); %#ok<AGROW>
            case 'im'
                parts(end+1,1) = "im: " + localTrialImageName(ex, T, tr); %#ok<AGROW>
            otherwise
                parts(end+1,1) = "group " + string(i); %#ok<AGROW>
        end
    end
    labels(i) = strjoin(parts, " | ");
end
end


function trialGroups = localNormalizeTrialGroups(trialNo, ex)
if isempty(trialNo) || localIsAllCode(trialNo)
    trialGroups = {1:numel(ex.Trials)};
    return
end
if ischar(trialNo) || (isstring(trialNo) && isscalar(trialNo))
    trialGroups = localResolveNamedTrialGroups(char(string(trialNo)), ex);
    return
end
nTrials = numel(ex.Trials);
if iscell(trialNo)
    if localIsNamedCodeCell(trialNo)
        trialGroups = localCombineNamedTrialGroups(trialNo, ex);
        return
    end
    trialGroups = cell(size(trialNo));
    for i = 1:numel(trialNo)
        trialGroups{i} = localValidateTrialVector(trialNo{i}, nTrials);
    end
else
    trialGroups = {localValidateTrialVector(trialNo, nTrials)};
end
end


function tf = localIsNamedCodeCell(trialNo)
tf = iscell(trialNo) && ~isempty(trialNo);
if ~tf
    return
end
for i = 1:numel(trialNo)
    item = trialNo{i};
    if ~(ischar(item) || (isstring(item) && isscalar(item)))
        tf = false;
        return
    end
end
end


function trialGroups = localCombineNamedTrialGroups(codeList, ex)
trialGroups = {1:numel(ex.Trials)};
for k = 1:numel(codeList)
    code = char(string(codeList{k}));
    nextGroups = localResolveNamedTrialGroups(code, ex);
    combined = {};
    nOut = 0;
    for i = 1:numel(trialGroups)
        for j = 1:numel(nextGroups)
            g = intersect(trialGroups{i}, nextGroups{j}, 'stable');
            if ~isempty(g)
                nOut = nOut + 1;
                combined{nOut,1} = g; %#ok<AGROW>
            end
        end
    end
    trialGroups = combined;
    if isempty(trialGroups)
        break
    end
end
if isempty(trialGroups)
    error('postEventLagErr:NamedGroupEmpty', ...
        'No trials remained after combining the requested named groupings.');
end
end


function trialGroups = localResolveNamedTrialGroups(code, ex)
code = lower(strtrim(code));
switch code
    case 'all'
        trialGroups = {1:numel(ex.Trials)};
    case {'bg', 'vis', 'tnum', 'im'}
        trialGroups = localResolveNamedTrialGroupsFromEx(code, ex);
    otherwise
        error('postEventLagErr:UnknownTrialCode', ...
            'Unknown trial grouping code ''%s''. Supported: ''all'', ''bg'', ''vis'', ''tnum'', ''im''.', code);
end
end


function trialGroups = localResolveNamedTrialGroupsFromEx(code, ex)
switch code
    case 'bg'
        values = NaN(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            values(j) = localTrialBackgroundNoiseLevel(ex.Trials(j));
        end
        levels = unique(values(isfinite(values)));
    case 'vis'
        values = NaN(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            values(j) = localTrialTargetVisibility(ex, ex.Trials(j));
        end
        levels = unique(values(isfinite(values)));
    case 'tnum'
        values = NaN(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            values(j) = localTrialTargetNum(ex, ex.Trials(j));
        end
        levels = unique(values(isfinite(values)));
    case 'im'
        values = strings(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            values(j) = localTrialImageName(ex, ex.Trials(j), j);
        end
        levels = unique(values(values ~= "" & ~ismissing(values)), 'stable');
end
if isempty(levels)
    error('postEventLagErr:NamedGroupEmpty', ...
        'No trials had usable values for grouping code ''%s''.', code);
end
trialGroups = cell(numel(levels), 1);
for i = 1:numel(levels)
    trialGroups{i} = find(values == levels(i));
end
end


function trialVec = localValidateTrialVector(trialVec, nTrials)
trialVec = unique(double(trialVec(:)'));
if isempty(trialVec) || any(~isfinite(trialVec)) || any(trialVec ~= round(trialVec))
    error('postEventLagErr:BadTrialNo', ...
        'Each trial selection must contain finite integer trial indices.');
end
trialVec = trialVec(trialVec >= 1 & trialVec <= nTrials);
if isempty(trialVec)
    error('postEventLagErr:BadTrialNo', ...
        'No requested trials were within the valid range 1:%d.', nTrials);
end
end


function opts = localApplyLegacySaccadeAliases(opts)
aliasPairs = {
    'saccadeVelThreshDegPerSec', 'speedThreshDegPerSec'
    'saccadeMinAmpDeg', 'minAmpDeg'
    'saccadeMinDurSec', 'minDurSec'
    'saccadeMaxDurSec', 'maxDurSec'
    'saccadeSmoothFrames', 'smoothFrames'
    };
for i = 1:size(aliasPairs, 1)
    oldField = aliasPairs{i, 1};
    newField = aliasPairs{i, 2};
    if (~isfield(opts, newField) || isempty(opts.(newField))) && isfield(opts, oldField) && ~isempty(opts.(oldField))
        opts.(newField) = opts.(oldField);
    end
end
end


function noiseLevel = localTrialBackgroundNoiseLevel(T)
noiseLevel = NaN;
if isfield(T, 'background_noise_lvl') && isscalar(T.background_noise_lvl) && isnumeric(T.background_noise_lvl)
    noiseLevel = double(T.background_noise_lvl);
end
end


function value = localTrialTargetVisibility(ex, T)
value = NaN;
if isfield(T, 'target_visibility') && isscalar(T.target_visibility) && isfinite(T.target_visibility)
    value = double(T.target_visibility);
elseif isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'graph') && ...
        isfield(ex.exp.CoPs.graph, 'target_visibility')
    v = ex.exp.CoPs.graph.target_visibility;
    if isscalar(v) && isfinite(v)
        value = double(v);
    end
end
end


function value = localTrialTargetNum(ex, T)
value = NaN;
if isfield(T, 'target_num') && isscalar(T.target_num) && isfinite(T.target_num)
    value = double(T.target_num);
elseif isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'ctl') && ...
        isfield(ex.exp.CoPs.ctl, 'target_num')
    v = ex.exp.CoPs.ctl.target_num;
    if isscalar(v) && isfinite(v)
        value = double(v);
    end
end
end


function imageName = localTrialImageName(ex, T, trialIdx)
imageName = string(missing);
if isfield(T, 'imageName') && (ischar(T.imageName) || isstring(T.imageName))
    candidate = string(T.imageName);
    if strlength(strtrim(candidate)) > 0
        imageName = candidate;
        return
    end
end
if isfield(T, 'stimPath') && (ischar(T.stimPath) || isstring(T.stimPath))
    candidate = localBasenameString(string(T.stimPath));
    if strlength(strtrim(candidate)) > 0
        imageName = candidate;
        return
    end
end
if isfield(ex, 'stim') && isstruct(ex.stim) && isfield(ex.stim, 'seq') && numel(ex.stim.seq) >= trialIdx
    candidate = localBasenameString(string(ex.stim.seq{trialIdx}));
    if strlength(strtrim(candidate)) > 0
        imageName = candidate;
    end
end
end


function out = localBasenameString(pathStr)
out = string(missing);
if strlength(strtrim(pathStr)) == 0 || ismissing(pathStr)
    return
end
[~, name, ext] = fileparts(char(pathStr));
candidate = string([name ext]);
if strlength(strtrim(candidate)) > 0
    out = candidate;
end
end


function tf = localIsAllCode(value)
tf = (ischar(value) && strcmpi(strtrim(value), 'all')) || ...
    (isstring(value) && isscalar(value) && strcmpi(strtrim(char(value)), 'all'));
end


function value = localFirstScalar(x)
if isempty(x)
    value = NaN;
elseif isscalar(x)
    value = double(x);
else
    value = double(x(1));
end
end


function dtSec = localResolveSampleDt(tRel, fallbackDtSec)
tRel = double(tRel(:));
tRel = tRel(isfinite(tRel));
if numel(tRel) < 2
    dtSec = fallbackDtSec;
    return
end
d = diff(tRel);
d = d(isfinite(d) & d > 0);
if isempty(d)
    dtSec = fallbackDtSec;
else
    dtSec = median(d, 'omitnan');
end
if ~isfinite(dtSec) || dtSec <= 0
    dtSec = fallbackDtSec;
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


function out = localTimeWindow(windowValue)
out = [];
if isempty(windowValue)
    return
end
out = double(windowValue(:)');
if numel(out) ~= 2 || ~all(isfinite(out)) || out(2) <= out(1)
    error('postEventLagErr:BadTimeWindow', ...
        'opts.timeWindowSec must be empty or a finite 1x2 increasing vector.');
end
end


function marginPx = localDefaultBetweenMarginPx(ex)
marginPx = NaN;
if isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'graph') && ...
        isfield(ex.exp.CoPs.graph, 'radius') && isfield(ex.exp.CoPs.graph, 'size_mult')
    marginPx = double(ex.exp.CoPs.graph.radius) * double(ex.exp.CoPs.graph.size_mult) / 2;
end
if ~isfinite(marginPx) || marginPx < 0
    marginPx = 0;
end
end


function trials = localFlattenTrialGroups(trialGroups)
if isempty(trialGroups)
    trials = [];
    return
end
trialGroups = cellfun(@(x) double(x(:)), trialGroups, 'UniformOutput', false);
trials = unique(vertcat(trialGroups{:}))';
end


function summary = localBuildGroupSummary(groupOut)
nGroup = numel(groupOut);
group = (1:nGroup)';
groupLabel = strings(nGroup, 1);
nEvents = zeros(nGroup, 1);
nRows = zeros(nGroup, 1);
errTraceRange = NaN(nGroup, 1);
plottedErrField = strings(nGroup, 1);
xErrTraceRange = NaN(nGroup, 1);
yErrTraceRange = NaN(nGroup, 1);
distDegMean = NaN(nGroup, 1);
distDegRange = NaN(nGroup, 1);
targetChangeFracMean = NaN(nGroup, 1);
targetShiftPxMean = NaN(nGroup, 1);
for g = 1:nGroup
    groupLabel(g) = string(groupOut{g}.groupLabel);
    nEvents(g) = groupOut{g}.nEvents;
    nRows(g) = groupOut{g}.nRows;
    errTraceRange(g) = groupOut{g}.errTraceRange;
    plottedErrField(g) = strjoin(string(groupOut{g}.plotFields), "/");
    xErrTraceRange(g) = groupOut{g}.errTraceXRange;
    yErrTraceRange(g) = groupOut{g}.errTraceYRange;
    distDegMean(g) = groupOut{g}.distDegMean;
    distDegRange(g) = groupOut{g}.distDegRange;
    if isfield(groupOut{g}, 'diagnostics') && ~isempty(groupOut{g}.diagnostics)
        d = groupOut{g}.diagnostics;
        targetChangeFracMean(g) = mean(d.targetChangeFrac, 'omitnan');
        targetShiftPxMean(g) = mean(d.meanTargetShiftPx, 'omitnan');
    end
end
summary = table(group, groupLabel, nEvents, nRows, errTraceRange, ...
    plottedErrField, xErrTraceRange, yErrTraceRange, distDegMean, distDegRange, ...
    targetChangeFracMean, targetShiftPxMean);
end


function localPlotComponentGroups(groupOut, opts, axisName, groupIdx, legendLabelsOverride, rowLabel)
traceField = localComponentTraceField(axisName, opts.componentUnits, opts.componentMetric);
axisLabel = upper(char(string(axisName)));
if strcmp(opts.componentMetric, 'signed')
    titleText = sprintf('%s signed post-event lag error', axisLabel);
else
    titleText = sprintf('%s absolute post-event lag error', axisLabel);
end
yLabelText = sprintf('%s (%s)', char(localErrFieldLabel(traceField)), char(string(opts.stat)));
localPlotGroups(groupOut, opts, groupIdx, legendLabelsOverride, rowLabel, traceField, yLabelText, titleText);
end


function localPlotGroups(groupOut, opts, groupIdx, legendLabelsOverride, rowLabel, traceField, yLabelText, titleText)
if nargin < 6 || isempty(traceField)
    traceField = 'errTrace';
end
if nargin < 7 || isempty(yLabelText)
    yLabelText = sprintf('%s (%s)', char(localErrFieldLabel(opts.errField)), char(string(opts.stat)));
end
if nargin < 8 || isempty(titleText)
    titleText = sprintf('%s-triggered post-event lag error', char(string(opts.eventType)));
end
ax = gca;
if logical(opts.newFigure)
    cla(ax, 'reset');
end
hold(ax, 'on')
grid(ax, 'on')
ax.Box = 'off';
legendLabels = strings(numel(groupIdx), 1);
plotted = false(numel(groupIdx), 1);
plotHandles = gobjects(numel(groupIdx), 1);
for j = 1:numel(groupIdx)
    g = groupIdx(j);
    errTrace = localGroupTrace(groupOut{g}, traceField);
    hasFiniteTrace = any(isfinite(errTrace));
    if hasFiniteTrace
        plotHandles(j) = plot(ax, groupOut{g}.tauSec, errTrace, ...
            'Color', opts.colors(g, :), 'LineWidth', opts.lineWidth);
    end
    if ~isempty(legendLabelsOverride) && numel(legendLabelsOverride) >= j
        legendLabels(j) = string(legendLabelsOverride{j});
    else
        legendLabels(j) = string(groupOut{g}.groupLabel);
    end
    legendLabels(j) = sprintf('%s (n=%d)', legendLabels(j), groupOut{g}.nEvents);
    plotted(j) = hasFiniteTrace;
end
xline(ax, 0, ':', 'Color', [0.4 0.4 0.4]);
yline(ax, 0, ':', 'Color', [0.4 0.4 0.4]);
xlabel('Target History Lag tau (s)', 'Interpreter', 'none');
ylabel(yLabelText, 'Interpreter', 'none');
if strlength(strtrim(string(rowLabel))) > 0
    titleText = sprintf('%s | %s', titleText, char(string(rowLabel)));
end
title(ax, titleText, 'Interpreter', 'none');
box(ax, 'off')
localSetPlotLimits(ax, groupOut, groupIdx, opts, traceField);
localLabelLineEnds(ax, groupOut, groupIdx, legendLabels, plotted, opts, traceField);
legendMaxGroups = double(localFirstScalar(opts.legendMaxGroups));
if ~isfinite(legendMaxGroups) || legendMaxGroups < 1
    legendMaxGroups = inf;
end
if logical(opts.showLegend) && numel(groupIdx) > 1 && nnz(plotted) <= legendMaxGroups && any(plotted)
    try
        legend(ax, plotHandles(plotted), cellstr(legendLabels(plotted)), ...
            'Location', 'best', 'Interpreter', 'none');
    catch
        warning('postEventLagErr:LegendFailed', ...
            'Could not draw legend; data lines and groupSummary are still valid.');
    end
elseif ~any(plotted)
    text(ax, 0.5, 0.5, 'No finite post-event lag-error rows', ...
        'Units', 'normalized', 'HorizontalAlignment', 'center', ...
        'Interpreter', 'none', 'Color', [0.4 0.4 0.4]);
end
end


function label = localErrFieldLabel(errField)
switch char(string(errField))
    case 'distDeg'
        label = "distance error (deg)";
    case 'distPx'
        label = "distance error (px)";
    case 'absXDeg'
        label = "absolute X displacement, |gaze - target| (deg)";
    case 'absXPx'
        label = "absolute X displacement, |gaze - target| (px)";
    case 'absYDeg'
        label = "absolute Y displacement, |gaze - target| (deg)";
    case 'absYPx'
        label = "absolute Y displacement, |gaze - target| (px)";
    case 'xDeg'
        label = "signed X error, gaze - target (deg)";
    case 'xPx'
        label = "signed X error, gaze - target (px)";
    case 'yDeg'
        label = "signed Y error, gaze - target (deg)";
    case 'yPx'
        label = "signed Y error, gaze - target (px)";
    otherwise
        label = string(errField);
end
end


function [xField, yField] = localComponentTraceFields(componentUnits, componentMetric)
if nargin < 2 || isempty(componentMetric)
    componentMetric = 'abs';
end
switch char(string(componentMetric))
    case 'signed'
        switch char(string(componentUnits))
            case 'px'
                xField = 'xPx';
                yField = 'yPx';
            otherwise
                xField = 'xDeg';
                yField = 'yDeg';
        end
    otherwise
        switch char(string(componentUnits))
            case 'px'
                xField = 'absXPx';
                yField = 'absYPx';
            otherwise
                xField = 'absXDeg';
                yField = 'absYDeg';
        end
end
end


function traceField = localComponentTraceField(axisName, componentUnits, componentMetric)
[xField, yField] = localComponentTraceFields(componentUnits, componentMetric);
switch lower(char(string(axisName)))
    case 'x'
        traceField = xField;
    case 'y'
        traceField = yField;
    otherwise
        error('postEventLagErr:BadAxis', 'axisName must be ''x'' or ''y''.');
end
end


function errTrace = localGroupTrace(groupOut, traceField)
traceField = char(string(traceField));
if strcmp(traceField, 'errTrace')
    errTrace = groupOut.errTrace;
elseif isfield(groupOut, 'traces') && isfield(groupOut.traces, traceField)
    errTrace = groupOut.traces.(traceField).value;
else
    errTrace = NaN(size(groupOut.tauSec));
end
errTrace = double(errTrace(:));
end


function localSetPlotLimits(ax, groupOut, groupIdx, opts, traceField)
tau = double(opts.tauSec(:));
tau = tau(isfinite(tau));
if ~isempty(tau)
    xMin = min(tau);
    xMax = max(tau);
    if logical(opts.labelLineEnds) && numel(groupIdx) > 1
        padRight = max(0.02, 0.12 * max(xMax - xMin, eps));
    else
        padRight = 0;
    end
    if xMax <= xMin
        pad = max(0.01, abs(xMin) * 0.05);
        xlim(ax, [xMin - pad, xMax + pad]);
    else
        xlim(ax, [xMin, xMax + padRight]);
    end
end

y = [];
for j = 1:numel(groupIdx)
    g = groupIdx(j);
    y = [y; localGroupTrace(groupOut{g}, traceField)]; %#ok<AGROW>
end
y = y(isfinite(y));
if isempty(y)
    return
end
y = [y; 0];
yMin = min(y);
yMax = max(y);
if yMax <= yMin
    pad = max(1, abs(yMin) * 0.05);
else
    pad = 0.08 * (yMax - yMin);
    if pad <= 0 || ~isfinite(pad)
        pad = max(1, max(abs([yMin yMax])) * 0.05);
    end
end
ylim(ax, [yMin - pad, yMax + pad]);
end


function localLabelLineEnds(ax, groupOut, groupIdx, legendLabels, plotted, opts, traceField)
if ~logical(opts.labelLineEnds) || nnz(plotted) < 2
    return
end
legendMaxGroups = double(localFirstScalar(opts.legendMaxGroups));
if ~isfinite(legendMaxGroups) || legendMaxGroups < 1
    legendMaxGroups = inf;
end
if nnz(plotted) > legendMaxGroups
    return
end
for j = 1:numel(groupIdx)
    if ~plotted(j)
        continue
    end
    g = groupIdx(j);
    tau = double(groupOut{g}.tauSec(:));
    errTrace = localGroupTrace(groupOut{g}, traceField);
    keep = isfinite(tau) & isfinite(errTrace);
    if ~any(keep)
        continue
    end
    idx = find(keep, 1, 'last');
    text(ax, tau(idx), errTrace(idx), "  " + string(legendLabels(j)), ...
        'Color', opts.colors(g, :), 'Interpreter', 'none', ...
        'VerticalAlignment', 'middle', 'Clipping', 'on');
end
end


function plotFacetSpec = localResolvePlotFacetSpec(trialNo, ex, nGroup)
plotFacetSpec = struct('enabled', false, 'nRows', 1, 'nLineGroups', nGroup, ...
    'rowGroupIdx', {{}}, 'rowLabels', strings(0, 1), ...
    'lineLabels', {{}}, 'lineGroupIndex', (1:nGroup)');
if ~localIsNamedCodeCell(trialNo) || numel(trialNo) ~= 2
    return
end
code1 = char(string(trialNo{1}));
code2 = char(string(trialNo{2}));
labels1 = localGroupingLevelLabels(code1, ex);
labels2 = localGroupingLevelLabels(code2, ex);
count1 = numel(labels1);
count2 = numel(labels2);
if ~(count1 >= 1 && count2 >= 1 && count1 * count2 == nGroup)
    return
end
plotFacetSpec.enabled = true;
plotFacetSpec.nRows = count1;
plotFacetSpec.nLineGroups = count2;
plotFacetSpec.rowGroupIdx = cell(count1, 1);
plotFacetSpec.rowLabels = labels1(:);
plotFacetSpec.lineLabels = cellstr(labels2(:));
plotFacetSpec.lineGroupIndex = repmat((1:count2)', count1, 1);
for i = 1:count1
    plotFacetSpec.rowGroupIdx{i} = ((i - 1) * count2 + 1):(i * count2);
end
end


function labels = localGroupingLevelLabels(code, ex)
code = lower(strtrim(char(string(code))));
switch code
    case 'all'
        labels = "all";
    case {'bg', 'vis', 'tnum', 'im'}
        groups = localResolveNamedTrialGroups(code, ex);
        labels = strings(numel(groups), 1);
        for i = 1:numel(groups)
            labels(i) = localSingleGroupLabel(code, groups{i}(1), ex);
        end
    otherwise
        labels = strings(0, 1);
end
end


function label = localSingleGroupLabel(code, trialIdx, ex)
T = ex.Trials(trialIdx);
switch code
    case 'bg'
        label = "bg: " + string(localTrialBackgroundNoiseLevel(T));
    case 'vis'
        label = "vis: " + string(localTrialTargetVisibility(ex, T));
    case 'tnum'
        label = "tnum: " + string(localTrialTargetNum(ex, T));
    case 'im'
        label = "im: " + localTrialImageName(ex, T, trialIdx);
    otherwise
        label = "all";
end
prefix = code + ": ";
if startsWith(char(label), prefix)
    label = strip(extractAfter(string(label), strlength(prefix)));
end
end
