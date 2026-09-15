function out = plotCCG2(in, trialNo, opts, varargin)
% plotCCG2  Plot a 2D velocity CCG using gaze-target velocity dot products.
%
%   out = plotCCG2(ex, [])
%   out = plotCCG2(ex, 'bg', opts)
%   out = plotCCG2(ex, {'bg','vis'}, opts)
%
% The underlying chunks, grouping, preprocessing, target selection, and
% shuffling are inherited from ccg(). The plotted value is a vector
% correlation:
%
%   dot([vx_gaze vy_gaze], [vx_target vy_target]) /
%   (||v_gaze|| * ||v_target||)

if nargin < 2
    trialNo = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
if ischar(opts) || (isstring(opts) && isscalar(opts))
    if ~strcmpi(char(string(opts)), 'all')
        error('plotCCG2:AxisRemoved', 'The axis selector was removed. plotCCG2() always plots the 2D vector CCG.');
    end
    if ~isempty(varargin)
        opts = varargin{1};
    else
        opts = struct();
    end
elseif ~isstruct(opts)
    error('plotCCG2:BadOpts', 'Third argument must be opts or the legacy string ''all''.');
end

ccgOpts = opts;
ccgOpts.plot = false;
raw = ccg(in, trialNo, ccgOpts);
out = localAddVectorCcg(raw, ccgOpts);
out.axisName = '2d';
out.vectorMethod = 'velocityDotProduct';
[refOut, refInfo] = localBuildReferenceVectorOut(in, out, ccgOpts);
out.refGroup = localGetField(ccgOpts, 'refGroup', 't12bg-1');
out.refInfo = refInfo;
if ~isempty(refOut)
    out.refGroups = refOut.groups;
else
    out.refGroups = {};
end

plotOpts = localPlotDefaults(opts, out, trialNo, in);
if logical(plotOpts.plot)
    if plotOpts.newFigure
        figure;
    end
    localPlotVectorCcg(out, trialNo, plotOpts, in, refOut);
end
end


function out = localAddVectorCcg(out, opts)
if ~isfield(out, 'groups') || isempty(out.groups)
    return
end
if ~isfield(out, 'episodes') || isempty(out.episodes)
    for g = 1:numel(out.groups)
        out.groups{g}.ccg2D = NaN(0, 0);
        out.groups{g}.mean2D = NaN(1, 0);
        out.groups{g}.aggregate2D = NaN(1, 0);
        out.groups{g}.nChunks2D = NaN(1, 0);
        out.groups{g}.support2D = NaN(1, 0);
        out.groups{g}.accum2D = NaN(1, 0);
        out.groups{g}.weightSum2D = NaN(1, 0);
        out.groups{g}.chunkCcg2D = NaN(0, 0);
        out.groups{g}.chunkWeight2D = NaN(0, 0);
    end
    return
end

demeanMode = localResolveDemeanModeLocal(localGetField(opts, 'demeanMode', localGetField(out, 'demeanMode', 'chunk')));
aggregateMode = validatestring(char(string(localGetField(opts, 'aggregateMode', localGetField(out, 'aggregateMode', 'chunk')))), {'chunk', 'trial'});

for g = 1:numel(out.groups)
    group = out.groups{g};
    E = out.episodes(double(out.episodes.group) == g, :);
    lagSec = localGroupLagSec(out, group);
    stepAmpMinPx = localGetField(group, 'stepAmpMinPx', NaN);
    stepAmpMaxPx = localGetField(group, 'stepAmpMaxPx', NaN);
    group = localComputeVectorGroup(E, group, lagSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, aggregateMode);
    out.groups{g} = group;
end
end


function group = localComputeVectorGroup(E, group, lagSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, aggregateMode)
group.ccg2D = NaN(0, numel(lagSec));
group.mean2D = NaN(1, numel(lagSec));
group.aggregate2D = NaN(1, numel(lagSec));
group.nChunks2D = NaN(1, numel(lagSec));
group.support2D = NaN(1, numel(lagSec));
group.accum2D = NaN(1, numel(lagSec));
group.weightSum2D = NaN(1, numel(lagSec));
group.chunkCcg2D = NaN(0, numel(lagSec));
group.chunkWeight2D = NaN(0, numel(lagSec));
if isempty(E) || isempty(lagSec)
    return
end

trialIds = unique(double(E.trial(:)'));
switch aggregateMode
    case 'trial'
        M = NaN(numel(trialIds), numel(lagSec));
        for i = 1:numel(trialIds)
            Ei = E(double(E.trial) == trialIds(i), :);
            row = localAggregateVectorChunks(Ei, lagSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, localDefaultVectorMeans());
            if numel(row.corr) == numel(lagSec)
                M(i, :) = row.corr(:)';
            end
        end
        group.ccg2D = M;
        group.mean2D = mean(M, 1, 'omitnan');
        group.aggregate2D = group.mean2D;
        supportRow = localAggregateVectorChunks(E, lagSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, localDefaultVectorMeans());
        group.nChunks2D = supportRow.nChunks(:)';
        group.support2D = supportRow.support(:)';
        group.accum2D = supportRow.accum(:)';
        group.weightSum2D = supportRow.weightSum(:)';
        group.chunkCcg2D = supportRow.chunkCorrRows;
        group.chunkWeight2D = supportRow.chunkWeightRows;
    case 'chunk'
        globalMeans = localDefaultVectorMeans();
        if strcmp(demeanMode, 'global')
            globalMeans = localVectorMeansForEpisodes(E, stepAmpMinPx, stepAmpMaxPx, NaN);
        end
        row = localAggregateVectorChunks(E, lagSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans);
        group.aggregate2D = row.corr(:)';
        group.nChunks2D = row.nChunks(:)';
        group.support2D = row.support(:)';
        group.accum2D = row.accum(:)';
        group.weightSum2D = row.weightSum(:)';
        group.chunkCcg2D = row.chunkCorrRows;
        group.chunkWeight2D = row.chunkWeightRows;
        group.ccg2D = NaN(numel(trialIds), numel(lagSec));
        for i = 1:numel(trialIds)
            Ei = E(double(E.trial) == trialIds(i), :);
            rowi = localAggregateVectorChunks(Ei, lagSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans);
            if numel(rowi.corr) == numel(lagSec)
                group.ccg2D(i, :) = rowi.corr(:)';
            end
        end
        group.mean2D = mean(group.ccg2D, 1, 'omitnan');
end
end


function row = localAggregateVectorChunks(E, lagSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans)
row = localEmptyVectorRow(lagSec);
if isempty(E) || isempty(lagSec)
    return
end
for i = 1:height(E)
    trialMeans = localDefaultVectorMeans();
    if strcmp(demeanMode, 'trial')
        trialMeans = localVectorMeansForEpisodes(E, stepAmpMinPx, stepAmpMaxPx, double(E.trial(i)));
    end
    chunk = localVectorCorrFromPositions( ...
        E.gazeX{i}, E.gazeY{i}, E.targetX{i}, E.targetY{i}, ...
        double(E.dtStepSec(i)), lagSec, stepAmpMinPx, stepAmpMaxPx, ...
        demeanMode, trialMeans, globalMeans);
    if isempty(chunk.accum) || ~any(chunk.weightSum > 0)
        continue
    end
    row.accum = row.accum + chunk.accum;
    row.weightSum = row.weightSum + chunk.weightSum;
    row.nChunks = row.nChunks + chunk.nChunks;
    row.support = row.support + chunk.support;
    row.chunkCorrRows(end+1, :) = chunk.corr(:)'; %#ok<AGROW>
    row.chunkWeightRows(end+1, :) = chunk.weightSum(:)'; %#ok<AGROW>
end
row.corr = localSafeWeightedMean(row.accum, row.weightSum);
end


function chunk = localVectorCorrFromPositions(gazeX, gazeY, targetX, targetY, dtSec, lagSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, trialMeans, globalMeans)
chunk = localEmptyVectorRow(lagSec);
gazeX = double(gazeX(:));
gazeY = double(gazeY(:));
targetX = double(targetX(:));
targetY = double(targetY(:));
if numel(gazeX) < 3 || numel(gazeY) ~= numel(gazeX) || ...
        numel(targetX) ~= numel(gazeX) || numel(targetY) ~= numel(gazeX) || ...
        ~isfinite(dtSec) || dtSec <= 0
    return
end

lagSamples = round(double(lagSec(:)) ./ dtSec);
validMask = isfinite(gazeX) & isfinite(gazeY) & isfinite(targetX) & isfinite(targetY);
idx = find(validMask);
if numel(idx) < 3
    return
end

runBreak = [true; diff(idx) > 1];
runStarts = find(runBreak);
runEnds = [runStarts(2:end) - 1; numel(idx)];
for i = 1:numel(runStarts)
    ii = idx(runStarts(i):runEnds(i));
    if numel(ii) < 4
        continue
    end
    gxVel = diff(gazeX(ii)) ./ dtSec;
    gyVel = diff(gazeY(ii)) ./ dtSec;
    txVel = diff(targetX(ii)) ./ dtSec;
    tyVel = diff(targetY(ii)) ./ dtSec;
    stepAmpPx = hypot(diff(targetX(ii)), diff(targetY(ii)));
    good = isfinite(gxVel) & isfinite(gyVel) & isfinite(txVel) & isfinite(tyVel) & isfinite(stepAmpPx);
    if isfinite(stepAmpMinPx)
        good = good & stepAmpPx >= stepAmpMinPx;
    end
    if isfinite(stepAmpMaxPx)
        good = good & stepAmpPx < stepAmpMaxPx;
    end
    gxVel = gxVel(good);
    gyVel = gyVel(good);
    txVel = txVel(good);
    tyVel = tyVel(good);
    if numel(gxVel) < 3
        continue
    end

    [gxVel, gyVel, txVel, tyVel] = localApplyVectorDemean( ...
        gxVel, gyVel, txVel, tyVel, demeanMode, trialMeans, globalMeans);
    xc = localVectorXcorrCoeff(gxVel, gyVel, txVel, tyVel, lagSamples);
    finiteMask = isfinite(xc);
    if ~any(finiteMask)
        continue
    end
    overlapCount = double(numel(gxVel) - abs(lagSamples));
    overlapCount(overlapCount < 0) = 0;
    w = numel(gxVel);
    chunk.accum(finiteMask) = chunk.accum(finiteMask) + w .* xc(finiteMask);
    chunk.weightSum(finiteMask) = chunk.weightSum(finiteMask) + w;
    chunk.nChunks(finiteMask) = chunk.nChunks(finiteMask) + 1;
    chunk.support(finiteMask) = chunk.support(finiteMask) + overlapCount(finiteMask);
end
chunk.corr = localSafeWeightedMean(chunk.accum, chunk.weightSum);
end


function xc = localVectorXcorrCoeff(gxVel, gyVel, txVel, tyVel, lagSamples)
n = numel(gxVel);
xc = NaN(numel(lagSamples), 1);
for i = 1:numel(lagSamples)
    lag = lagSamples(i);
    if lag >= 0
        gIdx = (1 + lag):n;
        tIdx = 1:(n - lag);
    else
        gIdx = 1:(n + lag);
        tIdx = (1 - lag):n;
    end
    if numel(gIdx) < 1 || numel(tIdx) ~= numel(gIdx)
        continue
    end
    numerator = sum(gxVel(gIdx) .* txVel(tIdx) + gyVel(gIdx) .* tyVel(tIdx), 'omitnan');
    gazePower = sum(gxVel(gIdx).^2 + gyVel(gIdx).^2, 'omitnan');
    targetPower = sum(txVel(tIdx).^2 + tyVel(tIdx).^2, 'omitnan');
    denom = sqrt(gazePower .* targetPower);
    if isfinite(denom) && denom > 0
        xc(i) = numerator ./ denom;
    end
end
end


function means = localVectorMeansForEpisodes(E, stepAmpMinPx, stepAmpMaxPx, trialId)
sumVals = zeros(1, 4);
nVals = 0;
for i = 1:height(E)
    if isfinite(trialId) && double(E.trial(i)) ~= trialId
        continue
    end
    dtSec = double(E.dtStepSec(i));
    if ~isfinite(dtSec) || dtSec <= 0
        continue
    end
    gx = double(E.gazeX{i}(:));
    gy = double(E.gazeY{i}(:));
    tx = double(E.targetX{i}(:));
    ty = double(E.targetY{i}(:));
    n = min([numel(gx), numel(gy), numel(tx), numel(ty)]);
    if n < 3
        continue
    end
    gx = gx(1:n);
    gy = gy(1:n);
    tx = tx(1:n);
    ty = ty(1:n);
    validMask = isfinite(gx) & isfinite(gy) & isfinite(tx) & isfinite(ty);
    idx = find(validMask);
    runBreak = [true; diff(idx) > 1];
    runStarts = find(runBreak);
    runEnds = [runStarts(2:end) - 1; numel(idx)];
    for j = 1:numel(runStarts)
        ii = idx(runStarts(j):runEnds(j));
        if numel(ii) < 4
            continue
        end
        gxVel = diff(gx(ii)) ./ dtSec;
        gyVel = diff(gy(ii)) ./ dtSec;
        txVel = diff(tx(ii)) ./ dtSec;
        tyVel = diff(ty(ii)) ./ dtSec;
        stepAmpPx = hypot(diff(tx(ii)), diff(ty(ii)));
        good = isfinite(gxVel) & isfinite(gyVel) & isfinite(txVel) & isfinite(tyVel) & isfinite(stepAmpPx);
        if isfinite(stepAmpMinPx)
            good = good & stepAmpPx >= stepAmpMinPx;
        end
        if isfinite(stepAmpMaxPx)
            good = good & stepAmpPx < stepAmpMaxPx;
        end
        if ~any(good)
            continue
        end
        sumVals = sumVals + [sum(gxVel(good), 'omitnan'), sum(gyVel(good), 'omitnan'), ...
            sum(txVel(good), 'omitnan'), sum(tyVel(good), 'omitnan')];
        nVals = nVals + nnz(good);
    end
end
means = localDefaultVectorMeans();
if nVals > 0
    means.gx = sumVals(1) ./ nVals;
    means.gy = sumVals(2) ./ nVals;
    means.tx = sumVals(3) ./ nVals;
    means.ty = sumVals(4) ./ nVals;
end
end


function [gxVel, gyVel, txVel, tyVel] = localApplyVectorDemean(gxVel, gyVel, txVel, tyVel, demeanMode, trialMeans, globalMeans)
switch localResolveDemeanModeLocal(demeanMode)
    case 'chunk'
        gxVel = gxVel - mean(gxVel, 'omitnan');
        gyVel = gyVel - mean(gyVel, 'omitnan');
        txVel = txVel - mean(txVel, 'omitnan');
        tyVel = tyVel - mean(tyVel, 'omitnan');
    case 'trial'
        [gxVel, gyVel, txVel, tyVel] = localSubtractVectorMeans(gxVel, gyVel, txVel, tyVel, trialMeans);
    case 'global'
        [gxVel, gyVel, txVel, tyVel] = localSubtractVectorMeans(gxVel, gyVel, txVel, tyVel, globalMeans);
    case 'none'
end
end


function [gxVel, gyVel, txVel, tyVel] = localSubtractVectorMeans(gxVel, gyVel, txVel, tyVel, means)
if isfinite(means.gx)
    gxVel = gxVel - means.gx;
end
if isfinite(means.gy)
    gyVel = gyVel - means.gy;
end
if isfinite(means.tx)
    txVel = txVel - means.tx;
end
if isfinite(means.ty)
    tyVel = tyVel - means.ty;
end
end


function means = localDefaultVectorMeans()
means = struct('gx', NaN, 'gy', NaN, 'tx', NaN, 'ty', NaN);
end


function row = localEmptyVectorRow(lagSec)
lagSec = double(lagSec(:));
row = struct('corr', NaN(size(lagSec)), 'accum', zeros(size(lagSec)), ...
    'weightSum', zeros(size(lagSec)), 'nChunks', zeros(size(lagSec)), ...
    'support', zeros(size(lagSec)), 'chunkCorrRows', NaN(0, numel(lagSec)), ...
    'chunkWeightRows', NaN(0, numel(lagSec)));
end


function x = localSafeWeightedMean(accum, weightSum)
x = NaN(size(accum));
mask = isfinite(accum) & isfinite(weightSum) & weightSum > 0;
x(mask) = accum(mask) ./ weightSum(mask);
end


function lagSec = localGroupLagSec(out, group)
lagSec = [];
if isfield(group, 'lagSec') && ~isempty(group.lagSec)
    lagSec = double(group.lagSec(:));
elseif isfield(out, 'lagSec') && ~isempty(out.lagSec)
    lagSec = double(out.lagSec(:));
end
end


function [refOut, refInfo] = localBuildReferenceVectorOut(in, out, ccgOpts)
refOut = [];
refInfo = struct('enabled', false);
if ~localIsExLike(in) || ~isfield(out, 'trialGroups') || isempty(out.trialGroups) || ...
        ~isfield(out, 'episodes') || isempty(out.episodes)
    return
end
refGroup = localGetField(ccgOpts, 'refGroup', 't12bg-1');
[refTrialGroups, refInfo] = refGroupTrialGroupsCoPs(in, out.trialGroups, refGroup);
if ~isfield(refInfo, 'enabled') || ~isequal(refInfo.enabled, true) || ~any(cellfun(@(x) ~isempty(x), refTrialGroups(:)))
    return
end

demeanMode = localResolveDemeanModeLocal(localGetField(ccgOpts, 'demeanMode', localGetField(out, 'demeanMode', 'chunk')));
aggregateMode = validatestring(char(string(localGetField(ccgOpts, 'aggregateMode', localGetField(out, 'aggregateMode', 'chunk')))), {'chunk', 'trial'});
mainLabels = localOutputGroupLabels(out);
refOut = out;
refOut.trialGroups = refTrialGroups;
refOut.trials = localFlattenTrialGroupsLocal(refTrialGroups);
nRef = size(refTrialGroups, 2);
refLabels = strings(numel(out.groups), nRef);
refEpisodes = cell(numel(out.groups), nRef);
refOut.groups = cell(numel(out.groups), nRef);
for r = 1:nRef
    for g = 1:numel(out.groups)
        group = out.groups{g};
        lagSec = localGroupLagSec(out, group);
        stepAmpMinPx = localGetField(group, 'stepAmpMinPx', NaN);
        stepAmpMaxPx = localGetField(group, 'stepAmpMaxPx', NaN);
        E = out.episodes(double(out.episodes.group) == g, :);
        if ~isempty(refTrialGroups{g, r}) && ismember('trial', E.Properties.VariableNames)
            E = E(ismember(double(E.trial), double(refTrialGroups{g, r})), :);
        else
            E = table();
        end
        group = localComputeVectorGroup(E, group, lagSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, aggregateMode);
        group.trials = refTrialGroups{g, r};
        group.groupLabel = localReferenceGroupLabel(refInfo.labels(r), mainLabels(g));
        group.refIndex = r;
        group.refTargetNum = localRefTargetNum(refInfo, r);
        refLabels(g, r) = string(group.groupLabel);
        refOut.groups{g, r} = group;
        refEpisodes{g, r} = E;
    end
end
refOut.episodes = vertcatNonEmptyTablesCoPs(refEpisodes);
refOut.groupLabels = refLabels;
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


function trials = localFlattenTrialGroupsLocal(trialGroups)
if isempty(trialGroups)
    trials = [];
    return
end
pieces = cell(numel(trialGroups), 1);
for i = 1:numel(trialGroups)
    pieces{i} = double(trialGroups{i}(:));
end
pieces = pieces(~cellfun(@isempty, pieces));
if isempty(pieces)
    trials = [];
else
    trials = unique(vertcat(pieces{:}))';
end
end


function opts = localPlotDefaults(opts, out, trialNo, in)
if ~isfield(opts, 'plot') || isempty(opts.plot)
    opts.plot = true;
end
if ~isfield(opts, 'newFigure') || isempty(opts.newFigure)
    opts.newFigure = true;
end
if ~isfield(opts, 'lineWidth') || isempty(opts.lineWidth)
    opts.lineWidth = 1.25;
end
if ~isfield(opts, 'legendLocation') || isempty(opts.legendLocation)
    opts.legendLocation = 'northeastoutside';
end
if ~isfield(opts, 'refGroup')
    opts.refGroup = 't12bg-1';
end
if ~isfield(opts, 'refLineStyle')
    opts.refLineStyle = [];
end
if ~isfield(opts, 'refLineWidth')
    opts.refLineWidth = [];
end
nGroup = numel(out.groups);
facetSpec = localResolveFacetSpec(out, trialNo, in);
opts.colors = resolveCcgPlotColors(nGroup, opts, facetSpec, localOutputGroupLabels(out));
end


function localPlotVectorCcg(out, trialNo, opts, in, refOut)
if nargin < 5
    refOut = [];
end
facetSpec = localResolveFacetSpec(out, trialNo, in);
if facetSpec.enabled
    tiledlayout(facetSpec.nRows, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
    for iRow = 1:facetSpec.nRows
        nexttile;
        localPlotGroupSet(out, facetSpec.rowGroupIdx{iRow}, opts, facetSpec.groupLineLabels, facetSpec.rowLabels(iRow), refOut);
    end
else
    localPlotGroupSet(out, 1:numel(out.groups), opts, {}, "", refOut);
end
titleText = sprintf('2D Velocity CCG (%d group%s)', numel(out.groups), localPlural(numel(out.groups)));
if localIsNamedCodeCell(trialNo)
    titleText = sprintf('%s | %s', titleText, strjoin(cellfun(@char, trialNo, 'UniformOutput', false), ' x '));
end
sgtitle(titleText, 'Interpreter', 'none');
end


function localPlotGroupSet(out, groupIdx, opts, legendLabelsOverride, rowLabel, refOut)
if nargin < 6
    refOut = [];
end
hold on
lagSec = double(out.lagSec(:));
nRef = 0;
if ~isempty(refOut) && isfield(refOut, 'groups') && ~isempty(refOut.groups)
    nRef = size(refOut.groups, 2);
end
nLegendSlots = numel(groupIdx) * (1 + nRef);
legendLabels = cell(nLegendSlots, 1);
plotted = false(nLegendSlots, 1);
plotHandles = gobjects(nLegendSlots, 1);
plotCount = 0;
for j = 1:numel(groupIdx)
    g = groupIdx(j);
    xc = double(out.groups{g}.aggregate2D(:));
    groupLagSec = localGroupLagSec(out, out.groups{g});
    if ~isempty(groupLagSec)
        lagSecUse = groupLagSec(:);
    else
        lagSecUse = lagSec;
    end
    if isempty(lagSecUse) || isempty(xc) || numel(lagSecUse) ~= numel(xc)
        continue
    end
    plotCount = plotCount + 1;
    plotHandles(plotCount) = plot(lagSecUse, xc, 'Color', opts.colors(g, :), 'LineWidth', opts.lineWidth);
    if ~isempty(legendLabelsOverride) && numel(legendLabelsOverride) == numel(out.groups)
        label = string(legendLabelsOverride{g});
    elseif ~isempty(legendLabelsOverride) && numel(legendLabelsOverride) >= j
        label = string(legendLabelsOverride{j});
    else
        label = string(out.groups{g}.groupLabel);
        if strlength(strtrim(label)) == 0 || ismissing(label)
            label = "group " + string(g);
        end
    end
    legendLabels{plotCount} = sprintf('%s (n=%d)', char(label), numel(out.groups{g}.trials));
    plotted(plotCount) = true;
end
for r = 1:nRef
    for j = 1:numel(groupIdx)
        g = groupIdx(j);
        if isempty(refOut) || ~isfield(refOut, 'groups') || size(refOut.groups, 1) < g || isempty(refOut.groups{g, r})
            continue
        end
        xc = double(refOut.groups{g, r}.aggregate2D(:));
        groupLagSec = localGroupLagSec(refOut, refOut.groups{g, r});
        if ~isempty(groupLagSec)
            lagSecUse = groupLagSec(:);
        else
            lagSecUse = lagSec;
        end
        if isempty(lagSecUse) || isempty(xc) || numel(lagSecUse) ~= numel(xc) || ~any(isfinite(xc))
            continue
        end
        plotCount = plotCount + 1;
        plotHandles(plotCount) = plot(lagSecUse, xc, ...
            'Color', localReferenceColor(opts.colors(g, :), r, nRef), ...
            'LineStyle', localReferenceLineStyle(opts, refOut.groups{g, r}), ...
            'LineWidth', localReferenceLineWidth(opts));
        label = string(refOut.groups{g, r}.groupLabel);
        if strlength(strtrim(label)) == 0 || ismissing(label)
            label = "reference group " + string(g);
        end
        legendLabels{plotCount} = sprintf('%s (n=%d)', char(label), numel(refOut.groups{g, r}.trials));
        plotted(plotCount) = true;
    end
end
xline(0, ':');
yline(0, ':');
localApplyCcgWindowXLim(opts, lagSec);
xlabel('Lag (s)');
ylabel('2D velocity xcorr');
titleText = '2D Velocity CCG';
if strlength(strtrim(string(rowLabel))) > 0
    titleText = sprintf('%s | %s', titleText, char(string(rowLabel)));
end
title(titleText, 'Interpreter', 'none');
box off
if nnz(plotted) > 1
    legend(plotHandles(plotted), legendLabels(plotted), ...
        'Location', char(string(opts.legendLocation)), 'Interpreter', 'none');
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


function localApplyCcgWindowXLim(opts, lagSec)
xWindow = [];
if isstruct(opts) && isfield(opts, 'ccgWindowSec') && ~isempty(opts.ccgWindowSec)
    xWindow = double(opts.ccgWindowSec(:));
    xWindow = xWindow(isfinite(xWindow));
end
if numel(xWindow) >= 2
    xWindow = [min(xWindow), max(xWindow)];
elseif ~isempty(lagSec)
    xWindow = double(lagSec(:));
    xWindow = xWindow(isfinite(xWindow));
    if numel(xWindow) >= 2
        xWindow = [min(xWindow), max(xWindow)];
    else
        xWindow = [];
    end
end
if numel(xWindow) == 2 && xWindow(2) > xWindow(1)
    xlim(xWindow);
end
end


function facetSpec = localResolveFacetSpec(out, trialNo, in)
nGroup = numel(out.groups);
facetSpec = struct('enabled', false, 'nRows', 1, 'nLineGroups', nGroup, ...
    'rowGroupIdx', {{}}, 'rowLabels', strings(0, 1), ...
    'groupLineLabels', {{}}, 'lineGroupIndex', (1:nGroup)');
inputMode = "";
if isfield(out, 'inputMode') && ~isempty(out.inputMode)
    inputMode = string(out.inputMode);
end
if ~strcmp(inputMode, "ex") && ~localIsExLike(in)
    return
end
if ~localIsNamedCodeCell(trialNo) || numel(trialNo) ~= 2
    return
end
code1 = localCanonicalGroupingCode(trialNo{1});
code2 = localCanonicalGroupingCode(trialNo{2});
if localIsPercentileCode(code1) || localIsPercentileCode(code2)
    return
end

levelLabels = strings(nGroup, 2);
useSpecLabels = false;
if isfield(out, 'groupingSpec') && isstruct(out.groupingSpec) && ...
        isfield(out.groupingSpec, 'codeList') && isfield(out.groupingSpec, 'groupLevelLabels')
    [levelLabels, useSpecLabels] = localFacetLabelsFromGroupingSpec(out.groupingSpec, code1, code2, nGroup);
end
if ~useSpecLabels
    levelLabels = localFacetLabelsFromGroupLabels(out, code1, code2);
end
validGroups = strlength(strtrim(levelLabels(:, 1))) > 0 & strlength(strtrim(levelLabels(:, 2))) > 0;
if ~any(validGroups)
    return
end
rowLabels = localUniqueStableStrings(levelLabels(validGroups, 1));
lineLabels = localUniqueStableStrings(levelLabels(validGroups, 2));
if isempty(rowLabels) || isempty(lineLabels)
    return
end

facetSpec.enabled = true;
facetSpec.nRows = numel(rowLabels);
facetSpec.nLineGroups = numel(lineLabels);
facetSpec.rowLabels = rowLabels(:);
facetSpec.groupLineLabels = cellstr(levelLabels(:, 2));
facetSpec.rowGroupIdx = cell(facetSpec.nRows, 1);
for i = 1:facetSpec.nRows
    facetSpec.rowGroupIdx{i} = find(validGroups & strcmp(levelLabels(:, 1), rowLabels(i))).';
end
facetSpec.lineGroupIndex = ones(nGroup, 1);
for g = 1:nGroup
    idx = find(strcmp(lineLabels, levelLabels(g, 2)), 1, 'first');
    if ~isempty(idx)
        facetSpec.lineGroupIndex(g) = idx;
    end
end
end


function [levelLabels, ok] = localFacetLabelsFromGroupingSpec(groupingSpec, code1, code2, nGroup)
levelLabels = strings(nGroup, 2);
ok = false;
specCodes = groupingSpec.codeList;
if numel(specCodes) < 2 || size(groupingSpec.groupLevelLabels, 1) ~= nGroup
    return
end
for i = 1:numel(specCodes)
    specCodes{i} = localCanonicalGroupingCode(specCodes{i});
end
col1 = find(strcmp(specCodes, code1), 1, 'first');
col2 = find(strcmp(specCodes, code2), 1, 'first');
if isempty(col1) || isempty(col2) || size(groupingSpec.groupLevelLabels, 2) < max([col1, col2])
    return
end
levelLabels(:, 1) = string(groupingSpec.groupLevelLabels(:, col1));
levelLabels(:, 2) = string(groupingSpec.groupLevelLabels(:, col2));
ok = true;
end


function levelLabels = localFacetLabelsFromGroupLabels(out, code1, code2)
nGroup = numel(out.groups);
levelLabels = strings(nGroup, 2);
groupLabels = localOutputGroupLabels(out);
for g = 1:nGroup
    levelLabels(g, 1) = localGroupLabelValue(groupLabels(g), code1);
    levelLabels(g, 2) = localGroupLabelValue(groupLabels(g), code2);
end
end


function groupLabels = localOutputGroupLabels(out)
nGroup = numel(out.groups);
groupLabels = strings(nGroup, 1);
if isfield(out, 'groupLabels') && numel(out.groupLabels) >= nGroup
    rawLabels = string(out.groupLabels(:));
    groupLabels(:) = rawLabels(1:nGroup);
    return
end
for g = 1:nGroup
    if isfield(out.groups{g}, 'groupLabel') && ~isempty(out.groups{g}.groupLabel)
        groupLabels(g) = string(out.groups{g}.groupLabel);
    end
end
end


function value = localGroupLabelValue(groupLabel, code)
groupLabel = string(groupLabel);
value = "";
if strlength(strtrim(groupLabel)) == 0 || ismissing(groupLabel)
    return
end
if strcmp(code, 'all') && strcmpi(strtrim(groupLabel), "all")
    value = "all";
    return
end
if strcmp(code, 'pur') && strcmpi(strtrim(groupLabel), "pur")
    value = "pur";
    return
end
parts = split(groupLabel, "|");
prefix = string(code) + ":";
for i = 1:numel(parts)
    part = strtrim(parts(i));
    if startsWith(lower(part), lower(prefix))
        value = strtrim(extractAfter(part, strlength(prefix)));
        return
    end
end
end


function labels = localUniqueStableStrings(values)
values = string(values(:));
labels = strings(0, 1);
for i = 1:numel(values)
    value = strtrim(values(i));
    if strlength(value) == 0 || ismissing(value)
        continue
    end
    if ~any(strcmp(labels, value))
        labels(end+1, 1) = value; %#ok<AGROW>
    end
end
end


function code = localCanonicalGroupingCode(code)
code = lower(strtrim(char(string(code))));
if localIsRewardQuadCode(code)
    code = 'rq';
elseif ismember(code, {'pur', 'purs', 'pursuit', 'pursuittrial', 'pursuittrials'})
    code = 'pur';
end
end


function tf = localIsRewardQuadCode(code)
code = lower(strtrim(char(string(code))));
tf = ismember(code, {'rq', 'rewq', 'rquad', 'rewardquad', 'rewardquadrant'});
end


function tf = localIsExLike(value)
tf = isstruct(value) && isscalar(value) && isfield(value, 'Trials');
end


function tf = localIsNamedCodeCell(value)
tf = iscell(value) && ~isempty(value);
if ~tf
    return
end
for i = 1:numel(value)
    if ~(ischar(value{i}) || (isstring(value{i}) && isscalar(value{i})))
        tf = false;
        return
    end
end
end


function tf = localIsPercentileCode(value)
code = lower(strtrim(char(string(value))));
tf = ~isempty(regexp(code, '^p\d+(\.\d+)?$', 'once'));
end


function mode = localResolveDemeanModeLocal(value)
if nargin < 1 || isempty(value)
    mode = 'chunk';
    return
end
mode = lower(strtrim(char(string(value))));
switch mode
    case {'chunk', 'trial', 'global', 'none'}
    otherwise
        error('plotCCG2:BadDemeanMode', 'opts.demeanMode must be ''chunk'', ''trial'', ''global'', or ''none''.');
end
end


function value = localGetField(s, fieldName, defaultValue)
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);
else
    value = defaultValue;
end
end


function suffix = localPlural(n)
if n == 1
    suffix = '';
else
    suffix = 's';
end
end
