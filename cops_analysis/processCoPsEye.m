


function out = processCoPsEye(ex, opts)
% analyzeCoPsEye
% Offline analysis for eye-tracking data from runTrialTaskCoPsx.m (ex.Trials).
%
% out = analyzeCoPsEye(ex)
% out = analyzeCoPsEye(ex, opts)
%
% Inputs
%   ex   : experiment struct containing ex.Trials and calibration/settings fields.
%   opts : (optional) struct with fields:
%       .makePlots       (logical, default true)
%       .savePlots       (logical, default false)
%       .plotDir         (char, default 'analysis_plots')
%       .maxLagSec       (double, default 0.5)
%       .useEyeTime      (logical, default false) use Eye.t if reliable
%       .trackingSource  (default 'hmmSmoothed') target identity source:
%                        'hmmSmoothed', 'hmmFiltered', 'hmmPredictive', or
%                        'model-free'. A missing requested HMM source is an error.
%       .hmmHardThreshold (default 0.9) assign a target only when its HMM
%           probability exceeds this value for two-state TID/SM models.
%           Three-state SM3 assignments use the most probable state among
%           TLeft, TRight, and non-tracking; this threshold is ignored.
%       .distanceUnits   'deg' (default) returns public distance/position
%                        outputs in visual degrees. Use 'px' only for
%                        backward-compatible pixel output.
%
% Output (struct)
%   out.trialSummary : full table with one row per trial
%   out.sessionSummary : session-level summary; all non-trial-primary metrics
%       should be interpreted from this level by default
%   out.samples      : table with per-sample traces (long format)
%   out.meta         : struct with options and helper metadata

if nargin < 2 || isempty(opts)
    opts = struct();
end

defaults = struct( ...
    'makePlots', false, ...
    'savePlots', 0, ...
    'plotDir', '/home/vpixx/vsgui/vsg/cops_analysis/plots', ...
    'maxLagSec', 5, ...
    'useEyeTime', true, ...
    'onlyGoState', true, ...
    'minInBoundsFrac', 0.33, ...
    'minRewardPoints', 500, ...
    'sampleTrials', [13,14, 50, 100], ...
    'analysisStartStep', 1, ...
    'rewardDistanceNBins', 12, ...
    'trackingDistMult', 2.5, ...
    'minTrackingSec', 0.05, ...
    'switchRequireSaccade', true, ...
    'requireTrackingSaccade', false, ...
    'trackingPreWindowSec', 0.1, ...
    'trackingBlinkGapSec', 0.15, ...
    'trackingVar', 'isTracking_wta', ...
    'trackingSource', 'hmmSmoothed', ...
    'hmmHardThreshold', 0.9, ...
    'distanceUnits', 'deg');
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field)
        opts.(field) = defaults.(field);
    end
end
opts.trackingSource = localResolveTrackingSource(opts.trackingSource);
opts.hmmHardThreshold = localResolveHmmHardThreshold(opts.hmmHardThreshold);
opts.distanceUnits = localResolveDistanceUnits(opts.distanceUnits);

if ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('Input ex has no trials in ex.Trials.');
end

nTr = numel(ex.Trials);
usesHmmTracking = ~strcmp(opts.trackingSource, 'model-free');
hmmCoverage = localValidateHmmCoverage(ex.Trials, opts.trackingSource);
[trialPrimaryMetrics, sessionPrimaryMetrics] = getMetricPrimacyLists();
sessionParams = extractSessionParams(ex);

trialSummary = table('Size', [nTr 111], ...
    'VariableTypes', [repmat({'double'}, 1, 7), {'string'}, repmat({'double'}, 1, 103)], ...
    'VariableNames', {'trial','nSamples','inBoundsFrac','backgroundNoiseLvl','targetVisibility','coherence','targetNum','imageName','meanDistPx1', ...
    'meanDistPx2','meanDistPx', ...
    'stepCaptureProb','stepMedianTimeToCaptureSec','stepCaptureAtEndProb','nAnalyzedSteps','nCapturedSteps', ...
    'targetTransitionProb','targetSwitchRateHz','targetMeanDwellSteps','targetMeanDwellSec', ...
    'targetMeanDwellSecNear','targetMeanDwellSecMid','targetMeanDwellSecFar', ...
    'isTracking','isTracking_sacc','isTracking_conserv','isTracking_lib','isTracking_wta','peakTrackFrac','outerTrackFrac','peakTrackBias','firstTrackPeakTarget','trackErrorPx','trackVariabilityPx','trackBiasPx','trackScreenCenterBiasPx','trackGaussSpecificBiasPx','trackBiasXPx','trackBiasYPx', ...
    'nTrackedSamplesEarly','nTrackedSamplesLate', ...
    'trackErrorPxEarly','trackErrorPxLate', ...
    'trackErrorRmsPxEarly','trackErrorRmsPxLate', ...
    'trackVariabilityPxEarly','trackVariabilityPxLate', ...
    'trackBiasPxEarly','trackBiasPxLate', ...
    'trackScreenCenterBiasPxEarly','trackScreenCenterBiasPxLate', ...
    'trackGaussSpecificBiasPxEarly','trackGaussSpecificBiasPxLate', ...
    'trackBiasXPxEarly','trackBiasXPxLate', ...
    'trackBiasYPxEarly','trackBiasYPxLate', ...
    'nTrackedSamples','nTrackedSamplesNear','nTrackedSamplesMid','nTrackedSamplesFar', ...
    'trackErrorPxNear','trackErrorPxMid','trackErrorPxFar', ...
    'trackErrorRmsPx','trackErrorRmsPxNear','trackErrorRmsPxMid','trackErrorRmsPxFar', ...
    'trackVariabilityPxNear','trackVariabilityPxMid','trackVariabilityPxFar', ...
    'trackBiasPxNear','trackBiasPxMid','trackBiasPxFar', ...
    'trackScreenCenterBiasPxNear','trackScreenCenterBiasPxMid','trackScreenCenterBiasPxFar', ...
    'trackGaussSpecificBiasPxNear','trackGaussSpecificBiasPxMid','trackGaussSpecificBiasPxFar', ...
    'trackBiasXPxNear','trackBiasXPxMid','trackBiasXPxFar', ...
    'trackBiasYPxNear','trackBiasYPxMid','trackBiasYPxFar', ...
    'switchToPeakFrac', ...
    'switchWhenOtherPeakFrac','switchProbPeak','switchProbOuter','switchProbDelta', ...
    'saccToPeak','saccToOuter','saccPeakFrac', ...
    'distFixMid','distFixPeak','distPerm', ...
    'meanScaledRewardSaved','nRewardEvents','good', ...
    'targetQ1TimeSec', 'targetQ2TimeSec','targetQ3TimeSec','targetQ4TimeSec',...
    'gazeQ1TimeSec', 'gazeQ2TimeSec','gazeQ3TimeSec','gazeQ4TimeSec', ...
    'gaussQuadNormPeak','gaussQuadNormOther','gaussQuadBias'});
trialSummary{:, [1:7, 9:111]} = NaN;
keepMainTrial = false(nTr, 1);
permControlData = cell(nTr, 1);
iriTables = cell(nTr, 1);
trackingTables = cell(nTr, 1);
rewardSwitchTables = cell(nTr, 1);
sessionTrackingSamples = initSessionTrackingSamples();
sessionObs = initSessionPrimaryObservations();

sampleTables = cell(1, numel(opts.sampleTrials));
includeSampleTrial = false(nTr, 1);
includeSampleTrial(opts.sampleTrials) = true;

screenW = ex.setup.screenRect(3);
screenH = ex.setup.screenRect(4);
maxDistPx = hypot(screenW, screenH);

pooledRewardByDistance.gaze = rewardDistanceAccumulatorCoPs('init', opts.rewardDistanceNBins, maxDistPx);
pooledRewardByDistance.target = rewardDistanceAccumulatorCoPs('init', opts.rewardDistanceNBins, maxDistPx);

for j = 1:nTr
    if mod(j,20)==0
        fprintf('trial %d\n',j)
    end
    T = ex.Trials(j);

    isFixationTrial = isfield(T, 'isFixationTrial') && logical(T.isFixationTrial);
    isTutorialTrial = isfield(T, 'isTutorialTrial') && logical(T.isTutorialTrial);
    hasRunPhase = isfield(T, 'runPhase') && ~isempty(T.runPhase);
    if hasRunPhase
        runPhase = string(T.runPhase);
        isMainTrial = runPhase == "main";
    else
        % Backward compatibility: older CoPs sessions did not label run
        % phase, and should be treated as main-task trials unless another
        % explicit exclusion flag is present.
        isMainTrial = ~isFixationTrial && ~isTutorialTrial;
    end

    % Analyze only main-task trials. Skip tutorial, fixation/recentering,
    % and any other non-main trial types when present.
    if ~isMainTrial || isFixationTrial || isTutorialTrial
        continue
    end
    keepMainTrial(j) = true;
    trialSummary.backgroundNoiseLvl(j) = getTrialBackgroundNoiseLevel(T);
    trialSummary.targetVisibility(j) = getTrialTargetVisibility(T, sessionParams);
    trialSummary.coherence(j) = getTrialCoherence(T, sessionParams);
    trialSummary.targetNum(j) = getTrialTargetNum(T, sessionParams);
    trialSummary.imageName(j) = getTrialImageName(ex, T, j);

    % extract locations by timepoint 
    [xPx, yPx, tRel, tAbs, valid] = reconstructEyePx(ex, T, opts.useEyeTime, opts);
    
    [targetX, targetY, target2X, target2Y, stepIdx] = mapTargetsByStep(ex, T, tRel);

    
    % trial selection
    sel = selectTrials(ex, T, tAbs, xPx, yPx, valid, opts);
    inBounds = sel.inBounds;

    % select only tp during 'go' period
    goMask = true(size(tAbs));
    if opts.onlyGoState
        goMask = tAbs >= T.times.stimOn & tAbs <= T.TrialEnd;
    end

    xPx = xPx(goMask);
    yPx = yPx(goMask);
    tRel = tRel(goMask);
    tAbs = tAbs(goMask);
    valid = valid(goMask);
    targetX = targetX(goMask);
    targetY = targetY(goMask);
    target2X = target2X(goMask);
    target2Y = target2Y(goMask);
    stepIdx = stepIdx(goMask);
    inBounds = inBounds(goMask);

    % Canonicalize identity once: target 1 is the target that starts on the
    % left (then upper on an exact x tie), and retains that identity.
    [targetX, targetY, target2X, target2Y] = canonicalizeTargetOrder(targetX, targetY, target2X, target2Y);
    [hmmAssignedTarget, hasHmmAssignment] = localHmmAssignedTarget( ...
        T, stepIdx, opts.trackingSource, opts.hmmHardThreshold);
    missingHmmForTrial = usesHmmTracking && ~hasHmmAssignment;
    
    nS = numel(tRel); % num of samples
    dtSec = 1 / inferFs(ex);

    %distances
    distPx1 = computeDistanceToTargets(xPx, yPx, targetX, targetY, inBounds);
    distPx2 = computeDistanceToTargets(xPx, yPx, target2X, target2Y, inBounds);
    distPx = distPx1;
    useT2 = isfinite(distPx2) & ((~isfinite(distPx1)) | distPx2 < distPx1);
    distPx(useT2) = distPx2(useT2);

    xPx(~inBounds) = NaN;
    yPx(~inBounds) = NaN;
    % sample trial extraction here
    if includeSampleTrial(j)
        jj=find(opts.sampleTrials==j);
        sampleTables{jj} = table(repmat(j, nS, 1), tRel(:), tAbs(:), xPx(:), yPx(:), ...
            inBounds(:), stepIdx(:), targetX(:), targetY(:), target2X(:), target2Y(:), distPx(:), ...
            'VariableNames', {'trial','tRelSec','tAbsSec','xPx','yPx','inBounds', ...
            'step','targetX','targetY','target2X', 'target2Y','distPx'});
    end

    if ~sel.keepTrial
        trialSummary.trial(j) = j;
        trialSummary.good(j) = 0;
        trialSummary.inBoundsFrac(j) = mean(inBounds, 'omitnan');
        continue
    end
    trialSummary.good(j) = 1;
    
    analysisMask = stepIdx >= opts.analysisStartStep;

    rewTS = calcRewPerTp(ex, xPx, yPx, targetX, targetY, target2X, target2Y, inBounds, T);
    rewardThis = rewTS.scaledReward;
    gaussCtr = getGaussianCenterPx(ex,T);
    fixMid = ex.fix.PCtr(:)';

    trialSummary.distFixMid(j) = meanDistanceToCloserTarget( ...
        repmat(fixMid(1), size(targetX)), repmat(fixMid(2), size(targetY)), ...
        targetX, targetY, target2X, target2Y, analysisMask);
    trialSummary.distFixPeak(j) = meanDistanceToCloserTarget( ...
        repmat(gaussCtr(1), size(targetX)), repmat(gaussCtr(2), size(targetY)), ...
        targetX, targetY, target2X, target2Y, analysisMask);

    gazeTimes=computeQuadrantTimes(xPx, yPx, ex.fix.PCtr(:)', analysisMask & inBounds, dtSec);
    trialSummary.gazeQ1TimeSec(j)= gazeTimes(1);
    trialSummary.gazeQ2TimeSec(j)= gazeTimes(2);
    trialSummary.gazeQ3TimeSec(j)= gazeTimes(3);
    trialSummary.gazeQ4TimeSec(j)= gazeTimes(4);

    tgtXAll = [targetX(:); target2X(:)];
    tgtYAll = [targetY(:); target2Y(:)];
    tgtMaskAll = [analysisMask(:) & inBounds(:); analysisMask(:) & inBounds(:)];
    targetTimes=computeQuadrantTimes(tgtXAll, tgtYAll, ex.fix.PCtr(:)', tgtMaskAll, dtSec);
    trialSummary.targetQ1TimeSec(j) = targetTimes(1);
    trialSummary.targetQ2TimeSec(j) = targetTimes(2);
    trialSummary.targetQ3TimeSec(j) = targetTimes(3);
    trialSummary.targetQ4TimeSec(j) = targetTimes(4);

    gaussQuadIdx = classifyQuadrantCoPs(gaussCtr(1), gaussCtr(2), ex.fix.PCtr(:)');
    if ~isnan(gaussQuadIdx)
        normOcc = gazeTimes ./ targetTimes;
        normOcc(~isfinite(normOcc)) = NaN;
        otherIdx = setdiff(1:4, gaussQuadIdx);
        trialSummary.gaussQuadNormPeak(j) = normOcc(gaussQuadIdx);
        trialSummary.gaussQuadNormOther(j) = mean(normOcc(otherIdx), 'omitnan');
        if isfinite(trialSummary.gaussQuadNormPeak(j)) && isfinite(trialSummary.gaussQuadNormOther(j))
            trialSummary.gaussQuadBias(j) = ...
                trialSummary.gaussQuadNormPeak(j) - trialSummary.gaussQuadNormOther(j);
        end
    end

    gazeDistFromGaussCtr = hypot(xPx - gaussCtr(1), yPx - gaussCtr(2));
    t1DistFromGaussCtr = hypot(targetX - gaussCtr(1), targetY - gaussCtr(2));
    t2DistFromGaussCtr = hypot(target2X - gaussCtr(1), target2Y - gaussCtr(2));
    targetDistFromGaussCtr = [t1DistFromGaussCtr(:); t2DistFromGaussCtr(:)];
    targetReward = [rewardThis(:); rewardThis(:)];

    keepGaze = analysisMask & inBounds & isfinite(gazeDistFromGaussCtr) & isfinite(rewardThis);
    keepTarget = tgtMaskAll & isfinite(targetDistFromGaussCtr) & isfinite(targetReward);
    pooledRewardByDistance.gaze = rewardDistanceAccumulatorCoPs('update', ...
        pooledRewardByDistance.gaze, gazeDistFromGaussCtr(keepGaze), rewardThis(keepGaze));
    pooledRewardByDistance.target = rewardDistanceAccumulatorCoPs('update', ...
        pooledRewardByDistance.target, targetDistFromGaussCtr(keepTarget), targetReward(keepTarget));

    % Keep the step index returned by mapTargetsByStep so that target
    % trajectories and step-conditioned analyses use the same discretization.
    nStep = numel(unique(stepIdx(isfinite(stepIdx))));
    % xPx = accumarray(g, xPx, [nStep 1], @(v) mean(v, 'omitnan'), NaN);
    % yPx = accumarray(g, yPx, [nStep 1], @(v) mean(v, 'omitnan'), NaN);
    % tRel = accumarray(g, tRel, [nStep 1], @(v) mean(v, 'omitnan'), NaN);
    % tAbs = accumarray(g, tAbs, [nStep 1], @(v) mean(v, 'omitnan'), NaN);
    % valid = accumarray(g, double(valid), [nStep 1], @mean, 0) > 0;
    % 
    % targetX = accumarray(g, targetX, [nStep 1], @(v) mean(v, 'omitnan'), NaN);
    % targetY = accumarray(g, targetY, [nStep 1], @(v) mean(v, 'omitnan'), NaN);
    % target2X =accumarray(g, target2X, [nStep 1], @(v) mean(v, 'omitnan'), NaN);
    % target2Y =accumarray(g, target2Y, [nStep 1], @(v) mean(v, 'omitnan'), NaN);
    % stepIdx = accumarray(g, stepIdx, [nStep 1], @(v) mean(v, 'omitnan'), NaN);
    % 
    % capture stats: gaze entering a target zone
    captureRadiusPx = ex.exp.CoPs.graph.radius * ex.exp.CoPs.graph.size_mult;
    stepCap = computeStepCaptureMetrics(tRel, stepIdx, xPx, yPx, targetX, targetY, target2X, target2Y, inBounds, captureRadiusPx);
    trialSummary.stepCaptureProb(j) = stepCap.captureProb;
    trialSummary.stepMedianTimeToCaptureSec(j) = stepCap.medianTimeToCaptureSec;
    trialSummary.stepCaptureAtEndProb(j) = stepCap.captureAtEndProb;
    trialSummary.nAnalyzedSteps(j) = stepCap.nSteps;
    trialSummary.nCapturedSteps(j) = sum(stepCap.captured, 'omitnan');

    % switching behav
    betweenMarginPx = captureRadiusPx / 2; % margin of error: values below signify 
    % distance difference between targets being to small to assign identity
    if usesHmmTracking
        stab = localSwitchingFromHmm(hmmAssignedTarget, tRel, stepIdx, ex.exp.CoPs.ctl.nsteps);
    else
        stab = calcSwitching(tRel, stepIdx, xPx, yPx, distPx1, distPx2, inBounds, ...
            betweenMarginPx, ex.exp.CoPs.ctl.nsteps, dtSec, ex.setup, opts.switchRequireSaccade);
    end
    trialSummary.targetSwitchRateHz(j) = stab.switchRateHz;
    trialSummary.targetTransitionProb(j) = stab.transProbStep;
    trialSummary.targetMeanDwellSteps(j) = stab.meanDwellSteps;
    trialSummary.targetMeanDwellSec(j) = stab.meanDwellSec;
    dwellBinMetrics = computeTrialTargetDwellDistanceBinMetrics( ...
        stepIdx, distPx1, distPx2, t1DistFromGaussCtr, t2DistFromGaussCtr, ...
        inBounds, betweenMarginPx, tRel, ex.exp.CoPs.ctl.nsteps, sessionParams.gaussSigma, ...
        hmmAssignedTarget);
    trialSummary.targetMeanDwellSecNear(j) = dwellBinMetrics.targetMeanDwellSecNear;
    trialSummary.targetMeanDwellSecMid(j) = dwellBinMetrics.targetMeanDwellSecMid;
    trialSummary.targetMeanDwellSecFar(j) = dwellBinMetrics.targetMeanDwellSecFar;

    % peak bias: preference for tracking target that is closer to the Gaussian peak
    trackingDistPx = opts.trackingDistMult * captureRadiusPx;
    minTrackingSec = opts.minTrackingSec;
    earlyTrackingSec = 0.100;
    minPhaseTrackingSec = 0.200;
    peakBias = calcCtrTrackingBias( ...
        targetX, targetY, target2X, target2Y, xPx, yPx, distPx1, distPx2, ...
        inBounds, betweenMarginPx, gaussCtr, stepIdx, nStep, trackingDistPx, minTrackingSec, dtSec, ex.fix.PCtr(:)', earlyTrackingSec, minPhaseTrackingSec, ex.setup, opts.requireTrackingSaccade, opts.switchRequireSaccade, hmmAssignedTarget);
    % Recompute peak-choice metrics directly on the processed trial inputs.
    % This keeps switch-conditioned peak metrics aligned with the validated
    % direct helper path even if wrapper internals drift.
    if usesHmmTracking
        assignPeak = localAssignmentFromTargetIds(hmmAssignedTarget, stepIdx);
    else
        assignPeak = assignTargetIdentityCoPs(distPx1, distPx2, inBounds, betweenMarginPx, stepIdx);
    end
    peakDist1 = hypot(targetX(:) - gaussCtr(1), targetY(:) - gaussCtr(2));
    peakDist2 = hypot(target2X(:) - gaussCtr(1), target2Y(:) - gaussCtr(2));
    peakCloser = zeros(size(peakDist1));
    peakCloser(peakDist1 < peakDist2) = 1;
    peakCloser(peakDist2 < peakDist1) = 2;
    directChoice = computePeakChoiceMetricsCoPs( ...
        assignPeak, peakCloser, peakBias.isTracking, stepIdx, xPx, yPx, ...
        targetX, targetY, target2X, target2Y, gaussCtr, nStep, dtSec, ex.setup, ...
        opts.switchRequireSaccade && ~usesHmmTracking, distPx1, distPx2, trackingDistPx);
    choiceFields = fieldnames(directChoice);
    for ii = 1:numel(choiceFields)
        peakBias.(choiceFields{ii}) = directChoice.(choiceFields{ii});
    end
    trackingTables{j} = buildTrialTrackingTable( ...
        j, tRel, tAbs, stepIdx, xPx, yPx, targetX, targetY, target2X, target2Y, ...
        distPx1, distPx2, inBounds, betweenMarginPx, peakBias, gaussCtr, ex.fix.PCtr(:)', dtSec, ...
        opts.trackingPreWindowSec, opts.trackingBlinkGapSec, opts.trackingVar, opts.requireTrackingSaccade, hmmAssignedTarget);
    rewardSwitchTables{j} = buildRewardTriggeredSwitchTable( ...
        j, tRel, stepIdx, distPx1, distPx2, inBounds, betweenMarginPx, T, opts.analysisStartStep, ...
        trialSummary.backgroundNoiseLvl(j), [-0.5, 0.5], hmmAssignedTarget);
    validTrackingMask = analysisMask & valid;
    if any(validTrackingMask)
        trialSummary.isTracking(j) = mean(peakBias.isTracking(validTrackingMask), 'omitnan');
        trialSummary.isTracking_sacc(j) = mean(peakBias.isTrackingSacc(validTrackingMask), 'omitnan');
        trialSummary.isTracking_conserv(j) = mean(peakBias.isTrackingConserv(validTrackingMask), 'omitnan');
        trialSummary.isTracking_lib(j) = mean(peakBias.isTrackingLib(validTrackingMask), 'omitnan');
        trialSummary.isTracking_wta(j) = mean(peakBias.isTrackingWTA(validTrackingMask), 'omitnan');
    end
    trialSummary.peakTrackFrac(j) = peakBias.trackPeakFrac;
    trialSummary.outerTrackFrac(j) = peakBias.trackOuterFrac;
    trialSummary.peakTrackBias(j) = peakBias.peakTrackBias;
    trialSummary.firstTrackPeakTarget(j) = peakBias.firstTrackPeakTarget;
    trialSummary.trackErrorPx(j) = peakBias.trackErrorPx;
    trialSummary.trackErrorRmsPx(j) = peakBias.trackErrorRmsPx;
    trialSummary.trackVariabilityPx(j) = peakBias.trackVariabilityPx;
    trialSummary.trackBiasPx(j) = peakBias.trackBiasPx;
    trialSummary.trackScreenCenterBiasPx(j) = peakBias.trackScreenCenterBiasPx;
    trialSummary.trackGaussSpecificBiasPx(j) = peakBias.trackGaussSpecificBiasPx;
    trialSummary.trackBiasXPx(j) = peakBias.trackBiasXPx;
    trialSummary.trackBiasYPx(j) = peakBias.trackBiasYPx;
    trialBinMetrics = computeTrialTrackDistanceBinMetrics(peakBias, sessionParams.gaussSigma);
    trialPhaseMetrics = computeTrialTrackPhaseBinMetrics(peakBias);
    trialSummary.nTrackedSamplesEarly(j) = trialPhaseMetrics.nTrackedSamplesEarly;
    trialSummary.nTrackedSamplesLate(j) = trialPhaseMetrics.nTrackedSamplesLate;
    trialSummary.trackErrorPxEarly(j) = trialPhaseMetrics.trackErrorPxEarly;
    trialSummary.trackErrorPxLate(j) = trialPhaseMetrics.trackErrorPxLate;
    trialSummary.trackErrorRmsPxEarly(j) = trialPhaseMetrics.trackErrorRmsPxEarly;
    trialSummary.trackErrorRmsPxLate(j) = trialPhaseMetrics.trackErrorRmsPxLate;
    trialSummary.trackVariabilityPxEarly(j) = trialPhaseMetrics.trackVariabilityPxEarly;
    trialSummary.trackVariabilityPxLate(j) = trialPhaseMetrics.trackVariabilityPxLate;
    trialSummary.trackBiasPxEarly(j) = trialPhaseMetrics.trackBiasPxEarly;
    trialSummary.trackBiasPxLate(j) = trialPhaseMetrics.trackBiasPxLate;
    trialSummary.trackScreenCenterBiasPxEarly(j) = trialPhaseMetrics.trackScreenCenterBiasPxEarly;
    trialSummary.trackScreenCenterBiasPxLate(j) = trialPhaseMetrics.trackScreenCenterBiasPxLate;
    trialSummary.trackGaussSpecificBiasPxEarly(j) = trialPhaseMetrics.trackGaussSpecificBiasPxEarly;
    trialSummary.trackGaussSpecificBiasPxLate(j) = trialPhaseMetrics.trackGaussSpecificBiasPxLate;
    trialSummary.trackBiasXPxEarly(j) = trialPhaseMetrics.trackBiasXPxEarly;
    trialSummary.trackBiasXPxLate(j) = trialPhaseMetrics.trackBiasXPxLate;
    trialSummary.trackBiasYPxEarly(j) = trialPhaseMetrics.trackBiasYPxEarly;
    trialSummary.trackBiasYPxLate(j) = trialPhaseMetrics.trackBiasYPxLate;
    trialSummary.nTrackedSamples(j) = trialBinMetrics.nTrackedSamples;
    trialSummary.nTrackedSamplesNear(j) = trialBinMetrics.nTrackedSamplesNear;
    trialSummary.nTrackedSamplesMid(j) = trialBinMetrics.nTrackedSamplesMid;
    trialSummary.nTrackedSamplesFar(j) = trialBinMetrics.nTrackedSamplesFar;
    trialSummary.trackErrorPxNear(j) = trialBinMetrics.trackErrorPxNear;
    trialSummary.trackErrorPxMid(j) = trialBinMetrics.trackErrorPxMid;
    trialSummary.trackErrorPxFar(j) = trialBinMetrics.trackErrorPxFar;
    trialSummary.trackErrorRmsPxNear(j) = trialBinMetrics.trackErrorRmsPxNear;
    trialSummary.trackErrorRmsPxMid(j) = trialBinMetrics.trackErrorRmsPxMid;
    trialSummary.trackErrorRmsPxFar(j) = trialBinMetrics.trackErrorRmsPxFar;
    trialSummary.trackVariabilityPxNear(j) = trialBinMetrics.trackVariabilityPxNear;
    trialSummary.trackVariabilityPxMid(j) = trialBinMetrics.trackVariabilityPxMid;
    trialSummary.trackVariabilityPxFar(j) = trialBinMetrics.trackVariabilityPxFar;
    trialSummary.trackBiasPxNear(j) = trialBinMetrics.trackBiasPxNear;
    trialSummary.trackBiasPxMid(j) = trialBinMetrics.trackBiasPxMid;
    trialSummary.trackBiasPxFar(j) = trialBinMetrics.trackBiasPxFar;
    trialSummary.trackScreenCenterBiasPxNear(j) = trialBinMetrics.trackScreenCenterBiasPxNear;
    trialSummary.trackScreenCenterBiasPxMid(j) = trialBinMetrics.trackScreenCenterBiasPxMid;
    trialSummary.trackScreenCenterBiasPxFar(j) = trialBinMetrics.trackScreenCenterBiasPxFar;
    trialSummary.trackGaussSpecificBiasPxNear(j) = trialBinMetrics.trackGaussSpecificBiasPxNear;
    trialSummary.trackGaussSpecificBiasPxMid(j) = trialBinMetrics.trackGaussSpecificBiasPxMid;
    trialSummary.trackGaussSpecificBiasPxFar(j) = trialBinMetrics.trackGaussSpecificBiasPxFar;
    trialSummary.trackBiasXPxNear(j) = trialBinMetrics.trackBiasXPxNear;
    trialSummary.trackBiasXPxMid(j) = trialBinMetrics.trackBiasXPxMid;
    trialSummary.trackBiasXPxFar(j) = trialBinMetrics.trackBiasXPxFar;
    trialSummary.trackBiasYPxNear(j) = trialBinMetrics.trackBiasYPxNear;
    trialSummary.trackBiasYPxMid(j) = trialBinMetrics.trackBiasYPxMid;
    trialSummary.trackBiasYPxFar(j) = trialBinMetrics.trackBiasYPxFar;
    trialSummary.switchToPeakFrac(j) = peakBias.switchToPeakFrac;
    trialSummary.switchWhenOtherPeakFrac(j) = peakBias.switchWhenOtherPeakFrac;
    trialSummary.switchProbPeak(j) = peakBias.switchProbPeak;
    trialSummary.switchProbOuter(j) = peakBias.switchProbOuter;
    trialSummary.switchProbDelta(j) = peakBias.switchProbDelta;
    trialSummary.saccToPeak(j) = peakBias.saccToPeak;
    trialSummary.saccToOuter(j) = peakBias.saccToOuter;
    trialSummary.saccPeakFrac(j) = peakBias.saccPeakFrac;
    sessionTrackingSamples = appendSessionTrackingSamples(sessionTrackingSamples, peakBias, trialSummary.backgroundNoiseLvl(j));
    sessionObs = appendSessionPrimaryObservations(sessionObs, stepCap, stab, dwellBinMetrics, peakBias, ...
        xPx, yPx, targetX, targetY, target2X, target2Y, analysisMask, inBounds, ...
        ex.fix.PCtr(:)', dtSec, gaussQuadIdx, trialSummary.backgroundNoiseLvl(j));
    if missingHmmForTrial
        trialSummary = localSetHmmTrackingMissing(trialSummary, j);
    end






    % Fill summary row.
    trialSummary.trial(j) = j;
    trialSummary.nSamples(j) = nS;
    trialSummary.inBoundsFrac(j) = mean(inBounds, 'omitnan');
    trialSummary.meanDistPx1(j) = mean(distPx1, 'omitnan');
    trialSummary.meanDistPx2(j) = mean(distPx2, 'omitnan');
    trialSummary.meanDistPx(j) = mean(distPx, 'omitnan');

    if isfield(T, 'scaledReward') && ~isempty(T.scaledReward)
        trialSummary.meanScaledRewardSaved(j) = mean(T.scaledReward, 'omitnan');
    else
        trialSummary.meanScaledRewardSaved(j) = NaN;
    end


    if isfield(T, 'times') && isfield(T.times, 'reward')
        rv = T.times.reward;
        trialSummary.nRewardEvents(j) = sum(isfinite(rv));
        rv = rv(isfinite(rv));
        if numel(rv) >= 2
            iriTables{j} = table( ...
                ones(numel(rv) - 1, 1), ...
                repmat(j, numel(rv) - 1, 1), ...
                (1:(numel(rv) - 1))', ...
                diff(rv(:)), ...
                repmat(trialSummary.backgroundNoiseLvl(j), numel(rv) - 1, 1), ...
                'VariableNames', {'sessionNo', 'trial', 'iriNo', 'iriSec', 'backgroundNoiseLvl'});
        end
    else
        trialSummary.nRewardEvents(j) = NaN;
    end

    permControlData{j} = struct( ...
        'xPx', xPx, ...
        'yPx', yPx, ...
        'targetX', targetX, ...
        'targetY', targetY, ...
        'target2X', target2X, ...
        'target2Y', target2Y, ...
        'analysisMask', analysisMask);

end

trialSummary = assignPermutedDistanceControl(trialSummary, permControlData);

trialSummary = trialSummary(keepMainTrial, :);

nonEmptySampleTables = sampleTables(~cellfun(@isempty, sampleTables));
if isempty(nonEmptySampleTables)
    samples = table();
else
    samples = vertcat(nonEmptySampleTables{:});
end

nonEmptyIriTables = iriTables(~cellfun(@isempty, iriTables));
if isempty(nonEmptyIriTables)
    iri = table();
else
    iri = vertcat(nonEmptyIriTables{:});
end

nonEmptyTrackingTables = trackingTables(~cellfun(@isempty, trackingTables));
if isempty(nonEmptyTrackingTables)
    tracking = table();
else
    tracking = vertcat(nonEmptyTrackingTables{:});
end

nonEmptyRewardSwitchTables = rewardSwitchTables(~cellfun(@isempty, rewardSwitchTables));
if isempty(nonEmptyRewardSwitchTables)
    rewardSwitch = table();
else
    rewardSwitch = vertcat(nonEmptyRewardSwitchTables{:});
end

sessionSummary = struct();
sessionSummary.nTrials = height(trialSummary);
sessionSummary = addNestedSessionMomentSummaries(sessionSummary, sessionObs, sessionTrackingSamples, sessionPrimaryMetrics, sessionParams.gaussSigma);
trialPrimaryVars = intersect(trialPrimaryMetrics, trialSummary.Properties.VariableNames, 'stable');

out = struct();
out.trialSummary = trialSummary;
out.sessionSummary = sessionSummary;
out.samples = samples;
out.iri = iri;
out.tracking = tracking;
out.rewardSwitch = rewardSwitch;
out.params = sessionParams;
out.meta = struct('nTrials', nTr, 'nMainTrials', sum(keepMainTrial), 'options', opts, 'fsHz', inferFs(ex));
out.meta.hmmCoverage = hmmCoverage;
out.meta.rewardByDistance = struct();
out.meta.rewardByDistance.gaze = rewardDistanceAccumulatorCoPs('finalize', pooledRewardByDistance.gaze);
out.meta.rewardByDistance.target = rewardDistanceAccumulatorCoPs('finalize', pooledRewardByDistance.target);
out.meta.quadrantLabels = struct( ...
    'Q1', 'top-right', ...
    'Q2', 'top-left', ...
    'Q3', 'bottom-left', ...
    'Q4', 'bottom-right');
out.meta.trackDistanceBins = getGaussDistanceBinDefinitions(sessionParams.gaussSigma);
out.meta.trackingAggregation = buildTrackingAggregation(sessionTrackingSamples, sessionParams.gaussSigma);
out.meta.metricPrimacy = struct( ...
    'trialPrimary', {trialPrimaryVars}, ...
    'sessionPrimary', {sessionPrimaryMetrics}, ...
    'trialSummaryInterpretation', 'Use out.trialSummary for per-trial measures; trial-primary fields are listed in out.meta.metricPrimacy.trialPrimary.', ...
    'sessionSummaryInterpretation', 'Use out.sessionSummary as the default level for all session-primary metrics.');


if opts.makePlots
    plotCoPsEyeQC(out, opts);
end

if strcmp(opts.distanceUnits, 'deg')
    out = localConvertPublicOutputsToDegrees(out, ex.setup);
end

end


function units = localResolveDistanceUnits(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error('processCoPsEye:BadDistanceUnits', ...
        'opts.distanceUnits must be ''deg'' or ''px''.');
end
units = lower(strtrim(char(value)));
if ~ismember(units, {'deg', 'px'})
    error('processCoPsEye:BadDistanceUnits', ...
        'opts.distanceUnits must be ''deg'' or ''px''.');
end
end


function out = localConvertPublicOutputsToDegrees(out, setup)
scale = px2deg(1, setup);
screenCenter = localScreenCenterPx(setup);

% These legacy names contain distances but did not state their units.
out.trialSummary = localConvertNamedDistances(out.trialSummary, scale, ...
    {'distFixMid','distFixPeak','distPerm'}, ...
    {'distFixMidDeg','distFixPeakDeg','distPermDeg'});
out.trialSummary = convertCoPsPxFieldsToDeg(out.trialSummary, setup);
out.sessionSummary = convertCoPsPxFieldsToDeg(out.sessionSummary, setup);

out.samples = localCenterPxColumns(out.samples, screenCenter, {'xPx','yPx'});
out.samples = localConvertAbsoluteColumns(out.samples, screenCenter, scale, ...
    {'targetX','targetY','target2X','target2Y'}, ...
    {'targetXDeg','targetYDeg','target2XDeg','target2YDeg'});
out.samples = convertCoPsPxFieldsToDeg(out.samples, setup);

out.tracking = localCenterPxColumns(out.tracking, screenCenter, {'xPx','yPx'});
out.tracking = localConvertAbsoluteColumns(out.tracking, screenCenter, scale, ...
    {'trackedTargetX','trackedTargetY'}, ...
    {'trackedTargetXDeg','trackedTargetYDeg'});
out.tracking = convertCoPsPxFieldsToDeg(out.tracking, setup);
out.rewardSwitch = convertCoPsPxFieldsToDeg(out.rewardSwitch, setup);

if isfield(out.params, 'gaussSigma')
    out.params.gaussSigmaDeg = out.params.gaussSigma .* scale;
    out.params = rmfield(out.params, 'gaussSigma');
end
out.meta.rewardByDistance = convertCoPsPxFieldsToDeg( ...
    out.meta.rewardByDistance, setup);
out.meta.trackDistanceBins = convertCoPsPxFieldsToDeg( ...
    out.meta.trackDistanceBins, setup);
out.meta.metricPrimacy = convertCoPsPxFieldsToDeg( ...
    out.meta.metricPrimacy, setup);
if isfield(out.meta.metricPrimacy, 'trialPrimary')
    names = string(out.meta.metricPrimacy.trialPrimary);
    names(names == "distFixMid") = "distFixMidDeg";
    names(names == "distFixPeak") = "distFixPeakDeg";
    names(names == "distPerm") = "distPermDeg";
    out.meta.metricPrimacy.trialPrimary = cellstr(names);
end
out.meta.trackingAggregation = localConvertTrackingAggregationToDegrees( ...
    out.meta.trackingAggregation, scale);
out.meta.distanceUnits = 'deg';
out.meta.coordinateReference = ...
    'Visual degrees relative to screen center; positive x/y follow pixel-axis directions.';
end


function center = localScreenCenterPx(setup)
if ~isstruct(setup) || ~isfield(setup, 'screenRect') || ...
        numel(setup.screenRect) < 4
    error('processCoPsEye:MissingScreenGeometry', ...
        'setup.screenRect is required for degree-coordinate outputs.');
end
rect = double(setup.screenRect(:)');
center = [(rect(1) + rect(3)) / 2, (rect(2) + rect(4)) / 2];
end


function T = localCenterPxColumns(T, center, names)
if isempty(T)
    return
end
for i = 1:numel(names)
    name = names{i};
    if ~ismember(name, T.Properties.VariableNames)
        continue
    end
    if startsWith(lower(name), 'x')
        T.(name) = double(T.(name)) - center(1);
    elseif startsWith(lower(name), 'y')
        T.(name) = double(T.(name)) - center(2);
    end
end
end


function T = localConvertAbsoluteColumns(T, center, scale, oldNames, newNames)
if isempty(T)
    return
end
for i = 1:numel(oldNames)
    oldName = oldNames{i};
    if ~ismember(oldName, T.Properties.VariableNames)
        continue
    end
    if endsWith(lower(oldName), 'x')
        origin = center(1);
    else
        origin = center(2);
    end
    T.(oldName) = (double(T.(oldName)) - origin) .* scale;
    T.Properties.VariableNames{strcmp(T.Properties.VariableNames, oldName)} = newNames{i};
end
end


function T = localConvertNamedDistances(T, scale, oldNames, newNames)
for i = 1:numel(oldNames)
    oldName = oldNames{i};
    if ~ismember(oldName, T.Properties.VariableNames)
        continue
    end
    T.(oldName) = double(T.(oldName)) .* scale;
    T.Properties.VariableNames{strcmp(T.Properties.VariableNames, oldName)} = newNames{i};
end
end


function agg = localConvertTrackingAggregationToDegrees(agg, scale)
if ~isstruct(agg)
    return
end
groups = {'distanceBins', 'phaseBins'};
linearFields = {'sumBias','sumBiasX','sumBiasY','sumScreenCenterBias', ...
    'sumGaussSpecificBias','sumErrDist','sumErrX','sumErrY'};
squaredFields = {'sumErrSq','sumErrXSq','sumErrYSq'};
for g = 1:numel(groups)
    groupName = groups{g};
    if ~isfield(agg, groupName) || ~isstruct(agg.(groupName))
        continue
    end
    bins = fieldnames(agg.(groupName));
    for b = 1:numel(bins)
        stats = agg.(groupName).(bins{b});
        for i = 1:numel(linearFields)
            if isfield(stats, linearFields{i})
                stats.(linearFields{i}) = stats.(linearFields{i}) .* scale;
            end
        end
        for i = 1:numel(squaredFields)
            if isfield(stats, squaredFields{i})
                stats.(squaredFields{i}) = stats.(squaredFields{i}) .* scale.^2;
            end
        end
        agg.(groupName).(bins{b}) = stats;
    end
end
agg.distanceUnits = 'deg';
end


function [trialPrimaryMetrics, sessionPrimaryMetrics] = getMetricPrimacyLists()
trialPrimaryMetrics = { ...
    'trial', ...
    'nSamples', ...
    'backgroundNoiseLvl', ...
    'targetVisibility', ...
    'inBoundsFrac', ...
    'meanDistPx1', ...
    'meanDistPx2', ...
    'meanDistPx', ...
    'distFixMid', ...
    'distFixPeak', ...
    'distPerm', ...
    'meanScaledRewardSaved', ...
    'nRewardEvents', ...
    'good'};

specs = getSessionMetricSpecs();
sessionPrimaryMetrics = {specs.name};
end


function specs = getSessionMetricSpecs()
specs = [ ...
    metricSpec('stepCaptureProb', 'observedMean'), ...
    metricSpec('stepMedianTimeToCaptureSec', 'captureLatency'), ...
    metricSpec('stepCaptureAtEndProb', 'observedMean'), ...
    metricSpec('targetTransitionProb', 'observedMean'), ...
    metricSpec('targetSwitchRateHz', 'switchRate'), ...
    metricSpec('targetMeanDwellSteps', 'observedMean'), ...
    metricSpec('targetMeanDwellSec', 'observedMean'), ...
    metricSpec('targetMeanDwellSecNear', 'observedMean'), ...
    metricSpec('targetMeanDwellSecMid', 'observedMean'), ...
    metricSpec('targetMeanDwellSecFar', 'observedMean'), ...
    metricSpec('peakTrackFrac', 'observedMean'), ...
    metricSpec('outerTrackFrac', 'observedMean'), ...
    metricSpec('peakTrackBias', 'observedMean'), ...
    metricSpec('trackErrorPx', 'track', 'trackKind', 'error', 'includeDistanceBins', true, 'includePhaseBins', true), ...
    metricSpec('trackVariabilityPx', 'track', 'trackKind', 'variability', 'includeDistanceBins', true, 'includePhaseBins', true), ...
    metricSpec('trackBiasPx', 'track', 'trackKind', 'bias', 'includeDistanceBins', true, 'includePhaseBins', true), ...
    metricSpec('trackScreenCenterBiasPx', 'track', 'trackKind', 'screenCenterBias', 'includeDistanceBins', true, 'includePhaseBins', true), ...
    metricSpec('trackGaussSpecificBiasPx', 'track', 'trackKind', 'gaussSpecificBias', 'includeDistanceBins', true, 'includePhaseBins', true), ...
    metricSpec('trackBiasXPx', 'track', 'trackKind', 'biasX', 'includeDistanceBins', true, 'includePhaseBins', true), ...
    metricSpec('trackBiasYPx', 'track', 'trackKind', 'biasY', 'includeDistanceBins', true, 'includePhaseBins', true), ...
    metricSpec('switchToPeakFrac', 'observedMean'), ...
    metricSpec('switchWhenOtherPeakFrac', 'observedMean'), ...
    metricSpec('switchProbPeak', 'observedMean'), ...
    metricSpec('switchProbOuter', 'observedMean'), ...
    metricSpec('switchProbDelta', 'switchDelta'), ...
    metricSpec('saccToPeak', 'observedSum'), ...
    metricSpec('saccToOuter', 'observedSum'), ...
    metricSpec('saccPeakFrac', 'observedMean'), ...
    metricSpec('targetQ1TimeSec', 'observedSum'), ...
    metricSpec('targetQ2TimeSec', 'observedSum'), ...
    metricSpec('targetQ3TimeSec', 'observedSum'), ...
    metricSpec('targetQ4TimeSec', 'observedSum'), ...
    metricSpec('gazeQ1TimeSec', 'observedSum'), ...
    metricSpec('gazeQ2TimeSec', 'observedSum'), ...
    metricSpec('gazeQ3TimeSec', 'observedSum'), ...
    metricSpec('gazeQ4TimeSec', 'observedSum'), ...
    metricSpec('gaussQuadNormPeak', 'gaussQuad', 'gaussMode', 'peak'), ...
    metricSpec('gaussQuadNormOther', 'gaussQuad', 'gaussMode', 'other'), ...
    metricSpec('gaussQuadBias', 'gaussQuad', 'gaussMode', 'bias')];
end


function spec = metricSpec(name, kind, varargin)
spec = struct( ...
    'name', name, ...
    'kind', kind, ...
    'trackKind', '', ...
    'includeDistanceBins', false, ...
    'includePhaseBins', false, ...
    'gaussMode', '');
for i = 1:2:numel(varargin)
    spec.(varargin{i}) = varargin{i+1};
end
end


function sessionObs = initSessionPrimaryObservations()
sessionObs = struct( ...
    'switchProbPeak', zeros(0,1), ...
    'switchProbPeakNoise', zeros(0,1), ...
    'switchProbOuter', zeros(0,1), ...
    'switchProbOuterNoise', zeros(0,1), ...
    'targetSwitchEvents', zeros(0,1), ...
    'targetSwitchEventsNoise', zeros(0,1), ...
    'targetSwitchTotalDurSec', 0, ...
    'targetSwitchDurSec', zeros(0,1), ...
    'targetSwitchDurSecNoise', zeros(0,1), ...
    'gaussQuadPeakGazeTimeSec', 0, ...
    'gaussQuadPeakGazeTimeSecByTrial', zeros(0,1), ...
    'gaussQuadPeakTargetTimeSec', 0, ...
    'gaussQuadPeakTargetTimeSecByTrial', zeros(0,1), ...
    'gaussQuadOtherGazeTimeSec', 0, ...
    'gaussQuadOtherGazeTimeSecByTrial', zeros(0,1), ...
    'gaussQuadOtherTargetTimeSec', 0, ...
    'gaussQuadOtherTargetTimeSecByTrial', zeros(0,1), ...
    'gaussQuadNoise', zeros(0,1));
end


function sessionObs = appendSessionPrimaryObservations(sessionObs, stepCap, stab, dwellBinMetrics, peakBias, ...
    xPx, yPx, targetX, targetY, target2X, target2Y, analysisMask, inBounds, ctrPx, dtSec, gaussQuadIdx, noiseLevel)
sessionObs = appendObservedValues(sessionObs, 'stepCaptureProb', double(stepCap.captured(:)), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'stepCaptureAtEndProb', double(stepCap.capturedAtStepEnd(:)), noiseLevel);

capTimes = stepCap.timeToCaptureSec(stepCap.captured & isfinite(stepCap.timeToCaptureSec) & stepCap.timeToCaptureSec > 0);
sessionObs = appendObservedValues(sessionObs, 'stepMedianTimeToCaptureSec', capTimes(:), noiseLevel);

sessionObs = appendObservedValues(sessionObs, 'targetTransitionProb', double(stab.switchIndicators(:)), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'targetMeanDwellSteps', stab.dwellSteps(:), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'targetMeanDwellSec', stab.dwellSec(:), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'targetMeanDwellSecNear', dwellBinMetrics.dwellSecNear(:), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'targetMeanDwellSecMid', dwellBinMetrics.dwellSecMid(:), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'targetMeanDwellSecFar', dwellBinMetrics.dwellSecFar(:), noiseLevel);

sessionObs = appendObservedValues(sessionObs, 'peakTrackFrac', double(peakBias.trackedIsPeak(:)), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'outerTrackFrac', 1 - double(peakBias.trackedIsPeak(:)), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'peakTrackBias', peakBias.trackedPeakBiasObs(:), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'trackBiasPx', peakBias.trackedBiasPx(:), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'trackScreenCenterBiasPx', peakBias.trackedScreenCenterBiasPx(:), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'trackGaussSpecificBiasPx', peakBias.trackedGaussSpecificBiasPx(:), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'trackBiasXPx', peakBias.trackedBiasXPx(:), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'trackBiasYPx', peakBias.trackedBiasYPx(:), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'switchToPeakFrac', double(peakBias.switchToPeakObs(:)), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'switchWhenOtherPeakFrac', double(peakBias.switchWhenOtherPeakObs(:)), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'switchProbPeak', double(peakBias.switchProbPeakObs(:)), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'switchProbOuter', double(peakBias.switchProbOuterObs(:)), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'saccToPeak', double(peakBias.saccEntryPeakObs(:)), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'saccToOuter', double(~peakBias.saccEntryPeakObs(:)), noiseLevel);
sessionObs = appendObservedValues(sessionObs, 'saccPeakFrac', double(peakBias.saccEntryPeakObs(:)), noiseLevel);
sessionObs.targetSwitchEvents = [sessionObs.targetSwitchEvents; double(stab.switchIndicators(:))]; %#ok<AGROW>
sessionObs.targetSwitchEventsNoise = [sessionObs.targetSwitchEventsNoise; repmat(noiseLevel, numel(stab.switchIndicators), 1)]; %#ok<AGROW>
if isfinite(stab.trialDurSec)
    sessionObs.targetSwitchTotalDurSec = sessionObs.targetSwitchTotalDurSec + stab.trialDurSec;
    sessionObs.targetSwitchDurSec = [sessionObs.targetSwitchDurSec; stab.trialDurSec]; %#ok<AGROW>
    sessionObs.targetSwitchDurSecNoise = [sessionObs.targetSwitchDurSecNoise; noiseLevel]; %#ok<AGROW>
end

if ~isnan(gaussQuadIdx)
    gazeMask = analysisMask(:) & inBounds(:) & isfinite(xPx(:)) & isfinite(yPx(:));
    if any(gazeMask)
        x = xPx(gazeMask);
        y = yPx(gazeMask);
        gazeQuad = classifyQuadrantCoPs(x, y, ctrPx);
        ctrGaze = dtSec * sum(gazeQuad == gaussQuadIdx);
        othGaze = dtSec * sum(gazeQuad ~= gaussQuadIdx);
        sessionObs.gaussQuadPeakGazeTimeSec = sessionObs.gaussQuadPeakGazeTimeSec + ctrGaze;
        sessionObs.gaussQuadOtherGazeTimeSec = sessionObs.gaussQuadOtherGazeTimeSec + othGaze;
        sessionObs.gaussQuadPeakGazeTimeSecByTrial = [sessionObs.gaussQuadPeakGazeTimeSecByTrial; ctrGaze]; %#ok<AGROW>
        sessionObs.gaussQuadOtherGazeTimeSecByTrial = [sessionObs.gaussQuadOtherGazeTimeSecByTrial; othGaze]; %#ok<AGROW>
    end

    targetMask = [analysisMask(:) & inBounds(:); analysisMask(:) & inBounds(:)];
    tgtXAll = [targetX(:); target2X(:)];
    tgtYAll = [targetY(:); target2Y(:)];
    tgtXAll = tgtXAll(targetMask);
    tgtYAll = tgtYAll(targetMask);
    if ~isempty(tgtXAll)
        targetQuad = classifyQuadrantCoPs(tgtXAll, tgtYAll, ctrPx);
        ctrTgt = dtSec * sum(targetQuad == gaussQuadIdx);
        othTgt = dtSec * sum(targetQuad ~= gaussQuadIdx);
        sessionObs.gaussQuadPeakTargetTimeSec = sessionObs.gaussQuadPeakTargetTimeSec + ctrTgt;
        sessionObs.gaussQuadOtherTargetTimeSec = sessionObs.gaussQuadOtherTargetTimeSec + othTgt;
        sessionObs.gaussQuadPeakTargetTimeSecByTrial = [sessionObs.gaussQuadPeakTargetTimeSecByTrial; ctrTgt]; %#ok<AGROW>
        sessionObs.gaussQuadOtherTargetTimeSecByTrial = [sessionObs.gaussQuadOtherTargetTimeSecByTrial; othTgt]; %#ok<AGROW>
        sessionObs.gaussQuadNoise = [sessionObs.gaussQuadNoise; noiseLevel]; %#ok<AGROW>
    end
end

gazeMask = analysisMask(:) & inBounds(:) & isfinite(xPx(:)) & isfinite(yPx(:));
if any(gazeMask)
    x = xPx(gazeMask);
    y = yPx(gazeMask);
    sessionObs = appendObservedValues(sessionObs, 'gazeQ1TimeSec', dtSec * double(x >= ctrPx(1) & y < ctrPx(2)), noiseLevel);
    sessionObs = appendObservedValues(sessionObs, 'gazeQ2TimeSec', dtSec * double(x < ctrPx(1) & y < ctrPx(2)), noiseLevel);
    sessionObs = appendObservedValues(sessionObs, 'gazeQ3TimeSec', dtSec * double(x < ctrPx(1) & y >= ctrPx(2)), noiseLevel);
    sessionObs = appendObservedValues(sessionObs, 'gazeQ4TimeSec', dtSec * double(x >= ctrPx(1) & y >= ctrPx(2)), noiseLevel);
end

targetMask = [analysisMask(:) & inBounds(:); analysisMask(:) & inBounds(:)];
tgtX = [targetX(:); target2X(:)];
tgtY = [targetY(:); target2Y(:)];
tgtX = tgtX(targetMask);
tgtY = tgtY(targetMask);
if ~isempty(tgtX)
    sessionObs = appendObservedValues(sessionObs, 'targetQ1TimeSec', dtSec * double(tgtX >= ctrPx(1) & tgtY < ctrPx(2)), noiseLevel);
    sessionObs = appendObservedValues(sessionObs, 'targetQ2TimeSec', dtSec * double(tgtX < ctrPx(1) & tgtY < ctrPx(2)), noiseLevel);
    sessionObs = appendObservedValues(sessionObs, 'targetQ3TimeSec', dtSec * double(tgtX < ctrPx(1) & tgtY >= ctrPx(2)), noiseLevel);
    sessionObs = appendObservedValues(sessionObs, 'targetQ4TimeSec', dtSec * double(tgtX >= ctrPx(1) & tgtY >= ctrPx(2)), noiseLevel);
end
end


function dwellMetrics = computeTrialTargetDwellDistanceBinMetrics(stepIdx, distPx1, distPx2, t1DistFromGaussCtr, t2DistFromGaussCtr, ...
    inBounds, betweenMarginPx, tRel, nsteps, gaussSigma, assignedTargetOverride)
dwellMetrics = struct( ...
    'targetMeanDwellSecNear', NaN, ...
    'targetMeanDwellSecMid', NaN, ...
    'targetMeanDwellSecFar', NaN, ...
    'dwellSecNear', zeros(0, 1), ...
    'dwellSecMid', zeros(0, 1), ...
    'dwellSecFar', zeros(0, 1));

if nargin >= 11 && ~isempty(assignedTargetOverride)
    assign = localAssignmentFromTargetIds(assignedTargetOverride, stepIdx);
else
    assign = assignTargetIdentityCoPs(distPx1, distPx2, inBounds, betweenMarginPx, stepIdx);
end
assignedStep = assign.assignedStep(:);
steps = assign.step(:);
if isempty(steps) || isempty(assignedStep)
    return
end

stepDist1 = aggregateStepwiseMean(stepIdx, t1DistFromGaussCtr, steps);
stepDist2 = aggregateStepwiseMean(stepIdx, t2DistFromGaussCtr, steps);
assignedTargetDist = NaN(size(assignedStep));
assignedTargetDist(assignedStep == 1) = stepDist1(assignedStep == 1);
assignedTargetDist(assignedStep == 2) = stepDist2(assignedStep == 2);

stepDurSec = inferStepDurationSec(tRel, nsteps);
bins = resolveGaussDistanceBins(gaussSigma);
suffixMap = {'Near', 'Mid', 'Far'};
binCode = zeros(size(assignedStep));
for i = 1:numel(bins)
    m = assignedStep > 0 & assignedTargetDist >= bins(i).lowerPx & assignedTargetDist <= bins(i).upperPx;
    binCode(m) = i;
end

valid = assignedStep > 0 & binCode > 0 & isfinite(assignedTargetDist);
if ~any(valid)
    return
end

assignedValid = assignedStep(valid);
binValid = binCode(valid);
runStart = [true; diff(assignedValid) ~= 0 | diff(binValid) ~= 0];
runIdx = cumsum(runStart);
runBin = accumarray(runIdx, binValid, [], @(v) v(1));
dwellSec = accumarray(runIdx, 1, [], @sum) * stepDurSec;

for i = 1:numel(bins)
    fieldName = ['dwellSec' suffixMap{i}];
    meanField = ['targetMeanDwellSec' suffixMap{i}];
    vals = dwellSec(runBin == i);
    dwellMetrics.(fieldName) = vals(:);
    if ~isempty(vals)
        dwellMetrics.(meanField) = mean(vals, 'omitnan');
    end
end
end


function stepMeans = aggregateStepwiseMean(stepIdx, values, steps)
stepIdx = stepIdx(:);
values = values(:);
steps = steps(:);
stepMeans = NaN(size(steps));
for i = 1:numel(steps)
    mask = isfinite(stepIdx) & stepIdx == steps(i) & isfinite(values);
    if any(mask)
        stepMeans(i) = mean(values(mask), 'omitnan');
    end
end
end


function stepDurSec = inferStepDurationSec(tRel, nsteps)
trialDur = max(tRel) - min(tRel);
if ~isfinite(trialDur) || trialDur <= 0
    stepDurSec = NaN;
else
    stepDurSec = trialDur / max(nsteps, 1);
end
end


function sessionSummary = addNestedSessionMomentSummaries(sessionSummary, sessionObs, sessionTrackingSamples, sessionPrimaryMetrics, gaussSigma)
meanStruct = struct();
sdStruct = struct();
seStruct = struct();
specs = getSessionMetricSpecs();
specMap = containers.Map({specs.name}, num2cell(1:numel(specs)));

for i = 1:numel(sessionPrimaryMetrics)
    metric = sessionPrimaryMetrics{i};
    spec = specs(specMap(metric));
    [meanStruct.(metric), sdStruct.(metric), seStruct.(metric)] = ...
        computeSessionPrimaryMoments(spec, sessionObs, sessionTrackingSamples, gaussSigma);
end

sessionSummary.mean = meanStruct;
sessionSummary.sd = sdStruct;
sessionSummary.se = seStruct;
end

function [meanVal, sdVal, seVal] = computeSessionPrimaryMoments(spec, sessionObs, sessionTrackingSamples, gaussSigma)
meanVal = struct('all', NaN);
sdVal = struct('all', NaN);
seVal = struct('all', NaN);

switch spec.kind
    case 'captureLatency'
        [meanVal, sdVal, seVal] = computeCaptureLatencyMoments(sessionObs);
        return
    case 'switchRate'
        [meanVal, sdVal, seVal] = computeSwitchRateMoments(sessionObs);
        return
    case 'switchDelta'
        [meanVal, sdVal, seVal] = computeSwitchProbDeltaMoments(sessionObs);
        return
    case 'gaussQuad'
        [meanVal, sdVal, seVal] = computeGaussQuadMoments(sessionObs, spec.gaussMode);
        return
    case 'track'
        [meanVal, sdVal, seVal] = computeTrackMetricMoments(sessionTrackingSamples, spec.trackKind, spec.includeDistanceBins, spec.includePhaseBins, gaussSigma);
        return
    case 'observedSum'
        [meanVal, sdVal, seVal] = summarizeObservedMetric(sessionObs, spec.name, 'sum', false);
        return
    case 'observedMean'
        [meanVal, sdVal, seVal] = summarizeObservedMetric(sessionObs, spec.name, 'mean', true);
        return
    otherwise
        [meanVal, sdVal, seVal] = summarizeObservedMetric(sessionObs, spec.name, 'mean', true);
        return
end
end


function sessionObs = appendObservedValues(sessionObs, fieldName, values, noiseLevel)
if isempty(values)
    return
end

values = values(:);
values = values(isfinite(values));
if isempty(values)
    return
end

if ~isfield(sessionObs, fieldName)
    sessionObs.(fieldName) = zeros(0, 1);
end

noiseField = [fieldName 'Noise'];
if ~isfield(sessionObs, noiseField)
    sessionObs.(noiseField) = zeros(0, 1);
end

sessionObs.(fieldName) = [sessionObs.(fieldName); values]; %#ok<AGROW>
sessionObs.(noiseField) = [sessionObs.(noiseField); repmat(noiseLevel, numel(values), 1)]; %#ok<AGROW>
end


function [meanVal, sdVal, seVal] = computeCaptureLatencyMoments(sessionObs)
meanVal = struct('all', NaN);
sdVal = struct('all', NaN);
seVal = struct('all', NaN);

lat = sessionObs.stepMedianTimeToCaptureSec(:);
noise = sessionObs.stepMedianTimeToCaptureSecNoise(:);

[meanVal.all, sdVal.all, seVal.all] = summarizeLatencyVector(lat);

validNoise = isfinite(noise);
if any(validNoise)
    uniqueNoise = unique(noise(validNoise));
    for i = 1:numel(uniqueNoise)
        noiseLevel = uniqueNoise(i);
        suffix = makeNoiseLevelFieldSuffix(noiseLevel);
        mask = validNoise & noise == noiseLevel;
        [meanVal.(suffix), sdVal.(suffix), seVal.(suffix)] = summarizeLatencyVector(lat(mask));
    end
end
end


function [meanStruct, sdStruct, seStruct] = summarizeObservedMetric(sessionObs, fieldName, mode, includeDispersion)
if nargin < 4
    includeDispersion = true;
end
meanStruct = struct('all', NaN);
sdStruct = struct('all', NaN);
seStruct = struct('all', NaN);

if ~isfield(sessionObs, fieldName)
    return
end
obs = sessionObs.(fieldName)(:);
noiseField = [fieldName 'Noise'];
if isfield(sessionObs, noiseField)
    noise = sessionObs.(noiseField)(:);
else
    noise = NaN(size(obs));
end

[meanStruct.all, sdStruct.all, seStruct.all] = summarizeVectorWithMode(obs, mode, includeDispersion);

validNoise = isfinite(noise);
if any(validNoise)
    uniqueNoise = unique(noise(validNoise));
    for i = 1:numel(uniqueNoise)
        noiseLevel = uniqueNoise(i);
        suffix = makeNoiseLevelFieldSuffix(noiseLevel);
        mask = validNoise & noise == noiseLevel;
        [meanStruct.(suffix), sdStruct.(suffix), seStruct.(suffix)] = ...
            summarizeVectorWithMode(obs(mask), mode, includeDispersion);
    end
end
end


function [meanStruct, sdStruct, seStruct] = computeSwitchRateMoments(sessionObs)
meanStruct = struct('all', NaN);
sdStruct = struct('all', NaN);
seStruct = struct('all', NaN);

[meanStruct.all, sdStruct.all, seStruct.all] = summarizeSwitchRate( ...
    sessionObs.targetSwitchEvents(:), sessionObs.targetSwitchTotalDurSec);

noise = sessionObs.targetSwitchEventsNoise(:);
validNoise = isfinite(noise);
if any(validNoise)
    uniqueNoise = unique(noise(validNoise));
    for i = 1:numel(uniqueNoise)
        noiseLevel = uniqueNoise(i);
        suffix = makeNoiseLevelFieldSuffix(noiseLevel);
        maskEvents = validNoise & noise == noiseLevel;
        maskDur = isfinite(sessionObs.targetSwitchDurSecNoise(:)) & sessionObs.targetSwitchDurSecNoise(:) == noiseLevel;
        totalDur = sum(sessionObs.targetSwitchDurSec(maskDur), 'omitnan');
        [meanStruct.(suffix), sdStruct.(suffix), seStruct.(suffix)] = summarizeSwitchRate( ...
            sessionObs.targetSwitchEvents(maskEvents), totalDur);
    end
end
end


function [meanStruct, sdStruct, seStruct] = computeSwitchProbDeltaMoments(sessionObs)
meanStruct = struct('all', NaN);
sdStruct = struct('all', NaN);
seStruct = struct('all', NaN);

[meanStruct.all, sdStruct.all, seStruct.all] = summarizeDelta( ...
    sessionObs.switchProbPeak(:), sessionObs.switchProbOuter(:));

noiseC = sessionObs.switchProbPeakNoise(:);
noiseO = sessionObs.switchProbOuterNoise(:);
noiseVals = unique([noiseC(isfinite(noiseC)); noiseO(isfinite(noiseO))]);
for i = 1:numel(noiseVals)
    noiseLevel = noiseVals(i);
    suffix = makeNoiseLevelFieldSuffix(noiseLevel);
    obsC = sessionObs.switchProbPeak(noiseC == noiseLevel);
    obsO = sessionObs.switchProbOuter(noiseO == noiseLevel);
    [meanStruct.(suffix), sdStruct.(suffix), seStruct.(suffix)] = summarizeDelta(obsC, obsO);
end
end


function [meanStruct, sdStruct, seStruct] = computeGaussQuadMoments(sessionObs, mode)
meanStruct = struct('all', NaN);
sdStruct = struct('all', NaN);
seStruct = struct('all', NaN);

switch mode
    case 'peak'
        meanStruct.all = safeRatio(sessionObs.gaussQuadPeakGazeTimeSec, sessionObs.gaussQuadPeakTargetTimeSec);
    case 'other'
        meanStruct.all = safeRatio(sessionObs.gaussQuadOtherGazeTimeSec, sessionObs.gaussQuadOtherTargetTimeSec);
    case 'bias'
        ctr = safeRatio(sessionObs.gaussQuadPeakGazeTimeSec, sessionObs.gaussQuadPeakTargetTimeSec);
        oth = safeRatio(sessionObs.gaussQuadOtherGazeTimeSec, sessionObs.gaussQuadOtherTargetTimeSec);
        meanStruct.all = ctr - oth;
end

noise = sessionObs.gaussQuadNoise(:);
validNoise = isfinite(noise);
if any(validNoise)
    uniqueNoise = unique(noise(validNoise));
    for i = 1:numel(uniqueNoise)
        noiseLevel = uniqueNoise(i);
        suffix = makeNoiseLevelFieldSuffix(noiseLevel);
        mask = validNoise & noise == noiseLevel;
        ctrG = sum(sessionObs.gaussQuadPeakGazeTimeSecByTrial(mask), 'omitnan');
        ctrT = sum(sessionObs.gaussQuadPeakTargetTimeSecByTrial(mask), 'omitnan');
        othG = sum(sessionObs.gaussQuadOtherGazeTimeSecByTrial(mask), 'omitnan');
        othT = sum(sessionObs.gaussQuadOtherTargetTimeSecByTrial(mask), 'omitnan');
        switch mode
            case 'peak'
                meanStruct.(suffix) = safeRatio(ctrG, ctrT);
            case 'other'
                meanStruct.(suffix) = safeRatio(othG, othT);
            case 'bias'
                meanStruct.(suffix) = safeRatio(ctrG, ctrT) - safeRatio(othG, othT);
        end
        sdStruct.(suffix) = NaN;
        seStruct.(suffix) = NaN;
    end
end
end


function [meanStruct, sdStruct, seStruct] = computeTrackMetricMoments(sessionTrackingSamples, metricKind, includeDistanceBins, includePhaseBins, gaussSigma)
meanStruct = struct('all', NaN);
sdStruct = struct('all', NaN);
seStruct = struct('all', NaN);

[obsAll, validMask] = resolveTrackObservations(sessionTrackingSamples, metricKind, true(size(sessionTrackingSamples.errX)));
[meanStruct.all, sdStruct.all, seStruct.all] = summarizeVectorWithMode(obsAll, 'mean', true);

noise = sessionTrackingSamples.noise(:);
validNoise = validMask & isfinite(noise);
if any(validNoise)
    uniqueNoise = unique(noise(validNoise));
    for i = 1:numel(uniqueNoise)
        noiseLevel = uniqueNoise(i);
        suffix = makeNoiseLevelFieldSuffix(noiseLevel);
        [obs, ~] = resolveTrackObservations(sessionTrackingSamples, metricKind, validMask & noise == noiseLevel);
        [meanStruct.(suffix), sdStruct.(suffix), seStruct.(suffix)] = summarizeVectorWithMode(obs, 'mean', true);
    end
end

if includeDistanceBins
    bins = resolveGaussDistanceBins(gaussSigma);
    for i = 1:numel(bins)
        binName = bins(i).name;
        [obs, ~] = resolveTrackObservations(sessionTrackingSamples, metricKind, validMask & bins(i).maskFn(sessionTrackingSamples.targetDistFromCtr));
        [meanStruct.(binName), sdStruct.(binName), seStruct.(binName)] = summarizeVectorWithMode(obs, 'mean', true);
    end
end

if includePhaseBins
    phaseDefs = getTrackPhaseBinDefinitions();
    for i = 1:numel(phaseDefs)
        phaseName = phaseDefs(i).name;
        mask = validMask & sessionTrackingSamples.phaseCode(:) == phaseDefs(i).code;
        [obs, ~] = resolveTrackObservations(sessionTrackingSamples, metricKind, mask);
        [meanStruct.(phaseName), sdStruct.(phaseName), seStruct.(phaseName)] = summarizeVectorWithMode(obs, 'mean', true);
    end
end
end


function [obs, validMask] = resolveTrackObservations(sessionTrackingSamples, metricKind, mask)
errX = sessionTrackingSamples.errX(:);
errY = sessionTrackingSamples.errY(:);
mask = mask(:);
switch metricKind
    case 'bias'
        obs = sessionTrackingSamples.bias(:);
        validMask = mask & isfinite(obs);
    case 'screenCenterBias'
        obs = sessionTrackingSamples.screenCenterBias(:);
        validMask = mask & isfinite(obs);
    case 'gaussSpecificBias'
        obs = sessionTrackingSamples.gaussSpecificBias(:);
        validMask = mask & isfinite(obs);
    case 'biasX'
        obs = sessionTrackingSamples.biasX(:);
        validMask = mask & isfinite(obs);
    case 'biasY'
        obs = sessionTrackingSamples.biasY(:);
        validMask = mask & isfinite(obs);
    case 'error'
        obs = sqrt(errX.^2 + errY.^2);
        validMask = mask & isfinite(obs);
    case 'variability'
        validMask = mask & isfinite(errX) & isfinite(errY);
        if any(validMask)
            meanErrX = mean(errX(validMask), 'omitnan');
            meanErrY = mean(errY(validMask), 'omitnan');
            obs = sqrt((errX - meanErrX).^2 + (errY - meanErrY).^2);
        else
            obs = NaN(size(errX));
        end
        validMask = validMask & isfinite(obs);
    otherwise
        obs = NaN(size(errX));
        validMask = false(size(errX));
end
obs = obs(validMask);
end


function [meanVal, sdVal, seVal] = summarizeVectorWithMode(obs, mode, includeDispersion)
if nargin < 3
    includeDispersion = true;
end
meanVal = NaN;
sdVal = NaN;
seVal = NaN;
obs = obs(isfinite(obs));
if isempty(obs)
    return
end

switch mode
    case 'sum'
        meanVal = sum(obs, 'omitnan');
    case 'median'
        meanVal = median(obs, 'omitnan');
    otherwise
        meanVal = mean(obs, 'omitnan');
end

if ~includeDispersion
    return
end

if numel(obs) == 1
    sdVal = 0;
    seVal = 0;
else
    sdVal = std(obs, 0, 'omitnan');
    seVal = sdVal / sqrt(numel(obs));
end
end


function [rateVal, sdVal, seVal] = summarizeSwitchRate(events, totalDur)
rateVal = NaN;
sdVal = NaN;
seVal = NaN;
events = events(isfinite(events));
if isempty(events) || ~isfinite(totalDur) || totalDur <= 0
    return
end
nSwitch = sum(events, 'omitnan');
rateVal = nSwitch / totalDur;
sdVal = sqrt(rateVal);
seVal = sqrt(nSwitch) / totalDur;
end


function [deltaVal, sdVal, seVal] = summarizeDelta(obsCenter, obsOuter)
deltaVal = NaN;
sdVal = NaN;
seVal = NaN;
obsCenter = obsCenter(isfinite(obsCenter));
obsOuter = obsOuter(isfinite(obsOuter));
if isempty(obsCenter) || isempty(obsOuter)
    return
end
pCenter = mean(obsCenter, 'omitnan');
pOuter = mean(obsOuter, 'omitnan');
deltaVal = pCenter - pOuter;
varCenter = pCenter * (1 - pCenter);
varOuter = pOuter * (1 - pOuter);
sdVal = sqrt(varCenter + varOuter);
seVal = sqrt((varCenter / numel(obsCenter)) + (varOuter / numel(obsOuter)));
end


function r = safeRatio(num, den)
r = NaN;
if isfinite(num) && isfinite(den) && den > 0
    r = num / den;
end
end


function [medianVal, sdVal, seVal] = summarizeLatencyVector(lat)
medianVal = NaN;
sdVal = NaN;
seVal = NaN;
lat = lat(isfinite(lat));
if isempty(lat)
    return
end

medianVal = median(lat, 'omitnan');
if numel(lat) == 1
    sdVal = 0;
    seVal = 0;
else
    sdVal = std(lat, 0, 'omitnan');
    seVal = sdVal / sqrt(numel(lat));
end
end


function params = extractSessionParams(ex)
tutNreps = getNestedNumeric(ex, {'exp', 'CoPs', 'tut', 'nreps'});
[waitSecs, waitHz] = resolveCoPsWaitSecs(ex, NaN);
params = struct( ...
    'expNreps', getNestedNumeric(ex, {'exp', 'nreps'}), ...
    'totalNreps', getNestedNumeric(ex, {'exp', 'total_nreps'}), ...
    'nsteps', getNestedNumeric(ex, {'exp', 'CoPs', 'ctl', 'nsteps'}), ...
    'waitSecs', waitSecs, ...
    'waitHz', waitHz, ...
    'gaussScalar', getFirstAvailableNestedNumeric(ex, { ...
        {'exp', 'CoPs', 'ctl', 'gauss_scalar'}, ...
        {'exp', 'CoPs', 'ctl', 'precision_weight'}}), ...
    'gaussCenterIdx', getNestedNumeric(ex, {'exp', 'CoPs', 'rew', 'gauss_center_idx'}), ...
    'maxDistMult', getNestedNumeric(ex, {'exp', 'CoPs', 'ctl', 'max_dist_mult'}), ...
    'targetNum', getNestedNumeric(ex, {'exp', 'CoPs', 'ctl', 'target_num'}), ...
    'rewardThreshold', getNestedNumeric(ex, {'exp', 'CoPs', 'rew', 'threshold'}), ...
    'rewardDuration', getNestedNumeric(ex, {'exp', 'CoPs', 'rew', 'duration'}), ...
    'gaussSigma', getNestedNumeric(ex, {'exp', 'CoPs', 'rew', 'gauss_sigma'}), ...
    'targetVisibility', getDefaultedTargetVisibility(ex), ...
    'coherence', getDefaultedCoherence(ex), ...
    'showGaussMarker', getNestedNumericOrLogical(ex, {'exp', 'CoPs', 'rew', 'show_gauss_marker'}), ...
    'backgroundNoiseMain', preserveNumericValue(getNestedValue(ex, {'exp', 'CoPs', 'graph', 'background_noise_lvl'})), ...
    'freeViewing', getNestedNumeric(ex, {'exp', 'CoPs', 'freeViewing'}));

if isnan(params.totalNreps)
    params.totalNreps = params.expNreps + tutNreps;
end
end


function value = getTrialTargetVisibility(T, sessionParams)
value = 1;
if isfield(T, 'target_visibility') && isscalar(T.target_visibility) && isfinite(T.target_visibility)
    value = double(T.target_visibility);
elseif isfield(sessionParams, 'targetVisibility') && isscalar(sessionParams.targetVisibility) && isfinite(sessionParams.targetVisibility)
    value = sessionParams.targetVisibility;
end
end


function value = getTrialCoherence(T, sessionParams)
value = 1;
if isfield(T, 'coherence') && isscalar(T.coherence) && isfinite(T.coherence)
    value = double(T.coherence);
elseif isfield(sessionParams, 'coherence') && isscalar(sessionParams.coherence) && isfinite(sessionParams.coherence)
    value = sessionParams.coherence;
end
end


function value = getTrialTargetNum(T, sessionParams)
value = NaN;
if isfield(T, 'target_num') && isscalar(T.target_num) && isfinite(T.target_num)
    value = double(T.target_num);
elseif isfield(sessionParams, 'targetNum') && isscalar(sessionParams.targetNum) && isfinite(sessionParams.targetNum)
    value = double(sessionParams.targetNum);
end
end


function imageName = getTrialImageName(ex, T, trialIdx)
imageName = string(missing);

if isfield(T, 'imageName') && (ischar(T.imageName) || isstring(T.imageName))
    candidate = string(T.imageName);
    if strlength(strtrim(candidate)) > 0
        imageName = candidate;
        return
    end
end

if isfield(T, 'stimPath') && (ischar(T.stimPath) || isstring(T.stimPath))
    candidate = basenameStringLocal(T.stimPath);
    if strlength(candidate) > 0
        imageName = candidate;
        return
    end
end

if isfield(ex, 'stim') && isstruct(ex.stim) && isfield(ex.stim, 'seq') && ...
        numel(ex.stim.seq) >= trialIdx
    candidate = basenameStringLocal(ex.stim.seq{trialIdx});
    if strlength(candidate) > 0
        imageName = candidate;
    end
end
end


function value = getDefaultedTargetVisibility(ex)
value = preserveNumericValue(getNestedValue(ex, {'exp', 'CoPs', 'graph', 'target_visibility'}));
if ~isnumeric(value) || isempty(value) || all(~isfinite(value(:)))
    value = 1;
end
end


function value = getDefaultedCoherence(ex)
value = preserveNumericValue(getNestedValue(ex, {'exp', 'CoPs', 'ctl', 'coherence'}));
if ~isnumeric(value) || isempty(value) || all(~isfinite(value(:)))
    value = 1;
end
end


function sessionTrackingSamples = initSessionTrackingSamples()
sessionTrackingSamples = struct( ...
    'errX', [], ...
    'errY', [], ...
    'bias', [], ...
    'biasX', [], ...
    'biasY', [], ...
    'screenCenterBias', [], ...
    'gaussSpecificBias', [], ...
    'targetDistFromCtr', [], ...
    'phaseCode', [], ...
    'noise', []);
end


function sessionTrackingSamples = appendSessionTrackingSamples(sessionTrackingSamples, centerBias, noiseLevel)
if ~isfield(centerBias, 'trackedErrXPx') || isempty(centerBias.trackedErrXPx)
    return
end

noiseVec = repmat(noiseLevel, numel(centerBias.trackedErrXPx), 1);
sessionTrackingSamples.errX = [sessionTrackingSamples.errX; centerBias.trackedErrXPx(:)]; %#ok<AGROW>
sessionTrackingSamples.errY = [sessionTrackingSamples.errY; centerBias.trackedErrYPx(:)]; %#ok<AGROW>
sessionTrackingSamples.bias = [sessionTrackingSamples.bias; centerBias.trackedBiasPx(:)]; %#ok<AGROW>
sessionTrackingSamples.biasX = [sessionTrackingSamples.biasX; centerBias.trackedBiasXPx(:)]; %#ok<AGROW>
sessionTrackingSamples.biasY = [sessionTrackingSamples.biasY; centerBias.trackedBiasYPx(:)]; %#ok<AGROW>
sessionTrackingSamples.screenCenterBias = [sessionTrackingSamples.screenCenterBias; centerBias.trackedScreenCenterBiasPx(:)]; %#ok<AGROW>
sessionTrackingSamples.gaussSpecificBias = [sessionTrackingSamples.gaussSpecificBias; centerBias.trackedGaussSpecificBiasPx(:)]; %#ok<AGROW>
sessionTrackingSamples.targetDistFromCtr = [sessionTrackingSamples.targetDistFromCtr; centerBias.trackedTargetDistFromCtrPx(:)]; %#ok<AGROW>
sessionTrackingSamples.phaseCode = [sessionTrackingSamples.phaseCode; centerBias.trackedPhaseCode(:)]; %#ok<AGROW>
sessionTrackingSamples.noise = [sessionTrackingSamples.noise; noiseVec(:)]; %#ok<AGROW>
end


function metrics = computeTrialTrackDistanceBinMetrics(peakBias, gaussSigma)
metricNames = { ...
    'nTrackedSamples', 'nTrackedSamplesNear', 'nTrackedSamplesMid', 'nTrackedSamplesFar', ...
    'trackErrorPxNear', 'trackErrorPxMid', 'trackErrorPxFar', ...
    'trackErrorRmsPxNear', 'trackErrorRmsPxMid', 'trackErrorRmsPxFar', ...
    'trackVariabilityPxNear', 'trackVariabilityPxMid', 'trackVariabilityPxFar', ...
    'trackBiasPxNear', 'trackBiasPxMid', 'trackBiasPxFar', ...
    'trackScreenCenterBiasPxNear', 'trackScreenCenterBiasPxMid', 'trackScreenCenterBiasPxFar', ...
    'trackGaussSpecificBiasPxNear', 'trackGaussSpecificBiasPxMid', 'trackGaussSpecificBiasPxFar', ...
    'trackBiasXPxNear', 'trackBiasXPxMid', 'trackBiasXPxFar', ...
    'trackBiasYPxNear', 'trackBiasYPxMid', 'trackBiasYPxFar'};
metrics = cell2struct(repmat({NaN}, size(metricNames)), metricNames, 2);

if ~isfield(peakBias, 'trackedTargetDistFromCtrPx') || isempty(peakBias.trackedTargetDistFromCtrPx)
    return
end

metrics.nTrackedSamples = numel(peakBias.trackedTargetDistFromCtrPx);

bins = resolveGaussDistanceBins(gaussSigma);
suffixMap = {'Near', 'Mid', 'Far'};
for i = 1:numel(bins)
    mask = bins(i).maskFn(peakBias.trackedTargetDistFromCtrPx(:));
    suffix = suffixMap{i};
    metrics.(['nTrackedSamples' suffix]) = sum(mask, 'omitnan');
    metrics.(['trackErrorPx' suffix]) = computeTrackErrorFromArrays(peakBias.trackedErrXPx, peakBias.trackedErrYPx, mask);
    metrics.(['trackErrorRmsPx' suffix]) = computeTrackErrorRmsFromArrays(peakBias.trackedErrXPx, peakBias.trackedErrYPx, mask);
    metrics.(['trackVariabilityPx' suffix]) = computeTrackVariabilityFromArrays(peakBias.trackedErrXPx, peakBias.trackedErrYPx, mask);
    metrics.(['trackBiasPx' suffix]) = meanWithMask(peakBias.trackedBiasPx, mask);
    metrics.(['trackScreenCenterBiasPx' suffix]) = meanWithMask(peakBias.trackedScreenCenterBiasPx, mask);
    metrics.(['trackGaussSpecificBiasPx' suffix]) = meanWithMask(peakBias.trackedGaussSpecificBiasPx, mask);
    metrics.(['trackBiasXPx' suffix]) = meanWithMask(peakBias.trackedBiasXPx, mask);
    metrics.(['trackBiasYPx' suffix]) = meanWithMask(peakBias.trackedBiasYPx, mask);
end
end


function metrics = computeTrialTrackPhaseBinMetrics(peakBias)
metricNames = { ...
    'nTrackedSamplesEarly','nTrackedSamplesLate', ...
    'trackErrorPxEarly','trackErrorPxLate', ...
    'trackErrorRmsPxEarly','trackErrorRmsPxLate', ...
    'trackVariabilityPxEarly','trackVariabilityPxLate', ...
    'trackBiasPxEarly','trackBiasPxLate', ...
    'trackScreenCenterBiasPxEarly','trackScreenCenterBiasPxLate', ...
    'trackGaussSpecificBiasPxEarly','trackGaussSpecificBiasPxLate', ...
    'trackBiasXPxEarly','trackBiasXPxLate', ...
    'trackBiasYPxEarly','trackBiasYPxLate'};
metrics = cell2struct(repmat({NaN}, size(metricNames)), metricNames, 2);

if ~isfield(peakBias, 'trackedPhaseCode') || isempty(peakBias.trackedPhaseCode)
    return
end

phaseDefs = getTrackPhaseBinDefinitions();
for i = 1:numel(phaseDefs)
    mask = peakBias.trackedPhaseCode(:) == phaseDefs(i).code;
    suffix = phaseDefs(i).suffix;
    metrics.(['nTrackedSamples' suffix]) = sum(mask);
    metrics.(['trackErrorPx' suffix]) = computeTrackErrorFromArrays(peakBias.trackedErrXPx, peakBias.trackedErrYPx, mask);
    metrics.(['trackErrorRmsPx' suffix]) = computeTrackErrorRmsFromArrays(peakBias.trackedErrXPx, peakBias.trackedErrYPx, mask);
    metrics.(['trackVariabilityPx' suffix]) = computeTrackVariabilityFromArrays(peakBias.trackedErrXPx, peakBias.trackedErrYPx, mask);
    metrics.(['trackBiasPx' suffix]) = meanWithMask(peakBias.trackedBiasPx, mask);
    metrics.(['trackScreenCenterBiasPx' suffix]) = meanWithMask(peakBias.trackedScreenCenterBiasPx, mask);
    metrics.(['trackGaussSpecificBiasPx' suffix]) = meanWithMask(peakBias.trackedGaussSpecificBiasPx, mask);
    metrics.(['trackBiasXPx' suffix]) = meanWithMask(peakBias.trackedBiasXPx, mask);
    metrics.(['trackBiasYPx' suffix]) = meanWithMask(peakBias.trackedBiasYPx, mask);
end
end


function value = meanWithMask(x, mask)
x = x(:);
mask = mask(:) & isfinite(x);
if ~any(mask)
    value = NaN;
    return
end
value = mean(x(mask), 'omitnan');
end


function value = computeTrackErrorFromArrays(errX, errY, mask)
errX = errX(:);
errY = errY(:);
mask = mask(:) & isfinite(errX) & isfinite(errY);
if ~any(mask)
    value = NaN;
    return
end
value = mean(hypot(errX(mask), errY(mask)), 'omitnan');
end


function value = computeTrackErrorRmsFromArrays(errX, errY, mask)
errX = errX(:);
errY = errY(:);
mask = mask(:) & isfinite(errX) & isfinite(errY);
if ~any(mask)
    value = NaN;
    return
end
value = sqrt(mean(errX(mask).^2 + errY(mask).^2, 'omitnan'));
end


function value = computeTrackVariabilityFromArrays(errX, errY, mask)
errX = errX(:);
errY = errY(:);
mask = mask(:) & isfinite(errX) & isfinite(errY);
if ~any(mask)
    value = NaN;
    return
end
errX = errX(mask);
errY = errY(mask);
meanErrX = mean(errX, 'omitnan');
meanErrY = mean(errY, 'omitnan');
value = sqrt(mean((errX - meanErrX).^2 + (errY - meanErrY).^2, 'omitnan'));
end


function bins = resolveGaussDistanceBins(gaussSigma)
defs = getGaussDistanceBinDefinitions(gaussSigma);
bins = defs;
bins(1).maskFn = @(d) isfinite(d) & d <= defs(1).upperPx;
bins(2).maskFn = @(d) isfinite(d) & d > defs(2).lowerPx & d <= defs(2).upperPx;
bins(3).maskFn = @(d) isfinite(d) & d > defs(3).lowerPx;
end


function defs = getGaussDistanceBinDefinitions(gaussSigma)
if ~isfinite(gaussSigma) || gaussSigma <= 0
    gaussSigma = 175;
end

defs = struct( ...
    'name', {'near', 'mid', 'far'}, ...
    'lowerPx', {0, gaussSigma, 2 * gaussSigma}, ...
    'upperPx', {gaussSigma, 2 * gaussSigma, Inf});
end


function defs = getTrackPhaseBinDefinitions()
defs = struct( ...
    'name', {'early', 'late'}, ...
    'suffix', {'Early', 'Late'}, ...
    'code', {1, 2});
end


function agg = buildTrackingAggregation(sessionTrackingSamples, gaussSigma)
agg = struct();
agg.distanceBins = struct();
agg.phaseBins = struct();

if isempty(sessionTrackingSamples.errX)
    return
end

bins = resolveGaussDistanceBins(gaussSigma);
for i = 1:numel(bins)
    binName = bins(i).name;
    mask = bins(i).maskFn(sessionTrackingSamples.targetDistFromCtr);
    agg.distanceBins.(binName) = summarizeTrackingStats(sessionTrackingSamples, mask);
end

phaseDefs = getTrackPhaseBinDefinitions();
for i = 1:numel(phaseDefs)
    phaseName = phaseDefs(i).name;
    mask = sessionTrackingSamples.phaseCode == phaseDefs(i).code;
    agg.phaseBins.(phaseName) = summarizeTrackingStats(sessionTrackingSamples, mask);
end
end


function stats = summarizeTrackingStats(sessionTrackingSamples, mask)
mask = mask(:);
errX = sessionTrackingSamples.errX(:);
errY = sessionTrackingSamples.errY(:);
[~, biasMask] = resolveTrackObservations(sessionTrackingSamples, 'bias', mask);
[~, screenMask] = resolveTrackObservations(sessionTrackingSamples, 'screenCenterBias', mask);
[~, gaussMask] = resolveTrackObservations(sessionTrackingSamples, 'gaussSpecificBias', mask);

valid = mask & isfinite(errX) & isfinite(errY) & biasMask(:) & screenMask(:) & gaussMask(:);
errX = sessionTrackingSamples.errX(valid);
errY = sessionTrackingSamples.errY(valid);
errDist = hypot(errX, errY);
bias = sessionTrackingSamples.bias(valid);
screenCenterBias = sessionTrackingSamples.screenCenterBias(valid);
gaussSpecificBias = sessionTrackingSamples.gaussSpecificBias(valid);

stats = struct( ...
    'n', numel(errX), ...
    'sumBias', sum(bias, 'omitnan'), ...
    'sumBiasX', sum(sessionTrackingSamples.biasX(valid), 'omitnan'), ...
    'sumBiasY', sum(sessionTrackingSamples.biasY(valid), 'omitnan'), ...
    'sumScreenCenterBias', sum(screenCenterBias, 'omitnan'), ...
    'sumGaussSpecificBias', sum(gaussSpecificBias, 'omitnan'), ...
    'sumErrDist', sum(errDist, 'omitnan'), ...
    'nErrDist', sum(isfinite(errDist)), ...
    'sumErrSq', sum(errX.^2 + errY.^2, 'omitnan'), ...
    'sumErrX', sum(errX, 'omitnan'), ...
    'sumErrY', sum(errY, 'omitnan'), ...
    'sumErrXSq', sum(errX.^2, 'omitnan'), ...
    'sumErrYSq', sum(errY.^2, 'omitnan'));
end


function suffix = makeNoiseLevelFieldSuffix(noiseLevel)
noiseLabel = regexprep(num2str(noiseLevel, '%.15g'), '\.', 'p');
noiseLabel = regexprep(noiseLabel, '-', 'm');
suffix = matlab.lang.makeValidName(['noise' noiseLabel]);
end


function noiseLevel = getTrialBackgroundNoiseLevel(T)
noiseLevel = NaN;
if isfield(T, 'background_noise_lvl') && isscalar(T.background_noise_lvl) && isnumeric(T.background_noise_lvl)
    noiseLevel = T.background_noise_lvl;
end
end


function trackingTable = buildTrialTrackingTable(trialNo, tRel, tAbs, stepIdx, xPx, yPx, ...
    targetX, targetY, target2X, target2Y, distPx1, distPx2, inBounds, betweenMarginPx, peakBias, peakPx, screenCenterPx, dtSec, preTrackingSec, blinkGapSec, trackingVar, requireTrackingSaccade, assignedTargetOverride)
trackingTable = table();

if nargin < 20 || isempty(blinkGapSec)
    blinkGapSec = 0;
end
if nargin < 21 || isempty(trackingVar)
    trackingVar = 'isTracking_wta';
end
if nargin < 22 || isempty(requireTrackingSaccade)
    requireTrackingSaccade = true;
end
if nargin < 23
    assignedTargetOverride = [];
end
trackingField = iResolveTrackingFieldLocal(trackingVar, requireTrackingSaccade);

if ~isstruct(peakBias) || ~isfield(peakBias, trackingField) || isempty(peakBias.(trackingField))
    return
end

singleTargetTrial = ~any(isfinite(target2X(:)) & isfinite(target2Y(:)));
if ~isempty(assignedTargetOverride)
    assignedSample = double(assignedTargetOverride(:));
    assignedSample(~ismember(assignedSample, [1 2])) = 0;
elseif singleTargetTrial
    assignedSample = ones(size(distPx1(:)));
else
    assign = assignTargetIdentityCoPs(distPx1, distPx2, inBounds, betweenMarginPx);
    assignedSample = assign.assignedSample(:);
end
if isempty(assignedTargetOverride) && strcmp(trackingField, 'isTrackingWTA') && ...
        isfield(peakBias, 'trackedTargetIdWTA') && ~isempty(peakBias.trackedTargetIdWTA)
    assignedSample = double(peakBias.trackedTargetIdWTA(:));
end
trackedSeries = peakBias.(trackingField)(:);
trackedMask = trackedSeries >= 1 & assignedSample > 0;
if ~any(trackedMask)
    return
end

trackedIdx = find(trackedMask);
trackedAssigned = assignedSample(trackedIdx);
runBreak = [true; diff(trackedIdx) > 1 | diff(trackedAssigned) ~= 0];
runStartPos = find(runBreak);
runEndPos = [runStartPos(2:end) - 1; numel(trackedIdx)];
runStartIdx = trackedIdx(runStartPos);
runEndIdx = trackedIdx(runEndPos);
runTargetId = assignedSample(runStartIdx);
phaseCodePerSample = NaN(size(assignedSample));
if strcmp(trackingField, 'isTracking') && isfield(peakBias, 'trackedPhaseCode') && ~isempty(peakBias.trackedPhaseCode)
    phaseCodePerSample(trackedMask) = peakBias.trackedPhaseCode(:);
end

if ~isfinite(dtSec) || dtSec <= 0
    preSamples = 0;
    maxBlinkGapSamples = 0;
else
    preSamples = max(0, round(max(preTrackingSec, 0) / dtSec));
    maxBlinkGapSamples = max(0, round(max(blinkGapSec, 0) / dtSec));
end

if numel(runStartIdx) >= 2 && maxBlinkGapSamples > 0
    mergedStarts = [];
    mergedEnds = [];
    mergedTargets = [];
    mergedStartIdx = runStartIdx(1);
    mergedEndIdx = runEndIdx(1);
    mergedTargetId = runTargetId(1);
    for i = 2:numel(runStartIdx)
        gapStartIdx = mergedEndIdx + 1;
        gapEndIdx = runStartIdx(i) - 1;
        gapLen = gapEndIdx - gapStartIdx + 1;
        sameTarget = runTargetId(i) == mergedTargetId;
        canBridge = false;
        if sameTarget && gapLen >= 1 && gapLen <= maxBlinkGapSamples
            gapMask = ~isfinite(xPx(gapStartIdx:gapEndIdx)) & ~isfinite(yPx(gapStartIdx:gapEndIdx));
            canBridge = all(gapMask);
        end
        if canBridge
            mergedEndIdx = runEndIdx(i);
        else
            mergedStarts(end+1,1) = mergedStartIdx; %#ok<AGROW>
            mergedEnds(end+1,1) = mergedEndIdx; %#ok<AGROW>
            mergedTargets(end+1,1) = mergedTargetId; %#ok<AGROW>
            mergedStartIdx = runStartIdx(i);
            mergedEndIdx = runEndIdx(i);
            mergedTargetId = runTargetId(i);
        end
    end
    mergedStarts(end+1,1) = mergedStartIdx;
    mergedEnds(end+1,1) = mergedEndIdx;
    mergedTargets(end+1,1) = mergedTargetId;
    runStartIdx = mergedStarts;
    runEndIdx = mergedEnds;
    runTargetId = mergedTargets;
end

trackingPieces = cell(numel(runStartIdx), 1);
for i = 1:numel(runStartIdx)
    startIdx = runStartIdx(i);
    endIdx = runEndIdx(i);
    intervalTargetId = runTargetId(i);
    if intervalTargetId == 1
        intervalTargetX = targetX(:);
        intervalTargetY = targetY(:);
    else
        intervalTargetX = target2X(:);
        intervalTargetY = target2Y(:);
    end

    windowStartIdx = max(1, startIdx - preSamples);
    sampleIdx = (windowStartIdx:endIdx)';
    nRun = numel(sampleIdx);
    startTimeRel = tRel(startIdx);
    endTimeRel = tRel(endIdx);
    startTimeAbs = tAbs(startIdx);
    endTimeAbs = tAbs(endIdx);
    durationSec = endTimeRel - startTimeRel;
    sampleFromTrackingOnset = sampleIdx - startIdx;
    tFromTrackingOnset = tRel(sampleIdx) - startTimeRel;

    trackedTargetX = intervalTargetX(sampleIdx);
    trackedTargetY = intervalTargetY(sampleIdx);
    targetToPeakX = peakPx(1) - trackedTargetX;
    targetToPeakY = peakPx(2) - trackedTargetY;
    targetToPeakNorm = hypot(targetToPeakX, targetToPeakY);
    unitToPeakX = targetToPeakX ./ targetToPeakNorm;
    unitToPeakY = targetToPeakY ./ targetToPeakNorm;
    unitToPeakX(~isfinite(unitToPeakX)) = NaN;
    unitToPeakY(~isfinite(unitToPeakY)) = NaN;

    targetToScreenCtrX = screenCenterPx(1) - trackedTargetX;
    targetToScreenCtrY = screenCenterPx(2) - trackedTargetY;
    targetToScreenCtrNorm = hypot(targetToScreenCtrX, targetToScreenCtrY);
    unitToScreenCtrX = targetToScreenCtrX ./ targetToScreenCtrNorm;
    unitToScreenCtrY = targetToScreenCtrY ./ targetToScreenCtrNorm;
    unitToScreenCtrX(~isfinite(unitToScreenCtrX)) = NaN;
    unitToScreenCtrY(~isfinite(unitToScreenCtrY)) = NaN;

    peakOnScreenDot = unitToPeakX .* unitToScreenCtrX + unitToPeakY .* unitToScreenCtrY;
    peakSpecificX = unitToPeakX - peakOnScreenDot .* unitToScreenCtrX;
    peakSpecificY = unitToPeakY - peakOnScreenDot .* unitToScreenCtrY;
    peakSpecificNorm = hypot(peakSpecificX, peakSpecificY);
    unitPeakSpecificX = peakSpecificX ./ peakSpecificNorm;
    unitPeakSpecificY = peakSpecificY ./ peakSpecificNorm;
    unitPeakSpecificX(peakSpecificNorm < 1e-6) = NaN;
    unitPeakSpecificY(peakSpecificNorm < 1e-6) = NaN;

    gazeErrX = xPx(sampleIdx) - trackedTargetX;
    gazeErrY = yPx(sampleIdx) - trackedTargetY;
    towardPeakX = sign(peakPx(1) - trackedTargetX);
    towardPeakY = sign(peakPx(2) - trackedTargetY);
    signedBiasX = gazeErrX .* towardPeakX;
    signedBiasY = gazeErrY .* towardPeakY;
    signedBias = gazeErrX .* unitToPeakX + gazeErrY .* unitToPeakY;
    signedScreenCenterBias = gazeErrX .* unitToScreenCtrX + gazeErrY .* unitToScreenCtrY;
    signedGaussSpecificBias = gazeErrX .* unitPeakSpecificX + gazeErrY .* unitPeakSpecificY;

    trackingPieces{i} = table( ...
        repmat(trialNo, nRun, 1), ...
        repmat(i, nRun, 1), ...
        sampleIdx(:), ...
        repmat(startIdx, nRun, 1), ...
        repmat(endIdx, nRun, 1), ...
        repmat(startTimeRel, nRun, 1), ...
        repmat(endTimeRel, nRun, 1), ...
        repmat(startTimeAbs, nRun, 1), ...
        repmat(endTimeAbs, nRun, 1), ...
        repmat(durationSec, nRun, 1), ...
        sampleFromTrackingOnset(:), ...
        tFromTrackingOnset(:), ...
        stepIdx(sampleIdx), ...
        repmat(intervalTargetId, nRun, 1), ...
        xPx(sampleIdx), ...
        yPx(sampleIdx), ...
        trackedTargetX(:), ...
        trackedTargetY(:), ...
        gazeErrX(:), ...
        gazeErrY(:), ...
        hypot(gazeErrX(:), gazeErrY(:)), ...
        signedBias(:), ...
        signedScreenCenterBias(:), ...
        signedGaussSpecificBias(:), ...
        signedBiasX(:), ...
        signedBiasY(:), ...
        targetToPeakNorm(:), ...
        trackedSeries(sampleIdx), ...
        'VariableNames', { ...
            'trial', 'intervalNo', 'sampleIdx', 'startSample', 'endSample', ...
            'startTimeRelSec', 'endTimeRelSec', 'startTimeAbsSec', 'endTimeAbsSec', 'durationSec', ...
            'sampleFromTrackingOnset', 'tFromTrackingOnsetSec', 'step', 'trackedTargetId', ...
            'xPx', 'yPx', 'trackedTargetX', 'trackedTargetY', ...
            'trackErrXPx', 'trackErrYPx', 'trackErrorPx', ...
            'trackBiasPx', 'trackScreenCenterBiasPx', 'trackGaussSpecificBiasPx', ...
            'trackBiasXPx', 'trackBiasYPx', 'trackedTargetDistFromCtrPx', 'isTracking'});
    trackingPieces{i}.trackedPhaseCode = phaseCodePerSample(sampleIdx);
end

trackingTable = vertcat(trackingPieces{:});
end


function rewardSwitchTable = buildRewardTriggeredSwitchTable(trialNo, tRel, stepIdx, distPx1, distPx2, inBounds, betweenMarginPx, T, analysisStartStep, backgroundNoiseLvl, windowSec, assignedTargetOverride)
rewardSwitchTable = table();
if nargin < 10 || isempty(windowSec)
    windowSec = [-0.5, 0.5];
end

if ~isfield(T, 'times') || ~isfield(T.times, 'reward') || isempty(T.times.reward)
    return
end

if nargin >= 12 && ~isempty(assignedTargetOverride)
    assign = localAssignmentFromTargetIds(assignedTargetOverride, stepIdx);
else
    assign = assignTargetIdentityCoPs(distPx1, distPx2, inBounds, betweenMarginPx, stepIdx);
end
uStep = assign.step(:);
assignedStep = assign.assignedStep(:);
if isempty(uStep) || isempty(assignedStep)
    return
end

stepTimes = NaN(size(uStep));
for k = 1:numel(uStep)
    m = isfinite(stepIdx) & (stepIdx == uStep(k)) & isfinite(tRel);
    if any(m)
        stepTimes(k) = min(tRel(m));
    end
end

validStep = isfinite(uStep) & isfinite(stepTimes) & (uStep >= analysisStartStep) & (assignedStep > 0);
seqAssigned = assignedStep(validStep);
seqTimes = stepTimes(validStep);
seqSteps = uStep(validStep);
if isempty(seqAssigned)
    return
end

switchMask = [false; diff(seqAssigned) ~= 0];
switchIdx = find(switchMask);
switchTimes = seqTimes(switchIdx);
switchSteps = seqSteps(switchIdx);
targetBefore = seqAssigned(switchIdx - 1);
targetAfter = seqAssigned(switchIdx);

rewardTimes = T.times.reward(:);
rewardTimes = rewardTimes(isfinite(rewardTimes));
if isempty(rewardTimes)
    return
end
if isfield(T, 'TrialStart') && isfinite(T.TrialStart)
    rewardTimes = rewardTimes - T.TrialStart;
end
analysisStartTime = min(tRel(isfinite(tRel) & isfinite(stepIdx) & stepIdx >= analysisStartStep), [], 'omitnan');
if isfinite(analysisStartTime)
    rewardTimes = rewardTimes(rewardTimes >= analysisStartTime);
end
trialEndTime = max(tRel, [], 'omitnan');
if isfinite(trialEndTime)
    rewardTimes = rewardTimes(rewardTimes <= trialEndTime);
end
if isempty(rewardTimes)
    return
end

rows = cell(numel(rewardTimes), 1);
for r = 1:numel(rewardTimes)
    rel = switchTimes - rewardTimes(r);
    keep = rel >= windowSec(1) & rel <= windowSec(2);
    if any(keep)
        rows{r} = table( ...
            repmat(trialNo, sum(keep), 1), ...
            repmat(r, sum(keep), 1), ...
            rewardTimes(r) * ones(sum(keep), 1), ...
            switchIdx(keep), ...
            switchSteps(keep), ...
            switchTimes(keep), ...
            rel(keep), ...
            targetBefore(keep), ...
            targetAfter(keep), ...
            repmat(backgroundNoiseLvl, sum(keep), 1), ...
            true(sum(keep), 1), ...
            'VariableNames', { ...
                'trial', 'rewardNo', 'rewardTimeRelSec', 'switchNo', 'switchStep', ...
                'switchTimeRelSec', 'tFromRewardSec', 'targetBefore', 'targetAfter', ...
                'backgroundNoiseLvl', 'hasSwitch'});
    else
        rows{r} = table( ...
            trialNo, ...
            r, ...
            rewardTimes(r), ...
            NaN, ...
            NaN, ...
            NaN, ...
            NaN, ...
            NaN, ...
            NaN, ...
            backgroundNoiseLvl, ...
            false, ...
            'VariableNames', { ...
                'trial', 'rewardNo', 'rewardTimeRelSec', 'switchNo', 'switchStep', ...
                'switchTimeRelSec', 'tFromRewardSec', 'targetBefore', 'targetAfter', ...
                'backgroundNoiseLvl', 'hasSwitch'});
    end
end

rewardSwitchTable = vertcat(rows{:});
end


function mask = analysisMaskFromStep(stepIdx, analysisStartStep)
mask = isfinite(stepIdx(:)) & stepIdx(:) >= analysisStartStep;
end

function trackingField = iResolveTrackingFieldLocal(trackingVar, requireTrackingSaccade)
trackingVar = char(string(trackingVar));
switch trackingVar
    case 'isTracking'
        if requireTrackingSaccade
            trackingField = 'isTrackingSacc';
        else
            trackingField = 'isTracking';
        end
    case 'isTracking_conserv'
        trackingField = 'isTrackingConserv';
    case 'isTracking_lib'
        trackingField = 'isTrackingLib';
    case 'isTracking_wta'
        trackingField = 'isTrackingWTA';
    otherwise
        error('processCoPsEye:BadTrackingVar', ...
            'opts.trackingVar must be ''isTracking'', ''isTracking_conserv'', ''isTracking_lib'', or ''isTracking_wta''.');
end
end


function name = basenameStringLocal(pathValue)
name = "";
if ~(ischar(pathValue) || isstring(pathValue))
    return
end
pathStr = char(string(pathValue));
if isempty(pathStr)
    return
end
[~, baseName, ext] = fileparts(pathStr);
if isempty(baseName) && isempty(ext)
    return
end
if isempty(baseName)
    name = string(ext);
else
    name = string(baseName);
end
end


function value = getNestedValue(s, fields)
value = NaN;
cur = s;
for i = 1:numel(fields)
    field = fields{i};
    if ~isstruct(cur) || ~isfield(cur, field)
        return
    end
    cur = cur.(field);
end
value = cur;
end


function value = getNestedNumeric(s, fields)
value = getNestedValue(s, fields);
if isempty(value)
    value = NaN;
elseif ~isscalar(value) || ~isnumeric(value)
    value = NaN;
end
end


function value = getFirstAvailableNestedNumeric(s, fieldSets)
value = NaN;
for i = 1:numel(fieldSets)
    value = getNestedNumeric(s, fieldSets{i});
    if isfinite(value)
        return
    end
end
end


function value = getNestedNumericOrLogical(s, fields)
value = getNestedValue(s, fields);
if isempty(value)
    value = NaN;
elseif ~isscalar(value) || ~(isnumeric(value) || islogical(value))
    value = NaN;
else
    value = double(value);
end
end


function value = summarizeNumericValue(x)
if isempty(x) || ~isnumeric(x)
    value = NaN;
elseif isscalar(x)
    value = x;
else
    value = mean(x(:), 'omitnan');
end
end


function value = preserveNumericValue(x)
if isempty(x) || ~isnumeric(x)
    value = NaN;
else
    value = double(x);
end
end


function [targetX, targetY, target2X, target2Y] = canonicalizeTargetOrder(targetX, targetY, target2X, target2Y)
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


function source = localResolveTrackingSource(value)
key = lower(strrep(strrep(char(string(value)), '-', ''), '_', ''));
switch key
    case {'hmmsmoothed', 'smoothed'}
        source = 'hmmSmoothed';
    case {'hmmfiltered', 'filtered'}
        source = 'hmmFiltered';
    case {'hmmpredictive', 'predictive'}
        source = 'hmmPredictive';
    case {'modelfree', 'geometric'}
        source = 'model-free';
    otherwise
        error('processCoPsEye:BadTrackingSource', ...
            ['opts.trackingSource must be ''hmmSmoothed'', ''hmmFiltered'', ' ...
             '''hmmPredictive'', or ''model-free''.']);
end
end


function threshold = localResolveHmmHardThreshold(value)
threshold = double(value);
if ~isscalar(threshold) || ~isfinite(threshold) || threshold < 0.5 || threshold > 1
    error('processCoPsEye:BadHmmHardThreshold', ...
        'opts.hmmHardThreshold must be a finite scalar between 0.5 and 1.');
end
end


function coverage = localValidateHmmCoverage(trials, source)
coverage = struct('source', source, 'nTrials', numel(trials), ...
    'nTrialsWithProbabilities', NaN, 'nTrialsMissingProbabilities', NaN);
if strcmp(source, 'model-free')
    return
end

method = lower(erase(source, 'hmm'));
hasProbabilities = false(numel(trials), 1);
for trialNo = 1:numel(trials)
    T = trials(trialNo);
    if isfield(T, 'hmm') && isstruct(T.hmm) && ...
            isfield(T.hmm, method) && isstruct(T.hmm.(method)) && ...
            isfield(T.hmm.(method), 'pTLeft')
        values = double(T.hmm.(method).pTLeft(:));
        hasProbabilities(trialNo) = any(isfinite(values));
    end
end
coverage.nTrialsWithProbabilities = sum(hasProbabilities);
coverage.nTrialsMissingProbabilities = sum(~hasProbabilities);
if coverage.nTrialsWithProbabilities == 0
    error('processCoPsEye:MissingHmmTracking', ...
        ['No usable %s probabilities were found anywhere in ex.Trials. ' ...
         'Merge the matching HMM prediction sidecar with mergeCoPsHmmStruct(), ' ...
         'or set opts.trackingSource to ''model-free'' explicitly.'], source);
end
end


function [assignedTarget, available] = localHmmAssignedTarget(T, stepIdx, source, threshold)
assignedTarget = [];
available = false;
if strcmp(source, 'model-free')
    return
end

stepIdx = double(stepIdx(:));
assignedTarget = nan(size(stepIdx));
method = lower(erase(source, 'hmm'));
if ~isfield(T, 'hmm') || ~isstruct(T.hmm) || ...
        ~isfield(T.hmm, method) || ~isstruct(T.hmm.(method)) || ...
        ~isfield(T.hmm.(method), 'pTLeft')
    return
end

methodHmm = T.hmm.(method);
[assignedTarget, available] = assignHmmTrackingStateCoPs( ...
    methodHmm, stepIdx, threshold);
end


function trialSummary = localSetHmmTrackingMissing(trialSummary, trialNo)
names = string(trialSummary.Properties.VariableNames);
prefixes = ["isTracking", "peakTrack", "outerTrack", "firstTrack", ...
    "trackError", "trackVariability", "trackBias", "trackScreenCenterBias", ...
    "trackGaussSpecificBias", "nTracked", "switchToPeak", ...
    "switchWhenOtherPeak", "switchProb", "saccTo", "saccPeak"];
isTrackingMetric = false(size(names));
for i = 1:numel(prefixes)
    isTrackingMetric = isTrackingMetric | startsWith(names, prefixes(i));
end
trialSummary{trialNo, cellstr(names(isTrackingMetric))} = NaN(1, sum(isTrackingMetric));
end


function assign = localAssignmentFromTargetIds(assignedTarget, stepIdx)
assignedTarget = double(assignedTarget(:));
invalidCode = isfinite(assignedTarget) & ~ismember(assignedTarget, [0 1 2]);
assignedTarget(invalidCode) = 0;
assign = struct('assignedSample', assignedTarget, 'betweenSample', assignedTarget == 0);
stepIdx = double(stepIdx(:));
uStep = unique(stepIdx(isfinite(stepIdx)));
uStep = uStep(:);
assignedStep = zeros(size(uStep));
for k = 1:numel(uStep)
    values = assignedTarget(stepIdx == uStep(k));
    values = values(values > 0);
    n1 = sum(values == 1);
    n2 = sum(values == 2);
    if n1 > n2
        assignedStep(k) = 1;
    elseif n2 > n1
        assignedStep(k) = 2;
    end
end
assign.step = uStep;
assign.assignedStep = assignedStep;
end


function stab = localSwitchingFromHmm(assignedTarget, tRel, stepIdx, nsteps)
stab = struct( ...
    'bothFrac', NaN, ...
    'switchRateHz', NaN, ...
    'transProbStep', NaN, ...
    'meanDwellSteps', NaN, ...
    'meanDwellSec', NaN, ...
    'switchIndicators', false(0, 1), ...
    'stayIndicators', false(0, 1), ...
    'dwellSteps', zeros(0, 1), ...
    'dwellSec', zeros(0, 1), ...
    'trialDurSec', NaN);

assign = localAssignmentFromTargetIds(assignedTarget, stepIdx);
assignedStep = assign.assignedStep(:);
steps = assign.step(:);
if isempty(steps)
    return
end

stepHasProbability = false(size(steps));
assignedTarget = double(assignedTarget(:));
stepIdx = double(stepIdx(:));
for k = 1:numel(steps)
    stepHasProbability(k) = any(isfinite(assignedTarget(stepIdx == steps(k))));
end
if any(stepHasProbability)
    stab.bothFrac = mean(assignedStep(stepHasProbability) == 0);
end

assigned = assignedStep(assignedStep > 0);
if isempty(assigned)
    return
end
switched = diff(assigned) ~= 0;
stab.switchIndicators = switched(:);
stab.stayIndicators = ~switched(:);
stab.transProbStep = sum(switched) / max(numel(assigned) - 1, 1);

runIdx = cumsum([true; switched(:)]);
dwellSteps = accumarray(runIdx, 1);
stab.dwellSteps = dwellSteps(:);
stab.meanDwellSteps = mean(dwellSteps, 'omitnan');

finiteTime = double(tRel(isfinite(tRel)));
if numel(finiteTime) >= 2
    trialDurSec = max(finiteTime) - min(finiteTime);
    stab.trialDurSec = trialDurSec;
    if trialDurSec > 0
        stab.switchRateHz = sum(switched) / trialDurSec;
        stepDurSec = trialDurSec / max(double(nsteps), 1);
        stab.dwellSec = dwellSteps(:) * stepDurSec;
        stab.meanDwellSec = stab.meanDwellSteps * stepDurSec;
    end
end
end


function meanDist = meanDistanceToCloserTarget(gazeX, gazeY, targetX, targetY, target2X, target2Y, mask)
gazeX = gazeX(:);
gazeY = gazeY(:);
targetX = targetX(:);
targetY = targetY(:);
target2X = target2X(:);
target2Y = target2Y(:);
mask = mask(:);

n = min([numel(gazeX), numel(gazeY), numel(targetX), numel(targetY), ...
    numel(target2X), numel(target2Y), numel(mask)]);
if n == 0
    meanDist = NaN;
    return
end

gazeX = gazeX(1:n);
gazeY = gazeY(1:n);
targetX = targetX(1:n);
targetY = targetY(1:n);
target2X = target2X(1:n);
target2Y = target2Y(1:n);
mask = mask(1:n);

d1 = hypot(gazeX - targetX, gazeY - targetY);
d2 = hypot(gazeX - target2X, gazeY - target2Y);
d = d1;
useT2 = isfinite(d2) & ((~isfinite(d1)) | d2 < d1);
d(useT2) = d2(useT2);
keep = mask & isfinite(d);
if ~any(keep)
    meanDist = NaN;
else
    meanDist = mean(d(keep), 'omitnan');
end
end


function trialSummary = assignPermutedDistanceControl(trialSummary, permControlData)
eligibleIdx = find(~cellfun(@isempty, permControlData));
if numel(eligibleIdx) < 2
    return
end

permOrder = eligibleIdx(randperm(numel(eligibleIdx)));
if any(permOrder == eligibleIdx)
    permOrder = eligibleIdx([2:end, 1]);
end

for i = 1:numel(eligibleIdx)
    srcIdx = eligibleIdx(i);
    permIdx = permOrder(i);
    if srcIdx == permIdx
        continue
    end

    src = permControlData{srcIdx};
    perm = permControlData{permIdx};
    [permX, permY] = resampleGazeTrajectory(perm.xPx, perm.yPx, numel(src.xPx));
    trialSummary.distPerm(srcIdx) = meanDistanceToCloserTarget( ...
        permX, permY, src.targetX, src.targetY, src.target2X, src.target2Y, src.analysisMask);
end
end


function [xOut, yOut] = resampleGazeTrajectory(xIn, yIn, nOut)
if numel(xIn) == nOut
    xOut = xIn;
    yOut = yIn;
    return
end

tIn = linspace(0, 1, numel(xIn));
tOut = linspace(0, 1, nOut);
xOut = interpFinite1(tIn, xIn, tOut);
yOut = interpFinite1(tIn, yIn, tOut);
end


function yOut = interpFinite1(xIn, yIn, xOut)
valid = isfinite(yIn);
if sum(valid) < 2
    yOut = NaN(size(xOut));
    return
end
yOut = interp1(xIn(valid), yIn(valid), xOut, 'linear', NaN);
end
