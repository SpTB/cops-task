function out = debugSaccadeDetection(ex, trialNo, opts)
% debugSaccadeDetection  Diagnose why an event is or is not detected as a saccade.
%
%   out = debugSaccadeDetection(ex, 18)
%   out = debugSaccadeDetection(ex, 18, opts)
%
% Useful opts fields:
%   .onlyGoState            (default true)
%   .useEyeTime             (default false)
%   .timeWindowSec          (default []) trial-relative seconds for
%                           returned rows / plotting only
%   .detectWindowSec        (default []) trial-relative seconds to crop
%                           before running the detector
%   .truncateTrialFromStep  (default 0)
%   .speedThreshDegPerSec   (default 10)
%   .minAmpDeg              (default 1)
%   .minDurSec              (default 0.008)
%   .maxDurSec              (default 0.060)
%   .smoothFrames           (default 5)
%   .plot                   (default true)
%   .newFigure              (default true)
%
% Output fields:
%   .samples    samplewise table
%   .segments   segment diagnostic table
%   .params     resolved detector params

if nargin < 2 || isempty(trialNo)
    error('debugSaccadeDetection:MissingTrialNo', 'trialNo is required.');
end
if nargin < 3 || isempty(opts)
    opts = struct();
end

defaults = struct( ...
    'onlyGoState', true, ...
    'useEyeTime', true, ...
    'timeWindowSec', [], ...
    'detectWindowSec', [], ...
    'truncateTrialFromStep', 0, ...
    'speedThreshDegPerSec', 10, ...
    'minAmpDeg', 1, ...
    'minDurSec', 0.008, ...
    'maxDurSec', 5, ...
    'smoothFrames', 5, ...
    'plot', true, ...
    'newFigure', true);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field) || isempty(opts.(field))
        opts.(field) = defaults.(field);
    end
end

trialNo = double(trialNo);
if ~isscalar(trialNo) || ~isfinite(trialNo) || trialNo < 1 || trialNo > numel(ex.Trials) || trialNo ~= round(trialNo)
    error('debugSaccadeDetection:BadTrialNo', 'trialNo must be a valid trial index.');
end

T = ex.Trials(trialNo);
[xPx, yPx, tRel, tAbs, valid] = reconstructEyePx(ex, T, opts.useEyeTime, opts);

goMask = true(size(tRel));
if opts.onlyGoState && isfield(T, 'times') && isfield(T.times, 'stimOn') && isfield(T, 'TrialEnd')
    goMask = tAbs >= T.times.stimOn & tAbs <= T.TrialEnd;
end
xPx = xPx(goMask);
yPx = yPx(goMask);
tRel = tRel(goMask);
tAbs = tAbs(goMask);
valid = valid(goMask);

[~, ~, ~, ~, stepIdx] = mapTargetsByStep(ex, T, tRel);
truncateFromStep = localFirstScalar(opts.truncateTrialFromStep);
if isfinite(truncateFromStep) && truncateFromStep > 0
    keepMask = isfinite(stepIdx) & stepIdx >= truncateFromStep;
    xPx = xPx(keepMask);
    yPx = yPx(keepMask);
    tRel = tRel(keepMask);
    tAbs = tAbs(keepMask);
    valid = valid(keepMask);
    stepIdx = stepIdx(keepMask);
end

twDetect = localTimeWindow(opts.detectWindowSec);
if ~isempty(twDetect)
    keepMask = tRel >= twDetect(1) & tRel <= twDetect(2);
    xPx = xPx(keepMask);
    yPx = yPx(keepMask);
    tRel = tRel(keepMask);
    tAbs = tAbs(keepMask);
    valid = valid(keepMask);
    stepIdx = stepIdx(keepMask);
end

tw = localTimeWindow(opts.timeWindowSec);
if ~isempty(tw)
    keepMask = tRel >= tw(1) & tRel <= tw(2);
    xPx = xPx(keepMask);
    yPx = yPx(keepMask);
    tRel = tRel(keepMask);
    tAbs = tAbs(keepMask);
    valid = valid(keepMask);
    stepIdx = stepIdx(keepMask);
end

dtSec = localResolveSampleDt(tRel, 1 / inferFs(ex));
params = localSaccadeParams(dtSec, opts);

xSmooth = movmean(xPx, params.smoothFrames, 'omitnan');
ySmooth = movmean(yPx, params.smoothFrames, 'omitnan');
dxPx = [0; diff(xSmooth)];
dyPx = [0; diff(ySmooth)];
speedPxPerSec = hypot(dxPx, dyPx) ./ dtSec;
speedDegPerSec = px2deg(speedPxPerSec, ex.setup);

validMask = isfinite(speedDegPerSec) & isfinite(xSmooth) & isfinite(ySmooth);
candidateMask = validMask & (speedDegPerSec >= params.speedThreshDegPerSec);

maskPadded = [false; candidateMask; false];
segStarts = find(diff(maskPadded) == 1);
segStops = find(diff(maskPadded) == -1) - 1;
nSeg = numel(segStarts);

segTrial = repmat(trialNo, nSeg, 1);
segNo = (1:nSeg)';
segStartSec = NaN(nSeg, 1);
segStopSec = NaN(nSeg, 1);
segDurSec = NaN(nSeg, 1);
segPeakSpeedDegPerSec = NaN(nSeg, 1);
segAmpDeg = NaN(nSeg, 1);
passDur = false(nSeg, 1);
passAmp = false(nSeg, 1);
accepted = false(nSeg, 1);
rejectReason = strings(nSeg, 1);
for k = 1:nSeg
    idx = segStarts(k):segStops(k);
    segStartSec(k) = tRel(segStarts(k));
    segStopSec(k) = tRel(segStops(k));
    segDurSec(k) = numel(idx) * dtSec;
    segPeakSpeedDegPerSec(k) = max(speedDegPerSec(idx), [], 'omitnan');
    ampPx = hypot(xSmooth(segStops(k)) - xSmooth(segStarts(k)), ySmooth(segStops(k)) - ySmooth(segStarts(k)));
    segAmpDeg(k) = px2deg(ampPx, ex.setup);
    passDur(k) = numel(idx) >= params.minDurFrames && numel(idx) <= params.maxDurFrames;
    passAmp(k) = isfinite(segAmpDeg(k)) && segAmpDeg(k) >= params.minAmpDeg;
    accepted(k) = passDur(k) && passAmp(k);
    if accepted(k)
        rejectReason(k) = "accepted";
    elseif ~passDur(k)
        if numel(idx) < params.minDurFrames
            rejectReason(k) = "too short";
        else
            rejectReason(k) = "too long";
        end
    elseif ~passAmp(k)
        rejectReason(k) = "amp too small";
    else
        rejectReason(k) = "other";
    end
end

samples = table( ...
    repmat(trialNo, numel(tRel), 1), (1:numel(tRel))', tRel(:), tAbs(:), stepIdx(:), ...
    xPx(:), yPx(:), xSmooth(:), ySmooth(:), valid(:), ...
    speedDegPerSec(:), candidateMask(:), ...
    'VariableNames', {'trial','sampleIdx','tRelSec','tAbsSec','step', ...
    'xPx','yPx','xSmooth','ySmooth','valid','speedDegPerSec','candidateMask'});

segments = table( ...
    segTrial, segNo, segStarts, segStops, segStartSec, segStopSec, segDurSec, ...
    segPeakSpeedDegPerSec, segAmpDeg, passDur, passAmp, accepted, rejectReason, ...
    'VariableNames', {'trial','segmentNo','startIdx','stopIdx','startSec','stopSec','durSec', ...
    'peakSpeedDegPerSec','ampDeg','passDur','passAmp','accepted','rejectReason'});

if opts.plot
    if opts.newFigure
        figure;
    end
    tiledlayout(3, 1, 'Padding', 'compact', 'TileSpacing', 'compact');

    nexttile;
    plot(tRel, xPx, 'b', 'LineWidth', 1); hold on
    plot(tRel, xSmooth, 'r', 'LineWidth', 1);
    ylabel('X (px)');
    title(sprintf('Trial %d saccade debug', trialNo), 'Interpreter', 'none');
    legend({'x raw', 'x smooth'}, 'Location', 'best');
    box off

    nexttile;
    plot(tRel, speedDegPerSec, 'k', 'LineWidth', 1); hold on
    yline(params.speedThreshDegPerSec, ':r', 'LineWidth', 1);
    for k = 1:nSeg
        c = [0.7 0.7 0.7];
        if accepted(k)
            c = [0.2 0.7 0.2];
        end
        patch([segStartSec(k) segStopSec(k) segStopSec(k) segStartSec(k)], ...
              [0 0 max(speedDegPerSec, [], 'omitnan') max(speedDegPerSec, [], 'omitnan')], ...
              c, 'FaceAlpha', 0.12, 'EdgeColor', 'none');
    end
    plot(tRel, speedDegPerSec, 'k', 'LineWidth', 1);
    ylabel('Speed (deg/s)');
    box off

    nexttile;
    stairs(tRel, double(candidateMask), 'k', 'LineWidth', 1); hold on
    if any(accepted)
        acceptedMask = false(size(candidateMask));
        for k = find(accepted(:))'
            acceptedMask(segStarts(k):segStops(k)) = true;
        end
        stairs(tRel, 1.1 * double(acceptedMask), 'g', 'LineWidth', 1.5);
    end
    ylim([-0.1 1.3]);
    xlabel('Trial time (s)');
    ylabel('Mask');
    yticks([0 1]);
    yticklabels({'off', 'on'});
    box off
end

out = struct();
out.samples = samples;
out.segments = segments;
out.params = params;
end


function params = localSaccadeParams(dtSec, opts)
params = struct();
params.preSaccadeWindowFrames = 3;
params.speedThreshDegPerSec = opts.speedThreshDegPerSec;
params.minAmpDeg = opts.minAmpDeg;
params.minDurSec = opts.minDurSec;
params.maxDurSec = opts.maxDurSec;
params.smoothFrames = opts.smoothFrames;
if ~isfinite(dtSec) || dtSec <= 0
    params.minDurFrames = 1;
    params.maxDurFrames = inf;
else
    params.preSaccadeWindowSec = params.preSaccadeWindowFrames * dtSec;
    params.minDurFrames = max(1, round(params.minDurSec / dtSec));
    params.maxDurFrames = max(params.minDurFrames, round(params.maxDurSec / dtSec));
end
end


function value = localFirstScalar(value)
if isempty(value)
    value = NaN;
else
    value = double(value(1));
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


function dtSec = localResolveSampleDt(tRel, fallbackDtSec)
dtSec = fallbackDtSec;
if numel(tRel) >= 2
    d = diff(tRel(:));
    d = d(isfinite(d) & d > 0);
    if ~isempty(d)
        dtSec = median(d);
    end
end
if ~isfinite(dtSec) || dtSec <= 0
    dtSec = fallbackDtSec;
end
end
