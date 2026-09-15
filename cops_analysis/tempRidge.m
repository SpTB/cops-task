function out = tempRidge(in, trialNo, opts, varargin)
% tempRidge  Fit temporal ridge kernels from target history to gaze.
%
%   out = tempRidge(ex, trialNo)
%   out = tempRidge(ex, {g1, g2}, opts)
%   out = tempRidge(ex, 'bg', opts)
%   out = tempRidge(trackingTable, trialNo, opts)
%
% The function reuses ccg() to build cleaned, step-aggregated episodes,
% then fits lagged target-history models separately for x and y.
%
% Model lags are fit with positive values meaning target history precedes gaze:
%   gaze(t) = sum_lag beta(lag) * target(t - lag)
% For Huk-style plotting/output, plotLagSec = -modelLagSec, so preceding
% target history appears at negative times.
%
% Options
%   .analysisMode  (default 'continuous') 'continuous' or 'saccade'
%   .signalMode    (default 'velocity') 'velocity' or 'position'
%   .lagWindowSec  (default [-0.5 2.5]) lag window in seconds
%   .saccadeResponse (default 'auto') 'auto', 'delta', or 'endpoint'
%   .lambda        (default []) scalar ridge strength; [] uses CV
%   .lambdaGrid    (default logspace(-6, 2, 33)) CV candidate strengths
%   .cvFolds       (default 5)
%   .cvMode        (default 'trial') 'trial', 'chunk', or 'observation'
%   .cvSeed        (default 1)
%   .lagDropoutBlocksSec  (default []) Nx2 lag bands on plot lag axis
%   .lagDropoutBlockLabels (default []) optional labels for dropout bands
%   .rewardDirectionMode (default false) split target-history predictors
%                      into toward-reward and away-from-reward motion
%                      using the selected target's distance change relative
%                      to the Gaussian reward center. Continuous velocity
%                      mode and raw ex input only.
%   .rewardDirectionGainWindowSec (default []) plot-lag window for summary
%                      gains; [] uses all target-leading lags (plot lag <= 0)
%   .rewardRegionMode (default false) split target-history predictors into
%                      high and low reward-region motion. High means the
%                      selected target footprint intersects the Gaussian
%                      reward region inside rewardRegionSigmaRadius SD and
%                      with multiplier >= rewardRegionMinMultiplier.
%                      Continuous velocity mode and raw ex input only.
%   .rewardRegionSigmaRadius (default 3) SD radius cap for high reward region
%   .rewardRegionMinMultiplier (default 1.1) minimum gain multiplier for
%                      high reward region (1.1 = 10% over baseline)
%   .rewardRegionGainWindowSec (default []) plot-lag window for summary
%                      gains; [] uses all target-leading lags (plot lag <= 0)
%   .standardize   (default true) standardize predictors before fitting
%   .minSamples    (default 25) minimum observations per axis/group
%   .plot          (default false)
%   .newFigure     (default true)
%   .lineWidth     (default 1.25)
%   .colors        (default lines(nGroup))
%
% ccg() preprocessing options such as useEyeTime, eyeTimeAlignmentMode,
% lowpassHz, interpBlinkSec, removeSaccadesForCcg, shuffleEyeAcrossTrials,
% and shuffleEyeWithinTrials are forwarded to ccg().

if nargin < 2
    trialNo = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
if ischar(opts) || (isstring(opts) && isscalar(opts))
    if ~strcmpi(char(string(opts)), 'all')
        error('tempRidge:BadOpts', 'Third argument must be opts or the legacy string ''all''.');
    end
    if ~isempty(varargin)
        opts = varargin{1};
    else
        opts = struct();
    end
elseif ~isstruct(opts)
    error('tempRidge:BadOpts', 'Third argument must be an opts struct.');
end

defaults = struct( ...
    'analysisMode', 'continuous', ...
    'signalMode', 'velocity', ...
    'lagWindowSec', [-0.5 2.5], ...
    'saccadeResponse', 'auto', ...
    'lambda', [], ...
    'lambdaGrid', logspace(-6, 2, 33), ...
    'cvFolds', 5, ...
    'cvMode', 'trial', ...
    'cvSeed', 1, ...
    'lagDropoutBlocksSec', [], ...
    'lagDropoutBlockLabels', [], ...
    'rewardDirectionMode', false, ...
    'rewardDirectionGainWindowSec', [], ...
    'rewardRegionMode', false, ...
    'rewardRegionSigmaRadius', 3, ...
    'rewardRegionMinMultiplier', 1.1, ...
    'rewardRegionGainWindowSec', [], ...
    'standardize', true, ...
    'minSamples', 25, ...
    'plot', true, ...
    'newFigure', true, ...
    'lineWidth', 1.25, ...
    'colors', [], ...
    'onlyGoState', true, ...
    'useEyeTime', true, ...
    'useTrackingOnly', true, ...
    'lowpassHz', 2, ...
    'saccadeLowpassHz', [], ...
    'interpBlinkSec', 0.15, ...
    'truncateTrialFromStep', 0, ...
    'timeWindowSec', [], ...
    'setup', [], ...
    'speedThreshDegPerSec', 30, ...
    'minAmpDeg', 1, ...
    'minDurSec', 0.008, ...
    'maxDurSec', 5, ...
    'smoothFrames', 5);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field)
        opts.(field) = defaults.(field);
    end
end

opts.analysisMode = validatestring(char(string(opts.analysisMode)), {'continuous', 'saccade'});
opts.signalMode = validatestring(char(string(opts.signalMode)), {'velocity', 'position'});
opts.saccadeResponse = validatestring(char(string(opts.saccadeResponse)), {'auto', 'delta', 'endpoint'});
opts.cvMode = validatestring(char(string(opts.cvMode)), {'trial', 'chunk', 'observation'});
opts.lagWindowSec = localValidateLagWindow(opts.lagWindowSec);
opts.lambdaGrid = localValidateLambdaGrid(opts.lambdaGrid);
opts.cvFolds = max(2, round(double(localFirstScalar(opts.cvFolds))));
opts.cvSeed = double(localFirstScalar(opts.cvSeed));
opts.lagDropoutBlocksSec = localValidateLagDropoutBlocks(opts.lagDropoutBlocksSec);
opts.lagDropoutBlockLabels = localValidateLagDropoutLabels( ...
    opts.lagDropoutBlockLabels, opts.lagDropoutBlocksSec);
opts.rewardDirectionMode = logical(opts.rewardDirectionMode);
opts.rewardDirectionGainWindowSec = localValidateOptionalTimeWindow(opts.rewardDirectionGainWindowSec, ...
    'rewardDirectionGainWindowSec');
opts.rewardRegionMode = logical(opts.rewardRegionMode);
opts.rewardRegionSigmaRadius = double(localFirstScalar(opts.rewardRegionSigmaRadius));
if ~isfinite(opts.rewardRegionSigmaRadius) || opts.rewardRegionSigmaRadius <= 0
    error('tempRidge:BadRewardRegionSigmaRadius', ...
        'opts.rewardRegionSigmaRadius must be a finite positive scalar.');
end
opts.rewardRegionMinMultiplier = double(localFirstScalar(opts.rewardRegionMinMultiplier));
if ~isfinite(opts.rewardRegionMinMultiplier) || opts.rewardRegionMinMultiplier <= 1
    error('tempRidge:BadRewardRegionMinMultiplier', ...
        'opts.rewardRegionMinMultiplier must be a finite scalar greater than 1.');
end
opts.rewardRegionGainWindowSec = localValidateOptionalTimeWindow(opts.rewardRegionGainWindowSec, ...
    'rewardRegionGainWindowSec');
opts.standardize = logical(opts.standardize);
opts.minSamples = max(1, round(double(localFirstScalar(opts.minSamples))));

if opts.rewardDirectionMode && opts.rewardRegionMode
    error('tempRidge:RewardSplitConflict', ...
        'Use either opts.rewardDirectionMode or opts.rewardRegionMode, not both in the same fit.');
end
if opts.rewardDirectionMode
    if ~strcmp(opts.analysisMode, 'continuous') || ~strcmp(opts.signalMode, 'velocity')
        error('tempRidge:RewardDirectionUnsupported', ...
            'opts.rewardDirectionMode currently requires analysisMode=''continuous'' and signalMode=''velocity''.');
    end
    if ~localIsExStruct(in)
        error('tempRidge:RewardDirectionRequiresEx', ...
            'opts.rewardDirectionMode currently requires raw ex input so Gaussian reward centers can be resolved.');
    end
end
if opts.rewardRegionMode
    if ~strcmp(opts.analysisMode, 'continuous') || ~strcmp(opts.signalMode, 'velocity')
        error('tempRidge:RewardRegionUnsupported', ...
            'opts.rewardRegionMode currently requires analysisMode=''continuous'' and signalMode=''velocity''.');
    end
    if ~localIsExStruct(in)
        error('tempRidge:RewardRegionRequiresEx', ...
            'opts.rewardRegionMode currently requires raw ex input so Gaussian reward centers can be resolved.');
    end
end

ccgOpts = localCcgOpts(opts);
base = ccg(in, trialNo, ccgOpts);
opts.setup = localResolveAnalysisSetup(in, opts);
episodes = base.episodes;
rewardSplitInfo = localRewardSplitInfo(in, opts);

dtStepSec = NaN;
if ~isempty(episodes) && ismember('dtStepSec', episodes.Properties.VariableNames)
    dtStepSec = localCommonDtStepSec(episodes.dtStepSec);
end
if ~isfinite(dtStepSec) || dtStepSec <= 0
    error('tempRidge:BadStepDt', 'Could not infer a valid step duration from ccg() episodes.');
end

lagSamples = localLagSamples(opts.lagWindowSec, dtStepSec);
modelLagSec = lagSamples .* dtStepSec;
plotLagSecRaw = -modelLagSec;
[plotLagSec, plotOrder] = sort(plotLagSecRaw);

groupLabels = base.groupLabels;
nGroup = numel(base.trialGroups);
groups = cell(nGroup, 1);
if strcmp(opts.analysisMode, 'saccade')
    saccades = localBuildSaccadeEventTable(in, base, opts);
    for g = 1:nGroup
        if isempty(saccades) || ~ismember('group', saccades.Properties.VariableNames)
            Sg = table();
        else
            Sg = saccades(double(saccades.group) == g, :);
        end
        groups{g} = localFitSaccadeGroup(Sg, lagSamples, modelLagSec, plotLagSec, plotOrder, opts, g, groupLabels(g));
    end
else
    saccades = table();
    for g = 1:nGroup
        if isempty(episodes) || ~ismember('group', episodes.Properties.VariableNames)
            Eg = table();
        else
            Eg = episodes(double(episodes.group) == g, :);
        end
        groups{g} = localFitGroup(Eg, lagSamples, modelLagSec, plotLagSec, plotOrder, opts, g, groupLabels(g), rewardSplitInfo);
    end
end

if opts.plot
    localPlotTempRidge(groups, plotLagSec, opts, groupLabels);
end

out = struct();
out.episodes = episodes;
out.trials = base.trials;
out.trialGroups = base.trialGroups;
out.groupLabels = groupLabels;
out.groupingSpec = base.groupingSpec;
out.inputMode = base.inputMode;
out.analysisMode = char(opts.analysisMode);
out.signalMode = char(opts.signalMode);
out.saccadeResponse = localResolveSaccadeResponse(opts);
out.rewardDirectionMode = logical(opts.rewardDirectionMode);
out.rewardDirectionGainWindowSec = opts.rewardDirectionGainWindowSec;
out.rewardRegionMode = logical(opts.rewardRegionMode);
out.rewardRegionSigmaRadius = opts.rewardRegionSigmaRadius;
out.rewardRegionMinMultiplier = opts.rewardRegionMinMultiplier;
out.rewardRegionGainWindowSec = opts.rewardRegionGainWindowSec;
out.lagSec = plotLagSec(:)';
out.plotLagSec = plotLagSec(:)';
out.modelLagSec = modelLagSec(plotOrder);
out.lagSamples = lagSamples(plotOrder);
out.dtStepSec = dtStepSec;
out.lagDropoutBlocksSec = opts.lagDropoutBlocksSec;
out.lagDropoutBlockLabels = opts.lagDropoutBlockLabels;
out.groups = groups;
out.saccades = saccades;
out.baseCcg = base;
end


function ccgOpts = localCcgOpts(opts)
ccgOpts = opts;
removeFields = {'analysisMode','signalMode','lagWindowSec','saccadeResponse','lambda','lambdaGrid', ...
    'cvFolds','cvMode','cvSeed','lagDropoutBlocksSec','lagDropoutBlockLabels', ...
    'rewardDirectionMode','rewardDirectionGainWindowSec', ...
    'rewardRegionMode','rewardRegionSigmaRadius','rewardRegionMinMultiplier','rewardRegionGainWindowSec', ...
    'standardize','minSamples','saccadeLowpassHz'};
ccgOpts = rmfield(ccgOpts, intersect(fieldnames(ccgOpts), removeFields));
ccgOpts.plot = false;
ccgOpts.newFigure = false;
end


function group = localFitGroup(E, lagSamples, modelLagSec, plotLagSec, plotOrder, opts, groupNo, groupLabel, rewardSplitInfo)
if nargin < 9
    rewardSplitInfo = struct('mode', 'none');
end
group = struct();
group.group = groupNo;
group.groupLabel = groupLabel;
group.trials = [];
group.lagSec = plotLagSec(:)';
group.plotLagSec = plotLagSec(:)';
group.modelLagSec = modelLagSec(plotOrder);
group.lagSamples = lagSamples(plotOrder);
group.signalMode = char(opts.signalMode);
group.x = localEmptyFit(lagSamples);
group.y = localEmptyFit(lagSamples);
group.betaX = NaN(1, numel(lagSamples));
group.betaY = NaN(1, numel(lagSamples));
group.r2X = NaN;
group.r2Y = NaN;
group.cvR2X = NaN;
group.cvR2Y = NaN;
group.residSdX = NaN;
group.residSdY = NaN;
group.cvResidSdX = NaN;
group.cvResidSdY = NaN;
group.residSdDegX = NaN;
group.residSdDegY = NaN;
group.cvResidSdDegX = NaN;
group.cvResidSdDegY = NaN;
group.lambdaX = NaN;
group.lambdaY = NaN;
group.lagDropoutX = localEmptyLagDropoutTable();
group.lagDropoutY = localEmptyLagDropoutTable();
group.rewardDirectionMode = logical(opts.rewardDirectionMode);
group.betaTowardX = NaN(1, numel(lagSamples));
group.betaAwayX = NaN(1, numel(lagSamples));
group.betaTowardY = NaN(1, numel(lagSamples));
group.betaAwayY = NaN(1, numel(lagSamples));
group.rewardDirectionGainX = localEmptyRewardDirectionGainTable();
group.rewardDirectionGainY = localEmptyRewardDirectionGainTable();
group.rewardDirectionIndexX = NaN;
group.rewardDirectionIndexY = NaN;
group.rewardRegionMode = logical(opts.rewardRegionMode);
group.betaHighX = NaN(1, numel(lagSamples));
group.betaLowX = NaN(1, numel(lagSamples));
group.betaHighY = NaN(1, numel(lagSamples));
group.betaLowY = NaN(1, numel(lagSamples));
group.rewardRegionGainX = localEmptyRewardRegionGainTable();
group.rewardRegionGainY = localEmptyRewardRegionGainTable();
group.rewardRegionIndexX = NaN;
group.rewardRegionIndexY = NaN;
group.rewardRegionDefinition = localRewardRegionDefinition(rewardSplitInfo);
if isempty(E)
    return
end

group.trials = unique(double(E.trial(:))', 'stable');
[Xx, yx, trialX, chunkX, designInfoX] = localBuildAxisDesign(E, 'x', lagSamples, opts, rewardSplitInfo);
[Xy, yy, trialY, chunkY, designInfoY] = localBuildAxisDesign(E, 'y', lagSamples, opts, rewardSplitInfo);

group.x = localFitAxisRidge(Xx, yx, trialX, chunkX, designInfoX.featureLagSamples, opts);
group.y = localFitAxisRidge(Xy, yy, trialY, chunkY, designInfoY.featureLagSamples, opts);
group.x.lagSamples = designInfoX.featureLagSamples(:);
group.x.baseLagSamples = lagSamples(:);
group.x.modelLagSec = modelLagSec(:);
group.x.plotLagSec = -modelLagSec(:);
group.x.featureKind = designInfoX.featureKind(:);
group.y.lagSamples = designInfoY.featureLagSamples(:);
group.y.baseLagSamples = lagSamples(:);
group.y.modelLagSec = modelLagSec(:);
group.y.plotLagSec = -modelLagSec(:);
group.y.featureKind = designInfoY.featureKind(:);
if logical(opts.rewardDirectionMode)
    [group.betaTowardX, group.betaAwayX] = localRewardDirectionBetas(group.x.beta, designInfoX, plotOrder);
    [group.betaTowardY, group.betaAwayY] = localRewardDirectionBetas(group.y.beta, designInfoY, plotOrder);
    group.betaX = group.betaTowardX;
    group.betaY = group.betaTowardY;
    group.rewardDirectionGainX = localRewardDirectionGainTable( ...
        group.betaTowardX, group.betaAwayX, plotLagSec, opts);
    group.rewardDirectionGainY = localRewardDirectionGainTable( ...
        group.betaTowardY, group.betaAwayY, plotLagSec, opts);
    group.rewardDirectionIndexX = localRewardDirectionIndex(group.rewardDirectionGainX);
    group.rewardDirectionIndexY = localRewardDirectionIndex(group.rewardDirectionGainY);
elseif logical(opts.rewardRegionMode)
    [group.betaHighX, group.betaLowX] = localRewardRegionBetas(group.x.beta, designInfoX, plotOrder);
    [group.betaHighY, group.betaLowY] = localRewardRegionBetas(group.y.beta, designInfoY, plotOrder);
    group.betaX = group.betaHighX;
    group.betaY = group.betaHighY;
    group.rewardRegionGainX = localRewardRegionGainTable( ...
        group.betaHighX, group.betaLowX, plotLagSec, opts);
    group.rewardRegionGainY = localRewardRegionGainTable( ...
        group.betaHighY, group.betaLowY, plotLagSec, opts);
    group.rewardRegionIndexX = localRewardRegionIndex(group.rewardRegionGainX);
    group.rewardRegionIndexY = localRewardRegionIndex(group.rewardRegionGainY);
else
    group.betaX = group.x.beta(plotOrder)';
    group.betaY = group.y.beta(plotOrder)';
end
group.r2X = group.x.r2;
group.r2Y = group.y.r2;
group.cvR2X = group.x.cvR2;
group.cvR2Y = group.y.cvR2;
group.residSdX = group.x.residSd;
group.residSdY = group.y.residSd;
group.cvResidSdX = group.x.cvResidSd;
group.cvResidSdY = group.y.cvResidSd;
group.residSdDegX = group.x.residSdDeg;
group.residSdDegY = group.y.residSdDeg;
group.cvResidSdDegX = group.x.cvResidSdDeg;
group.cvResidSdDegY = group.y.cvResidSdDeg;
group.lambdaX = group.x.lambda;
group.lambdaY = group.y.lambda;
group.lagDropoutX = localLagDropoutTable(Xx, yx, trialX, chunkX, ...
    designInfoX.featureLagSamples, designInfoX.featureModelLagSec, group.x, opts);
group.lagDropoutY = localLagDropoutTable(Xy, yy, trialY, chunkY, ...
    designInfoY.featureLagSamples, designInfoY.featureModelLagSec, group.y, opts);
end


function group = localFitSaccadeGroup(S, lagSamples, modelLagSec, plotLagSec, plotOrder, opts, groupNo, groupLabel)
group = struct();
group.group = groupNo;
group.groupLabel = groupLabel;
group.trials = [];
group.lagSec = plotLagSec(:)';
group.plotLagSec = plotLagSec(:)';
group.modelLagSec = modelLagSec(plotOrder);
group.lagSamples = lagSamples(plotOrder);
group.signalMode = char(opts.signalMode);
group.analysisMode = 'saccade';
group.saccadeResponse = localResolveSaccadeResponse(opts);
group.x = localEmptyFit(lagSamples);
group.y = localEmptyFit(lagSamples);
group.betaX = NaN(1, numel(lagSamples));
group.betaY = NaN(1, numel(lagSamples));
group.r2X = NaN;
group.r2Y = NaN;
group.cvR2X = NaN;
group.cvR2Y = NaN;
group.residSdX = NaN;
group.residSdY = NaN;
group.cvResidSdX = NaN;
group.cvResidSdY = NaN;
group.residSdDegX = NaN;
group.residSdDegY = NaN;
group.cvResidSdDegX = NaN;
group.cvResidSdDegY = NaN;
group.lambdaX = NaN;
group.lambdaY = NaN;
group.lagDropoutX = localEmptyLagDropoutTable();
group.lagDropoutY = localEmptyLagDropoutTable();
group.nSaccades = 0;
if isempty(S)
    return
end

group.trials = unique(double(S.trial(:))', 'stable');
group.nSaccades = height(S);
[Xx, yx, trialX, eventX] = localBuildSaccadeAxisDesign(S, 'x', lagSamples);
[Xy, yy, trialY, eventY] = localBuildSaccadeAxisDesign(S, 'y', lagSamples);

group.x = localFitAxisRidge(Xx, yx, trialX, eventX, lagSamples, opts);
group.y = localFitAxisRidge(Xy, yy, trialY, eventY, lagSamples, opts);
group.x.lagSamples = lagSamples(:);
group.x.modelLagSec = modelLagSec(:);
group.x.plotLagSec = -modelLagSec(:);
group.y.lagSamples = lagSamples(:);
group.y.modelLagSec = modelLagSec(:);
group.y.plotLagSec = -modelLagSec(:);
group.betaX = group.x.beta(plotOrder)';
group.betaY = group.y.beta(plotOrder)';
group.r2X = group.x.r2;
group.r2Y = group.y.r2;
group.cvR2X = group.x.cvR2;
group.cvR2Y = group.y.cvR2;
group.residSdX = group.x.residSd;
group.residSdY = group.y.residSd;
group.cvResidSdX = group.x.cvResidSd;
group.cvResidSdY = group.y.cvResidSd;
group.residSdDegX = group.x.residSdDeg;
group.residSdDegY = group.y.residSdDeg;
group.cvResidSdDegX = group.x.cvResidSdDeg;
group.cvResidSdDegY = group.y.cvResidSdDeg;
group.lambdaX = group.x.lambda;
group.lambdaY = group.y.lambda;
group.lagDropoutX = localLagDropoutTable(Xx, yx, trialX, eventX, lagSamples, modelLagSec, group.x, opts);
group.lagDropoutY = localLagDropoutTable(Xy, yy, trialY, eventY, lagSamples, modelLagSec, group.y, opts);
end


function [X, y, trialId, chunkId, designInfo] = localBuildAxisDesign(E, axisName, lagSamples, opts, rewardSplitInfo)
designInfo = localDesignInfo(lagSamples, localInferModelLagSecFromEpisodes(E, lagSamples), localRewardSplitMode(opts));
XBlocks = cell(height(E), 1);
yBlocks = cell(height(E), 1);
trialBlocks = cell(height(E), 1);
chunkBlocks = cell(height(E), 1);
nBlocks = 0;

for i = 1:height(E)
    switch axisName
        case 'x'
            gaze = double(E.gazeX{i}(:));
            target = double(E.targetX{i}(:));
        case 'y'
            gaze = double(E.gazeY{i}(:));
            target = double(E.targetY{i}(:));
    end
    targetX = double(E.targetX{i}(:));
    targetY = double(E.targetY{i}(:));
    dtStepSec = double(localFirstScalar(E.dtStepSec(i)));
    if numel(gaze) ~= numel(target) || numel(gaze) < 3 || ~isfinite(dtStepSec) || dtStepSec <= 0
        continue
    end
    if numel(targetX) ~= numel(target) || numel(targetY) ~= numel(target)
        continue
    end
    splitMode = localRewardSplitMode(opts);
    designInfo = localDesignInfo(lagSamples, lagSamples .* dtStepSec, splitMode);

    switch opts.signalMode
        case 'velocity'
            response = diff(gaze) ./ dtStepSec;
            stimulus = diff(target) ./ dtStepSec;
        case 'position'
            response = gaze;
            stimulus = target;
    end

    if logical(opts.rewardDirectionMode)
        trialNo = double(localFirstScalar(E.trial(i)));
        centerPx = localRewardCenterForTrial(rewardSplitInfo, trialNo);
        if any(~isfinite(centerPx))
            continue
        end
        [stimToward, stimAway] = localSplitStimulusByRewardDirection( ...
            stimulus, targetX, targetY, centerPx, opts.signalMode);
        [XiToward, yiToward] = localLaggedDesign(stimToward, response, lagSamples);
        [XiAway, yiAway] = localLaggedDesign(stimAway, response, lagSamples);
        if isempty(yiToward) || isempty(yiAway) || numel(yiToward) ~= numel(yiAway)
            continue
        end
        Xi = [XiToward, XiAway];
        yi = yiToward;
    elseif logical(opts.rewardRegionMode)
        trialNo = double(localFirstScalar(E.trial(i)));
        region = localRewardRegionForTrial(rewardSplitInfo, trialNo);
        if ~localRewardRegionIsUsable(region)
            continue
        end
        [stimHigh, stimLow] = localSplitStimulusByRewardRegion( ...
            stimulus, targetX, targetY, region, opts.signalMode);
        [XiHigh, yiHigh] = localLaggedDesign(stimHigh, response, lagSamples);
        [XiLow, yiLow] = localLaggedDesign(stimLow, response, lagSamples);
        if isempty(yiHigh) || isempty(yiLow) || numel(yiHigh) ~= numel(yiLow)
            continue
        end
        Xi = [XiHigh, XiLow];
        yi = yiHigh;
    else
        [Xi, yi] = localLaggedDesign(stimulus, response, lagSamples);
    end

    if isempty(yi)
        continue
    end
    nBlocks = nBlocks + 1;
    XBlocks{nBlocks} = Xi;
    yBlocks{nBlocks} = yi;
    trialBlocks{nBlocks} = repmat(double(E.trial(i)), numel(yi), 1);
    chunkBlocks{nBlocks} = repmat(i, numel(yi), 1);
end

if nBlocks == 0
    X = NaN(0, numel(designInfo.featureLagSamples));
    y = NaN(0, 1);
    trialId = NaN(0, 1);
    chunkId = NaN(0, 1);
else
    X = vertcat(XBlocks{1:nBlocks});
    y = vertcat(yBlocks{1:nBlocks});
    trialId = vertcat(trialBlocks{1:nBlocks});
    chunkId = vertcat(chunkBlocks{1:nBlocks});
end
end


function [X, y, trialId, eventId] = localBuildSaccadeAxisDesign(S, axisName, lagSamples)
XBlocks = cell(height(S), 1);
yBlocks = cell(height(S), 1);
trialBlocks = cell(height(S), 1);
eventBlocks = cell(height(S), 1);
nBlocks = 0;

for i = 1:height(S)
    switch axisName
        case 'x'
            stimulus = double(S.stimX{i}(:));
            response = double(S.responseX(i));
        case 'y'
            stimulus = double(S.stimY{i}(:));
            response = double(S.responseY(i));
    end
    anchorIdx = double(S.anchorIdx(i));
    if ~isfinite(response) || ~isfinite(anchorIdx) || isempty(stimulus)
        continue
    end
    [Xi, yi] = localLaggedEventDesign(stimulus, response, anchorIdx, lagSamples);
    if isempty(yi)
        continue
    end
    nBlocks = nBlocks + 1;
    XBlocks{nBlocks} = Xi;
    yBlocks{nBlocks} = yi;
    trialBlocks{nBlocks} = double(S.trial(i));
    eventBlocks{nBlocks} = i;
end

if nBlocks == 0
    X = NaN(0, numel(lagSamples));
    y = NaN(0, 1);
    trialId = NaN(0, 1);
    eventId = NaN(0, 1);
else
    X = vertcat(XBlocks{1:nBlocks});
    y = vertcat(yBlocks{1:nBlocks});
    trialId = vertcat(trialBlocks{1:nBlocks});
    eventId = vertcat(eventBlocks{1:nBlocks});
end
end


function [X, y] = localLaggedDesign(stimulus, response, lagSamples)
stimulus = double(stimulus(:));
response = double(response(:));
n = min(numel(stimulus), numel(response));
stimulus = stimulus(1:n);
response = response(1:n);

nLag = numel(lagSamples);
X = NaN(n, nLag);
t = (1:n)';
for j = 1:nLag
    src = t - lagSamples(j);
    valid = src >= 1 & src <= n;
    X(valid, j) = stimulus(src(valid));
end

validRows = isfinite(response) & all(isfinite(X), 2);
X = X(validRows, :);
y = response(validRows);
end


function splitMode = localRewardSplitMode(opts)
if isfield(opts, 'rewardDirectionMode') && logical(opts.rewardDirectionMode)
    splitMode = 'direction';
elseif isfield(opts, 'rewardRegionMode') && logical(opts.rewardRegionMode)
    splitMode = 'region';
else
    splitMode = 'none';
end
end


function designInfo = localDesignInfo(lagSamples, modelLagSec, splitMode)
lagSamples = double(lagSamples(:));
modelLagSec = double(modelLagSec(:));
if numel(modelLagSec) ~= numel(lagSamples)
    modelLagSec = NaN(size(lagSamples));
end
splitMode = lower(strtrim(char(string(splitMode))));
switch splitMode
    case 'direction'
        featureKind = [repmat("toward", numel(lagSamples), 1); repmat("away", numel(lagSamples), 1)];
        featureLagSamples = [lagSamples; lagSamples];
        featureModelLagSec = [modelLagSec; modelLagSec];
    case 'region'
        featureKind = [repmat("high", numel(lagSamples), 1); repmat("low", numel(lagSamples), 1)];
        featureLagSamples = [lagSamples; lagSamples];
        featureModelLagSec = [modelLagSec; modelLagSec];
    otherwise
        featureKind = repmat("all", numel(lagSamples), 1);
        featureLagSamples = lagSamples;
        featureModelLagSec = modelLagSec;
end
designInfo = struct( ...
    'featureLagSamples', featureLagSamples, ...
    'featureModelLagSec', featureModelLagSec, ...
    'featureKind', featureKind);
end


function modelLagSec = localInferModelLagSecFromEpisodes(E, lagSamples)
dtStepSec = NaN;
if ~isempty(E) && istable(E) && ismember('dtStepSec', E.Properties.VariableNames)
    dtStepSec = localCommonDtStepSec(E.dtStepSec);
end
if ~isfinite(dtStepSec) || dtStepSec <= 0
    dtStepSec = 1;
end
modelLagSec = double(lagSamples(:)) .* dtStepSec;
end


function [stimToward, stimAway] = localSplitStimulusByRewardDirection(stimulus, targetX, targetY, centerPx, signalMode)
stimulus = double(stimulus(:));
targetX = double(targetX(:));
targetY = double(targetY(:));
centerPx = double(centerPx(:)');
stimToward = zeros(size(stimulus));
stimAway = zeros(size(stimulus));
switch char(string(signalMode))
    case 'velocity'
        if numel(targetX) < 2 || numel(targetY) < 2
            stimToward(:) = NaN;
            stimAway(:) = NaN;
            return
        end
        n = min([numel(stimulus), numel(targetX) - 1, numel(targetY) - 1]);
        if n < 1
            stimToward(:) = NaN;
            stimAway(:) = NaN;
            return
        end
        d0 = hypot(targetX(1:n) - centerPx(1), targetY(1:n) - centerPx(2));
        d1 = hypot(targetX(2:n+1) - centerPx(1), targetY(2:n+1) - centerPx(2));
        toward = isfinite(d0) & isfinite(d1) & (d1 <= d0);
        away = isfinite(d0) & isfinite(d1) & ~toward;
        valid = false(size(stimulus));
        validStep = isfinite(d0) & isfinite(d1);
        valid(1:n) = validStep;
        stimToward(~valid) = NaN;
        stimAway(~valid) = NaN;
        idx = find(validStep);
        stimToward(idx) = stimulus(idx) .* double(toward(idx));
        stimAway(idx) = stimulus(idx) .* double(away(idx));
    otherwise
        error('tempRidge:RewardDirectionSignalMode', ...
            'Reward-direction split is currently implemented for velocity mode only.');
end
end


function [stimHigh, stimLow] = localSplitStimulusByRewardRegion(stimulus, targetX, targetY, region, signalMode)
stimulus = double(stimulus(:));
targetX = double(targetX(:));
targetY = double(targetY(:));
stimHigh = zeros(size(stimulus));
stimLow = zeros(size(stimulus));
switch char(string(signalMode))
    case 'velocity'
        if numel(targetX) < 2 || numel(targetY) < 2
            stimHigh(:) = NaN;
            stimLow(:) = NaN;
            return
        end
        n = min([numel(stimulus), numel(targetX) - 1, numel(targetY) - 1]);
        if n < 1
            stimHigh(:) = NaN;
            stimLow(:) = NaN;
            return
        end
        posX = targetX(2:n+1);
        posY = targetY(2:n+1);
        d = hypot(posX - region.centerX, posY - region.centerY);
        high = isfinite(d) & (d <= region.highRadiusPx + region.targetRadiusPx);
        validStep = isfinite(d);
        valid = false(size(stimulus));
        valid(1:n) = validStep;
        stimHigh(~valid) = NaN;
        stimLow(~valid) = NaN;
        idx = find(validStep);
        stimHigh(idx) = stimulus(idx) .* double(high(idx));
        stimLow(idx) = stimulus(idx) .* double(~high(idx));
    otherwise
        error('tempRidge:RewardRegionSignalMode', ...
            'Reward-region split is currently implemented for velocity mode only.');
end
end


function info = localRewardSplitInfo(in, opts)
info = struct('mode', localRewardSplitMode(opts), ...
    'centerX', NaN(0, 1), 'centerY', NaN(0, 1), ...
    'highRadiusPx', NaN(0, 1), 'targetRadiusPx', NaN(0, 1), ...
    'sigmaPx', NaN(0, 1), 'gaussScalar', NaN(0, 1), ...
    'minMultiplier', NaN, 'sigmaRadius', NaN);
if strcmp(info.mode, 'none')
    return
end
if ~localIsExStruct(in)
    return
end
nTrial = numel(in.Trials);
info.centerX = NaN(nTrial, 1);
info.centerY = NaN(nTrial, 1);
info.highRadiusPx = NaN(nTrial, 1);
info.targetRadiusPx = NaN(nTrial, 1);
info.sigmaPx = NaN(nTrial, 1);
info.gaussScalar = NaN(nTrial, 1);
info.minMultiplier = NaN;
info.sigmaRadius = NaN;
if strcmp(info.mode, 'region')
    info.minMultiplier = opts.rewardRegionMinMultiplier;
    info.sigmaRadius = opts.rewardRegionSigmaRadius;
    targetRadiusPx = localTargetRadiusPx(in);
    if ~isfinite(targetRadiusPx) || targetRadiusPx < 0
        error('tempRidge:RewardRegionTargetRadiusUnavailable', ...
            'opts.rewardRegionMode requires ex.exp.CoPs.graph.radius and size_mult to define the target footprint.');
    end
else
    targetRadiusPx = NaN;
end
for j = 1:nTrial
    try
        ctr = getGaussianCenterPx(in, in.Trials(j));
    catch
        ctr = [NaN NaN];
    end
    ctr = double(ctr(:)');
    if numel(ctr) >= 2 && all(isfinite(ctr(1:2)))
        info.centerX(j) = ctr(1);
        info.centerY(j) = ctr(2);
    end
    if strcmp(info.mode, 'region')
        sigmaPx = localRewardSigmaPx(in, in.Trials(j));
        gaussScalar = localGaussScalar(in, in.Trials(j));
        info.sigmaPx(j) = sigmaPx;
        info.gaussScalar(j) = gaussScalar;
        info.targetRadiusPx(j) = targetRadiusPx;
        info.highRadiusPx(j) = localRewardHighRadiusPx( ...
            sigmaPx, gaussScalar, opts.rewardRegionSigmaRadius, opts.rewardRegionMinMultiplier);
    end
end
end


function centerPx = localRewardCenterForTrial(info, trialNo)
centerPx = [NaN NaN];
if ~isstruct(info) || ~isfield(info, 'mode') || strcmp(info.mode, 'none')
    return
end
trialNo = round(double(localFirstScalar(trialNo)));
if ~isfinite(trialNo) || trialNo < 1 || trialNo > numel(info.centerX)
    return
end
centerPx = [double(info.centerX(trialNo)), double(info.centerY(trialNo))];
end


function region = localRewardRegionForTrial(info, trialNo)
region = struct('centerX', NaN, 'centerY', NaN, 'highRadiusPx', NaN, ...
    'targetRadiusPx', NaN, 'sigmaPx', NaN, 'gaussScalar', NaN, ...
    'minMultiplier', NaN, 'sigmaRadius', NaN);
if ~isstruct(info) || ~isfield(info, 'mode') || ~strcmp(info.mode, 'region')
    return
end
trialNo = round(double(localFirstScalar(trialNo)));
if ~isfinite(trialNo) || trialNo < 1 || trialNo > numel(info.centerX)
    return
end
region.centerX = double(info.centerX(trialNo));
region.centerY = double(info.centerY(trialNo));
region.highRadiusPx = double(info.highRadiusPx(trialNo));
region.targetRadiusPx = double(info.targetRadiusPx(trialNo));
region.sigmaPx = double(info.sigmaPx(trialNo));
region.gaussScalar = double(info.gaussScalar(trialNo));
region.minMultiplier = double(info.minMultiplier);
region.sigmaRadius = double(info.sigmaRadius);
end


function tf = localRewardRegionIsUsable(region)
tf = isstruct(region) && isfinite(region.centerX) && isfinite(region.centerY) && ...
    isfinite(region.highRadiusPx) && region.highRadiusPx >= 0 && ...
    isfinite(region.targetRadiusPx) && region.targetRadiusPx >= 0;
end


function radiusPx = localRewardHighRadiusPx(sigmaPx, gaussScalar, sigmaRadius, minMultiplier)
radiusPx = NaN;
if ~isfinite(sigmaPx) || sigmaPx <= 0 || ~isfinite(gaussScalar) || gaussScalar <= 1 || ...
        ~isfinite(sigmaRadius) || sigmaRadius <= 0 || ~isfinite(minMultiplier) || minMultiplier <= 1
    return
end
if gaussScalar <= minMultiplier
    radiusPx = NaN;
    return
end
requiredRewardFrac = (minMultiplier - 1) ./ (gaussScalar - 1);
requiredRewardFrac = max(realmin, min(1, requiredRewardFrac));
multRadiusPx = sigmaPx .* sqrt(-2 .* log(requiredRewardFrac));
radiusPx = min(sigmaRadius .* sigmaPx, multRadiusPx);
end


function sigmaPx = localRewardSigmaPx(ex, T)
sigmaPx = NaN;
if nargin > 1 && isfield(T, 'gauss_sigma') && isscalar(T.gauss_sigma) && isfinite(T.gauss_sigma)
    sigmaPx = double(T.gauss_sigma);
    return
end
if isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'rew') && ...
        isfield(ex.exp.CoPs.rew, 'gauss_sigma') && isscalar(ex.exp.CoPs.rew.gauss_sigma) && ...
        isfinite(ex.exp.CoPs.rew.gauss_sigma)
    sigmaPx = double(ex.exp.CoPs.rew.gauss_sigma);
end
end


function gaussScalar = localGaussScalar(ex, T)
gaussScalar = NaN;
if nargin > 1 && isfield(T, 'gauss_scalar') && isscalar(T.gauss_scalar) && isfinite(T.gauss_scalar)
    gaussScalar = double(T.gauss_scalar);
    return
end
if isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'ctl') && ...
        isfield(ex.exp.CoPs.ctl, 'gauss_scalar') && isscalar(ex.exp.CoPs.ctl.gauss_scalar) && ...
        isfinite(ex.exp.CoPs.ctl.gauss_scalar)
    gaussScalar = double(ex.exp.CoPs.ctl.gauss_scalar);
end
end


function radiusPx = localTargetRadiusPx(ex)
radiusPx = NaN;
if ~isfield(ex, 'exp') || ~isfield(ex.exp, 'CoPs') || ~isfield(ex.exp.CoPs, 'graph')
    return
end
graph = ex.exp.CoPs.graph;
if ~isfield(graph, 'radius') || ~isfield(graph, 'size_mult') || ...
        ~isscalar(graph.radius) || ~isscalar(graph.size_mult) || ...
        ~isfinite(graph.radius) || ~isfinite(graph.size_mult)
    return
end
radiusPx = double(graph.radius) .* double(graph.size_mult);
end


function def = localRewardRegionDefinition(info)
def = struct('enabled', false, 'sigmaRadius', NaN, 'minMultiplier', NaN, ...
    'medianHighRadiusPx', NaN, 'medianTargetRadiusPx', NaN, ...
    'medianSigmaPx', NaN, 'medianGaussScalar', NaN);
if ~isstruct(info) || ~isfield(info, 'mode') || ~strcmp(info.mode, 'region')
    return
end
def.enabled = true;
def.sigmaRadius = info.sigmaRadius;
def.minMultiplier = info.minMultiplier;
def.medianHighRadiusPx = median(info.highRadiusPx, 'omitnan');
def.medianTargetRadiusPx = median(info.targetRadiusPx, 'omitnan');
def.medianSigmaPx = median(info.sigmaPx, 'omitnan');
def.medianGaussScalar = median(info.gaussScalar, 'omitnan');
end


function [betaToward, betaAway] = localRewardDirectionBetas(beta, designInfo, plotOrder)
beta = double(beta(:));
featureKind = string(designInfo.featureKind(:));
nLag = numel(plotOrder);
betaTowardRaw = NaN(nLag, 1);
betaAwayRaw = NaN(nLag, 1);
towardIdx = find(featureKind == "toward");
awayIdx = find(featureKind == "away");
if numel(towardIdx) == nLag
    betaTowardRaw = beta(towardIdx);
end
if numel(awayIdx) == nLag
    betaAwayRaw = beta(awayIdx);
end
betaToward = betaTowardRaw(plotOrder)';
betaAway = betaAwayRaw(plotOrder)';
end


function [betaHigh, betaLow] = localRewardRegionBetas(beta, designInfo, plotOrder)
beta = double(beta(:));
featureKind = string(designInfo.featureKind(:));
nLag = numel(plotOrder);
betaHighRaw = NaN(nLag, 1);
betaLowRaw = NaN(nLag, 1);
highIdx = find(featureKind == "high");
lowIdx = find(featureKind == "low");
if numel(highIdx) == nLag
    betaHighRaw = beta(highIdx);
end
if numel(lowIdx) == nLag
    betaLowRaw = beta(lowIdx);
end
betaHigh = betaHighRaw(plotOrder)';
betaLow = betaLowRaw(plotOrder)';
end


function T = localRewardDirectionGainTable(betaToward, betaAway, plotLagSec, opts)
labels = ["toward"; "away"];
betaCell = {double(betaToward(:)); double(betaAway(:))};
peakBeta = NaN(2, 1);
areaBeta = NaN(2, 1);
absAreaBeta = NaN(2, 1);
gainWindow = localRewardDirectionGainWindow(plotLagSec, opts);
for i = 1:2
    b = betaCell{i};
    keep = gainWindow(:) & isfinite(b);
    if ~any(keep)
        continue
    end
    peakBeta(i) = max(b(keep), [], 'omitnan');
    areaBeta(i) = sum(b(keep), 'omitnan');
    absAreaBeta(i) = sum(abs(b(keep)), 'omitnan');
end
T = table(labels, peakBeta, areaBeta, absAreaBeta, ...
    'VariableNames', {'direction','peakBeta','areaBeta','absAreaBeta'});
end


function keep = localRewardDirectionGainWindow(plotLagSec, opts)
plotLagSec = double(plotLagSec(:));
tw = opts.rewardDirectionGainWindowSec;
if isempty(tw)
    keep = plotLagSec <= 0;
else
    keep = plotLagSec >= tw(1) & plotLagSec <= tw(2);
end
if ~any(keep)
    keep = isfinite(plotLagSec);
end
end


function idx = localRewardDirectionIndex(T)
idx = NaN;
if isempty(T) || height(T) < 2 || ~ismember('areaBeta', T.Properties.VariableNames)
    return
end
toward = T.areaBeta(strcmp(string(T.direction), "toward"));
away = T.areaBeta(strcmp(string(T.direction), "away"));
if isempty(toward) || isempty(away) || ~isfinite(toward) || ~isfinite(away)
    return
end
denom = abs(toward) + abs(away);
if denom <= eps
    return
end
idx = (toward - away) ./ denom;
end


function T = localEmptyRewardDirectionGainTable()
T = table(strings(0, 1), NaN(0, 1), NaN(0, 1), NaN(0, 1), ...
    'VariableNames', {'direction','peakBeta','areaBeta','absAreaBeta'});
end


function T = localRewardRegionGainTable(betaHigh, betaLow, plotLagSec, opts)
labels = ["high"; "low"];
betaCell = {double(betaHigh(:)); double(betaLow(:))};
peakBeta = NaN(2, 1);
areaBeta = NaN(2, 1);
absAreaBeta = NaN(2, 1);
gainWindow = localRewardRegionGainWindow(plotLagSec, opts);
for i = 1:2
    b = betaCell{i};
    keep = gainWindow(:) & isfinite(b);
    if ~any(keep)
        continue
    end
    peakBeta(i) = max(b(keep), [], 'omitnan');
    areaBeta(i) = sum(b(keep), 'omitnan');
    absAreaBeta(i) = sum(abs(b(keep)), 'omitnan');
end
T = table(labels, peakBeta, areaBeta, absAreaBeta, ...
    'VariableNames', {'region','peakBeta','areaBeta','absAreaBeta'});
end


function keep = localRewardRegionGainWindow(plotLagSec, opts)
plotLagSec = double(plotLagSec(:));
tw = opts.rewardRegionGainWindowSec;
if isempty(tw)
    keep = plotLagSec <= 0;
else
    keep = plotLagSec >= tw(1) & plotLagSec <= tw(2);
end
if ~any(keep)
    keep = isfinite(plotLagSec);
end
end


function idx = localRewardRegionIndex(T)
idx = NaN;
if isempty(T) || height(T) < 2 || ~ismember('areaBeta', T.Properties.VariableNames)
    return
end
high = T.areaBeta(strcmp(string(T.region), "high"));
low = T.areaBeta(strcmp(string(T.region), "low"));
if isempty(high) || isempty(low) || ~isfinite(high) || ~isfinite(low)
    return
end
denom = abs(high) + abs(low);
if denom <= eps
    return
end
idx = (high - low) ./ denom;
end


function T = localEmptyRewardRegionGainTable()
T = table(strings(0, 1), NaN(0, 1), NaN(0, 1), NaN(0, 1), ...
    'VariableNames', {'region','peakBeta','areaBeta','absAreaBeta'});
end


function [X, y] = localLaggedEventDesign(stimulus, response, anchorIdx, lagSamples)
stimulus = double(stimulus(:));
response = double(response);
anchorIdx = round(double(anchorIdx));
src = anchorIdx - lagSamples(:)';
valid = src >= 1 & src <= numel(stimulus);
if ~isfinite(response) || ~all(valid)
    X = NaN(0, numel(lagSamples));
    y = NaN(0, 1);
    return
end
X = reshape(stimulus(src), 1, []);
if any(~isfinite(X))
    X = NaN(0, numel(lagSamples));
    y = NaN(0, 1);
    return
end
y = response;
end


function fit = localFitAxisRidge(X, y, trialId, chunkId, lagSamples, opts)
fit = localEmptyFit(lagSamples);
y = y(:);
trialId = trialId(:);
chunkId = chunkId(:);
valid = isfinite(y) & all(isfinite(X), 2);
X = X(valid, :);
y = y(valid);
trialId = trialId(valid);
chunkId = chunkId(valid);

fit.nObs = numel(y);
fit.nTrials = numel(unique(trialId(isfinite(trialId))));
fit.nChunks = numel(unique(chunkId(isfinite(chunkId))));
if fit.nObs < opts.minSamples || size(X, 2) == 0
    return
end

[foldId, nFolds] = localMakeFolds(fit.nObs, trialId, chunkId, opts);
lambdaGrid = localResolveFitLambdas(opts.lambda, opts.lambdaGrid);
cvMse = NaN(size(lambdaGrid));
if isempty(opts.lambda) && nFolds >= 2
    for i = 1:numel(lambdaGrid)
        cvMse(i) = localCrossValMse(X, y, foldId, nFolds, lambdaGrid(i), opts.standardize);
    end
    if any(isfinite(cvMse))
        [~, bestIdx] = min(cvMse);
    else
        bestIdx = ceil(numel(lambdaGrid) / 2);
    end
else
    bestIdx = 1;
end
lambda = lambdaGrid(bestIdx);

model = localFitRidgeModel(X, y, lambda, opts.standardize);
yHat = localPredictRidgeModel(model, X);
fit.beta = model.beta(:);
fit.betaStd = model.betaStd(:);
fit.intercept = model.intercept;
fit.lambda = lambda;
fit.r2 = localR2(y, yHat);
fit.residSd = localResidualSd(y, yHat);
fit.residSdDeg = localConvertSignalPxToDeg(fit.residSd, opts);
fit.yHat = yHat;
fit.y = y;
fit.trial = trialId;
fit.chunk = chunkId;
fit.xMean = model.xMean;
fit.xScale = model.xScale;
fit.yMean = model.yMean;
fit.cvMse = cvMse;
fit.lambdaGrid = lambdaGrid;
fit.foldId = foldId;

if nFolds >= 2
    cvPred = localCrossValPred(X, y, foldId, nFolds, lambda, opts.standardize);
    fit.cvYHat = cvPred;
    fit.cvR2 = localR2(y(isfinite(cvPred)), cvPred(isfinite(cvPred)));
    fit.cvResidSd = localResidualSd(y, cvPred);
    fit.cvResidSdDeg = localConvertSignalPxToDeg(fit.cvResidSd, opts);
end
end


function dropout = localLagDropoutTable(X, y, trialId, chunkId, lagSamples, modelLagSec, fullFit, opts)
blocks = opts.lagDropoutBlocksSec;
nBlock = size(blocks, 1);
dropout = localEmptyLagDropoutTable(nBlock);
if nBlock == 0
    return
end

plotLagSec = -double(modelLagSec(:))';
labels = string(opts.lagDropoutBlockLabels(:));
tol = 1e-10;
for b = 1:nBlock
    lagLo = blocks(b, 1);
    lagHi = blocks(b, 2);
    dropMask = plotLagSec >= lagLo - tol & plotLagSec <= lagHi + tol;
    keepMask = ~dropMask;

    dropout.blockLabel(b) = labels(b);
    dropout.lagStartSec(b) = lagLo;
    dropout.lagEndSec(b) = lagHi;
    dropout.nDroppedLags(b) = nnz(dropMask);
    dropout.nKeptLags(b) = nnz(keepMask);
    dropout.droppedLagSec{b} = sort(plotLagSec(dropMask));
    dropout.cvR2Full(b) = fullFit.cvR2;
    dropout.r2Full(b) = fullFit.r2;
    dropout.lambdaFull(b) = fullFit.lambda;
    dropout.nObs(b) = fullFit.nObs;

    if nnz(dropMask) == 0 || nnz(keepMask) == 0 || isempty(y)
        continue
    end

    dropFit = localFitAxisRidge(X(:, keepMask), y, trialId, chunkId, lagSamples(keepMask), opts);
    dropout.cvR2Dropout(b) = dropFit.cvR2;
    dropout.r2Dropout(b) = dropFit.r2;
    dropout.lambdaDropout(b) = dropFit.lambda;
    if isfinite(fullFit.cvR2) && isfinite(dropFit.cvR2)
        dropout.cvR2Loss(b) = fullFit.cvR2 - dropFit.cvR2;
    end
    if isfinite(fullFit.r2) && isfinite(dropFit.r2)
        dropout.r2Loss(b) = fullFit.r2 - dropFit.r2;
    end
end
end


function dropout = localEmptyLagDropoutTable(nBlock)
if nargin < 1
    nBlock = 0;
end
dropout = table( ...
    strings(nBlock, 1), ...
    NaN(nBlock, 1), ...
    NaN(nBlock, 1), ...
    NaN(nBlock, 1), ...
    NaN(nBlock, 1), ...
    cell(nBlock, 1), ...
    NaN(nBlock, 1), ...
    NaN(nBlock, 1), ...
    NaN(nBlock, 1), ...
    NaN(nBlock, 1), ...
    NaN(nBlock, 1), ...
    NaN(nBlock, 1), ...
    NaN(nBlock, 1), ...
    NaN(nBlock, 1), ...
    NaN(nBlock, 1), ...
    'VariableNames', {'blockLabel','lagStartSec','lagEndSec','nDroppedLags','nKeptLags', ...
    'droppedLagSec','cvR2Full','cvR2Dropout','cvR2Loss','r2Full','r2Dropout','r2Loss', ...
    'lambdaFull','lambdaDropout','nObs'});
end


function fit = localEmptyFit(lagSamples)
fit = struct();
fit.beta = NaN(numel(lagSamples), 1);
fit.betaStd = NaN(numel(lagSamples), 1);
fit.intercept = NaN;
fit.lambda = NaN;
fit.r2 = NaN;
fit.cvR2 = NaN;
fit.residSd = NaN;
fit.cvResidSd = NaN;
fit.residSdDeg = NaN;
fit.cvResidSdDeg = NaN;
fit.nObs = 0;
fit.nTrials = 0;
fit.nChunks = 0;
fit.y = NaN(0, 1);
fit.yHat = NaN(0, 1);
fit.cvYHat = NaN(0, 1);
fit.trial = NaN(0, 1);
fit.chunk = NaN(0, 1);
fit.xMean = NaN(1, numel(lagSamples));
fit.xScale = NaN(1, numel(lagSamples));
fit.yMean = NaN;
fit.cvMse = NaN(0, 1);
fit.lambdaGrid = NaN(0, 1);
fit.foldId = NaN(0, 1);
end


function model = localFitRidgeModel(X, y, lambda, standardize)
X = double(X);
y = double(y(:));
n = size(X, 1);
p = size(X, 2);

xMean = mean(X, 1);
if standardize
    xScale = std(X, 0, 1);
    xScale(~isfinite(xScale) | xScale <= eps) = 1;
else
    xScale = ones(1, p);
end
Xz = (X - xMean) ./ xScale;
yMean = mean(y);
yc = y - yMean;

lambda = max(0, double(localFirstScalar(lambda)));
if lambda == 0
    betaStd = pinv(Xz) * yc;
else
    betaStd = (Xz' * Xz + n * lambda * eye(p)) \ (Xz' * yc);
end
beta = betaStd ./ xScale(:);
intercept = yMean - xMean * beta;

model = struct();
model.beta = beta;
model.betaStd = betaStd;
model.intercept = intercept;
model.xMean = xMean;
model.xScale = xScale;
model.yMean = yMean;
model.lambda = lambda;
end


function yHat = localPredictRidgeModel(model, X)
yHat = model.intercept + double(X) * model.beta;
end


function mse = localCrossValMse(X, y, foldId, nFolds, lambda, standardize)
pred = localCrossValPred(X, y, foldId, nFolds, lambda, standardize);
valid = isfinite(pred);
if ~any(valid)
    mse = NaN;
else
    err = y(valid) - pred(valid);
    mse = mean(err .^ 2, 'omitnan');
end
end


function pred = localCrossValPred(X, y, foldId, nFolds, lambda, standardize)
pred = NaN(size(y));
for f = 1:nFolds
    test = foldId == f;
    train = ~test & isfinite(foldId);
    if nnz(test) < 1 || nnz(train) < 2
        continue
    end
    model = localFitRidgeModel(X(train, :), y(train), lambda, standardize);
    pred(test) = localPredictRidgeModel(model, X(test, :));
end
end


function [foldId, nFolds] = localMakeFolds(nObs, trialId, chunkId, opts)
nFoldsRequested = max(2, round(double(localFirstScalar(opts.cvFolds))));
switch opts.cvMode
    case 'trial'
        unitId = trialId(:);
    case 'chunk'
        unitId = chunkId(:);
    case 'observation'
        unitId = (1:nObs)';
end

if numel(unique(unitId(isfinite(unitId)))) < 2 && ~strcmp(opts.cvMode, 'observation')
    unitId = (1:nObs)';
end

unitVals = unique(unitId(isfinite(unitId)), 'stable');
nUnits = numel(unitVals);
nFolds = min(nFoldsRequested, nUnits);
foldId = NaN(nObs, 1);
if nFolds < 2
    return
end

if isfinite(opts.cvSeed)
    prevRng = rng;
    cleanupObj = onCleanup(@() rng(prevRng));
    rng(opts.cvSeed);
end
perm = randperm(nUnits);
unitFold = zeros(nUnits, 1);
unitFold(perm) = mod(0:nUnits-1, nFolds) + 1;

for i = 1:nUnits
    foldId(unitId == unitVals(i)) = unitFold(i);
end
end


function r2 = localR2(y, yHat)
y = double(y(:));
yHat = double(yHat(:));
valid = isfinite(y) & isfinite(yHat);
if nnz(valid) < 2
    r2 = NaN;
    return
end
y = y(valid);
yHat = yHat(valid);
sst = sum((y - mean(y)).^2);
if sst <= eps
    r2 = NaN;
else
    r2 = 1 - sum((y - yHat).^2) ./ sst;
end
end


function sd = localResidualSd(y, yHat)
y = double(y(:));
yHat = double(yHat(:));
valid = isfinite(y) & isfinite(yHat);
if nnz(valid) < 2
    sd = NaN;
else
    sd = std(y(valid) - yHat(valid), 0);
end
end


function valueDeg = localConvertSignalPxToDeg(valuePx, opts)
valueDeg = NaN(size(valuePx));
if ~isfield(opts, 'setup') || isempty(opts.setup) || ~isfinite(valuePx)
    return
end
try
    valueDeg = px2deg(valuePx, opts.setup);
catch
    valueDeg = NaN(size(valuePx));
end
end


function setup = localResolveAnalysisSetup(in, opts)
setup = [];
if isfield(opts, 'setup') && ~isempty(opts.setup)
    setup = opts.setup;
elseif localIsExStruct(in) && isfield(in, 'setup')
    setup = in.setup;
end
end


function lagWindowSec = localValidateLagWindow(lagWindowSec)
lagWindowSec = double(lagWindowSec(:)');
if numel(lagWindowSec) ~= 2 || any(~isfinite(lagWindowSec)) || lagWindowSec(1) > lagWindowSec(2)
    error('tempRidge:BadLagWindow', 'opts.lagWindowSec must be a finite [min max] vector.');
end
end


function blocks = localValidateLagDropoutBlocks(blocks)
if isempty(blocks)
    blocks = zeros(0, 2);
    return
end
if ischar(blocks) || isstring(blocks) || iscell(blocks)
    error('tempRidge:BadLagDropoutBlocks', ...
        'opts.lagDropoutBlocksSec must be empty or an Nx2 numeric matrix.');
end
blocks = double(blocks);
if isvector(blocks) && numel(blocks) == 2
    blocks = blocks(:)';
end
if ~ismatrix(blocks) || size(blocks, 2) ~= 2 || any(~isfinite(blocks(:)))
    error('tempRidge:BadLagDropoutBlocks', ...
        'opts.lagDropoutBlocksSec must be empty or an Nx2 finite numeric matrix.');
end
blocks = sort(blocks, 2);
end


function labels = localValidateLagDropoutLabels(labels, blocks)
nBlock = size(blocks, 1);
if nBlock == 0
    labels = strings(0, 1);
    return
end
if isempty(labels)
    labels = strings(nBlock, 1);
    for i = 1:nBlock
        labels(i) = sprintf('%.3g to %.3g s', blocks(i, 1), blocks(i, 2));
    end
    return
end
labels = string(labels(:));
if numel(labels) ~= nBlock
    error('tempRidge:BadLagDropoutLabels', ...
        'opts.lagDropoutBlockLabels must have one label per lag dropout block.');
end
end


function tw = localValidateOptionalTimeWindow(value, fieldName)
if nargin < 2
    fieldName = 'timeWindow';
end
if isempty(value)
    tw = [];
    return
end
tw = double(value(:)');
if numel(tw) ~= 2 || any(~isfinite(tw)) || tw(1) > tw(2)
    error('tempRidge:BadTimeWindow', 'opts.%s must be empty or a finite [min max] vector.', fieldName);
end
end


function lagSamples = localLagSamples(lagWindowSec, dtStepSec)
tol = 1e-9;
minLag = ceil(lagWindowSec(1) / dtStepSec - tol);
maxLag = floor(lagWindowSec(2) / dtStepSec + tol);
if minLag > maxLag
    error('tempRidge:BadLagWindow', 'opts.lagWindowSec contains no valid step lags.');
end
lagSamples = minLag:maxLag;
end


function lambdaGrid = localValidateLambdaGrid(lambdaGrid)
lambdaGrid = double(lambdaGrid(:));
lambdaGrid = lambdaGrid(isfinite(lambdaGrid) & lambdaGrid >= 0);
lambdaGrid = unique(lambdaGrid, 'stable');
if isempty(lambdaGrid)
    error('tempRidge:BadLambdaGrid', 'opts.lambdaGrid must contain at least one finite nonnegative value.');
end
end


function lambdaGrid = localResolveFitLambdas(lambda, lambdaGrid)
if isempty(lambda)
    lambdaGrid = double(lambdaGrid(:));
else
    lambda = double(localFirstScalar(lambda));
    if ~isfinite(lambda) || lambda < 0
        error('tempRidge:BadLambda', 'opts.lambda must be empty or a finite nonnegative scalar.');
    end
    lambdaGrid = lambda;
end
end


function tf = localIsExStruct(in)
tf = isstruct(in) && isfield(in, 'Trials') && ~isempty(in.Trials);
end


function saccades = localBuildSaccadeEventTable(in, base, opts)
rows = cell(1000, 1);
rowCount = 0;
if strcmp(base.inputMode, 'ex')
    for g = 1:numel(base.trialGroups)
        trialList = base.trialGroups{g};
        for i = 1:numel(trialList)
            trialIdx = trialList(i);
            samples = localPrepareExTrialSamples(in, trialIdx, opts);
            [newRows, nNew] = localBuildSaccadeRowsFromSamples(samples, g, base.groupLabels(g), trialIdx, NaN, opts);
            if nNew == 0
                continue
            end
            if rowCount + nNew > numel(rows)
                rows{rowCount + nNew, 1} = [];
            end
            rows(rowCount + (1:nNew)) = newRows(1:nNew);
            rowCount = rowCount + nNew;
        end
    end
elseif strcmp(base.inputMode, 'tracking')
    setup = localResolveSetupForSaccades(opts);
    opts.setup = setup;
    for g = 1:numel(base.trialGroups)
        trialList = base.trialGroups{g};
        trialMask = ismember(double(in.trial), trialList);
        groupTable = in(trialMask, :);
        if isempty(groupTable)
            continue
        end
        [groupIdx, intervalInfo] = findgroups(groupTable(:, {'trial', 'intervalNo'}));
        for i = 1:height(intervalInfo)
            episode = groupTable(groupIdx == i, :);
            samples = localPrepareTrackingEpisodeSamples(episode, opts);
            trialIdx = double(intervalInfo.trial(i));
            intervalNo = double(intervalInfo.intervalNo(i));
            [newRows, nNew] = localBuildSaccadeRowsFromSamples(samples, g, base.groupLabels(g), trialIdx, intervalNo, opts);
            if nNew == 0
                continue
            end
            if rowCount + nNew > numel(rows)
                rows{rowCount + nNew, 1} = [];
            end
            rows(rowCount + (1:nNew)) = newRows(1:nNew);
            rowCount = rowCount + nNew;
        end
    end
else
    error('tempRidge:BadInputMode', 'Unsupported input mode for saccade analysis: %s.', base.inputMode);
end

if rowCount == 0
    saccades = table();
else
    saccades = vertcat(rows{1:rowCount});
end
end


function samples = localPrepareExTrialSamples(ex, trialIdx, opts)
samples = localEmptySamples();
if trialIdx < 1 || trialIdx > numel(ex.Trials)
    return
end
T = ex.Trials(trialIdx);
[xPx, yPx, tRel, tAbs, valid] = reconstructEyePx(ex, T, opts.useEyeTime, opts);
[targetX, targetY, ~, ~, stepIdx] = mapTargetsByStep(ex, T, tRel);
if isempty(tRel)
    return
end

goMask = true(size(tRel));
if opts.onlyGoState && isfield(T, 'times') && isfield(T.times, 'stimOn') && isfield(T, 'TrialEnd')
    goMask = tAbs >= T.times.stimOn & tAbs <= T.TrialEnd;
end
[xPx, yPx, targetX, targetY, stepIdx, tRel, valid] = localApplySampleMask( ...
    goMask, xPx, yPx, targetX, targetY, stepIdx, tRel, valid);

truncateFromStep = double(localFirstScalar(opts.truncateTrialFromStep));
if isfinite(truncateFromStep) && truncateFromStep > 0
    keepMask = isfinite(stepIdx) & stepIdx >= truncateFromStep;
    [xPx, yPx, targetX, targetY, stepIdx, tRel, valid] = localApplySampleMask( ...
        keepMask, xPx, yPx, targetX, targetY, stepIdx, tRel, valid);
end

timeWindowSec = localTimeWindow(opts.timeWindowSec);
if ~isempty(timeWindowSec)
    keepMask = tRel >= timeWindowSec(1) & tRel <= timeWindowSec(2);
    [xPx, yPx, targetX, targetY, stepIdx, tRel, valid] = localApplySampleMask( ...
        keepMask, xPx, yPx, targetX, targetY, stepIdx, tRel, valid);
end

if isfield(ex, 'setup') && isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'graph')
    [texBounds, ~] = localTextureBounds(ex.setup.screenRect, ex.exp.CoPs.graph);
    insideTexture = xPx >= texBounds.xMin & xPx <= texBounds.xMax & ...
        yPx >= texBounds.yMin & yPx <= texBounds.yMax;
    valid = valid & insideTexture;
end
xPx(~valid) = NaN;
yPx(~valid) = NaN;

dtSec = 1 / inferFs(ex);
[xPx, yPx] = preprocessGazeForCcgCoPs( ...
    xPx, yPx, dtSec, opts.interpBlinkSec, opts.saccadeLowpassHz);

samples.xPx = xPx;
samples.yPx = yPx;
samples.targetX = targetX;
samples.targetY = targetY;
samples.stepIdx = stepIdx;
samples.tRel = tRel;
samples.dtSec = dtSec;
samples.setup = ex.setup;
end


function samples = localPrepareTrackingEpisodeSamples(episode, opts)
samples = localEmptySamples();
if isempty(episode)
    return
end
if ismember('sampleIdx', episode.Properties.VariableNames)
    episode = sortrows(episode, {'sampleIdx', 'step'});
else
    episode = sortrows(episode, {'tFromTrackingOnsetSec', 'step'});
end

sampleMask = true(height(episode), 1);
if logical(opts.useTrackingOnly) && ismember('isTracking', episode.Properties.VariableNames)
    sampleMask = double(episode.isTracking) >= 1;
end
truncateFromStep = double(localFirstScalar(opts.truncateTrialFromStep));
if isfinite(truncateFromStep) && truncateFromStep > 0
    sampleMask = sampleMask & isfinite(episode.step) & double(episode.step) >= truncateFromStep;
end
timeWindowSec = localTimeWindow(opts.timeWindowSec);
if ~isempty(timeWindowSec)
    sampleMask = sampleMask & episode.tFromTrackingOnsetSec >= timeWindowSec(1) & ...
        episode.tFromTrackingOnsetSec <= timeWindowSec(2);
end
episode = episode(sampleMask, :);
if height(episode) < 2
    return
end

dtFallback = localResolveStepDt(double(episode.tFromTrackingOnsetSec), NaN);
dtSec = localResolveSampleDtFromEpisode(episode, dtFallback);
xPx = double(episode.xPx(:));
yPx = double(episode.yPx(:));
[xPx, yPx] = preprocessGazeForCcgCoPs( ...
    xPx, yPx, dtSec, opts.interpBlinkSec, opts.saccadeLowpassHz);

samples.xPx = xPx;
samples.yPx = yPx;
samples.targetX = double(episode.trackedTargetX(:));
samples.targetY = double(episode.trackedTargetY(:));
samples.stepIdx = double(episode.step(:));
samples.tRel = double(episode.tFromTrackingOnsetSec(:));
samples.dtSec = dtSec;
samples.setup = opts.setup;
end


function [rows, rowCount] = localBuildSaccadeRowsFromSamples(samples, groupNo, groupLabel, trialIdx, intervalNo, opts)
rows = cell(0, 1);
rowCount = 0;
if isempty(samples.tRel) || numel(samples.tRel) < 2
    return
end
if isempty(samples.setup)
    return
end
stepTable = localAggregateToSteps(samples.xPx, samples.yPx, samples.targetX, samples.targetY, ...
    samples.stepIdx, samples.tRel);
if isempty(stepTable) || height(stepTable) < 3
    return
end
dtStepSec = localResolveStepDt(stepTable.tRelSec, NaN);
if ~isfinite(dtStepSec) || dtStepSec <= 0
    return
end

saccParams = localBuildSaccadeParams(samples.dtSec, opts);
[saccStarts, saccStops, speedDegPerSec] = detectTrackingSaccadesCoPs( ...
    samples.xPx, samples.yPx, samples.dtSec, samples.setup, saccParams);
if isempty(saccStarts)
    return
end

[stimX, stimY, anchorOffset] = localSaccadeStimulus(stepTable, dtStepSec, opts);
responseMode = localResolveSaccadeResponse(opts);
rows = cell(numel(saccStarts), 1);
for i = 1:numel(saccStarts)
    i0 = saccStarts(i);
    i1 = saccStops(i);
    if i0 < 1 || i1 > numel(samples.xPx) || i1 < i0
        continue
    end
    startPos = [double(samples.xPx(i0)), double(samples.yPx(i0))];
    stopPos = [double(samples.xPx(i1)), double(samples.yPx(i1))];
    if any(~isfinite(startPos)) || any(~isfinite(stopPos))
        continue
    end
    onsetStep = double(samples.stepIdx(i0));
    stopStep = double(samples.stepIdx(i1));
    stepRow = find(double(stepTable.step) == onsetStep, 1, 'first');
    if isempty(stepRow)
        continue
    end
    anchorIdx = stepRow + anchorOffset;
    if ~isfinite(anchorIdx)
        continue
    end
    switch responseMode
        case 'delta'
            response = stopPos - startPos;
        case 'endpoint'
            response = stopPos;
    end
    saccAmpPx = hypot(stopPos(1) - startPos(1), stopPos(2) - startPos(2));
    if ~(isfinite(saccAmpPx) && saccAmpPx > 0)
        continue
    end
    rowCount = rowCount + 1;
    rows{rowCount, 1} = table( ...
        groupNo, string(groupLabel), double(trialIdx), double(intervalNo), rowCount, ...
        double(i0), double(i1), double(samples.tRel(i0)), double(samples.tRel(i1)), ...
        onsetStep, stopStep, double(anchorIdx), dtStepSec, ...
        startPos(1), startPos(2), stopPos(1), stopPos(2), ...
        response(1), response(2), saccAmpPx, px2deg(saccAmpPx, samples.setup), ...
        max(speedDegPerSec(i0:i1), [], 'omitnan'), ...
        {stimX(:)'}, {stimY(:)'}, string(responseMode), string(opts.signalMode), ...
        'VariableNames', {'group','groupLabel','trial','intervalNo','saccNo', ...
        'saccStartSample','saccStopSample','saccStartTimeSec','saccStopTimeSec', ...
        'saccStartStep','saccStopStep','anchorIdx','dtStepSec', ...
        'startX','startY','stopX','stopY','responseX','responseY', ...
        'saccAmpPx','saccAmpDeg','peakSpeedDegPerSec', ...
        'stimX','stimY','saccadeResponse','signalMode'});
end
rows = rows(1:rowCount);
end


function samples = localEmptySamples()
samples = struct('xPx', [], 'yPx', [], 'targetX', [], 'targetY', [], ...
    'stepIdx', [], 'tRel', [], 'dtSec', NaN, 'setup', []);
end


function [xPx, yPx, targetX, targetY, stepIdx, tRel, valid] = localApplySampleMask( ...
    mask, xPx, yPx, targetX, targetY, stepIdx, tRel, valid)
mask = logical(mask(:));
xPx = xPx(mask);
yPx = yPx(mask);
targetX = targetX(mask);
targetY = targetY(mask);
stepIdx = stepIdx(mask);
tRel = tRel(mask);
valid = valid(mask);
end


function [stimX, stimY, anchorOffset] = localSaccadeStimulus(stepTable, dtStepSec, opts)
switch opts.signalMode
    case 'velocity'
        stimX = diff(double(stepTable.targetX(:))) ./ dtStepSec;
        stimY = diff(double(stepTable.targetY(:))) ./ dtStepSec;
        anchorOffset = -1;
    case 'position'
        stimX = double(stepTable.targetX(:));
        stimY = double(stepTable.targetY(:));
        anchorOffset = 0;
end
end


function responseMode = localResolveSaccadeResponse(opts)
responseMode = char(string(opts.saccadeResponse));
if strcmp(responseMode, 'auto')
    switch opts.signalMode
        case 'velocity'
            responseMode = 'delta';
        case 'position'
            responseMode = 'endpoint';
    end
end
end


function params = localBuildSaccadeParams(dtSec, opts)
params = struct();
params.preSaccadeWindowFrames = 3;
params.speedThreshDegPerSec = double(localFirstScalar(opts.speedThreshDegPerSec));
params.minAmpDeg = double(localFirstScalar(opts.minAmpDeg));
params.minDurSec = double(localFirstScalar(opts.minDurSec));
params.maxDurSec = double(localFirstScalar(opts.maxDurSec));
params.smoothFrames = max(1, round(double(localFirstScalar(opts.smoothFrames))));
if ~isfinite(dtSec) || dtSec <= 0
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


function setup = localResolveSetupForSaccades(opts)
setup = [];
if isfield(opts, 'setup') && ~isempty(opts.setup)
    setup = opts.setup;
end
if isempty(setup)
    error('tempRidge:MissingSetup', ...
        'opts.setup is required for saccade-mode tracking-table input.');
end
end


function stepTable = localAggregateToSteps(xPx, yPx, targetX, targetY, stepIdx, tRelSec)
valid = isfinite(stepIdx) & isfinite(targetX) & isfinite(targetY);
if ~any(valid)
    stepTable = table();
    return
end
T = table(double(stepIdx(valid)), double(tRelSec(valid)), double(xPx(valid)), double(yPx(valid)), ...
    double(targetX(valid)), double(targetY(valid)), ...
    'VariableNames', {'step','tRelSec','xPx','yPx','targetX','targetY'});
[stepGroups, ~] = findgroups(T.step);
stepTable = table();
stepTable.step = splitapply(@(x) x(1), T.step, stepGroups);
stepTable.tRelSec = splitapply(@mean, T.tRelSec, stepGroups);
stepTable.xPx = splitapply(@(x) mean(x, 'omitnan'), T.xPx, stepGroups);
stepTable.yPx = splitapply(@(x) mean(x, 'omitnan'), T.yPx, stepGroups);
stepTable.targetX = splitapply(@(x) mean(x, 'omitnan'), T.targetX, stepGroups);
stepTable.targetY = splitapply(@(x) mean(x, 'omitnan'), T.targetY, stepGroups);
stepTable = sortrows(stepTable, 'step');
end


function dtStep = localResolveStepDt(tRelSec, fallbackDtSec)
if numel(tRelSec) >= 2
    dtCandidates = diff(tRelSec(:));
    dtCandidates = dtCandidates(isfinite(dtCandidates) & dtCandidates > 0);
    if ~isempty(dtCandidates)
        dtStep = median(dtCandidates, 'omitnan');
        return
    end
end
dtStep = fallbackDtSec;
end


function dtSec = localResolveSampleDtFromEpisode(episode, fallbackDtSec)
if ismember('sampleIdx', episode.Properties.VariableNames) && ...
        ismember('tFromTrackingOnsetSec', episode.Properties.VariableNames)
    sampleIdx = double(episode.sampleIdx(:));
    tRelSec = double(episode.tFromTrackingOnsetSec(:));
    valid = isfinite(sampleIdx) & isfinite(tRelSec);
    sampleIdx = sampleIdx(valid);
    tRelSec = tRelSec(valid);
    if numel(sampleIdx) >= 2
        ds = diff(sampleIdx);
        dt = diff(tRelSec);
        good = ds > 0 & isfinite(dt);
        if any(good)
            dtPerSample = dt(good) ./ ds(good);
            dtPerSample = dtPerSample(isfinite(dtPerSample) & dtPerSample > 0);
            if ~isempty(dtPerSample)
                dtSec = median(dtPerSample, 'omitnan');
                return
            end
        end
    end
end
if isfinite(fallbackDtSec) && fallbackDtSec > 0
    dtSec = fallbackDtSec;
else
    dtSec = 1 / 60;
end
end


function tw = localTimeWindow(value)
tw = [];
if isempty(value) || ~isnumeric(value) || numel(value) < 2
    return
end
tw = double(value(1:2));
if any(~isfinite(tw))
    tw = [];
    return
end
tw = sort(tw(:))';
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


function dt = localCommonDtStepSec(dtVals)
dtVals = double(dtVals(:));
dtVals = dtVals(isfinite(dtVals) & dtVals > 0);
if isempty(dtVals)
    dt = NaN;
else
    dt = median(dtVals, 'omitnan');
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


function localPlotTempRidge(groups, plotLagSec, opts, groupLabels)
nGroup = numel(groups);
colors = opts.colors;
if isempty(colors)
    colors = lines(nGroup);
else
    colors = double(colors);
    if size(colors, 1) < nGroup || size(colors, 2) ~= 3
        error('tempRidge:BadColors', 'opts.colors must be an nGroup x 3 RGB array.');
    end
end

if opts.newFigure
    figure;
end
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile;
localPlotAxis(groups, plotLagSec, colors, groupLabels, 'x', opts);
nexttile;
localPlotAxis(groups, plotLagSec, colors, groupLabels, 'y', opts);
sgtitle(sprintf('Temporal ridge (%s)', opts.signalMode), 'Interpreter', 'none');
end


function localPlotAxis(groups, plotLagSec, colors, groupLabels, axisName, opts)
hold on;
plotHandles = gobjects(0, 1);
legendLabels = strings(0, 1);
useRewardDirection = isfield(opts, 'rewardDirectionMode') && logical(opts.rewardDirectionMode);
useRewardRegion = isfield(opts, 'rewardRegionMode') && logical(opts.rewardRegionMode);
for g = 1:numel(groups)
    switch axisName
        case 'x'
            beta = groups{g}.betaX;
            betaToward = groups{g}.betaTowardX;
            betaAway = groups{g}.betaAwayX;
            betaHigh = groups{g}.betaHighX;
            betaLow = groups{g}.betaLowX;
        case 'y'
            beta = groups{g}.betaY;
            betaToward = groups{g}.betaTowardY;
            betaAway = groups{g}.betaAwayY;
            betaHigh = groups{g}.betaHighY;
            betaLow = groups{g}.betaLowY;
    end
    if useRewardDirection
        if ~isempty(betaToward) && any(isfinite(betaToward))
            plotHandles(end+1, 1) = plot(plotLagSec, betaToward, ...
                'Color', colors(g, :), 'LineWidth', opts.lineWidth, 'LineStyle', '-'); %#ok<AGROW>
            legendLabels(end+1, 1) = string(groupLabels(g)) + " toward"; %#ok<AGROW>
        end
        if ~isempty(betaAway) && any(isfinite(betaAway))
            plotHandles(end+1, 1) = plot(plotLagSec, betaAway, ...
                'Color', colors(g, :), 'LineWidth', opts.lineWidth, 'LineStyle', '--'); %#ok<AGROW>
            legendLabels(end+1, 1) = string(groupLabels(g)) + " away"; %#ok<AGROW>
        end
    elseif useRewardRegion
        if ~isempty(betaHigh) && any(isfinite(betaHigh))
            plotHandles(end+1, 1) = plot(plotLagSec, betaHigh, ...
                'Color', colors(g, :), 'LineWidth', opts.lineWidth, 'LineStyle', '-'); %#ok<AGROW>
            legendLabels(end+1, 1) = string(groupLabels(g)) + " high"; %#ok<AGROW>
        end
        if ~isempty(betaLow) && any(isfinite(betaLow))
            plotHandles(end+1, 1) = plot(plotLagSec, betaLow, ...
                'Color', colors(g, :), 'LineWidth', opts.lineWidth, 'LineStyle', '--'); %#ok<AGROW>
            legendLabels(end+1, 1) = string(groupLabels(g)) + " low"; %#ok<AGROW>
        end
    else
        if isempty(beta) || ~any(isfinite(beta))
            continue
        end
        plotHandles(end+1, 1) = plot(plotLagSec, beta, ...
            'Color', colors(g, :), 'LineWidth', opts.lineWidth); %#ok<AGROW>
        legendLabels(end+1, 1) = string(groupLabels(g)); %#ok<AGROW>
    end
end
xline(0, ':', 'Color', [0.4 0.4 0.4]);
yline(0, ':', 'Color', [0.4 0.4 0.4]);
xlabel('Target time relative to gaze (s)');
xlim([min(plotLagSec) max(plotLagSec)]);
ylabel('Ridge weight');
title(sprintf('%s %s', upper(axisName), opts.signalMode), 'Interpreter', 'none');
grid on;
box off;
if numel(plotHandles) > 1
    legend(plotHandles, cellstr(legendLabels), 'Interpreter', 'none', 'Location', 'northeastoutside');
end
hold off;
end
