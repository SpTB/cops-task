function out = plotGazeRewDistDays(subject, dateFrom, dateTo, opts)
% plotGazeRewDistDays  Average reward-distance learning across reward sessions.
%
%   A = plotGazeRewDistDays('ly', 'Jul1')
%   A = plotGazeRewDistDays('ly', '2026.07.01', '2026.07.29')
%   A = plotGazeRewDistDays('ly', 'Jul1', opts)
%
% dateTo defaults to the newest available date for the animal. An analysis
% session is a contiguous run of trials with one reward-center location;
% MAT-file boundaries alone do not start a new session. Curves are aligned
% by trial within reward-center session and averaged with equal session
% weight. By default, the plot shows the mean median-gaze distance together
% with the mean reward-closer and random-target reference distances.
%
% Main options:
%   dataRoot               CoPs data root (auto-detected when possible)
%   includeTrials          exDay phase selection (default 'main+pre')
%   windowTrials           rolling trials within reward session (default 20)
%   stepTrials             rolling-window step (default 5)
%   minRewardSessionTrials minimum selected trials in a reward session
%   rewardCenterToleranceNorm tolerance for center changes (default 1e-6)
%   minSessionsPerPoint    minimum sessions plotted in an average (default 2)
%   aggregateBinTrials     alignment-bin width (default stepTrials)
%   includePartialWindows  allow shortened end windows (default false)
%   diff                   plot controlled difference (default false)
%   showSessions           show individual reward-session curves (default true)
%   showSem                draw mean +/- SEM ribbon (default true)
%   trajectoryOpts         extra options passed to gazeHeatTrajectory

if nargin < 1 || isempty(subject)
    error('plotGazeRewDistDays:MissingSubject', ...
        'Provide an animal, e.g. plotGazeRewDistDays(''ly'', ''Jul1'').');
end
if nargin < 2
    dateFrom = [];
end
if nargin < 3
    dateTo = [];
end
if nargin < 4 || isempty(opts)
    opts = struct();
elseif ~isstruct(opts)
    error('plotGazeRewDistDays:BadOpts', 'opts must be a struct.');
end
if isstruct(dateTo)
    opts = localMergeStructs(dateTo, opts);
    dateTo = [];
end
if isstruct(dateFrom)
    opts = localMergeStructs(dateFrom, opts);
    dateFrom = [];
end

opts = localDefaults(opts);
subject = localResolveSubject(subject, opts.dataRoot);
availableDates = localAvailableDates(fullfile(char(opts.dataRoot), char(subject)));
if isempty(availableDates)
    error('plotGazeRewDistDays:NoDates', ...
        'No YYYY.MM.DD folders found for %s under %s.', subject, opts.dataRoot);
end
if isempty(dateFrom)
    firstDate = availableDates(1);
else
    firstDate = localParseDate(dateFrom);
end
if isempty(dateTo)
    lastDate = availableDates(end);
else
    lastDate = localParseDate(dateTo);
end
if lastDate < firstDate
    error('plotGazeRewDistDays:BadDateRange', 'dateTo precedes dateFrom.');
end
dates = availableDates(availableDates >= firstDate & availableDates <= lastDate);
if isempty(dates)
    error('plotGazeRewDistDays:NoDatesInRange', ...
        'No available dates fall within %s to %s.', ...
        datestr(firstDate, 'yyyy.mm.dd'), datestr(lastDate, 'yyyy.mm.dd'));
end

windowTables = {};
sessionRows = localEmptySessionRows();
globalSession = 0;
for iDate = 1:numel(dates)
    dayDate = dates(iDate);
    exOpts = struct('subject', subject, 'dataRoot', opts.dataRoot, ...
        'includeTrials', opts.includeTrials, 'minTrialNum', opts.minTrialNum);
    try
        ex = exDay(dayDate, exOpts);
    catch err
        sessionRows = localAppendFailure(sessionRows, subject, dayDate, err);
        if opts.verbose
            warning('plotGazeRewDistDays:DaySkipped', ...
                'Skipped %s: %s', datestr(dayDate, 'yyyy.mm.dd'), err.message);
        end
        continue
    end

    centers = localRewardCenterNormByTrial(ex);
    rewardRuns = localContiguousRewardRuns(centers, opts.rewardCenterToleranceNorm);
    for iRun = 1:numel(rewardRuns)
        trialList = rewardRuns(iRun).trialStart:rewardRuns(iRun).trialStop;
        globalSession = globalSession + 1;
        row = localInitSessionRow(subject, dayDate, globalSession, iRun, ...
            trialList, rewardRuns(iRun).centerNorm, ex);
        if numel(trialList) < opts.minRewardSessionTrials
            row.status = "too_few_trials";
            row.message = "reward session shorter than minRewardSessionTrials";
            sessionRows(end+1) = row; %#ok<AGROW>
            continue
        end
        try
            T = gazeHeatTrajectory(ex, trialList, opts.trajectoryOpts);
        catch err
            row.status = "analysis_failed";
            row.message = string(err.message);
            sessionRows(end+1) = row; %#ok<AGROW>
            continue
        end
        row.nSelectedTrials = numel(T.trials);
        if row.nSelectedTrials < opts.minRewardSessionTrials || isempty(T.summary)
            row.status = "too_few_selected_trials";
            row.message = "too few trajectory-selected trials";
            sessionRows(end+1) = row; %#ok<AGROW>
            continue
        end

        S = T.summary;
        ok = strcmp(string(S.status), "ok") ...
            & isfinite(S.medianDistToRewardDeg) ...
            & isfinite(S.rewardCloserTargetDistDeg) ...
            & isfinite(S.randomTargetDistDeg);
        S = S(ok, :);
        if isempty(S)
            row.status = "no_valid_windows";
            row.message = "trajectory contained no valid distance windows";
            sessionRows(end+1) = row; %#ok<AGROW>
            continue
        end
        n = height(S);
        sessionTrialStart = double(S.trialStart) - trialList(1) + 1;
        sessionTrialStop = double(S.trialStop) - trialList(1) + 1;
        sessionTrialCenter = mean([sessionTrialStart, sessionTrialStop], 2);
        meta = table( ...
            repmat(globalSession, n, 1), repmat(iRun, n, 1), ...
            repmat(dayDate, n, 1), repmat(string(subject), n, 1), ...
            sessionTrialStart, sessionTrialStop, sessionTrialCenter, ...
            S.medianDistToRewardDeg - S.rewardCloserTargetDistDeg, ...
            'VariableNames', {'rewardSession','rewardSessionInDay','date','subject', ...
            'sessionTrialStart','sessionTrialStop','sessionTrialCenter', ...
            'excessDistToRewardDeg'});
        windowTables{end+1, 1} = [meta, S]; %#ok<AGROW>
        row.status = "included";
        row.message = "";
        row.nWindows = n;
        sessionRows(end+1) = row; %#ok<AGROW>
        if opts.verbose
            fprintf('Included reward session %d: %s, %d trials, center [%.4f %.4f]\n', ...
                globalSession, datestr(dayDate, 'yyyy.mm.dd'), row.nSelectedTrials, ...
                row.rewardCenterXNorm, row.rewardCenterYNorm);
        end
    end
end

if isempty(windowTables)
    windowTable = table();
    meanTable = table();
    plotHandles = struct();
    warning('plotGazeRewDistDays:NoIncludedSessions', ...
        'No reward-center sessions produced valid trajectory windows.');
else
    windowTable = vertcat(windowTables{:});
    meanTable = localAggregateWindows(windowTable, opts);
    plotHandles = localPlot(windowTable, meanTable, opts);
end

out = struct();
out.subject = string(subject);
out.dateFrom = firstDate;
out.dateTo = lastDate;
out.availableDates = dates(:);
out.sessionTable = struct2table(sessionRows);
out.windowTable = windowTable;
out.meanTable = meanTable;
out.plot = plotHandles;
out.options = opts;
out.definition = "one session = one contiguous reward-center location within a day";
end


function opts = localDefaults(opts)
defaultRoot = "/media/vpixx/DATA/CoPs";
if exist('Y:\data\CoPs', 'dir')
    defaultRoot = "Y:\data\CoPs";
end
defaults = struct( ...
    'dataRoot', defaultRoot, ...
    'includeTrials', 'main+pre', ...
    'minTrialNum', 1, ...
    'windowTrials', 20, ...
    'stepTrials', 5, ...
    'minRewardSessionTrials', [], ...
    'rewardCenterToleranceNorm', 1e-6, ...
    'minSessionsPerPoint', 2, ...
    'aggregateBinTrials', [], ...
    'includePartialWindows', false, ...
    'diff', false, ...
    'showSessions', true, ...
    'showSem', true, ...
    'newFigure', true, ...
    'sessionColor', [0.72 0.72 0.72], ...
    'meanColor', [0.85 0.33 0.10], ...
    'closerColor', [0 0 0], ...
    'randomColor', [0.35 0.35 0.35], ...
    'closerLineStyle', ':', ...
    'randomLineStyle', '--', ...
    'sessionLineWidth', 0.7, ...
    'meanLineWidth', 2.5, ...
    'trajectoryOpts', struct(), ...
    'verbose', true);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(opts, names{i}) || isempty(opts.(names{i}))
        opts.(names{i}) = defaults.(names{i});
    end
end
opts.windowTrials = max(1, round(double(opts.windowTrials(1))));
opts.stepTrials = max(1, round(double(opts.stepTrials(1))));
if isempty(opts.minRewardSessionTrials)
    opts.minRewardSessionTrials = opts.windowTrials;
else
    opts.minRewardSessionTrials = max(1, round(double(opts.minRewardSessionTrials(1))));
end
opts.minSessionsPerPoint = max(1, round(double(opts.minSessionsPerPoint(1))));
if isempty(opts.aggregateBinTrials)
    opts.aggregateBinTrials = opts.stepTrials;
else
    opts.aggregateBinTrials = max(1, double(opts.aggregateBinTrials(1)));
end
if ~isstruct(opts.trajectoryOpts)
    error('plotGazeRewDistDays:BadTrajectoryOpts', 'trajectoryOpts must be a struct.');
end
opts.trajectoryOpts.windowTrials = opts.windowTrials;
opts.trajectoryOpts.stepTrials = opts.stepTrials;
opts.trajectoryOpts.includePartialWindows = logical(opts.includePartialWindows(1));
end


function subject = localResolveSubject(subject, dataRoot)
subject = lower(strtrim(string(subject)));
switch subject
    case {"ka", "kaki"}
        subject = "kaki";
    case {"ly", "lychee"}
        subject = "lychee";
end
subjectDir = fullfile(char(dataRoot), char(subject));
if ~exist(subjectDir, 'dir')
    error('plotGazeRewDistDays:SubjectNotFound', ...
        'Subject directory not found: %s', subjectDir);
end
end


function dates = localAvailableDates(subjectDir)
raw = dir(subjectDir);
raw = raw([raw.isdir]);
dates = NaT(0, 1);
for i = 1:numel(raw)
    token = regexp(raw(i).name, '^\d{4}\.\d{2}\.\d{2}', 'match', 'once');
    if isempty(token)
        continue
    end
    try
        dates(end+1, 1) = datetime(token, 'InputFormat', 'yyyy.MM.dd'); %#ok<AGROW>
    catch
    end
end
dates = unique(sort(dates));
end


function d = localParseDate(value)
if isdatetime(value)
    d = datetime(year(value), month(value), day(value));
    return
end
s = strtrim(char(string(value)));
try
    d = datetime(s, 'InputFormat', 'yyyy.MM.dd');
    return
catch
end
tok = regexp(lower(s), ...
    '^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s*([0-9]{1,2})$', ...
    'tokens', 'once');
if isempty(tok)
    error('plotGazeRewDistDays:BadDate', ...
        'Date must be datetime, ''YYYY.MM.DD'', or shorthand like ''Jul3''.');
end
months = struct('jan',1,'feb',2,'mar',3,'apr',4,'may',5,'jun',6, ...
    'jul',7,'aug',8,'sep',9,'oct',10,'nov',11,'dec',12);
d = datetime(year(datetime('today')), months.(tok{1}), str2double(tok{2}));
end


function centers = localRewardCenterNormByTrial(ex)
nTrials = numel(ex.Trials);
centers = NaN(nTrials, 2);
for i = 1:nTrials
    T = ex.Trials(i);
    if isfield(T, 'gaussRewardCenterNorm') && isnumeric(T.gaussRewardCenterNorm) ...
            && numel(T.gaussRewardCenterNorm) >= 2 ...
            && all(isfinite(T.gaussRewardCenterNorm(1:2)))
        centers(i, :) = double(T.gaussRewardCenterNorm(1:2));
    elseif isfield(T, 'gaussRewardCenterPx') && isnumeric(T.gaussRewardCenterPx) ...
            && numel(T.gaussRewardCenterPx) >= 2 ...
            && all(isfinite(T.gaussRewardCenterPx(1:2)))
        % Pixel values are used only as stable location identifiers when
        % normalized coordinates are unavailable.
        centers(i, :) = double(T.gaussRewardCenterPx(1:2));
    end
end
end


function runs = localContiguousRewardRuns(centers, tolerance)
runs = struct('trialStart', {}, 'trialStop', {}, 'centerNorm', {});
currentStart = NaN;
currentCenter = [NaN NaN];
for i = 1:size(centers, 1)
    center = centers(i, :);
    valid = all(isfinite(center));
    changed = valid && (~all(isfinite(currentCenter)) ...
        || norm(center - currentCenter) > tolerance);
    if (~valid || changed) && isfinite(currentStart)
        runs(end+1) = struct('trialStart', currentStart, ... %#ok<AGROW>
            'trialStop', i - 1, 'centerNorm', currentCenter);
        currentStart = NaN;
        currentCenter = [NaN NaN];
    end
    if valid && ~isfinite(currentStart)
        currentStart = i;
        currentCenter = center;
    end
end
if isfinite(currentStart)
    runs(end+1) = struct('trialStart', currentStart, ...
        'trialStop', size(centers, 1), 'centerNorm', currentCenter);
end
end


function row = localInitSessionRow(subject, dayDate, globalSession, sessionInDay, trialList, center, ex)
sourceFiles = strings(0, 1);
for i = trialList
    T = ex.Trials(i);
    if isfield(T, 'sourceFileName')
        sourceFiles(end+1, 1) = string(T.sourceFileName); %#ok<AGROW>
    end
end
sourceFiles = unique(sourceFiles(sourceFiles ~= ""), 'stable');
row = localBlankSessionRow();
row.subject = string(subject);
row.date = dayDate;
row.rewardSession = globalSession;
row.rewardSessionInDay = sessionInDay;
row.rewardCenterXNorm = center(1);
row.rewardCenterYNorm = center(2);
row.dayTrialStart = trialList(1);
row.dayTrialStop = trialList(end);
row.nRawTrials = numel(trialList);
row.sourceFiles = strjoin(sourceFiles, " | ");
end


function rows = localEmptySessionRows()
rows = repmat(localBlankSessionRow(), 0, 1);
end


function row = localBlankSessionRow()
row = struct('subject', "", 'date', NaT, 'rewardSession', NaN, ...
    'rewardSessionInDay', NaN, 'rewardCenterXNorm', NaN, ...
    'rewardCenterYNorm', NaN, 'dayTrialStart', NaN, 'dayTrialStop', NaN, ...
    'nRawTrials', NaN, 'nSelectedTrials', NaN, 'nWindows', 0, ...
    'sourceFiles', "", 'status', "", 'message', "");
end


function rows = localAppendFailure(rows, subject, dayDate, err)
row = localBlankSessionRow();
row.subject = string(subject);
row.date = dayDate;
row.status = "day_failed";
row.message = string(err.message);
rows(end+1) = row;
end


function M = localAggregateWindows(S, opts)
nominalFirstCenter = (opts.windowTrials + 1) ./ 2;
binIndex = round((double(S.sessionTrialCenter) - nominalFirstCenter) ...
    ./ opts.aggregateBinTrials);
S.aggregateTrialCenter = nominalFirstCenter + binIndex .* opts.aggregateBinTrials;

% Collapse any duplicate windows within a session/bin before averaging so
% every reward-center session has equal weight at each learning exposure.
sessionIds = unique(double(S.rewardSession));
sessionBinRows = NaN(0, 8);
for iSession = 1:numel(sessionIds)
    inSession = double(S.rewardSession) == sessionIds(iSession);
    centers = unique(double(S.aggregateTrialCenter(inSession)));
    for iCenter = 1:numel(centers)
        use = inSession & abs(double(S.aggregateTrialCenter) - centers(iCenter)) < 1e-9;
        sessionBinRows(end+1, :) = [sessionIds(iSession), centers(iCenter), ... %#ok<AGROW>
            mean(double(S.medianDistToRewardDeg(use)), 'omitnan'), ...
            mean(double(S.rewardCloserTargetDistDeg(use)), 'omitnan'), ...
            mean(double(S.randomTargetDistDeg(use)), 'omitnan'), ...
            mean(double(S.excessDistToRewardDeg(use)), 'omitnan'), ...
            min(double(S.sessionTrialStart(use))), max(double(S.sessionTrialStop(use)))];
    end
end
xValues = unique(sessionBinRows(:, 2));
rows = NaN(numel(xValues), 12);
for i = 1:numel(xValues)
    use = abs(sessionBinRows(:, 2) - xValues(i)) < 1e-9;
    gaze = sessionBinRows(use, 3);
    closer = sessionBinRows(use, 4);
    random = sessionBinRows(use, 5);
    excess = sessionBinRows(use, 6);
    rows(i, :) = [xValues(i), nnz(use), mean(gaze, 'omitnan'), ...
        localSem(gaze), mean(closer, 'omitnan'), localSem(closer), ...
        mean(random, 'omitnan'), localSem(random), ...
        mean(excess, 'omitnan'), localSem(excess), ...
        min(sessionBinRows(use, 7)), max(sessionBinRows(use, 8))];
end
M = array2table(rows, 'VariableNames', {'sessionTrialCenter','nSessions', ...
    'meanGazeDistDeg','semGazeDistDeg','meanCloserTargetDistDeg', ...
    'semCloserTargetDistDeg','meanRandomTargetDistDeg', ...
    'semRandomTargetDistDeg','meanExcessDistDeg','semExcessDistDeg', ...
    'sessionTrialStart','sessionTrialStop'});
M = M(M.nSessions >= opts.minSessionsPerPoint, :);
end


function value = localSem(x)
x = x(isfinite(x));
if numel(x) < 2
    value = NaN;
else
    value = std(x, 0) ./ sqrt(numel(x));
end
end


function handles = localPlot(S, M, opts)
if opts.newFigure
    handles.figure = figure;
else
    handles.figure = gcf;
end
handles.axes = gca;
ax = handles.axes;
wasHeld = ishold(ax);
hold(ax, 'on');
handles.sessions = gobjects(0, 1);
if opts.showSessions
    sessionIds = unique(double(S.rewardSession));
    for i = 1:numel(sessionIds)
        use = double(S.rewardSession) == sessionIds(i);
        [x, order] = sort(double(S.sessionTrialCenter(use)));
        if opts.diff
            y = double(S.excessDistToRewardDeg(use));
        else
            y = double(S.medianDistToRewardDeg(use));
        end
        y = y(order);
        h = plot(ax, x, y, '-', 'Color', opts.sessionColor, ...
            'LineWidth', opts.sessionLineWidth, 'HandleVisibility', 'off');
        handles.sessions(end+1, 1) = h; %#ok<AGROW>
    end
end
handles.ribbon = gobjects(0);
handles.mean = gobjects(0);
handles.closer = gobjects(0);
handles.random = gobjects(0);
if ~isempty(M)
    x = M.sessionTrialCenter;
    if opts.diff
        y = M.meanExcessDistDeg;
        se = M.semExcessDistDeg;
    else
        y = M.meanGazeDistDeg;
        se = M.semGazeDistDeg;
    end
    if opts.showSem
        good = isfinite(x) & isfinite(y) & isfinite(se);
        if any(good)
            handles.ribbon = fill(ax, [x(good); flipud(x(good))], ...
                [y(good)-se(good); flipud(y(good)+se(good))], ...
                opts.meanColor, 'FaceAlpha', 0.18, 'EdgeColor', 'none', ...
                'HandleVisibility', 'off');
        end
    end
    handles.mean = plot(ax, x, y, '-o', 'Color', opts.meanColor, ...
        'LineWidth', opts.meanLineWidth, 'MarkerSize', 5, ...
        'DisplayName', 'median gaze');
    if ~opts.diff
        handles.closer = plot(ax, x, M.meanCloserTargetDistDeg, ...
            char(string(opts.closerLineStyle)), ...
            'Color', opts.closerColor, 'LineWidth', 1.7, ...
            'DisplayName', 'reward-closer target');
        handles.random = plot(ax, x, M.meanRandomTargetDistDeg, ...
            char(string(opts.randomLineStyle)), ...
            'Color', opts.randomColor, 'LineWidth', 1.7, ...
            'DisplayName', 'random target');
    end
end
if opts.diff
    yline(ax, 0, ':', 'HandleVisibility', 'off');
    ylabel(ax, 'excess distance over reward-closer target (deg)');
    title(ax, 'Gaze-to-reward distance across reward-center sessions');
else
    ylabel(ax, 'distance to reward center (deg)');
    title(ax, 'Gaze distance across reward-center sessions');
end
xlabel(ax, 'trial within reward-center session');
box(ax, 'off');
if ~isempty(M)
    legend(ax, 'Location', 'best');
end
if ~wasHeld
    hold(ax, 'off');
end
end


function out = localMergeStructs(a, b)
out = a;
names = fieldnames(b);
for i = 1:numel(names)
    out.(names{i}) = b.(names{i});
end
end
