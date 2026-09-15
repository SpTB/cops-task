function out = ccgSacRew(ex, trialNo, opts, varargin)
% ccgSacRew  Cross-correlate saccade velocity with reward-onset impulses.
%
%   out = ccgSacRew(ex)
%   out = ccgSacRew(ex, 1:120)
%   out = ccgSacRew(ex, 'bg')
%   out = ccgSacRew(ex, {'bg','vis'})
%
% Gaze preprocessing and tracking chunks are inherited from ccg.m:
% two-target trials use opts.trackingSource (default hmmFiltered), while
% one-target trials always use their sole target model-free.

if nargin < 2
    trialNo = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
if ischar(opts) || (isstring(opts) && isscalar(opts))
    if ~strcmpi(char(string(opts)), 'all')
        error('ccgSacRew:AxisRemoved', 'The axis selector was removed. ccgSacRew() now always computes both x and y.');
    end
    if ~isempty(varargin)
        opts = varargin{1};
    else
        opts = struct();
    end
elseif ~isstruct(opts)
    error('ccgSacRew:BadOpts', 'Third argument must be opts or the legacy string ''all''.');
end
if ~isstruct(ex) || ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('ccgSacRew:BadInput', 'First input must be an ex struct with Trials.');
end

defaults = struct( ...
    'onlyGoState', true, ...
    'useEyeTime', true, ...
    'lowpassHz', [], ...
    'interpBlinkSec', 0.15, ...
    'ccgWindowSec', [-0.5 2.25], ...
    'rewardKernelSec', 0.05, ...
    'plot', false, ...
    'newFigure', true, ...
    'lineWidth', 1.25, ...
    'aggregateMode', 'chunk', ...
    'colors', [], ...
    'refGroup', 't12bg-1', ...
    'refLineStyle', [], ...
    'refLineWidth', [], ...
    'truncateTrialFromStep', 0, ...
    'timeWindowSec', [], ...
    'speedThreshDegPerSec', 10, ...
    'minAmpDeg', 1, ...
    'minDurSec', 0.008, ...
    'maxDurSec', 5, ...
    'smoothFrames', 5, ...
    'saccadePadSec', 0.02);
opts = localApplyLegacySaccadeAliases(opts);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field) || (isempty(opts.(field)) && ~strcmp(field, 'refGroup'))
        opts.(field) = defaults.(field);
    end
end
opts.setup = ex.setup;

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
        error('ccgSacRew:BadColors', 'opts.colors must be an nGroup x 3 RGB array.');
    end
end

episodes = cell(nGroup, 1);
for g = 1:nGroup
    episodes{g} = localBuildEpisodeTable(ex, trialGroups{g}, g, opts);
end
allEpisodes = vertcat(episodes{:});

groupOut = cell(nGroup, 1);
lagSec = [];
if ~isempty(allEpisodes) && ismember('group', allEpisodes.Properties.VariableNames)
    for g = 1:nGroup
        groupOut{g} = localAggregateEpisodes(allEpisodes(allEpisodes.group == g, :), opts);
        groupOut{g}.groupLabel = groupLabels(g);
        if isempty(lagSec)
            lagSec = groupOut{g}.lagSec;
        end
    end
else
    for g = 1:nGroup
        groupOut{g} = localAggregateEpisodes(table(), opts);
        groupOut{g}.groupLabel = groupLabels(g);
    end
end
refGroupOut = {};
refInfo = struct('enabled', false);
if opts.plot
    [refGroupOut, refInfo] = localBuildReferenceGroupOut(ex, trialGroups, groupLabels, opts);
end

if opts.plot
    if opts.newFigure
        figure;
    end
    if plotFacetSpec.enabled
        tiledlayout(plotFacetSpec.nRows, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
        for iRow = 1:plotFacetSpec.nRows
            nexttile;
            localPlotGroups(lagSec, groupOut, 'x', opts, plotFacetSpec.rowGroupIdx{iRow}, ...
                plotFacetSpec.lineLabels, plotFacetSpec.rowLabels(iRow), refGroupOut);
            nexttile;
            localPlotGroups(lagSec, groupOut, 'y', opts, plotFacetSpec.rowGroupIdx{iRow}, ...
                plotFacetSpec.lineLabels, plotFacetSpec.rowLabels(iRow), refGroupOut);
        end
    else
        tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
        nexttile;
        localPlotGroups(lagSec, groupOut, 'x', opts, [], {}, "", refGroupOut);
        nexttile;
        localPlotGroups(lagSec, groupOut, 'y', opts, [], {}, "", refGroupOut);
    end
    sgtitle(sprintf('Saccade-Reward CCG (%d group%s)', nGroup, localPlural(nGroup)), 'Interpreter', 'none');
end

out = struct();
out.episodes = allEpisodes;
out.trials = localFlattenTrialGroups(trialGroups);
out.trialGroups = trialGroups;
out.groupLabels = groupLabels;
out.axisName = 'all';
out.lagSec = lagSec;
out.aggregateMode = char(string(opts.aggregateMode));
out.groups = groupOut;
out.refGroup = opts.refGroup;
out.refInfo = refInfo;
out.refGroups = refGroupOut;
end


function T = localBuildEpisodeTable(ex, trialList, groupNo, opts)
T = buildCcgTrackingEpisodes(ex, trialList, groupNo, opts);
if isempty(T)
    return
end
T.rewardImpulse = cell(height(T), 1);
for i = 1:height(T)
    trialNo = double(T.trial(i));
    tRel = double(T.tRelSec{i}(:));
    rewardImpulse = localRewardImpulseTrain(ex.Trials(trialNo), tRel);
    rewardImpulse = localSmoothRewardImpulseTrain( ...
        rewardImpulse, double(T.dtSec(i)), opts.rewardKernelSec);
    T.rewardImpulse{i} = rewardImpulse(:)';
end
end


function rewardImpulse = localRewardImpulseTrain(T, tRel)
rewardImpulse = zeros(size(tRel));
if ~isfield(T, 'times') || ~isfield(T.times, 'reward') || isempty(T.times.reward)
    return
end
rewardTimes = T.times.reward(:);
rewardTimes = rewardTimes(isfinite(rewardTimes));
if isempty(rewardTimes)
    return
end
if isfield(T, 'TrialStart') && isfinite(T.TrialStart)
    rewardTimes = rewardTimes - T.TrialStart;
end
for i = 1:numel(rewardTimes)
    [~, idx] = min(abs(double(tRel) - double(rewardTimes(i))));
    if ~isempty(idx) && isfinite(idx)
        rewardImpulse(idx) = rewardImpulse(idx) + 1;
    end
end
end


function rewardImpulse = localSmoothRewardImpulseTrain(rewardImpulse, dtSec, kernelSec)
rewardImpulse = double(rewardImpulse(:));
kernelSec = double(localFirstScalar(kernelSec));
if ~isfinite(kernelSec) || kernelSec <= 0 || ~isfinite(dtSec) || dtSec <= 0
    return
end
sigmaFrames = kernelSec / dtSec;
halfWidth = max(1, ceil(4 * sigmaFrames));
x = (-halfWidth:halfWidth)';
k = exp(-0.5 * (x ./ sigmaFrames).^2);
k = k ./ sum(k);
rewardImpulse = conv(rewardImpulse, k, 'same');
end


function group = localAggregateEpisodes(episodes, opts)
group = struct('trials', [], 'lagSec', [], 'ccgX', [], 'ccgY', [], 'meanX', [], 'meanY', [], ...
    'aggregateX', [], 'aggregateY', [], 'nChunksX', [], 'nChunksY', []);
if isempty(episodes)
    return
end

trialIds = unique(double(episodes.trial(:)'));
groupDtSec = localCommonDtSec(episodes.dtSec);
[group.ccgX, lagSec] = localPerTrialCorrMatrix(episodes, trialIds, 'x', opts.ccgWindowSec, groupDtSec, opts);
[group.ccgY, ~] = localPerTrialCorrMatrix(episodes, trialIds, 'y', opts.ccgWindowSec, groupDtSec, opts);
group.trials = trialIds;
group.lagSec = lagSec;
group.meanX = mean(group.ccgX, 1, 'omitnan');
group.meanY = mean(group.ccgY, 1, 'omitnan');
[group.nChunksX, group.nChunksY] = localChunkCountsAcrossEpisodes(episodes, opts, groupDtSec);
[group.aggregateX, group.aggregateY] = localAggregateAcrossEpisodes(episodes, trialIds, opts, groupDtSec);
end


function [M, lagSec] = localPerTrialCorrMatrix(episodes, trialIds, axisName, ccgWindowSec, commonDtSec, opts)
lagSec = [];
M = NaN(numel(trialIds), 0);
rows = cell(numel(trialIds), 1);
for i = 1:numel(trialIds)
    E = episodes(double(episodes.trial) == trialIds(i), :);
    rows{i} = localAggregateChunksForTrial(E, axisName, ccgWindowSec, commonDtSec, opts);
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
        M(i,:) = rows{i}.corr(:)';
    end
end
end


function row = localAggregateChunksForTrial(E, axisName, ccgWindowSec, commonDtSec, opts)
row = struct('lagSec', NaN(0,1), 'corr', NaN(0,1), 'accum', NaN(0,1), ...
    'weightSum', NaN(0,1), 'nChunks', NaN(0,1));
if isempty(E)
    return
end
if nargin < 4 || ~isfinite(commonDtSec) || commonDtSec <= 0
    commonDtSec = localCommonDtSec(E.dtSec);
end
for i = 1:height(E)
    switch axisName
        case 'x'
            chunk = localChunkCorrFromVectors(E.gazeX{i}, E.gazeY{i}, E.rewardImpulse{i}, commonDtSec, ccgWindowSec, opts);
        case 'y'
            chunk = localChunkCorrFromVectors(E.gazeY{i}, E.gazeX{i}, E.rewardImpulse{i}, commonDtSec, ccgWindowSec, opts);
    end
    if isempty(row.lagSec) && ~isempty(chunk.lagSec)
        row.lagSec = chunk.lagSec;
        row.accum = zeros(size(chunk.accum));
        row.weightSum = zeros(size(chunk.accum));
        row.nChunks = zeros(size(chunk.accum));
    end
    if isempty(chunk.accum) || ~any(chunk.weightSum > 0)
        continue
    end
    row.accum = row.accum + chunk.accum;
    row.weightSum = row.weightSum + chunk.weightSum;
    row.nChunks = row.nChunks + chunk.nChunks;
end
row.corr = localSafeWeightedMean(row.accum, row.weightSum);
end


function chunk = localChunkCorrFromVectors(gazePos, gazePosOther, rewardImpulse, dtSec, ccgWindowSec, opts)
chunk = struct('lagSec', NaN(0,1), 'corr', NaN(0,1), 'accum', NaN(0,1), ...
    'weightSum', NaN(0,1), 'nChunks', NaN(0,1));
gazePos = double(gazePos(:));
gazePosOther = double(gazePosOther(:));
rewardImpulse = double(rewardImpulse(:));
if numel(gazePos) < 4 || numel(gazePosOther) ~= numel(gazePos) || numel(rewardImpulse) ~= numel(gazePos) || ...
        ~isfinite(dtSec) || dtSec <= 0
    return
end

validMask = isfinite(gazePos) & isfinite(rewardImpulse);
if nnz(validMask) < 4
    return
end

maxLagSamples = max(1, round(max(abs(ccgWindowSec)) / dtSec));
lagsAll = (-maxLagSamples:maxLagSamples)';
lagSecAll = lagsAll .* dtSec;
keep = lagSecAll >= min(ccgWindowSec) & lagSecAll <= max(ccgWindowSec);
chunk.lagSec = lagSecAll(keep);
chunk.accum = zeros(sum(keep), 1);
chunk.weightSum = zeros(sum(keep), 1);
chunk.nChunks = zeros(sum(keep), 1);

[saccadeStarts, saccadeStops] = localDetectSaccadeMask(gazePos, gazePosOther, dtSec, opts.setup, opts);
if isempty(saccadeStarts)
    return
end
saccadeMask = false(size(gazePos));
for i = 1:numel(saccadeStarts)
    saccadeMask(saccadeStarts(i):saccadeStops(i)) = true;
end

eyeVel = [0; diff(gazePos)] ./ dtSec;
validMask = validMask & isfinite(eyeVel);
if nnz(validMask) < 4
    return
end

idx = find(validMask);
runBreak = [true; diff(idx) > 1];
runStarts = find(runBreak);
runEnds = [runStarts(2:end)-1; numel(idx)];
for i = 1:numel(runStarts)
    ii = idx(runStarts(i):runEnds(i));
    if numel(ii) < 4
        continue
    end
    saccVel = zeros(numel(ii), 1);
    localMask = saccadeMask(ii);
    saccVel(localMask) = eyeVel(ii(localMask));
    rew = rewardImpulse(ii);
    xc = xcorr(saccVel, rew, maxLagSamples, 'coeff');
    xc = double(xc(keep));
    finiteMask = isfinite(xc);
    if ~any(finiteMask)
        continue
    end
    w = numel(ii);
    chunk.accum(finiteMask) = chunk.accum(finiteMask) + w .* xc(finiteMask);
    chunk.weightSum(finiteMask) = chunk.weightSum(finiteMask) + w;
    chunk.nChunks(finiteMask) = chunk.nChunks(finiteMask) + 1;
end
chunk.corr = localSafeWeightedMean(chunk.accum, chunk.weightSum);
end


function [saccadeStarts, saccadeStops] = localDetectSaccadeMask(gazePosX, gazePosY, dtSec, setup, opts)
gazePosX = double(gazePosX(:));
gazePosY = double(gazePosY(:));
if numel(gazePosX) < 2 || numel(gazePosY) ~= numel(gazePosX) || ~isfinite(dtSec) || dtSec <= 0
    saccadeStarts = zeros(0,1);
    saccadeStops = zeros(0,1);
    return
end
[saccadeStarts, saccadeStops] = detectTrackingSaccadesCoPs( ...
    gazePosX, gazePosY, dtSec, setup, localBuildSaccadeParams(dtSec, opts));
if isempty(saccadeStarts)
    return
end
padFrames = localResolvePadFrames(dtSec, opts.saccadePadSec);
saccadeStarts = max(1, saccadeStarts - padFrames);
saccadeStops = min(numel(gazePosX), saccadeStops + padFrames);
end


function params = localBuildSaccadeParams(dtSec, opts)
params = struct();
params.preSaccadeWindowFrames = 3;
params.speedThreshDegPerSec = double(localFirstScalar(opts.speedThreshDegPerSec));
if ~isfinite(params.speedThreshDegPerSec) || params.speedThreshDegPerSec <= 0
    params.speedThreshDegPerSec = 30;
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


function [aggX, aggY] = localAggregateAcrossEpisodes(episodes, trialIds, opts, commonDtSec)
aggregateMode = validatestring(char(string(opts.aggregateMode)), {'chunk', 'trial'});
switch aggregateMode
    case 'trial'
        [M, ~] = localPerTrialCorrMatrix(episodes, trialIds, 'x', opts.ccgWindowSec, commonDtSec, opts);
        aggX = mean(M, 1, 'omitnan');
        [M, ~] = localPerTrialCorrMatrix(episodes, trialIds, 'y', opts.ccgWindowSec, commonDtSec, opts);
        aggY = mean(M, 1, 'omitnan');
    case 'chunk'
        row = localAggregateChunksForTrial(episodes, 'x', opts.ccgWindowSec, commonDtSec, opts);
        aggX = row.corr(:)';
        row = localAggregateChunksForTrial(episodes, 'y', opts.ccgWindowSec, commonDtSec, opts);
        aggY = row.corr(:)';
end
end


function [nChunksX, nChunksY] = localChunkCountsAcrossEpisodes(episodes, opts, commonDtSec)
row = localAggregateChunksForTrial(episodes, 'x', opts.ccgWindowSec, commonDtSec, opts);
nChunksX = row.nChunks(:)';
row = localAggregateChunksForTrial(episodes, 'y', opts.ccgWindowSec, commonDtSec, opts);
nChunksY = row.nChunks(:)';
end


function y = localSafeWeightedMean(accum, weightSum)
y = NaN(size(accum));
valid = isfinite(weightSum) & (weightSum > 0);
y(valid) = accum(valid) ./ weightSum(valid);
end


function [refGroupOut, refInfo] = localBuildReferenceGroupOut(ex, trialGroups, groupLabels, opts)
refGroupOut = {};
refInfo = struct('enabled', false);
if ~isfield(opts, 'refGroup')
    return
end
[refTrialGroups, refInfo] = refGroupTrialGroupsCoPs(ex, trialGroups, opts.refGroup);
if ~isfield(refInfo, 'enabled') || ~isequal(refInfo.enabled, true) || ~any(cellfun(@(x) ~isempty(x), refTrialGroups(:)))
    return
end

nGroup = numel(trialGroups);
nRef = size(refTrialGroups, 2);
refGroupOut = cell(nGroup, nRef);
refOpts = opts;
refOpts.trackingSource = 'model-free';
for r = 1:nRef
    refEpisodes = cell(nGroup, 1);
    for g = 1:nGroup
        if isempty(refTrialGroups{g, r})
            refEpisodes{g} = table();
        else
            refEpisodes{g} = localBuildEpisodeTable(ex, refTrialGroups{g, r}, g, refOpts);
        end
    end
    refAllEpisodes = vertcatNonEmptyTablesCoPs(refEpisodes);

    for g = 1:nGroup
        if ~isempty(refAllEpisodes) && ismember('group', refAllEpisodes.Properties.VariableNames)
            refGroupOut{g, r} = localAggregateEpisodes(refAllEpisodes(refAllEpisodes.group == g, :), opts);
        else
            refGroupOut{g, r} = localAggregateEpisodes(table(), opts);
        end
        refGroupOut{g, r}.groupLabel = localReferenceGroupLabel(refInfo.labels(r), groupLabels(g));
        refGroupOut{g, r}.refIndex = r;
        refGroupOut{g, r}.refTargetNum = localRefTargetNum(refInfo, r);
    end
end
end


function targetNum = localRefTargetNum(refInfo, idx)
targetNum = NaN;
if isstruct(refInfo) && isfield(refInfo, 'targetNums') && numel(refInfo.targetNums) >= idx
    targetNum = double(refInfo.targetNums(idx));
end
end


function label = localReferenceGroupLabel(refLabel, groupLabel)
refLabel = strtrim(string(refLabel));
groupLabel = strtrim(string(groupLabel));
if strlength(refLabel) == 0 || ismissing(refLabel)
    refLabel = "ref";
end
if strlength(groupLabel) == 0 || ismissing(groupLabel) || strcmpi(groupLabel, "all")
    label = refLabel;
else
    label = refLabel + " | " + groupLabel;
end
end


function localPlotGroups(lagSec, groupOut, axisName, opts, groupIdx, legendLabelsOverride, rowLabel, refGroupOut)
if nargin < 5 || isempty(groupIdx)
    groupIdx = 1:numel(groupOut);
end
if nargin < 6
    legendLabelsOverride = {};
end
if nargin < 7
    rowLabel = "";
end
if nargin < 8
    refGroupOut = {};
end
hold on
lagSec = double(lagSec(:));
nRef = 0;
if ~isempty(refGroupOut)
    nRef = size(refGroupOut, 2);
end
nLegendSlots = numel(groupIdx) * (1 + nRef);
legendLabels = cell(nLegendSlots, 1);
plotted = false(nLegendSlots, 1);
plotHandles = gobjects(nLegendSlots, 1);
plotCount = 0;
for j = 1:numel(groupIdx)
    g = groupIdx(j);
    switch axisName
        case 'x'
            xc = groupOut{g}.aggregateX;
            titleText = 'X Saccade-Reward CCG';
        case 'y'
            xc = groupOut{g}.aggregateY;
            titleText = 'Y Saccade-Reward CCG';
    end
    xc = double(xc(:));
    if isempty(lagSec) || isempty(xc) || numel(lagSec) ~= numel(xc)
        continue
    end
    plotCount = plotCount + 1;
    plotHandles(plotCount) = plot(lagSec, xc, 'Color', opts.colors(g, :), 'LineWidth', opts.lineWidth);
    if ~isempty(legendLabelsOverride) && numel(legendLabelsOverride) >= j
        label = string(legendLabelsOverride{j});
    else
        label = string(groupOut{g}.groupLabel);
        if strlength(strtrim(label)) == 0 || ismissing(label)
            label = "group " + string(g);
        end
    end
    legendLabels{plotCount} = sprintf('%s (n=%d)', char(label), numel(groupOut{g}.trials));
    plotted(plotCount) = true;
end
for r = 1:nRef
    for j = 1:numel(groupIdx)
        g = groupIdx(j);
        if isempty(refGroupOut) || size(refGroupOut, 1) < g || isempty(refGroupOut{g, r})
            continue
        end
        switch axisName
            case 'x'
                xc = refGroupOut{g, r}.aggregateX;
            case 'y'
                xc = refGroupOut{g, r}.aggregateY;
        end
        xc = double(xc(:));
        if isempty(lagSec) || isempty(xc) || numel(lagSec) ~= numel(xc) || ~any(isfinite(xc))
            continue
        end
        plotCount = plotCount + 1;
        plotHandles(plotCount) = plot(lagSec, xc, ...
            'Color', localReferenceColor(opts.colors(g, :), r, nRef), ...
            'LineStyle', localReferenceLineStyle(opts, refGroupOut{g, r}), ...
            'LineWidth', localReferenceLineWidth(opts));
        label = string(refGroupOut{g, r}.groupLabel);
        if strlength(strtrim(label)) == 0 || ismissing(label)
            label = "reference group " + string(g);
        end
        legendLabels{plotCount} = sprintf('%s (n=%d)', char(label), numel(refGroupOut{g, r}.trials));
        plotted(plotCount) = true;
    end
end
xline(0, ':');
yline(0, ':');
xlim([min(opts.ccgWindowSec) max(opts.ccgWindowSec)]);
xlabel('Lag (s)');
ylabel('xcorr');
if strlength(strtrim(string(rowLabel))) > 0
    titleText = sprintf('%s | %s', titleText, char(string(rowLabel)));
end
title(titleText, 'Interpreter', 'none');
box off
if nnz(plotted) > 1
    legend(plotHandles(plotted), legendLabels(plotted), 'Location', 'best', 'Interpreter', 'none');
end
end


function color = localReferenceColor(baseColor, refIdx, nRef)
baseColor = double(baseColor(:)');
if numel(baseColor) ~= 3 || any(~isfinite(baseColor))
    baseColor = [0 0 0];
end
baseColor = min(max(baseColor, 0), 1);
if nRef <= 1
    shade = 0.45;
elseif refIdx == 1
    shade = 0.25;
elseif refIdx == 2
    shade = -0.35;
else
    shade = 0.25 - (refIdx - 1) .* (0.8 ./ max(1, nRef - 1));
end
if shade >= 0
    color = baseColor + (1 - baseColor) .* shade;
else
    color = baseColor .* (1 + shade);
end
color = min(max(color, 0), 1);
end


function style = localReferenceLineStyle(opts, refGroup)
if isstruct(opts) && isfield(opts, 'refLineStyle') && ~isempty(opts.refLineStyle)
    style = char(string(opts.refLineStyle));
    return
end
targetNum = NaN;
if isstruct(refGroup) && isfield(refGroup, 'refTargetNum') && ~isempty(refGroup.refTargetNum)
    targetNum = double(refGroup.refTargetNum);
end
if isfinite(targetNum) && abs(targetNum - 1) < 1e-9
    style = ':';
else
    style = '--';
end
end


function lineWidth = localReferenceLineWidth(opts)
lineWidth = opts.lineWidth;
if isstruct(opts) && isfield(opts, 'refLineWidth') && ~isempty(opts.refLineWidth)
    candidate = double(opts.refLineWidth);
    candidate = candidate(1);
    if isfinite(candidate) && candidate > 0
        lineWidth = candidate;
    end
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
count1 = localGroupingLevelCount(code1, ex);
count2 = localGroupingLevelCount(code2, ex);
if ~(isfinite(count1) && isfinite(count2) && count1 >= 1 && count2 >= 1 && count1 * count2 == nGroup)
    return
end
labels1 = localGroupingLevelLabels(code1, ex);
labels2 = localGroupingLevelLabels(code2, ex);
if numel(labels1) ~= count1 || numel(labels2) ~= count2
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


function n = localGroupingLevelCount(code, ex)
labels = localGroupingLevelLabels(code, ex);
n = numel(labels);
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
            tmp = localBuildGroupLabels({code}, groups(i), ex);
            labels(i) = tmp(1);
        end
    otherwise
        labels = strings(0, 1);
end
labels = labels(:);
if ~isempty(labels)
    prefix = code + ": ";
    for i = 1:numel(labels)
        labels(i) = strip(localRemovePrefix(char(labels(i)), prefix));
    end
end
end


function out = localRemovePrefix(in, prefix)
if startsWith(in, prefix)
    out = extractAfter(string(in), strlength(prefix));
else
    out = string(in);
end
end


function groupLabels = localBuildGroupLabels(trialNo, trialGroups, ex)
nGroup = numel(trialGroups);
groupLabels = strings(nGroup, 1);
if isempty(trialGroups)
    return
end
if isempty(trialNo)
    groupLabels(:) = "all";
    return
end
if ischar(trialNo) || (isstring(trialNo) && isscalar(trialNo))
    codeList = {char(string(trialNo))};
elseif localIsNamedCodeCell(trialNo)
    codeList = cellfun(@(x) char(string(x)), trialNo, 'UniformOutput', false);
else
    for i = 1:nGroup
        groupLabels(i) = "group " + string(i);
    end
    return
end
for i = 1:nGroup
    tr = trialGroups{i}(1);
    T = ex.Trials(tr);
    parts = strings(0,1);
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
        end
    end
    groupLabels(i) = strjoin(parts, " | ");
end
end


function trialGroups = localNormalizeTrialGroups(trialNo, ex)
if isempty(trialNo)
    trialGroups = {1:numel(ex.Trials)};
    return
end
if ischar(trialNo) || (isstring(trialNo) && isscalar(trialNo))
    code = char(string(trialNo));
    trialGroups = localResolveNamedTrialGroups(code, ex);
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
    if strlength(candidate) > 0
        imageName = candidate;
        return
    end
end
if isfield(ex, 'stim') && isstruct(ex.stim) && isfield(ex.stim, 'seq') && numel(ex.stim.seq) >= trialIdx
    candidate = localBasenameString(string(ex.stim.seq{trialIdx}));
    if strlength(candidate) > 0
        imageName = candidate;
    end
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
    error('ccgSacRew:NamedGroupEmpty', ...
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
        error('ccgSacRew:UnknownTrialCode', ...
            'Unknown trial grouping code ''%s''. Currently supported: ''all'', ''bg'', ''vis'', ''tnum'', ''im''.', code);
end
end


function trialGroups = localResolveNamedTrialGroupsFromEx(code, ex)
switch code
    case 'bg'
        values = NaN(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            T = ex.Trials(j);
            if isfield(T, 'background_noise_lvl') && isnumeric(T.background_noise_lvl) && isscalar(T.background_noise_lvl)
                values(j) = double(T.background_noise_lvl);
            end
        end
        levels = unique(values(isfinite(values)));
        if isempty(levels)
            error('ccgSacRew:NamedGroupEmpty', 'No trials had finite background_noise_lvl values.');
        end
        trialGroups = cell(numel(levels), 1);
        for i = 1:numel(levels)
            trialGroups{i} = find(values == levels(i));
        end
    case 'vis'
        values = NaN(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            T = ex.Trials(j);
            if isfield(T, 'target_visibility') && isnumeric(T.target_visibility) && isscalar(T.target_visibility)
                values(j) = double(T.target_visibility);
            end
        end
        levels = unique(values(isfinite(values)));
        if isempty(levels)
            error('ccgSacRew:NamedGroupEmpty', 'No trials had finite target_visibility values.');
        end
        trialGroups = cell(numel(levels), 1);
        for i = 1:numel(levels)
            trialGroups{i} = find(values == levels(i));
        end
    case 'tnum'
        values = NaN(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            T = ex.Trials(j);
            if isfield(T, 'target_num') && isnumeric(T.target_num) && isscalar(T.target_num)
                values(j) = double(T.target_num);
            end
        end
        levels = unique(values(isfinite(values)));
        if isempty(levels)
            error('ccgSacRew:NamedGroupEmpty', 'No trials had finite target_num values.');
        end
        trialGroups = cell(numel(levels), 1);
        for i = 1:numel(levels)
            trialGroups{i} = find(values == levels(i));
        end
    case 'im'
        values = strings(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            T = ex.Trials(j);
            if isfield(T, 'imageName') && (ischar(T.imageName) || isstring(T.imageName))
                candidate = string(T.imageName);
                if strlength(strtrim(candidate)) > 0
                    values(j) = candidate;
                    continue
                end
            end
            if isfield(T, 'stimPath') && (ischar(T.stimPath) || isstring(T.stimPath))
                candidate = localBasenameString(string(T.stimPath));
                if strlength(candidate) > 0
                    values(j) = candidate;
                    continue
                end
            end
            if isfield(ex, 'stim') && isstruct(ex.stim) && isfield(ex.stim, 'seq') && numel(ex.stim.seq) >= j
                candidate = localBasenameString(string(ex.stim.seq{j}));
                if strlength(candidate) > 0
                    values(j) = candidate;
                end
            end
        end
        levels = unique(values(values ~= "" & ~ismissing(values)), 'stable');
        if isempty(levels)
            error('ccgSacRew:NamedGroupEmpty', 'No trials had finite imageName values.');
        end
        trialGroups = cell(numel(levels), 1);
        for i = 1:numel(levels)
            trialGroups{i} = find(values == levels(i));
        end
end
end


function name = localBasenameString(pathStr)
name = string(missing);
if strlength(pathStr) == 0 || ismissing(pathStr)
    return
end
[~, stem, ext] = fileparts(char(pathStr));
candidate = string([stem ext]);
if strlength(strtrim(candidate)) > 0
    name = candidate;
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


function trialVec = localValidateTrialVector(trialVec, nTrials)
trialVec = unique(double(trialVec(:)'));
if isempty(trialVec) || any(~isfinite(trialVec)) || any(trialVec ~= round(trialVec))
    error('ccgSacRew:BadTrialNo', 'Each trial selection must contain finite integer trial indices.');
end
trialVec = trialVec(trialVec >= 1 & trialVec <= nTrials);
if isempty(trialVec)
    error('ccgSacRew:BadTrialNo', 'No requested trials were within the valid range 1:%d.', nTrials);
end
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


function suffix = localPlural(n)
if n == 1
    suffix = '';
else
    suffix = 's';
end
end


function dtSec = localResolveSampleDt(tRelSec, fallbackDtSec)
dtSec = NaN;
if numel(tRelSec) >= 2
    dtCandidates = diff(double(tRelSec(:)));
    dtCandidates = dtCandidates(isfinite(dtCandidates) & dtCandidates > 0);
    if ~isempty(dtCandidates)
        dtSec = median(dtCandidates, 'omitnan');
        return
    end
end
dtSec = fallbackDtSec;
end


function dtSec = localCommonDtSec(dtValues)
dtValues = double(dtValues(:));
dtValues = dtValues(isfinite(dtValues) & dtValues > 0);
if isempty(dtValues)
    dtSec = NaN;
else
    dtSec = median(dtValues, 'omitnan');
end
end


function padFrames = localResolvePadFrames(dtSec, padSec)
padSec = double(localFirstScalar(padSec));
if ~isfinite(padSec) || padSec < 0 || ~isfinite(dtSec) || dtSec <= 0
    padFrames = 0;
else
    padFrames = round(padSec / dtSec);
end
padFrames = max(0, padFrames);
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
    error('ccgSacRew:BadTimeWindow', ...
        'opts.timeWindowSec must be empty or a finite 1x2 increasing vector.');
end
end
