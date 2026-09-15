function out = ccg(in, trialNo, opts, varargin)
% ccg  Compute chunk-based velocity cross-correlograms from CoPs data.
%
%   out = ccg(ex, 10)
%   out = ccg(ex, [10 11 12])
%   out = ccg(ex, {bg0, bg1}, opts)
%   out = ccg(ex, 'bg')
%   out = ccg(ex, 'rq')
%   out = ccg(ex, {'bg', 'rq'})
%   out = ccg(t, [10 11 12], opts)
%
% Inputs
%   in       : experiment struct containing ex.Trials, or a tracking table
%              returned by processCoPsEye().tracking
%              For raw ex input with two targets, the reference target is
%              chosen by opts.referenceTargetMode.
%   trialNo  : scalar/vector of trial numbers, or cell array of numeric
%              trial vectors, 'bg' for one group per background_noise_lvl,
%              'visLvl3' for low/mid/high visibility bins,
%              'pur'/'pursuit' for pursuit trials only, 'pre' for preblock
%              trials only, or 'rq' for
%              reward-quadrant chunk groups. Cell arrays of named group codes such as
%              {'bg','rq'} request intersections. By default, pursuit
%              and preblock trials are excluded unless explicitly requested.
%   opts     : optional struct with fields:
%       .onlyGoState    (default true)
%       .useEyeTime     (default true)
%       .targetSource   (default 'targetPositions' for raw ex input)
%                       'targetPositions' uses saved per-step target
%                       coordinates; 'sampled' uses target coordinates
%                       reconstructed at each eye sample
%       .ccgTimebase    (default 'step') 'step' keeps the legacy stepwise
%                       velocity CCG; 'sample' computes velocity CCG from
%                       eye-sample traces before collapsing to target steps
%       .stepClockOffsetSec (default -0.05) signed offset for the
%                       reconstructed target-step clock relative to stimOn;
%                       negative advances target steps, positive delays
%                       them, 0 gives legacy no-offset behavior
%       .lowpassHz      (default 2)
%       .interpBlinkSec (default 0.15) maximum gaze-gap interpolation;
%                       zero keeps blinks/missing gaze masked
%       .removeSaccadesForCcg (default false)
%       .saccadeInterp  (default false)
%       .saccadePadSec  (default 0.02)
%       .speedThreshDegPerSec (default [])
%       .minAmpDeg    (default 1)
%       .minDurSec    (default 0.008)
%       .maxDurSec    (default 5)
%       .smoothFrames (default 5)
%       .shuffleEyeAcrossTrials (default false)
%       .shuffleEyeWithinTrials (default false)
%       .shuffleEyeCircularWithinTrials (default false) circularly shift
%                       stepwise gaze within each trial, preserving gaze
%                       autocorrelation while breaking target alignment
%       .shuffleCircularMinShiftSec (default []) minimum circular shift;
%                       defaults to max(abs(ccgWindowSec))
%       .shuffleCircularMinShiftSteps (default []) step-count override for
%                       minimum circular shift
%       .shuffleSeed    (default [])
%       .setup          (required for tracking-table input when
%                        removeSaccadesForCcg is true or stepAmpMinDeg is set)
%       .ccgWindowSec   (default [-0.5 2.5])
%       .plot           (default false)
%       .newFigure      (default true)
%       .episodesOnly   (default false) return the shared preprocessed
%                       episode table without computing correlations
%       .lineWidth      (default 1.25)
%       .legendLocation (default 'northeastoutside') legend placement for
%                       plotted groups. Avoids MATLAB's 'best' placement,
%                       which can call shadowed helper functions on some paths.
%       .aggregateMode  (default 'chunk') one of:
%                       'chunk' = pool chunkwise contributions across all
%                                 selected trials
%                       'trial' = compute one CCG per trial, then average
%       .demeanMode     (default 'chunk') velocity demeaning before xcorr:
%                       'chunk' = subtract each chunk mean (legacy/default)
%                       'trial' = subtract one mean per trial and axis
%                       'global' = subtract one mean per group and axis
%                       'none' = no velocity demeaning (diagnostic)
%       .stepGazeSummary (default 'first') how gaze samples within each
%                       target step are collapsed before the stepwise CCG:
%                       'mean', 'first', 'middle', or 'last'
%       .minChunkSec   (default 0.1) keep only chunks with duration
%                      at or above this value in seconds
%       .maxChunkSec   (default []) keep only chunks with duration
%                      at or below this value in seconds
%       .referenceTargetMode (default 'chunk') for raw ex two-target input:
%                      'trial' chooses once per trial; 'chunk' chooses
%                      separately for each contiguous chunk by gaze distance;
%                      'targetCloser'/'targetFarther' choose per chunk by
%                      distance to the Gaussian reward center
%       .referenceTargetChoice (default 'closer') choose 'closer',
%                      'farther', 'target1', or 'target2' when two targets
%                      are available for 'trial'/'chunk' gaze-distance modes
%       .trackingSource (default 'hmmFiltered', raw ex input only) chooses
%                      the tracked target from 'hmmFiltered',
%                      'hmmSmoothed', or 'hmmPredictive' hard TLeft states.
%                      'model-free' retains referenceTargetMode behavior.
%                      Missing HMM data do not fall back to model-free.
%       .hmmHardThreshold (default 0.9) for two-state HMMs, select a target
%                      only when its probability is strictly greater than
%                      this value. Three-state HMMs instead use the most
%                      probable TLeft/TRight/non-tracking state.
%       .minTrackingSec (default 0.1) minimum retained hard-HMM target run
%       .trackingBridgeMaxSec (default 0.1) bridge an internal no-tracking
%                      (0) run no longer than this duration when the same
%                      target has valid runs on both sides. Opposite-target
%                      runs are never bridged.
%       .rewardQuadCloseMinFrac (default 0.5) with 'rq' grouping, chunks
%                      where the selected target spends at least this
%                      fraction in the high-reward quadrant are 'close'
%       .rewardQuadFarMaxFrac (default 0) with 'rq' grouping, chunks where
%                      the selected target spends at most this fraction in
%                      the high-reward quadrant are 'far'; remaining chunks
%                      are 'mid'
%       .excludeBoundaryChunks (default false, raw ex input only) drop
%                      chunks where the chosen reference target reaches the
%                      stimulus boundary zone
%       .boundaryMarginPx (default []) boundary-zone width in pixels;
%                      defaults to the rendered target radius
%       .boundaryMarginDeg (default []) boundary-zone width in visual
%                      degrees; overrides boundaryMarginPx when finite
%       .stepAmpAboveMean (default false) keep only target-step
%                         transitions above the group mean amplitude
%       .stepAmpMinPrctile (default []) keep only target-step transitions
%                          at or above this percentile of group amplitudes
%       .stepAmpMinDeg   (default []) absolute minimum target-step
%                         amplitude in visual degrees
%       .colors         (default warm-to-cool for 3 levels, otherwise lines(nGroup));
%                       full nGroup x 3 RGB group-color override
%       .levelColors    (default []) level-specific RGB override. Use
%                       struct('levels', ["low","mid","high"], 'colors', C)
%                       or {'low', C1; 'mid', C2; 'high', C3}.
%       .truncateTrialFromStep (default 0)
%       .useTrackingOnly (default true for tracking-table input)
%       .fromState      (default 'all') for raw ex input only:
%                       'all', 'smooth', 'fix', 'fixation',
%                       'sac', 'sacc', 'saccade'
%       .visLvls        (default [0.75 0.9]) cutoffs for 'visLvl3':
%                       low < visLvls(1), mid < visLvls(2), high otherwise
%
% Output
%   out.episodes   : table with one row per contiguous chunk
%   out.trialGroups: cell array of requested trial groups
%   out.groups     : one struct per group with aggregated CCGs,
%                    per-lag contributing chunk counts, and per-lag
%                    overlap support counts
%   out.lagSec     : lag axis in seconds

if nargin < 2
    trialNo = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
if ischar(opts) || (isstring(opts) && isscalar(opts))
    if ~strcmpi(char(string(opts)), 'all')
        error('ccg:AxisRemoved', 'The axis selector was removed. ccg() now always computes both x and y.');
    end
    if ~isempty(varargin)
        opts = varargin{1};
    else
        opts = struct();
    end
elseif ~isstruct(opts)
    error('ccg:BadOpts', 'Third argument must be opts or the legacy string ''all''.');
end

defaults = struct( ...
    'onlyGoState', true, ...
    'useEyeTime', true, ...
    'targetSource', 'targetPositions', ...
    'ccgTimebase', 'step', ...
    'targetStepTimingMode', [], ...
    'stepClockOffsetSec', -0.05, ...
    'lowpassHz', 2, ...
    'interpBlinkSec', 0.15, ...
    'removeSaccadesForCcg', false, ...
    'saccadeInterp', false, ...
    'saccadePadSec', 0.02, ...
    'speedThreshDegPerSec', [], ...
    'minAmpDeg', 1, ...
    'minDurSec', 0.008, ...
    'maxDurSec', 5, ...
    'smoothFrames', 5, ...
    'shuffleEyeAcrossTrials', false, ...
    'shuffleEyeWithinTrials', false, ...
    'shuffleEyeCircularWithinTrials', false, ...
    'shuffleCircularMinShiftSec', [], ...
    'shuffleCircularMinShiftSteps', [], ...
    'shuffleSeed', [], ...
    'setup', [], ...
    'ccgWindowSec', [-0.5 2.5], ...
    'plot', false, ...
    'newFigure', true, ...
    'episodesOnly', false, ...
    'lineWidth', 1.25, ...
    'legendLocation', 'northeastoutside', ...
    'aggregateMode', 'chunk', ...
    'demeanMode', 'chunk', ...
    'stepGazeSummary', 'first', ...
    'minChunkSec', 0.1, ...
    'maxChunkSec', [], ...
    'referenceTargetMode', 'chunk', ...
    'referenceTargetChoice', 'closer', ...
    'trackingSource', 'hmmFiltered', ...
    'hmmHardThreshold', 0.9, ...
    'minTrackingSec', 0.1, ...
    'trackingBridgeMaxSec', 0.1, ...
    'rewardQuadCloseMinFrac', 0.5, ...
    'rewardQuadFarMaxFrac', 0, ...
    'excludeBoundaryChunks', false, ...
    'boundaryMarginPx', [], ...
    'boundaryMarginDeg', [], ...
    'stepAmpAboveMean', false, ...
    'stepAmpMinPrctile', [], ...
    'stepAmpMinDeg', [], ...
    'colors', [], ...
    'levelColors', [], ...
    'refGroup', 't12bg-1', ...
    'refLineStyle', [], ...
    'refLineWidth', [], ...
    'truncateTrialFromStep', 0, ...
    'useTrackingOnly', true, ...
    'timeWindowSec', [], ...
    'fromState', 'all', ...
    'visLvls', [0.75 0.9]);
opts = localApplyLegacySaccadeAliases(opts);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field)
        opts.(field) = defaults.(field);
    end
end
opts.demeanMode = localResolveDemeanMode(opts.demeanMode);
opts.stepGazeSummary = localResolveStepGazeSummary(opts.stepGazeSummary);
opts.ccgTimebase = localResolveCcgTimebase(opts.ccgTimebase);
opts.trackingSource = localResolveHmmTrackingSource(opts.trackingSource);
opts.hmmHardThreshold = localResolveHmmHardThreshold(opts.hmmHardThreshold);
opts.minTrackingSec = localResolveNonnegativeDuration(opts.minTrackingSec, 'minTrackingSec');
opts.trackingBridgeMaxSec = localResolveNonnegativeDuration( ...
    opts.trackingBridgeMaxSec, 'trackingBridgeMaxSec');

inputMode = localResolveInputMode(in);
switch inputMode
    case 'ex'
        availableTrials = 1:numel(in.Trials);
        opts.setup = in.setup;
    case 'tracking'
        availableTrials = unique(double(in.trial(:)'));
        opts.targetSource = 'sampled';
        opts.stepClockOffsetSec = [];
        if ~strcmp(localResolveFromState(opts.fromState), 'all')
            error('ccg:FromStateTrackingUnsupported', ...
                'opts.fromState is supported only for raw ex input, not tracking-table input.');
        end
        if logical(opts.excludeBoundaryChunks)
            error('ccg:BoundaryFilterTrackingUnsupported', ...
                'opts.excludeBoundaryChunks requires raw ex input so texture geometry can be inferred.');
        end
end
availableTrials = localApplyPursuitTrialSelection(trialNo, availableTrials, in, inputMode);
if isempty(availableTrials)
    error('ccg:NoTrials', 'Input contains no usable trials.');
end

[groupingSpec, trialGroups, groupLabels, groupOptsList] = localResolveGroupingSpec(trialNo, availableTrials, in, inputMode, opts);
nGroup = numel(trialGroups);
plotFacetSpec = localResolvePlotFacetSpec(trialNo, groupingSpec, in, inputMode, trialGroups, opts);
opts.colors = resolveCcgPlotColors(nGroup, opts, plotFacetSpec, groupLabels);

episodes = cell(nGroup, 1);
for g = 1:nGroup
    buildOpts = groupOptsList{g};
    switch inputMode
        case 'ex'
            episodes{g} = localBuildEpisodeTableFromEx(in, trialGroups{g}, g, buildOpts);
        case 'tracking'
            episodes{g} = localBuildEpisodeTableFromTracking(in, trialGroups{g}, g, buildOpts);
    end
    if logical(opts.shuffleEyeAcrossTrials)
        episodes{g} = localShuffleEpisodeGazeAcrossTrials(episodes{g}, opts);
    end
    if logical(opts.shuffleEyeWithinTrials)
        episodes{g} = localShuffleEpisodeGazeWithinTrials(episodes{g}, opts);
    end
    if logical(opts.shuffleEyeCircularWithinTrials)
        episodes{g} = localShuffleEpisodeGazeCircularWithinTrials(episodes{g}, opts);
    end
end
allEpisodes = vertcat(episodes{:});
if logical(opts.episodesOnly)
    out = struct('episodes', allEpisodes, 'trialGroups', {trialGroups}, ...
        'groupLabels', groupLabels, 'trackingSource', string(opts.trackingSource));
    return
end

groupOut = cell(nGroup, 1);
lagSec = [];
globalDtStepSec = NaN;
if ~isempty(allEpisodes) && ismember('dtStepSec', allEpisodes.Properties.VariableNames)
    globalDtStepSec = localCommonDtStepSec(allEpisodes.dtStepSec);
end
if ~isempty(allEpisodes) && ismember('group', allEpisodes.Properties.VariableNames)
    for g = 1:nGroup
        groupOut{g} = localAggregateEpisodes(allEpisodes(allEpisodes.group == g, :), groupOptsList{g}, globalDtStepSec);
        groupOut{g}.groupLabel = groupLabels(g);
        if isempty(lagSec)
            lagSec = groupOut{g}.lagSec;
        end
    end
else
    for g = 1:nGroup
        groupOut{g} = localAggregateEpisodes(table(), groupOptsList{g}, globalDtStepSec);
        groupOut{g}.groupLabel = groupLabels(g);
    end
end
refGroupOut = {};
refInfo = struct('enabled', false);
if opts.plot && strcmp(inputMode, 'ex')
    [refGroupOut, refInfo] = localBuildReferenceGroupOut( ...
        in, trialGroups, groupLabels, groupOptsList, globalDtStepSec, opts);
end

if opts.plot
    if opts.newFigure
        figure;
    end
    if plotFacetSpec.enabled
        tiledlayout(plotFacetSpec.nRows, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
        for iRow = 1:plotFacetSpec.nRows
            nexttile;
            localPlotCcgGroups(lagSec, groupOut, 'x', opts, plotFacetSpec.rowGroupIdx{iRow}, ...
                plotFacetSpec.groupLineLabels, plotFacetSpec.rowLabels(iRow), refGroupOut);
            nexttile;
            localPlotCcgGroups(lagSec, groupOut, 'y', opts, plotFacetSpec.rowGroupIdx{iRow}, ...
                plotFacetSpec.groupLineLabels, plotFacetSpec.rowLabels(iRow), refGroupOut);
        end
    else
        tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
        nexttile;
        localPlotCcgGroups(lagSec, groupOut, 'x', opts, [], {}, "", refGroupOut);
        nexttile;
        localPlotCcgGroups(lagSec, groupOut, 'y', opts, [], {}, "", refGroupOut);
    end
    sgtitle(sprintf('Velocity CCG (%d group%s)', nGroup, localPlural(nGroup)), 'Interpreter', 'none');
end

out = struct();
out.episodes = allEpisodes;
out.trials = localFlattenTrialGroups(trialGroups);
out.trialGroups = trialGroups;
out.groupLabels = groupLabels;
out.groupingSpec = groupingSpec;
out.axisName = 'all';
out.lagSec = lagSec;
out.aggregateMode = char(string(opts.aggregateMode));
out.demeanMode = char(string(opts.demeanMode));
out.stepGazeSummary = char(string(opts.stepGazeSummary));
out.ccgTimebase = char(string(opts.ccgTimebase));
out.targetSource = localResolveTargetSource(opts);
out.trackingSource = char(string(opts.trackingSource));
out.hmmHardThreshold = opts.hmmHardThreshold;
out.minTrackingSec = opts.minTrackingSec;
out.trackingBridgeMaxSec = opts.trackingBridgeMaxSec;
out.interpBlinkSec = opts.interpBlinkSec;
out.minChunkSec = opts.minChunkSec;
out.referenceTargetMode = char(localResolveReferenceTargetMode(opts));
out.referenceTargetChoice = char(string(opts.referenceTargetChoice));
out.stepClockOffsetSec = localResolveCcgStepClockOffsetSec(opts);
out.targetStepTimingMode = string(localResolveCcgTargetStepTimingMode(opts));
out.groups = groupOut;
out.inputMode = inputMode;
out.refGroup = opts.refGroup;
out.refInfo = refInfo;
out.refGroups = refGroupOut;
end


function T = localBuildEpisodeTableFromEx(ex, trialList, groupNo, opts)
localValidateHmmCoverage(ex, trialList, opts.trackingSource);
rows = cell(numel(trialList), 1);
rowCount = 0;
ccgTimebase = localResolveCcgTimebase(opts.ccgTimebase);
for i = 1:numel(trialList)
    trialNo = trialList(i);
    if strcmp(ccgTimebase, 'sample')
        ccgTable = localBuildSampleTable(ex, trialNo, opts);
    else
        ccgTable = localBuildStepTable(ex, trialNo, opts);
    end
    if isempty(ccgTable) || height(ccgTable) < 2
        continue
    end
    dtSec = localResolveStepDt(ccgTable.tRelSec, 1 / inferFs(ex));
    rewardQuadMeta = localRewardQuadMetaForTrial(ex, ex.Trials(trialNo), opts);
    [rows, rowCount] = localAppendChunkRows( ...
        rows, rowCount, ccgTable, groupNo, trialNo, dtSec, opts, rewardQuadMeta);
end

if rowCount == 0
    T = table();
else
    T = vertcat(rows{1:rowCount});
    T = localFilterEpisodeChunksByLength(T, opts);
end
end


function T = localBuildEpisodeTableFromTracking(trackingTable, trialList, groupNo, opts)
rows = cell(height(trackingTable), 1);
rowCount = 0;
ccgTimebase = localResolveCcgTimebase(opts.ccgTimebase);
trialMask = ismember(double(trackingTable.trial), trialList);
trackingTable = trackingTable(trialMask, :);
if isempty(trackingTable)
    T = table();
    return
end

[groupIdx, intervalInfo] = findgroups(trackingTable(:, {'trial', 'intervalNo'}));
for i = 1:height(intervalInfo)
    episode = trackingTable(groupIdx == i, :);
    if isempty(episode)
        continue
    end
    episode = sortrows(episode, {'sampleIdx', 'step'});
    sampleMask = true(height(episode), 1);
    if logical(opts.useTrackingOnly)
        sampleMask = double(episode.isTracking) >= 1;
    end
    truncateFromStep = double(localFirstScalar(opts.truncateTrialFromStep));
    if isfinite(truncateFromStep) && truncateFromStep > 0
        sampleMask = sampleMask & isfinite(episode.step) & double(episode.step) >= truncateFromStep;
    end
    episode = episode(sampleMask, :);
    if height(episode) < 2
        continue
    end
    dtFallback = localResolveStepDt(double(episode.tFromTrackingOnsetSec), NaN);
    dtSampleSec = localResolveSampleDtFromEpisode(episode, dtFallback);
    xPx = double(episode.xPx(:));
    yPx = double(episode.yPx(:));
    protectedNaNMask = false(size(xPx));
    if logical(opts.removeSaccadesForCcg)
        setup = localResolveCcgSetupForTracking(opts);
        [xPx, yPx, protectedNaNMask] = localApplySaccadeHandlingForCcg( ...
            xPx, yPx, dtSampleSec, setup, opts);
    end
    [xPx, yPx] = preprocessGazeForCcgCoPs( ...
        xPx, yPx, dtSampleSec, opts.interpBlinkSec, opts.lowpassHz, protectedNaNMask);
    if strcmp(ccgTimebase, 'sample')
        sampleTable = localSampleTableFromVectors( ...
            xPx, yPx, double(episode.trackedTargetX(:)), double(episode.trackedTargetY(:)), ...
            double(episode.step(:)), double(episode.tFromTrackingOnsetSec(:)), ...
            [], [], [], opts);
        if isempty(sampleTable) || height(sampleTable) < 2
            continue
        end
        trialNo = double(intervalInfo.trial(i));
        [rows, rowCount] = localAppendChunkRows(rows, rowCount, sampleTable, groupNo, trialNo, dtSampleSec, opts);
        continue
    end
    stepTable = localAggregateToSteps( ...
        xPx, yPx, ...
        double(episode.trackedTargetX(:)), double(episode.trackedTargetY(:)), ...
        double(episode.step(:)), double(episode.tFromTrackingOnsetSec(:)), ...
        [], [], [], opts.stepGazeSummary);
    if isempty(stepTable) || height(stepTable) < 2
        continue
    end
    dtStepSec = localResolveStepDt(stepTable.tRelSec, dtFallback);
    trialNo = double(intervalInfo.trial(i));
    [rows, rowCount] = localAppendChunkRows(rows, rowCount, stepTable, groupNo, trialNo, dtStepSec, opts);
end

if rowCount == 0
    T = table();
else
    T = vertcat(rows{1:rowCount});
    T = localFilterEpisodeChunksByLength(T, opts);
end
end


function sampleTable = localBuildSampleTable(ex, trialNo, opts)
T = ex.Trials(trialNo);
[xPx, yPx, tRel, tAbs, valid] = reconstructEyePx(ex, T, opts.useEyeTime, opts);
exStepClock = localApplyCcgStepClockOptions(ex, opts);
[targetX, targetY, target2X, target2Y, stepIdx] = mapTargetsByStep(exStepClock, T, tRel);
targetSource = localResolveTargetSource(opts);

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

timeWindowSec = localTimeWindow(opts.timeWindowSec);
if ~isempty(timeWindowSec)
    keepMask = tRel >= timeWindowSec(1) & tRel <= timeWindowSec(2);
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

fromState = localResolveFromState(opts.fromState);
if ~strcmp(fromState, 'all')
    stateOpts = rmfield(opts, intersect(fieldnames(opts), {'plot','newFigure','colors','levelColors','aggregateMode', ...
        'removeSaccadesForCcg','saccadeInterp','shuffleEyeAcrossTrials','shuffleEyesAcrossTrials', ...
        'shuffleEyeWithinTrials','shuffleEyesWithinTrial','shuffleEyeWithinTrial','shuffleSeed','stepAmpAboveMean', ...
        'stepAmpMinPrctile','stepAmpMinDeg','fromState','useTrackingOnly'}));
    G = classifyGazeState(ex, trialNo, stateOpts);
    stateKeep = localStateMaskForCode(G.samples, fromState);
    if numel(stateKeep) ~= numel(xPx)
        error('ccg:StateMaskSizeMismatch', ...
            'Internal error: gaze-state mask size did not match trial sample count.');
    end
    xPx(~stateKeep) = NaN;
    yPx(~stateKeep) = NaN;
end

[texBounds, ~] = localTextureBounds(ex.setup.screenRect, ex.exp.CoPs.graph);
insideTexture = xPx >= texBounds.xMin & xPx <= texBounds.xMax & ...
    yPx >= texBounds.yMin & yPx <= texBounds.yMax;
xPx(~insideTexture) = NaN;
yPx(~insideTexture) = NaN;
valid = valid & insideTexture; %#ok<NASGU>

dtSec = 1 / inferFs(ex);
protectedNaNMask = false(size(xPx));
if logical(opts.removeSaccadesForCcg)
    [xPx, yPx, protectedNaNMask] = localApplySaccadeHandlingForCcg( ...
        xPx, yPx, dtSec, ex.setup, opts);
end
[xPx, yPx] = preprocessGazeForCcgCoPs(xPx, yPx, dtSec, opts.interpBlinkSec, opts.lowpassHz, protectedNaNMask);

if strcmp(targetSource, 'targetPositions') && isfield(T, 'targetPositions') && ~isempty(T.targetPositions)
    [targetX, targetY, target2X, target2Y] = localTargetsFromSavedPositions(T, stepIdx);
end
[targetX, targetY, target2X, target2Y] = localCanonicalizeTargetOrder( ...
    targetX, targetY, target2X, target2Y);
trialTrackingSource = opts.trackingSource;
if localTrialTargetNum(ex, T) < 2
    trialTrackingSource = 'model-free';
end
[targetX, targetY, target2X, target2Y, hmmReferenceUsed, hmmReferenceId, hmmCcgInclude] = ...
    localApplyHmmReferenceTarget(T, stepIdx, targetX, targetY, target2X, target2Y, ...
    tRel, trialTrackingSource, opts.hmmHardThreshold, ...
    opts.minTrackingSec, opts.trackingBridgeMaxSec);
xPx(~hmmCcgInclude) = NaN;
yPx(~hmmCcgInclude) = NaN;

referenceTargetMode = localResolveReferenceTargetMode(opts);
referenceTargetChoice = validatestring(char(string(opts.referenceTargetChoice)), {'closer', 'farther', 'target1', 'target2'});
referenceTargetId = hmmReferenceId;
if ~hmmReferenceUsed && strcmp(referenceTargetMode, "trial")
    [targetX, targetY, referenceTargetId] = localSelectTrialReferenceTarget( ...
        xPx, yPx, targetX, targetY, target2X, target2Y, referenceTargetChoice);
end

sampleTable = localSampleTableFromVectors( ...
    double(xPx(:)), double(yPx(:)), double(targetX(:)), double(targetY(:)), ...
    double(stepIdx(:)), double(tRel(:)), referenceTargetId, double(target2X(:)), double(target2Y(:)), opts);
sampleTable = localAnnotateBoundaryContact(sampleTable, ex.setup, ex.exp.CoPs.graph, opts);
end


function stepTable = localBuildStepTable(ex, trialNo, opts)
T = ex.Trials(trialNo);
[xPx, yPx, tRel, tAbs, valid] = reconstructEyePx(ex, T, opts.useEyeTime, opts);
exStepClock = localApplyCcgStepClockOptions(ex, opts);
[targetX, targetY, target2X, target2Y, stepIdx] = mapTargetsByStep(exStepClock, T, tRel);
targetSource = localResolveTargetSource(opts);

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

timeWindowSec = localTimeWindow(opts.timeWindowSec);
if ~isempty(timeWindowSec)
    keepMask = tRel >= timeWindowSec(1) & tRel <= timeWindowSec(2);
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

fromState = localResolveFromState(opts.fromState);
if ~strcmp(fromState, 'all')
    stateOpts = rmfield(opts, intersect(fieldnames(opts), {'plot','newFigure','colors','levelColors','aggregateMode', ...
        'removeSaccadesForCcg','saccadeInterp','shuffleEyeAcrossTrials','shuffleEyesAcrossTrials', ...
        'shuffleEyeWithinTrials','shuffleEyesWithinTrial','shuffleEyeWithinTrial','shuffleSeed','stepAmpAboveMean', ...
        'stepAmpMinPrctile','stepAmpMinDeg','fromState','useTrackingOnly'}));
    G = classifyGazeState(ex, trialNo, stateOpts);
    stateKeep = localStateMaskForCode(G.samples, fromState);
    if numel(stateKeep) ~= numel(xPx)
        error('ccg:StateMaskSizeMismatch', ...
            'Internal error: gaze-state mask size did not match trial sample count.');
    end
    xPx(~stateKeep) = NaN;
    yPx(~stateKeep) = NaN;
end

[texBounds, ~] = localTextureBounds(ex.setup.screenRect, ex.exp.CoPs.graph);
insideTexture = xPx >= texBounds.xMin & xPx <= texBounds.xMax & ...
    yPx >= texBounds.yMin & yPx <= texBounds.yMax;
xPx(~insideTexture) = NaN;
yPx(~insideTexture) = NaN;
valid = valid & insideTexture; %#ok<NASGU>

dtSec = 1 / inferFs(ex);
protectedNaNMask = false(size(xPx));
if logical(opts.removeSaccadesForCcg)
    [xPx, yPx, protectedNaNMask] = localApplySaccadeHandlingForCcg( ...
        xPx, yPx, dtSec, ex.setup, opts);
end
[xPx, yPx] = preprocessGazeForCcgCoPs(xPx, yPx, dtSec, opts.interpBlinkSec, opts.lowpassHz, protectedNaNMask);

if strcmp(targetSource, 'targetPositions') && isfield(T, 'targetPositions') && ~isempty(T.targetPositions)
    [targetX, targetY, target2X, target2Y] = localTargetsFromSavedPositions(T, stepIdx);
end
[targetX, targetY, target2X, target2Y] = localCanonicalizeTargetOrder( ...
    targetX, targetY, target2X, target2Y);
trialTrackingSource = opts.trackingSource;
if localTrialTargetNum(ex, T) < 2
    trialTrackingSource = 'model-free';
end
[targetX, targetY, target2X, target2Y, hmmReferenceUsed, hmmReferenceId, hmmCcgInclude] = ...
    localApplyHmmReferenceTarget(T, stepIdx, targetX, targetY, target2X, target2Y, ...
    tRel, trialTrackingSource, opts.hmmHardThreshold, ...
    opts.minTrackingSec, opts.trackingBridgeMaxSec);
xPx(~hmmCcgInclude) = NaN;
yPx(~hmmCcgInclude) = NaN;

referenceTargetMode = localResolveReferenceTargetMode(opts);
referenceTargetChoice = validatestring(char(string(opts.referenceTargetChoice)), {'closer', 'farther', 'target1', 'target2'});
referenceTargetId = hmmReferenceId;
if ~hmmReferenceUsed && strcmp(referenceTargetMode, "trial")
    [targetX, targetY, referenceTargetId] = localSelectTrialReferenceTarget( ...
        xPx, yPx, targetX, targetY, target2X, target2Y, referenceTargetChoice);
end

stepTable = localAggregateToSteps( ...
    double(xPx(:)), double(yPx(:)), double(targetX(:)), double(targetY(:)), ...
    double(stepIdx(:)), double(tRel(:)), referenceTargetId, double(target2X(:)), double(target2Y(:)), ...
    opts.stepGazeSummary);
stepTable = localAnnotateBoundaryContact(stepTable, ex.setup, ex.exp.CoPs.graph, opts);
end


function targetSource = localResolveTargetSource(opts)
targetSource = 'targetPositions';
if isstruct(opts) && isfield(opts, 'targetSource') && ~isempty(opts.targetSource)
    targetSource = validatestring(char(opts.targetSource), {'targetPositions', 'positions', 'sampled'});
end
if strcmp(targetSource, 'positions')
    targetSource = 'targetPositions';
end
end


function exOut = localApplyCcgStepClockOptions(exIn, opts)
exOut = exIn;
offsetSec = localResolveCcgStepClockOffsetSec(opts);
targetStepTimingMode = localResolveCcgTargetStepTimingMode(opts);
if ~isfinite(offsetSec) && isempty(targetStepTimingMode)
    return
end
if ~isfield(exOut, 'exp') || ~isstruct(exOut.exp)
    exOut.exp = struct();
end
if ~isfield(exOut.exp, 'CoPs') || ~isstruct(exOut.exp.CoPs)
    exOut.exp.CoPs = struct();
end
if ~isfield(exOut.exp.CoPs, 'analysis') || ~isstruct(exOut.exp.CoPs.analysis)
    exOut.exp.CoPs.analysis = struct();
end
if isfinite(offsetSec)
    exOut.exp.CoPs.analysis.stepClockOffsetSec = offsetSec;
end
if ~isempty(targetStepTimingMode)
    exOut.exp.CoPs.analysis.targetStepTimingMode = targetStepTimingMode;
end
end


function mode = localResolveCcgTargetStepTimingMode(opts)
mode = '';
if ~isstruct(opts)
    return
end
candidateFields = {'targetStepTimingMode', 'stepTimingMode', 'frameStepTimingMode'};
for i = 1:numel(candidateFields)
    field = candidateFields{i};
    if isfield(opts, field) && ~isempty(opts.(field))
        mode = char(string(opts.(field)));
        mode = strtrim(mode);
        return
    end
end
end


function offsetSec = localResolveCcgStepClockOffsetSec(opts)
offsetSec = NaN;
if isstruct(opts) && isfield(opts, 'stepClockOffsetSec') && ~isempty(opts.stepClockOffsetSec)
    offsetSec = double(localFirstScalar(opts.stepClockOffsetSec));
    if isfinite(offsetSec)
        offsetSec = double(offsetSec);
    end
end
end


function [targetX, targetY, target2X, target2Y] = localTargetsFromSavedPositions(T, stepIdx)
stepIdx = double(stepIdx(:));
n = numel(stepIdx);
targetX = NaN(n, 1);
targetY = NaN(n, 1);
target2X = NaN(n, 1);
target2Y = NaN(n, 1);
if ~isfield(T, 'targetPositions') || isempty(T.targetPositions)
    return
end

nsteps = getfieldOrNaN(T, 'nsteps');
if ~isfinite(nsteps) || nsteps < 1
    nsteps = numel(T.targetPositions);
end
nsteps = min(nsteps, numel(T.targetPositions));

for i = 1:n
    s = stepIdx(i);
    if ~isfinite(s)
        continue
    end
    s = max(1, min(nsteps, round(s)));
    tp = T.targetPositions(s);
    if isfield(tp, 'targ1') && isfield(tp.targ1, 'pos_abs') && numel(tp.targ1.pos_abs) >= 2
        targetX(i) = tp.targ1.pos_abs(1);
        targetY(i) = tp.targ1.pos_abs(2);
    end
    if isfield(tp, 'targ2') && isfield(tp.targ2, 'pos_abs') && numel(tp.targ2.pos_abs) >= 2
        target2X(i) = tp.targ2.pos_abs(1);
        target2Y(i) = tp.targ2.pos_abs(2);
    end
end
end


function source = localResolveHmmTrackingSource(value)
key = lower(strrep(strrep(char(string(value)), '-', ''), '_', ''));
switch key
    case {'hmmfiltered', 'filtered'}
        source = 'hmmFiltered';
    case {'hmmsmoothed', 'smoothed'}
        source = 'hmmSmoothed';
    case {'hmmpredictive', 'predictive'}
        source = 'hmmPredictive';
    case {'modelfree', 'geometric'}
        source = 'model-free';
    otherwise
        error('ccg:BadTrackingSource', ...
            ['opts.trackingSource must be ''hmmFiltered'', ''hmmSmoothed'', ' ...
             '''hmmPredictive'', or ''model-free''.']);
end
end


function threshold = localResolveHmmHardThreshold(value)
threshold = double(value);
if ~isscalar(threshold) || ~isfinite(threshold) || threshold < 0.5 || threshold > 1
    error('ccg:BadHmmHardThreshold', ...
        'opts.hmmHardThreshold must be a finite scalar between 0.5 and 1.');
end
end


function durationSec = localResolveNonnegativeDuration(value, optionName)
durationSec = double(localFirstScalar(value));
if ~isfinite(durationSec) || durationSec < 0
    error('ccg:BadTrackingDuration', ...
        'opts.%s must be a finite nonnegative scalar.', optionName);
end
end


function localValidateHmmCoverage(ex, trialList, source)
if strcmp(source, 'model-free') || isempty(trialList)
    return
end
method = lower(erase(source, 'hmm'));
hasProbabilities = false(numel(trialList), 1);
needsHmm = false(numel(trialList), 1);
for i = 1:numel(trialList)
    T = ex.Trials(trialList(i));
    targetNum = localTrialTargetNum(ex, T);
    needsHmm(i) = ~isfinite(targetNum) || targetNum >= 2;
    if ~needsHmm(i)
        continue
    end
    if isfield(T, 'hmm') && isstruct(T.hmm) && ...
            isfield(T.hmm, method) && isstruct(T.hmm.(method)) && ...
            isfield(T.hmm.(method), 'pTLeft')
        values = double(T.hmm.(method).pTLeft(:));
        hasProbabilities(i) = any(isfinite(values));
    end
end
if any(needsHmm) && ~any(hasProbabilities(needsHmm))
    error('ccg:MissingHmmTracking', ...
        ['No usable %s probabilities were found in the selected trials. ' ...
         'Merge the matching HMM sidecar, or explicitly set ' ...
         'opts.trackingSource to ''model-free''.'], source);
end
end


function [targetX, targetY, target2X, target2Y] = localCanonicalizeTargetOrder( ...
    targetX, targetY, target2X, target2Y)
firstValid = find(isfinite(targetX) & isfinite(targetY) & ...
    isfinite(target2X) & isfinite(target2Y), 1, 'first');
if isempty(firstValid)
    return
end
swapTargets = targetX(firstValid) > target2X(firstValid) || ...
    (targetX(firstValid) == target2X(firstValid) && targetY(firstValid) > target2Y(firstValid));
if swapTargets
    [targetX, target2X] = deal(target2X, targetX);
    [targetY, target2Y] = deal(target2Y, targetY);
end
end


function [targetX, targetY, target2X, target2Y, used, referenceTargetId, ccgInclude] = ...
    localApplyHmmReferenceTarget(T, stepIdx, targetX, targetY, target2X, target2Y, ...
    tRel, source, threshold, minTrackingSec, bridgeMaxSec)
used = false;
referenceTargetId = NaN(size(stepIdx));
ccgInclude = true(size(stepIdx));
if strcmp(source, 'model-free')
    return
end
used = true;
method = lower(erase(source, 'hmm'));
if ~isfield(T, 'hmm') || ~isstruct(T.hmm) || ...
        ~isfield(T.hmm, method) || ~isstruct(T.hmm.(method)) || ...
        ~isfield(T.hmm.(method), 'pTLeft')
    targetX(:) = NaN;
    targetY(:) = NaN;
    target2X(:) = NaN;
    target2Y(:) = NaN;
    ccgInclude(:) = false;
    return
end

methodHmm = T.hmm.(method);
[hardState, available] = assignHmmTrackingStateCoPs( ...
    methodHmm, stepIdx, threshold);
if ~available
    targetX(:) = NaN;
    targetY(:) = NaN;
    target2X(:) = NaN;
    target2Y(:) = NaN;
    ccgInclude(:) = false;
    return
end

[hardState, ccgInclude] = localRegularizeHmmTrackingState( ...
    hardState, tRel, minTrackingSec, bridgeMaxSec);
referenceTargetId = hardState;

selectedX = nan(size(targetX));
selectedY = nan(size(targetY));
chooseLeft = hardState == 1;
chooseRight = hardState == 2;
selectedX(chooseLeft) = targetX(chooseLeft);
selectedY(chooseLeft) = targetY(chooseLeft);
selectedX(chooseRight) = target2X(chooseRight);
selectedY(chooseRight) = target2Y(chooseRight);
targetX = selectedX;
targetY = selectedY;
target2X = nan(size(target2X));
target2Y = nan(size(target2Y));
end


function [state, includeMask] = localRegularizeHmmTrackingState( ...
    state, tRel, minTrackingSec, bridgeMaxSec)
state = double(state(:));
tRel = double(tRel(:));
n = min(numel(state), numel(tRel));
state = state(1:n);
tRel = tRel(1:n);
rawState = state;
includeMask = false(size(state));
if n == 0
    return
end

% Repeatedly bridge eligible no-tracking gaps. Each new pass can use a
% legitimately merged run as a flank. Opposite-target and missing-state
% runs are never eligible, so positive switch evidence always splits chunks.
durationToleranceSec = 1e-9;
while true
    [runStart, runStop, runCode] = localStateRuns(state);
    bridgeTo = zeros(numel(runStart), 1);
    for r = 2:(numel(runStart) - 1)
        flankCode = runCode(r - 1);
        gapDurationSec = localRunDurationSec(tRel, runStart(r), runStop(r));
        leftDurationSec = localRunDurationSec(tRel, runStart(r - 1), runStop(r - 1));
        rightDurationSec = localRunDurationSec(tRel, runStart(r + 1), runStop(r + 1));
        stableFlanks = leftDurationSec + durationToleranceSec >= minTrackingSec && ...
            rightDurationSec + durationToleranceSec >= minTrackingSec;
        briefRelativeToFlanks = gapDurationSec + durationToleranceSec < ...
            min(leftDurationSec, rightDurationSec);
        if ismember(flankCode, [1 2]) && runCode(r + 1) == flankCode && ...
                runCode(r) == 0 && stableFlanks && ...
                gapDurationSec <= bridgeMaxSec + durationToleranceSec && ...
                briefRelativeToFlanks
            bridgeTo(r) = flankCode;
        end
    end
    if ~any(bridgeTo > 0)
        break
    end
    % Apply one pass simultaneously, then recalculate runs for controlled
    % cascading on the next pass.
    for r = find(bridgeTo > 0)'
        state(runStart(r):runStop(r)) = bridgeTo(r);
    end
end

% Remove confident target runs that remain shorter than the minimum.
[runStart, runStop, runCode] = localStateRuns(state);
for r = 1:numel(runStart)
    if ismember(runCode(r), [1 2]) && ...
            localRunDurationSec(tRel, runStart(r), runStop(r)) < minTrackingSec
        state(runStart(r):runStop(r)) = 0;
    end
end

% Original no-tracking samples bridged into a target run are retained.
assigned = ismember(state, [1 2]);
includeMask = assigned & (rawState == state | rawState == 0);
end


function [runStart, runStop, runCode] = localStateRuns(state)
code = state(:);
code(~isfinite(code)) = -1;
if isempty(code)
    runStart = zeros(0, 1);
    runStop = zeros(0, 1);
    runCode = zeros(0, 1);
    return
end
runStart = find([true; diff(code) ~= 0]);
runStop = [runStart(2:end) - 1; numel(code)];
runCode = code(runStart);
end


function durationSec = localRunDurationSec(tRel, firstIndex, lastIndex)
finiteTime = tRel(isfinite(tRel));
dtSec = median(diff(finiteTime), 'omitnan');
if ~isfinite(dtSec) || dtSec <= 0
    dtSec = 0;
end
segmentTime = tRel(firstIndex:lastIndex);
segmentTime = segmentTime(isfinite(segmentTime));
if isempty(segmentTime)
    durationSec = (lastIndex - firstIndex + 1) * dtSec;
else
    durationSec = max(segmentTime) - min(segmentTime) + dtSec;
end
end


function [rows, rowCount] = localAppendChunkRows(rows, rowCount, stepTable, groupNo, trialNo, dtStepSec, opts, rewardQuadMeta)
if nargin < 8 || isempty(rewardQuadMeta)
    rewardQuadMeta = struct();
end
% Keep HMM-regularized chunk continuity across missing gaze samples. The
% correlation code below splits finite data into runs, so it never computes
% a velocity across a missing-gaze interval.
chunkMask = isfinite(stepTable.targetX) & isfinite(stepTable.targetY);
idx = find(chunkMask);
if isempty(idx)
    return
end
referenceId = double(stepTable.referenceTargetId(idx));
prevFinite = isfinite(referenceId(1:end-1));
nextFinite = isfinite(referenceId(2:end));
referenceChanged = [false; ...
    (prevFinite & nextFinite & referenceId(2:end) ~= referenceId(1:end-1)) | ...
    xor(nextFinite, prevFinite)];
runBreak = [true; diff(idx) > 1 | diff(stepTable.step(idx)) > 1] | referenceChanged;
runStarts = find(runBreak);
runEnds = [runStarts(2:end)-1; numel(idx)];
for k = 1:numel(runStarts)
    ii = idx(runStarts(k):runEnds(k));
    if numel(ii) < 2
        continue
    end
    chunkTargetX = stepTable.targetX(ii);
    chunkTargetY = stepTable.targetY(ii);
    referenceTargetId = localFirstFinite(stepTable.referenceTargetId(ii));
    referenceTargetMode = localResolveReferenceTargetMode(opts);
    if ismember('target2X', stepTable.Properties.VariableNames) && ...
            any(isfinite(stepTable.target2X(ii)) & isfinite(stepTable.target2Y(ii)))
        if strcmp(referenceTargetMode, "chunk")
            [chunkTargetX, chunkTargetY, referenceTargetId] = localSelectTrialReferenceTarget( ...
                stepTable.xPx(ii), stepTable.yPx(ii), ...
                stepTable.targetX(ii), stepTable.targetY(ii), ...
                stepTable.target2X(ii), stepTable.target2Y(ii), opts.referenceTargetChoice);
        elseif localUsesRewardCenterTargetMode(referenceTargetMode)
            [chunkTargetX, chunkTargetY, referenceTargetId] = localSelectRewardCenterReferenceTarget( ...
                stepTable.targetX(ii), stepTable.targetY(ii), ...
                stepTable.target2X(ii), stepTable.target2Y(ii), rewardQuadMeta, referenceTargetMode);
        end
    end
    touchesBoundary = localChunkTouchesBoundary(stepTable, ii, referenceTargetId);
    if logical(opts.excludeBoundaryChunks) && touchesBoundary
        continue
    end
    [rewardQuadClass, rewardQuadFrac, rewardQuadHighIdx] = localRewardQuadChunkClass( ...
        chunkTargetX, chunkTargetY, rewardQuadMeta, opts);
    if localUsesRewardQuadFilter(opts) && ...
            ~strcmp(char(rewardQuadClass), localCanonicalRewardQuadClass(opts.rewardQuadClass))
        continue
    end
    chunkDurSec = max(0, ...
        double(stepTable.tRelSec(ii(end)) - stepTable.tRelSec(ii(1))) + dtStepSec);
    rowCount = rowCount + 1;
    rows{rowCount,1} = table( ...
        groupNo, trialNo, k, ii(1), ii(end), numel(ii), dtStepSec, chunkDurSec, ...
        {stepTable.step(ii).'}, {stepTable.tRelSec(ii).'}, ...
        {stepTable.xPx(ii).'}, {chunkTargetX(:).'}, ...
        {stepTable.yPx(ii).'}, {chunkTargetY(:).'}, ...
        referenceTargetId, touchesBoundary, string(rewardQuadClass), rewardQuadFrac, rewardQuadHighIdx, ...
        'VariableNames', {'group','trial','chunkNo','chunkStartRow','chunkEndRow','nSteps','dtStepSec','chunkDurSec', ...
        'step','tRelSec','gazeX','targetX','gazeY','targetY','referenceTargetId','touchesBoundary', ...
        'rewardQuadClass','rewardQuadFrac','rewardQuadHighIdx'});
end
end


function meta = localRewardQuadMetaForTrial(ex, T, opts)
meta = struct('enabled', localUsesRewardQuadFilter(opts), ...
    'needsRewardCenter', localUsesRewardCenterTargetMode(localResolveReferenceTargetMode(opts)), ...
    'fixCenterPx', [NaN NaN], 'gaussCenterPx', [NaN NaN], 'highQuadIdx', NaN);
if ~meta.enabled && ~meta.needsRewardCenter
    return
end
if meta.needsRewardCenter && ~meta.enabled
    targetNum = localTrialTargetNum(ex, T);
    if isfinite(targetNum) && targetNum < 2
        return
    end
end

try
    gaussCenterPx = getGaussianCenterPx(ex, T);
catch ME
    error('ccg:RewardQuadUnavailable', ...
        'Reward-center target selection/grouping requires metadata readable by getGaussianCenterPx(): %s', ME.message);
end
gaussCenterPx = double(gaussCenterPx(:)');
if numel(gaussCenterPx) < 2 || any(~isfinite(gaussCenterPx(1:2)))
    error('ccg:RewardQuadUnavailable', ...
        'Reward-center target selection/grouping could not resolve a finite reward-center location.');
end
meta.gaussCenterPx = gaussCenterPx(1:2);

if ~meta.enabled
    return
end

fixCenterPx = localResolveFixCenterPx(ex);
if any(~isfinite(fixCenterPx))
    error('ccg:RewardQuadUnavailable', ...
        'Reward-quadrant grouping requires ex.fix.PCtr or ex.setup.screenRect to define quadrant boundaries.');
end

highQuadIdx = classifyQuadrantCoPs(gaussCenterPx(1), gaussCenterPx(2), fixCenterPx);
if ~isfinite(highQuadIdx)
    error('ccg:RewardQuadUnavailable', ...
        'Reward-quadrant grouping could not classify the reward center into a quadrant.');
end

meta.fixCenterPx = fixCenterPx;
meta.highQuadIdx = double(highQuadIdx);
end


function ctr = localResolveFixCenterPx(ex)
ctr = [NaN NaN];
if isfield(ex, 'fix') && isfield(ex.fix, 'PCtr') && numel(ex.fix.PCtr) >= 2
    candidate = double(ex.fix.PCtr(:)');
    if all(isfinite(candidate(1:2)))
        ctr = candidate(1:2);
        return
    end
end
if isfield(ex, 'setup') && isfield(ex.setup, 'screenRect') && numel(ex.setup.screenRect) >= 4
    rect = double(ex.setup.screenRect(:)');
    if all(isfinite(rect(1:4)))
        ctr = [(rect(1) + rect(3)) ./ 2, (rect(2) + rect(4)) ./ 2];
    end
end
end


function [className, frac, highQuadIdx] = localRewardQuadChunkClass(targetX, targetY, meta, opts)
className = "";
frac = NaN;
highQuadIdx = NaN;
if ~isstruct(meta) || ~isfield(meta, 'enabled') || ~logical(meta.enabled)
    return
end

highQuadIdx = double(meta.highQuadIdx);
quadIdx = classifyQuadrantCoPs(double(targetX(:)), double(targetY(:)), meta.fixCenterPx);
valid = isfinite(quadIdx);
if ~any(valid)
    className = "unknown";
    return
end

frac = mean(double(quadIdx(valid) == highQuadIdx), 'omitnan');
closeMinFrac = double(localFirstScalar(opts.rewardQuadCloseMinFrac));
farMaxFrac = double(localFirstScalar(opts.rewardQuadFarMaxFrac));
if ~isfinite(closeMinFrac)
    closeMinFrac = 0.5;
end
if ~isfinite(farMaxFrac)
    farMaxFrac = 0;
end
closeMinFrac = max(0, min(1, closeMinFrac));
farMaxFrac = max(0, min(1, farMaxFrac));

if frac >= closeMinFrac
    className = "close";
elseif frac <= farMaxFrac
    className = "far";
else
    className = "mid";
end
end


function sampleTable = localSampleTableFromVectors(xPx, yPx, targetX, targetY, stepIdx, tRelSec, referenceTargetId, target2X, target2Y, opts)
if nargin < 7 || isempty(referenceTargetId)
    referenceTargetId = NaN;
end
if nargin < 8 || isempty(target2X)
    target2X = NaN(size(targetX));
end
if nargin < 9 || isempty(target2Y)
    target2Y = NaN(size(targetY));
end
if nargin < 10
    opts = struct(); %#ok<NASGU>
end

xPx = double(xPx(:));
yPx = double(yPx(:));
targetX = double(targetX(:));
targetY = double(targetY(:));
target2X = double(target2X(:));
target2Y = double(target2Y(:));
stepIdx = double(stepIdx(:));
tRelSec = double(tRelSec(:));

n = min([numel(xPx), numel(yPx), numel(targetX), numel(targetY), ...
    numel(target2X), numel(target2Y), numel(stepIdx), numel(tRelSec)]);
sampleTable = table();
if n < 1
    return
end

xPx = xPx(1:n);
yPx = yPx(1:n);
targetX = targetX(1:n);
targetY = targetY(1:n);
target2X = target2X(1:n);
target2Y = target2Y(1:n);
stepIdx = stepIdx(1:n);
tRelSec = tRelSec(1:n);

valid = isfinite(stepIdx) & isfinite(tRelSec) & isfinite(targetX) & isfinite(targetY);
if ~any(valid)
    return
end

sampleTable = table( ...
    stepIdx(valid), tRelSec(valid), xPx(valid), yPx(valid), ...
    targetX(valid), targetY(valid), target2X(valid), target2Y(valid), ...
    localReferenceIdRows(referenceTargetId, valid), ...
    'VariableNames', {'step','tRelSec','xPx','yPx','targetX','targetY','target2X','target2Y','referenceTargetId'});
end


function stepTable = localAggregateToSteps(xPx, yPx, targetX, targetY, stepIdx, tRelSec, referenceTargetId, target2X, target2Y, stepGazeSummary)
if nargin < 7 || isempty(referenceTargetId)
    referenceTargetId = NaN;
end
if nargin < 8 || isempty(target2X)
    target2X = NaN(size(targetX));
end
if nargin < 9 || isempty(target2Y)
    target2Y = NaN(size(targetY));
end
if nargin < 10 || isempty(stepGazeSummary)
    stepGazeSummary = 'mean';
end
stepGazeSummary = localResolveStepGazeSummary(stepGazeSummary);
valid = isfinite(stepIdx) & isfinite(targetX) & isfinite(targetY);
if ~any(valid)
    stepTable = table();
    return
end
referenceTargetIdRows = localReferenceIdRows(referenceTargetId, valid);
T = table(stepIdx(valid), tRelSec(valid), xPx(valid), yPx(valid), targetX(valid), targetY(valid), target2X(valid), target2Y(valid), referenceTargetIdRows, ...
    'VariableNames', {'step','tRelSec','xPx','yPx','targetX','targetY','target2X','target2Y','referenceTargetId'});
[stepGroups, ~] = findgroups(T.step);
stepTable = table();
stepTable.step = splitapply(@(x) x(1), T.step, stepGroups);
stepTable.tRelSec = splitapply(@mean, T.tRelSec, stepGroups);
stepTable.xPx = splitapply(@(x) localSummarizeStepGaze(x, stepGazeSummary), T.xPx, stepGroups);
stepTable.yPx = splitapply(@(x) localSummarizeStepGaze(x, stepGazeSummary), T.yPx, stepGroups);
stepTable.targetX = splitapply(@(x) mean(x, 'omitnan'), T.targetX, stepGroups);
stepTable.targetY = splitapply(@(x) mean(x, 'omitnan'), T.targetY, stepGroups);
stepTable.target2X = splitapply(@(x) mean(x, 'omitnan'), T.target2X, stepGroups);
stepTable.target2Y = splitapply(@(x) mean(x, 'omitnan'), T.target2Y, stepGroups);
stepTable.referenceTargetId = splitapply(@localFirstFinite, T.referenceTargetId, stepGroups);
stepTable = sortrows(stepTable, 'step');
end


function rows = localReferenceIdRows(referenceTargetId, valid)
valid = logical(valid(:));
referenceTargetId = double(referenceTargetId(:));
if isscalar(referenceTargetId)
    rows = repmat(referenceTargetId, sum(valid), 1);
elseif numel(referenceTargetId) == numel(valid)
    rows = referenceTargetId(valid);
else
    error('ccg:ReferenceTargetIdSizeMismatch', ...
        'Reference-target state must be scalar or match the sample vector length.');
end
end


function value = localSummarizeStepGaze(x, mode)
x = double(x(:));
switch localResolveStepGazeSummary(mode)
    case 'mean'
        value = mean(x, 'omitnan');
    case 'first'
        idx = find(isfinite(x), 1, 'first');
        value = localValueAtIndexOrNaN(x, idx);
    case 'middle'
        idxAll = find(isfinite(x));
        if isempty(idxAll)
            value = NaN;
        else
            idx = idxAll(max(1, ceil(numel(idxAll) / 2)));
            value = x(idx);
        end
    case 'last'
        idx = find(isfinite(x), 1, 'last');
        value = localValueAtIndexOrNaN(x, idx);
end
end


function value = localValueAtIndexOrNaN(x, idx)
if isempty(idx)
    value = NaN;
else
    value = x(idx);
end
end


function [targetX, targetY, referenceTargetId] = localSelectTrialReferenceTarget(xPx, yPx, targetX, targetY, target2X, target2Y, targetChoice)
if nargin < 7 || isempty(targetChoice)
    targetChoice = 'closer';
end
targetChoice = validatestring(char(string(targetChoice)), {'closer', 'farther', 'target1', 'target2'});
referenceTargetId = 1;
if strcmp(targetChoice, 'target1')
    return
end
if ~any(isfinite(target2X(:)) & isfinite(target2Y(:)))
    return
end

if strcmp(targetChoice, 'target2')
    targetX = double(target2X(:));
    targetY = double(target2Y(:));
    referenceTargetId = 2;
    return
end

xPx = double(xPx(:));
yPx = double(yPx(:));
targetX = double(targetX(:));
targetY = double(targetY(:));
target2X = double(target2X(:));
target2Y = double(target2Y(:));

valid = isfinite(xPx) & isfinite(yPx) & ...
    isfinite(targetX) & isfinite(targetY) & ...
    isfinite(target2X) & isfinite(target2Y);
if ~any(valid)
    return
end

d1 = hypot(xPx(valid) - targetX(valid), yPx(valid) - targetY(valid));
d2 = hypot(xPx(valid) - target2X(valid), yPx(valid) - target2Y(valid));
meanD1 = mean(d1, 'omitnan');
meanD2 = mean(d2, 'omitnan');
chooseTarget2 = false;
switch targetChoice
    case 'closer'
        chooseTarget2 = isfinite(meanD2) && (~isfinite(meanD1) || meanD2 < meanD1);
    case 'farther'
        chooseTarget2 = isfinite(meanD2) && (~isfinite(meanD1) || meanD2 > meanD1);
end
if chooseTarget2
    targetX = target2X;
    targetY = target2Y;
    referenceTargetId = 2;
end
end


function [targetX, targetY, referenceTargetId] = localSelectRewardCenterReferenceTarget(targetX, targetY, target2X, target2Y, meta, targetMode)
targetMode = localResolveReferenceTargetMode(struct('referenceTargetMode', targetMode));
referenceTargetId = 1;
if ~localUsesRewardCenterTargetMode(targetMode)
    return
end
if ~isstruct(meta) || ~isfield(meta, 'gaussCenterPx') || numel(meta.gaussCenterPx) < 2 || ...
        any(~isfinite(double(meta.gaussCenterPx(1:2))))
    error('ccg:RewardCenterTargetModeUnavailable', ...
        'referenceTargetMode=''%s'' requires raw ex reward-center metadata from getGaussianCenterPx().', char(targetMode));
end
if ~any(isfinite(target2X(:)) & isfinite(target2Y(:)))
    return
end

targetX = double(targetX(:));
targetY = double(targetY(:));
target2X = double(target2X(:));
target2Y = double(target2Y(:));
ctr = double(meta.gaussCenterPx(1:2));

valid = isfinite(targetX) & isfinite(targetY) & isfinite(target2X) & isfinite(target2Y);
if ~any(valid)
    return
end

d1 = hypot(targetX(valid) - ctr(1), targetY(valid) - ctr(2));
d2 = hypot(target2X(valid) - ctr(1), target2Y(valid) - ctr(2));
meanD1 = mean(d1, 'omitnan');
meanD2 = mean(d2, 'omitnan');

chooseTarget2 = false;
if strcmp(targetMode, "targetCloser")
    chooseTarget2 = isfinite(meanD2) && (~isfinite(meanD1) || meanD2 < meanD1);
elseif strcmp(targetMode, "targetFarther")
    chooseTarget2 = isfinite(meanD2) && (~isfinite(meanD1) || meanD2 > meanD1);
end
if chooseTarget2
    targetX = target2X;
    targetY = target2Y;
    referenceTargetId = 2;
end
end


function mode = localResolveReferenceTargetMode(opts)
mode = "chunk";
if isstruct(opts) && isfield(opts, 'referenceTargetMode') && ~isempty(opts.referenceTargetMode)
    mode = string(opts.referenceTargetMode);
end
mode = lower(strtrim(mode(1)));
switch mode
    case "trial"
        mode = "trial";
    case "chunk"
        mode = "chunk";
    case {"targetcloser", "rewardcloser", "peakcloser"}
        mode = "targetCloser";
    case {"targetfarther", "rewardfarther", "peakfarther", "targetfurther", "rewardfurther", "peakfurther"}
        mode = "targetFarther";
    otherwise
        error('ccg:BadReferenceTargetMode', ...
            'opts.referenceTargetMode must be ''trial'', ''chunk'', ''targetCloser'', or ''targetFarther''.');
end
end


function tf = localUsesRewardCenterTargetMode(mode)
if isstruct(mode)
    mode = localResolveReferenceTargetMode(mode);
else
    mode = localResolveReferenceTargetMode(struct('referenceTargetMode', mode));
end
tf = strcmp(mode, "targetCloser") || strcmp(mode, "targetFarther");
end


function stepTable = localAnnotateBoundaryContact(stepTable, setup, graph, opts)
if isempty(stepTable)
    return
end
nRows = height(stepTable);
stepTable.referenceAtBoundary = false(nRows, 1);
stepTable.target2AtBoundary = false(nRows, 1);
hasGeometry = isstruct(setup) && isfield(setup, 'screenRect') && ...
    isstruct(graph) && isfield(graph, 'texture_dims') && isfield(graph, 'size_mult');
if ~hasGeometry
    if logical(opts.excludeBoundaryChunks)
        error('ccg:BoundaryGeometryUnavailable', ...
            'excludeBoundaryChunks requires ex.setup.screenRect and ex.exp.CoPs.graph texture geometry.');
    end
    return
end
stepTable.referenceAtBoundary = localTargetAtBoundary( ...
    stepTable.targetX, stepTable.targetY, setup, graph, opts);
if ismember('target2X', stepTable.Properties.VariableNames) && ismember('target2Y', stepTable.Properties.VariableNames)
    stepTable.target2AtBoundary = localTargetAtBoundary( ...
        stepTable.target2X, stepTable.target2Y, setup, graph, opts);
end
end


function atBoundary = localTargetAtBoundary(targetX, targetY, setup, graph, opts)
targetX = double(targetX(:));
targetY = double(targetY(:));
atBoundary = false(size(targetX));
if isempty(targetX) || numel(targetY) ~= numel(targetX)
    return
end
[bounds, ~] = localTextureBounds(setup.screenRect, graph);
marginPx = localResolveBoundaryMarginPx(setup, graph, opts);
valid = isfinite(targetX) & isfinite(targetY);
atBoundary(valid) = targetX(valid) <= bounds.xMin + marginPx | ...
    targetX(valid) >= bounds.xMax - marginPx | ...
    targetY(valid) <= bounds.yMin + marginPx | ...
    targetY(valid) >= bounds.yMax - marginPx;
end


function marginPx = localResolveBoundaryMarginPx(setup, graph, opts)
marginPx = NaN;
if isfield(opts, 'boundaryMarginDeg')
    marginDeg = double(localFirstScalar(opts.boundaryMarginDeg));
    if isfinite(marginDeg)
        dpp = px2deg(1, setup);
        if isfinite(dpp) && dpp > 0
            marginPx = marginDeg ./ dpp;
        end
    end
end
if ~isfinite(marginPx) && isfield(opts, 'boundaryMarginPx')
    marginPx = double(localFirstScalar(opts.boundaryMarginPx));
end
if ~isfinite(marginPx)
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
marginPx = max(0, double(marginPx));
end


function tf = localChunkTouchesBoundary(stepTable, ii, referenceTargetId)
tf = false;
vars = stepTable.Properties.VariableNames;
useTarget2Boundary = isfinite(referenceTargetId) && round(referenceTargetId) == 2 && ...
    ismember('target2AtBoundary', vars);
if useTarget2Boundary
    flag = stepTable.target2AtBoundary(ii);
elseif ismember('referenceAtBoundary', vars)
    flag = stepTable.referenceAtBoundary(ii);
else
    flag = false(numel(ii), 1);
end
tf = any(logical(flag(:)));
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


function group = localAggregateEpisodes(episodes, opts, commonDtStepSec)
group = struct('trials', [], 'lagSec', [], 'ccgX', [], 'ccgY', [], 'meanX', [], 'meanY', [], ...
    'aggregateX', [], 'aggregateY', [], ...
    'nChunksX', [], 'nChunksY', [], 'supportX', [], 'supportY', [], ...
    'stepAmpMinPx', NaN, 'stepAmpMaxPx', NaN, 'stepAmpMinDeg', NaN, 'stepAmpMaxDeg', NaN, ...
    'demeanMode', '');
if isempty(episodes)
    return
end

trialIds = unique(double(episodes.trial(:)'));
if nargin < 3 || ~isfinite(commonDtStepSec) || commonDtStepSec <= 0
    commonDtStepSec = localCommonDtStepSec(episodes.dtStepSec);
end
[stepAmpMinPx, stepAmpMaxPx, stepAmpMinDeg, stepAmpMaxDeg] = localResolveGroupStepAmpRange(episodes, opts);
[group.ccgX, lagSec] = localPerTrialCorrMatrix(episodes, trialIds, 'x', opts.ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, opts.demeanMode);
[group.ccgY, ~] = localPerTrialCorrMatrix(episodes, trialIds, 'y', opts.ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, opts.demeanMode);
group.trials = trialIds;
group.lagSec = lagSec;
group.meanX = mean(group.ccgX, 1, 'omitnan');
group.meanY = mean(group.ccgY, 1, 'omitnan');
[group.nChunksX, group.nChunksY] = localChunkCountsAcrossEpisodes(episodes, opts, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, opts.demeanMode);
[group.supportX, group.supportY] = localChunkSupportAcrossEpisodes(episodes, opts, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, opts.demeanMode);
[group.aggregateX, group.aggregateY] = localAggregateAcrossEpisodes(episodes, trialIds, opts, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, opts.demeanMode);
group.stepAmpMinPx = stepAmpMinPx;
group.stepAmpMaxPx = stepAmpMaxPx;
group.stepAmpMinDeg = stepAmpMinDeg;
group.stepAmpMaxDeg = stepAmpMaxDeg;
group.demeanMode = char(string(opts.demeanMode));
end


function [M, lagSec] = localPerTrialCorrMatrix(episodes, trialIds, axisName, ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode)
lagSec = [];
M = NaN(numel(trialIds), 0);
rows = cell(numel(trialIds),1);
demeanMode = localResolveDemeanMode(demeanMode);
globalMeans = localDefaultVelocityMeans();
if strcmp(demeanMode, 'global')
    globalMeans = localVelocityMeansForEpisodes(episodes, axisName, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx);
end
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
        M(i,:) = rows{i}.corr(:)';
    end
end
end


function row = localAggregateChunksForTrial(E, axisName, ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans)
row = struct('lagSec', NaN(0,1), 'corr', NaN(0,1), 'accum', NaN(0,1), ...
    'weightSum', NaN(0,1), 'nChunks', NaN(0,1), 'support', NaN(0,1));
if isempty(E)
    return
end
if nargin < 4 || ~isfinite(commonDtStepSec) || commonDtStepSec <= 0
    commonDtStepSec = localCommonDtStepSec(E.dtStepSec);
end
if nargin < 5
    stepAmpMinPx = NaN;
end
if nargin < 6
    stepAmpMaxPx = NaN;
end
if nargin < 7 || isempty(demeanMode)
    demeanMode = 'chunk';
end
demeanMode = localResolveDemeanMode(demeanMode);
if nargin < 8 || isempty(globalMeans)
    globalMeans = localDefaultVelocityMeans();
    if strcmp(demeanMode, 'global')
        globalMeans = localVelocityMeansForEpisodes(E, axisName, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx);
    end
end
for i = 1:height(E)
    trialMeans = localDefaultVelocityMeans();
    if strcmp(demeanMode, 'trial')
        trialMeans = localVelocityMeansForTrial(E, axisName, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, double(E.trial(i)));
    end
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
chunk = struct('lagSec', NaN(0,1), 'corr', NaN(0,1), 'accum', NaN(0,1), ...
    'weightSum', NaN(0,1), 'nChunks', NaN(0,1), 'support', NaN(0,1));
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
demeanMode = localResolveDemeanMode(demeanMode);
if nargin < 9 || isempty(trialMeans)
    trialMeans = localDefaultVelocityMeans();
end
if nargin < 10 || isempty(globalMeans)
    globalMeans = localDefaultVelocityMeans();
end
maxLagSamples = max(1, round(max(abs(ccgWindowSec)) / dtStepSec));
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
runEnds = [runStarts(2:end)-1; numel(idx)];
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
        good = good & (stepAmpPx >= stepAmpMinPx);
    end
    if isfinite(stepAmpMaxPx)
        good = good & (stepAmpPx < stepAmpMaxPx);
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


function [aggX, aggY] = localAggregateAcrossEpisodes(episodes, trialIds, opts, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode)
aggregateMode = validatestring(char(string(opts.aggregateMode)), {'chunk', 'trial'});
demeanMode = localResolveDemeanMode(demeanMode);
switch aggregateMode
    case 'trial'
        [M, ~] = localPerTrialCorrMatrix(episodes, trialIds, 'x', opts.ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode);
        aggX = mean(M, 1, 'omitnan');
        [M, ~] = localPerTrialCorrMatrix(episodes, trialIds, 'y', opts.ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode);
        aggY = mean(M, 1, 'omitnan');
    case 'chunk'
        globalMeans = localDefaultVelocityMeans();
        if strcmp(demeanMode, 'global')
            globalMeans = localVelocityMeansForEpisodes(episodes, 'x', commonDtStepSec, stepAmpMinPx, stepAmpMaxPx);
        end
        row = localAggregateChunksForTrial(episodes, 'x', opts.ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans);
        aggX = row.corr(:)';
        globalMeans = localDefaultVelocityMeans();
        if strcmp(demeanMode, 'global')
            globalMeans = localVelocityMeansForEpisodes(episodes, 'y', commonDtStepSec, stepAmpMinPx, stepAmpMaxPx);
        end
        row = localAggregateChunksForTrial(episodes, 'y', opts.ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans);
        aggY = row.corr(:)';
end
end


function [nChunksX, nChunksY] = localChunkCountsAcrossEpisodes(episodes, opts, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode)
demeanMode = localResolveDemeanMode(demeanMode);
globalMeans = localDefaultVelocityMeans();
if strcmp(demeanMode, 'global')
    globalMeans = localVelocityMeansForEpisodes(episodes, 'x', commonDtStepSec, stepAmpMinPx, stepAmpMaxPx);
end
row = localAggregateChunksForTrial(episodes, 'x', opts.ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans);
nChunksX = row.nChunks(:)';
globalMeans = localDefaultVelocityMeans();
if strcmp(demeanMode, 'global')
    globalMeans = localVelocityMeansForEpisodes(episodes, 'y', commonDtStepSec, stepAmpMinPx, stepAmpMaxPx);
end
row = localAggregateChunksForTrial(episodes, 'y', opts.ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans);
nChunksY = row.nChunks(:)';
end


function [supportX, supportY] = localChunkSupportAcrossEpisodes(episodes, opts, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode)
demeanMode = localResolveDemeanMode(demeanMode);
globalMeans = localDefaultVelocityMeans();
if strcmp(demeanMode, 'global')
    globalMeans = localVelocityMeansForEpisodes(episodes, 'x', commonDtStepSec, stepAmpMinPx, stepAmpMaxPx);
end
row = localAggregateChunksForTrial(episodes, 'x', opts.ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans);
supportX = row.support(:)';
globalMeans = localDefaultVelocityMeans();
if strcmp(demeanMode, 'global')
    globalMeans = localVelocityMeansForEpisodes(episodes, 'y', commonDtStepSec, stepAmpMinPx, stepAmpMaxPx);
end
row = localAggregateChunksForTrial(episodes, 'y', opts.ccgWindowSec, commonDtStepSec, stepAmpMinPx, stepAmpMaxPx, demeanMode, globalMeans);
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
        % Diagnostic mode: preserve absolute velocity offsets.
end
end


function means = localDefaultVelocityMeans()
means = struct('gaze', NaN, 'target', NaN);
end


function means = localVelocityMeansForEpisodes(episodes, axisName, dtStepSec, stepAmpMinPx, stepAmpMaxPx)
gazeAll = [];
targetAll = [];
if isempty(episodes)
    means = struct('gaze', NaN, 'target', NaN);
    return
end
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
        otherwise
            error('ccg:BadAxisName', 'axisName must be ''x'' or ''y''.');
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
    good = good & (stepAmpPx >= stepAmpMinPx);
end
if isfinite(stepAmpMaxPx)
    good = good & (stepAmpPx < stepAmpMaxPx);
end
gazeVel = gazeVel(good);
targetVel = targetVel(good);
end


function ccgTimebase = localResolveCcgTimebase(value)
if nargin < 1 || isempty(value)
    ccgTimebase = 'step';
    return
end
ccgTimebase = lower(strtrim(char(string(value))));
switch ccgTimebase
    case {'step', 'steps', 'stepwise'}
        ccgTimebase = 'step';
    case {'sample', 'samples', 'sampled', 'frame', 'frames', 'samplewise'}
        ccgTimebase = 'sample';
    otherwise
        error('ccg:BadCcgTimebase', ...
            'opts.ccgTimebase must be ''step'' or ''sample''.');
end
end


function demeanMode = localResolveDemeanMode(value)
if nargin < 1 || isempty(value)
    demeanMode = 'chunk';
    return
end
demeanMode = lower(strtrim(char(string(value))));
switch demeanMode
    case {'chunk', 'trial', 'global', 'none'}
        return
    otherwise
        error('ccg:BadDemeanMode', ...
            'opts.demeanMode must be ''chunk'', ''trial'', ''global'', or ''none''.');
end
end


function stepGazeSummary = localResolveStepGazeSummary(value)
if nargin < 1 || isempty(value)
    stepGazeSummary = 'mean';
    return
end
stepGazeSummary = lower(strtrim(char(string(value))));
switch stepGazeSummary
    case {'mean', 'first', 'middle', 'last'}
        return
    otherwise
        error('ccg:BadStepGazeSummary', ...
            'opts.stepGazeSummary must be ''mean'', ''first'', ''middle'', or ''last''.');
end
end


function y = localSafeWeightedMean(accum, weightSum)
y = NaN(size(accum));
valid = isfinite(weightSum) & (weightSum > 0);
y(valid) = accum(valid) ./ weightSum(valid);
end


function [stepAmpMinPx, stepAmpMaxPx, stepAmpMinDeg, stepAmpMaxDeg] = localResolveGroupStepAmpRange(episodes, opts)
stepAmpMinPx = NaN;
stepAmpMaxPx = NaN;
stepAmpMinDeg = NaN;
stepAmpMaxDeg = NaN;
if isempty(episodes)
    return
end

allAmpPx = [];
for i = 1:height(episodes)
    tx = double(episodes.targetX{i}(:));
    ty = double(episodes.targetY{i}(:));
    if numel(tx) < 2 || numel(ty) ~= numel(tx)
        continue
    end
    ampPx = hypot(diff(tx), diff(ty));
    ampPx = ampPx(isfinite(ampPx));
    if ~isempty(ampPx)
        allAmpPx = [allAmpPx; ampPx]; %#ok<AGROW>
    end
end
if isempty(allAmpPx)
    return
end

rangeCandidatesPx = [NaN NaN];
if isfield(opts, 'stepAmpAboveMean') && logical(opts.stepAmpAboveMean)
    rangeCandidatesPx = [mean(allAmpPx, 'omitnan') NaN];
end
if isfield(opts, 'stepAmpMinPrctile')
    prc = double(localFirstScalar(opts.stepAmpMinPrctile));
    if isfinite(prc)
        rangeCandidatesPx = [max(rangeCandidatesPx(1), prctile(allAmpPx, prc)) NaN];
    end
end
if isfield(opts, 'stepAmpMinDeg')
    minDeg = double(localFirstScalar(opts.stepAmpMinDeg));
    if isfinite(minDeg)
        setup = localResolveCcgSetupForTracking(opts);
        dpp = px2deg(1, setup);
        rangeCandidatesPx = [max(rangeCandidatesPx(1), minDeg ./ dpp) NaN];
    end
end
if isfield(opts, 'stepAmpPrctileRange') && ~isempty(opts.stepAmpPrctileRange)
    pRange = double(opts.stepAmpPrctileRange(:)');
    if numel(pRange) == 2
        if isfinite(pRange(1))
            rangeCandidatesPx(1) = max(rangeCandidatesPx(1), prctile(allAmpPx, pRange(1)));
        end
        if isfinite(pRange(2))
            if ~isfinite(rangeCandidatesPx(2))
                rangeCandidatesPx(2) = prctile(allAmpPx, pRange(2));
            else
                rangeCandidatesPx(2) = min(rangeCandidatesPx(2), prctile(allAmpPx, pRange(2)));
            end
        end
    end
end
if isfinite(rangeCandidatesPx(1)) && rangeCandidatesPx(1) < 0
    rangeCandidatesPx(1) = NaN;
end
stepAmpMinPx = rangeCandidatesPx(1);
stepAmpMaxPx = rangeCandidatesPx(2);
if isfield(opts, 'setup') && ~isempty(opts.setup)
    if isfinite(stepAmpMinPx)
        stepAmpMinDeg = px2deg(stepAmpMinPx, opts.setup);
    end
    if isfinite(stepAmpMaxPx)
        stepAmpMaxDeg = px2deg(stepAmpMaxPx, opts.setup);
    end
end
end


function [refGroupOut, refInfo] = localBuildReferenceGroupOut(ex, trialGroups, groupLabels, groupOptsList, globalDtStepSec, opts)
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
refGroupOptsList = groupOptsList;
for g = 1:nGroup
    refGroupOptsList{g}.trackingSource = 'model-free';
end
for r = 1:nRef
    refEpisodes = cell(nGroup, 1);
    for g = 1:nGroup
        if isempty(refTrialGroups{g, r})
            refEpisodes{g} = table();
        else
            refEpisodes{g} = localBuildEpisodeTableFromEx( ...
                ex, refTrialGroups{g, r}, g, refGroupOptsList{g});
        end
    end
    refAllEpisodes = vertcatNonEmptyTablesCoPs(refEpisodes);
    refDtStepSec = globalDtStepSec;
    if (~isfinite(refDtStepSec) || refDtStepSec <= 0) && ~isempty(refAllEpisodes) && ...
            ismember('dtStepSec', refAllEpisodes.Properties.VariableNames)
        refDtStepSec = localCommonDtStepSec(refAllEpisodes.dtStepSec);
    end

    for g = 1:nGroup
        if ~isempty(refAllEpisodes) && ismember('group', refAllEpisodes.Properties.VariableNames)
            refGroupOut{g, r} = localAggregateEpisodes(refAllEpisodes(refAllEpisodes.group == g, :), groupOptsList{g}, refDtStepSec);
        else
            refGroupOut{g, r} = localAggregateEpisodes(table(), groupOptsList{g}, refDtStepSec);
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


function localPlotCcgGroups(lagSec, groupOut, axisName, opts, groupIdx, legendLabelsOverride, rowLabel, refGroupOut)
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
            titleText = 'X Velocity CCG';
        case 'y'
            xc = groupOut{g}.aggregateY;
            titleText = 'Y Velocity CCG';
    end
    xc = double(xc(:));
    if isempty(lagSec) || isempty(xc) || numel(lagSec) ~= numel(xc)
        continue
    end
    plotCount = plotCount + 1;
    plotHandles(plotCount) = plot(lagSec, xc, 'Color', opts.colors(g, :), 'LineWidth', opts.lineWidth);
    if ~isempty(legendLabelsOverride) && numel(legendLabelsOverride) == numel(groupOut)
        label = string(legendLabelsOverride{g});
    elseif ~isempty(legendLabelsOverride) && numel(legendLabelsOverride) >= j
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
localApplyCcgWindowXLim(opts, lagSec);
xlabel('Lag (s)');
ylabel('xcorr');
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


function plotFacetSpec = localResolvePlotFacetSpec(trialNo, groupingSpec, in, inputMode, trialGroups, opts)
nGroup = numel(trialGroups);
plotFacetSpec = struct('enabled', false, 'nRows', 1, 'nLineGroups', nGroup, ...
    'rowGroupIdx', {{}}, 'rowLabels', strings(0, 1), ...
    'lineLabels', {{}}, 'groupLineLabels', {{}}, 'lineGroupIndex', (1:nGroup)');
if ~strcmp(inputMode, 'ex') || ~localIsNamedCodeCell(trialNo) || numel(trialNo) ~= 2
    return
end
code1 = localCanonicalGroupingCode(trialNo{1});
code2 = localCanonicalGroupingCode(trialNo{2});
if localIsPercentileCode(code1) || localIsPercentileCode(code2)
    return
end
ex = in;
labels1 = localGroupingLevelLabels(code1, groupingSpec, ex, opts);
labels2 = localGroupingLevelLabels(code2, groupingSpec, ex, opts);
if isempty(labels1) || isempty(labels2)
    return
end

groupRowLabels = strings(nGroup, 1);
groupLineLabels = strings(nGroup, 1);
useSpecLabels = false;
if isfield(groupingSpec, 'codeList') && isfield(groupingSpec, 'groupLevelLabels')
    specCodes = groupingSpec.codeList;
    for i = 1:numel(specCodes)
        specCodes{i} = localCanonicalGroupingCode(specCodes{i});
    end
    col1 = find(strcmp(specCodes, code1), 1, 'first');
    col2 = find(strcmp(specCodes, code2), 1, 'first');
    if ~isempty(col1) && ~isempty(col2) && size(groupingSpec.groupLevelLabels, 1) == nGroup
        groupRowLabels = string(groupingSpec.groupLevelLabels(:, col1));
        groupLineLabels = string(groupingSpec.groupLevelLabels(:, col2));
        useSpecLabels = true;
    end
end
if ~useSpecLabels
    for g = 1:nGroup
        if isempty(trialGroups{g})
            continue
        end
        tr = trialGroups{g}(1);
        if tr < 1 || tr > numel(ex.Trials)
            continue
        end
        T = ex.Trials(tr);
        groupRowLabels(g) = localTrialGroupingLevelLabel(code1, ex, T, tr, opts);
        groupLineLabels(g) = localTrialGroupingLevelLabel(code2, ex, T, tr, opts);
    end
end
validGroups = strlength(strtrim(groupRowLabels)) > 0 & strlength(strtrim(groupLineLabels)) > 0;
if ~any(validGroups)
    return
end

rowLabels = labels1(:);
for g = find(validGroups(:))'
    if ~any(strcmp(rowLabels, groupRowLabels(g)))
        rowLabels(end+1,1) = groupRowLabels(g); %#ok<AGROW>
    end
end
hasRow = false(numel(rowLabels), 1);
for i = 1:numel(rowLabels)
    hasRow(i) = any(validGroups & strcmp(groupRowLabels, rowLabels(i)));
end
rowLabels = rowLabels(hasRow);

lineLabels = labels2(:);
for g = find(validGroups(:))'
    if ~any(strcmp(lineLabels, groupLineLabels(g)))
        lineLabels(end+1,1) = groupLineLabels(g); %#ok<AGROW>
    end
end

lineGroupIndex = ones(nGroup, 1);
for g = 1:nGroup
    idx = find(strcmp(lineLabels, groupLineLabels(g)), 1, 'first');
    if ~isempty(idx)
        lineGroupIndex(g) = idx;
    end
end

plotFacetSpec.enabled = true;
plotFacetSpec.nRows = numel(rowLabels);
plotFacetSpec.nLineGroups = numel(lineLabels);
plotFacetSpec.rowGroupIdx = cell(plotFacetSpec.nRows, 1);
plotFacetSpec.rowLabels = rowLabels(:);
plotFacetSpec.lineLabels = cellstr(lineLabels(:));
plotFacetSpec.groupLineLabels = cellstr(groupLineLabels(:));
plotFacetSpec.lineGroupIndex = lineGroupIndex(:);
for i = 1:plotFacetSpec.nRows
    plotFacetSpec.rowGroupIdx{i} = find(validGroups & strcmp(groupRowLabels, rowLabels(i))).';
end
end


function n = localGroupingLevelCount(code, groupingSpec, ex, opts)
if nargin < 4
    opts = struct();
end
labels = localGroupingLevelLabels(code, groupingSpec, ex, opts);
n = numel(labels);
end


function labels = localGroupingLevelLabels(code, groupingSpec, ex, opts)
if nargin < 4
    opts = struct();
end
code = localCanonicalGroupingCode(code);
if localIsPercentileCode(code)
    labels = localPercentileGroupLabels(localPercentileEdges(code));
    return
end
switch code
    case 'all'
        labels = "all";
    case 'pur'
        labels = "pur";
    case 'pre'
        labels = "pre";
    case {'bg', 'vis', 'vislvl3', 'tnum', 'im'}
        groups = localResolveNamedTrialGroups(code, 1:numel(ex.Trials), ex, 'ex', opts);
        labels = strings(numel(groups), 1);
        for i = 1:numel(groups)
            tmp = localBuildGroupLabels({code}, groups(i), ex, 'ex', opts);
            labels(i) = tmp(1);
        end
    case 'rq'
        labels = localRewardQuadLabels();
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
inText = string(in);
prefixText = string(prefix);
if startsWith(lower(inText), lower(prefixText))
    out = extractAfter(inText, strlength(prefixText));
else
    out = inText;
end
end


function label = localTrialGroupingLevelLabel(code, ex, T, trialNo, opts)
if nargin < 5
    opts = struct();
end
code = localCanonicalGroupingCode(code);
label = "";
switch code
    case 'all'
        label = "all";
    case 'pur'
        label = "pur";
    case 'pre'
        label = "pre";
    case 'bg'
        label = string(localTrialBackgroundNoiseLevel(T));
    case 'vis'
        label = string(localTrialTargetVisibility(ex, T));
    case 'vislvl3'
        label = localVisibilityLevel3Label(localTrialTargetVisibility(ex, T), opts);
    case 'tnum'
        label = string(localTrialTargetNum(ex, T));
    case 'im'
        label = localTrialImageName(ex, T, trialNo);
    case 'rq'
        label = "";
end
label = strip(string(label));
if ismissing(label) || strcmp(label, "NaN")
    label = "";
end
end


function label = localVisibilityLevel3Label(value, opts)
if nargin < 2
    opts = struct();
end
edges = localResolveVisLvl3Edges(opts);
value = double(value);
label = "";
if ~isscalar(value) || ~isfinite(value)
    return
end
if value < edges(1)
    label = "low";
elseif value < edges(2)
    label = "mid";
else
    label = "high";
end
end


function edges = localResolveVisLvl3Edges(opts)
edges = [0.75, 0.9];
if isstruct(opts) && isfield(opts, 'visLvls') && ~isempty(opts.visLvls)
    candidate = double(opts.visLvls(:)');
    candidate = candidate(isfinite(candidate));
    if numel(candidate) ~= 2 || candidate(2) <= candidate(1)
        error('ccg:BadVisLvls', ...
            'opts.visLvls must be two increasing finite values, e.g. [0.75 0.9].');
    end
    edges = candidate;
end
end


function groupLabels = localBuildGroupLabels(trialNo, trialGroups, in, inputMode, opts)
if nargin < 5
    opts = struct();
end
nGroup = numel(trialGroups);
groupLabels = strings(nGroup, 1);
if isempty(trialGroups)
    return
end
if isempty(trialNo)
    groupLabels(:) = "all";
    return
end
if ~(strcmp(inputMode, 'ex') && localIsExStruct(in))
    if ischar(trialNo) || (isstring(trialNo) && isscalar(trialNo)) && strcmpi(char(string(trialNo)), 'all')
        groupLabels(:) = "all";
    else
        for i = 1:nGroup
            groupLabels(i) = "group " + string(i);
        end
    end
    return
end
ex = in;
if localIsPercentileGrouping(trialNo)
    edges = localPercentileEdges(trialNo);
    groupLabels = localPercentileGroupLabels(edges);
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
        code = localCanonicalGroupingCode(codeList{k});
        switch code
            case 'all'
                parts(end+1,1) = "all"; %#ok<AGROW>
            case 'pur'
                parts(end+1,1) = "pur"; %#ok<AGROW>
            case 'pre'
                parts(end+1,1) = "pre"; %#ok<AGROW>
            case 'bg'
                parts(end+1,1) = "bg: " + string(localTrialBackgroundNoiseLevel(T)); %#ok<AGROW>
            case 'vis'
                parts(end+1,1) = "vis: " + string(localTrialTargetVisibility(ex, T)); %#ok<AGROW>
            case 'vislvl3'
                parts(end+1,1) = "visLvl3: " + localVisibilityLevel3Label(localTrialTargetVisibility(ex, T), opts); %#ok<AGROW>
            case 'tnum'
                parts(end+1,1) = "tnum: " + string(localTrialTargetNum(ex, T)); %#ok<AGROW>
            case 'im'
                parts(end+1,1) = "im: " + localTrialImageName(ex, T, tr); %#ok<AGROW>
            case 'rq'
                parts(end+1,1) = "rq"; %#ok<AGROW>
        end
    end
    groupLabels(i) = strjoin(parts, " | ");
end
end


function tf = localIsPercentileGrouping(trialNo)
if ischar(trialNo) || (isstring(trialNo) && isscalar(trialNo))
    tf = localIsPercentileCode(char(string(trialNo)));
    return
end
if iscell(trialNo) && ~isempty(trialNo)
    tf = true;
    for i = 1:numel(trialNo)
        item = trialNo{i};
        if ~(ischar(item) || (isstring(item) && isscalar(item)))
            tf = false;
            return
        end
        if ~localIsPercentileCode(char(string(item)))
            tf = false;
            return
        end
    end
    return
end
tf = false;
end


function tf = localIsPercentileCode(code)
tf = ~isempty(regexp(lower(strtrim(code)), '^p\d+(\.\d+)?$', 'once'));
end


function code = localCanonicalGroupingCode(code)
code = lower(strtrim(char(string(code))));
if localIsRewardQuadCode(code)
    code = 'rq';
elseif ismember(code, {'pur', 'purs', 'pursuit', 'pursuittrial', 'pursuittrials'})
    code = 'pur';
elseif ismember(code, {'pre', 'preblock', 'pretrial', 'pretrials'})
    code = 'pre';
elseif ismember(code, {'vislvl3', 'vislevel3', 'visibilitylvl3', 'visibilitylevel3'})
    code = 'vislvl3';
end
end


function tf = localIsRewardQuadCode(code)
code = lower(strtrim(char(string(code))));
tf = ismember(code, {'rq', 'rewq', 'rquad', 'rewardquad', 'rewardquadrant'});
end


function labels = localRewardQuadLabels()
labels = ["far"; "mid"; "close"];
end


function tf = localUsesRewardQuadFilter(opts)
tf = isstruct(opts) && isfield(opts, 'rewardQuadClass') && ~isempty(opts.rewardQuadClass) && ...
    strlength(strtrim(string(opts.rewardQuadClass))) > 0;
end


function className = localCanonicalRewardQuadClass(value)
className = lower(strtrim(char(string(value))));
switch className
    case {'far', 'zero', 'none', 'low'}
        className = 'far';
    case {'mid', 'middle', 'partial'}
        className = 'mid';
    case {'close', 'near', 'high', 'peak'}
        className = 'close';
    otherwise
        error('ccg:BadRewardQuadClass', ...
            'rewardQuadClass must be ''far'', ''mid'', or ''close''.');
end
end


function codeList = localCodeList(trialNo)
codeList = {};
if ischar(trialNo) || (isstring(trialNo) && isscalar(trialNo))
    codeList = {char(string(trialNo))};
elseif iscell(trialNo) && ~isempty(trialNo)
    allString = true;
    for i = 1:numel(trialNo)
        item = trialNo{i};
        if ~(ischar(item) || (isstring(item) && isscalar(item)))
            allString = false;
            break
        end
    end
    if allString
        codeList = cellfun(@(x) char(string(x)), trialNo, 'UniformOutput', false);
    end
end
end


function edges = localPercentileEdges(trialNo)
if ischar(trialNo) || (isstring(trialNo) && isscalar(trialNo))
    codeList = {char(string(trialNo))};
else
    codeList = cellfun(@(x) char(string(x)), trialNo, 'UniformOutput', false);
end
edges = NaN(1, numel(codeList));
for i = 1:numel(codeList)
    edges(i) = str2double(regexprep(lower(strtrim(codeList{i})), '^p', ''));
end
edges = unique(sort(edges));
end


function labels = localPercentileGroupLabels(edges)
edges = edges(:)';
labels = strings(numel(edges) + 1, 1);
if isempty(edges)
    labels = "all";
    return
end
labels(1) = "< p" + string(edges(1));
for i = 2:numel(edges)
    labels(i) = "p" + string(edges(i-1)) + " - p" + string(edges(i));
end
labels(end) = "> p" + string(edges(end));
end


function groupOpts = localOptsWithPercentileBin(opts, edges, binIdx)
groupOpts = opts;
if binIdx <= numel(edges)
    upperEdge = edges(binIdx);
else
    upperEdge = inf;
end
if binIdx == 1
    lowerEdge = -inf;
else
    lowerEdge = edges(binIdx - 1);
end
pRange = [NaN NaN];
if isfinite(lowerEdge)
    pRange(1) = lowerEdge;
end
if isfinite(upperEdge)
    pRange(2) = upperEdge;
end
groupOpts.stepAmpPrctileRange = pRange;
groupOpts.stepAmpAboveMean = false;
groupOpts.stepAmpMinPrctile = [];
groupOpts.stepAmpMinDeg = [];
end


function inputMode = localResolveInputMode(in)
if localIsExStruct(in)
    inputMode = 'ex';
elseif localIsTrackingTable(in)
    inputMode = 'tracking';
else
    error('ccg:BadInput', ...
        'First input must be an ex struct with Trials or a tracking table from processCoPsEye().');
end
end


function availableTrials = localApplyPursuitTrialSelection(trialNo, availableTrials, in, inputMode)
requestedPursuit = localRequestsPursuitTrials(trialNo);
requestedPre = localRequestsPreTrials(trialNo);
switch inputMode
    case 'ex'
        pursuitTrials = localPursuitTrialNumbersFromEx(in);
        preTrials = localPreTrialNumbersFromEx(in);
    case 'tracking'
        pursuitTrials = localPursuitTrialNumbersFromTracking(in);
        preTrials = localPreTrialNumbersFromTracking(in);
    otherwise
        pursuitTrials = [];
        preTrials = [];
end

if requestedPursuit && requestedPre
    error('ccg:IncompatibleTrialSelectors', ...
        'Request either pursuit trials or preblock trials, not both.');
elseif requestedPursuit
    availableTrials = intersect(availableTrials, pursuitTrials, 'stable');
    if isempty(availableTrials)
        error('ccg:NoPursuitTrials', ...
            'No pursuit trials were available. Expected isPursuitTrial=true or runPhase=''pursuit'' trial metadata.');
    end
elseif requestedPre
    availableTrials = intersect(availableTrials, preTrials, 'stable');
    if isempty(availableTrials)
        error('ccg:NoPreTrials', ...
            'No preblock trials were available. Expected isPreTrial=true or runPhase=''pre'' trial metadata.');
    end
else
    availableTrials = setdiff(availableTrials, unique([pursuitTrials, preTrials]), 'stable');
end
end


function tf = localRequestsPursuitTrials(trialNo)
codeList = localCodeList(trialNo);
tf = false;
for i = 1:numel(codeList)
    if strcmp(localCanonicalGroupingCode(codeList{i}), 'pur')
        tf = true;
        return
    end
end
end


function tf = localRequestsPreTrials(trialNo)
codeList = localCodeList(trialNo);
tf = false;
for i = 1:numel(codeList)
    if strcmp(localCanonicalGroupingCode(codeList{i}), 'pre')
        tf = true;
        return
    end
end
end


function trialVec = localPursuitTrialNumbersFromEx(ex)
trialVec = [];
if ~isfield(ex, 'Trials') || isempty(ex.Trials)
    return
end
isPur = false(1, numel(ex.Trials));
for j = 1:numel(ex.Trials)
    T = ex.Trials(j);
    if isfield(T, 'isPursuitTrial') && ~isempty(T.isPursuitTrial)
        v = T.isPursuitTrial;
        if (isnumeric(v) || islogical(v)) && isfinite(double(v(1)))
            isPur(j) = logical(v(1));
            continue
        end
    end
    if isfield(T, 'runPhase') && ~isempty(T.runPhase)
        phase = lower(strtrim(char(string(T.runPhase))));
        isPur(j) = strcmp(phase, 'pursuit');
    end
end
trialVec = find(isPur);
end


function trialVec = localPreTrialNumbersFromEx(ex)
trialVec = [];
if ~isfield(ex, 'Trials') || isempty(ex.Trials)
    return
end
isPre = false(1, numel(ex.Trials));
for j = 1:numel(ex.Trials)
    T = ex.Trials(j);
    if isfield(T, 'isPreTrial') && ~isempty(T.isPreTrial)
        v = T.isPreTrial;
        if (isnumeric(v) || islogical(v)) && isfinite(double(v(1)))
            isPre(j) = logical(v(1));
            continue
        end
    end
    if isfield(T, 'runPhase') && ~isempty(T.runPhase)
        phase = lower(strtrim(char(string(T.runPhase))));
        isPre(j) = strcmp(phase, 'pre');
    end
end
trialVec = find(isPre);
end


function trialVec = localPursuitTrialNumbersFromTracking(trackingTable)
trialVec = [];
if ~istable(trackingTable) || ~ismember('trial', trackingTable.Properties.VariableNames)
    return
end
vars = trackingTable.Properties.VariableNames;
hasPurFlag = ismember('isPursuitTrial', vars);
hasRunPhase = ismember('runPhase', vars);
if ~hasPurFlag && ~hasRunPhase
    return
end
trialIds = unique(double(trackingTable.trial(:))', 'stable');
isPur = false(size(trialIds));
for i = 1:numel(trialIds)
    rows = double(trackingTable.trial) == trialIds(i);
    if hasPurFlag
        v = trackingTable.isPursuitTrial(rows);
        if isnumeric(v) || islogical(v)
            isPur(i) = any(logical(v(:)));
        end
    end
    if ~isPur(i) && hasRunPhase
        isPur(i) = any(strcmpi(strtrim(string(trackingTable.runPhase(rows))), "pursuit"));
    end
end
trialVec = trialIds(isPur);
end


function trialVec = localPreTrialNumbersFromTracking(trackingTable)
trialVec = [];
if ~istable(trackingTable) || ~ismember('trial', trackingTable.Properties.VariableNames)
    return
end
vars = trackingTable.Properties.VariableNames;
hasPreFlag = ismember('isPreTrial', vars);
hasRunPhase = ismember('runPhase', vars);
if ~hasPreFlag && ~hasRunPhase
    return
end
trialIds = unique(double(trackingTable.trial(:))', 'stable');
isPre = false(size(trialIds));
for i = 1:numel(trialIds)
    rows = double(trackingTable.trial) == trialIds(i);
    if hasPreFlag
        v = trackingTable.isPreTrial(rows);
        if isnumeric(v) || islogical(v)
            isPre(i) = any(logical(v(:)));
        end
    end
    if ~isPre(i) && hasRunPhase
        isPre(i) = any(strcmpi(strtrim(string(trackingTable.runPhase(rows))), "pre"));
    end
end
trialVec = trialIds(isPre);
end


function code = localResolveFromState(value)
if isempty(value)
    code = 'all';
    return
end
code = lower(strtrim(char(string(value))));
switch code
    case 'all'
        code = 'all';
    case 'smooth'
        code = 'smooth';
    case {'fix', 'fixation'}
        code = 'fixation';
    case {'sac', 'sacc', 'saccade'}
        code = 'saccade';
    otherwise
        error('ccg:BadFromState', ...
            'opts.fromState must be ''all'', ''smooth'', ''fix''/''fixation'', or ''sac''/''sacc''/''saccade''.');
end
end


function mask = localStateMaskForCode(samples, fromState)
switch fromState
    case 'smooth'
        mask = logical(samples.isSmoothPursuit);
    case 'fixation'
        mask = logical(samples.isFixation);
    case 'saccade'
        mask = logical(samples.isSaccade);
    otherwise
        mask = true(height(samples), 1);
end
mask = mask(:);
end


function [groupingSpec, trialGroups, groupLabels, groupOptsList] = localResolveGroupingSpec(trialNo, availableTrials, in, inputMode, opts)
groupingSpec = struct('mode', 'trial', 'percentileEdges', []);
codeList = localCodeList(trialNo);
if ~isempty(codeList)
    for i = 1:numel(codeList)
        codeList{i} = localCanonicalGroupingCode(codeList{i});
    end
    isRewardQuad = cellfun(@localIsRewardQuadCode, codeList);
    if any(isRewardQuad)
        if ~strcmp(inputMode, 'ex')
            error('ccg:RewardQuadRequiresEx', ...
                'Reward-quadrant grouping ''rq'' requires raw ex input.');
        end
        if sum(isRewardQuad) > 1
            error('ccg:DuplicateRewardQuadGrouping', ...
                'Reward-quadrant grouping ''rq'' can be requested only once.');
        end
        baseCodeList = codeList(~isRewardQuad);
        if any(cellfun(@localIsPercentileCode, baseCodeList))
            error('ccg:RewardQuadPercentileUnsupported', ...
                'Reward-quadrant grouping ''rq'' can be combined with trial-level codes such as ''bg'' or ''vis'', not percentile step-amplitude bins.');
        end
        groupingSpec.mode = 'rewardQuadChunks';
        groupingSpec.codeList = codeList;
        [trialGroups, groupLabels, groupOptsList, groupLevelLabels] = localResolveRewardQuadGrouping( ...
            baseCodeList, availableTrials, in, inputMode, opts, codeList);
        groupingSpec.rewardQuadLabels = localRewardQuadLabels();
        groupingSpec.groupLevelLabels = groupLevelLabels;
        return
    end
    isPercentile = cellfun(@localIsPercentileCode, codeList);
    if any(isPercentile) && any(~isPercentile)
        if sum(isPercentile) > 1
            error('ccg:BadPercentileGrouping', ...
                'Multiple percentile codes can only be combined with other percentile codes.');
        end
        edges = localPercentileEdges(codeList(isPercentile));
        groupingSpec.mode = 'hybridStepAmpPercentileBins';
        groupingSpec.percentileEdges = edges;
        baseSelector = codeList(~isPercentile);
        if numel(baseSelector) == 1
            baseSelector = baseSelector{1};
        end
        baseTrialGroups = localNormalizeTrialGroups(baseSelector, availableTrials, in, inputMode, opts);
        baseLabels = localBuildGroupLabels(baseSelector, baseTrialGroups, in, inputMode, opts);
        pLabels = localPercentileGroupLabels(edges);
        nBase = numel(baseTrialGroups);
        nBins = numel(pLabels);
        trialGroups = cell(nBase * nBins, 1);
        groupLabels = strings(nBase * nBins, 1);
        groupOptsList = cell(nBase * nBins, 1);
        idx = 0;
        for iBase = 1:nBase
            for iBin = 1:nBins
                idx = idx + 1;
                trialGroups{idx} = baseTrialGroups{iBase};
                groupLabels(idx) = baseLabels(iBase) + " | " + pLabels(iBin);
                groupOptsList{idx} = localOptsWithPercentileBin(opts, edges, iBin);
            end
        end
        return
    end
end

trialGroups = localNormalizeTrialGroups(trialNo, availableTrials, in, inputMode, opts);
groupLabels = localBuildGroupLabels(trialNo, trialGroups, in, inputMode, opts);
groupOptsList = repmat({opts}, numel(trialGroups), 1);
if ~localIsPercentileGrouping(trialNo)
    return
end
edges = localPercentileEdges(trialNo);
groupingSpec.mode = 'stepAmpPercentileBins';
groupingSpec.percentileEdges = edges;
trialGroups = repmat({availableTrials}, numel(edges) + 1, 1);
groupLabels = localPercentileGroupLabels(edges);
groupOptsList = repmat({opts}, numel(trialGroups), 1);
for i = 1:numel(groupOptsList)
    groupOptsList{i} = localOptsWithPercentileBin(opts, edges, i);
end
end


function [trialGroups, groupLabels, groupOptsList, groupLevelLabels] = localResolveRewardQuadGrouping( ...
    baseCodeList, availableTrials, in, inputMode, opts, fullCodeList)
if isempty(baseCodeList)
    baseTrialGroups = {availableTrials};
    baseLabels = "all";
else
    if numel(baseCodeList) == 1
        baseSelector = baseCodeList{1};
    else
        baseSelector = baseCodeList;
    end
    baseTrialGroups = localNormalizeTrialGroups(baseSelector, availableTrials, in, inputMode, opts);
    baseLabels = localBuildGroupLabels(baseSelector, baseTrialGroups, in, inputMode, opts);
end

rqLabels = localRewardQuadLabels();
nBase = numel(baseTrialGroups);
nRq = numel(rqLabels);
nCode = numel(fullCodeList);
trialGroups = cell(nBase * nRq, 1);
groupLabels = strings(nBase * nRq, 1);
groupOptsList = cell(nBase * nRq, 1);
groupLevelLabels = strings(nBase * nRq, nCode);

baseLevelLabels = strings(nBase, numel(baseCodeList));
if ~isempty(baseCodeList)
    ex = in;
    for iBase = 1:nBase
        tr = baseTrialGroups{iBase}(1);
        T = ex.Trials(tr);
        for k = 1:numel(baseCodeList)
            baseLevelLabels(iBase, k) = localTrialGroupingLevelLabel(baseCodeList{k}, ex, T, tr, opts);
        end
    end
end

idx = 0;
for iBase = 1:nBase
    for iRq = 1:nRq
        idx = idx + 1;
        trialGroups{idx} = baseTrialGroups{iBase};
        groupOpts = opts;
        groupOpts.rewardQuadClass = char(rqLabels(iRq));
        groupOptsList{idx} = groupOpts;

        rqPart = "rq: " + rqLabels(iRq);
        if isempty(baseCodeList) || strcmp(baseLabels(iBase), "all")
            groupLabels(idx) = rqPart;
        else
            groupLabels(idx) = baseLabels(iBase) + " | " + rqPart;
        end

        for kCode = 1:nCode
            if localIsRewardQuadCode(fullCodeList{kCode})
                groupLevelLabels(idx, kCode) = rqLabels(iRq);
            else
                baseIdx = find(strcmp(baseCodeList, fullCodeList{kCode}), 1, 'first');
                if ~isempty(baseIdx)
                    groupLevelLabels(idx, kCode) = baseLevelLabels(iBase, baseIdx);
                end
            end
        end
    end
end
end


function tf = localIsExStruct(in)
tf = isstruct(in) && isfield(in, 'Trials') && ~isempty(in.Trials);
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


function tf = localIsTrackingTable(in)
requiredVars = {'trial','intervalNo','step','xPx','yPx','trackedTargetX','trackedTargetY','isTracking'};
tf = istable(in) && all(ismember(requiredVars, in.Properties.VariableNames));
end


function setup = localResolveCcgSetupForTracking(opts)
setup = [];
if isfield(opts, 'setup') && ~isempty(opts.setup)
    setup = opts.setup;
end
if isempty(setup)
    error('ccg:MissingSetup', ...
        'opts.setup is required for tracking-table input when removeSaccadesForCcg is true or stepAmpMinDeg is set.');
end
end


function episodes = localShuffleEpisodeGazeAcrossTrials(episodes, opts)
if isempty(episodes) || height(episodes) == 0
    return
end

trialIds = unique(double(episodes.trial(:))', 'stable');
if numel(trialIds) < 2
    return
end

seed = double(localFirstScalar(opts.shuffleSeed));
if isfinite(seed)
    prevRng = rng;
    cleanupObj = onCleanup(@() rng(prevRng)); %#ok<NASGU>
    rng(seed);
end

permOrder = randperm(numel(trialIds));
if all(permOrder == 1:numel(trialIds))
    permOrder = circshift(permOrder, 1);
end
donorTrialIds = trialIds(permOrder);

for iTrial = 1:numel(trialIds)
    recipTrial = trialIds(iTrial);
    donorTrial = donorTrialIds(iTrial);
    recipRows = find(double(episodes.trial) == recipTrial);
    donorRows = find(double(episodes.trial) == donorTrial);
    if isempty(recipRows) || isempty(donorRows)
        continue
    end
    recipRows = recipRows(localSortEpisodeRows(episodes(recipRows, :)));
    donorRows = donorRows(localSortEpisodeRows(episodes(donorRows, :)));
    for k = 1:numel(recipRows)
        donorRow = donorRows(mod(k - 1, numel(donorRows)) + 1);
        recipRow = recipRows(k);
        [gazeX, gazeY] = localRemapDonorGazeToRecipient( ...
            episodes.step{recipRow}, episodes.step{donorRow}, ...
            episodes.gazeX{donorRow}, episodes.gazeY{donorRow});
        episodes.gazeX{recipRow} = gazeX;
        episodes.gazeY{recipRow} = gazeY;
    end
end
end


function episodes = localShuffleEpisodeGazeWithinTrials(episodes, opts)
if isempty(episodes) || height(episodes) == 0
    return
end

seed = double(localFirstScalar(opts.shuffleSeed));
if isfinite(seed)
    prevRng = rng;
    cleanupObj = onCleanup(@() rng(prevRng));
    rng(seed);
end

trialIds = unique(double(episodes.trial(:))', 'stable');
for iTrial = 1:numel(trialIds)
    trialRows = find(double(episodes.trial) == trialIds(iTrial));
    if isempty(trialRows)
        continue
    end
    trialRows = trialRows(localSortEpisodeRows(episodes(trialRows, :)));

    rowLengths = zeros(numel(trialRows), 1);
    for k = 1:numel(trialRows)
        rowLengths(k) = numel(episodes.gazeX{trialRows(k)});
    end
    nGaze = sum(rowLengths);
    if nGaze < 2
        continue
    end

    gazeX = NaN(nGaze, 1);
    gazeY = NaN(nGaze, 1);
    cursor = 1;
    for k = 1:numel(trialRows)
        row = trialRows(k);
        nRow = rowLengths(k);
        if nRow == 0
            continue
        end
        rowIdx = cursor:(cursor + nRow - 1);
        gazeX(rowIdx) = double(episodes.gazeX{row}(:));
        gazeY(rowIdx) = double(episodes.gazeY{row}(:));
        cursor = cursor + nRow;
    end

    permOrder = randperm(nGaze);
    gazeX = gazeX(permOrder);
    gazeY = gazeY(permOrder);

    cursor = 1;
    for k = 1:numel(trialRows)
        row = trialRows(k);
        nRow = rowLengths(k);
        if nRow == 0
            continue
        end
        rowIdx = cursor:(cursor + nRow - 1);
        episodes.gazeX{row} = reshape(gazeX(rowIdx), size(episodes.gazeX{row}));
        episodes.gazeY{row} = reshape(gazeY(rowIdx), size(episodes.gazeY{row}));
        cursor = cursor + nRow;
    end
end
end


function episodes = localShuffleEpisodeGazeCircularWithinTrials(episodes, opts)
if isempty(episodes) || height(episodes) == 0
    return
end

seed = double(localFirstScalar(opts.shuffleSeed));
if isfinite(seed)
    prevRng = rng;
    cleanupObj = onCleanup(@() rng(prevRng)); %#ok<NASGU>
    rng(seed);
end

trialIds = unique(double(episodes.trial(:))', 'stable');
for iTrial = 1:numel(trialIds)
    trialRows = find(double(episodes.trial) == trialIds(iTrial));
    if isempty(trialRows)
        continue
    end
    trialRows = trialRows(localSortEpisodeRows(episodes(trialRows, :)));

    rowLengths = zeros(numel(trialRows), 1);
    for k = 1:numel(trialRows)
        rowLengths(k) = numel(episodes.gazeX{trialRows(k)});
    end
    nGaze = sum(rowLengths);
    if nGaze < 4
        continue
    end

    minShiftSteps = localResolveCircularMinShiftSteps(episodes, trialRows, opts);
    if ~isfinite(minShiftSteps) || minShiftSteps < 1
        minShiftSteps = 1;
    end
    minShiftSteps = min(round(minShiftSteps), floor((nGaze - 1) / 2));
    if minShiftSteps < 1
        continue
    end

    validShifts = [minShiftSteps:(nGaze - minShiftSteps)];
    if isempty(validShifts)
        continue
    end
    shiftSteps = validShifts(randi(numel(validShifts)));

    gazeX = NaN(nGaze, 1);
    gazeY = NaN(nGaze, 1);
    cursor = 1;
    for k = 1:numel(trialRows)
        row = trialRows(k);
        nRow = rowLengths(k);
        if nRow == 0
            continue
        end
        rowIdx = cursor:(cursor + nRow - 1);
        gazeX(rowIdx) = double(episodes.gazeX{row}(:));
        gazeY(rowIdx) = double(episodes.gazeY{row}(:));
        cursor = cursor + nRow;
    end

    gazeX = circshift(gazeX, shiftSteps);
    gazeY = circshift(gazeY, shiftSteps);

    cursor = 1;
    for k = 1:numel(trialRows)
        row = trialRows(k);
        nRow = rowLengths(k);
        if nRow == 0
            continue
        end
        rowIdx = cursor:(cursor + nRow - 1);
        episodes.gazeX{row} = reshape(gazeX(rowIdx), size(episodes.gazeX{row}));
        episodes.gazeY{row} = reshape(gazeY(rowIdx), size(episodes.gazeY{row}));
        cursor = cursor + nRow;
    end
end
end


function minShiftSteps = localResolveCircularMinShiftSteps(episodes, trialRows, opts)
minShiftSteps = double(localFirstScalar(opts.shuffleCircularMinShiftSteps));
if isfinite(minShiftSteps) && minShiftSteps > 0
    return
end

minShiftSec = double(localFirstScalar(opts.shuffleCircularMinShiftSec));
if ~isfinite(minShiftSec) || minShiftSec <= 0
    minShiftSec = max(abs(double(opts.ccgWindowSec(:))));
end

dtStepSec = NaN;
if ismember('dtStepSec', episodes.Properties.VariableNames)
    dtStepSec = median(double(episodes.dtStepSec(trialRows)), 'omitnan');
    if ~isfinite(dtStepSec) || dtStepSec <= 0
        dtStepSec = localFirstFinite(double(episodes.dtStepSec(:)));
    end
end
if ~isfinite(dtStepSec) || dtStepSec <= 0
    minShiftSteps = 1;
else
    minShiftSteps = ceil(minShiftSec / dtStepSec);
end
end


function sortIdx = localSortEpisodeRows(T)
if isempty(T)
    sortIdx = zeros(0, 1);
    return
end
if ismember('chunkNo', T.Properties.VariableNames)
    [~, sortIdx] = sortrows(table(double(T.chunkNo), double(T.chunkStartRow)), [1 2]);
else
    [~, sortIdx] = sortrows(table(double(T.chunkStartRow)), 1);
end
end


function [gazeX, gazeY] = localRemapDonorGazeToRecipient(recipStep, donorStep, donorGazeX, donorGazeY)
recipStep = double(recipStep(:));
donorStep = double(donorStep(:));
donorGazeX = double(donorGazeX(:));
donorGazeY = double(donorGazeY(:));
gazeX = NaN(size(recipStep));
gazeY = NaN(size(recipStep));
if isempty(recipStep) || isempty(donorStep)
    return
end
[~, ia, ib] = intersect(recipStep, donorStep, 'stable');
if isempty(ia)
    return
end
gazeX(ia) = donorGazeX(ib);
gazeY(ia) = donorGazeY(ib);
end


function trialGroups = localNormalizeTrialGroups(trialNo, availableTrials, in, inputMode, opts)
if nargin < 5
    opts = struct();
end
if isempty(trialNo)
    trialGroups = {availableTrials};
    return
end
if localIsPercentileGrouping(trialNo)
    trialGroups = {availableTrials};
    return
end
if ischar(trialNo) || (isstring(trialNo) && isscalar(trialNo))
    code = char(string(trialNo));
    trialGroups = localResolveNamedTrialGroups(code, availableTrials, in, inputMode, opts);
    return
end
if iscell(trialNo)
    if localIsNamedCodeCell(trialNo)
        trialGroups = localCombineNamedTrialGroups(trialNo, availableTrials, in, inputMode, opts);
        return
    end
    trialGroups = cell(size(trialNo));
    for i = 1:numel(trialNo)
        trialGroups{i} = localValidateTrialVector(trialNo{i}, availableTrials);
    end
else
    trialGroups = {localValidateTrialVector(trialNo, availableTrials)};
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


function trialGroups = localCombineNamedTrialGroups(codeList, availableTrials, in, inputMode, opts)
if nargin < 5
    opts = struct();
end
trialGroups = {availableTrials};
for k = 1:numel(codeList)
    code = char(string(codeList{k}));
    nextGroups = localResolveNamedTrialGroups(code, availableTrials, in, inputMode, opts);
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
    error('ccg:NamedGroupEmpty', ...
        'No trials remained after combining the requested named groupings.');
end
end


function trialGroups = localResolveNamedTrialGroups(code, availableTrials, in, inputMode, opts)
if nargin < 5
    opts = struct();
end
code = localCanonicalGroupingCode(code);
switch code
    case 'all'
        trialGroups = {availableTrials};
    case 'pur'
        switch inputMode
            case 'ex'
                trialGroups = {intersect(localPursuitTrialNumbersFromEx(in), availableTrials, 'stable')};
            case 'tracking'
                trialGroups = {intersect(localPursuitTrialNumbersFromTracking(in), availableTrials, 'stable')};
            otherwise
                trialGroups = {availableTrials};
        end
        if isempty(trialGroups{1})
            error('ccg:NoPursuitTrials', ...
                'No pursuit trials were available. Expected isPursuitTrial=true or runPhase=''pursuit'' trial metadata.');
        end
    case 'pre'
        switch inputMode
            case 'ex'
                trialGroups = {intersect(localPreTrialNumbersFromEx(in), availableTrials, 'stable')};
            case 'tracking'
                trialGroups = {intersect(localPreTrialNumbersFromTracking(in), availableTrials, 'stable')};
            otherwise
                trialGroups = {availableTrials};
        end
        if isempty(trialGroups{1})
            error('ccg:NoPreTrials', ...
                'No preblock trials were available. Expected isPreTrial=true or runPhase=''pre'' trial metadata.');
        end
    case {'bg', 'vis', 'vislvl3', 'tnum', 'im'}
        if ~strcmp(inputMode, 'ex')
            error('ccg:NamedGroupRequiresEx', ...
                'Named trial grouping codes are currently supported only for raw ex input.');
        end
        trialGroups = localResolveNamedTrialGroupsFromEx(code, availableTrials, in, opts);
    otherwise
        error('ccg:UnknownTrialCode', ...
            ['Unknown grouping code ''%s''. Supported trial-level codes are ''all'', ''pur'', ''pre'', ''bg'', ''vis'', ''visLvl3'', ''tnum'', ''im''; ' ...
            'supported chunk-level code is ''rq''.'], code);
end
end


function trialGroups = localResolveNamedTrialGroupsFromEx(code, availableTrials, ex, opts)
if nargin < 4
    opts = struct();
end
switch code
    case 'bg'
        values = NaN(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            T = ex.Trials(j);
            if isfield(T, 'background_noise_lvl') && isnumeric(T.background_noise_lvl) && isscalar(T.background_noise_lvl)
                values(j) = double(T.background_noise_lvl);
            end
        end
        keep = isfinite(values) & ismember(1:numel(values), availableTrials);
        levels = unique(values(keep));
        if isempty(levels)
            error('ccg:NamedGroupEmpty', ...
                'No available trials had finite background_noise_lvl values.');
        end
        trialGroups = cell(numel(levels), 1);
        for i = 1:numel(levels)
            trialGroups{i} = find(values == levels(i));
            trialGroups{i} = intersect(trialGroups{i}, availableTrials, 'stable');
        end
    case 'vis'
        values = NaN(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            T = ex.Trials(j);
            if isfield(T, 'target_visibility') && isnumeric(T.target_visibility) && isscalar(T.target_visibility)
                values(j) = double(T.target_visibility);
            end
        end
        keep = isfinite(values) & ismember(1:numel(values), availableTrials);
        levels = unique(values(keep));
        if isempty(levels)
            error('ccg:NamedGroupEmpty', ...
                'No available trials had finite target_visibility values.');
        end
        trialGroups = cell(numel(levels), 1);
        for i = 1:numel(levels)
            trialGroups{i} = find(values == levels(i));
            trialGroups{i} = intersect(trialGroups{i}, availableTrials, 'stable');
        end
    case 'vislvl3'
        edges = localResolveVisLvl3Edges(opts);
        values = NaN(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            T = ex.Trials(j);
            values(j) = localTrialTargetVisibility(ex, T);
        end
        keep = isfinite(values) & ismember(1:numel(values), availableTrials);
        masks = {values < edges(1), values >= edges(1) & values < edges(2), values >= edges(2)};
        trialGroups = cell(0, 1);
        for i = 1:numel(masks)
            trials = find(keep & masks{i});
            trials = intersect(trials, availableTrials, 'stable');
            if ~isempty(trials)
                trialGroups{end+1, 1} = trials; %#ok<AGROW>
            end
        end
        if isempty(trialGroups)
            error('ccg:NamedGroupEmpty', ...
                'No available trials matched visLvl3 bins: low < %.4g, mid >= %.4g & < %.4g, high >= %.4g.', ...
                edges(1), edges(1), edges(2), edges(2));
        end
    case 'tnum'
        values = NaN(1, numel(ex.Trials));
        for j = 1:numel(ex.Trials)
            T = ex.Trials(j);
            if isfield(T, 'target_num') && isnumeric(T.target_num) && isscalar(T.target_num)
                values(j) = double(T.target_num);
            end
        end
        keep = isfinite(values) & ismember(1:numel(values), availableTrials);
        levels = unique(values(keep));
        if isempty(levels)
            error('ccg:NamedGroupEmpty', ...
                'No available trials had finite target_num values.');
        end
        trialGroups = cell(numel(levels), 1);
        for i = 1:numel(levels)
            trialGroups{i} = find(values == levels(i));
            trialGroups{i} = intersect(trialGroups{i}, availableTrials, 'stable');
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
        keep = values ~= "" & ~ismissing(values) & ismember(1:numel(values), availableTrials);
        levels = unique(values(keep), 'stable');
        if isempty(levels)
            error('ccg:NamedGroupEmpty', ...
                'No available trials had finite imageName values.');
        end
        trialGroups = cell(numel(levels), 1);
        for i = 1:numel(levels)
            trialGroups{i} = find(values == levels(i));
            trialGroups{i} = intersect(trialGroups{i}, availableTrials, 'stable');
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


function trialVec = localValidateTrialVector(trialVec, availableTrials)
trialVec = unique(double(trialVec(:)'));
if isempty(trialVec) || any(~isfinite(trialVec)) || any(trialVec ~= round(trialVec))
    error('ccg:BadTrialNo', 'Each trial selection must contain finite integer trial indices.');
end
trialVec = intersect(trialVec, availableTrials, 'stable');
if isempty(trialVec)
    error('ccg:BadTrialNo', ...
        'No requested trials were available in the input.');
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


function suffix = localPlural(n)
if n == 1
    suffix = '';
else
    suffix = 's';
end
end


function dtStep = localResolveStepDt(tRelSec, fallbackDtSec)
dtStep = NaN;
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


function dtStepSec = localCommonDtStepSec(dtValues)
dtValues = double(dtValues(:));
dtValues = dtValues(isfinite(dtValues) & dtValues > 0);
if isempty(dtValues)
    dtStepSec = NaN;
else
    dtStepSec = median(dtValues, 'omitnan');
end
end


function dtSec = localResolveSampleDtFromEpisode(episode, fallbackDtSec)
dtSec = NaN;
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


function [xPx, yPx, protectedNaNMask] = localApplySaccadeHandlingForCcg(xPx, yPx, dtSec, setup, opts)
xPx = double(xPx(:));
yPx = double(yPx(:));
protectedNaNMask = false(size(xPx));
if ~isfinite(dtSec) || dtSec <= 0
    return
end

[saccadeStarts, saccadeStops] = detectTrackingSaccadesCoPs( ...
    xPx, yPx, dtSec, setup, localBuildCurrentSaccadeParams(dtSec, opts));
if isempty(saccadeStarts)
    return
end

padFrames = localResolvePadFrames(dtSec, opts.saccadePadSec);
mask = false(size(xPx));
for i = 1:numel(saccadeStarts)
    i0 = max(1, saccadeStarts(i) - padFrames);
    i1 = min(numel(xPx), saccadeStops(i) + padFrames);
    mask(i0:i1) = true;
end
if logical(opts.saccadeInterp)
    xPx = localInterpMaskedGapsWithNeighborMeans(xPx, mask, 5);
    yPx = localInterpMaskedGapsWithNeighborMeans(yPx, mask, 5);
else
    protectedNaNMask = mask;
    xPx(protectedNaNMask) = NaN;
    yPx(protectedNaNMask) = NaN;
end
end


function params = localBuildCurrentSaccadeParams(dtSec, opts)
params = struct();
params.preSaccadeWindowFrames = 3;
if isfield(opts, 'speedThreshDegPerSec') && isfinite(double(localFirstScalar(opts.speedThreshDegPerSec)))
    params.speedThreshDegPerSec = double(localFirstScalar(opts.speedThreshDegPerSec));
else
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
    'shuffleEyesAcrossTrials', 'shuffleEyeAcrossTrials'
    'shuffleEyesWithinTrial', 'shuffleEyeWithinTrials'
    'shuffleEyeWithinTrial', 'shuffleEyeWithinTrials'
    };
for i = 1:size(aliasPairs, 1)
    oldField = aliasPairs{i, 1};
    newField = aliasPairs{i, 2};
    if (~isfield(opts, newField) || isempty(opts.(newField))) && isfield(opts, oldField) && ~isempty(opts.(oldField))
        opts.(newField) = opts.(oldField);
    end
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


function mask = localDilateBinaryMask(mask, padFrames)
mask = logical(mask(:));
if ~any(mask) || padFrames <= 0
    return
end
idx = find(mask);
for i = 1:numel(idx)
    i0 = max(1, idx(i) - padFrames);
    i1 = min(numel(mask), idx(i) + padFrames);
    mask(i0:i1) = true;
end
end


function T = localFilterEpisodeChunksByLength(T, opts)
if isempty(T) || ~ismember('chunkDurSec', T.Properties.VariableNames)
    return
end
minChunkSec = double(localFirstScalar(opts.minChunkSec));
maxChunkSec = double(localFirstScalar(opts.maxChunkSec));
keep = true(height(T), 1);
if isfinite(minChunkSec)
    keep = keep & isfinite(T.chunkDurSec) & double(T.chunkDurSec) >= minChunkSec;
end
if isfinite(maxChunkSec)
    keep = keep & isfinite(T.chunkDurSec) & double(T.chunkDurSec) <= maxChunkSec;
end
T = T(keep, :);
end


function trials = localFlattenTrialGroups(trialGroups)
if isempty(trialGroups)
    trials = [];
    return
end
trialGroups = cellfun(@(x) double(x(:)), trialGroups, 'UniformOutput', false);
trials = unique(vertcat(trialGroups{:}))';
end


function x = localInterpMaskedGapsWithNeighborMeans(x, mask, nSide)
x = x(:);
mask = logical(mask(:));
if ~any(mask)
    return
end

d = diff([false; mask; false]);
gapStarts = find(d == 1);
gapEnds = find(d == -1) - 1;
for i = 1:numel(gapStarts)
    g0 = gapStarts(i);
    g1 = gapEnds(i);
    leftIdx = max(1, g0 - nSide):(g0 - 1);
    rightIdx = (g1 + 1):min(numel(x), g1 + nSide);
    leftVals = x(leftIdx);
    rightVals = x(rightIdx);
    leftVals = leftVals(isfinite(leftVals) & ~mask(leftIdx));
    rightVals = rightVals(isfinite(rightVals) & ~mask(rightIdx));
    if isempty(leftVals) || isempty(rightVals)
        x(g0:g1) = NaN;
        continue
    end
    fillVals = linspace(mean(leftVals, 'omitnan'), mean(rightVals, 'omitnan'), g1 - g0 + 3);
    x(g0:g1) = fillVals(2:end-1);
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
