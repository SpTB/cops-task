function out = collectGazeHeat(subject, groupingArg, opts)
% collectGazeHeat  Collect reward-aligned gazeHeat maps across sessions.
%
%   A = collectGazeHeat('ka')
%   A = collectGazeHeat('ka', 'block', opts)
%   plotGazeHeatAggregate(A, 'block')
%
% The aggregation pools raw gaze/target histogram counts before smoothing
% and normalization, so longer sessions contribute proportionally more
% samples. By default each trial is rotated so the reward peak is aligned to
% the top-left quadrant, then the final coordinate frame is rotated 45 deg
% counterclockwise so that top-left becomes left. If opts.plotRotate45 is
% explicitly false and opts.alignRewardToTopLeft is not specified, the native
% coordinate frame is preserved.
%
% Block aggregates are always stored in A.blockGroups, so a collection made
% with groupingArg=[] can still be plotted by block later.
%
% Common filters mirror collectCCG2:
%   opts.dateFrom, opts.dateTo, opts.waitHz, opts.targetNum,
%   opts.backgroundNoiseLvl, opts.targetVisibility, opts.imageName
% Numeric filters including opts.waitHz and opts.waitSecs accept exact
% numeric values or comparison strings such as '>10' or '<=30'.
%
% Additional filter/group:
%   opts.blockLvls = [120 240] defines trialDay block cutoffs:
%       block 1: trialDay <= 120
%       block 2: 120 < trialDay <= 240
%       block 3: trialDay > 240
%     Any increasing vector is accepted, e.g. [100 200].
%   opts.block = block number(s) to include, or [] for all blocks.

if nargin < 2
    groupingArg = [];
end
if nargin < 3 || isempty(opts)
    if isstruct(groupingArg) && ~localLooksLikeGroupingArg(groupingArg)
        opts = groupingArg;
        groupingArg = [];
    else
        opts = struct();
    end
elseif ~isstruct(opts)
    error('collectGazeHeat:BadOpts', 'opts must be a struct.');
end

opts = localDefaults(opts);
subject = localResolveSubject(subject, opts);
subjectDir = fullfile(char(opts.dataRoot), char(subject));
if ~exist(subjectDir, 'dir')
    error('collectGazeHeat:SubjectNotFound', 'Subject directory not found: %s', subjectDir);
end

dateFrom = localParseDateBound(opts.dateFrom, false);
dateTo = localParseDateBound(opts.dateTo, true);
sessionDirs = localSessionDirs(subjectDir, dateFrom, dateTo);

[candidates, fileRows, maxAbsDeg] = localFindCandidateSessions(subject, sessionDirs, opts);
if isempty(candidates)
    out = localEmptyOutput(subject, groupingArg, opts, fileRows);
    return
end

[xEdges, yEdges] = localAggregateEdges(maxAbsDeg, opts);
[groupLabels, groupInfo] = localGroupLabels(groupingArg, opts);
groups = cell(numel(groupLabels), 1);
for g = 1:numel(groupLabels)
    groups{g} = localEmptyGroup(groupLabels(g), xEdges, yEdges);
end
blockLabels = localBlockLabels(opts.blockLvls);
blockGroups = cell(numel(blockLabels), 1);
for g = 1:numel(blockLabels)
    blockGroups{g} = localEmptyGroup(blockLabels(g), xEdges, yEdges);
end

heatOpts = opts.gazeHeatOpts;
heatOpts.plot = false;
heatOpts.newFigure = false;
if ~isfield(heatOpts, 'flipY') || isempty(heatOpts.flipY)
    heatOpts.flipY = true;
end

for i = 1:numel(candidates)
    C = candidates(i);
    try
        S = load(C.filePath, 'ex');
    catch
        continue
    end
    if ~isfield(S, 'ex') || ~isfield(S.ex, 'Trials')
        continue
    end
    ex = S.ex;
    for j = 1:numel(C.trialList)
        trialIdx = C.trialList(j);
        if trialIdx < 1 || trialIdx > numel(ex.Trials)
            continue
        end
        gIdx = localGroupIndexForTrial(groupInfo, C.block(j));
        if ~isfinite(gIdx) || gIdx < 1 || gIdx > numel(groups)
            continue
        end
        try
            H = gazeHeat(ex, trialIdx, heatOpts);
        catch
            continue
        end
        peakDeg = localFirstRewardPeakDeg(H);
        [gx, gy] = localTransformPoints(H.xDeg, H.yDeg, peakDeg, opts);
        [tx, ty] = localTransformPoints(H.targetXDeg, H.targetYDeg, peakDeg, opts);
        [px, py] = localTransformPoints(peakDeg(1), peakDeg(2), peakDeg, opts);
        circleDeg = localTransformRewardPeakCircle(H, peakDeg, opts);

        gazeCounts = localHistcounts2(gx, gy, xEdges, yEdges);
        targetCounts = localHistcounts2(tx, ty, xEdges, yEdges);
        groups{gIdx} = localAddTrialToGroup(groups{gIdx}, gazeCounts, targetCounts, ...
            gx, gy, tx, ty, C.trialDay(j), C.block(j), C.fileName, px, py, circleDeg);
        blockIdx = C.block(j);
        if isfinite(blockIdx) && blockIdx >= 1 && blockIdx <= numel(blockGroups)
            blockGroups{blockIdx} = localAddTrialToGroup(blockGroups{blockIdx}, gazeCounts, targetCounts, ...
                gx, gy, tx, ty, C.trialDay(j), C.block(j), C.fileName, px, py, circleDeg);
        end
    end
end

for g = 1:numel(groups)
    groups{g} = localFinalizeGroup(groups{g}, opts);
end
for g = 1:numel(blockGroups)
    blockGroups{g} = localFinalizeGroup(blockGroups{g}, opts);
end

out = struct();
out.subject = string(subject);
out.groupingArg = groupingArg;
out.groupLabels = groupLabels(:);
out.groups = groups;
out.blockLabels = blockLabels(:);
out.blockGroups = blockGroups;
out.xEdgesDeg = xEdges;
out.yEdgesDeg = yEdges;
out.xCentersDeg = localBinCenters(xEdges);
out.yCentersDeg = localBinCenters(yEdges);
out.fileTable = localRowsToTable(fileRows);
out.options = opts;
out.colormap = localColormapByName(opts.colorScheme, opts.nColors);
out.colorbarLabel = localColorbarLabel(opts.targetNormalize);
out.transform = struct( ...
    'alignRewardToTopLeft', logical(opts.alignRewardToTopLeft), ...
    'plotRotate45', logical(opts.plotRotate45), ...
    'description', "reward-aligned; optional +45deg plot rotation");
end


function group = localAddTrialToGroup(group, gazeCounts, targetCounts, gx, gy, tx, ty, trialDay, block, fileName, px, py, circleDeg)
group.counts = group.counts + gazeCounts;
group.targetCounts = group.targetCounts + targetCounts;
group.nTrials = group.nTrials + 1;
group.nGazeSamples = group.nGazeSamples + sum(isfinite(gx) & isfinite(gy));
group.nTargetSamples = group.nTargetSamples + sum(isfinite(tx) & isfinite(ty));
group.trialDay = [group.trialDay; trialDay];
group.block = [group.block; block];
group.fileName = [group.fileName; string(fileName)];
if isfinite(px) && isfinite(py)
    group.rewardPeakDeg = [group.rewardPeakDeg; [px, py]];
end
if nargin >= 13 && ~isempty(circleDeg)
    keep = all(isfinite(circleDeg), 2) & circleDeg(:, 3) > 0;
    if any(keep)
        group.rewardPeakCircleDeg = [group.rewardPeakCircleDeg; circleDeg(keep, :)];
    end
end
end


function tf = localLooksLikeGroupingArg(value)
tf = ischar(value) || isstring(value) || isnumeric(value) || iscell(value);
end


function opts = localDefaults(opts)
hasBlockLvls = isfield(opts, 'blockLvls') && ~isempty(opts.blockLvls);
hasLegacyBlockEdges = isfield(opts, 'blockEdges') && ~isempty(opts.blockEdges);
hasAlignRewardToTopLeft = isfield(opts, 'alignRewardToTopLeft') && ~isempty(opts.alignRewardToTopLeft);
hasPlotRotate45 = isfield(opts, 'plotRotate45') && ~isempty(opts.plotRotate45);
defaultDataRoot = "/media/vpixx/DATA/CoPs";
if ~exist(char(defaultDataRoot), 'dir')
    defaultDataRoot = "Y:\data\CoPs";
end
defaults = struct( ...
    'dataRoot', defaultDataRoot, ...
    'dateFrom', [], ...
    'dateTo', [], ...
    'targetNum', [], ...
    'backgroundNoiseLvl', [], ...
    'targetVisibility', [], ...
    'imageName', [], ...
    'block', [], ...
    'waitSecs', [], ...
    'waitHz', [], ...
    'waitTolSec', 1e-4, ...
    'waitHzTol', 1e-4, ...
    'excludePursuit', true, ...
    'excludePre', true, ...
    'blockLvls', [120 240], ...
    'blockEdges', [], ...
    'binSizeDeg', 0.25, ...
    'boundsDeg', [], ...
    'smoothSigmaDeg', 0.5, ...
    'normalize', 'pdf', ...
    'targetNormalize', 'logRatio', ...
    'targetPseudocount', 1e-6, ...
    'targetDensityTarget', 'all', ...
    'alignRewardToTopLeft', true, ...
    'plotRotate45', true, ...
    'colorScheme', 'balance', ...
    'nColors', 256, ...
    'gazeHeatOpts', struct(), ...
    'verbose', true);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(opts, names{i}) || isempty(opts.(names{i}))
        opts.(names{i}) = defaults.(names{i});
    end
end
if ~hasAlignRewardToTopLeft && hasPlotRotate45 && ~logical(opts.plotRotate45)
    opts.alignRewardToTopLeft = false;
end
opts.binSizeDeg = double(localFirstScalar(opts.binSizeDeg));
opts.smoothSigmaDeg = double(localFirstScalar(opts.smoothSigmaDeg));
opts.targetPseudocount = double(localFirstScalar(opts.targetPseudocount));
opts.nColors = max(2, round(double(localFirstScalar(opts.nColors))));
if ~hasBlockLvls && hasLegacyBlockEdges
    opts.blockLvls = opts.blockEdges;
end
opts.blockLvls = double(opts.blockLvls(:)');
if isempty(opts.blockLvls) || any(~isfinite(opts.blockLvls)) || any(diff(opts.blockLvls) <= 0)
    error('collectGazeHeat:BadBlockLvls', ...
        'opts.blockLvls must be an increasing numeric vector, default [120 240].');
end
opts.blockEdges = opts.blockLvls;
if ~isstruct(opts.gazeHeatOpts)
    error('collectGazeHeat:BadGazeHeatOpts', 'opts.gazeHeatOpts must be a struct.');
end
opts.gazeHeatOpts.binSizeDeg = opts.binSizeDeg;
opts.gazeHeatOpts.smoothSigmaDeg = opts.smoothSigmaDeg;
opts.gazeHeatOpts.normalize = opts.normalize;
opts.gazeHeatOpts.targetNormalize = opts.targetNormalize;
opts.gazeHeatOpts.targetPseudocount = opts.targetPseudocount;
opts.gazeHeatOpts.targetDensityTarget = opts.targetDensityTarget;
end


function [candidates, rows, maxAbsDeg] = localFindCandidateSessions(subject, sessionDirs, opts)
candidates = struct('filePath', {}, 'fileName', {}, 'sessionDate', {}, ...
    'trialList', {}, 'trialDay', {}, 'block', {}, 'waitSecs', {}, 'waitHz', {});
rows = localEmptyRows();
maxAbsDeg = 0;
lastDate = "";
dayTrialOffset = 0;

for iDir = 1:numel(sessionDirs)
    sessionDir = sessionDirs(iDir);
    dateKey = string(sessionDir.name);
    if ~strcmp(dateKey, lastDate)
        dayTrialOffset = 0;
        lastDate = dateKey;
    end
    files = localListSessionExFiles(fullfile(sessionDir.folder, sessionDir.name));
    for iFile = 1:numel(files)
        filePath = files{iFile};
        row = localInitRow(subject, sessionDir.name, sessionDir.date, filePath);
        try
            S = load(filePath, 'ex');
        catch err
            row.status = "load_failed";
            row.message = string(err.message);
            rows = localAppendRow(rows, row);
            continue
        end
        if ~isfield(S, 'ex') || ~isstruct(S.ex) || ~isfield(S.ex, 'Trials') || isempty(S.ex.Trials)
            row.status = "missing_ex";
            row.message = "File does not contain ex.Trials";
            rows = localAppendRow(rows, row);
            continue
        end
        ex = S.ex;
        nTrials = numel(ex.Trials);
        trialDay = dayTrialOffset + (1:nTrials);
        block = localTrialDayBlock(trialDay, opts.blockLvls);
        dayTrialOffset = dayTrialOffset + nTrials;

        [waitSecs, waitHz] = localResolveWait(ex);
        row.waitSecs = waitSecs;
        row.waitHz = waitHz;
        [ok, msg] = localSessionMatches(waitSecs, waitHz, opts);
        if ~ok
            row.status = "session_filtered";
            row.message = msg;
            rows = localAppendRow(rows, row);
            continue
        end

        keep = localSubsetTrials(ex, trialDay, block, opts);
        row.nSelectedTrials = nnz(keep);
        if row.nSelectedTrials == 0
            row.status = "too_few_selected_trials";
            row.message = "nSelectedTrials=0";
            rows = localAppendRow(rows, row);
            continue
        end
        trialList = find(keep);
        maxAbsDeg = max(maxAbsDeg, localMaxTransformedBoundsDeg(ex, opts));
        row.status = "included";
        rows = localAppendRow(rows, row);
        candidates(end+1) = struct( ... %#ok<AGROW>
            'filePath', string(filePath), ...
            'fileName', string(row.fileName), ...
            'sessionDate', sessionDir.date, ...
            'trialList', trialList(:)', ...
            'trialDay', trialDay(trialList(:))', ...
            'block', block(trialList(:))', ...
            'waitSecs', waitSecs, ...
            'waitHz', waitHz);
        if opts.verbose
            fprintf('Included %s: %d gaze-heat trials\n', row.fileName, row.nSelectedTrials);
        end
    end
end
end


function keep = localSubsetTrials(ex, trialDay, block, opts)
nTrials = numel(ex.Trials);
keep = true(1, nTrials);
if logical(opts.excludePursuit)
    keep = keep & ~localPursuitMask(ex);
end
if logical(opts.excludePre)
    keep = keep & ~localPreMask(ex);
end
if ~isempty(opts.targetNum)
    keep = keep & localNumericMember(localTrialNumericValues(ex, 'target_num'), opts.targetNum)';
end
if ~isempty(opts.backgroundNoiseLvl)
    keep = keep & localNumericMember(localTrialNumericValues(ex, 'background_noise_lvl'), opts.backgroundNoiseLvl)';
end
if ~isempty(opts.targetVisibility)
    keep = keep & localNumericMember(localTrialNumericValues(ex, 'target_visibility'), opts.targetVisibility)';
end
if ~isempty(opts.imageName)
    keep = keep & localStringMember(localTrialStringValues(ex, 'imageName'), opts.imageName)';
end
if ~isempty(opts.block)
    keep = keep & localBlockMember(block, opts.block);
end
keep = keep & isfinite(trialDay) & isfinite(block);
end


function [groupLabels, groupInfo] = localGroupLabels(groupingArg, opts)
if isempty(groupingArg) || localIsAllCode(groupingArg)
    groupLabels = "all";
    groupInfo = struct('mode', 'all');
    return
end
code = lower(strtrim(string(groupingArg)));
switch code
    case "block"
        groupLabels = localBlockLabels(opts.blockLvls);
        groupInfo = struct('mode', 'block');
    otherwise
        error('collectGazeHeat:UnknownGrouping', ...
            'Supported groupingArg values are [], ''all'', or ''block''.');
end
end


function idx = localGroupIndexForTrial(groupInfo, block)
switch groupInfo.mode
    case 'all'
        idx = 1;
    case 'block'
        idx = block;
    otherwise
        idx = NaN;
end
end


function group = localEmptyGroup(label, xEdges, yEdges)
nX = numel(xEdges) - 1;
nY = numel(yEdges) - 1;
group = struct();
group.groupLabel = label;
group.counts = zeros(nX, nY);
group.targetCounts = zeros(nX, nY);
group.smoothCounts = zeros(nX, nY);
group.smoothTargetCounts = zeros(nX, nY);
group.gazeDensity = zeros(nX, nY);
group.targetDensity = zeros(nX, nY);
group.density = NaN(nX, nY);
group.nTrials = 0;
group.nGazeSamples = 0;
group.nTargetSamples = 0;
group.trialDay = [];
group.block = [];
group.fileName = strings(0, 1);
group.rewardPeakDeg = zeros(0, 2);
group.rewardPeakPlotDeg = [NaN NaN];
group.rewardPeakCircleDeg = zeros(0, 3);
end


function group = localFinalizeGroup(group, opts)
if group.nGazeSamples == 0
    group.smoothCounts = zeros(size(group.counts));
    group.smoothTargetCounts = zeros(size(group.targetCounts));
    group.gazeDensity = zeros(size(group.counts));
    group.targetDensity = zeros(size(group.targetCounts));
    group.density = NaN(size(group.counts));
    group.colorbarLabel = localColorbarLabel(opts.targetNormalize);
    return
end
sigmaBins = opts.smoothSigmaDeg ./ opts.binSizeDeg;
group.smoothCounts = localSmooth2(group.counts, sigmaBins);
group.smoothTargetCounts = localSmooth2(group.targetCounts, sigmaBins);
group.gazeDensity = localNormalizeDensity(group.smoothCounts, opts.normalize, opts.binSizeDeg);
group.targetDensity = localNormalizeDensity(group.smoothTargetCounts, opts.normalize, opts.binSizeDeg);
[group.density, group.colorbarLabel] = localTargetNormalizedMap( ...
    group.gazeDensity, group.targetDensity, opts.targetNormalize, opts.targetPseudocount);
if ~isempty(group.rewardPeakDeg)
    group.rewardPeakPlotDeg = median(group.rewardPeakDeg, 1, 'omitnan');
end
if ~isempty(group.rewardPeakCircleDeg)
    group.rewardPeakCircleDeg = localUniqueRowsTol(group.rewardPeakCircleDeg, 1e-6);
end
group.fileName = unique(group.fileName, 'stable');
end


function [xEdges, yEdges] = localAggregateEdges(maxAbsDeg, opts)
if ~isempty(opts.boundsDeg)
    b = double(opts.boundsDeg(:)');
    if numel(b) ~= 4 || any(~isfinite(b))
        error('collectGazeHeat:BadBounds', 'opts.boundsDeg must be [xMin xMax yMin yMax].');
    end
    xEdges = localEdges(b(1), b(2), opts.binSizeDeg);
    yEdges = localEdges(b(3), b(4), opts.binSizeDeg);
    return
end
if ~isfinite(maxAbsDeg) || maxAbsDeg <= 0
    maxAbsDeg = 15;
end
maxAbsDeg = ceil(maxAbsDeg ./ opts.binSizeDeg) .* opts.binSizeDeg;
xEdges = -maxAbsDeg:opts.binSizeDeg:maxAbsDeg;
yEdges = xEdges;
end


function maxAbsDeg = localMaxTransformedBoundsDeg(ex, opts)
[x0, y0] = localReferenceCenterPx(ex);
[plotBoundsPx, ~] = localPlotBoundsPx(ex, opts);
boundsDeg = localBoundsDeg(plotBoundsPx, x0, y0, ex.setup, true);
corners = [ ...
    boundsDeg.xMin boundsDeg.yMin; ...
    boundsDeg.xMin boundsDeg.yMax; ...
    boundsDeg.xMax boundsDeg.yMin; ...
    boundsDeg.xMax boundsDeg.yMax];
angles = [0, pi/2, pi, 3*pi/2];
if logical(opts.plotRotate45)
    angles = angles + pi/4;
end
maxAbsDeg = 0;
for i = 1:numel(angles)
    xy = localRotateXY(corners(:,1), corners(:,2), angles(i));
    maxAbsDeg = max(maxAbsDeg, max(abs(xy(:))));
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
    targetAngle = 3*pi/4;
    peakAngle = atan2(double(peakDeg(2)), double(peakDeg(1)));
    angle = angle + targetAngle - peakAngle;
end
if logical(opts.plotRotate45)
    angle = angle + pi/4;
end
xy = localRotateXY(x, y, angle);
xr = xy(:, 1);
yr = xy(:, 2);
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


function xy = localRotateXY(x, y, angle)
x = double(x(:));
y = double(y(:));
c = cos(angle);
s = sin(angle);
xy = [x .* c - y .* s, x .* s + y .* c];
end


function block = localTrialDayBlock(trialDay, edges)
trialDay = double(trialDay);
block = NaN(size(trialDay));
finiteTrial = isfinite(trialDay);
block(finiteTrial) = 1;
for i = 1:numel(edges)
    block(finiteTrial & trialDay > edges(i)) = i + 1;
end
end


function labels = localBlockLabels(blockLvls)
blockLvls = double(blockLvls(:)');
nBlocks = numel(blockLvls) + 1;
labels = strings(nBlocks, 1);
for i = 1:nBlocks
    if i == 1
        labels(i) = "block 1: <=" + localNumberText(blockLvls(1));
    elseif i <= numel(blockLvls)
        labels(i) = "block " + string(i) + ": >" + localNumberText(blockLvls(i - 1)) + ...
            " & <=" + localNumberText(blockLvls(i));
    else
        labels(i) = "block " + string(i) + ": >" + localNumberText(blockLvls(end));
    end
end
end


function txt = localNumberText(value)
txt = string(sprintf('%.15g', double(value)));
end


function tf = localBlockMember(block, requested)
maxBlock = max(block(isfinite(block)), [], 'omitnan');
requested = localNormalizeBlockRequest(requested, maxBlock);
tf = ismember(double(block), requested);
end


function requested = localNormalizeBlockRequest(requested, maxBlock)
if nargin < 2 || isempty(maxBlock) || ~isfinite(maxBlock)
    maxBlock = Inf;
end
if isnumeric(requested) || islogical(requested)
    requested = double(requested(:)');
elseif ischar(requested) || isstring(requested)
    txt = lower(strtrim(string(requested(:))));
    requested = NaN(size(txt));
    for i = 1:numel(txt)
        tok = regexp(char(txt(i)), '(?:block)?\s*(\d+)', 'tokens', 'once');
        if ~isempty(tok)
            requested(i) = str2double(tok{1});
        end
    end
elseif iscell(requested)
    vals = [];
    for i = 1:numel(requested)
        vals = [vals, localNormalizeBlockRequest(requested{i}, maxBlock)]; %#ok<AGROW>
    end
    requested = vals;
else
    requested = [];
end
requested = unique(requested(isfinite(requested) & requested >= 1 & requested <= maxBlock));
end


function mask = localPursuitMask(ex)
nTrials = numel(ex.Trials);
mask = false(1, nTrials);
for i = 1:nTrials
    T = ex.Trials(i);
    if isfield(T, 'isPursuitTrial') && logical(T.isPursuitTrial)
        mask(i) = true;
    elseif isfield(T, 'runPhase') && any(strcmpi(string(T.runPhase), ["pursuit", "pur"]))
        mask(i) = true;
    end
end
end


function mask = localPreMask(ex)
nTrials = numel(ex.Trials);
mask = false(1, nTrials);
for i = 1:nTrials
    T = ex.Trials(i);
    if isfield(T, 'isPreTrial') && logical(T.isPreTrial)
        mask(i) = true;
    elseif isfield(T, 'runPhase') && strcmpi(string(T.runPhase), "pre")
        mask(i) = true;
    end
end
end


function values = localTrialNumericValues(ex, fieldName)
nTrials = numel(ex.Trials);
values = NaN(nTrials, 1);
fallback = localTrialFieldFallback(ex, fieldName);
for i = 1:nTrials
    T = ex.Trials(i);
    if isfield(T, fieldName) && isnumeric(T.(fieldName)) && isscalar(T.(fieldName))
        values(i) = double(T.(fieldName));
    elseif isfinite(fallback)
        values(i) = fallback;
    end
end
end


function fallback = localTrialFieldFallback(ex, fieldName)
fallback = NaN;
switch fieldName
    case 'target_num'
        fallback = localGetNestedNumeric(ex, {'exp', 'CoPs', 'ctl', 'target_num'});
    case 'background_noise_lvl'
        fallback = localGetNestedNumeric(ex, {'exp', 'CoPs', 'graph', 'background_noise_lvl'});
    case 'target_visibility'
        fallback = localGetNestedNumeric(ex, {'exp', 'CoPs', 'graph', 'target_visibility'});
end
end


function values = localTrialStringValues(ex, fieldName)
nTrials = numel(ex.Trials);
values = strings(nTrials, 1);
for i = 1:nTrials
    T = ex.Trials(i);
    if isfield(T, fieldName) && (ischar(T.(fieldName)) || isstring(T.(fieldName)))
        values(i) = string(T.(fieldName));
    elseif strcmp(fieldName, 'imageName')
        values(i) = localTrialImageName(ex, i);
    end
end
end


function imageName = localTrialImageName(ex, trialNo)
imageName = "";
if isfield(ex, 'stim') && isstruct(ex.stim) && isfield(ex.stim, 'seq') && numel(ex.stim.seq) >= trialNo
    imageName = localBasenameString(string(ex.stim.seq{trialNo}));
end
end


function name = localBasenameString(pathText)
name = "";
if ~(ischar(pathText) || isstring(pathText)) || ismissing(string(pathText)) || strlength(string(pathText)) == 0
    return
end
[~, stem, ext] = fileparts(char(string(pathText)));
candidate = string([stem ext]);
if strlength(strtrim(candidate)) > 0
    name = candidate;
end
end


function mask = localNumericMember(values, requested)
mask = false(size(values));
if isempty(requested)
    return
end
if isnumeric(requested) || islogical(requested)
    requested = double(requested(:));
    requested = requested(isfinite(requested));
    for i = 1:numel(requested)
        mask = mask | abs(values - requested(i)) <= 1e-9;
    end
    return
end
if iscell(requested)
    for i = 1:numel(requested)
        mask = mask | localNumericMember(values, requested{i});
    end
    return
end
if ischar(requested) || isstring(requested)
    requested = localTextTokens(requested);
    for i = 1:numel(requested)
        mask = mask | localNumericFilterMask(values, requested(i));
    end
    return
end
error('collectGazeHeat:BadNumericFilter', ...
    'Numeric filters must be numeric values or comparison strings such as ''>0''.');
end


function tokens = localTextTokens(value)
if ischar(value)
    tokens = strtrim(string(value));
else
    tokens = strtrim(string(value(:)));
end
tokens = tokens(strlength(tokens) > 0 & ~ismissing(tokens));
end


function mask = localNumericFilterMask(values, expr)
expr = strtrim(string(expr));
tok = regexp(char(expr), ...
    '^\s*(>=|<=|==|~=|!=|>|<|=)?\s*([-+]?(?:(?:\d+\.?\d*)|(?:\.\d+))(?:[eE][-+]?\d+)?)\s*$', ...
    'tokens', 'once');
if isempty(tok)
    error('collectGazeHeat:BadNumericFilter', ...
        'Could not parse numeric filter ''%s''. Use forms like ''>0'', ''<=5'', or ''==1''.', expr);
end
op = tok{1};
threshold = str2double(tok{2});
if isempty(op)
    op = '==';
elseif strcmp(op, '=')
    op = '==';
elseif strcmp(op, '!=')
    op = '~=';
end
switch op
    case '>'
        mask = values > threshold;
    case '>='
        mask = values >= threshold;
    case '<'
        mask = values < threshold;
    case '<='
        mask = values <= threshold;
    case '=='
        mask = abs(values - threshold) <= 1e-9;
    case '~='
        mask = isfinite(values) & abs(values - threshold) > 1e-9;
    otherwise
        error('collectGazeHeat:BadNumericFilter', ...
            'Unsupported numeric filter operator ''%s''.', op);
end
end


function mask = localStringMember(values, requested)
requested = string(requested);
requested = requested(:);
requested = requested(strlength(strtrim(requested)) > 0);
mask = false(size(values));
for i = 1:numel(requested)
    mask = mask | strcmpi(strtrim(values), strtrim(requested(i)));
end
end


function [waitSecs, waitHz] = localResolveWait(ex)
waitSecs = NaN;
waitHz = NaN;
if exist('resolveCoPsWaitSecs', 'file') == 2
    try
        [waitSecs, waitHz] = resolveCoPsWaitSecs(ex, NaN);
        return
    catch
    end
end
waitHz = localGetNestedNumeric(ex, {'exp', 'CoPs', 'timing', 'waitHz'});
if isfinite(waitHz) && waitHz > 0
    waitSecs = 1 ./ waitHz;
    return
end
waitSecs = localGetNestedNumeric(ex, {'exp', 'CoPs', 'timing', 'wait_secs'});
if ~isfinite(waitSecs)
    waitSecs = localGetNestedNumeric(ex, {'timing', 'wait_secs'});
end
if isfinite(waitSecs) && waitSecs > 0
    waitHz = 1 ./ waitSecs;
end
end


function [ok, msg] = localSessionMatches(waitSecs, waitHz, opts)
ok = true;
msg = "";
if ~isempty(opts.waitSecs)
    if ~localScalarMatchesNumericRequest(waitSecs, opts.waitSecs, opts.waitTolSec)
        ok = false;
        msg = sprintf('waitSecs %.6g did not match requested values', waitSecs);
        return
    end
end
if ~isempty(opts.waitHz)
    if ~localScalarMatchesNumericRequest(waitHz, opts.waitHz, opts.waitHzTol)
        ok = false;
        msg = sprintf('waitHz %.6g did not match requested values', waitHz);
        return
    end
end
end


function tf = localScalarMatchesNumericRequest(value, requested, tol)
tf = false;
if ~isfinite(value)
    return
end
if isempty(requested)
    tf = true;
    return
end
if isnumeric(requested) || islogical(requested)
    requested = double(requested(:));
    requested = requested(isfinite(requested));
    tf = any(abs(double(value) - requested) <= double(tol));
    return
end
if iscell(requested)
    for i = 1:numel(requested)
        tf = tf || localScalarMatchesNumericRequest(value, requested{i}, tol);
    end
    return
end
if ischar(requested) || isstring(requested)
    tokens = localTextTokens(requested);
    for i = 1:numel(tokens)
        tf = tf || localNumericFilterMask(double(value), tokens(i));
    end
    return
end
error('collectGazeHeat:BadNumericFilter', ...
    'waitSecs/waitHz filters must be numeric values or comparison strings such as ''>10''.');
end


function subject = localResolveSubject(subject, opts)
if ~(ischar(subject) || (isstring(subject) && isscalar(subject)))
    error('collectGazeHeat:BadSubject', 'subject must be a text scalar.');
end
subject = lower(strtrim(string(subject)));
switch subject
    case {"ka", "kaki"}
        subject = "kaki";
    case {"ly", "lychee"}
        subject = "lychee";
end
candidate = fullfile(char(opts.dataRoot), char(subject));
if ~exist(candidate, 'dir')
    rootInfo = dir(char(opts.dataRoot));
    rootInfo = rootInfo([rootInfo.isdir]);
    names = string({rootInfo.name});
    match = names(startsWith(lower(names), lower(subject)) & ~ismember(names, [".", ".."]));
    if numel(match) == 1
        subject = match(1);
    end
end
end


function d = localParseDateBound(value, useEndOfDay)
if isempty(value)
    d = [];
    return
end
if isdatetime(value)
    d = datetime(year(value), month(value), day(value));
else
    d = localParseDateString(char(string(value)));
end
if useEndOfDay
    d = d + days(1) - seconds(eps);
end
end


function d = localParseDateString(s)
s = strtrim(char(s));
try
    d = datetime(s, 'InputFormat', 'yyyy.MM.dd');
    return
catch
end
tok = regexp(lower(s), '^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s*([0-9]{1,2})$', 'tokens', 'once');
if isempty(tok)
    error('collectGazeHeat:BadDate', 'Date must be ''YYYY.MM.DD'', datetime, or shorthand like ''Jun10''.');
end
months = struct('jan',1,'feb',2,'mar',3,'apr',4,'may',5,'jun',6, ...
    'jul',7,'aug',8,'sep',9,'oct',10,'nov',11,'dec',12);
d = datetime(year(datetime('today')), months.(tok{1}), str2double(tok{2}));
end


function sessionDirs = localSessionDirs(subjectDir, dateFrom, dateTo)
raw = dir(subjectDir);
raw = raw([raw.isdir]);
raw = raw(~ismember({raw.name}, {'.', '..'}));
sessionDirs = struct('name', {}, 'folder', {}, 'date', {});
for i = 1:numel(raw)
    [d, ok] = localParseSessionFolderDate(raw(i).name);
    if ~ok
        continue
    end
    if ~isempty(dateFrom) && d < dateFrom
        continue
    end
    if ~isempty(dateTo) && d > dateTo
        continue
    end
    sessionDirs(end+1) = struct('name', raw(i).name, 'folder', raw(i).folder, 'date', d); %#ok<AGROW>
end
if ~isempty(sessionDirs)
    [~, order] = sort([sessionDirs.date]);
    sessionDirs = sessionDirs(order);
end
end


function [d, ok] = localParseSessionFolderDate(folderName)
ok = false;
d = NaT;
token = regexp(folderName, '^\d{4}\.\d{2}\.\d{2}', 'match', 'once');
if isempty(token)
    return
end
d = datetime(token, 'InputFormat', 'yyyy.MM.dd');
ok = true;
end


function files = localListSessionExFiles(dateDir)
files = {};
rootFiles = dir(fullfile(dateDir, '*.mat'));
rootFiles = rootFiles(~startsWith({rootFiles.name}, 'dailyLog'));
rootFiles = rootFiles(~contains({rootFiles.name}, 'EyeCal'));
for i = 1:numel(rootFiles)
    files{end+1, 1} = fullfile(rootFiles(i).folder, rootFiles(i).name); %#ok<AGROW>
end
experimentalDir = fullfile(dateDir, 'experimental');
if exist(experimentalDir, 'dir')
    expFiles = dir(fullfile(experimentalDir, '*.mat'));
    expFiles = expFiles(~startsWith({expFiles.name}, 'dailyLog'));
    expFiles = expFiles(~contains({expFiles.name}, 'EyeCal'));
    for i = 1:numel(expFiles)
        files{end+1, 1} = fullfile(expFiles(i).folder, expFiles(i).name); %#ok<AGROW>
    end
end
files = unique(files, 'stable');
files = localSortFilesByTimestamp(files);
end


function files = localSortFilesByTimestamp(files)
if isempty(files)
    return
end
sortKey = NaN(numel(files), 1);
names = strings(numel(files), 1);
for i = 1:numel(files)
    info = dir(files{i});
    if ~isempty(info)
        names(i) = string(info.name);
        sortKey(i) = localSessionTimeSortKey(info.name);
        if ~isfinite(sortKey(i))
            sortKey(i) = info.datenum;
        end
    else
        names(i) = string(files{i});
        sortKey(i) = i;
    end
end
T = table(sortKey, names, files(:), 'VariableNames', {'sortKey','name','file'});
T = sortrows(T, {'sortKey','name'});
files = T.file;
end


function key = localSessionTimeSortKey(fileName)
key = NaN;
tok = regexp(char(fileName), '^[A-Za-z]+_(\d{1,2})\.(\d{2})', 'tokens', 'once');
if isempty(tok)
    return
end
hh = str2double(tok{1});
mm = str2double(tok{2});
if isfinite(hh) && isfinite(mm)
    key = hh .* 60 + mm;
end
end


function rows = localEmptyRows()
rows = struct('subject', {}, 'sessionFolder', {}, 'sessionDate', {}, ...
    'fileName', {}, 'filePath', {}, 'status', {}, 'message', {}, ...
    'waitSecs', {}, 'waitHz', {}, 'nSelectedTrials', {});
end


function row = localInitRow(subject, sessionFolder, sessionDate, filePath)
[~, name, ext] = fileparts(filePath);
row = struct( ...
    'subject', string(subject), ...
    'sessionFolder', string(sessionFolder), ...
    'sessionDate', sessionDate, ...
    'fileName', string([name ext]), ...
    'filePath', string(filePath), ...
    'status', "unchecked", ...
    'message', "", ...
    'waitSecs', NaN, ...
    'waitHz', NaN, ...
    'nSelectedTrials', NaN);
end


function rows = localAppendRow(rows, row)
if isempty(rows)
    rows = row;
else
    rows(end+1) = row;
end
end


function T = localRowsToTable(rows)
if isempty(rows)
    T = table();
else
    T = struct2table(rows, 'AsArray', true);
end
end


function out = localEmptyOutput(subject, groupingArg, opts, fileRows)
out = struct();
out.subject = string(subject);
out.groupingArg = groupingArg;
out.groupLabels = strings(0, 1);
out.groups = {};
out.blockLabels = localBlockLabels(opts.blockLvls);
out.blockGroups = {};
out.xEdgesDeg = [];
out.yEdgesDeg = [];
out.xCentersDeg = [];
out.yCentersDeg = [];
out.fileTable = localRowsToTable(fileRows);
out.options = opts;
out.colormap = localColormapByName(opts.colorScheme, opts.nColors);
out.colorbarLabel = localColorbarLabel(opts.targetNormalize);
end


function value = localGetNestedNumeric(s, fields)
value = NaN;
for i = 1:numel(fields)
    if ~isstruct(s) || ~isfield(s, fields{i})
        return
    end
    s = s.(fields{i});
end
if (isnumeric(s) || islogical(s)) && isscalar(s) && isfinite(double(s))
    value = double(s);
end
end


function [plotBounds, textureBounds] = localPlotBoundsPx(ex, opts)
screenRect = double(ex.setup.screenRect);
plotBounds = struct('xMin', screenRect(1), 'xMax', screenRect(3), ...
    'yMin', screenRect(2), 'yMax', screenRect(4));
textureBounds = plotBounds;
if isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'graph')
    graph = ex.exp.CoPs.graph;
    if isfield(graph, 'texture_dims') && isfield(graph, 'size_mult') && ...
            ~isempty(graph.texture_dims) && ~isempty(graph.size_mult)
        texDimPx = double(graph.texture_dims(1)) * double(graph.size_mult);
        xShift = (screenRect(3) - texDimPx) / 2;
        yShift = (screenRect(4) - texDimPx) / 2;
        textureBounds = struct('xMin', xShift, 'xMax', xShift + texDimPx, ...
            'yMin', yShift, 'yMax', yShift + texDimPx);
    end
end
if localGetLogicalField(opts, 'insideTextureOnly', true)
    plotBounds = textureBounds;
end
end


function tf = localGetLogicalField(s, name, defaultValue)
tf = defaultValue;
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    tf = logical(s.(name));
end
if isstruct(s) && isfield(s, 'gazeHeatOpts') && isstruct(s.gazeHeatOpts) && ...
        isfield(s.gazeHeatOpts, name) && ~isempty(s.gazeHeatOpts.(name))
    tf = logical(s.gazeHeatOpts.(name));
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
yMin = px2deg(boundsPx.yMin - y0, setup);
yMax = px2deg(boundsPx.yMax - y0, setup);
if flipY
    yVals = sort([-yMin, -yMax]);
else
    yVals = sort([yMin, yMax]);
end
boundsDeg = struct( ...
    'xMin', px2deg(boundsPx.xMin - x0, setup), ...
    'xMax', px2deg(boundsPx.xMax - x0, setup), ...
    'yMin', yVals(1), ...
    'yMax', yVals(2));
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
finiteCounts = counts(isfinite(counts));
total = sum(finiteCounts(:));
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
        error('collectGazeHeat:BadNormalize', ...
            'opts.normalize must be count, probability, pdf, or peak.');
end
end


function [map, label] = localTargetNormalizedMap(gazeDensity, targetDensity, mode, pseudocount)
mode = lower(strtrim(char(string(mode))));
switch mode
    case 'none'
        map = gazeDensity;
        label = 'gaze density';
    case 'ratio'
        map = (gazeDensity + pseudocount) ./ (targetDensity + pseudocount);
        label = 'gaze / target density';
    case 'logratio'
        map = log2((gazeDensity + pseudocount) ./ (targetDensity + pseudocount));
        label = 'log2(gaze / target density)';
    case 'difference'
        map = gazeDensity - targetDensity;
        label = 'gaze density - target density';
    otherwise
        error('collectGazeHeat:BadTargetNormalize', ...
            'opts.targetNormalize must be none, ratio, logRatio, or difference.');
end
end


function label = localColorbarLabel(targetNormalize)
[~, label] = localTargetNormalizedMap(1, 1, targetNormalize, 1e-6);
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


function rows = localUniqueRowsTol(rows, tol)
if isempty(rows)
    return
end
keep = all(isfinite(rows), 2);
rows = rows(keep, :);
if isempty(rows)
    return
end
rounded = round(rows ./ tol) .* tol;
[~, ia] = unique(rounded, 'rows', 'stable');
rows = rows(ia, :);
end


function cmap = localColormapByName(scheme, nColors)
scheme = lower(strtrim(char(string(scheme))));
switch scheme
    case {'balance', 'balanced', 'diverging', 'bluered', 'bluewhitered'}
        cmap = localInterpolatedColormap([ ...
            0.08 0.19 0.55; ...
            0.26 0.57 0.78; ...
            0.96 0.96 0.96; ...
            0.88 0.42 0.31; ...
            0.55 0.08 0.11], nColors);
    case {'redblue', 'redwhiteblue'}
        cmap = flipud(localColormapByName('balance', nColors));
    case {'density', 'fire'}
        cmap = localInterpolatedColormap([ ...
            0.00 0.00 0.00; ...
            0.15 0.05 0.35; ...
            0.70 0.10 0.20; ...
            0.95 0.58 0.10; ...
            1.00 0.96 0.72], nColors);
    case {'hot', 'parula', 'turbo', 'jet', 'gray', 'grey'}
        if strcmp(scheme, 'grey')
            scheme = 'gray';
        end
        try
            cmap = feval(scheme, nColors);
        catch
            cmap = hot(nColors);
        end
    otherwise
        cmap = localColormapByName('balance', nColors);
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


function tf = localIsAllCode(value)
tf = (ischar(value) && strcmpi(strtrim(value), 'all')) || ...
    (isstring(value) && isscalar(value) && strcmpi(strtrim(char(value)), 'all'));
end
