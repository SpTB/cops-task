function out = pupRew(ex, opts)
% pupRew  Reward-event-locked pupil responses for CoPs sessions.
%
% out = pupRew(ex)
% out = pupRew(ex, opts)
%
% Reward releases are read from ex.Trials(k).times.reward. The function
% resolves whether those timestamps use the absolute experiment clock or are
% already trial-relative by comparing both interpretations with reconstructed
% eye time. Pupil preprocessing matches pupilHmmTransitions: robust session-eye
% z-scoring, outlier rejection, blink padding, short-gap interpolation,
% smoothing, and binocular averaging.
%
% Important options (defaults):
%   .preSec                  1.5
%   .postSec                 3.0
%   .baselineWindowSec      [-1.5 -1.0] ([] = no event baseline)
%   .earlyWindowSec         [0.2 1.0]
%   .lateWindowSec          [1.0 2.5]
%   .minRewardSeparationSec 0.50
%   .blinkPaddingSec        0.10
%   .maxInterpGapSec        0.15
%   .smoothWindowSec        0.10
%   .excludeOutsideScreen   true
%   .screenPaddingPx        0
%   .minBaselineValidFrac   0.70
%   .minEpochValidFrac      0.60
%   .makePlot               true

if nargin < 2 || isempty(opts)
    opts = struct();
end
defaults = struct( ...
    'useEyeTime', true, 'trialList', [], ...
    'preSec', 1.5, 'postSec', 3.0, ...
    'baselineWindowSec', [-1.5 -1.0], ...
    'earlyWindowSec', [0.2 1.0], 'lateWindowSec', [1.0 2.5], ...
    'minRewardSeparationSec', 0.50, ...
    'blinkPaddingSec', 0.10, 'maxInterpGapSec', 0.15, ...
    'smoothWindowSec', 0.10, 'outlierMad', 6, ...
    'excludeOutsideScreen', true, 'screenPaddingPx', 0, ...
    'minBaselineValidFrac', 0.70, 'minEpochValidFrac', 0.60, ...
    'makePlot', true);
opts = localFillDefaults(opts, defaults);
localValidateOptions(opts);

if ~isstruct(ex) || ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('pupRew:BadEx', 'ex must contain ex.Trials.');
end
screenRect = localScreenRect(ex, opts.excludeOutsideScreen);
fs = inferFs(ex);
if ~isfinite(fs) || fs <= 0
    error('pupRew:BadSamplingRate', ...
        'Could not determine a positive eye sampling rate.');
end
trialList = localTrialList(opts.trialList, numel(ex.Trials));
[pupilCenter, pupilScale] = localSessionPupilScale( ...
    ex, trialList, opts, screenRect);
timeSec = (-round(opts.preSec*fs):round(opts.postSec*fs)) ./ fs;

eventRows = repmat(localEmptyEventRow(), 0, 1);
combinedCells = cell(0, 1); leftCells = cell(0, 1);
rightCells = cell(0, 1); rawCells = cell(0, 1);
nRewardsFound = 0; nRejectedSeparation = 0; nRejectedCoverage = 0;
nTrialsWithRewards = 0;
nOutsideScreenSamples = 0;

for trialNo = trialList(:)'
    T = ex.Trials(trialNo);
    [xPx, yPx, tRel, ~, gazeValid] = reconstructEyePx( ...
        ex, T, opts.useEyeTime, opts);
    [leftRaw, rightRaw, leftValid, rightValid] = localRawPupil(T);
    n = min([numel(tRel), numel(leftRaw), numel(rightRaw)]);
    if n < 2
        continue
    end
    tRel = double(tRel(1:n));
    leftRaw = leftRaw(1:n); rightRaw = rightRaw(1:n);
    leftValid = leftValid(1:n); rightValid = rightValid(1:n);
    insideScreen = localInsideScreen(xPx(1:n), yPx(1:n), ...
        gazeValid(1:n), screenRect, opts.screenPaddingPx);
    hardExclude = opts.excludeOutsideScreen & ~insideScreen;
    nOutsideScreenSamples = nOutsideScreenSamples + sum(hardExclude);
    left = localPreprocessPupil(leftRaw, leftValid, ...
        pupilCenter.left, pupilScale.left, fs, opts, hardExclude);
    right = localPreprocessPupil(rightRaw, rightValid, ...
        pupilCenter.right, pupilScale.right, fs, opts, hardExclude);
    combined = localNanMeanPair(left, right);

    [rewardTimes, clockSource] = localRewardTimesRelative(T, tRel);
    if isempty(rewardTimes)
        continue
    end
    nTrialsWithRewards = nTrialsWithRewards + 1;
    nRewardsFound = nRewardsFound + numel(rewardTimes);
    for rewardNo = 1:numel(rewardTimes)
        previousInterval = Inf; nextInterval = Inf;
        if rewardNo > 1
            previousInterval = rewardTimes(rewardNo)-rewardTimes(rewardNo-1);
        end
        if rewardNo < numel(rewardTimes)
            nextInterval = rewardTimes(rewardNo+1)-rewardTimes(rewardNo);
        end
        if min(previousInterval, nextInterval) < opts.minRewardSeparationSec
            nRejectedSeparation = nRejectedSeparation + 1;
            continue
        end
        eventTime = rewardTimes(rewardNo);
        queryTime = eventTime + timeSec;
        combinedRaw = interp1(tRel, combined, queryTime, 'linear', NaN);
        leftEpoch = interp1(tRel, left, queryTime, 'linear', NaN);
        rightEpoch = interp1(tRel, right, queryTime, 'linear', NaN);
        useBaseline = ~isempty(opts.baselineWindowSec);
        if useBaseline
            baselineMask = localWindowMask(timeSec, opts.baselineWindowSec);
            baselineCoverage = mean(isfinite(combinedRaw(baselineMask)));
        else
            baselineMask = false(size(timeSec));
            baselineCoverage = 1;
        end
        if baselineCoverage < opts.minBaselineValidFrac || ...
                mean(isfinite(combinedRaw)) < opts.minEpochValidFrac
            nRejectedCoverage = nRejectedCoverage + 1;
            continue
        end
        if useBaseline
            combinedBaseline = mean(combinedRaw(baselineMask), 'omitnan');
            combinedEpoch = combinedRaw - combinedBaseline;
            leftEpoch = leftEpoch - mean(leftEpoch(baselineMask), 'omitnan');
            rightEpoch = rightEpoch - mean(rightEpoch(baselineMask), 'omitnan');
        else
            combinedBaseline = NaN;
            combinedEpoch = combinedRaw;
        end

        responseMask = localWindowMask( ...
            timeSec, [opts.earlyWindowSec(1), opts.lateWindowSec(2)]);
        row = localEmptyEventRow();
        row.trial = trialNo; row.rewardNo = rewardNo;
        row.rewardTimeRelSec = eventTime;
        row.rewardClockSource = clockSource;
        row.previousRewardIntervalSec = previousInterval;
        row.nextRewardIntervalSec = nextInterval;
        row.backgroundNoiseLvl = localTrialScalar(T, ...
            {'backgroundNoiseLvl','background','bg'});
        row.targetVisibility = localTrialScalar(T, ...
            {'targetVisibility','visibility','vis'});
        row.targetNum = localTrialScalar(T, {'targetNum','nTargets'});
        row.baselinePupilZ = combinedBaseline;
        row.earlyPupilChangeZ = localWindowMean( ...
            combinedEpoch, timeSec, opts.earlyWindowSec);
        row.latePupilChangeZ = localWindowMean( ...
            combinedEpoch, timeSec, opts.lateWindowSec);
        row.peakPostPupilChangeZ = max( ...
            combinedEpoch(responseMask), [], 'omitnan');
        row.troughPostPupilChangeZ = min( ...
            combinedEpoch(responseMask), [], 'omitnan');
        row.validEpochFrac = mean(isfinite(combinedRaw));
        eventRows(end+1, 1) = row; %#ok<AGROW>
        combinedCells{end+1, 1} = combinedEpoch; %#ok<AGROW>
        leftCells{end+1, 1} = leftEpoch; %#ok<AGROW>
        rightCells{end+1, 1} = rightEpoch; %#ok<AGROW>
        rawCells{end+1, 1} = combinedRaw; %#ok<AGROW>
    end
end

if isempty(eventRows)
    events = struct2table(localEmptyEventRow()); events(1,:) = [];
    combined = nan(0, numel(timeSec)); left = combined;
    right = combined; combinedRaw = combined;
else
    events = struct2table(eventRows);
    combined = vertcat(combinedCells{:}); left = vertcat(leftCells{:});
    right = vertcat(rightCells{:}); combinedRaw = vertcat(rawCells{:});
end
summary = localSummary(events);
figureHandle = [];
if opts.makePlot
    figureHandle = localPlot(timeSec, combined, opts, height(events));
end
out = struct();
out.events = events; out.timeSec = timeSec(:)';
out.traces = struct('combined', combined, 'left', left, 'right', right, ...
    'combinedUncorrectedZ', combinedRaw);
out.summary = summary; out.figure = figureHandle; out.opts = opts;
out.meta = struct('samplingRateHz', fs, 'pupilChannelRight', 3, ...
    'pupilChannelLeft', 6, 'pupilCenter', pupilCenter, ...
    'pupilScale', pupilScale, ...
    'excludeOutsideScreen', opts.excludeOutsideScreen, ...
    'screenRectPx', screenRect, 'screenPaddingPx', opts.screenPaddingPx, ...
    'nOutsideScreenSamplesExcluded', nOutsideScreenSamples, ...
    'nTrialsRequested', numel(trialList), ...
    'nTrialsWithRewards', nTrialsWithRewards, ...
    'nRewardsFound', nRewardsFound, ...
    'nRejectedRewardSeparation', nRejectedSeparation, ...
    'nRejectedPupilCoverage', nRejectedCoverage, ...
    'nEventsRetained', height(events));
end


function opts = localFillDefaults(opts, defaults)
names = fieldnames(defaults);
for i = 1:numel(names)
    allowEmpty = strcmp(names{i}, 'baselineWindowSec');
    if ~isfield(opts, names{i}) || ...
            (isempty(opts.(names{i})) && ~allowEmpty)
        opts.(names{i}) = defaults.(names{i});
    end
end
end


function localValidateOptions(opts)
if opts.preSec <= 0 || opts.postSec <= 0
    error('pupRew:BadEpoch', 'preSec and postSec must be positive.');
end
if ~(isscalar(opts.excludeOutsideScreen) && ...
        (islogical(opts.excludeOutsideScreen) || isnumeric(opts.excludeOutsideScreen)) && ...
        isfinite(double(opts.excludeOutsideScreen)) && ...
        ismember(double(opts.excludeOutsideScreen), [0 1]))
    error('pupRew:BadScreenOption', ...
        'excludeOutsideScreen must be logical or 0/1.');
end
if ~(isscalar(opts.screenPaddingPx) && isnumeric(opts.screenPaddingPx) && ...
        isfinite(opts.screenPaddingPx) && opts.screenPaddingPx >= 0)
    error('pupRew:BadScreenPadding', ...
        'screenPaddingPx must be a finite nonnegative scalar.');
end
for name = {'baselineWindowSec','earlyWindowSec','lateWindowSec'}
    value = opts.(name{1});
    if strcmp(name{1}, 'baselineWindowSec') && isempty(value), continue; end
    if numel(value) ~= 2 || any(~isfinite(value)) || value(2) <= value(1) || ...
            value(1) < -opts.preSec || value(2) > opts.postSec
        error('pupRew:BadWindow', ...
            '%s must be an increasing pair inside the epoch.', name{1});
    end
end
if ~isscalar(opts.minRewardSeparationSec) || ...
        ~isfinite(opts.minRewardSeparationSec) || opts.minRewardSeparationSec < 0
    error('pupRew:BadSeparation', ...
        'minRewardSeparationSec must be a finite nonnegative scalar.');
end
end


function trials = localTrialList(requested, nTrials)
if isempty(requested)
    trials = 1:nTrials;
else
    trials = unique(double(requested(:)'));
    if any(~isfinite(trials) | trials ~= round(trials) | ...
            trials < 1 | trials > nTrials)
        error('pupRew:BadTrialList', ...
            'trialList must contain valid integer trial numbers.');
    end
end
end


function [times, source] = localRewardTimesRelative(T, tRel)
times = []; source = "missing";
if ~isfield(T, 'times') || ~isfield(T.times, 'reward') || ...
        isempty(T.times.reward)
    return
end
raw = double(T.times.reward(:)); raw = raw(isfinite(raw));
if isempty(raw), return; end
relative = raw; absolute = nan(size(raw));
if isfield(T, 'TrialStart') && isscalar(T.TrialStart) && ...
        isfinite(T.TrialStart)
    absolute = raw - double(T.TrialStart);
end
lower = min(tRel, [], 'omitnan'); upper = max(tRel, [], 'omitnan');
scoreRelative = sum(relative >= lower & relative <= upper);
scoreAbsolute = sum(absolute >= lower & absolute <= upper);
if scoreAbsolute > scoreRelative || ...
        (scoreAbsolute == scoreRelative && scoreAbsolute > 0 && ...
        median(abs(absolute), 'omitnan') < median(abs(relative), 'omitnan'))
    times = absolute; source = "absolute-minus-TrialStart";
else
    times = relative; source = "already-relative";
end
times = sort(times(isfinite(times) & times >= lower & times <= upper));
end


function [center, scale] = localSessionPupilScale(ex, trials, opts, screenRect)
leftAll = zeros(0,1); rightAll = zeros(0,1);
for trial = trials(:)'
    T = ex.Trials(trial);
    [left, right, leftValid, rightValid] = localRawPupil(T);
    if opts.excludeOutsideScreen
        [xPx, yPx, ~, ~, gazeValid] = reconstructEyePx( ...
            ex, T, opts.useEyeTime, opts);
        n = min([numel(left), numel(right), numel(xPx), numel(yPx)]);
        left = left(1:n); right = right(1:n);
        leftValid = leftValid(1:n); rightValid = rightValid(1:n);
        insideScreen = localInsideScreen(xPx(1:n), yPx(1:n), ...
            gazeValid(1:n), screenRect, opts.screenPaddingPx);
        leftValid = leftValid & insideScreen;
        rightValid = rightValid & insideScreen;
    end
    leftAll = [leftAll; left(leftValid)]; %#ok<AGROW>
    rightAll = [rightAll; right(rightValid)]; %#ok<AGROW>
end
[center.left, scale.left] = localRobustLocationScale(leftAll, opts.outlierMad);
[center.right, scale.right] = localRobustLocationScale(rightAll, opts.outlierMad);
end


function [center, scale] = localRobustLocationScale(values, outlierMad)
values = double(values(:)); values = values(isfinite(values));
if isempty(values), center = NaN; scale = NaN; return; end
center = median(values); scale = 1.4826*median(abs(values-center));
if ~isfinite(scale) || scale <= 0, scale = std(values, 'omitnan'); end
if ~isfinite(scale) || scale <= 0, scale = 1; end
keep = abs(values-center) <= outlierMad*scale;
if any(keep)
    center = median(values(keep));
    scale2 = 1.4826*median(abs(values(keep)-center));
    if isfinite(scale2) && scale2 > 0, scale = scale2; end
end
end


function [left, right, leftValid, rightValid] = localRawPupil(T)
left = zeros(0,1); right = zeros(0,1);
leftValid = false(0,1); rightValid = false(0,1);
if ~isfield(T,'Eye') || ~isfield(T.Eye,'v') || isempty(T.Eye.v), return; end
V = double(T.Eye.v); n = size(V,2);
if isfield(T.Eye,'n') && isscalar(T.Eye.n) && isfinite(T.Eye.n) && ...
        T.Eye.n > 0 && T.Eye.n <= n
    n = double(T.Eye.n);
end
V = V(:,1:n); right = nan(n,1); left = nan(n,1);
rightValid = false(n,1); leftValid = false(n,1);
if size(V,1) >= 3
    right = V(3,:)'; rightValid = isfinite(right);
    if size(V,1) >= 2
        rightValid = rightValid & isfinite(V(1,:)') & isfinite(V(2,:)');
    end
end
if size(V,1) >= 6
    left = V(6,:)';
    leftValid = isfinite(left) & isfinite(V(4,:)') & isfinite(V(5,:)');
end
end


function pupil = localPreprocessPupil( ...
        raw, valid, center, scale, fs, opts, hardExclude)
raw = double(raw(:)); valid = logical(valid(:)) & isfinite(raw);
if nargin < 7 || isempty(hardExclude)
    hardExclude = false(size(raw));
else
    hardExclude = logical(hardExclude(:));
end
if numel(hardExclude) ~= numel(raw)
    error('pupRew:ScreenMaskSize', ...
        'The screen mask must match the pupil trace length.');
end
if isfinite(center) && isfinite(scale) && scale > 0
    valid = valid & abs(raw-center) <= opts.outlierMad*scale;
else
    valid(:) = false;
end
padding = max(0,round(opts.blinkPaddingSec*fs));
if padding > 0
    expanded = conv(double(~valid),ones(2*padding+1,1),'same') > 0;
    valid(expanded) = false;
end
pupil = nan(size(raw)); pupil(valid) = (raw(valid)-center)./scale;
pupil = localInterpolateShortGaps(pupil,round(opts.maxInterpGapSec*fs));
pupil(hardExclude) = NaN;
pupil = localNanMovingAverage(pupil,max(1,round(opts.smoothWindowSec*fs)));
pupil(hardExclude) = NaN;
end


function rect = localScreenRect(ex, required)
rect = [];
if isfield(ex, 'setup') && isfield(ex.setup, 'screenRect') && ...
        numel(ex.setup.screenRect) >= 4
    candidate = double(ex.setup.screenRect(1:4));
    if all(isfinite(candidate)) && candidate(3) > candidate(1) && ...
            candidate(4) > candidate(2)
        rect = candidate;
    end
end
if logical(required) && isempty(rect)
    error('pupRew:MissingScreenRect', ...
        ['opts.excludeOutsideScreen=true requires a valid ' ...
         'ex.setup.screenRect. Set the option false only for legacy data.']);
end
end


function inside = localInsideScreen(xPx, yPx, gazeValid, rect, paddingPx)
xPx = double(xPx(:)); yPx = double(yPx(:));
gazeValid = logical(gazeValid(:));
if isempty(rect)
    inside = gazeValid & isfinite(xPx) & isfinite(yPx);
    return
end
inside = gazeValid & isfinite(xPx) & isfinite(yPx) & ...
    xPx >= rect(1) - paddingPx & xPx <= rect(3) + paddingPx & ...
    yPx >= rect(2) - paddingPx & yPx <= rect(4) + paddingPx;
end


function values = localInterpolateShortGaps(values, maxGap)
if maxGap < 1 || numel(values) < 3, return; end
missing = ~isfinite(values); edges = diff([false; missing; false]);
starts = find(edges==1); stops = find(edges==-1)-1;
for i = 1:numel(starts)
    a = starts(i); b = stops(i);
    if b-a+1 <= maxGap && a > 1 && b < numel(values) && ...
            isfinite(values(a-1)) && isfinite(values(b+1))
        values(a:b) = interp1([a-1 b+1],[values(a-1) values(b+1)], ...
            a:b,'linear');
    end
end
end


function output = localNanMovingAverage(values, window)
kernel = ones(max(1,round(window)),1); valid = isfinite(values);
filled = values; filled(~valid) = 0;
denominator = conv(double(valid),kernel,'same');
output = conv(filled,kernel,'same')./denominator;
output(denominator==0) = NaN;
end


function output = localNanMeanPair(first, second)
validFirst = isfinite(first); validSecond = isfinite(second);
count = double(validFirst)+double(validSecond);
first(~validFirst)=0; second(~validSecond)=0;
output=(first+second)./count; output(count==0)=NaN;
end


function value = localTrialScalar(T, names)
value = NaN;
for i = 1:numel(names)
    if isfield(T,names{i}) && isnumeric(T.(names{i})) && ...
            isscalar(T.(names{i})) && isfinite(T.(names{i}))
        value = double(T.(names{i})); return
    end
end
if isfield(T,'params') && isstruct(T.params)
    for i = 1:numel(names)
        if isfield(T.params,names{i}) && isnumeric(T.params.(names{i})) && ...
                isscalar(T.params.(names{i})) && isfinite(T.params.(names{i}))
            value = double(T.params.(names{i})); return
        end
    end
end
end


function row = localEmptyEventRow()
row = struct('trial',NaN,'rewardNo',NaN,'rewardTimeRelSec',NaN, ...
    'rewardClockSource',"",'previousRewardIntervalSec',NaN, ...
    'nextRewardIntervalSec',NaN,'backgroundNoiseLvl',NaN, ...
    'targetVisibility',NaN,'targetNum',NaN,'baselinePupilZ',NaN, ...
    'earlyPupilChangeZ',NaN,'latePupilChangeZ',NaN, ...
    'peakPostPupilChangeZ',NaN,'troughPostPupilChangeZ',NaN, ...
    'validEpochFrac',NaN);
end


function mask = localWindowMask(time, window)
mask = time >= window(1) & time <= window(2);
end


function value = localWindowMean(trace, time, window)
value = mean(trace(localWindowMask(time,window)),'omitnan');
end


function summary = localSummary(events)
if isempty(events)
    summary = table(0,NaN,NaN,NaN,NaN, ...
        'VariableNames',{'nRewards','earlyPupilChangeZ', ...
        'latePupilChangeZ','peakPostPupilChangeZ','troughPostPupilChangeZ'});
    return
end
summary = table(height(events), ...
    mean(events.earlyPupilChangeZ,'omitnan'), ...
    mean(events.latePupilChangeZ,'omitnan'), ...
    mean(events.peakPostPupilChangeZ,'omitnan'), ...
    mean(events.troughPostPupilChangeZ,'omitnan'), ...
    'VariableNames',{'nRewards','earlyPupilChangeZ', ...
    'latePupilChangeZ','peakPostPupilChangeZ','troughPostPupilChangeZ'});
end


function figureHandle = localPlot(time, traces, opts, nEvents)
figureHandle = figure('Color','w','Name','Reward-locked pupil response');
hold on
if ~isempty(traces)
    average = mean(traces,1,'omitnan');
    count = sum(isfinite(traces),1);
    sem = std(traces,0,1,'omitnan')./sqrt(max(count,1));
    fill([time fliplr(time)],[average-sem fliplr(average+sem)], ...
        [0.20 0.55 0.25],'FaceAlpha',0.18,'EdgeColor','none');
    plot(time,average,'Color',[0.10 0.45 0.18],'LineWidth',2);
end
xline(0,'k--','Reward'); yline(0,'Color',[.55 .55 .55]);
xlabel('Time from reward release (s)');
if isempty(opts.baselineWindowSec)
    ylabel('Pupil size (session-eye SD)'); baselineLabel = 'no event baseline';
else
    ylabel('\Delta pupil (session-eye SD)');
    baselineLabel = sprintf('baseline [%g, %g] s',opts.baselineWindowSec);
end
title(sprintf('Reward-locked pupil response; %s; n=%d rewards', ...
    baselineLabel,nEvents)); grid on
end
