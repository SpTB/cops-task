function out = plotGazeAcorr(ex, trialNo, axisName, opts)
% plotGazeAcorr  Plot stepwise gaze autocorrelation using ccg-style processing.
%
%   plotGazeAcorr(ex)
%   plotGazeAcorr(ex, [])
%   plotGazeAcorr(ex, 'all')
%   plotGazeAcorr(ex, 10)
%   plotGazeAcorr(ex, 10, 'x')
%   plotGazeAcorr(ex, 1:50, 'all')
%
% Inputs
%   ex       : experiment struct containing ex.Trials
%   trialNo  : []/'all' for all trials, or scalar/vector of trial indices
%   axisName : 'x', 'y', or 'all' (default)
%   opts     : optional struct. All ccg() gaze-processing options are
%              accepted and passed through, including useEyeTime,
%              eyeTimeAlignmentMode, lowpassHz, interpBlinkSec,
%              removeSaccadesForCcg, truncateTrialFromStep, timeWindowSec,
%              fromState, stepClockOffsetSec, and stepGazeSummary.
%       .signalMode     (default 'velocity') 'velocity' or 'position'
%       .acorrWindowSec (default []) optional 1x2 lag window in seconds
%       .newFigure      (default true)
%       .lineWidth      (default 1.25)
%
% Output
%   out.lagSec   : lag axis in seconds
%   out.trials   : included trial ids
%   out.acorrX   : per-trial x autocorrelation matrix
%   out.acorrY   : per-trial y autocorrelation matrix
%   out.meanX    : mean x autocorrelation
%   out.meanY    : mean y autocorrelation
%   out.episodes : ccg() episodes used as the processed gaze source

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
    'signalMode', 'velocity', ...
    'acorrWindowSec', [], ...
    'newFigure', true, ...
    'lineWidth', 1.25);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field)
        opts.(field) = defaults.(field);
    end
end
opts.signalMode = validatestring(char(string(opts.signalMode)), {'position', 'velocity'});

if ~isstruct(ex) || ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('plotGazeAcorr:BadInput', 'First input must be an ex struct with Trials.');
end

trialNo = localResolveTrialNo(trialNo, numel(ex.Trials));

ccgOpts = opts;
ccgOpts.plot = false;
ccgOpts.newFigure = false;
if isfield(ccgOpts, 'source') && ~isfield(ccgOpts, 'targetSource')
    ccgOpts.targetSource = ccgOpts.source;
end

C = ccg(ex, trialNo, ccgOpts);
if ~isfield(C, 'episodes') || isempty(C.episodes)
    [out, lagSec, meanX, meanY] = localEmptyOutput(trialNo, opts); %#ok<ASGLU>
    localMaybePlotEmpty(axisName, opts);
    return
end

E = C.episodes;
if isempty(E) || ~all(ismember({'trial','gazeX','gazeY','dtStepSec'}, E.Properties.VariableNames))
    [out, lagSec, meanX, meanY] = localEmptyOutput(trialNo, opts); %#ok<ASGLU>
    localMaybePlotEmpty(axisName, opts);
    return
end

trialKeep = localEpisodeTrialOrder(E, trialNo);
commonDtStepSec = localCommonDtStepSec(E.dtStepSec);
globalMeans = localGlobalGazeMeans(E, commonDtStepSec, opts.signalMode);

lagSecRows = cell(numel(trialKeep), 1);
acorrXRows = cell(numel(trialKeep), 1);
acorrYRows = cell(numel(trialKeep), 1);
keepTrial = false(numel(trialKeep), 1);
nChunksRows = NaN(numel(trialKeep), 1);
nSignalSamplesRows = NaN(numel(trialKeep), 1);

for i = 1:numel(trialKeep)
    Ei = E(double(E.trial(:)) == double(trialKeep(i)), :);
    if isempty(Ei)
        continue
    end
    nChunksRows(i) = height(Ei);
    trialMeans = localTrialGazeMeans(Ei, commonDtStepSec, opts.signalMode);
    [sx, sy] = localGazeSignalsFromEpisodes(Ei, commonDtStepSec, opts.signalMode);
    nSignalSamplesRows(i) = sum(isfinite(sx(:)) | isfinite(sy(:)));

    meanX = localResolveDemeanMean(opts, trialMeans.x, globalMeans.x);
    meanY = localResolveDemeanMean(opts, trialMeans.y, globalMeans.y);
    [acx, lagSecHere] = localAutocorr1d(sx, commonDtStepSec, opts, meanX);
    [acy, ~] = localAutocorr1d(sy, commonDtStepSec, opts, meanY);
    if isempty(acx) || isempty(acy)
        continue
    end
    lagSecRows{i} = lagSecHere(:)';
    acorrXRows{i} = acx(:)';
    acorrYRows{i} = acy(:)';
    keepTrial(i) = true;
end

trialKeep = trialKeep(keepTrial);
[lagSec, acorrX, acorrY] = localAlignAcorrRows(lagSecRows, acorrXRows, acorrYRows, keepTrial, commonDtStepSec);
lagWindow = localLagWindow(opts.acorrWindowSec);
if ~isempty(lagWindow) && ~isempty(lagSec)
    keepLag = lagSec >= lagWindow(1) & lagSec <= lagWindow(2);
    lagSec = lagSec(keepLag);
    acorrX = acorrX(:, keepLag);
    acorrY = acorrY(:, keepLag);
end

meanX = mean(acorrX, 1, 'omitnan');
meanY = mean(acorrY, 1, 'omitnan');
nTrialsPerLagX = sum(isfinite(acorrX), 1);
nTrialsPerLagY = sum(isfinite(acorrY), 1);

if opts.newFigure
    figure;
end

switch axisName
    case 'x'
        localPlotAcorr(lagSec, meanX, sprintf('Gaze X %s autocorrelation', opts.signalMode), opts.lineWidth);
    case 'y'
        localPlotAcorr(lagSec, meanY, sprintf('Gaze Y %s autocorrelation', opts.signalMode), opts.lineWidth);
    case 'all'
        tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
        nexttile;
        localPlotAcorr(lagSec, meanX, sprintf('Gaze X %s autocorrelation', opts.signalMode), opts.lineWidth);
        nexttile;
        localPlotAcorr(lagSec, meanY, sprintf('Gaze Y %s autocorrelation', opts.signalMode), opts.lineWidth);
        sgtitle(sprintf('Gaze %s autocorrelation (%d trial%s)', opts.signalMode, ...
            numel(trialKeep), localPlural(numel(trialKeep))), 'Interpreter', 'none');
end

out = struct();
out.lagSec = lagSec(:);
out.trials = trialKeep(:);
out.acorrX = acorrX;
out.acorrY = acorrY;
out.meanX = meanX(:);
out.meanY = meanY(:);
out.nTrialsPerLagX = nTrialsPerLagX(:);
out.nTrialsPerLagY = nTrialsPerLagY(:);
out.signalMode = opts.signalMode;
out.demeanMode = localResolveDemeanMode(opts);
out.commonDtStepSec = commonDtStepSec;
out.nChunksPerTrial = nChunksRows(keepTrial);
out.nSignalSamplesPerTrial = nSignalSamplesRows(keepTrial);
out.episodes = E;
out.ccg = C;
end


function [lagSec, acorrX, acorrY] = localAlignAcorrRows(lagSecRows, acorrXRows, acorrYRows, keepTrial, dtStep)
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

if isfinite(dtStep) && dtStep > 0
    lagKeys = unique(round(allLag ./ dtStep));
    lagSec = lagKeys(:) .* dtStep;
else
    lagSec = unique(localRoundToTol(allLag(:), 1e-9));
    lagKeys = lagSec;
end

acorrX = NaN(numel(rowIdx), numel(lagSec));
acorrY = NaN(numel(rowIdx), numel(lagSec));
for r = 1:numel(rowIdx)
    i = rowIdx(r);
    thisLag = lagSecRows{i}(:)';
    if isfinite(dtStep) && dtStep > 0
        thisKeys = round(thisLag ./ dtStep);
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
    error('plotGazeAcorr:BadTrialNo', ...
        'trialNo must be numeric, [], or ''all''.');
end

trialNo = unique(double(trialNo(:)'));
if isempty(trialNo) || any(~isfinite(trialNo)) || any(trialNo ~= round(trialNo))
    error('plotGazeAcorr:BadTrialNo', ...
        'trialNo must contain finite integer trial indices.');
end

trialNo = trialNo(trialNo >= 1 & trialNo <= nTrials);
if isempty(trialNo)
    error('plotGazeAcorr:BadTrialNo', ...
        'No requested trials were within the valid range.');
end
end


function tf = localIsAllCode(value)
tf = (ischar(value) && strcmpi(strtrim(value), 'all')) || ...
    (isstring(value) && isscalar(value) && strcmpi(strtrim(char(value)), 'all'));
end


function trialOrder = localEpisodeTrialOrder(E, requestedTrials)
trialOrder = requestedTrials(:);
hasEpisode = ismember(trialOrder, unique(double(E.trial(:))));
trialOrder = trialOrder(hasEpisode);
end


function [sx, sy] = localGazeSignalsFromEpisodes(E, dtStepSec, signalMode)
sx = [];
sy = [];
for i = 1:height(E)
    x = double(E.gazeX{i}(:));
    y = double(E.gazeY{i}(:));
    n = min(numel(x), numel(y));
    if n < 1
        continue
    end
    x = x(1:n);
    y = y(1:n);
    switch signalMode
        case 'position'
            thisX = x;
            thisY = y;
        case 'velocity'
            if n < 2 || ~isfinite(dtStepSec) || dtStepSec <= 0
                continue
            end
            thisX = diff(x) ./ dtStepSec;
            thisY = diff(y) ./ dtStepSec;
    end
    if ~isempty(sx)
        sx(end+1, 1) = NaN; %#ok<AGROW>
        sy(end+1, 1) = NaN; %#ok<AGROW>
    end
    sx = [sx; thisX(:)]; %#ok<AGROW>
    sy = [sy; thisY(:)]; %#ok<AGROW>
end
end


function means = localTrialGazeMeans(E, dtStepSec, signalMode)
[sx, sy] = localGazeSignalsFromEpisodes(E, dtStepSec, signalMode);
means = struct('x', localMeanFinite(sx), 'y', localMeanFinite(sy));
end


function means = localGlobalGazeMeans(E, dtStepSec, signalMode)
[sx, sy] = localGazeSignalsFromEpisodes(E, dtStepSec, signalMode);
means = struct('x', localMeanFinite(sx), 'y', localMeanFinite(sy));
end


function value = localResolveDemeanMean(opts, trialMean, globalMean)
mode = localResolveDemeanMode(opts);
switch mode
    case 'trial'
        value = trialMean;
    case 'global'
        value = globalMean;
    otherwise
        value = NaN;
end
end


function mode = localResolveDemeanMode(opts)
mode = 'chunk';
if isstruct(opts) && isfield(opts, 'demeanMode') && ~isempty(opts.demeanMode)
    mode = lower(strtrim(char(string(opts.demeanMode))));
end
switch mode
    case {'chunk', 'trial', 'global', 'none'}
        return
    otherwise
        error('plotGazeAcorr:BadDemeanMode', ...
            'opts.demeanMode must be ''chunk'', ''trial'', ''global'', or ''none''.');
end
end


function [ac, lagSec] = localAutocorr1d(x, dtStep, opts, fixedMean)
x = double(x(:));
ac = [];
lagSec = [];
if numel(x) < 2 || ~isfinite(dtStep) || dtStep <= 0
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
support = zeros(numel(lags), 1);
demeanMode = localResolveDemeanMode(opts);
for i = 1:numel(runStarts)
    ii = idx(runStarts(i):runEnds(i));
    if numel(ii) < 2
        continue
    end
    xi = x(ii);
    switch demeanMode
        case 'chunk'
            xi = xi - mean(xi, 'omitnan');
        case {'trial', 'global'}
            if isfinite(fixedMean)
                xi = xi - fixedMean;
            end
    end
    if ~any(isfinite(xi)) || ~any(abs(xi(isfinite(xi))) > 0)
        continue
    end
    [aci, lagi] = xcorr(xi, 'coeff');
    finite = isfinite(aci);
    if ~any(finite)
        continue
    end
    loc = lagi(:) + maxLag + 1;
    loc = loc(finite);
    acVals = aci(finite);
    acVals = acVals(:);
    supportVals = double(numel(xi) - abs(lagi(finite)));
    supportVals = supportVals(:);
    w = numel(xi);
    accum(loc) = accum(loc) + w .* acVals;
    weight(loc) = weight(loc) + w;
    support(loc) = support(loc) + supportVals;
end

valid = weight > 0 & support > 0;
if ~any(valid)
    return
end
ac = NaN(size(lags));
ac(valid) = accum(valid) ./ weight(valid);
lagSec = lags(:) .* dtStep;
end


function dtStep = localCommonDtStepSec(dtVals)
dtVals = double(dtVals(:));
dtVals = dtVals(isfinite(dtVals) & dtVals > 0);
if isempty(dtVals)
    dtStep = NaN;
else
    dtStep = median(dtVals, 'omitnan');
end
end


function lagWindow = localLagWindow(value)
lagWindow = [];
if isempty(value)
    return
end
lagWindow = double(value(:)');
if numel(lagWindow) ~= 2 || ~all(isfinite(lagWindow)) || lagWindow(2) <= lagWindow(1)
    error('plotGazeAcorr:BadLagWindow', ...
        'opts.acorrWindowSec must be empty or a finite 1x2 increasing vector.');
end
end


function m = localMeanFinite(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    m = NaN;
else
    m = mean(x, 'omitnan');
end
end


function y = localRoundToTol(x, tol)
y = round(double(x) ./ tol) .* tol;
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


function [out, lagSec, meanX, meanY] = localEmptyOutput(trialNo, opts)
lagSec = NaN(0, 1);
meanX = NaN(0, 1);
meanY = NaN(0, 1);
out = struct();
out.lagSec = lagSec;
out.trials = trialNo(:);
out.acorrX = NaN(0, 0);
out.acorrY = NaN(0, 0);
out.meanX = meanX;
out.meanY = meanY;
out.nTrialsPerLagX = NaN(0, 1);
out.nTrialsPerLagY = NaN(0, 1);
out.signalMode = opts.signalMode;
out.demeanMode = localResolveDemeanMode(opts);
out.commonDtStepSec = NaN;
out.nChunksPerTrial = NaN(0, 1);
out.nSignalSamplesPerTrial = NaN(0, 1);
out.episodes = table();
out.ccg = struct();
end


function localMaybePlotEmpty(axisName, opts)
if ~logical(opts.newFigure)
    return
end
figure;
switch axisName
    case {'x', 'y'}
        localPlotAcorr(NaN(0,1), NaN(0,1), 'Gaze autocorrelation (no valid trials)', opts.lineWidth);
    otherwise
        tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
        nexttile;
        localPlotAcorr(NaN(0,1), NaN(0,1), 'Gaze X autocorrelation (no valid trials)', opts.lineWidth);
        nexttile;
        localPlotAcorr(NaN(0,1), NaN(0,1), 'Gaze Y autocorrelation (no valid trials)', opts.lineWidth);
end
end


function suffix = localPlural(n)
if n == 1
    suffix = '';
else
    suffix = 's';
end
end
