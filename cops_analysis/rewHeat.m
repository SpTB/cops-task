function out = rewHeat(ex, trialNo, opts)
% rewHeat  Plot empirical CoPs reward distribution for a session.
%
%   rewHeat(ex)
%   rewHeat(ex, 1:80)
%   out = rewHeat(ex, [], opts)
%
% Default plot units are rewards/sec/bin: the spatial contribution of each
% gaze-location bin to the analyzed session reward rate. This is an
% empirical distribution over where rewards were delivered, using
% reconstructed gaze at each saved reward time.
%
% Useful options:
%   opts.value = 'sessionRate' (default), 'localRate', 'rewardPoints',
%       'meanRewardPerSample', 'dwellTime', or 'sampleCount'
%   opts.rewardMetric = 'events' (default), 'duration', or 'scaled'
%   opts.rewardSource = 'recomputed' (default) or 'saved' for scaled metric
%   opts.queryDeg = []         % return reward values at [x y] plot coords
%   opts.queryNorm = []        % return reward values at [x y] texture coords [0,1]
%   opts.queryPx = []          % return reward values at [x y] screen pixels
%
% Examples:
%   rewHeat(ex)
%   out = rewHeat(ex, 1:(ex.j-1));
%   out = rewHeat(ex, [], struct('value', 'localRate'));

if nargin < 2
    trialNo = [];
end
if nargin < 3 || isempty(opts)
    if isstruct(trialNo)
        opts = trialNo;
        trialNo = [];
    else
        opts = struct();
    end
elseif ~isstruct(opts)
    error('rewHeat:BadOpts', 'opts must be a struct.');
end

localEnsureHelperPath();
localRequireCoPsEx(ex);
opts = localDefaults(opts);

[x0, y0] = localReferenceCenterPx(ex);
[plotBoundsPx, textureBoundsPx, geom] = localPlotGeometryPx(ex, opts);
boundsDeg = localBoundsDeg(plotBoundsPx, x0, y0, ex.setup, opts.flipY);
xEdges = localEdges(boundsDeg.xMin, boundsDeg.xMax, opts.binSizeDeg);
yEdges = localEdges(boundsDeg.yMin, boundsDeg.yMax, opts.binSizeDeg);

trialList = localResolveTrialList(ex, trialNo);
if isempty(trialList)
    error('rewHeat:NoTrialsSelected', 'No completed trials selected.');
end

acc = localEmptyAccumulator(xEdges, yEdges);
trialSummary = localEmptyTrialSummary(numel(trialList));
for i = 1:numel(trialList)
    trialIdx = trialList(i);
    T = ex.Trials(trialIdx);
    [sampleRows, rowSummary] = localRewardSamplesForTrial(ex, T, trialIdx, opts, textureBoundsPx);
    trialSummary = localStoreTrialSummary(trialSummary, i, rowSummary);
    acc.deliveredRewardEvents = acc.deliveredRewardEvents + rowSummary.nDeliveredRewardEvents;
    acc.assignedRewardEvents = acc.assignedRewardEvents + rowSummary.nAssignedRewardEvents;
    if isfinite(rowSummary.deliveredRewardDurationSec)
        acc.deliveredRewardDurationSec = acc.deliveredRewardDurationSec + rowSummary.deliveredRewardDurationSec;
    end
    if isempty(sampleRows.xDeg)
        continue
    end
    acc = localAccumulateSamples(acc, sampleRows);
end

if acc.totalAnalyzedSec <= 0 || acc.totalSamples == 0
    error('rewHeat:NoSamples', 'No valid reward samples remained after filtering.');
end

maps = localFinalizeMaps(acc, opts);
[plotColormap, plotColorLimits, colorSchemeUsed] = localResolveColorDisplay(maps.displayMap, opts);
[rewardPeakPx, rewardPeakDeg, sigmaDeg] = localRewardPeakForPlot(ex, trialList, x0, y0, opts);
if isempty(opts.queryCircleRadiusDeg)
    opts.queryCircleRadiusDeg = sigmaDeg;
end
query = localQueryMaps(opts, x0, y0, ex.setup, geom, xEdges, yEdges, maps, acc.totalAnalyzedSec);
if opts.printQuery && ~isempty(query)
    disp(query);
end

if opts.plot
    if opts.newFigure
        figure;
    end
    imagesc(maps.xCentersDeg, maps.yCentersDeg, maps.displayMap');
    set(gca, 'YDir', 'normal');
    axis image;
    colormap(plotColormap);
    if ~isempty(plotColorLimits)
        caxis(plotColorLimits);
    end
    cb = colorbar;
    ylabel(cb, maps.colorbarLabel);
    xlabel('x position (deg)');
    if opts.flipY
        ylabel('y position (deg, up positive)');
    else
        ylabel('y position (deg, screen down positive)');
    end
    title(sprintf('Empirical reward heat: %s, %.3g %s, %d trials', ...
        maps.value, acc.totalRewardPoints / acc.totalAnalyzedSec, maps.totalRateUnits, numel(trialList)), ...
        'Interpreter', 'none');

    if opts.showTextureBox || opts.showRewardPeak || opts.showSigmaCircle || opts.showQueryCircle
        hold on;
    end
    if opts.showTextureBox
        textureBoundsDeg = localBoundsDeg(textureBoundsPx, x0, y0, ex.setup, opts.flipY);
        localDrawBounds(textureBoundsDeg, [1 1 1] .* 0.95);
    end
    if opts.showSigmaCircle
        localDrawCircles(rewardPeakDeg, sigmaDeg, opts.sigmaCircleColor, ...
            opts.sigmaCircleLineStyle, opts.sigmaCircleLineWidth);
    end
    if opts.showRewardPeak
        localDrawRewardPeak(rewardPeakDeg, opts);
    end
    if opts.showQueryCircle
        localDrawQueryCircles(query, opts);
    end
    if opts.showTextureBox || opts.showRewardPeak || opts.showSigmaCircle || opts.showQueryCircle
        hold off;
    end
end

out = struct();
out.value = maps.value;
out.rewardMetric = opts.rewardMetric;
out.rewardUnits = maps.rewardUnits;
out.xEdgesDeg = xEdges;
out.yEdgesDeg = yEdges;
out.xCentersDeg = maps.xCentersDeg;
out.yCentersDeg = maps.yCentersDeg;
out.rewardPoints = maps.rewardPoints;
out.dwellTimeSec = maps.dwellTimeSec;
out.sampleCount = maps.sampleCount;
out.sessionRate = maps.sessionRate;
out.localRate = maps.localRate;
out.meanRewardPerSample = maps.meanRewardPerSample;
out.displayMap = maps.displayMap;
out.colorbarLabel = maps.colorbarLabel;
out.colorScheme = colorSchemeUsed;
out.colorLimits = plotColorLimits;
out.colormap = plotColormap;
out.totalRewardPoints = acc.totalRewardPoints;
out.totalAnalyzedSec = acc.totalAnalyzedSec;
out.totalRewardRate = acc.totalRewardPoints / acc.totalAnalyzedSec;
out.totalRewardRateUnits = maps.totalRateUnits;
out.totalSamples = acc.totalSamples;
out.deliveredRewardEvents = acc.deliveredRewardEvents;
out.assignedRewardEvents = acc.assignedRewardEvents;
out.deliveredRewardEventsPerSec = acc.deliveredRewardEvents / acc.totalAnalyzedSec;
out.deliveredRewardDurationSec = acc.deliveredRewardDurationSec;
out.deliveredRewardDurationPerSec = acc.deliveredRewardDurationSec / acc.totalAnalyzedSec;
out.rewardPeakPx = rewardPeakPx;
out.rewardPeakDeg = rewardPeakDeg;
out.gaussSigmaDeg = sigmaDeg;
out.trials = trialList;
out.trialSummary = struct2table(trialSummary);
out.query = query;
out.geometry = geom;
out.opts = opts;
end


function opts = localDefaults(opts)
defaults = struct( ...
    'value', 'sessionRate', ...
    'rewardMetric', 'events', ...
    'rewardSource', 'recomputed', ...
    'rewardTimeToleranceSec', [], ...
    'useEyeTime', true, ...
    'onlyGoState', true, ...
    'insideTextureOnly', true, ...
    'binSizeDeg', 0.25, ...
    'smoothSigmaDeg', 0.5, ...
    'flipY', true, ...
    'plot', true, ...
    'newFigure', true, ...
    'showTextureBox', true, ...
    'showRewardPeak', true, ...
    'rewardPeakMarker', '+', ...
    'rewardPeakColor', [0 0 0], ...
    'rewardPeakMarkerSize', 10, ...
    'rewardPeakLineWidth', 2.25, ...
    'showSigmaCircle', true, ...
    'sigmaCircleColor', [0 0 0], ...
    'sigmaCircleLineStyle', ':', ...
    'sigmaCircleLineWidth', 1.5, ...
    'queryDeg', [], ...
    'queryNorm', [], ...
    'queryPx', [], ...
    'queryCircleRadiusDeg', [], ...
    'showQueryCircle', true, ...
    'queryCircleColor', [0 0 0], ...
    'queryCircleLineStyle', '--', ...
    'queryCircleLineWidth', 1.25, ...
    'printQuery', true, ...
    'colorScheme', 'viridis', ...
    'colormap', [], ...
    'nColors', 256, ...
    'colorLimits', [], ...
    'colorLimitMode', 'none', ...
    'colorLimitPrctile', 99);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(opts, names{i}) || isempty(opts.(names{i}))
        opts.(names{i}) = defaults.(names{i});
    end
end
opts.value = localCanonicalValue(opts.value);
opts.rewardMetric = validatestring(char(string(opts.rewardMetric)), {'events', 'duration', 'scaled'});
opts.rewardSource = validatestring(char(string(opts.rewardSource)), {'recomputed', 'saved'});
opts.binSizeDeg = double(localFirstScalar(opts.binSizeDeg));
opts.smoothSigmaDeg = double(localFirstScalar(opts.smoothSigmaDeg));
if ~isfinite(opts.binSizeDeg) || opts.binSizeDeg <= 0
    error('rewHeat:BadBinSize', 'opts.binSizeDeg must be positive.');
end
if ~isfinite(opts.smoothSigmaDeg) || opts.smoothSigmaDeg < 0
    error('rewHeat:BadSmoothSigma', 'opts.smoothSigmaDeg must be non-negative.');
end
if ~isempty(opts.rewardTimeToleranceSec)
    opts.rewardTimeToleranceSec = double(localFirstScalar(opts.rewardTimeToleranceSec));
    if ~isfinite(opts.rewardTimeToleranceSec) || opts.rewardTimeToleranceSec <= 0
        error('rewHeat:BadRewardTimeTolerance', 'opts.rewardTimeToleranceSec must be positive.');
    end
end
opts.showTextureBox = logical(localFirstScalar(opts.showTextureBox));
opts.showRewardPeak = logical(localFirstScalar(opts.showRewardPeak));
opts.showSigmaCircle = logical(localFirstScalar(opts.showSigmaCircle));
opts.showQueryCircle = logical(localFirstScalar(opts.showQueryCircle));
opts.printQuery = logical(localFirstScalar(opts.printQuery));
if ~isempty(opts.queryCircleRadiusDeg)
    opts.queryCircleRadiusDeg = double(localFirstScalar(opts.queryCircleRadiusDeg));
    if ~isfinite(opts.queryCircleRadiusDeg) || opts.queryCircleRadiusDeg <= 0
        opts.queryCircleRadiusDeg = [];
    end
end
opts.nColors = max(2, round(double(localFirstScalar(opts.nColors))));
opts.colorScheme = char(string(opts.colorScheme));
opts.colorLimitMode = validatestring(char(string(opts.colorLimitMode)), {'none', 'prctile'});
opts.colorLimitPrctile = double(localFirstScalar(opts.colorLimitPrctile));
if ~isfinite(opts.colorLimitPrctile) || opts.colorLimitPrctile <= 0 || opts.colorLimitPrctile > 100
    error('rewHeat:BadColorLimitPrctile', 'opts.colorLimitPrctile must be in (0, 100].');
end
end


function value = localCanonicalValue(value)
value = lower(strtrim(char(string(value))));
switch value
    case {'sessionrate', 'rate', 'rewardrate', 'earnedrate', 'distribution'}
        value = 'sessionRate';
    case {'localrate', 'conditionalrate', 'conditional'}
        value = 'localRate';
    case {'rewardpoints', 'points', 'sum', 'rewardevents', 'events', 'countrewards'}
        value = 'rewardPoints';
    case {'meanrewardpersample', 'meanreward', 'samplemean'}
        value = 'meanRewardPerSample';
    case {'dwelltime', 'dwell', 'time'}
        value = 'dwellTime';
    case {'samplecount', 'count', 'samples'}
        value = 'sampleCount';
    otherwise
        error('rewHeat:BadValue', ...
            'opts.value must be sessionRate, localRate, rewardPoints, meanRewardPerSample, dwellTime, or sampleCount.');
end
end


function localEnsureHelperPath()
thisDir = fileparts(mfilename('fullpath'));
helperDir = fullfile(thisDir, 'helpers');
if exist(helperDir, 'dir')
    addpath(helperDir);
end
end


function localRequireCoPsEx(ex)
if ~isstruct(ex) || ~isfield(ex, 'exp') || ~isfield(ex.exp, 'CoPs')
    error('rewHeat:BadEx', 'Input ex must contain ex.exp.CoPs.');
end
if ~isfield(ex, 'setup') || ~isfield(ex.setup, 'screenRect') || ...
        ~isfield(ex.setup, 'monitorWidth') || ~isfield(ex.setup, 'viewingDistance')
    error('rewHeat:MissingSetup', ...
        'ex.setup.screenRect, monitorWidth, and viewingDistance are required.');
end
end


function acc = localEmptyAccumulator(xEdges, yEdges)
sz = [numel(xEdges) - 1, numel(yEdges) - 1];
acc = struct();
acc.xEdgesDeg = xEdges;
acc.yEdgesDeg = yEdges;
acc.rewardPoints = zeros(sz);
acc.dwellTimeSec = zeros(sz);
acc.sampleCount = zeros(sz);
acc.totalRewardPoints = 0;
acc.totalAnalyzedSec = 0;
acc.totalSamples = 0;
acc.deliveredRewardEvents = 0;
acc.assignedRewardEvents = 0;
acc.deliveredRewardDurationSec = 0;
end


function rows = localEmptyTrialSummary(n)
rows = repmat(struct( ...
    'trial', NaN, ...
    'nSamples', 0, ...
    'durationSec', 0, ...
    'rewardPoints', 0, ...
    'rewardRate', NaN, ...
    'nDeliveredRewardEvents', 0, ...
    'nAssignedRewardEvents', 0, ...
    'deliveredRewardDurationSec', 0, ...
    'rewardSource', ""), n, 1);
end


function [samples, summary] = localRewardSamplesForTrial(ex, T, trialIdx, opts, textureBoundsPx)
samples = struct('xDeg', [], 'yDeg', [], 'reward', [], 'dtSec', []);
summary = struct( ...
    'trial', trialIdx, ...
    'nSamples', 0, ...
    'durationSec', 0, ...
    'rewardPoints', 0, ...
    'rewardRate', NaN, ...
    'nDeliveredRewardEvents', localRewardEventCount(T), ...
    'nAssignedRewardEvents', 0, ...
    'deliveredRewardDurationSec', localDeliveredRewardDurationSec(ex, T), ...
    'rewardSource', string(opts.rewardMetric));

eyeOpts = opts;
[xPx, yPx, tRel, tAbs, valid] = reconstructEyePx(ex, T, opts.useEyeTime, eyeOpts);
if isempty(xPx)
    return
end
xPx = xPx(:);
yPx = yPx(:);
tRel = tRel(:);
tAbs = tAbs(:);
valid = valid(:);
n = min([numel(xPx), numel(yPx), numel(tRel), numel(tAbs), numel(valid)]);
xPx = xPx(1:n);
yPx = yPx(1:n);
tRel = tRel(1:n);
tAbs = tAbs(1:n);
valid = valid(1:n);

inBounds = valid & localOnScreenMask(xPx, yPx, ex.setup.screenRect);
if opts.insideTextureOnly
    inBounds = inBounds & xPx >= textureBoundsPx.xMin & xPx <= textureBoundsPx.xMax & ...
        yPx >= textureBoundsPx.yMin & yPx <= textureBoundsPx.yMax;
end
analysisMask = inBounds;
if opts.onlyGoState
    analysisMask = analysisMask & localGoMask(T, tAbs);
end
if ~any(analysisMask)
    return
end

dtSec = localSampleDtSec(ex, tRel);
if ~isfinite(dtSec) || dtSec <= 0
    return
end

if strcmp(opts.rewardMetric, 'scaled')
    reward = localRewardSignal(ex, T, xPx, yPx, tRel, inBounds, analysisMask, opts);
    summary.rewardSource = string(['scaled-' char(string(opts.rewardSource))]);
else
    [reward, nAssignedRewardEvents] = localEmpiricalRewardSignal(ex, T, tAbs, analysisMask, dtSec, opts);
    summary.nAssignedRewardEvents = nAssignedRewardEvents;
end

[x0, y0] = localReferenceCenterPx(ex);
xDeg = localPxToDeg(xPx - x0, ex.setup);
yDeg = localPxToDeg(yPx - y0, ex.setup);
if opts.flipY
    yDeg = -yDeg;
end

keep = analysisMask & isfinite(reward) & isfinite(xDeg) & isfinite(yDeg);
samples.xDeg = xDeg(keep);
samples.yDeg = yDeg(keep);
samples.reward = reward(keep);
samples.dtSec = repmat(dtSec, sum(keep), 1);

summary.nSamples = numel(samples.reward);
summary.durationSec = sum(samples.dtSec);
summary.rewardPoints = sum(samples.reward);
if summary.durationSec > 0
    summary.rewardRate = summary.rewardPoints ./ summary.durationSec;
end
end


function reward = localRewardSignal(ex, T, xPx, yPx, tRel, inBounds, analysisMask, opts)
reward = NaN(size(xPx));
if strcmp(opts.rewardSource, 'saved') && isfield(T, 'scaledReward') && ~isempty(T.scaledReward)
    saved = double(T.scaledReward(:));
    idx = find(analysisMask(:));
    n = min(numel(saved), numel(idx));
    if n > 0
        reward(idx(1:n)) = saved(1:n);
    end
    if any(isfinite(reward(analysisMask)))
        return
    end
end

[targetX, targetY, target2X, target2Y] = mapTargetsByStep(ex, T, tRel);
reward = localRecomputeScaledReward(ex, T, xPx, yPx, targetX, targetY, target2X, target2Y, inBounds);
end


function [reward, nAssigned] = localEmpiricalRewardSignal(ex, T, tAbs, analysisMask, dtSec, opts)
reward = zeros(size(tAbs));
nAssigned = 0;
rewardTimes = localRewardTimesAbs(T);
if isempty(rewardTimes)
    return
end

sampleIdx = find(analysisMask(:) & isfinite(tAbs(:)));
if isempty(sampleIdx)
    return
end

if isempty(opts.rewardTimeToleranceSec)
    timeTolSec = max(2 .* dtSec, 0.05);
else
    timeTolSec = opts.rewardTimeToleranceSec;
end
eventAmount = localRewardEventAmount(ex, T, opts.rewardMetric);
for i = 1:numel(rewardTimes)
    [delta, nearestRelIdx] = min(abs(tAbs(sampleIdx) - rewardTimes(i)));
    if isfinite(delta) && delta <= timeTolSec
        nearestIdx = sampleIdx(nearestRelIdx);
        reward(nearestIdx) = reward(nearestIdx) + eventAmount;
        nAssigned = nAssigned + 1;
    end
end
end


function rewardTimes = localRewardTimesAbs(T)
rewardTimes = [];
if ~isfield(T, 'times') || ~isfield(T.times, 'reward') || isempty(T.times.reward)
    return
end
rewardTimes = double(T.times.reward(:));
rewardTimes = rewardTimes(isfinite(rewardTimes));
if isempty(rewardTimes)
    return
end

trialStart = localFirstScalar(getfieldOrEmpty(T, 'TrialStart'));
trialEnd = localFirstScalar(getfieldOrEmpty(T, 'TrialEnd'));
if ~isfinite(trialStart)
    return
end

if isfinite(trialEnd)
    inAbsWindow = rewardTimes >= trialStart - 1 & rewardTimes <= trialEnd + 1;
    relTimes = rewardTimes + trialStart;
    inRelWindow = relTimes >= trialStart - 1 & relTimes <= trialEnd + 1;
    if mean(inRelWindow) > mean(inAbsWindow)
        rewardTimes = relTimes;
    end
    return
end

looksRelative = trialStart > 60 && all(rewardTimes < 60);
if looksRelative
    rewardTimes = rewardTimes + trialStart;
end
end


function amount = localRewardEventAmount(ex, T, rewardMetric)
switch char(string(rewardMetric))
    case 'duration'
        amount = NaN;
        if isfield(T, 'RewardSize') && isfinite(localFirstScalar(T.RewardSize))
            amount = double(localFirstScalar(T.RewardSize));
        elseif isfield(ex.exp.CoPs, 'rew') && isfield(ex.exp.CoPs.rew, 'duration') && ...
                isfinite(localFirstScalar(ex.exp.CoPs.rew.duration))
            amount = double(localFirstScalar(ex.exp.CoPs.rew.duration));
        end
        if ~isfinite(amount)
            amount = 1;
        end
    otherwise
        amount = 1;
end
end


function scaledReward = localRecomputeScaledReward(ex, T, xPx, yPx, targetX, targetY, target2X, target2Y, inBounds)
xPx = xPx(:);
yPx = yPx(:);
targetX = targetX(:);
targetY = targetY(:);
target2X = target2X(:);
target2Y = target2Y(:);
n = min([numel(xPx), numel(yPx), numel(targetX), numel(targetY), numel(target2X), numel(target2Y), numel(inBounds)]);
xPx = xPx(1:n);
yPx = yPx(1:n);
targetX = targetX(1:n);
targetY = targetY(1:n);
target2X = target2X(1:n);
target2Y = target2Y(1:n);
inBounds = inBounds(1:n);

maxDistanceReward = localRewardRadiusPx(ex, T);
d1 = hypot(xPx - targetX, yPx - targetY);
d2 = hypot(xPx - target2X, yPx - target2Y);
dMin = d1;
useT2 = isfinite(d2) & ((~isfinite(d1)) | d2 < d1);
dMin(useT2) = d2(useT2);
closeness = 1 - (dMin ./ maxDistanceReward);
closeness = max(0, min(1, closeness));
closeness(~inBounds) = 0;

if localIsPursuitTrial(T)
    scaledReward = closeness;
    return
end

gaussReward = localGaussianRewardAtGaze(ex, T, xPx, yPx, inBounds);
rewardType = 'mult';
if isfield(ex.exp.CoPs, 'ctl') && isfield(ex.exp.CoPs.ctl, 'reward_type') && ~isempty(ex.exp.CoPs.ctl.reward_type)
    rewardType = lower(strtrim(char(string(ex.exp.CoPs.ctl.reward_type))));
end

switch rewardType
    case 'add'
        precisionWeight = localGetScalarField(ex.exp.CoPs.ctl, 'precision_weight', 0.5);
        scaledReward = closeness .* precisionWeight + gaussReward .* (1 - precisionWeight);
    otherwise
        scaledReward = closeness .* gaussReward;
end
scaledReward(~inBounds) = 0;
end


function rewardRadiusPx = localRewardRadiusPx(ex, T)
rewardRadiusPx = NaN;
if isstruct(T) && isfield(T, 'rewardRadiusPx') && isfinite(localFirstScalar(T.rewardRadiusPx))
    rewardRadiusPx = double(localFirstScalar(T.rewardRadiusPx));
elseif isstruct(T) && isfield(T, 'mainRewardRadiusPx') && isfinite(localFirstScalar(T.mainRewardRadiusPx))
    rewardRadiusPx = double(localFirstScalar(T.mainRewardRadiusPx));
end
if isfinite(rewardRadiusPx) && rewardRadiusPx > 0
    return
end
graph = ex.exp.CoPs.graph;
ctl = ex.exp.CoPs.ctl;
radiusScreenPx = NaN;
if isfield(graph, 'radiusScreenPx') && isfinite(localFirstScalar(graph.radiusScreenPx))
    radiusScreenPx = double(localFirstScalar(graph.radiusScreenPx));
elseif isfield(graph, 'radius') && isfield(graph, 'size_mult') && ...
        isfinite(localFirstScalar(graph.radius)) && isfinite(localFirstScalar(graph.size_mult))
    radiusScreenPx = double(localFirstScalar(graph.radius)) .* double(localFirstScalar(graph.size_mult));
end
rewardRadiusPx = localGetScalarField(ctl, 'max_dist_mult', 2.5) .* radiusScreenPx;
end


function gaussReward = localGaussianRewardAtGaze(ex, T, xPx, yPx, inBounds)
centerPx = localRewardNormToScreenPx(ex, localTrialRewardCenterNorm(ex, T));
sigmaPx = localRewardSigmaPx(ex);
gaussScalar = localTrialGaussScalar(ex, T);
gaussian = exp(-((xPx - centerPx(1)).^2 + (yPx - centerPx(2)).^2) ./ (2 * sigmaPx.^2));
gaussian(~inBounds) = 0;
gaussReward = gaussian .* (gaussScalar - 1) + 1;
gaussReward(~inBounds) = 0;
end


function tf = localIsPursuitTrial(T)
tf = false;
if isstruct(T) && isfield(T, 'isPursuitTrial') && ~isempty(T.isPursuitTrial)
    tf = logical(localFirstScalar(T.isPursuitTrial));
elseif isstruct(T) && isfield(T, 'runPhase') && ~isempty(T.runPhase)
    tf = strcmpi(char(string(T.runPhase)), 'pursuit') || strcmpi(char(string(T.runPhase)), 'pur');
end
end


function acc = localAccumulateSamples(acc, samples)
[~, ~, xBin] = histcounts(samples.xDeg, acc.xEdgesDeg);
[~, ~, yBin] = histcounts(samples.yDeg, acc.yEdgesDeg);
valid = xBin > 0 & yBin > 0 & isfinite(samples.reward) & isfinite(samples.dtSec);
if ~any(valid)
    return
end
xBin = xBin(valid);
yBin = yBin(valid);
reward = samples.reward(valid);
dtSec = samples.dtSec(valid);
lin = sub2ind(size(acc.rewardPoints), xBin, yBin);
acc.rewardPoints = acc.rewardPoints + reshape(accumarray(lin, reward, [numel(acc.rewardPoints), 1], @sum, 0), size(acc.rewardPoints));
acc.dwellTimeSec = acc.dwellTimeSec + reshape(accumarray(lin, dtSec, [numel(acc.dwellTimeSec), 1], @sum, 0), size(acc.dwellTimeSec));
acc.sampleCount = acc.sampleCount + reshape(accumarray(lin, ones(size(lin)), [numel(acc.sampleCount), 1], @sum, 0), size(acc.sampleCount));
acc.totalRewardPoints = acc.totalRewardPoints + sum(reward);
acc.totalAnalyzedSec = acc.totalAnalyzedSec + sum(dtSec);
acc.totalSamples = acc.totalSamples + numel(reward);
end


function trialSummary = localStoreTrialSummary(trialSummary, i, rowSummary)
trialSummary(i) = rowSummary;
end


function maps = localFinalizeMaps(acc, opts)
rewardPoints = localSmooth2(acc.rewardPoints, opts.smoothSigmaDeg ./ opts.binSizeDeg);
dwellTimeSec = localSmooth2(acc.dwellTimeSec, opts.smoothSigmaDeg ./ opts.binSizeDeg);
sampleCount = localSmooth2(acc.sampleCount, opts.smoothSigmaDeg ./ opts.binSizeDeg);

sessionRate = rewardPoints ./ max(acc.totalAnalyzedSec, eps);
localRate = rewardPoints ./ dwellTimeSec;
localRate(dwellTimeSec <= 0) = NaN;
meanRewardPerSample = rewardPoints ./ sampleCount;
meanRewardPerSample(sampleCount <= 0) = NaN;

[rewardUnits, sessionRateLabel, localRateLabel, sumLabel, meanLabel, totalRateUnits] = ...
    localRewardMetricLabels(opts.rewardMetric);
switch opts.value
    case 'localRate'
        displayMap = localRate;
        colorbarLabel = localRateLabel;
    case 'rewardPoints'
        displayMap = rewardPoints;
        colorbarLabel = sumLabel;
    case 'meanRewardPerSample'
        displayMap = meanRewardPerSample;
        colorbarLabel = meanLabel;
    case 'dwellTime'
        displayMap = dwellTimeSec;
        colorbarLabel = 'gaze dwell time (sec)';
    case 'sampleCount'
        displayMap = sampleCount;
        colorbarLabel = 'gaze sample count';
    otherwise
        displayMap = sessionRate;
        colorbarLabel = sessionRateLabel;
end

maps = struct();
maps.value = opts.value;
maps.rewardUnits = rewardUnits;
maps.totalRateUnits = totalRateUnits;
maps.xCentersDeg = localBinCenters(acc.xEdgesDeg);
maps.yCentersDeg = localBinCenters(acc.yEdgesDeg);
maps.rewardPoints = rewardPoints;
maps.dwellTimeSec = dwellTimeSec;
maps.sampleCount = sampleCount;
maps.sessionRate = sessionRate;
maps.localRate = localRate;
maps.meanRewardPerSample = meanRewardPerSample;
maps.displayMap = displayMap;
maps.colorbarLabel = colorbarLabel;
end


function [rewardUnits, sessionRateLabel, localRateLabel, sumLabel, meanLabel, totalRateUnits] = localRewardMetricLabels(rewardMetric)
switch char(string(rewardMetric))
    case 'duration'
        rewardUnits = 'reward delivery seconds';
        sessionRateLabel = 'reward delivery rate contribution (sec/sec/bin)';
        localRateLabel = 'conditional reward delivery rate (sec/sec)';
        sumLabel = 'reward delivery time (sec)';
        meanLabel = 'reward delivery sec/sample';
        totalRateUnits = 'reward-sec/sec';
    case 'scaled'
        rewardUnits = 'scaled reward points';
        sessionRateLabel = 'scaled reward rate contribution (points/sec/bin)';
        localRateLabel = 'conditional scaled reward rate (points/sec)';
        sumLabel = 'scaled reward points';
        meanLabel = 'scaled reward points/sample';
        totalRateUnits = 'scaled-points/sec';
    otherwise
        rewardUnits = 'reward events';
        sessionRateLabel = 'reward event rate contribution (rewards/sec/bin)';
        localRateLabel = 'conditional reward event rate (rewards/sec)';
        sumLabel = 'reward events';
        meanLabel = 'reward events/sample';
        totalRateUnits = 'rewards/sec';
end
end


function query = localQueryMaps(opts, x0, y0, setup, geom, xEdges, yEdges, maps, totalAnalyzedSec)
query = table();
rows = struct('units', {}, 'inputX', {}, 'inputY', {}, 'xDeg', {}, 'yDeg', {}, ...
    'xBin', {}, 'yBin', {}, 'insideMap', {}, 'sessionRate', {}, ...
    'localRate', {}, 'rewardPoints', {}, 'dwellTimeSec', {}, ...
    'sampleCount', {}, 'meanRewardPerSample', {}, 'displayValue', {}, ...
    'circleRadiusDeg', {}, 'circleSessionRate', {}, 'circleLocalRate', {}, ...
    'circleRewardPoints', {}, 'circleDwellTimeSec', {}, 'circleSampleCount', {});
rows = localAppendQueryRows(rows, opts.queryDeg, 'deg', x0, y0, setup, opts, geom);
rows = localAppendQueryRows(rows, opts.queryNorm, 'norm', x0, y0, setup, opts, geom);
rows = localAppendQueryRows(rows, opts.queryPx, 'px', x0, y0, setup, opts, geom);
if isempty(rows)
    return
end

if isempty(opts.queryCircleRadiusDeg)
    circleRadiusDeg = NaN;
else
    circleRadiusDeg = double(opts.queryCircleRadiusDeg);
end
for i = 1:numel(rows)
    xBin = localBinIndex(rows(i).xDeg, xEdges);
    yBin = localBinIndex(rows(i).yDeg, yEdges);
    rows(i).xBin = xBin;
    rows(i).yBin = yBin;
    rows(i).insideMap = isfinite(xBin) && isfinite(yBin);
    rows(i).circleRadiusDeg = circleRadiusDeg;
    if rows(i).insideMap
        rows(i).sessionRate = maps.sessionRate(xBin, yBin);
        rows(i).localRate = maps.localRate(xBin, yBin);
        rows(i).rewardPoints = maps.rewardPoints(xBin, yBin);
        rows(i).dwellTimeSec = maps.dwellTimeSec(xBin, yBin);
        rows(i).sampleCount = maps.sampleCount(xBin, yBin);
        rows(i).meanRewardPerSample = maps.meanRewardPerSample(xBin, yBin);
        rows(i).displayValue = maps.displayMap(xBin, yBin);
    end
    if isfinite(circleRadiusDeg) && circleRadiusDeg > 0
        circleMask = localCircleBinMask(rows(i).xDeg, rows(i).yDeg, circleRadiusDeg, maps.xCentersDeg, maps.yCentersDeg);
        rows(i).circleRewardPoints = sum(maps.rewardPoints(circleMask));
        rows(i).circleDwellTimeSec = sum(maps.dwellTimeSec(circleMask));
        rows(i).circleSampleCount = sum(maps.sampleCount(circleMask));
        rows(i).circleSessionRate = rows(i).circleRewardPoints ./ max(totalAnalyzedSec, eps);
        rows(i).circleLocalRate = rows(i).circleRewardPoints ./ rows(i).circleDwellTimeSec;
        if rows(i).circleDwellTimeSec <= 0
            rows(i).circleLocalRate = NaN;
        end
    end
end
query = struct2table(rows);
end


function rows = localAppendQueryRows(rows, coords, units, x0, y0, setup, opts, geom)
if isempty(coords)
    return
end
coords = localFirstPointRows(coords);
for i = 1:size(coords, 1)
    inputXY = coords(i, :);
    [xDeg, yDeg] = localQueryToPlotDeg(inputXY, units, x0, y0, setup, opts, geom);
    row = struct();
    row.units = string(units);
    row.inputX = inputXY(1);
    row.inputY = inputXY(2);
    row.xDeg = xDeg;
    row.yDeg = yDeg;
    row.xBin = NaN;
    row.yBin = NaN;
    row.insideMap = false;
    row.sessionRate = NaN;
    row.localRate = NaN;
    row.rewardPoints = NaN;
    row.dwellTimeSec = NaN;
    row.sampleCount = NaN;
    row.meanRewardPerSample = NaN;
    row.displayValue = NaN;
    row.circleRadiusDeg = NaN;
    row.circleSessionRate = NaN;
    row.circleLocalRate = NaN;
    row.circleRewardPoints = NaN;
    row.circleDwellTimeSec = NaN;
    row.circleSampleCount = NaN;
    rows(end+1) = row; %#ok<AGROW>
end
end


function [xDeg, yDeg] = localQueryToPlotDeg(inputXY, units, x0, y0, setup, opts, geom)
switch lower(units)
    case 'deg'
        xDeg = inputXY(1);
        yDeg = inputXY(2);
    case 'norm'
        xyPx = [geom.screenRect(1) + geom.xShift + inputXY(1) .* geom.drawnTexW, ...
            geom.screenRect(2) + geom.yShift + inputXY(2) .* geom.drawnTexH];
        xyDeg = localScreenPxToPlotDeg(xyPx, x0, y0, setup, opts.flipY);
        xDeg = xyDeg(1);
        yDeg = xyDeg(2);
    case 'px'
        xyDeg = localScreenPxToPlotDeg(inputXY, x0, y0, setup, opts.flipY);
        xDeg = xyDeg(1);
        yDeg = xyDeg(2);
    otherwise
        xDeg = NaN;
        yDeg = NaN;
end
end


function [rewardPeakPx, rewardPeakDeg, sigmaDeg] = localRewardPeakForPlot(ex, trialList, x0, y0, opts)
rewardPeakNorm = NaN(0, 2);
for i = 1:numel(trialList)
    T = ex.Trials(trialList(i));
    ctrNorm = localTrialRewardCenterNorm(ex, T);
    if all(isfinite(ctrNorm))
        rewardPeakNorm(end+1, :) = ctrNorm; %#ok<AGROW>
    end
end
if isempty(rewardPeakNorm)
    rewardPeakNorm = localRewardCenterNormFromSettings(ex);
end
rewardPeakPx = localRewardNormToScreenPx(ex, localUniqueRowsTol(rewardPeakNorm, 1e-9));
rewardPeakDeg = localScreenPxToPlotDeg(rewardPeakPx, x0, y0, ex.setup, opts.flipY);
sigmaDeg = localPxToDeg(localRewardSigmaPx(ex), ex.setup);
end


function localDrawBounds(bounds, color)
x = [bounds.xMin bounds.xMax bounds.xMax bounds.xMin bounds.xMin];
y = [bounds.yMin bounds.yMin bounds.yMax bounds.yMax bounds.yMin];
plot(x, y, '-', 'Color', color, 'LineWidth', 1.25);
end


function localDrawRewardPeak(rewardPeakDeg, opts)
if isempty(rewardPeakDeg)
    return
end
keep = all(isfinite(rewardPeakDeg), 2);
if ~any(keep)
    return
end
plot(rewardPeakDeg(keep, 1), rewardPeakDeg(keep, 2), ...
    char(string(opts.rewardPeakMarker)), ...
    'Color', opts.rewardPeakColor, ...
    'MarkerSize', opts.rewardPeakMarkerSize, ...
    'LineWidth', opts.rewardPeakLineWidth);
end


function localDrawCircles(centerDeg, radiusDeg, color, lineStyle, lineWidth)
if isempty(centerDeg) || ~isfinite(radiusDeg) || radiusDeg <= 0
    return
end
theta = linspace(0, 2*pi, 241);
for i = 1:size(centerDeg, 1)
    if any(~isfinite(centerDeg(i, :)))
        continue
    end
    plot(centerDeg(i, 1) + radiusDeg .* cos(theta), ...
        centerDeg(i, 2) + radiusDeg .* sin(theta), ...
        'LineStyle', char(string(lineStyle)), ...
        'Color', color, ...
        'LineWidth', lineWidth);
end
end


function localDrawQueryCircles(query, opts)
if isempty(query) || ~ismember('circleRadiusDeg', query.Properties.VariableNames)
    return
end
centers = [query.xDeg, query.yDeg];
for i = 1:height(query)
    localDrawCircles(centers(i, :), query.circleRadiusDeg(i), opts.queryCircleColor, ...
        opts.queryCircleLineStyle, opts.queryCircleLineWidth);
end
end


function trialList = localResolveTrialList(ex, trialNo)
if ~isfield(ex, 'Trials') || isempty(ex.Trials)
    trialList = [];
    return
end
nTrials = numel(ex.Trials);
if isempty(trialNo)
    if isfield(ex, 'j') && isfinite(localFirstScalar(ex.j)) && localFirstScalar(ex.j) > 1
        lastCompleted = min(nTrials, round(double(localFirstScalar(ex.j))) - 1);
        trialList = 1:lastCompleted;
    else
        trialList = 1:nTrials;
    end
    return
end
if (ischar(trialNo) && strcmpi(trialNo, 'all')) || ...
        (isstring(trialNo) && isscalar(trialNo) && strcmpi(trialNo, "all"))
    trialList = 1:nTrials;
    return
end
if islogical(trialNo)
    if numel(trialNo) ~= nTrials
        error('rewHeat:BadTrialMask', 'Logical trialNo must match numel(ex.Trials).');
    end
    trialList = find(trialNo(:))';
    return
end
trialList = unique(double(trialNo(:)'));
trialList = trialList(isfinite(trialList) & trialList == round(trialList));
trialList = trialList(trialList >= 1 & trialList <= nTrials);
end


function keep = localGoMask(T, tAbs)
keep = true(size(tAbs(:)));
if isfield(T, 'times') && isfield(T.times, 'stimOn') && isfield(T, 'TrialEnd') && ...
        isfinite(T.times.stimOn) && isfinite(T.TrialEnd)
    keep = tAbs(:) >= T.times.stimOn & tAbs(:) <= T.TrialEnd;
end
end


function keep = localOnScreenMask(xPx, yPx, screenRect)
xPx = xPx(:);
yPx = yPx(:);
screenRect = double(screenRect(:)');
if numel(screenRect) < 4
    keep = isfinite(xPx) & isfinite(yPx);
    return
end
keep = isfinite(xPx) & isfinite(yPx) & ...
    xPx >= screenRect(1) & xPx <= screenRect(3) & ...
    yPx >= screenRect(2) & yPx <= screenRect(4);
end


function dtSec = localSampleDtSec(ex, tRel)
tRel = tRel(isfinite(tRel));
dtSec = NaN;
if numel(tRel) >= 2
    d = diff(tRel);
    d = d(isfinite(d) & d > 0);
    if ~isempty(d)
        dtSec = median(d);
    end
end
if ~isfinite(dtSec) || dtSec <= 0
    try
        dtSec = 1 / inferFs(ex);
    catch
        dtSec = NaN;
    end
end
end


function n = localRewardEventCount(T)
n = 0;
if isfield(T, 'times') && isfield(T.times, 'reward') && ~isempty(T.times.reward)
    n = sum(isfinite(T.times.reward(:)));
end
end


function dur = localDeliveredRewardDurationSec(ex, T)
n = localRewardEventCount(T);
durPerEvent = NaN;
if isfield(T, 'RewardSize') && isfinite(localFirstScalar(T.RewardSize))
    durPerEvent = double(localFirstScalar(T.RewardSize));
elseif isfield(ex.exp.CoPs, 'rew') && isfield(ex.exp.CoPs.rew, 'duration') && ...
        isfinite(localFirstScalar(ex.exp.CoPs.rew.duration))
    durPerEvent = double(localFirstScalar(ex.exp.CoPs.rew.duration));
end
if isfinite(durPerEvent)
    dur = n .* durPerEvent;
else
    dur = NaN;
end
end


function [plotBounds, textureBounds, geom] = localPlotGeometryPx(ex, opts)
graph = ex.exp.CoPs.graph;
screenRect = double(ex.setup.screenRect(:)');
if numel(screenRect) < 4
    error('rewHeat:BadScreenRect', 'ex.setup.screenRect must have 4 elements.');
end
if isfield(graph, 'texture_dims') && ~isempty(graph.texture_dims)
    textureDims = double(graph.texture_dims(:)');
else
    textureDims = [320, 320];
end
if numel(textureDims) < 2
    textureDims = [textureDims(1), textureDims(1)];
end
sizeMult = localGetScalarField(graph, 'size_mult', 1);
geom = struct();
geom.screenRect = screenRect;
geom.imgHeight = textureDims(1);
geom.imgWidth = textureDims(2);
geom.drawnTexH = geom.imgHeight * sizeMult;
geom.drawnTexW = geom.imgWidth * sizeMult;
geom.xShift = (screenRect(3) - geom.drawnTexW) / 2;
geom.yShift = (screenRect(4) - geom.drawnTexH) / 2;
textureBounds = struct('xMin', screenRect(1) + geom.xShift, ...
    'xMax', screenRect(1) + geom.xShift + geom.drawnTexW, ...
    'yMin', screenRect(2) + geom.yShift, ...
    'yMax', screenRect(2) + geom.yShift + geom.drawnTexH);
plotBounds = struct('xMin', screenRect(1), 'xMax', screenRect(3), ...
    'yMin', screenRect(2), 'yMax', screenRect(4));
if opts.insideTextureOnly
    plotBounds = textureBounds;
end
end


function ctrNorm = localTrialRewardCenterNorm(ex, T)
ctrNorm = [NaN, NaN];
if isstruct(T) && isfield(T, 'gaussRewardCenterNorm') && numel(T.gaussRewardCenterNorm) >= 2 && ...
        all(isfinite(T.gaussRewardCenterNorm(1:2)))
    ctrNorm = double(T.gaussRewardCenterNorm(1:2));
    return
end
ctrNorm = localRewardCenterNormFromSettings(ex);
end


function scalar = localTrialGaussScalar(ex, T)
scalar = NaN;
if isstruct(T) && isfield(T, 'gauss_scalar') && isfinite(localFirstScalar(T.gauss_scalar))
    scalar = double(localFirstScalar(T.gauss_scalar));
elseif isfield(ex.exp.CoPs, 'ctl') && isfield(ex.exp.CoPs.ctl, 'gauss_scalar') && ...
        isfinite(localFirstScalar(ex.exp.CoPs.ctl.gauss_scalar))
    scalar = double(localFirstScalar(ex.exp.CoPs.ctl.gauss_scalar));
end
if ~isfinite(scalar)
    scalar = 1;
end
end


function ctrNorm = localRewardCenterNormFromSettings(ex)
ctrNorm = [NaN, NaN];
if ~isfield(ex.exp.CoPs, 'rew')
    return
end
rew = ex.exp.CoPs.rew;
if isfield(rew, 'gauss_center_free') && logical(localFirstScalar(rew.gauss_center_free)) && ...
        isfield(rew, 'gauss_center_coords') && numel(rew.gauss_center_coords) >= 2 && ...
        all(isfinite(rew.gauss_center_coords(1:2)))
    ctrNorm = double(rew.gauss_center_coords(1:2));
    return
end
if isfield(rew, 'gauss_center_positions_norm') && ~isempty(rew.gauss_center_positions_norm)
    centers = double(rew.gauss_center_positions_norm);
    idx = 1;
    if isfield(rew, 'gauss_center_idx') && isfinite(localFirstScalar(rew.gauss_center_idx))
        idx = max(1, min(size(centers, 1), round(double(localFirstScalar(rew.gauss_center_idx)))));
    end
    ctrNorm = centers(idx, 1:2);
end
end


function centersPx = localRewardNormToScreenPx(ex, centersNorm)
centersNorm = localFirstPointRows(centersNorm);
[~, ~, geom] = localPlotGeometryPx(ex, struct('insideTextureOnly', true));
centersPx = NaN(size(centersNorm));
if isempty(centersNorm)
    return
end
centersPx(:, 1) = geom.screenRect(1) + geom.xShift + centersNorm(:, 1) .* geom.drawnTexW;
centersPx(:, 2) = geom.screenRect(2) + geom.yShift + centersNorm(:, 2) .* geom.drawnTexH;
end


function sigmaPx = localRewardSigmaPx(ex)
rew = ex.exp.CoPs.rew;
sigmaPx = NaN;
if isfield(rew, 'gauss_sigmaPx') && isfinite(localFirstScalar(rew.gauss_sigmaPx))
    sigmaPx = double(localFirstScalar(rew.gauss_sigmaPx));
    return
end
if isfield(rew, 'gauss_sigma') && isfinite(localFirstScalar(rew.gauss_sigma))
    sigmaVal = double(localFirstScalar(rew.gauss_sigma));
    units = localGetTextField(rew, 'gauss_sigmaUnits', 'px');
    if localIsVisualDegUnits(units)
        sigmaPx = localDegToPx(sigmaVal, ex.setup);
    else
        sigmaPx = sigmaVal;
    end
end
if (~isfinite(sigmaPx) || sigmaPx <= 0) && isfield(rew, 'gauss_sigmaDeg') && ...
        isfinite(localFirstScalar(rew.gauss_sigmaDeg))
    sigmaPx = localDegToPx(double(localFirstScalar(rew.gauss_sigmaDeg)), ex.setup);
end
if ~isfinite(sigmaPx) || sigmaPx <= 0
    error('rewHeat:BadSigma', 'Could not resolve reward Gaussian sigma.');
end
end


function [x0, y0] = localReferenceCenterPx(ex)
if isfield(ex, 'fix') && isfield(ex.fix, 'PCtr') && numel(ex.fix.PCtr) >= 2 && all(isfinite(ex.fix.PCtr(1:2)))
    x0 = double(ex.fix.PCtr(1));
    y0 = double(ex.fix.PCtr(2));
    return
end
rect = double(ex.setup.screenRect);
x0 = mean(rect([1 3]));
y0 = mean(rect([2 4]));
end


function boundsDeg = localBoundsDeg(boundsPx, x0, y0, setup, flipY)
yMin = localPxToDeg(boundsPx.yMin - y0, setup);
yMax = localPxToDeg(boundsPx.yMax - y0, setup);
if flipY
    yVals = sort([-yMin, -yMax]);
else
    yVals = sort([yMin, yMax]);
end
boundsDeg = struct( ...
    'xMin', localPxToDeg(boundsPx.xMin - x0, setup), ...
    'xMax', localPxToDeg(boundsPx.xMax - x0, setup), ...
    'yMin', yVals(1), ...
    'yMax', yVals(2));
end


function edges = localEdges(a, b, binSize)
edges = a:binSize:b;
if numel(edges) < 2 || edges(end) < b
    edges(end+1) = b;
end
end


function centers = localBinCenters(edges)
centers = edges(1:end-1) + diff(edges) ./ 2;
end


function y = localSmooth2(x, sigmaBins)
if sigmaBins <= 0
    y = x;
    return
end
halfWidth = max(1, ceil(3 * sigmaBins));
g = -halfWidth:halfWidth;
k = exp(-(g .^ 2) ./ (2 * sigmaBins .^ 2));
k = k ./ sum(k);
y = conv2(conv2(double(x), k, 'same'), k', 'same');
end


function binIdx = localBinIndex(value, edges)
binIdx = NaN;
if ~isfinite(value) || isempty(edges) || numel(edges) < 2
    return
end
idx = find(value >= edges(1:end-1) & value < edges(2:end), 1, 'first');
if isempty(idx) && value == edges(end)
    idx = numel(edges) - 1;
end
if ~isempty(idx)
    binIdx = idx;
end
end


function mask = localCircleBinMask(xDeg, yDeg, radiusDeg, xCentersDeg, yCentersDeg)
[xGrid, yGrid] = ndgrid(xCentersDeg, yCentersDeg);
mask = hypot(xGrid - xDeg, yGrid - yDeg) <= radiusDeg;
end


function [cmap, colorLimits, schemeUsed] = localResolveColorDisplay(map, opts)
schemeUsed = lower(strtrim(char(string(opts.colorScheme))));
if ~isempty(opts.colormap)
    if isnumeric(opts.colormap)
        cmap = double(opts.colormap);
        if size(cmap, 2) ~= 3 || isempty(cmap)
            error('rewHeat:BadColormap', 'opts.colormap must be an n x 3 RGB array or a colormap name.');
        end
        cmap = max(0, min(1, cmap));
        schemeUsed = 'custom';
    else
        schemeUsed = lower(strtrim(char(string(opts.colormap))));
        cmap = localColormapByName(schemeUsed, opts.nColors);
    end
else
    cmap = localColormapByName(schemeUsed, opts.nColors);
end
colorLimits = localResolveColorLimits(map, opts);
end


function cmap = localColormapByName(scheme, nColors)
scheme = lower(strtrim(char(string(scheme))));
switch scheme
    case 'viridis'
        cmap = localInterpolatedColormap([ ...
            0.27 0.00 0.33; ...
            0.23 0.32 0.55; ...
            0.13 0.57 0.55; ...
            0.37 0.79 0.38; ...
            0.99 0.91 0.14], nColors);
    case {'density', 'fire'}
        cmap = localInterpolatedColormap([ ...
            0.00 0.00 0.00; ...
            0.15 0.05 0.35; ...
            0.70 0.10 0.20; ...
            0.95 0.58 0.10; ...
            1.00 0.96 0.72], nColors);
    case {'hot', 'parula', 'turbo', 'jet', 'gray', 'grey', 'bone', 'copper'}
        if strcmp(scheme, 'grey')
            scheme = 'gray';
        end
        cmap = localBuiltinColormap(scheme, nColors);
    otherwise
        error('rewHeat:BadColorScheme', ...
            'Unknown opts.colorScheme ''%s''. Use viridis, density, hot, parula, turbo, gray, or jet.', scheme);
end
end


function cmap = localBuiltinColormap(name, nColors)
try
    cmap = feval(name, nColors);
catch
    switch lower(name)
        case 'turbo'
            cmap = localBuiltinColormap('parula', nColors);
        case 'parula'
            cmap = localBuiltinColormap('jet', nColors);
        otherwise
            cmap = hot(nColors);
    end
end
cmap = max(0, min(1, double(cmap)));
end


function cmap = localInterpolatedColormap(anchors, nColors)
anchors = double(anchors);
x = linspace(0, 1, size(anchors, 1));
xi = linspace(0, 1, nColors);
cmap = zeros(nColors, 3);
for k = 1:3
    cmap(:, k) = interp1(x, anchors(:, k), xi, 'linear');
end
cmap = max(0, min(1, cmap));
end


function colorLimits = localResolveColorLimits(map, opts)
if ~isempty(opts.colorLimits)
    colorLimits = double(opts.colorLimits(:)');
    colorLimits = colorLimits(isfinite(colorLimits));
    if numel(colorLimits) >= 2
        colorLimits = [min(colorLimits(1:2)), max(colorLimits(1:2))];
        if colorLimits(2) > colorLimits(1)
            return
        end
    end
    error('rewHeat:BadColorLimits', 'opts.colorLimits must contain two increasing finite values.');
end

finiteVals = double(map(isfinite(map)));
if isempty(finiteVals) || strcmp(opts.colorLimitMode, 'none')
    colorLimits = [];
    return
end
colorLimits = prctile(finiteVals, [0, opts.colorLimitPrctile]);
if colorLimits(2) <= colorLimits(1)
    colorLimits = [];
end
end


function xyDeg = localScreenPxToPlotDeg(xyPx, x0, y0, setup, flipY)
xyPx = localFirstPointRows(xyPx);
xyDeg = NaN(size(xyPx));
if isempty(xyPx)
    return
end
xyDeg(:, 1) = localPxToDeg(xyPx(:, 1) - x0, setup);
xyDeg(:, 2) = localPxToDeg(xyPx(:, 2) - y0, setup);
if flipY
    xyDeg(:, 2) = -xyDeg(:, 2);
end
end


function [xPx, yPx] = localPlotDegToScreenPx(xDeg, yDeg, x0, y0, setup, flipY)
xPx = x0 + localDegToPx(xDeg, setup);
if flipY
    yPx = y0 - localDegToPx(yDeg, setup);
else
    yPx = y0 + localDegToPx(yDeg, setup);
end
end


function rows = localUniqueRowsTol(rows, tol)
if isempty(rows)
    return
end
rows = double(rows);
rows = rows(all(isfinite(rows), 2), :);
if isempty(rows)
    return
end
roundedRows = round(rows ./ tol) .* tol;
[~, ia] = unique(roundedRows, 'rows');
rows = rows(sort(ia), :);
end


function rows = localFirstPointRows(value)
rows = double(value);
if isempty(rows)
    rows = NaN(0, 2);
    return
end
if isvector(rows)
    rows = rows(:)';
end
if size(rows, 2) < 2 && size(rows, 1) >= 2
    rows = rows';
end
if size(rows, 2) < 2
    rows = NaN(0, 2);
else
    rows = rows(:, 1:2);
end
end


function deg = localPxToDeg(px, setup)
cm = double(px) .* double(setup.monitorWidth) ./ double(setup.screenRect(3));
deg = rad2deg(atan(cm ./ double(setup.viewingDistance)));
end


function px = localDegToPx(deg, setup)
px = double(setup.viewingDistance) .* tan(deg2rad(double(deg))) .* ...
    double(setup.screenRect(3)) ./ double(setup.monitorWidth);
end


function tf = localIsVisualDegUnits(units)
units = lower(strtrim(char(string(units))));
tf = ismember(units, {'deg', 'degree', 'degrees', 'dva', 'visdeg', 'visualdeg', 'visualdegrees'});
end


function value = localGetScalarField(s, fieldName, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    candidate = double(localFirstScalar(s.(fieldName)));
    if isfinite(candidate)
        value = candidate;
    end
end
end


function value = localGetTextField(s, fieldName, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = char(string(s.(fieldName)));
end
end


function value = getfieldOrEmpty(s, fieldName)
value = [];
if isstruct(s) && isfield(s, fieldName)
    value = s.(fieldName);
end
end


function x = localFirstScalar(x)
if isempty(x)
    x = NaN;
else
    x = x(1);
end
end
