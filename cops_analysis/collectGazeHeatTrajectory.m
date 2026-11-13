function out = collectGazeHeatTrajectory(subject, groupingArg, opts)
% collectGazeHeatTrajectory  Collect gazeHeatTrajectory outputs across sessions.
%
%   A = collectGazeHeatTrajectory('ka')
%   A = collectGazeHeatTrajectory('ka', 'block', opts)
%   plotGazeHeatTrajectoryAggregate(A, 'block')
%
% This mirrors collectGazeHeat session discovery and filtering, but stores
% rolling density-peak trajectory summaries from gazeHeatTrajectory.
% Block aggregates are always stored in A.blockGroups, so a collection made
% with groupingArg=[] can still be plotted by block later.
% Numeric filters including opts.waitHz and opts.waitSecs accept exact
% numeric values or comparison strings such as '>10' or '<=30'.

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
    error('collectGazeHeatTrajectory:BadOpts', 'opts must be a struct.');
end

opts = localDefaults(opts);
subject = localResolveSubject(subject, opts);
subjectDir = fullfile(char(opts.dataRoot), char(subject));
if ~exist(subjectDir, 'dir')
    error('collectGazeHeatTrajectory:SubjectNotFound', 'Subject directory not found: %s', subjectDir);
end

dateFrom = localParseDateBound(opts.dateFrom, false);
dateTo = localParseDateBound(opts.dateTo, true);
sessionDirs = localSessionDirs(subjectDir, dateFrom, dateTo);

[candidates, fileRows] = localFindCandidateSessions(subject, sessionDirs, opts);
if isempty(candidates)
    out = localEmptyOutput(subject, groupingArg, opts, fileRows);
    return
end

[groupLabels, groupInfo] = localGroupLabels(groupingArg, opts);
groups = cell(numel(groupLabels), 1);
for g = 1:numel(groupLabels)
    groups{g} = localEmptyGroup(groupLabels(g));
end
blockLabels = localBlockLabels(opts.blockLvls);
blockGroups = cell(numel(blockLabels), 1);
for g = 1:numel(blockLabels)
    blockGroups{g} = localEmptyGroup(blockLabels(g));
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

    if strcmp(groupInfo.mode, 'all')
        groups{1} = localCollectRun(groups{1}, ex, C, C.trialList, groupLabels(1), NaN, opts);
    end

    for blockIdx = 1:numel(blockGroups)
        inBlock = C.block == blockIdx;
        if ~any(inBlock)
            continue
        end
        trialList = C.trialList(inBlock);
        blockGroups{blockIdx} = localCollectRun( ...
            blockGroups{blockIdx}, ex, C, trialList, blockLabels(blockIdx), blockIdx, opts);
    end
end

for g = 1:numel(blockGroups)
    blockGroups{g} = localFinalizeGroup(blockGroups{g}, opts);
end
if strcmp(groupInfo.mode, 'block')
    groups = blockGroups;
    groupLabels = blockLabels;
else
    for g = 1:numel(groups)
        groups{g} = localFinalizeGroup(groups{g}, opts);
    end
end

out = struct();
out.subject = string(subject);
out.groupingArg = groupingArg;
out.groupLabels = groupLabels(:);
out.groups = groups;
out.blockLabels = blockLabels(:);
out.blockGroups = blockGroups;
out.fileTable = localRowsToTable(fileRows);
out.options = opts;
out.transform = struct( ...
    'alignRewardToTopLeft', logical(opts.alignRewardToTopLeft), ...
    'plotRotate45', logical(opts.plotRotate45), ...
    'description', "gazeHeatTrajectory coordinate transform");
end


function group = localCollectRun(group, ex, C, trialList, groupLabel, blockIdx, opts)
trialList = double(trialList(:)');
trialList = trialList(isfinite(trialList));
if isempty(trialList)
    return
end
try
    T = gazeHeatTrajectory(ex, trialList, opts.gazeHeatTrajectoryOpts);
catch err
    failure = localFailureRow(C, groupLabel, blockIdx, numel(trialList), err);
    if isempty(group.failures) || width(group.failures) == 0
        group.failures = failure;
    else
        group.failures = [group.failures; failure];
    end
    return
end
if ~isstruct(T) || ~isfield(T, 'summary') || ~istable(T.summary)
    return
end
summary = localAugmentSummary(T.summary, C, groupLabel, blockIdx);
if isempty(group.summary)
    group.summary = summary;
else
    group.summary = [group.summary; summary];
end
group.nRuns = group.nRuns + 1;
group.nInputTrials = group.nInputTrials + numel(trialList);
group.fileName = unique([group.fileName; string(C.fileName)], 'stable');
end


function summary = localAugmentSummary(summary, C, groupLabel, blockIdx)
if isempty(summary) || height(summary) == 0
    return
end
n = height(summary);
trialStartDay = localTrialDayAt(C, summary.trialStart);
trialStopDay = localTrialDayAt(C, summary.trialStop);
trialCenterDay = mean([trialStartDay(:), trialStopDay(:)], 2, 'omitnan');
windowBlock = localWindowBlocks(C, summary.trialStart, summary.trialStop, blockIdx);

meta = table( ...
    repmat(string(C.subject), n, 1), ...
    repmat(string(C.sessionFolder), n, 1), ...
    repmat(C.sessionDate, n, 1), ...
    repmat(string(C.fileName), n, 1), ...
    repmat(string(C.filePath), n, 1), ...
    repmat(string(groupLabel), n, 1), ...
    (1:n)', ...
    trialStartDay(:), ...
    trialStopDay(:), ...
    trialCenterDay(:), ...
    windowBlock(:), ...
    repmat(double(C.waitSecs), n, 1), ...
    repmat(double(C.waitHz), n, 1), ...
    'VariableNames', {'subject','sessionFolder','sessionDate','fileName','filePath', ...
        'groupLabel','windowIndex','trialStartDay','trialStopDay','trialCenterDay', ...
        'block','waitSecs','waitHz'});
summary = [meta, summary];
end


function row = localFailureRow(C, groupLabel, blockIdx, nTrials, err)
row = table( ...
    string(C.subject), ...
    string(C.sessionFolder), ...
    C.sessionDate, ...
    string(C.fileName), ...
    string(C.filePath), ...
    string(groupLabel), ...
    double(blockIdx), ...
    double(nTrials), ...
    string(err.identifier), ...
    string(err.message), ...
    'VariableNames', {'subject','sessionFolder','sessionDate','fileName','filePath', ...
        'groupLabel','block','nTrials','identifier','message'});
end


function group = localFinalizeGroup(group, opts)
if isempty(group.summary) || height(group.summary) == 0
    group.meanTrajectory = table();
    return
end
ok = localOkRows(group.summary);
group.nWindows = height(group.summary);
group.nOkWindows = nnz(ok);
if any(ok)
    group.nSessions = numel(unique(string(group.summary.fileName(ok))));
    group.trialDayRange = [min(group.summary.trialCenterDay(ok), [], 'omitnan'), ...
        max(group.summary.trialCenterDay(ok), [], 'omitnan')];
    group.rewardPeakDeg = [ ...
        localAggregateValue(group.summary.rewardXDeg(ok), opts.aggregationStatistic), ...
        localAggregateValue(group.summary.rewardYDeg(ok), opts.aggregationStatistic)];
    group.rewardRadius1sdDeg = localAggregateValue(group.summary.rewardRadius1sdDeg(ok), opts.aggregationStatistic);
else
    group.trialDayRange = [NaN NaN];
    group.rewardPeakDeg = [NaN NaN];
    group.rewardRadius1sdDeg = NaN;
end
group.meanTrajectory = localAggregateTrajectory(group.summary, opts);
group.fileName = unique(group.fileName, 'stable');
end


function M = localAggregateTrajectory(S, opts)
ok = localOkRows(S);
if ~any(ok)
    M = table();
    return
end
S = S(ok, :);
x = double(S.trialCenterDay);
binSize = double(opts.trajectoryBinSizeTrials);
lo = floor(min(x, [], 'omitnan') ./ binSize) .* binSize;
hi = ceil(max(x, [], 'omitnan') ./ binSize) .* binSize;
if ~isfinite(lo) || ~isfinite(hi)
    M = table();
    return
end
if hi <= lo
    hi = lo + binSize;
end
edges = lo:binSize:hi;
if edges(end) < hi || numel(edges) < 2
    edges(end+1) = hi;
end
nBin = numel(edges) - 1;

trialCenterDay = NaN(nBin, 1);
trialStartDay = NaN(nBin, 1);
trialStopDay = NaN(nBin, 1);
nWindows = zeros(nBin, 1);
nSessions = zeros(nBin, 1);
nSamples = NaN(nBin, 1);
peakXDeg = NaN(nBin, 1);
peakYDeg = NaN(nBin, 1);
rewardXDeg = NaN(nBin, 1);
rewardYDeg = NaN(nBin, 1);
peakValue = NaN(nBin, 1);
peakDistToRewardDeg = NaN(nBin, 1);
peakDistToRewardDegSE = NaN(nBin, 1);
meanDistToRewardDeg = NaN(nBin, 1);
medianDistToRewardDeg = NaN(nBin, 1);
medianDistToRewardDegSE = NaN(nBin, 1);
rewardRadius1sdDeg = NaN(nBin, 1);
fracWithin1sd = NaN(nBin, 1);

for b = 1:nBin
    if b == nBin
        ii = x >= edges(b) & x <= edges(b + 1);
    else
        ii = x >= edges(b) & x < edges(b + 1);
    end
    if ~any(ii)
        continue
    end
    nWindows(b) = nnz(ii);
    nSessions(b) = numel(unique(string(S.fileName(ii))));
    trialCenterDay(b) = localAggregateValue(S.trialCenterDay(ii), opts.aggregationStatistic);
    trialStartDay(b) = min(S.trialStartDay(ii), [], 'omitnan');
    trialStopDay(b) = max(S.trialStopDay(ii), [], 'omitnan');
    nSamples(b) = sum(S.nSamples(ii), 'omitnan');
    peakXDeg(b) = localAggregateValue(S.peakXDeg(ii), opts.aggregationStatistic);
    peakYDeg(b) = localAggregateValue(S.peakYDeg(ii), opts.aggregationStatistic);
    rewardXDeg(b) = localAggregateValue(S.rewardXDeg(ii), opts.aggregationStatistic);
    rewardYDeg(b) = localAggregateValue(S.rewardYDeg(ii), opts.aggregationStatistic);
    peakValue(b) = localAggregateValue(S.peakValue(ii), opts.aggregationStatistic);
    peakDistToRewardDeg(b) = localAggregateValue(S.peakDistToRewardDeg(ii), opts.aggregationStatistic);
    peakDistToRewardDegSE(b) = localStandardError(S.peakDistToRewardDeg(ii));
    meanDistToRewardDeg(b) = localAggregateValue(S.meanDistToRewardDeg(ii), opts.aggregationStatistic);
    medianDistToRewardDeg(b) = localAggregateValue(S.medianDistToRewardDeg(ii), opts.aggregationStatistic);
    medianDistToRewardDegSE(b) = localStandardError(S.medianDistToRewardDeg(ii));
    rewardRadius1sdDeg(b) = localAggregateValue(S.rewardRadius1sdDeg(ii), opts.aggregationStatistic);
    fracWithin1sd(b) = localAggregateValue(S.fracWithin1sd(ii), opts.aggregationStatistic);
end

keep = nWindows > 0;
M = table( ...
    trialCenterDay(keep), trialStartDay(keep), trialStopDay(keep), ...
    nWindows(keep), nSessions(keep), nSamples(keep), ...
    peakXDeg(keep), peakYDeg(keep), rewardXDeg(keep), rewardYDeg(keep), ...
    peakValue(keep), peakDistToRewardDeg(keep), peakDistToRewardDegSE(keep), ...
    meanDistToRewardDeg(keep), medianDistToRewardDeg(keep), medianDistToRewardDegSE(keep), ...
    rewardRadius1sdDeg(keep), fracWithin1sd(keep), ...
    'VariableNames', {'trialCenterDay','trialStartDay','trialStopDay', ...
        'nWindows','nSessions','nSamples','peakXDeg','peakYDeg', ...
        'rewardXDeg','rewardYDeg','peakValue','peakDistToRewardDeg', ...
        'peakDistToRewardDegSE','meanDistToRewardDeg','medianDistToRewardDeg', ...
        'medianDistToRewardDegSE','rewardRadius1sdDeg','fracWithin1sd'});
end


function ok = localOkRows(S)
ok = strcmp(string(S.status), "ok") & ...
    isfinite(S.trialCenterDay) & isfinite(S.peakXDeg) & isfinite(S.peakYDeg);
end


function value = localAggregateValue(values, statistic)
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    value = NaN;
    return
end
switch lower(strtrim(char(string(statistic))))
    case {'mean', 'average', 'avg'}
        value = mean(values, 'omitnan');
    otherwise
        value = median(values, 'omitnan');
end
end


function value = localStandardError(values)
values = double(values(:));
values = values(isfinite(values));
n = numel(values);
if n < 2
    value = NaN;
else
    value = std(values, 0, 'omitnan') ./ sqrt(n);
end
end


function value = localTrialDayAt(C, trialNo)
trialNo = round(double(trialNo(:)));
value = NaN(size(trialNo));
valid = isfinite(trialNo) & trialNo >= 1 & trialNo <= numel(C.trialDayAll);
value(valid) = C.trialDayAll(trialNo(valid));
end


function block = localWindowBlocks(C, trialStart, trialStop, forcedBlock)
n = numel(trialStart);
block = NaN(n, 1);
if isfinite(forcedBlock)
    block(:) = forcedBlock;
    return
end
for i = 1:n
    a = max(1, round(double(trialStart(i))));
    b = min(numel(C.blockAll), round(double(trialStop(i))));
    if ~isfinite(a) || ~isfinite(b) || b < a
        continue
    end
    vals = C.blockAll(a:b);
    vals = vals(isfinite(vals));
    if isempty(vals)
        continue
    end
    block(i) = mode(vals);
end
end


function tf = localLooksLikeGroupingArg(value)
tf = ischar(value) || isstring(value) || isnumeric(value) || iscell(value);
end


function opts = localDefaults(opts)
hasBlockLvls = isfield(opts, 'blockLvls') && ~isempty(opts.blockLvls);
hasLegacyBlockEdges = isfield(opts, 'blockEdges') && ~isempty(opts.blockEdges);
hasTopLevelGazeHeatOpts = isfield(opts, 'gazeHeatOpts') && ~isempty(opts.gazeHeatOpts);
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
    'windowTrials', 20, ...
    'stepTrials', 5, ...
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
    'trajectoryBinSizeTrials', [], ...
    'aggregationStatistic', 'mean', ...
    'gazeHeatTrajectoryOpts', struct(), ...
    'gazeHeatOpts', struct(), ...
    'verbose', true);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(opts, names{i}) || isempty(opts.(names{i}))
        opts.(names{i}) = defaults.(names{i});
    end
end
if ~hasBlockLvls && hasLegacyBlockEdges
    opts.blockLvls = opts.blockEdges;
end
opts.blockLvls = double(opts.blockLvls(:)');
if isempty(opts.blockLvls) || any(~isfinite(opts.blockLvls)) || any(diff(opts.blockLvls) <= 0)
    error('collectGazeHeatTrajectory:BadBlockLvls', ...
        'opts.blockLvls must be an increasing numeric vector, default [120 240].');
end
opts.blockEdges = opts.blockLvls;
opts.windowTrials = max(1, round(double(localFirstScalar(opts.windowTrials))));
opts.stepTrials = max(1, round(double(localFirstScalar(opts.stepTrials))));
opts.peakFrac = max(0, min(1, double(localFirstScalar(opts.peakFrac))));
opts.binSizeDeg = double(localFirstScalar(opts.binSizeDeg));
opts.smoothSigmaDeg = double(localFirstScalar(opts.smoothSigmaDeg));
opts.targetPseudocount = double(localFirstScalar(opts.targetPseudocount));
if isempty(opts.trajectoryBinSizeTrials)
    opts.trajectoryBinSizeTrials = opts.stepTrials;
else
    opts.trajectoryBinSizeTrials = max(1, double(localFirstScalar(opts.trajectoryBinSizeTrials)));
end
if ~isstruct(opts.gazeHeatTrajectoryOpts)
    error('collectGazeHeatTrajectory:BadTrajectoryOpts', 'opts.gazeHeatTrajectoryOpts must be a struct.');
end
if ~isstruct(opts.gazeHeatOpts)
    error('collectGazeHeatTrajectory:BadGazeHeatOpts', 'opts.gazeHeatOpts must be a struct.');
end
opts.gazeHeatTrajectoryOpts = localTrajectoryOpts(opts, hasTopLevelGazeHeatOpts);
end


function trajOpts = localTrajectoryOpts(opts, hasTopLevelGazeHeatOpts)
trajOpts = opts.gazeHeatTrajectoryOpts;
fields = {'windowTrials','stepTrials','peakFrac','peakField','alignRewardToTopLeft', ...
    'plotRotate45','binSizeDeg','boundsDeg','smoothSigmaDeg','normalize', ...
    'targetNormalize','targetPseudocount','targetDensityTarget', ...
    'targetDensityRequiresGazeOnScreen','useEyeTime','onlyGoState', ...
    'insideTextureOnly','timeWindowSec','flipY','circleBound'};
for i = 1:numel(fields)
    trajOpts.(fields{i}) = opts.(fields{i});
end
if hasTopLevelGazeHeatOpts || ~isfield(trajOpts, 'gazeHeatOpts') || ~isstruct(trajOpts.gazeHeatOpts)
    trajOpts.gazeHeatOpts = opts.gazeHeatOpts;
end
end


function [candidates, rows] = localFindCandidateSessions(subject, sessionDirs, opts)
candidates = struct('subject', {}, 'filePath', {}, 'fileName', {}, ...
    'sessionFolder', {}, 'sessionDate', {}, 'trialList', {}, 'trialDay', {}, ...
    'block', {}, 'trialDayAll', {}, 'blockAll', {}, 'waitSecs', {}, 'waitHz', {});
rows = localEmptyRows();
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
        row.status = "included";
        rows = localAppendRow(rows, row);
        candidates(end+1) = struct( ... %#ok<AGROW>
            'subject', string(subject), ...
            'filePath', string(filePath), ...
            'fileName', string(row.fileName), ...
            'sessionFolder', string(sessionDir.name), ...
            'sessionDate', sessionDir.date, ...
            'trialList', trialList(:)', ...
            'trialDay', trialDay(trialList(:))', ...
            'block', block(trialList(:))', ...
            'trialDayAll', trialDay(:)', ...
            'blockAll', block(:)', ...
            'waitSecs', waitSecs, ...
            'waitHz', waitHz);
        if opts.verbose
            fprintf('Included %s: %d gaze-heat-trajectory trials\n', row.fileName, row.nSelectedTrials);
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
        error('collectGazeHeatTrajectory:UnknownGrouping', ...
            'Supported groupingArg values are [], ''all'', or ''block''.');
end
end


function tf = localIsAllCode(value)
tf = false;
if ischar(value) || (isstring(value) && isscalar(value))
    code = lower(strtrim(string(value)));
    tf = code == "" || code == "all";
end
end


function group = localEmptyGroup(label)
group = struct();
group.groupLabel = label;
group.summary = table();
group.meanTrajectory = table();
group.failures = table();
group.nRuns = 0;
group.nInputTrials = 0;
group.nWindows = 0;
group.nOkWindows = 0;
group.nSessions = 0;
group.trialDayRange = [NaN NaN];
group.rewardPeakDeg = [NaN NaN];
group.rewardRadius1sdDeg = NaN;
group.fileName = strings(0, 1);
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
error('collectGazeHeatTrajectory:BadNumericFilter', ...
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
    error('collectGazeHeatTrajectory:BadNumericFilter', ...
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
        error('collectGazeHeatTrajectory:BadNumericFilter', ...
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
error('collectGazeHeatTrajectory:BadNumericFilter', ...
    'waitSecs/waitHz filters must be numeric values or comparison strings such as ''>10''.');
end


function subject = localResolveSubject(subject, opts)
if ~(ischar(subject) || (isstring(subject) && isscalar(subject)))
    error('collectGazeHeatTrajectory:BadSubject', 'subject must be a text scalar.');
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
    error('collectGazeHeatTrajectory:BadDate', 'Date must be ''YYYY.MM.DD'', datetime, or shorthand like ''Jun10''.');
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
out.fileTable = localRowsToTable(fileRows);
out.options = opts;
out.transform = struct( ...
    'alignRewardToTopLeft', logical(opts.alignRewardToTopLeft), ...
    'plotRotate45', logical(opts.plotRotate45), ...
    'description', "gazeHeatTrajectory coordinate transform");
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
