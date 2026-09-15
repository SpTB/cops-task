function [chunkTable, csvPath] = exportSelReg(ex, csvPath, opts)
% exportSelReg  Export one row per CCG-defined tracking chunk.
%
%   T = exportSelReg(ex)
%   T = exportSelReg(ex, 'selection_chunks.csv')
%   [T, csvPath] = exportSelReg(ex, csvPath, opts)
%
% The default chunk definition is inherited from ccg.m via
% buildCcgTrackingEpisodes: hmmFiltered target assignment, hard threshold
% 0.9, minimum 100-ms tracking runs/chunks, bridging of eligible <=100-ms
% no-tracking gaps, and 150-ms blink interpolation. Pass overrides in
% opts.ccgOpts.
%
% By default, only two-target trials are retained because closer/farther
% target selection is undefined for one-target trials.
% opts.distanceUnits is 'deg' by default; use 'px' for legacy output.
% opts.compactOutput is true by default and retains only regression-ready
% identifiers, timing, selection labels, condition values, and the
% chunk-average/onset reward-distance predictors. Set it false to retain
% the full intermediate geometry table.

if nargin < 1 || ~isstruct(ex) || ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('exportSelReg:BadInput', 'ex must be a struct containing nonempty ex.Trials.');
end
if nargin < 2 || isempty(csvPath)
    csvPath = fullfile(pwd, 'selReg.csv');
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
defaults = struct( ...
    'trialList', 1:numel(ex.Trials), ...
    'twoTargetOnly', true, ...
    'writeCsv', true, ...
    'distanceUnits', 'deg', ...
    'compactOutput', true, ...
    'outputType', 'selection', ...
    'monkey', "", ...
    'date', "", ...
    'ccgOpts', struct());
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(opts, names{i}) || isempty(opts.(names{i}))
        opts.(names{i}) = defaults.(names{i});
    end
end
opts.distanceUnits = localResolveDistanceUnits(opts.distanceUnits);
opts.outputType = validatestring(char(string(opts.outputType)), ...
    {'selection','tracking'});

trialList = unique(double(opts.trialList(:)'));
trialList = trialList(isfinite(trialList) & trialList == round(trialList) & ...
    trialList >= 1 & trialList <= numel(ex.Trials));
if isempty(trialList)
    error('exportSelReg:NoTrials', 'opts.trialList contains no valid trial indices.');
end

episodes = buildCcgTrackingEpisodes(ex, trialList, 1, opts.ccgOpts);
chunkTable = localEmptyChunkTable();
if isempty(episodes)
    chunkTable = localConvertChunkDistanceUnits(chunkTable, ex.setup, opts.distanceUnits);
    if logical(opts.compactOutput)
        chunkTable = localCompactChunkTable( ...
            chunkTable, opts.distanceUnits, opts.outputType);
    end
    csvPath = char(string(csvPath));
    if logical(opts.writeCsv)
        localWriteTable(chunkTable, csvPath);
    end
    return
end

nEpisode = height(episodes);
rows = cell(nEpisode, 1);
nRow = 0;
for i = 1:nEpisode
    trialNo = round(double(episodes.trial(i)));
    T = ex.Trials(trialNo);
    step = double(episodes.step{i}(:));
    gazeX = double(episodes.gazeX{i}(:));
    gazeY = double(episodes.gazeY{i}(:));
    n = min([numel(step), numel(gazeX), numel(gazeY)]);
    if n < 1
        continue
    end
    step = step(1:n);
    gazeX = gazeX(1:n);
    gazeY = gazeY(1:n);

    [target1X, target1Y, target2X, target2Y] = localTargetsForSteps(T, step);
    [target1X, target1Y, target2X, target2Y] = localCanonicalizeTargets( ...
        target1X, target1Y, target2X, target2Y);
    hasTwoTargets = any(isfinite(target2X) & isfinite(target2Y));
    if logical(opts.twoTargetOnly) && ~hasTwoTargets
        continue
    end

    try
        rewardCenter = double(getGaussianCenterPx(ex, T));
        rewardCenter = rewardCenter(:)';
    catch
        rewardCenter = [NaN NaN];
    end
    if numel(rewardCenter) < 2
        rewardCenter = [NaN NaN];
    end

    gazeDist1 = hypot(gazeX - target1X, gazeY - target1Y);
    gazeDist2 = hypot(gazeX - target2X, gazeY - target2Y);
    rewardDist1 = hypot(target1X - rewardCenter(1), target1Y - rewardCenter(2));
    rewardDist2 = hypot(target2X - rewardCenter(1), target2Y - rewardCenter(2));
    interTargetDist = hypot(target1X - target2X, target1Y - target2Y);

    meanGazeDist1 = localMeanFinite(gazeDist1);
    meanGazeDist2 = localMeanFinite(gazeDist2);
    meanGazeDistanceGap = localMeanFinite(abs(gazeDist1 - gazeDist2));
    meanRewardDist1 = localMeanFinite(rewardDist1);
    meanRewardDist2 = localMeanFinite(rewardDist2);
    meanRewardGap = localMeanFinite(abs(rewardDist1 - rewardDist2));
    meanInterTargetDist = localMeanFinite(interTargetDist);

    closerTargetId = NaN;
    if isfinite(meanRewardDist1) && isfinite(meanRewardDist2)
        if meanRewardDist1 < meanRewardDist2
            closerTargetId = 1;
        elseif meanRewardDist2 < meanRewardDist1
            closerTargetId = 2;
        end
    end
    trackedTargetId = double(episodes.referenceTargetId(i));
    if ~ismember(trackedTargetId, [1 2])
        trackedTargetId = NaN;
    end

    % Reward distance of the physical target assigned to this HMM tracking
    % episode.  This differs from distM, which averages the distances of
    % both targets regardless of which one is being tracked.
    trackedTargetRewardDist = nan(n, 1);
    if trackedTargetId == 1
        trackedTargetRewardDist = rewardDist1;
    elseif trackedTargetId == 2
        trackedTargetRewardDist = rewardDist2;
    end
    meanTrackedTargetRewardDist = localMeanFinite(trackedTargetRewardDist);

    trackedCloser = NaN;
    if isfinite(trackedTargetId) && isfinite(closerTargetId)
        trackedCloser = double(trackedTargetId == closerTargetId);
    end

    [meanGazeDistCloser, meanGazeDistFarther] = localOrderByCloser( ...
        closerTargetId, meanGazeDist1, meanGazeDist2);
    [meanRewardDistCloser, meanRewardDistFarther] = localOrderByCloser( ...
        closerTargetId, meanRewardDist1, meanRewardDist2);
    chunkMidTimeSec = localChunkMidTimeSec(episodes, i);
    [distMOnset, distDOnset, closerTargetIdOnset] = ...
        localOnsetRewardDistances(T, step, rewardCenter);
    trackedCloserOnset = NaN;
    if isfinite(trackedTargetId) && isfinite(closerTargetIdOnset)
        trackedCloserOnset = double(trackedTargetId == closerTargetIdOnset);
    end
    screenRect = double(ex.setup.screenRect(:)');
    screenCenter = [(screenRect(1)+screenRect(3))/2, ...
        (screenRect(2)+screenRect(4))/2];
    assignedTarget = repmat(trackedTargetId, n, 1);
    trackedMask = isfinite(gazeX) & isfinite(gazeY) & ...
        isfinite(target1X) & isfinite(target1Y) & ...
        ((trackedTargetId == 1) | ...
        (trackedTargetId == 2 & isfinite(target2X) & isfinite(target2Y)));

    % Geometry-only projections onto the tracked-target-to-reward axis.
    % These are predictors, not observed gaze-bias outcomes.  A positive
    % value means the screen center or other target lies toward reward from
    % the tracked target; a negative value means it lies in the opposite
    % direction.
    trackedTargetX = nan(n, 1); trackedTargetY = nan(n, 1);
    otherTargetX = nan(n, 1); otherTargetY = nan(n, 1);
    if trackedTargetId == 1
        trackedTargetX = target1X; trackedTargetY = target1Y;
        otherTargetX = target2X; otherTargetY = target2Y;
    elseif trackedTargetId == 2
        trackedTargetX = target2X; trackedTargetY = target2Y;
        otherTargetX = target1X; otherTargetY = target1Y;
    end
    rewardVectorX = rewardCenter(1) - trackedTargetX;
    rewardVectorY = rewardCenter(2) - trackedTargetY;
    rewardVectorNorm = hypot(rewardVectorX, rewardVectorY);
    rewardUnitX = rewardVectorX ./ rewardVectorNorm;
    rewardUnitY = rewardVectorY ./ rewardVectorNorm;
    rewardUnitX(~isfinite(rewardUnitX)) = NaN;
    rewardUnitY(~isfinite(rewardUnitY)) = NaN;
    centerProjection = (screenCenter(1) - trackedTargetX) .* rewardUnitX + ...
        (screenCenter(2) - trackedTargetY) .* rewardUnitY;
    otherProjection = (otherTargetX - trackedTargetX) .* rewardUnitX + ...
        (otherTargetY - trackedTargetY) .* rewardUnitY;
    meanCenterProjection = localMeanFinite(centerProjection(trackedMask));
    meanOtherProjection = localMeanFinite(otherProjection(trackedMask));

    trackMetrics = computeTrackedBiasMetricsCoPs( ...
        target1X, target1Y, target2X, target2Y, gazeX, gazeY, ...
        assignedTarget, trackedMask, rewardCenter(1:2), screenCenter, ...
        double(episodes.dtSec(i)));

    nRow = nRow + 1;
    rows{nRow} = table( ...
        string(opts.monkey), localRequestedOrTrialDate(opts.date, ex, T), ...
        trialNo, localTrialOriginalNumber(T, trialNo), ...
        double(episodes.chunkNo(i)), double(episodes.chunkDurSec(i)), chunkMidTimeSec, ...
        double(episodes.nSamples(i)), double(episodes.dtSec(i)), ...
        trackedTargetId, closerTargetId, trackedCloser, ...
        meanGazeDist1, meanGazeDist2, meanGazeDistCloser, meanGazeDistFarther, ...
        meanGazeDistanceGap, ...
        meanRewardDist1, meanRewardDist2, meanRewardDistCloser, meanRewardDistFarther, ...
        meanRewardGap, meanInterTargetDist, meanTrackedTargetRewardDist, ...
        meanCenterProjection, meanOtherProjection, ...
        distMOnset, distDOnset, ...
        closerTargetIdOnset, trackedCloserOnset, ...
        trackMetrics.trackBiasPx, trackMetrics.trackGaussSpecificBiasPx, ...
        trackMetrics.trackScreenCenterBiasPx, trackMetrics.trackErrorPx, ...
        trackMetrics.trackVariabilityPx, ...
        rewardCenter(1), rewardCenter(2), ...
        localTrialScalar(T, {'background_noise_lvl'}), ...
        localTrialScalar(T, {'target_visibility', 'coherence'}), ...
        localTrialScalar(T, {'coherence', 'target_visibility'}), ...
        localTrialSourceFile(T), ...
        'VariableNames', { ...
        'monkey','date','trial','originalTrialNo','chunk','chunkLengthSec', ...
        'chunkTimeWithinTrialSec','nSamples','dtSec', ...
        'trackedTargetId','closerTargetId','trackedCloser', ...
        'meanGazeDistTarget1Px','meanGazeDistTarget2Px', ...
        'meanGazeDistCloserPx','meanGazeDistFartherPx','meanGazeDistanceGapPx', ...
        'meanRewardDistTarget1Px','meanRewardDistTarget2Px', ...
        'meanRewardDistCloserPx','meanRewardDistFartherPx', ...
        'meanRewardDistanceGapPx','meanInterTargetDistancePx', ...
        'meanTrackedTargetRewardDistPx', ...
        'meanCenterProjectionOntoRewardPx', ...
        'meanOtherProjectionOntoRewardPx', ...
        'distMOnsetPx','distDOnsetPx','closerTargetId_onset','trackedCloser_onset', ...
        'trackBiasPx','trackGaussSpecificBiasPx','trackScreenCenterBiasPx', ...
        'trackErrorPx','trackVariabilityPx', ...
        'rewardCenterXPx','rewardCenterYPx', ...
        'backgroundNoiseLvl','targetVisibility','coherence','sourceFile'});
end

if nRow > 0
    chunkTable = vertcat(rows{1:nRow});
    chunkTable.chunkTimeWithinTrialSec = localCenterChunkTimeWithinTrial( ...
        chunkTable.trial, chunkTable.chunkTimeWithinTrialSec);
end
chunkTable = localConvertChunkDistanceUnits(chunkTable, ex.setup, opts.distanceUnits);
if logical(opts.compactOutput)
    chunkTable = localCompactChunkTable( ...
        chunkTable, opts.distanceUnits, opts.outputType);
end
csvPath = char(string(csvPath));
if logical(opts.writeCsv)
    localWriteTable(chunkTable, csvPath);
    fprintf('exportSelReg: wrote %d tracking chunks to %s\n', height(chunkTable), csvPath);
end


function units = localResolveDistanceUnits(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error('exportSelReg:BadDistanceUnits', ...
        'opts.distanceUnits must be ''deg'' or ''px''.');
end
units = lower(strtrim(char(value)));
if ~ismember(units, {'deg', 'px'})
    error('exportSelReg:BadDistanceUnits', ...
        'opts.distanceUnits must be ''deg'' or ''px''.');
end
end


function T = localConvertChunkDistanceUnits(T, setup, units)
if strcmp(units, 'px')
    return
end
if ~isstruct(setup) || ~isfield(setup, 'screenRect') || numel(setup.screenRect) < 4
    error('exportSelReg:MissingScreenGeometry', ...
        'setup.screenRect is required for degree-coordinate outputs.');
end
rect = double(setup.screenRect(:)');
center = [(rect(1) + rect(3)) / 2, (rect(2) + rect(4)) / 2];
if ismember('rewardCenterXPx', T.Properties.VariableNames)
    T.rewardCenterXPx = double(T.rewardCenterXPx) - center(1);
end
if ismember('rewardCenterYPx', T.Properties.VariableNames)
    T.rewardCenterYPx = double(T.rewardCenterYPx) - center(2);
end
T = convertCoPsPxFieldsToDeg(T, setup);
end
end


function T = localEmptyChunkTable()
T = table( ...
    strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), strings(0,1), ...
    'VariableNames', { ...
    'monkey','date','trial','originalTrialNo','chunk','chunkLengthSec', ...
    'chunkTimeWithinTrialSec','nSamples','dtSec', ...
    'trackedTargetId','closerTargetId','trackedCloser', ...
    'meanGazeDistTarget1Px','meanGazeDistTarget2Px', ...
    'meanGazeDistCloserPx','meanGazeDistFartherPx','meanGazeDistanceGapPx', ...
    'meanRewardDistTarget1Px','meanRewardDistTarget2Px', ...
    'meanRewardDistCloserPx','meanRewardDistFartherPx', ...
    'meanRewardDistanceGapPx','meanInterTargetDistancePx', ...
    'meanTrackedTargetRewardDistPx', ...
    'meanCenterProjectionOntoRewardPx', ...
    'meanOtherProjectionOntoRewardPx', ...
    'distMOnsetPx','distDOnsetPx','closerTargetId_onset','trackedCloser_onset', ...
    'trackBiasPx','trackGaussSpecificBiasPx','trackScreenCenterBiasPx', ...
    'trackErrorPx','trackVariabilityPx', ...
    'rewardCenterXPx','rewardCenterYPx', ...
    'backgroundNoiseLvl','targetVisibility','coherence','sourceFile'});
end


function value = localChunkMidTimeSec(episodes, row)
value = NaN;
if ~ismember('tRelSec', episodes.Properties.VariableNames)
    return
end
t = double(episodes.tRelSec{row}(:));
t = t(isfinite(t));
if ~isempty(t)
    value = (t(1) + t(end)) / 2;
end
end


function centered = localCenterChunkTimeWithinTrial(trial, chunkMidTimeSec)
trial = double(trial(:));
chunkMidTimeSec = double(chunkMidTimeSec(:));
centered = nan(size(chunkMidTimeSec));
trialIds = unique(trial(isfinite(trial)));
for i = 1:numel(trialIds)
    idx = trial == trialIds(i) & isfinite(chunkMidTimeSec);
    if any(idx)
        centered(idx) = chunkMidTimeSec(idx) - mean(chunkMidTimeSec(idx));
    end
end
end


function [distM, distD, closerTargetId] = localOnsetRewardDistances(T, chunkStep, rewardCenter)
distM = NaN;
distD = NaN;
closerTargetId = NaN;
chunkStep = round(double(chunkStep(:)));
firstStep = find(isfinite(chunkStep) & chunkStep >= 1, 1, 'first');
if isempty(firstStep) || numel(rewardCenter) < 2 || ~all(isfinite(rewardCenter(1:2)))
    return
end
onsetStep = chunkStep(firstStep);
predictorStep = max(1, onsetStep - 1);
[x1, y1, x2, y2] = localTargetsForSteps(T, predictorStep);
if ~all(isfinite([x1, y1, x2, y2])) && predictorStep ~= onsetStep
    [x1, y1, x2, y2] = localTargetsForSteps(T, onsetStep);
end
if ~all(isfinite([x1, y1, x2, y2]))
    return
end
d1 = hypot(x1 - rewardCenter(1), y1 - rewardCenter(2));
d2 = hypot(x2 - rewardCenter(1), y2 - rewardCenter(2));
distM = (d1 + d2) / 2;
distD = abs(d1 - d2);
if d1 < d2
    closerTargetId = 1;
elseif d2 < d1
    closerTargetId = 2;
end
end


function value = localRequestedOrTrialDate(requestedDate, ex, T)
value = string(requestedDate);
if strlength(value) == 0
    value = localTrialDate(ex, T);
end
end


function T = localCompactChunkTable(T, units, outputType)
if strcmp(units, 'deg')
    suffix = 'Deg';
else
    suffix = 'Px';
end
reward1 = ['meanRewardDistTarget1' suffix];
reward2 = ['meanRewardDistTarget2' suffix];
gap = ['meanRewardDistanceGap' suffix];
onsetM = ['distMOnset' suffix];
onsetD = ['distDOnset' suffix];
T.distM = (double(T.(reward1)) + double(T.(reward2))) / 2;
T.distD = double(T.(gap));
T.distM_onset = double(T.(onsetM));
T.distD_onset = double(T.(onsetD));
identifiers = {'monkey','date','trial','originalTrialNo','chunk', ...
    'chunkLengthSec','chunkTimeWithinTrialSec'};
predictors = {'distM','distD','distM_onset','distD_onset', ...
    'backgroundNoiseLvl','targetVisibility'};
if strcmp(outputType, 'tracking')
    predictors = [{ 'meanTrackedTargetRewardDistDeg', ...
        'meanCenterProjectionOntoRewardDeg', ...
        'meanOtherProjectionOntoRewardDeg'}, predictors];
    if strcmp(units, 'px')
        predictors(1:3) = { 'meanTrackedTargetRewardDistPx', ...
            'meanCenterProjectionOntoRewardPx', ...
            'meanOtherProjectionOntoRewardPx'};
    end
    outcomes = {'trackBiasDeg','trackGaussSpecificBiasDeg', ...
        'trackScreenCenterBiasDeg','trackErrorDeg','trackVariabilityDeg'};
    if strcmp(units, 'px')
        outcomes = strrep(outcomes, 'Deg', 'Px');
    end
else
    outcomes = {'trackedTargetId','closerTargetId','trackedCloser', ...
        'closerTargetId_onset','trackedCloser_onset'};
end
keep = [identifiers, outcomes, predictors];
T = T(:, keep);
end


function [x1, y1, x2, y2] = localTargetsForSteps(T, step)
n = numel(step);
x1 = nan(n,1);
y1 = nan(n,1);
x2 = nan(n,1);
y2 = nan(n,1);
if ~isfield(T, 'targetPositions') || isempty(T.targetPositions)
    return
end
nStep = numel(T.targetPositions);
for i = 1:n
    s = round(step(i));
    if ~isfinite(s) || s < 1 || s > nStep
        continue
    end
    P = T.targetPositions(s);
    if isfield(P, 'targ1') && isstruct(P.targ1) && ...
            isfield(P.targ1, 'pos_abs') && numel(P.targ1.pos_abs) >= 2
        x1(i) = double(P.targ1.pos_abs(1));
        y1(i) = double(P.targ1.pos_abs(2));
    end
    if isfield(P, 'targ2') && isstruct(P.targ2) && ...
            isfield(P.targ2, 'pos_abs') && numel(P.targ2.pos_abs) >= 2
        x2(i) = double(P.targ2.pos_abs(1));
        y2(i) = double(P.targ2.pos_abs(2));
    end
end
end


function [x1, y1, x2, y2] = localCanonicalizeTargets(x1, y1, x2, y2)
firstValid = find(isfinite(x1) & isfinite(y1) & isfinite(x2) & isfinite(y2), 1, 'first');
if isempty(firstValid)
    return
end
swap = x1(firstValid) > x2(firstValid) || ...
    (x1(firstValid) == x2(firstValid) && y1(firstValid) > y2(firstValid));
if swap
    [x1, x2] = deal(x2, x1);
    [y1, y2] = deal(y2, y1);
end
end


function value = localMeanFinite(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    value = mean(x);
end
end


function [closerValue, fartherValue] = localOrderByCloser(closerTargetId, value1, value2)
closerValue = NaN;
fartherValue = NaN;
if closerTargetId == 1
    closerValue = value1;
    fartherValue = value2;
elseif closerTargetId == 2
    closerValue = value2;
    fartherValue = value1;
end
end


function value = localTrialScalar(T, candidateFields)
value = NaN;
for i = 1:numel(candidateFields)
    name = candidateFields{i};
    if isfield(T, name) && isnumeric(T.(name)) && isscalar(T.(name)) && isfinite(T.(name))
        value = double(T.(name));
        return
    end
end
end


function value = localTrialOriginalNumber(T, fallback)
value = localTrialScalar(T, {'originalTrialNo', 'trialInSession', 'trial'});
if ~isfinite(value)
    value = fallback;
end
end


function value = localTrialSourceFile(T)
value = "";
if isfield(T, 'sourceFileName') && (ischar(T.sourceFileName) || isstring(T.sourceFileName))
    value = string(T.sourceFileName);
end
end


function value = localTrialDate(ex, T)
value = "";
paths = strings(0,1);
for name = ["sourceFilePath", "sourceFileName"]
    if isfield(T, name) && (ischar(T.(name)) || isstring(T.(name)))
        paths(end+1,1) = string(T.(name)); %#ok<AGROW>
    end
end
if isfield(ex, 'Header') && isstruct(ex.Header) && isfield(ex.Header, 'onlineDirName')
    paths(end+1,1) = string(ex.Header.onlineDirName); %#ok<AGROW>
end
for i = 1:numel(paths)
    token = regexp(char(paths(i)), '(20\d{2})[.\-_/](\d{2})[.\-_/](\d{2})', 'tokens', 'once');
    if ~isempty(token)
        value = string(sprintf('%s-%s-%s', token{1}, token{2}, token{3}));
        return
    end
end
if isfield(ex, 'Header') && isstruct(ex.Header) && isfield(ex.Header, 'fileID')
    fileID = double(ex.Header.fileID(:));
    if numel(fileID) >= 3 && all(isfinite(fileID(1:3)))
        value = string(sprintf('%04d-%02d-%02d', round(fileID(1)), round(fileID(2)), round(fileID(3))));
    end
end
end


function localWriteTable(T, csvPath)
folder = fileparts(csvPath);
if ~isempty(folder) && ~isfolder(folder)
    mkdir(folder);
end
writetable(T, csvPath);
end
