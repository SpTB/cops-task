function T = checkPeakTrackFrac(ex, trials, opts)
% checkPeakTrackFrac Recompute peakTrackFrac directly from ex.Trials.
%
% Usage:
%   T = checkPeakTrackFrac(ex)
%   T = checkPeakTrackFrac(ex, 15)
%   T = checkPeakTrackFrac(ex, [10 15 20], opts)
%
% Options:
%   opts.useEyeTime             default false
%   opts.onlyGoState            default true
%   opts.minInBoundsFrac        default 0.33
%   opts.minRewardPoints        default 500
%   opts.analysisStartStep      default 1
%   opts.trackingDistMult       default 2.5
%   opts.minTrackingSec         default 0.05
%   opts.requireTrackingSaccade default false
%   opts.trackingVar            default 'isTracking'

if nargin < 2 || isempty(trials)
    trials = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
end

defaults = struct( ...
    'useEyeTime', true, ...
    'onlyGoState', true, ...
    'minInBoundsFrac', 0.33, ...
    'minRewardPoints', 500, ...
    'analysisStartStep', 1, ...
    'trackingDistMult', 2.5, ...
    'minTrackingSec', 0.05, ...
    'requireTrackingSaccade', false, ...
    'trackingVar', 'isTracking');
f = fieldnames(defaults);
for i = 1:numel(f)
    if ~isfield(opts, f{i})
        opts.(f{i}) = defaults.(f{i});
    end
end

if isempty(trials)
    trials = findMainTrialsLocal(ex);
end
trials = trials(:)';

rows = cell(numel(trials), 1);
dtSec = 1 / inferFs(ex);
captureRadiusPx = ex.exp.CoPs.graph.radius * ex.exp.CoPs.graph.size_mult;
betweenMarginPx = captureRadiusPx / 2;
trackingDistPx = opts.trackingDistMult * captureRadiusPx;

for ii = 1:numel(trials)
    j = trials(ii);
    Ttrial = ex.Trials(j);

    [xPx, yPx, tRel, tAbs, valid] = reconstructEyePx(ex, Ttrial, opts.useEyeTime, opts);
    [targetX, targetY, target2X, target2Y, stepIdx] = mapTargetsByStep(ex, Ttrial, tRel);

    sel = selectTrials(ex, Ttrial, tAbs, xPx, yPx, valid, opts);
    inBounds = sel.inBounds;

    if opts.onlyGoState
        goMask = tAbs >= Ttrial.times.stimOn & tAbs <= Ttrial.TrialEnd;
    else
        goMask = true(size(tAbs));
    end

    xPx = xPx(goMask);
    yPx = yPx(goMask);
    tRel = tRel(goMask);
    targetX = targetX(goMask);
    targetY = targetY(goMask);
    target2X = target2X(goMask);
    target2Y = target2Y(goMask);
    stepIdx = stepIdx(goMask);
    inBounds = inBounds(goMask);

    [targetX, targetY, target2X, target2Y] = canonicalizeTargetOrderLocal(targetX, targetY, target2X, target2Y);

    distPx1 = computeDistanceToTargets(xPx, yPx, targetX, targetY, inBounds);
    distPx2 = computeDistanceToTargets(xPx, yPx, target2X, target2Y, inBounds);
    analysisMask = stepIdx >= opts.analysisStartStep;

    assign = assignTargetIdentityCoPs(distPx1, distPx2, inBounds, betweenMarginPx);
    tracked = detectTrackedSamplesCoPs( ...
        assign.assignedSample, distPx1, distPx2, xPx, yPx, trackingDistPx, ...
        opts.minTrackingSec, dtSec, ex.setup, opts.requireTrackingSaccade);

    trackedSeries = resolveTrackingSeriesLocal(tracked, opts.trackingVar, opts.requireTrackingSaccade);
    trackedMask = trackedSeries >= 1 & assign.assignedSample > 0 & analysisMask;

    gaussCtr = getGaussianCenterPx(ex, Ttrial);
    distCtr1 = hypot(targetX(:) - gaussCtr(1), targetY(:) - gaussCtr(2));
    distCtr2 = hypot(target2X(:) - gaussCtr(1), target2Y(:) - gaussCtr(2));
    peakCloser = zeros(size(distCtr1));
    peakCloser(distCtr1 < distCtr2) = 1;
    peakCloser(distCtr2 < distCtr1) = 2;

    trackedAssigned = assign.assignedSample(trackedMask);
    trackedPeak = peakCloser(trackedMask);
    trackedIsPeak = trackedAssigned == trackedPeak & trackedPeak > 0;

    rows{ii} = table( ...
        j, ...
        sum(analysisMask & inBounds, 'omitnan'), ...
        sum(trackedMask, 'omitnan'), ...
        mean(trackedIsPeak, 'omitnan'), ...
        mean(trackedSeries(analysisMask & inBounds), 'omitnan'), ...
        sel.keepTrial, ...
        'VariableNames', {'trial', 'nAnalyzedSamples', 'nTrackedSamples', 'peakTrackFracManual', 'meanTrackingSeries', 'keepTrial'});
end

if isempty(rows)
    T = table();
else
    T = vertcat(rows{:});
end
end


function trials = findMainTrialsLocal(ex)
nTr = numel(ex.Trials);
keep = false(nTr, 1);
for j = 1:nTr
    T = ex.Trials(j);
    isFixationTrial = isfield(T, 'isFixationTrial') && logical(T.isFixationTrial);
    isTutorialTrial = isfield(T, 'isTutorialTrial') && logical(T.isTutorialTrial);
    hasRunPhase = isfield(T, 'runPhase') && ~isempty(T.runPhase);
    if hasRunPhase
        runPhase = string(T.runPhase);
        isMainTrial = runPhase == "main";
    else
        isMainTrial = ~isFixationTrial && ~isTutorialTrial;
    end
    keep(j) = isMainTrial && ~isFixationTrial && ~isTutorialTrial;
end
trials = find(keep);
end


function trackedSeries = resolveTrackingSeriesLocal(tracked, trackingVar, requireTrackingSaccade)
trackingVar = char(string(trackingVar));
switch trackingVar
    case 'isTracking'
        if requireTrackingSaccade
            trackedSeries = tracked.isTrackingSacc;
        else
            trackedSeries = tracked.isTracking;
        end
    case 'isTracking_conserv'
        trackedSeries = tracked.isTrackingConserv;
    case 'isTracking_lib'
        trackedSeries = tracked.isTrackingLib;
    otherwise
        error('checkPeakTrackFrac:BadTrackingVar', ...
            'trackingVar must be ''isTracking'', ''isTracking_conserv'', or ''isTracking_lib''.');
end
end


function [targetX, targetY, target2X, target2Y] = canonicalizeTargetOrderLocal(targetX, targetY, target2X, target2Y)
swapMask = (targetX > target2X) | ((targetX == target2X) & (targetY > target2Y));
tmpX = targetX(swapMask);
tmpY = targetY(swapMask);
targetX(swapMask) = target2X(swapMask);
targetY(swapMask) = target2Y(swapMask);
target2X(swapMask) = tmpX;
target2Y(swapMask) = tmpY;
end
