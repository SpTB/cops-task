function [episodeTable, csvPath, pupilOut] = exportPupilHmmRegressors(ex, csvPath, opts)
% exportPupilHmmRegressors  Export pupil/reward-distance tracking episodes.
%
%   T = exportPupilHmmRegressors(ex)
%   T = exportPupilHmmRegressors(ex, 'pupil_episodes.csv')
%   [T, csvPath, pupilOut] = exportPupilHmmRegressors(ex, csvPath, opts)
%
% One row is written per contiguous hard-HMM TLeft or TRight episode. The
% pupil outcome uses the same preprocessing as pupilHmmTransitions: robust
% within-input-trial-set-and-eye z scoring, blink padding, interpolation of short
% gaps, smoothing, binocular averaging, and (by default) strict exclusion of
% gaze outside the screen. Distances are exported in visual degrees.
%
% Main columns for an R mixed model:
%   meanPupilZ
%   meanPupilRaw
%   meanTrackedTargetRewardDistDeg
%   meanOtherTargetRewardDistDeg
%   distM
%   relativeAdvantage
%   meanGazeRewardDistDeg
%   meanGazeXDeg, meanGazeYDeg, meanGazeEccentricityDeg
%   meanGazeRadialErrorDeg
%   episodeDurationSec, validPupilFrac, block, trial, condition variables
%
% Important opts (defaults):
%   hmmMethod='smoothed', minEpisodeSec=0.10, minValidPupilFrac=0.50,
%   writeCsv=true. Other pupilHmmTransitions preprocessing options can be
%   supplied directly in opts. A manual call normalizes across opts.trialList;
%   exportHMM calls this once on the merged day before splitting block files.

if nargin < 1 || ~isstruct(ex) || ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('exportPupilHmmRegressors:BadInput', ...
        'ex must be a structure containing nonempty ex.Trials.');
end
if nargin < 2 || isempty(csvPath)
    csvPath = fullfile(pwd, 'pupilHmmEpisodes.csv');
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
defaults = struct( ...
    'hmmMethod', 'smoothed', ...
    'trialList', 1:numel(ex.Trials), ...
    'minEpisodeSec', 0.10, ...
    'minValidPupilFrac', 0.50, ...
    'writeCsv', true, ...
    'makePlot', false, ...
    'requireSm3', false, ...
    'baselineWindowSec', [], ...
    'excludeOutsideScreen', true);
opts = localFillDefaults(opts, defaults);
opts.hmmMethod = validatestring(char(string(opts.hmmMethod)), ...
    {'smoothed','filtered','predictive'});
validateattributes(opts.minEpisodeSec, {'numeric'}, ...
    {'scalar','real','finite','nonnegative'});
validateattributes(opts.minValidPupilFrac, {'numeric'}, ...
    {'scalar','real','finite','>=',0,'<=',1});

pupilOpts = opts;
pupilOpts.makePlot = false;
pupilOpts.requireSm3 = false;
pupilOpts.baselineWindowSec = [];
pupilOut = pupilHmmTransitions(ex, pupilOpts);
sampleTable = pupilOut.samplePupil;
rows = cell(0, 1);
screenRect = double(ex.setup.screenRect(:)');
screenCenter = [(screenRect(1)+screenRect(3))/2, ...
    (screenRect(2)+screenRect(4))/2];

for tableRow = 1:height(sampleTable)
    trialNo = double(sampleTable.trial(tableRow));
    T = ex.Trials(trialNo);
    time = double(sampleTable.tRelSec{tableRow}(:));
    pupil = double(sampleTable.pupilZ{tableRow}(:));
    pupilRaw = double(sampleTable.pupilRaw{tableRow}(:));
    gazeX = double(sampleTable.gazeXPx{tableRow}(:));
    gazeY = double(sampleTable.gazeYPx{tableRow}(:));
    hardTarget = double(sampleTable.hardTarget{tableRow}(:));
    n = min([numel(time), numel(pupil), numel(pupilRaw), numel(gazeX), ...
        numel(gazeY), numel(hardTarget)]);
    if n < 2
        continue
    end
    time = time(1:n); pupil = pupil(1:n); pupilRaw = pupilRaw(1:n);
    gazeX = gazeX(1:n); gazeY = gazeY(1:n);
    hardTarget = hardTarget(1:n);
    hardTarget(~ismember(hardTarget, [0 1 2])) = NaN;
    [target1X, target1Y, target2X, target2Y] = ...
        mapTargetsByStep(ex, T, time);
    target1X = double(target1X(:)); target1Y = double(target1Y(:));
    target2X = double(target2X(:)); target2Y = double(target2Y(:));
    n = min([n, numel(target1X), numel(target1Y), ...
        numel(target2X), numel(target2Y)]);
    time = time(1:n); pupil = pupil(1:n); pupilRaw = pupilRaw(1:n);
    gazeX = gazeX(1:n); gazeY = gazeY(1:n);
    hardTarget = hardTarget(1:n);
    target1X = target1X(1:n); target1Y = target1Y(1:n);
    target2X = target2X(1:n); target2Y = target2Y(1:n);

    try
        rewardCenter = double(getGaussianCenterPx(ex, T));
        rewardCenter = rewardCenter(:)';
    catch
        rewardCenter = [NaN NaN];
    end
    if numel(rewardCenter) < 2 || any(~isfinite(rewardCenter(1:2)))
        continue
    end
    dTarget1RewardPx = hypot(target1X-rewardCenter(1), target1Y-rewardCenter(2));
    dTarget2RewardPx = hypot(target2X-rewardCenter(1), target2Y-rewardCenter(2));
    dGazeRewardPx = hypot(gazeX-rewardCenter(1), gazeY-rewardCenter(2));
    trackedX = nan(n,1); trackedY = nan(n,1);
    trackedX(hardTarget == 1) = target1X(hardTarget == 1);
    trackedY(hardTarget == 1) = target1Y(hardTarget == 1);
    trackedX(hardTarget == 2) = target2X(hardTarget == 2);
    trackedY(hardTarget == 2) = target2Y(hardTarget == 2);
    dTrackedRewardPx = nan(n,1);
    dTrackedRewardPx(hardTarget == 1) = dTarget1RewardPx(hardTarget == 1);
    dTrackedRewardPx(hardTarget == 2) = dTarget2RewardPx(hardTarget == 2);
    dOtherRewardPx = nan(n,1);
    dOtherRewardPx(hardTarget == 1) = dTarget2RewardPx(hardTarget == 1);
    dOtherRewardPx(hardTarget == 2) = dTarget1RewardPx(hardTarget == 2);
    dGazeTrackedPx = hypot(gazeX-trackedX, gazeY-trackedY);
    trackedCloser = nan(n,1);
    validDistancePair = isfinite(dTarget1RewardPx) & isfinite(dTarget2RewardPx);
    trackedCloser(validDistancePair & hardTarget == 1) = double( ...
        dTarget1RewardPx(validDistancePair & hardTarget == 1) <= ...
        dTarget2RewardPx(validDistancePair & hardTarget == 1));
    trackedCloser(validDistancePair & hardTarget == 2) = double( ...
        dTarget2RewardPx(validDistancePair & hardTarget == 2) < ...
        dTarget1RewardPx(validDistancePair & hardTarget == 2));

    [runStarts, runStops] = localRuns(hardTarget);
    episodeNo = 0;
    for run = 1:numel(runStarts)
        first = runStarts(run); last = runStops(run);
        state = hardTarget(first);
        if ~ismember(state, [1 2])
            continue
        end
        durationSec = localDuration(time, first, last);
        if durationSec < opts.minEpisodeSec
            continue
        end
        episodeNo = episodeNo + 1;
        index = first:last;
        pupilValid = isfinite(pupil(index));
        regressorValid = pupilValid & isfinite(dTrackedRewardPx(index)) & ...
            isfinite(dGazeRewardPx(index)) & isfinite(dGazeTrackedPx(index));
        validPupilFrac = mean(pupilValid);
        validRegressorFrac = mean(regressorValid);
        if validPupilFrac < opts.minValidPupilFrac || ~any(regressorValid)
            continue
        end
        pupilValues = pupil(index); pupilValues = pupilValues(pupilValid);
        pupilRawValues = pupilRaw(index); pupilRawValues = pupilRawValues(pupilValid);
        targetRewardDeg = px2deg(dTrackedRewardPx(index(regressorValid)), ex.setup);
        otherTargetRewardDeg = px2deg( ...
            dOtherRewardPx(index(regressorValid)), ex.setup);
        distM = (targetRewardDeg + otherTargetRewardDeg) / 2;
        relativeAdvantage = otherTargetRewardDeg - targetRewardDeg;
        gazeRewardDeg = px2deg(dGazeRewardPx(index(regressorValid)), ex.setup);
        gazeTrackedDeg = px2deg(dGazeTrackedPx(index(regressorValid)), ex.setup);
        gazeXDeg = px2deg(gazeX(index(regressorValid))-screenCenter(1), ex.setup);
        gazeYDeg = px2deg(gazeY(index(regressorValid))-screenCenter(2), ex.setup);
        gazeEccentricityDeg = hypot(gazeXDeg,gazeYDeg);
        radialErrorDeg = gazeRewardDeg - targetRewardDeg;
        closerValues = trackedCloser(index);
        closerValues = closerValues(isfinite(closerValues));
        rows{end+1,1} = table( ... %#ok<AGROW>
            localTrialMonkey(ex), localTrialDate(ex, T), localTrialBlock(T), trialNo, ...
            localTrialOriginalNumber(T, trialNo), episodeNo, state, ...
            localMeanFinite(closerValues), time(first), time(last), durationSec, ...
            numel(index), sum(pupilValid), sum(regressorValid), ...
            validPupilFrac, validRegressorFrac, ...
            mean(pupilValues,'omitnan'), std(pupilValues,0,'omitnan'), ...
            mean(pupilRawValues,'omitnan'), std(pupilRawValues,0,'omitnan'), ...
            localMeanFinite(targetRewardDeg), localStdFinite(targetRewardDeg), ...
            localMeanFinite(otherTargetRewardDeg), ...
            localMeanFinite(distM), localMeanFinite(relativeAdvantage), ...
            localMeanFinite(gazeRewardDeg), localStdFinite(gazeRewardDeg), ...
            localMeanFinite(radialErrorDeg), localStdFinite(radialErrorDeg), ...
            localMeanFinite(gazeTrackedDeg), localStdFinite(gazeTrackedDeg), ...
            localMeanFinite(gazeXDeg), localStdFinite(gazeXDeg), ...
            localMeanFinite(gazeYDeg), localStdFinite(gazeYDeg), ...
            localMeanFinite(gazeEccentricityDeg), ...
            localStdFinite(gazeEccentricityDeg), ...
            localTrialScalar(T, {'backgroundNoiseLvl','background_noise_lvl','background','bg'}), ...
            localTrialScalar(T, {'targetVisibility','target_visibility','visibility','vis','coherence'}), ...
            localTrialSourceFile(T), ...
            'VariableNames', {'monkey','date','block','trial','originalTrialNo', ...
            'episode','trackedTargetId','proportionTrackedCloser', ...
            'episodeStartSec','episodeEndSec','episodeDurationSec', ...
            'nEpisodeSamples','nPupilSamples','nRegressionSamples', ...
            'validPupilFrac','validRegressionFrac','meanPupilZ','sdPupilZ', ...
            'meanPupilRaw','sdPupilRaw', ...
            'meanTrackedTargetRewardDistDeg','sdTrackedTargetRewardDistDeg', ...
            'meanOtherTargetRewardDistDeg','distM','relativeAdvantage', ...
            'meanGazeRewardDistDeg','sdGazeRewardDistDeg', ...
            'meanGazeRadialErrorDeg','sdGazeRadialErrorDeg', ...
            'meanGazeTrackedTargetDistDeg','sdGazeTrackedTargetDistDeg', ...
            'meanGazeXDeg','sdGazeXDeg','meanGazeYDeg','sdGazeYDeg', ...
            'meanGazeEccentricityDeg','sdGazeEccentricityDeg', ...
            'backgroundNoiseLvl','targetVisibility','sourceFile'});
    end
end

if isempty(rows)
    episodeTable = localEmptyTable();
else
    episodeTable = vertcat(rows{:});
end
csvPath = char(string(csvPath));
if logical(opts.writeCsv)
    parent = fileparts(csvPath);
    if ~isempty(parent) && ~isfolder(parent)
        mkdir(parent);
    end
    writetable(episodeTable, csvPath);
    fprintf('exportPupilHmmRegressors: wrote %d episodes to %s\n', ...
        height(episodeTable), csvPath);
end
end


function opts = localFillDefaults(opts, defaults)
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(opts, names{i}) || isempty(opts.(names{i}))
        opts.(names{i}) = defaults.(names{i});
    end
end
end


function [starts, stops] = localRuns(state)
state = double(state(:));
same = (state(2:end) == state(1:end-1)) | ...
    (isnan(state(2:end)) & isnan(state(1:end-1)));
starts = find([true; ~same]);
stops = [starts(2:end)-1; numel(state)];
end


function duration = localDuration(time, first, last)
nearby = time(max(1,first-2):min(numel(time),last+2));
dt = median(diff(nearby),'omitnan');
if ~isfinite(dt) || dt < 0
    dt = 0;
end
duration = max(0, time(last)-time(first)+dt);
end


function value = localMeanFinite(values)
values = double(values(:)); values = values(isfinite(values));
if isempty(values), value = NaN; else, value = mean(values); end
end


function value = localStdFinite(values)
values = double(values(:)); values = values(isfinite(values));
if numel(values) < 2, value = NaN; else, value = std(values,0); end
end


function value = localTrialScalar(T, names)
value = NaN;
for i = 1:numel(names)
    if isfield(T,names{i}) && isnumeric(T.(names{i})) && ...
            isscalar(T.(names{i})) && isfinite(T.(names{i}))
        value = double(T.(names{i})); return
    end
end
end


function value = localTrialBlock(T)
value = localTrialScalar(T, {'sessionInDay','block','blockNo'});
end


function value = localTrialOriginalNumber(T, fallback)
value = localTrialScalar(T, {'originalTrialNo','trialInSession','TrialNo','trialNo'});
if ~isfinite(value), value = fallback; end
end


function value = localTrialDate(ex, T)
value = "";
if isfield(T,'date') && ~isempty(T.date), value = string(T.date); return, end
if isfield(ex,'hmmMeta') && isstruct(ex.hmmMeta) && ...
        isfield(ex.hmmMeta,'date')
    value = string(ex.hmmMeta.date);
elseif isfield(ex,'hmmMeta') && isstruct(ex.hmmMeta) && ...
        isfield(ex.hmmMeta,'dayMerge') && ...
        isfield(ex.hmmMeta.dayMerge,'date')
    value = string(ex.hmmMeta.dayMerge.date);
end
end


function value = localTrialMonkey(ex)
value = "";
if isfield(ex,'hmmMeta') && isstruct(ex.hmmMeta)
    if isfield(ex.hmmMeta,'animal')
        value = string(ex.hmmMeta.animal);
    elseif isfield(ex.hmmMeta,'monkey')
        value = string(ex.hmmMeta.monkey);
    elseif isfield(ex.hmmMeta,'dayMerge') && ...
            isfield(ex.hmmMeta.dayMerge,'animal')
        value = string(ex.hmmMeta.dayMerge.animal);
    end
end
end


function value = localTrialSourceFile(T)
value = "";
if isfield(T,'sourceFileName') && ~isempty(T.sourceFileName)
    value = string(T.sourceFileName);
elseif isfield(T,'sourceFile') && ~isempty(T.sourceFile)
    value = string(T.sourceFile);
end
end


function T = localEmptyTable()
T = table(strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), strings(0,1), ...
    'VariableNames', {'monkey','date','block','trial','originalTrialNo','episode', ...
    'trackedTargetId','proportionTrackedCloser','episodeStartSec', ...
    'episodeEndSec','episodeDurationSec','nEpisodeSamples','nPupilSamples', ...
    'nRegressionSamples','validPupilFrac','validRegressionFrac','meanPupilZ', ...
    'sdPupilZ','meanPupilRaw','sdPupilRaw', ...
    'meanTrackedTargetRewardDistDeg','sdTrackedTargetRewardDistDeg', ...
    'meanOtherTargetRewardDistDeg','distM','relativeAdvantage', ...
    'meanGazeRewardDistDeg','sdGazeRewardDistDeg','meanGazeRadialErrorDeg', ...
    'sdGazeRadialErrorDeg','meanGazeTrackedTargetDistDeg', ...
    'sdGazeTrackedTargetDistDeg', ...
    'meanGazeXDeg','sdGazeXDeg','meanGazeYDeg','sdGazeYDeg', ...
    'meanGazeEccentricityDeg','sdGazeEccentricityDeg', ...
    'backgroundNoiseLvl','targetVisibility', ...
    'sourceFile'});
end
