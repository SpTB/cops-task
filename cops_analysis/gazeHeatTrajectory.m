function out = gazeHeatTrajectory(ex, trialNo, opts)
% gazeHeatTrajectory  Track rolling gaze-density peak relative to reward.
%
%   T = gazeHeatTrajectory(ex)
%   T = gazeHeatTrajectory(ex, 1:120)
%   T = gazeHeatTrajectory(ex, trialNo, opts)
%
% Defaults use rolling 20-trial windows stepped by 5 trials. Coordinates
% follow gazeHeat defaults, but reward alignment and final 45-deg rotation
% are off by default for this trajectory analysis. Single-target trials are
% excluded by default via opts.targetNum = 2.

if nargin < 2 || isempty(trialNo)
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
    error('gazeHeatTrajectory:BadOpts', 'opts must be a struct.');
end

opts = localDefaults(opts);
trialList = localResolveTrialList(ex, trialNo, opts);
windows = localBuildWindows( ...
    trialList, opts.windowTrials, opts.stepTrials, opts.includePartialWindows);

nWin = size(windows, 1);
rows = localInitRows(nWin);
windowInfo = repmat(struct( ...
    'trials', [], ...
    'xCentersDeg', [], ...
    'yCentersDeg', [], ...
    'density', [], ...
    'gazeDensity', [], ...
    'targetDensity', [], ...
    'rewardPeakDeg', [NaN NaN], ...
    'rewardPeakCircleDeg', zeros(0, 3)), nWin, 1);

heatOpts = localHeatOpts(opts);
for iWin = 1:nWin
    selectedTrialIdx = windows(iWin, 1):windows(iWin, 2);
    trials = trialList(selectedTrialIdx);
    rows.trialStart(iWin) = trials(1);
    rows.trialStop(iWin) = trials(end);
    rows.trialCenter(iWin) = mean(double([trials(1), trials(end)]));
    rows.trialStartSelected(iWin) = selectedTrialIdx(1);
    rows.trialStopSelected(iWin) = selectedTrialIdx(end);
    rows.trialCenterSelected(iWin) = mean(double([selectedTrialIdx(1), selectedTrialIdx(end)]));
    rows.nTrials(iWin) = numel(trials);
    windowInfo(iWin).trials = trials(:)';

    try
        H = gazeHeat(ex, trials, heatOpts);
    catch err
        rows.status(iWin) = "failed";
        rows.message(iWin) = string(err.message);
        continue
    end

    rewardPeakDeg = localFirstRewardPeakDeg(H);
    [xDeg, yDeg] = localTransformPoints(H.xDeg, H.yDeg, rewardPeakDeg, opts);
    [targetXDeg, targetYDeg] = localTransformPoints(H.targetXDeg, H.targetYDeg, rewardPeakDeg, opts);
    [rewardXDeg, rewardYDeg] = localTransformPoints(rewardPeakDeg(1), rewardPeakDeg(2), rewardPeakDeg, opts);
    circleDeg = localTransformRewardPeakCircle(H, rewardPeakDeg, opts);

    [xEdges, yEdges] = localWindowEdges(H, rewardPeakDeg, opts);
    [density, gazeDensity, targetDensity, xCenters, yCenters] = localWindowDensity( ...
        xDeg, yDeg, targetXDeg, targetYDeg, xEdges, yEdges, opts);
    [peakXDeg, peakYDeg, peakValue] = localPeakCentroid(density, xCenters, yCenters, opts.peakFrac);

    rows.status(iWin) = "ok";
    rows.message(iWin) = "";
    rows.nSamples(iWin) = sum(isfinite(xDeg) & isfinite(yDeg));
    rows.rewardXDeg(iWin) = rewardXDeg;
    rows.rewardYDeg(iWin) = rewardYDeg;
    rows.peakXDeg(iWin) = peakXDeg;
    rows.peakYDeg(iWin) = peakYDeg;
    rows.peakValue(iWin) = peakValue;
    rows.peakDistToRewardDeg(iWin) = hypot(peakXDeg - rewardXDeg, peakYDeg - rewardYDeg);

    distDeg = hypot(xDeg - rewardXDeg, yDeg - rewardYDeg);
    distDeg = distDeg(isfinite(distDeg));
    rows.meanDistToRewardDeg(iWin) = mean(distDeg, 'omitnan');
    rows.medianDistToRewardDeg(iWin) = median(distDeg, 'omitnan');
    [rows.rewardCloserTargetDistDeg(iWin), rows.randomTargetDistDeg(iWin)] = ...
        localTargetReferenceDistances(H, rewardPeakDeg, opts);

    radii = localCircleRadii(circleDeg);
    rows.rewardRadius1sdDeg(iWin) = localNthValue(radii, 1);
    rows.rewardRadius2sdDeg(iWin) = localNthValue(radii, 2);
    rows.rewardRadius3sdDeg(iWin) = localNthValue(radii, 3);
    rows.fracWithin1sd(iWin) = localFracWithin(distDeg, rows.rewardRadius1sdDeg(iWin));
    rows.fracWithin2sd(iWin) = localFracWithin(distDeg, rows.rewardRadius2sdDeg(iWin));
    rows.fracWithin3sd(iWin) = localFracWithin(distDeg, rows.rewardRadius3sdDeg(iWin));

    windowInfo(iWin).xCentersDeg = xCenters;
    windowInfo(iWin).yCentersDeg = yCenters;
    windowInfo(iWin).density = density;
    windowInfo(iWin).gazeDensity = gazeDensity;
    windowInfo(iWin).targetDensity = targetDensity;
    windowInfo(iWin).rewardPeakDeg = [rewardXDeg rewardYDeg];
    windowInfo(iWin).rewardPeakCircleDeg = circleDeg;
end

summary = localRowsToTable(rows);

out = struct();
out.summary = summary;
out.windows = windowInfo;
out.trials = trialList(:)';
out.opts = opts;
out.transform = struct( ...
    'alignRewardToTopLeft', logical(opts.alignRewardToTopLeft), ...
    'plotRotate45', logical(opts.plotRotate45));
end


function opts = localDefaults(opts)
defaults = struct( ...
    'windowTrials', 20, ...
    'stepTrials', 5, ...
    'includePartialWindows', true, ...
    'targetNum', 2, ...
    'peakFrac', 0.85, ...
    'peakField', 'gazeDensity', ...
    'alignRewardToTopLeft', false, ...
    'plotRotate45', false, ...
    'binSizeDeg', 0.25, ...
    'boundsDeg', [], ...
    'smoothSigmaDeg', 0.5, ...
    'normalize', 'pdf', ...
    'targetNormalize', 'logRatio', ...
    'targetPseudocount', 1e-6, ...
    'targetDensityTarget', 'all', ...
    'targetDensityRequiresGazeOnScreen', true, ...
    'useEyeTime', true, ...
    'onlyGoState', true, ...
    'insideTextureOnly', true, ...
    'timeWindowSec', [], ...
    'flipY', true, ...
    'circleBound', '3sd', ...
    'gazeHeatOpts', struct());
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(opts, names{i}) || isempty(opts.(names{i}))
        opts.(names{i}) = defaults.(names{i});
    end
end
opts.windowTrials = max(1, round(double(localFirstScalar(opts.windowTrials))));
opts.stepTrials = max(1, round(double(localFirstScalar(opts.stepTrials))));
opts.peakFrac = double(localFirstScalar(opts.peakFrac));
opts.peakFrac = max(0, min(1, opts.peakFrac));
opts.binSizeDeg = double(localFirstScalar(opts.binSizeDeg));
opts.smoothSigmaDeg = double(localFirstScalar(opts.smoothSigmaDeg));
opts.targetPseudocount = double(localFirstScalar(opts.targetPseudocount));
if ~isstruct(opts.gazeHeatOpts)
    error('gazeHeatTrajectory:BadGazeHeatOpts', 'opts.gazeHeatOpts must be a struct.');
end
end


function heatOpts = localHeatOpts(opts)
heatOpts = opts.gazeHeatOpts;
fields = {'useEyeTime','onlyGoState','insideTextureOnly','timeWindowSec', ...
    'binSizeDeg','smoothSigmaDeg','normalize','targetNormalize', ...
    'targetDensityTarget','targetDensityRequiresGazeOnScreen', ...
    'targetPseudocount','flipY','circleBound'};
for i = 1:numel(fields)
    heatOpts.(fields{i}) = opts.(fields{i});
end
heatOpts.plot = false;
heatOpts.newFigure = false;
end


function trialList = localResolveTrialList(ex, trialNo, opts)
if ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('gazeHeatTrajectory:NoTrials', 'Input ex has no trials in ex.Trials.');
end
nTrials = numel(ex.Trials);
if isempty(trialNo)
    trialList = 1:nTrials;
else
    trialList = unique(double(trialNo(:)'));
    trialList = trialList(isfinite(trialList) & trialList >= 1 & trialList <= nTrials);
end
if ~isempty(opts.targetNum)
    targetNum = localTrialTargetNumValues(ex);
    keep = false(size(trialList));
    trialTargetNum = double(targetNum(trialList(:)))';
    requested = double(opts.targetNum(:)');
    requested = requested(isfinite(requested));
    for i = 1:numel(requested)
        keep = keep | abs(trialTargetNum - requested(i)) <= 1e-9;
    end
    trialList = trialList(keep);
end
if isempty(trialList)
    error('gazeHeatTrajectory:EmptyTrials', 'No valid trials were selected.');
end
end


function values = localTrialTargetNumValues(ex)
nTrials = numel(ex.Trials);
values = NaN(nTrials, 1);
fallback = NaN;
if isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'ctl') && ...
        isfield(ex.exp.CoPs.ctl, 'target_num') && isnumeric(ex.exp.CoPs.ctl.target_num) && ...
        isscalar(ex.exp.CoPs.ctl.target_num) && isfinite(ex.exp.CoPs.ctl.target_num)
    fallback = double(ex.exp.CoPs.ctl.target_num);
end
for i = 1:nTrials
    T = ex.Trials(i);
    if isfield(T, 'target_num') && isnumeric(T.target_num) && isscalar(T.target_num) && isfinite(T.target_num)
        values(i) = double(T.target_num);
    elseif isfinite(fallback)
        values(i) = fallback;
    end
end
end


function windows = localBuildWindows(trialList, windowTrials, stepTrials, includePartialWindows)
nTrials = numel(trialList);
if ~includePartialWindows
    if nTrials < windowTrials
        windows = zeros(0, 2);
        return
    end
    starts = 1:stepTrials:(nTrials - windowTrials + 1);
    finalStart = nTrials - windowTrials + 1;
    if starts(end) ~= finalStart
        starts(end+1) = finalStart;
    end
    stops = starts + windowTrials - 1;
    windows = unique([starts(:), stops(:)], 'rows', 'stable');
    return
end
starts = 1:stepTrials:nTrials;
stops = min(nTrials, starts + windowTrials - 1);
if stops(end) < nTrials
    starts(end+1) = max(1, nTrials - windowTrials + 1); %#ok<AGROW>
    stops(end+1) = nTrials; %#ok<AGROW>
end
windows = unique([starts(:), stops(:)], 'rows', 'stable');
end


function rows = localInitRows(nWin)
rows = struct();
rows.trialStart = NaN(nWin, 1);
rows.trialStop = NaN(nWin, 1);
rows.trialCenter = NaN(nWin, 1);
rows.trialStartSelected = NaN(nWin, 1);
rows.trialStopSelected = NaN(nWin, 1);
rows.trialCenterSelected = NaN(nWin, 1);
rows.nTrials = NaN(nWin, 1);
rows.nSamples = NaN(nWin, 1);
rows.rewardXDeg = NaN(nWin, 1);
rows.rewardYDeg = NaN(nWin, 1);
rows.peakXDeg = NaN(nWin, 1);
rows.peakYDeg = NaN(nWin, 1);
rows.peakValue = NaN(nWin, 1);
rows.peakDistToRewardDeg = NaN(nWin, 1);
rows.meanDistToRewardDeg = NaN(nWin, 1);
rows.medianDistToRewardDeg = NaN(nWin, 1);
rows.rewardCloserTargetDistDeg = NaN(nWin, 1);
rows.randomTargetDistDeg = NaN(nWin, 1);
rows.rewardRadius1sdDeg = NaN(nWin, 1);
rows.rewardRadius2sdDeg = NaN(nWin, 1);
rows.rewardRadius3sdDeg = NaN(nWin, 1);
rows.fracWithin1sd = NaN(nWin, 1);
rows.fracWithin2sd = NaN(nWin, 1);
rows.fracWithin3sd = NaN(nWin, 1);
rows.status = repmat("unrun", nWin, 1);
rows.message = strings(nWin, 1);
end


function T = localRowsToTable(rows)
T = table( ...
    rows.trialStart, ...
    rows.trialStop, ...
    rows.trialCenter, ...
    rows.trialStartSelected, ...
    rows.trialStopSelected, ...
    rows.trialCenterSelected, ...
    rows.nTrials, ...
    rows.nSamples, ...
    rows.rewardXDeg, ...
    rows.rewardYDeg, ...
    rows.peakXDeg, ...
    rows.peakYDeg, ...
    rows.peakValue, ...
    rows.peakDistToRewardDeg, ...
    rows.meanDistToRewardDeg, ...
    rows.medianDistToRewardDeg, ...
    rows.rewardCloserTargetDistDeg, ...
    rows.randomTargetDistDeg, ...
    rows.rewardRadius1sdDeg, ...
    rows.rewardRadius2sdDeg, ...
    rows.rewardRadius3sdDeg, ...
    rows.fracWithin1sd, ...
    rows.fracWithin2sd, ...
    rows.fracWithin3sd, ...
    rows.status, ...
    rows.message, ...
    'VariableNames', {'trialStart','trialStop','trialCenter', ...
        'trialStartSelected','trialStopSelected','trialCenterSelected', ...
        'nTrials','nSamples', ...
        'rewardXDeg','rewardYDeg','peakXDeg','peakYDeg','peakValue', ...
        'peakDistToRewardDeg','meanDistToRewardDeg','medianDistToRewardDeg', ...
        'rewardCloserTargetDistDeg','randomTargetDistDeg', ...
        'rewardRadius1sdDeg','rewardRadius2sdDeg','rewardRadius3sdDeg', ...
        'fracWithin1sd','fracWithin2sd','fracWithin3sd','status','message'});
end


function [closerMean, randomMean] = localTargetReferenceDistances(H, rewardPeakDeg, opts)
closerMean = NaN;
randomMean = NaN;
if ~isstruct(H) || ~isfield(H, 'target1XDeg') || ~isfield(H, 'target1YDeg')
    return
end
if numel(rewardPeakDeg) < 2 || any(~isfinite(rewardPeakDeg(1:2)))
    return
end
[rewardX, rewardY] = localTransformPoints(rewardPeakDeg(1), rewardPeakDeg(2), rewardPeakDeg, opts);
[t1x, t1y] = localTransformPoints(H.target1XDeg, H.target1YDeg, rewardPeakDeg, opts);
d1 = hypot(t1x - rewardX, t1y - rewardY);
if isfield(H, 'target2XDeg') && isfield(H, 'target2YDeg')
    [t2x, t2y] = localTransformPoints(H.target2XDeg, H.target2YDeg, rewardPeakDeg, opts);
    d2 = hypot(t2x - rewardX, t2y - rewardY);
else
    d2 = NaN(size(d1));
end
if numel(d2) ~= numel(d1)
    d2 = NaN(size(d1));
end
closer = localRowNanMin([d1(:), d2(:)]);
randomExpected = localRowNanMean([d1(:), d2(:)]);
closerMean = mean(closer(isfinite(closer)), 'omitnan');
randomMean = mean(randomExpected(isfinite(randomExpected)), 'omitnan');
end


function y = localRowNanMin(M)
y = NaN(size(M, 1), 1);
for i = 1:size(M, 1)
    row = M(i, :);
    row = row(isfinite(row));
    if ~isempty(row)
        y(i) = min(row);
    end
end
end


function y = localRowNanMean(M)
y = NaN(size(M, 1), 1);
for i = 1:size(M, 1)
    row = M(i, :);
    row = row(isfinite(row));
    if ~isempty(row)
        y(i) = mean(row);
    end
end
end


function peakDeg = localFirstRewardPeakDeg(H)
peakDeg = [NaN NaN];
if isfield(H, 'rewardPeakDeg') && ~isempty(H.rewardPeakDeg)
    P = double(H.rewardPeakDeg);
    P = P(all(isfinite(P), 2), :);
    if ~isempty(P)
        peakDeg = P(1, 1:2);
    end
end
end


function [xr, yr] = localTransformPoints(x, y, peakDeg, opts)
x = double(x(:));
y = double(y(:));
angle = 0;
if logical(opts.alignRewardToTopLeft) && numel(peakDeg) >= 2 && all(isfinite(peakDeg(1:2)))
    angle = angle + 3*pi/4 - atan2(double(peakDeg(2)), double(peakDeg(1)));
end
if logical(opts.plotRotate45)
    angle = angle + pi/4;
end
c = cos(angle);
s = sin(angle);
xr = x .* c - y .* s;
yr = x .* s + y .* c;
end


function circleDeg = localTransformRewardPeakCircle(H, peakDeg, opts)
circleDeg = zeros(0, 3);
if ~isstruct(H) || ~isfield(H, 'rewardPeakCircleDeg') || isempty(H.rewardPeakCircleDeg)
    return
end
C = double(H.rewardPeakCircleDeg);
if size(C, 2) < 3
    return
end
keep = all(isfinite(C(:, 1:3)), 2) & C(:, 3) > 0;
if ~any(keep)
    return
end
[cx, cy] = localTransformPoints(C(keep, 1), C(keep, 2), peakDeg, opts);
circleDeg = [cx, cy, C(keep, 3)];
end


function [xEdges, yEdges] = localWindowEdges(H, rewardPeakDeg, opts)
if ~isempty(opts.boundsDeg)
    b = double(opts.boundsDeg(:)');
    if numel(b) ~= 4 || any(~isfinite(b))
        error('gazeHeatTrajectory:BadBounds', 'opts.boundsDeg must be [xMin xMax yMin yMax].');
    end
    xEdges = localEdges(b(1), b(2), opts.binSizeDeg);
    yEdges = localEdges(b(3), b(4), opts.binSizeDeg);
    return
end
if isfield(H, 'boundsDeg') && isstruct(H.boundsDeg)
    corners = [ ...
        H.boundsDeg.xMin H.boundsDeg.yMin; ...
        H.boundsDeg.xMin H.boundsDeg.yMax; ...
        H.boundsDeg.xMax H.boundsDeg.yMin; ...
        H.boundsDeg.xMax H.boundsDeg.yMax];
    [cx, cy] = localTransformPoints(corners(:, 1), corners(:, 2), rewardPeakDeg, opts);
    xEdges = localEdges(min(cx, [], 'omitnan'), max(cx, [], 'omitnan'), opts.binSizeDeg);
    yEdges = localEdges(min(cy, [], 'omitnan'), max(cy, [], 'omitnan'), opts.binSizeDeg);
else
    maxAbsDeg = 15;
    xEdges = -maxAbsDeg:opts.binSizeDeg:maxAbsDeg;
    yEdges = xEdges;
end
end


function [density, gazeDensity, targetDensity, xCenters, yCenters] = localWindowDensity(xDeg, yDeg, targetXDeg, targetYDeg, xEdges, yEdges, opts)
counts = localHistcounts2(xDeg, yDeg, xEdges, yEdges);
targetCounts = localHistcounts2(targetXDeg, targetYDeg, xEdges, yEdges);
smoothCounts = localSmooth2(counts, opts.smoothSigmaDeg ./ opts.binSizeDeg);
smoothTargetCounts = localSmooth2(targetCounts, opts.smoothSigmaDeg ./ opts.binSizeDeg);
gazeDensity = localNormalizeDensity(smoothCounts, opts.normalize, opts.binSizeDeg);
targetDensity = localNormalizeDensity(smoothTargetCounts, opts.normalize, opts.binSizeDeg);
switch lower(strtrim(char(string(opts.peakField))))
    case {'gaze', 'gazedensity', 'densityraw'}
        density = gazeDensity;
    case {'targetnormalized', 'density', 'logratio', 'ratio', 'difference'}
        density = localTargetNormalizedMap(gazeDensity, targetDensity, opts.targetNormalize, opts.targetPseudocount);
    otherwise
        error('gazeHeatTrajectory:BadPeakField', ...
            'opts.peakField must be ''gazeDensity'' or ''density''.');
end
xCenters = localBinCenters(xEdges);
yCenters = localBinCenters(yEdges);
end


function [peakX, peakY, peakValue] = localPeakCentroid(map, xCenters, yCenters, peakFrac)
peakX = NaN;
peakY = NaN;
peakValue = NaN;
if isempty(map) || ~any(isfinite(map(:)))
    return
end
peakValue = max(map(:), [], 'omitnan');
minValue = min(map(:), [], 'omitnan');
threshold = peakValue - (1 - peakFrac) .* (peakValue - minValue);
mask = isfinite(map) & map >= threshold;
if ~any(mask(:))
    return
end
[ix, iy] = ndgrid(1:numel(xCenters), 1:numel(yCenters));
w = map(mask);
if any(w <= 0)
    w = w - min(w) + eps;
end
x = xCenters(ix(mask));
y = yCenters(iy(mask));
sw = sum(w);
if ~isfinite(sw) || sw <= 0
    peakX = mean(x, 'omitnan');
    peakY = mean(y, 'omitnan');
else
    peakX = sum(x(:) .* w(:)) ./ sw;
    peakY = sum(y(:) .* w(:)) ./ sw;
end
end


function counts = localHistcounts2(x, y, xEdges, yEdges)
x = x(:);
y = y(:);
keep = isfinite(x) & isfinite(y);
x = x(keep);
y = y(keep);
counts = zeros(numel(xEdges) - 1, numel(yEdges) - 1);
if isempty(x)
    return
end
if exist('histcounts2', 'file') == 2 || exist('histcounts2', 'builtin') == 5
    counts = histcounts2(x, y, xEdges, yEdges);
    return
end
[~, ~, xBin] = histcounts(x, xEdges);
[~, ~, yBin] = histcounts(y, yEdges);
valid = xBin > 0 & yBin > 0;
for i = find(valid(:))'
    counts(xBin(i), yBin(i)) = counts(xBin(i), yBin(i)) + 1;
end
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


function density = localNormalizeDensity(counts, mode, binSizeDeg)
mode = lower(strtrim(char(string(mode))));
total = sum(counts(isfinite(counts)));
switch mode
    case {'count', 'counts'}
        density = counts;
    case {'probability', 'prob'}
        density = counts ./ max(total, eps);
    case {'pdf', 'density', 'probabilitydensity'}
        density = counts ./ max(total .* binSizeDeg .* binSizeDeg, eps);
    case {'peak', 'max'}
        density = counts ./ max(max(counts(:)), eps);
    otherwise
        error('gazeHeatTrajectory:BadNormalize', ...
            'opts.normalize must be count, probability, pdf, or peak.');
end
end


function map = localTargetNormalizedMap(gazeDensity, targetDensity, mode, pseudocount)
mode = lower(strtrim(char(string(mode))));
switch mode
    case 'none'
        map = gazeDensity;
    case 'ratio'
        map = (gazeDensity + pseudocount) ./ (targetDensity + pseudocount);
    case 'logratio'
        map = log2((gazeDensity + pseudocount) ./ (targetDensity + pseudocount));
    case 'difference'
        map = gazeDensity - targetDensity;
    otherwise
        error('gazeHeatTrajectory:BadTargetNormalize', ...
            'opts.targetNormalize must be none, ratio, logRatio, or difference.');
end
end


function radii = localCircleRadii(circleDeg)
radii = [];
if isempty(circleDeg) || size(circleDeg, 2) < 3
    return
end
radii = unique(circleDeg(isfinite(circleDeg(:, 3)) & circleDeg(:, 3) > 0, 3), 'stable');
radii = double(radii(:)');
end


function value = localNthValue(values, n)
value = NaN;
if numel(values) >= n
    value = values(n);
end
end


function frac = localFracWithin(distDeg, radiusDeg)
frac = NaN;
if isempty(distDeg) || ~isfinite(radiusDeg) || radiusDeg <= 0
    return
end
frac = mean(distDeg <= radiusDeg, 'omitnan');
end


function edges = localEdges(a, b, binSize)
if ~isfinite(a) || ~isfinite(b) || b <= a
    a = -15;
    b = 15;
end
edges = a:binSize:b;
if numel(edges) < 2 || edges(end) < b
    edges(end+1) = b;
end
end


function centers = localBinCenters(edges)
centers = edges(1:end-1) + diff(edges) ./ 2;
end


function value = localFirstScalar(value)
if isempty(value)
    value = NaN;
    return
end
value = double(value);
value = value(isfinite(value));
if isempty(value)
    value = NaN;
else
    value = value(1);
end
end
