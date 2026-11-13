function out = simCcgTargetResponse(ex, trialNo, opts)
% simCcgTargetResponse  Simulate CCG from delayed/filtered target following.
%
% out = simCcgTargetResponse(ex)
% out = simCcgTargetResponse(ex, trialNo)
% out = simCcgTargetResponse(ex, trialNo, opts)
%
% The function first runs ccg(ex, trialNo, opts.ccgOpts) with plotting off
% to get the exact episodes/chunks selected by the current CCG pipeline.
% It then replaces gaze in those episodes with synthetic gaze generated as:
%
%   delayed target position -> first-order low-pass response -> optional noise
%
% Options:
%   .targetMode        'observed' uses the real selected target sequence;
%                      'unbounded' replaces it with unbounded random walks
%                      sampled from selected target-step increments
%                      (default 'observed')
%   .responseDelaySec  pure response latency in seconds (default 0.2)
%   .responseTauSec    first-order response time constant in seconds
%                      after the delay; 0 disables smoothing (default 0.1)
%   .responseGain      response gain around the initial target position
%                      (default 1)
%   .noisePx           additive Gaussian position noise in pixels
%                      (default 0)
%   .arVelStdPxPerSec  stationary SD of an added AR(1) gaze-velocity
%                      component, in px/s. This creates gaze-intrinsic
%                      velocity autocorrelation independent of the target
%                      (default 0, disabled)
%   .arVelTauSec       autocorrelation time constant for the AR(1)
%                      velocity component (default 0.2)
%   .arVelRho          optional lag-1 AR coefficient for velocity noise;
%                      overrides arVelTauSec when finite. Use negative
%                      values to simulate alternating/anticorrelated
%                      velocity structure (default [])
%   .smoothSec         optional Gaussian smoothing of synthetic stepwise
%                      gaze position, in seconds, after noise (default 0)
%   .demeanMode        velocity demeaning for CCG aggregation, forwarded to
%                      both the observed ccg() call and synthetic CCG:
%                      'chunk' matches ccg default, 'trial' subtracts one
%                      mean per trial/axis, 'global' subtracts one mean per
%                      group/axis, 'none' skips demeaning (default 'chunk')
%   .seed              random seed for noise (default [])
%   .ccgOpts           options passed to ccg for episode selection
%                      (default: all non-simulation opts supplied here)
%   .plot              plot observed and synthetic CCG overlays
%                      (default true)

if nargin < 2
    trialNo = [];
end
if nargin >= 2 && isstruct(trialNo) && (nargin < 3 || isempty(opts))
    opts = trialNo;
    trialNo = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
end

hasExplicitCcgOpts = isfield(opts, 'ccgOpts') && ~isempty(opts.ccgOpts);
defaults = struct( ...
    'targetMode', 'observed', ...
    'responseDelaySec', 0.2, ...
    'responseTauSec', 0.1, ...
    'responseGain', 1, ...
    'noisePx', 0, ...
    'arVelStdPxPerSec', 0, ...
    'arVelTauSec', 0.2, ...
    'arVelRho', [], ...
    'smoothSec', 0, ...
    'demeanMode', 'chunk', ...
    'seed', [], ...
    'ccgOpts', struct(), ...
    'plot', true);
opts = localApplyDefaults(opts, defaults);

if ~isempty(opts.seed)
    localSetRandomSeed(opts.seed);
end

if hasExplicitCcgOpts
    ccgOpts = opts.ccgOpts;
else
    ccgOpts = localExtractCcgOpts(opts);
end
ccgOpts.plot = false;
ccgOpts.newFigure = false;

observed = ccg(ex, trialNo, ccgOpts);
synthetic = localSyntheticCcgFromObserved(observed, opts);

out = struct();
out.observed = observed;
out.synthetic = synthetic;
out.opts = opts;

if logical(opts.plot)
    localPlotObservedVsSynthetic(observed, synthetic);
end
end


function ccgOpts = localExtractCcgOpts(opts)
ccgOpts = opts;
simFields = {'targetMode','responseDelaySec','responseTauSec','responseGain','noisePx','arVelStdPxPerSec','arVelTauSec','arVelRho','smoothSec','seed','ccgOpts','plot'};
dropFields = intersect(fieldnames(ccgOpts), simFields);
if ~isempty(dropFields)
    ccgOpts = rmfield(ccgOpts, dropFields);
end
end


function synthetic = localSyntheticCcgFromObserved(observed, opts)
episodes = observed.episodes;
synthetic = struct();
synthetic.episodes = episodes;
synthetic.trials = observed.trials;
synthetic.trialGroups = observed.trialGroups;
synthetic.groupLabels = observed.groupLabels;
synthetic.groupingSpec = observed.groupingSpec;
synthetic.axisName = observed.axisName;
synthetic.lagSec = observed.lagSec;
synthetic.aggregateMode = observed.aggregateMode;
synthetic.targetSource = observed.targetSource;
synthetic.stepClockOffsetSec = observed.stepClockOffsetSec;
synthetic.groups = cell(size(observed.groups));
synthetic.inputMode = 'syntheticEpisodes';
synthetic.targetMode = localResolveTargetMode(opts.targetMode);
synthetic.demeanMode = localResolveDemeanMode(opts.demeanMode);

if isempty(episodes)
    for g = 1:numel(synthetic.groups)
        synthetic.groups{g} = localEmptyGroup();
        synthetic.groups{g}.groupLabel = observed.groupLabels(g);
    end
    return
end

if strcmp(synthetic.targetMode, 'unbounded')
    synthetic.episodes = localReplaceTargetsWithUnboundedWalks(synthetic.episodes);
end

for i = 1:height(episodes)
    dtStepSec = localFirstFinite(episodes.dtStepSec(i));
    if ~isfinite(dtStepSec) || dtStepSec <= 0
        dtStepSec = localStepDtFromEpisode(episodes, i);
    end
    tx = double(synthetic.episodes.targetX{i}(:));
    ty = double(synthetic.episodes.targetY{i}(:));
    [gx, gy] = localSyntheticGazeFromTarget(tx, ty, dtStepSec, opts);
    synthetic.episodes.gazeX{i} = gx(:)';
    synthetic.episodes.gazeY{i} = gy(:)';
end

commonDtStepSec = localCommonDtStepSec(synthetic.episodes.dtStepSec);
ccgWindowSec = localLagWindowFromObserved(observed);
aggregateMode = char(string(observed.aggregateMode));

for g = 1:numel(synthetic.groups)
    Eg = synthetic.episodes(double(synthetic.episodes.group) == g, :);
    if isempty(Eg)
        group = localEmptyGroup();
    else
        stepAmpMinPx = observed.groups{g}.stepAmpMinPx;
        stepAmpMaxPx = observed.groups{g}.stepAmpMaxPx;
        group = localAggregateEpisodes(Eg, aggregateMode, ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, synthetic.demeanMode);
    end
    group.groupLabel = observed.groupLabels(g);
    synthetic.groups{g} = group;
    if isempty(synthetic.lagSec) && ~isempty(group.lagSec)
        synthetic.lagSec = group.lagSec;
    end
end
end


function episodes = localReplaceTargetsWithUnboundedWalks(episodes)
deltas = localTargetDeltas(episodes);
if isempty(deltas)
    return
end

for i = 1:height(episodes)
    tx = double(episodes.targetX{i}(:));
    ty = double(episodes.targetY{i}(:));
    n = min(numel(tx), numel(ty));
    if n < 2
        continue
    end
    [newX, newY] = localUnboundedWalkFromDeltas(tx(1), ty(1), n, deltas);
    episodes.targetX{i} = newX(:)';
    episodes.targetY{i} = newY(:)';
end
end


function deltas = localTargetDeltas(episodes)
deltas = NaN(0, 2);
for i = 1:height(episodes)
    tx = double(episodes.targetX{i}(:));
    ty = double(episodes.targetY{i}(:));
    n = min(numel(tx), numel(ty));
    if n < 2
        continue
    end
    d = [diff(tx(1:n)), diff(ty(1:n))];
    d = d(all(isfinite(d), 2), :);
    if ~isempty(d)
        deltas = [deltas; d]; %#ok<AGROW>
    end
end
end


function [x, y] = localUnboundedWalkFromDeltas(x0, y0, n, deltas)
x = NaN(n, 1);
y = NaN(n, 1);
x(1) = x0;
y(1) = y0;
if isempty(deltas)
    return
end

drawIdx = randi(size(deltas, 1), n - 1, 1);
d = deltas(drawIdx, :);
x(2:end) = x0 + cumsum(d(:, 1));
y(2:end) = y0 + cumsum(d(:, 2));
end


function targetMode = localResolveTargetMode(value)
targetMode = lower(strtrim(char(string(value))));
switch targetMode
    case {'observed','real','actual'}
        targetMode = 'observed';
    case {'unbounded','noboundary','no-boundary','none'}
        targetMode = 'unbounded';
    otherwise
        error('simCcgTargetResponse:BadTargetMode', ...
            'opts.targetMode must be ''observed'' or ''unbounded''.');
end
end


function [gx, gy] = localSyntheticGazeFromTarget(tx, ty, dtStepSec, opts)
gx = localSyntheticAxis(tx, dtStepSec, opts.responseDelaySec, opts.responseTauSec, opts.responseGain);
gy = localSyntheticAxis(ty, dtStepSec, opts.responseDelaySec, opts.responseTauSec, opts.responseGain);

noisePx = double(localFirstScalar(opts.noisePx));
if isfinite(noisePx) && noisePx > 0
    gx = gx + noisePx .* randn(size(gx));
    gy = gy + noisePx .* randn(size(gy));
end

arVelStdPxPerSec = double(localFirstScalar(opts.arVelStdPxPerSec));
if isfinite(arVelStdPxPerSec) && arVelStdPxPerSec > 0
    arVelTauSec = double(localFirstScalar(opts.arVelTauSec));
    arVelRho = localFirstScalar(opts.arVelRho);
    gx = gx + localIntegratedArVelocityNoise(numel(gx), dtStepSec, arVelStdPxPerSec, arVelTauSec, arVelRho);
    gy = gy + localIntegratedArVelocityNoise(numel(gy), dtStepSec, arVelStdPxPerSec, arVelTauSec, arVelRho);
end

smoothSec = double(localFirstScalar(opts.smoothSec));
if isfinite(smoothSec) && smoothSec > 0
    gx = localSmoothStepSeries(gx, dtStepSec, smoothSec);
    gy = localSmoothStepSeries(gy, dtStepSec, smoothSec);
end
end


function posNoise = localIntegratedArVelocityNoise(n, dtStepSec, velStdPxPerSec, tauSec, rhoOverride)
posNoise = zeros(n, 1);
if n < 2 || ~isfinite(dtStepSec) || dtStepSec <= 0 || ...
        ~isfinite(velStdPxPerSec) || velStdPxPerSec <= 0
    return
end

if nargin >= 5 && isfinite(rhoOverride)
    rho = double(rhoOverride);
else
    tauSec = double(localFirstScalar(tauSec));
    if isfinite(tauSec) && tauSec > 0
        rho = exp(-dtStepSec ./ tauSec);
    else
        rho = 0;
    end
end
rho = min(max(rho, -0.999999), 0.999999);
innovStd = velStdPxPerSec .* sqrt(max(0, 1 - rho.^2));

velNoise = zeros(n - 1, 1);
velNoise(1) = velStdPxPerSec .* randn();
for k = 2:numel(velNoise)
    velNoise(k) = rho .* velNoise(k - 1) + innovStd .* randn();
end
posNoise(2:end) = cumsum(velNoise) .* dtStepSec;
posNoise = posNoise - posNoise(1);
end


function y = localSyntheticAxis(target, dtStepSec, delaySec, tauSec, gain)
target = double(target(:));
n = numel(target);
y = NaN(size(target));
if n == 0 || ~isfinite(dtStepSec) || dtStepSec <= 0
    return
end

delaySec = max(0, double(localFirstScalar(delaySec)));
tauSec = double(localFirstScalar(tauSec));
gain = double(localFirstScalar(gain));
if ~isfinite(gain)
    gain = 1;
end

t = (0:(n - 1))' .* dtStepSec;
targetDelay = interp1(t, target, t - delaySec, 'linear', target(1));
if ~isfinite(tauSec) || tauSec <= 0
    filtered = targetDelay;
else
    alpha = 1 - exp(-dtStepSec ./ tauSec);
    alpha = min(max(alpha, 0), 1);
    filtered = NaN(size(targetDelay));
    filtered(1) = targetDelay(1);
    for k = 2:n
        if isfinite(targetDelay(k)) && isfinite(filtered(k - 1))
            filtered(k) = filtered(k - 1) + alpha .* (targetDelay(k) - filtered(k - 1));
        elseif isfinite(targetDelay(k))
            filtered(k) = targetDelay(k);
        else
            filtered(k) = filtered(k - 1);
        end
    end
end

origin = target(1);
if ~isfinite(origin)
    origin = 0;
end
y = origin + gain .* (filtered - origin);
end


function y = localSmoothStepSeries(x, dtStepSec, smoothSec)
x = double(x(:));
y = x;
if isempty(x) || ~isfinite(dtStepSec) || dtStepSec <= 0 || ~isfinite(smoothSec) || smoothSec <= 0
    return
end

sigmaSteps = smoothSec ./ dtStepSec;
if ~isfinite(sigmaSteps) || sigmaSteps <= 0
    return
end

halfWidth = max(1, ceil(3 .* sigmaSteps));
k = (-halfWidth:halfWidth)';
w = exp(-0.5 .* (k ./ sigmaSteps).^2);
w = w ./ sum(w);

finite = isfinite(x);
x0 = x;
x0(~finite) = 0;
num = conv(x0, w, 'same');
den = conv(double(finite), w, 'same');
y = NaN(size(x));
good = den > 0;
y(good) = num(good) ./ den(good);
end


function group = localAggregateEpisodes(episodes, aggregateMode, ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode)
group = localEmptyGroup();
if isempty(episodes)
    return
end
if nargin < 7 || isempty(demeanMode)
    demeanMode = 'chunk';
end

trialIds = unique(double(episodes.trial(:)'));
if ~isfinite(commonDtStepSec) || commonDtStepSec <= 0
    commonDtStepSec = localCommonDtStepSec(episodes.dtStepSec);
end

[group.ccgX, lagSec] = localPerTrialCorrMatrix(episodes, trialIds, 'x', ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode);
[group.ccgY, ~] = localPerTrialCorrMatrix(episodes, trialIds, 'y', ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode);
group.trials = trialIds;
group.lagSec = lagSec;
group.meanX = mean(group.ccgX, 1, 'omitnan');
group.meanY = mean(group.ccgY, 1, 'omitnan');
[group.nChunksX, group.nChunksY] = localChunkCountsAcrossEpisodes(episodes, ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode);
[group.supportX, group.supportY] = localChunkSupportAcrossEpisodes(episodes, ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode);
[group.aggregateX, group.aggregateY] = localAggregateAcrossEpisodes(episodes, trialIds, aggregateMode, ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode);
group.stepAmpMinPx = stepAmpMinPx;
group.stepAmpMaxPx = stepAmpMaxPx;
end


function [M, lagSec] = localPerTrialCorrMatrix(episodes, trialIds, axisName, ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode)
lagSec = [];
M = NaN(numel(trialIds), 0);
rows = cell(numel(trialIds), 1);
globalMeans = localVelocityMeansForEpisodes(episodes, axisName, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx);
for i = 1:numel(trialIds)
    E = episodes(double(episodes.trial) == trialIds(i), :);
    rows{i} = localAggregateChunksForTrial(E, axisName, ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans);
    if isempty(lagSec) && ~isempty(rows{i}.lagSec)
        lagSec = rows{i}.lagSec(:)';
    end
end
if isempty(lagSec)
    return
end
M = NaN(numel(trialIds), numel(lagSec));
for i = 1:numel(trialIds)
    if numel(rows{i}.corr) == numel(lagSec)
        M(i, :) = rows{i}.corr(:)';
    end
end
end


function row = localAggregateChunksForTrial(E, axisName, ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans)
row = struct('lagSec', NaN(0, 1), 'corr', NaN(0, 1), 'accum', NaN(0, 1), ...
    'weightSum', NaN(0, 1), 'nChunks', NaN(0, 1), 'support', NaN(0, 1));
if isempty(E)
    return
end
if nargin < 7 || isempty(demeanMode)
    demeanMode = 'chunk';
end
if nargin < 8 || isempty(globalMeans)
    globalMeans = localVelocityMeansForEpisodes(E, axisName, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx);
end
if ~isfinite(commonDtStepSec) || commonDtStepSec <= 0
    commonDtStepSec = localCommonDtStepSec(E.dtStepSec);
end
for i = 1:height(E)
    trialMeans = localVelocityMeansForTrial(E, axisName, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, double(E.trial(i)));
    switch axisName
        case 'x'
            chunk = localChunkCorrFromVectors(E.gazeX{i}, E.targetX{i}, E.targetY{i}, commonDtStepSec, ccgWindowSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, trialMeans, globalMeans);
        case 'y'
            chunk = localChunkCorrFromVectors(E.gazeY{i}, E.targetY{i}, E.targetX{i}, commonDtStepSec, ccgWindowSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, trialMeans, globalMeans);
    end
    if isempty(row.lagSec) && ~isempty(chunk.lagSec)
        row.lagSec = chunk.lagSec;
        row.accum = zeros(size(chunk.accum));
        row.weightSum = zeros(size(chunk.accum));
        row.nChunks = zeros(size(chunk.accum));
        row.support = zeros(size(chunk.accum));
    end
    if isempty(chunk.accum) || ~any(chunk.weightSum > 0)
        continue
    end
    row.accum = row.accum + chunk.accum;
    row.weightSum = row.weightSum + chunk.weightSum;
    row.nChunks = row.nChunks + chunk.nChunks;
    row.support = row.support + chunk.support;
end
row.corr = localSafeWeightedMean(row.accum, row.weightSum);
end


function chunk = localChunkCorrFromVectors(gazePos, targetPos, targetPosOther, dtStepSec, ccgWindowSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, trialMeans, globalMeans)
chunk = struct('lagSec', NaN(0, 1), 'corr', NaN(0, 1), 'accum', NaN(0, 1), ...
    'weightSum', NaN(0, 1), 'nChunks', NaN(0, 1), 'support', NaN(0, 1));
gazePos = double(gazePos(:));
targetPos = double(targetPos(:));
targetPosOther = double(targetPosOther(:));
if numel(gazePos) < 3 || numel(targetPos) < 3 || numel(targetPosOther) ~= numel(targetPos) || ...
        ~isfinite(dtStepSec) || dtStepSec <= 0
    return
end

validMask = isfinite(gazePos) & isfinite(targetPos);
if nnz(validMask) < 3
    return
end
if nargin < 8 || isempty(demeanMode)
    demeanMode = 'chunk';
end
if nargin < 9 || isempty(trialMeans)
    trialMeans = struct('gaze', NaN, 'target', NaN);
end
if nargin < 10 || isempty(globalMeans)
    globalMeans = struct('gaze', NaN, 'target', NaN);
end

maxLagSamples = max(1, round(max(abs(ccgWindowSec)) ./ dtStepSec));
lagsAll = (-maxLagSamples:maxLagSamples)';
lagSecAll = lagsAll .* dtStepSec;
keep = lagSecAll >= min(ccgWindowSec) & lagSecAll <= max(ccgWindowSec);
chunk.lagSec = lagSecAll(keep);
chunk.accum = zeros(sum(keep), 1);
chunk.weightSum = zeros(sum(keep), 1);
chunk.nChunks = zeros(sum(keep), 1);
chunk.support = zeros(sum(keep), 1);

idx = find(validMask);
runBreak = [true; diff(idx) > 1];
runStarts = find(runBreak);
runEnds = [runStarts(2:end) - 1; numel(idx)];
for i = 1:numel(runStarts)
    ii = idx(runStarts(i):runEnds(i));
    if numel(ii) < 4
        continue
    end
    gazeVel = diff(gazePos(ii)) ./ dtStepSec;
    targetVel = diff(targetPos(ii)) ./ dtStepSec;
    stepAmpPx = hypot(diff(targetPos(ii)), diff(targetPosOther(ii)));
    good = isfinite(gazeVel) & isfinite(targetVel) & isfinite(stepAmpPx);
    if isfinite(stepAmpMinPx)
        good = good & stepAmpPx >= stepAmpMinPx;
    end
    if isfinite(stepAmpMaxPx)
        good = good & stepAmpPx < stepAmpMaxPx;
    end
    gazeVel = gazeVel(good);
    targetVel = targetVel(good);
    if numel(gazeVel) < 3
        continue
    end
    [gazeVel, targetVel] = localApplyVelocityDemean(gazeVel, targetVel, demeanMode, trialMeans, globalMeans);
    xc = xcorr(gazeVel, targetVel, maxLagSamples, 'coeff');
    xc = double(xc(keep));
    overlapCount = double(numel(gazeVel) - abs(lagsAll(keep)));
    finiteMask = isfinite(xc);
    if ~any(finiteMask)
        continue
    end
    w = numel(gazeVel);
    chunk.accum(finiteMask) = chunk.accum(finiteMask) + w .* xc(finiteMask);
    chunk.weightSum(finiteMask) = chunk.weightSum(finiteMask) + w;
    chunk.nChunks(finiteMask) = chunk.nChunks(finiteMask) + 1;
    chunk.support(finiteMask) = chunk.support(finiteMask) + overlapCount(finiteMask);
end
chunk.corr = localSafeWeightedMean(chunk.accum, chunk.weightSum);
end


function [aggX, aggY] = localAggregateAcrossEpisodes(episodes, trialIds, aggregateMode, ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode)
switch validatestring(char(string(aggregateMode)), {'chunk', 'trial'})
    case 'trial'
        [M, ~] = localPerTrialCorrMatrix(episodes, trialIds, 'x', ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode);
        aggX = mean(M, 1, 'omitnan');
        [M, ~] = localPerTrialCorrMatrix(episodes, trialIds, 'y', ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode);
        aggY = mean(M, 1, 'omitnan');
    case 'chunk'
        globalMeans = localVelocityMeansForEpisodes(episodes, 'x', commonDtStepSec, stepAmpMinPx, stepAmpMaxPx);
        row = localAggregateChunksForTrial(episodes, 'x', ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans);
        aggX = row.corr(:)';
        globalMeans = localVelocityMeansForEpisodes(episodes, 'y', commonDtStepSec, stepAmpMinPx, stepAmpMaxPx);
        row = localAggregateChunksForTrial(episodes, 'y', ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans);
        aggY = row.corr(:)';
end
end


function [nChunksX, nChunksY] = localChunkCountsAcrossEpisodes(episodes, ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode)
globalMeans = localVelocityMeansForEpisodes(episodes, 'x', commonDtStepSec, stepAmpMinPx, stepAmpMaxPx);
row = localAggregateChunksForTrial(episodes, 'x', ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans);
nChunksX = row.nChunks(:)';
globalMeans = localVelocityMeansForEpisodes(episodes, 'y', commonDtStepSec, stepAmpMinPx, stepAmpMaxPx);
row = localAggregateChunksForTrial(episodes, 'y', ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans);
nChunksY = row.nChunks(:)';
end


function [supportX, supportY] = localChunkSupportAcrossEpisodes(episodes, ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode)
globalMeans = localVelocityMeansForEpisodes(episodes, 'x', commonDtStepSec, stepAmpMinPx, stepAmpMaxPx);
row = localAggregateChunksForTrial(episodes, 'x', ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans);
supportX = row.support(:)';
globalMeans = localVelocityMeansForEpisodes(episodes, 'y', commonDtStepSec, stepAmpMinPx, stepAmpMaxPx);
row = localAggregateChunksForTrial(episodes, 'y', ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans);
supportY = row.support(:)';
end


function [gazeVel, targetVel] = localApplyVelocityDemean(gazeVel, targetVel, demeanMode, trialMeans, globalMeans)
switch localResolveDemeanMode(demeanMode)
    case 'chunk'
        gazeVel = gazeVel - mean(gazeVel, 'omitnan');
        targetVel = targetVel - mean(targetVel, 'omitnan');
    case 'trial'
        gazeVel = gazeVel - trialMeans.gaze;
        targetVel = targetVel - trialMeans.target;
    case 'global'
        gazeVel = gazeVel - globalMeans.gaze;
        targetVel = targetVel - globalMeans.target;
    case 'none'
        % Leave velocities in absolute coordinates as a diagnostic only.
end
end


function means = localVelocityMeansForEpisodes(episodes, axisName, dtStepSec, stepAmpMinPx, stepAmpMaxPx)
gazeAll = [];
targetAll = [];
for i = 1:height(episodes)
    switch axisName
        case 'x'
            gazePos = double(episodes.gazeX{i}(:));
            targetPos = double(episodes.targetX{i}(:));
            targetPosOther = double(episodes.targetY{i}(:));
        case 'y'
            gazePos = double(episodes.gazeY{i}(:));
            targetPos = double(episodes.targetY{i}(:));
            targetPosOther = double(episodes.targetX{i}(:));
    end
    [gazeVel, targetVel] = localVelocityVectors(gazePos, targetPos, targetPosOther, dtStepSec, stepAmpMinPx, stepAmpMaxPx);
    gazeAll = [gazeAll; gazeVel(:)]; %#ok<AGROW>
    targetAll = [targetAll; targetVel(:)]; %#ok<AGROW>
end
means = struct('gaze', mean(gazeAll, 'omitnan'), 'target', mean(targetAll, 'omitnan'));
end


function means = localVelocityMeansForTrial(episodes, axisName, dtStepSec, stepAmpMinPx, stepAmpMaxPx, trialId)
if isempty(episodes) || ~ismember('trial', episodes.Properties.VariableNames)
    means = struct('gaze', NaN, 'target', NaN);
    return
end
trialMask = double(episodes.trial(:)) == trialId;
means = localVelocityMeansForEpisodes(episodes(trialMask, :), axisName, dtStepSec, stepAmpMinPx, stepAmpMaxPx);
end


function [gazeVel, targetVel] = localVelocityVectors(gazePos, targetPos, targetPosOther, dtStepSec, stepAmpMinPx, stepAmpMaxPx)
gazeVel = NaN(0, 1);
targetVel = NaN(0, 1);
if numel(gazePos) < 2 || numel(targetPos) < 2 || numel(targetPosOther) ~= numel(targetPos) || ...
        ~isfinite(dtStepSec) || dtStepSec <= 0
    return
end
gazeVel = diff(gazePos(:)) ./ dtStepSec;
targetVel = diff(targetPos(:)) ./ dtStepSec;
stepAmpPx = hypot(diff(targetPos(:)), diff(targetPosOther(:)));
good = isfinite(gazeVel) & isfinite(targetVel) & isfinite(stepAmpPx);
if isfinite(stepAmpMinPx)
    good = good & stepAmpPx >= stepAmpMinPx;
end
if isfinite(stepAmpMaxPx)
    good = good & stepAmpPx < stepAmpMaxPx;
end
gazeVel = gazeVel(good);
targetVel = targetVel(good);
end


function demeanMode = localResolveDemeanMode(value)
demeanMode = lower(strtrim(char(string(value))));
switch demeanMode
    case {'chunk','trial','global','none'}
        return
    otherwise
        error('simCcgTargetResponse:BadDemeanMode', ...
            'opts.demeanMode must be ''chunk'', ''trial'', ''global'', or ''none''.');
end
end


function y = localSafeWeightedMean(accum, weightSum)
y = NaN(size(accum));
valid = isfinite(weightSum) & weightSum > 0;
y(valid) = accum(valid) ./ weightSum(valid);
end


function group = localEmptyGroup()
group = struct('trials', [], 'lagSec', [], 'ccgX', [], 'ccgY', [], 'meanX', [], 'meanY', [], ...
    'aggregateX', [], 'aggregateY', [], ...
    'nChunksX', [], 'nChunksY', [], 'supportX', [], 'supportY', [], ...
    'stepAmpMinPx', NaN, 'stepAmpMaxPx', NaN, 'stepAmpMinDeg', NaN, 'stepAmpMaxDeg', NaN, ...
    'groupLabel', "");
end


function dt = localCommonDtStepSec(dtValues)
dtValues = double(dtValues(:));
dtValues = dtValues(isfinite(dtValues) & dtValues > 0);
if isempty(dtValues)
    dt = NaN;
else
    dt = median(dtValues, 'omitnan');
end
end


function dt = localStepDtFromEpisode(episodes, i)
dt = NaN;
if ~ismember('tRelSec', episodes.Properties.VariableNames)
    return
end
t = double(episodes.tRelSec{i}(:));
d = diff(t);
d = d(isfinite(d) & d > 0);
if ~isempty(d)
    dt = median(d, 'omitnan');
end
end


function ccgWindowSec = localLagWindowFromObserved(observed)
lagSec = double(observed.lagSec(:));
lagSec = lagSec(isfinite(lagSec));
if isempty(lagSec)
    ccgWindowSec = [-0.5 2.5];
else
    ccgWindowSec = [min(lagSec), max(lagSec)];
end
end


function localPlotObservedVsSynthetic(observed, synthetic)
figure;
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
localPlotAxisOverlay(observed, synthetic, 'x');
localPlotAxisOverlay(observed, synthetic, 'y');
sgtitle(sprintf('Observed vs synthetic delayed-target CCG (%d group%s)', ...
    numel(observed.groups), localPlural(numel(observed.groups))), 'Interpreter', 'none');
end


function localPlotAxisOverlay(observed, synthetic, axisName)
nexttile;
hold on
nGroup = numel(observed.groups);
colors = lines(max(nGroup, 1));
legendText = strings(0, 1);
for g = 1:nGroup
    switch axisName
        case 'x'
            obsY = observed.groups{g}.aggregateX;
            simY = synthetic.groups{g}.aggregateX;
        case 'y'
            obsY = observed.groups{g}.aggregateY;
            simY = synthetic.groups{g}.aggregateY;
    end
    if numel(observed.lagSec) == numel(obsY)
        plot(observed.lagSec, obsY, '-', 'Color', colors(g, :), 'LineWidth', 1.25);
        legendText(end + 1, 1) = observed.groupLabels(g) + " obs"; %#ok<AGROW>
    end
    if numel(synthetic.lagSec) == numel(simY)
        plot(synthetic.lagSec, simY, '--', 'Color', colors(g, :), 'LineWidth', 1.25);
        legendText(end + 1, 1) = observed.groupLabels(g) + " sim"; %#ok<AGROW>
    end
end
xline(0, ':');
yline(0, ':');
xlabel('Lag (s)');
ylabel('Velocity xcorr');
title(upper(axisName), 'Interpreter', 'none');
if ~isempty(legendText)
    legend(legendText, 'Location', 'best', 'Interpreter', 'none');
end
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


function value = localFirstScalar(x)
value = NaN;
if isempty(x)
    return
end
if isnumeric(x) || islogical(x)
    value = double(x(1));
end
end


function value = localFirstFinite(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    value = x(1);
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


function suffix = localPlural(n)
if n == 1
    suffix = '';
else
    suffix = 's';
end
end
