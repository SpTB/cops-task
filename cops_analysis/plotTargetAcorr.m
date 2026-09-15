function out = plotTargetAcorr(ex, trialNo, axisName, opts)
% plotTargetAcorr  Plot stepwise target autocorrelation for one or more trials.
%
%   plotTargetAcorr(ex)
%   plotTargetAcorr(ex, [])
%   plotTargetAcorr(ex, 'all')
%   plotTargetAcorr(ex, 10)
%   plotTargetAcorr(ex, 10, 'x')
%   plotTargetAcorr(ex, 1:50, 'all')
%
% Inputs
%   ex       : experiment struct containing ex.Trials
%   trialNo  : []/'all' for all trials, or scalar/vector of trial indices
%   axisName : 'x', 'y', or 'all' (default)
%   opts     : optional struct with fields:
%       .onlyGoState            (default true)
%       .useEyeTime             (default false)
%       .source                 (default 'sampled') 'sampled' or
%                               'targetPositions'
%       .targetPositionsStepSelection (default 'matched') for
%                               source='targetPositions': 'matched' uses
%                               the same sampled/GO step set; 'all' uses
%                               every saved targetPositions step
%       .truncateTrialFromStep  (default 0)
%       .signalMode             (default 'position') 'position' or 'velocity'
%       .validTrackingChunksOnly (default false) use the same finite
%                               target/gaze chunks selected by ccg()
%       .boundaryOnly           (default false) keep only target positions
%                               near the texture boundary
%       .boundaryMarginPx       (default []) boundary-zone width in pixels;
%                               defaults to target radius * size_mult
%       .boundaryMarginDeg      (default []) boundary-zone width in visual
%                               degrees; overrides boundaryMarginPx
%       .newFigure              (default true)
%       .lineWidth              (default 1.25)
%
% Output
%   out.lagSec   : lag axis in seconds
%   out.trials   : included trial ids
%   out.acorrX   : per-trial x autocorrelation matrix
%   out.acorrY   : per-trial y autocorrelation matrix
%   out.meanX    : mean x autocorrelation
%   out.meanY    : mean y autocorrelation

if nargin < 2
    trialNo = [];
end
if nargin < 4 || isempty(opts)
    opts = struct();
end
if nargin < 3 || isempty(axisName)
    axisName = 'all';
elseif isstruct(axisName)
    opts = axisName;
    axisName = 'all';
end

axisName = validatestring(char(axisName), {'x', 'y', 'all'});

defaults = struct( ...
    'onlyGoState', true, ...
    'useEyeTime', true, ...
    'source', 'sampled', ...
    'targetPositionsStepSelection', 'matched', ...
    'truncateTrialFromStep', 0, ...
    'signalMode', 'velocity', ...'position'
    'validTrackingChunksOnly', false, ...
    'boundaryOnly', false, ...
    'boundaryMarginPx', [], ...
    'boundaryMarginDeg', [], ...
    'newFigure', true, ...
    'lineWidth', 1.25);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field)
        opts.(field) = defaults.(field);
    end
end
opts.signalMode = validatestring(char(opts.signalMode), {'position', 'velocity'});
opts.source = validatestring(char(opts.source), {'sampled', 'targetPositions', 'positions'});
if strcmp(opts.source, 'positions')
    opts.source = 'targetPositions';
end
opts.targetPositionsStepSelection = validatestring(char(opts.targetPositionsStepSelection), {'matched', 'all'});

if ~isstruct(ex) || ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('plotTargetAcorr:BadInput', 'First input must be an ex struct with Trials.');
end

trialNo = localResolveTrialNo(trialNo, numel(ex.Trials));

dtStepDefault = localResolveDefaultStepDt(ex);
lagSecRows = cell(numel(trialNo), 1);
acorrXRows = cell(numel(trialNo), 1);
acorrYRows = cell(numel(trialNo), 1);
keepTrial = false(numel(trialNo), 1);
nStepsRows = NaN(numel(trialNo), 1);
firstStepRows = NaN(numel(trialNo), 1);
lastStepRows = NaN(numel(trialNo), 1);
nBoundaryStepsRows = NaN(numel(trialNo), 1);
nSignalSamplesRows = NaN(numel(trialNo), 1);

for i = 1:numel(trialNo)
    if logical(opts.validTrackingChunksOnly)
        [tx, ty, dtStep, usedSteps] = localGetTrialTargetStepsFromCcgChunks(ex, trialNo(i), opts);
    else
        [tx, ty, dtStep, usedSteps] = localGetTrialTargetSteps(ex, trialNo(i), opts);
    end
    if isempty(tx) || isempty(ty)
        continue
    end
    if ~isfinite(dtStep) || dtStep <= 0
        dtStep = dtStepDefault;
    end
    if isfinite(dtStepDefault) && dtStepDefault > 0
        dtStep = dtStepDefault;
    end
    boundaryMask = localTargetBoundaryMask(ex, tx, ty, opts);
    [sx, sy] = localTargetSignal(tx, ty, dtStep, opts.signalMode, boundaryMask, opts.boundaryOnly);
    nBoundaryStepsRows(i) = sum(boundaryMask & isfinite(tx(:)) & isfinite(ty(:)));
    nSignalSamplesRows(i) = sum(isfinite(sx(:)) & isfinite(sy(:)));
    [acx, lagSecHere] = localAutocorr1d(sx, dtStep);
    [acy, ~] = localAutocorr1d(sy, dtStep);
    if isempty(acx) || isempty(acy)
        continue
    end
    lagSecRows{i} = lagSecHere(:)';
    acorrXRows{i} = acx(:)';
    acorrYRows{i} = acy(:)';
    keepTrial(i) = true;
    nStepsRows(i) = numel(usedSteps);
    if ~isempty(usedSteps)
        firstStepRows(i) = usedSteps(1);
        lastStepRows(i) = usedSteps(end);
    end
end

trialKeep = trialNo(keepTrial);
[lagSec, acorrX, acorrY] = localAlignAcorrRows(lagSecRows, acorrXRows, acorrYRows, keepTrial, dtStepDefault);

meanX = mean(acorrX, 1, 'omitnan');
meanY = mean(acorrY, 1, 'omitnan');
nTrialsPerLagX = sum(isfinite(acorrX), 1);
nTrialsPerLagY = sum(isfinite(acorrY), 1);

if opts.newFigure
    figure;
end

switch axisName
    case 'x'
        localPlotAcorr(lagSec, meanX, sprintf('Target X %s autocorrelation', opts.signalMode), opts.lineWidth);
    case 'y'
        localPlotAcorr(lagSec, meanY, sprintf('Target Y %s autocorrelation', opts.signalMode), opts.lineWidth);
    case 'all'
        tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
        nexttile;
        localPlotAcorr(lagSec, meanX, sprintf('Target X %s autocorrelation', opts.signalMode), opts.lineWidth);
        nexttile;
        localPlotAcorr(lagSec, meanY, sprintf('Target Y %s autocorrelation', opts.signalMode), opts.lineWidth);
        sgtitle(sprintf('Target %s autocorrelation (%d trial%s)', opts.signalMode, ...
            numel(trialKeep), localPlural(numel(trialKeep))), 'Interpreter', 'none');
end

out = struct();
out.lagSec = lagSec(:);
out.trials = trialKeep(:);
out.acorrX = acorrX;
out.acorrY = acorrY;
out.meanX = meanX;
out.meanY = meanY;
out.nTrialsPerLagX = nTrialsPerLagX(:);
out.nTrialsPerLagY = nTrialsPerLagY(:);
out.signalMode = opts.signalMode;
out.source = opts.source;
out.targetPositionsStepSelection = opts.targetPositionsStepSelection;
out.validTrackingChunksOnly = logical(opts.validTrackingChunksOnly);
out.boundaryOnly = logical(opts.boundaryOnly);
out.boundaryMarginPx = localResolveBoundaryMarginPx(ex, opts);
out.nStepsPerTrial = nStepsRows(keepTrial);
out.nBoundaryStepsPerTrial = nBoundaryStepsRows(keepTrial);
out.nSignalSamplesPerTrial = nSignalSamplesRows(keepTrial);
out.firstStep = firstStepRows(keepTrial);
out.lastStep = lastStepRows(keepTrial);
end


function [lagSec, acorrX, acorrY] = localAlignAcorrRows(lagSecRows, acorrXRows, acorrYRows, keepTrial, dtStepDefault)
rowIdx = find(keepTrial(:));
if isempty(rowIdx)
    lagSec = NaN(0, 1);
    acorrX = NaN(0, 0);
    acorrY = NaN(0, 0);
    return
end

allLag = [];
for i = rowIdx(:)'
    allLag = [allLag; lagSecRows{i}(:)]; %#ok<AGROW>
end
allLag = allLag(isfinite(allLag));
if isempty(allLag)
    lagSec = NaN(0, 1);
    acorrX = NaN(numel(rowIdx), 0);
    acorrY = NaN(numel(rowIdx), 0);
    return
end

if isfinite(dtStepDefault) && dtStepDefault > 0
    lagKeys = unique(round(allLag ./ dtStepDefault));
    lagSec = lagKeys(:) .* dtStepDefault;
else
    lagSec = unique(localRoundToTol(allLag(:), 1e-9));
    lagKeys = lagSec;
end

acorrX = NaN(numel(rowIdx), numel(lagSec));
acorrY = NaN(numel(rowIdx), numel(lagSec));
for r = 1:numel(rowIdx)
    i = rowIdx(r);
    thisLag = lagSecRows{i}(:)';
    if isfinite(dtStepDefault) && dtStepDefault > 0
        thisKeys = round(thisLag ./ dtStepDefault);
    else
        thisKeys = localRoundToTol(thisLag, 1e-9);
    end
    [tf, loc] = ismember(thisKeys, lagKeys);
    xRow = acorrXRows{i};
    yRow = acorrYRows{i};
    acorrX(r, loc(tf)) = xRow(tf);
    acorrY(r, loc(tf)) = yRow(tf);
end
end


function trialNo = localResolveTrialNo(trialNo, nTrials)
if isempty(trialNo) || localIsAllCode(trialNo)
    trialNo = 1:nTrials;
    return
end

if ~isnumeric(trialNo)
    error('plotTargetAcorr:BadTrialNo', ...
        'trialNo must be numeric, [], or ''all''.');
end

trialNo = unique(double(trialNo(:)'));
if isempty(trialNo) || any(~isfinite(trialNo)) || any(trialNo ~= round(trialNo))
    error('plotTargetAcorr:BadTrialNo', ...
        'trialNo must contain finite integer trial indices.');
end

trialNo = trialNo(trialNo >= 1 & trialNo <= nTrials);
if isempty(trialNo)
    error('plotTargetAcorr:BadTrialNo', ...
        'No requested trials were within the valid range.');
end
end


function tf = localIsAllCode(value)
tf = (ischar(value) && strcmpi(strtrim(value), 'all')) || ...
    (isstring(value) && isscalar(value) && strcmpi(strtrim(char(value)), 'all'));
end


function y = localRoundToTol(x, tol)
y = round(double(x) ./ tol) .* tol;
end


function [tx, ty, dtStep, usedSteps] = localGetTrialTargetSteps(ex, trialNo, opts)
T = ex.Trials(trialNo);
if strcmp(opts.source, 'targetPositions')
    [tx, ty, usedSteps] = localGetDirectTargetPositions(ex, T, opts);
    dtStep = localResolveTrialStepDt(ex, T);
    return
end

[~, ~, tRel, tAbs, ~] = reconstructEyePx(ex, T, opts.useEyeTime, opts);
[targetX, targetY, ~, ~, stepIdx] = mapTargetsByStep(ex, T, tRel);

goMask = true(size(tRel));
if opts.onlyGoState && isfield(T, 'times') && isfield(T.times, 'stimOn') && isfield(T, 'TrialEnd')
    goMask = tAbs >= T.times.stimOn & tAbs <= T.TrialEnd;
end

targetX = targetX(goMask);
targetY = targetY(goMask);
stepIdx = stepIdx(goMask);
tRel = tRel(goMask);

truncateFromStep = double(localFirstScalar(opts.truncateTrialFromStep));
if isfinite(truncateFromStep) && truncateFromStep > 0
    keepMask = isfinite(stepIdx) & stepIdx >= truncateFromStep;
    targetX = targetX(keepMask);
    targetY = targetY(keepMask);
    stepIdx = stepIdx(keepMask);
    tRel = tRel(keepMask);
end

valid = isfinite(stepIdx) & isfinite(targetX) & isfinite(targetY);
if ~any(valid)
    tx = [];
    ty = [];
    dtStep = NaN;
    usedSteps = [];
    return
end

TT = table(stepIdx(valid), tRel(valid), targetX(valid), targetY(valid), ...
    'VariableNames', {'step','tRelSec','targetX','targetY'});
[stepGroups, ~] = findgroups(TT.step);
tx = splitapply(@(x) mean(x, 'omitnan'), TT.targetX, stepGroups);
ty = splitapply(@(x) mean(x, 'omitnan'), TT.targetY, stepGroups);
tStep = splitapply(@mean, TT.tRelSec, stepGroups);
usedSteps = splitapply(@(x) x(1), TT.step, stepGroups);

dtStep = NaN;
if numel(tStep) >= 2
    d = diff(tStep);
    d = d(isfinite(d) & d > 0);
    if ~isempty(d)
        dtStep = median(d, 'omitnan');
    end
end
end


function [tx, ty, dtStep, usedSteps] = localGetTrialTargetStepsFromCcgChunks(ex, trialNo, opts)
tx = [];
ty = [];
usedSteps = [];
dtStep = NaN;

ccgOpts = opts;
ccgOpts.plot = false;
ccgOpts.newFigure = false;
if isfield(opts, 'source') && ~isempty(opts.source)
    source = validatestring(char(opts.source), {'sampled', 'targetPositions', 'positions'});
    if strcmp(source, 'positions')
        source = 'targetPositions';
    end
    ccgOpts.targetSource = source;
end

try
    C = ccg(ex, trialNo, ccgOpts);
catch ME
    error('plotTargetAcorr:CcgChunkSelectionFailed', ...
        'Could not obtain valid tracking chunks from ccg(): %s', ME.message);
end
if ~isfield(C, 'episodes') || isempty(C.episodes)
    return
end

E = C.episodes;
if isempty(E) || ~ismember('targetX', E.Properties.VariableNames) || ~ismember('targetY', E.Properties.VariableNames)
    return
end
if ismember('trial', E.Properties.VariableNames)
    E = E(double(E.trial(:)) == double(trialNo), :);
end
if isempty(E)
    return
end

if ismember('dtStepSec', E.Properties.VariableNames)
    dtCandidates = double(E.dtStepSec(:));
    dtCandidates = dtCandidates(isfinite(dtCandidates) & dtCandidates > 0);
    if ~isempty(dtCandidates)
        dtStep = median(dtCandidates, 'omitnan');
    end
end
if ~isfinite(dtStep) || dtStep <= 0
    dtStep = localResolveDefaultStepDt(ex);
end

for i = 1:height(E)
    thisTx = double(E.targetX{i}(:));
    thisTy = double(E.targetY{i}(:));
    n = min(numel(thisTx), numel(thisTy));
    if n < 1
        continue
    end
    thisTx = thisTx(1:n);
    thisTy = thisTy(1:n);
    if ~any(isfinite(thisTx) & isfinite(thisTy))
        continue
    end
    if ~isempty(tx)
        tx(end+1, 1) = NaN; %#ok<AGROW>
        ty(end+1, 1) = NaN; %#ok<AGROW>
        usedSteps(end+1, 1) = NaN; %#ok<AGROW>
    end
    tx = [tx; thisTx(:)]; %#ok<AGROW>
    ty = [ty; thisTy(:)]; %#ok<AGROW>
    if ismember('step', E.Properties.VariableNames)
        thisSteps = double(E.step{i}(:));
        if numel(thisSteps) >= n
            usedSteps = [usedSteps; thisSteps(1:n)]; %#ok<AGROW>
        else
            usedSteps = [usedSteps; NaN(n, 1)]; %#ok<AGROW>
        end
    else
        usedSteps = [usedSteps; NaN(n, 1)]; %#ok<AGROW>
    end
end

finiteStep = isfinite(usedSteps);
usedSteps = usedSteps(finiteStep);
end


function [tx, ty, stepIdx] = localGetDirectTargetPositions(ex, T, opts)
tx = [];
ty = [];
stepIdx = [];
if ~isfield(T, 'targetPositions') || isempty(T.targetPositions)
    return
end

nsteps = getfieldOrNaN(T, 'nsteps');
if ~isfinite(nsteps) || nsteps < 1
    nsteps = numel(T.targetPositions);
end
nsteps = min(nsteps, numel(T.targetPositions));
stepIdx = localDirectTargetStepSet(ex, T, opts, nsteps);

truncateFromStep = double(localFirstScalar(opts.truncateTrialFromStep));
if isfinite(truncateFromStep) && truncateFromStep > 0
    stepIdx = stepIdx(stepIdx >= truncateFromStep);
end
if isempty(stepIdx)
    return
end

tx = NaN(numel(stepIdx), 1);
ty = NaN(numel(stepIdx), 1);
for i = 1:numel(stepIdx)
    tp = T.targetPositions(stepIdx(i));
    if isfield(tp, 'targ1') && isfield(tp.targ1, 'pos_abs') && numel(tp.targ1.pos_abs) >= 2
        tx(i) = tp.targ1.pos_abs(1);
        ty(i) = tp.targ1.pos_abs(2);
    end
end

valid = isfinite(tx) & isfinite(ty);
tx = tx(valid);
ty = ty(valid);
stepIdx = stepIdx(valid);
end


function stepIdx = localDirectTargetStepSet(ex, T, opts, nsteps)
stepIdx = (1:nsteps)';
if ~strcmp(opts.targetPositionsStepSelection, 'matched')
    return
end

try
    [~, ~, tRel, tAbs, ~] = reconstructEyePx(ex, T, opts.useEyeTime, opts);
    if isempty(tRel)
        return
    end
    [~, ~, ~, ~, sampleStepIdx] = mapTargetsByStep(ex, T, tRel);
    goMask = true(size(tRel));
    if opts.onlyGoState && isfield(T, 'times') && isfield(T.times, 'stimOn') && isfield(T, 'TrialEnd')
        goMask = tAbs >= T.times.stimOn & tAbs <= T.TrialEnd;
    end
    sampleStepIdx = sampleStepIdx(goMask & isfinite(sampleStepIdx));
    sampleStepIdx = unique(sampleStepIdx(:), 'stable');
    sampleStepIdx = sampleStepIdx(sampleStepIdx >= 1 & sampleStepIdx <= nsteps);
    if ~isempty(sampleStepIdx)
        stepIdx = sampleStepIdx(:);
    end
catch
    stepIdx = (1:nsteps)';
end
end


function dtStep = localResolveTrialStepDt(ex, T)
dtStep = NaN;
if isstruct(T)
    if isfield(T, 'waitSecs') && ~isempty(T.waitSecs)
        dtStep = localFirstPositiveScalar(T.waitSecs);
    elseif isfield(T, 'waitHz') && ~isempty(T.waitHz)
        waitHz = localFirstPositiveScalar(T.waitHz);
        if isfinite(waitHz)
            dtStep = 1 / waitHz;
        end
    end
end
if ~isfinite(dtStep) || dtStep <= 0
    dtStep = localResolveDefaultStepDt(ex);
end
end


function [sx, sy] = localTargetSignal(tx, ty, dtStep, signalMode, boundaryMask, boundaryOnly)
if nargin < 5 || isempty(boundaryMask)
    boundaryMask = true(size(tx));
end
if nargin < 6
    boundaryOnly = false;
end
boundaryMask = logical(boundaryMask(:));
switch signalMode
    case 'position'
        sx = tx;
        sy = ty;
        if logical(boundaryOnly)
            keep = boundaryMask & isfinite(sx(:)) & isfinite(sy(:));
            sx(~keep) = NaN;
            sy(~keep) = NaN;
        end
    case 'velocity'
        if ~isfinite(dtStep) || dtStep <= 0
            sx = [];
            sy = [];
            return
        end
        sx = diff(double(tx(:))) ./ dtStep;
        sy = diff(double(ty(:))) ./ dtStep;
        if logical(boundaryOnly)
            keep = boundaryMask(1:end-1) | boundaryMask(2:end);
            sx(~keep) = NaN;
            sy(~keep) = NaN;
        end
end
end


function boundaryMask = localTargetBoundaryMask(ex, tx, ty, opts)
tx = double(tx(:));
ty = double(ty(:));
boundaryMask = true(size(tx));
if ~isfield(opts, 'boundaryOnly') || ~logical(opts.boundaryOnly)
    return
end
if numel(ty) ~= numel(tx)
    boundaryMask = false(size(tx));
    return
end
bounds = localTargetBounds(ex);
marginPx = localResolveBoundaryMarginPx(ex, opts);
valid = isfinite(tx) & isfinite(ty);
boundaryMask = false(size(tx));
boundaryMask(valid) = tx(valid) <= bounds.xMin + marginPx | ...
    tx(valid) >= bounds.xMax - marginPx | ...
    ty(valid) <= bounds.yMin + marginPx | ...
    ty(valid) >= bounds.yMax - marginPx;
end


function bounds = localTargetBounds(ex)
if isfield(ex, 'setup') && isfield(ex.setup, 'screenRect') && ...
        isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && ...
        isfield(ex.exp.CoPs, 'graph') && isfield(ex.exp.CoPs.graph, 'texture_dims') && ...
        isfield(ex.exp.CoPs.graph, 'size_mult')
    texDimPx = ex.exp.CoPs.graph.texture_dims(1) .* ex.exp.CoPs.graph.size_mult;
    xShift = (ex.setup.screenRect(3) - texDimPx) ./ 2;
    yShift = (ex.setup.screenRect(4) - texDimPx) ./ 2;
    bounds = struct( ...
        'xMin', xShift, ...
        'xMax', xShift + texDimPx, ...
        'yMin', yShift, ...
        'yMax', yShift + texDimPx);
    return
end
if isfield(ex, 'setup') && isfield(ex.setup, 'screenRect') && numel(ex.setup.screenRect) >= 4
    r = double(ex.setup.screenRect);
    bounds = struct('xMin', r(1), 'xMax', r(3), 'yMin', r(2), 'yMax', r(4));
    return
end
error('plotTargetAcorr:MissingBoundaryGeometry', ...
    'Boundary filtering requires ex.setup.screenRect and preferably ex.exp.CoPs.graph texture geometry.');
end


function marginPx = localResolveBoundaryMarginPx(ex, opts)
marginPx = NaN;
if isfield(opts, 'boundaryMarginDeg') && ~isempty(opts.boundaryMarginDeg)
    marginDeg = double(localFirstScalar(opts.boundaryMarginDeg));
    if isfinite(marginDeg) && isfield(ex, 'setup') && ~isempty(ex.setup)
        dpp = px2deg(1, ex.setup);
        if isfinite(dpp) && dpp > 0
            marginPx = marginDeg ./ dpp;
        end
    end
end
if ~isfinite(marginPx) && isfield(opts, 'boundaryMarginPx') && ~isempty(opts.boundaryMarginPx)
    marginPx = double(localFirstScalar(opts.boundaryMarginPx));
end
if ~isfinite(marginPx)
    marginPx = 0;
    if isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'graph')
        graph = ex.exp.CoPs.graph;
        radiusPx = 0;
        if isfield(graph, 'radius')
            radiusPx = double(localFirstScalar(graph.radius));
        end
        sizeMult = 1;
        if isfield(graph, 'size_mult')
            sizeMult = double(localFirstScalar(graph.size_mult));
        end
        marginPx = radiusPx .* sizeMult;
    end
end
marginPx = max(0, double(marginPx));
end


function [ac, lagSec] = localAutocorr1d(x, dtStep)
x = double(x(:));
ac = [];
lagSec = [];
if numel(x) < 2
    return
end

idx = find(isfinite(x));
if numel(idx) < 2
    return
end

runBreak = [true; diff(idx) > 1];
runStarts = find(runBreak);
runEnds = [runStarts(2:end) - 1; numel(idx)];
runLens = runEnds - runStarts + 1;
maxLag = max(runLens) - 1;
if maxLag < 1
    return
end

lags = (-maxLag:maxLag)';
accum = zeros(numel(lags), 1);
weight = zeros(numel(lags), 1);
for i = 1:numel(runStarts)
    ii = idx(runStarts(i):runEnds(i));
    if numel(ii) < 2
        continue
    end
    xi = x(ii);
    xi = xi - mean(xi, 'omitnan');
    if ~any(abs(xi) > 0)
        continue
    end
    [aci, lagi] = xcorr(xi, 'coeff');
    finite = isfinite(aci);
    if ~any(finite)
        continue
    end
    loc = lagi(:) + maxLag + 1;
    loc = loc(finite);
    w = numel(xi);
    accum(loc) = accum(loc) + w .* aci(finite);
    weight(loc) = weight(loc) + w;
end

valid = weight > 0;
if ~any(valid)
    return
end
ac = NaN(size(lags));
ac(valid) = accum(valid) ./ weight(valid);
lagSec = lags(:) .* dtStep;
end


function dt = localResolveDefaultStepDt(ex)
[dt, ~] = resolveCoPsWaitSecs(ex, NaN);
end


function localPlotAcorr(lagSec, ac, titleText, lineWidth)
plot(lagSec, ac, 'k', 'LineWidth', lineWidth);
hold on
xline(0, ':');
xlabel('Lag (s)');
ylabel('Autocorr');
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


function value = localFirstPositiveScalar(x)
value = NaN;
if isempty(x) || ~isnumeric(x)
    return
end
x = double(x(:));
x = x(isfinite(x) & x > 0);
if ~isempty(x)
    value = x(1);
end
end


function suffix = localPlural(n)
if n == 1
    suffix = '';
else
    suffix = 's';
end
end
