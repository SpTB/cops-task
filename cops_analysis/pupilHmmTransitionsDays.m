function out = pupilHmmTransitionsDays(animal, dateFrom, dateTo, opts)
% pupilHmmTransitionsDays  Aggregate HMM-transition pupil traces across days.
%
% out = pupilHmmTransitionsDays(animal, dateFrom, dateTo)
% out = pupilHmmTransitionsDays(animal, dateFrom, dateTo, opts)
%
% Examples
%   out = pupilHmmTransitionsDays('ka', 'jun02', 'jul12');
%   opts = struct('minTrials', 200, 'type', 'dayMean');
%   out = pupilHmmTransitionsDays('lychee', '2026.06.02', ...
%       '2026.07.12', opts);
%
% opts.type controls the unit contributing to the main trace:
%   'dayMean' (default) - average events within day, then average days.
%                         Thus every eligible day has equal weight.
%   'eventAgg'          - pool all events across eligible days before
%                         averaging. Days with more events have more weight.
%
% A day is eligible when its merged ex contains at least opts.minTrials
% trials (default 200). The function discovers fitted SM3 dates from their
% prediction CSVs, merges each sidecar with the raw blocks, and calls
% pupilHmmTransitions once per day. Options not listed below are forwarded
% to pupilHmmTransitions (for example baselineWindowSec or hmmMethod).
%
% Day-level options (defaults):
%   .minTrials  200
%   .type       'dayMean'
%   .model      'sm3'
%   .block      'all'
%   .makePlot   true
%   .failFast   false
%   .posCorrected true; fits/applies that day's EyeCal correction
%   .dataRoot   'Y:\data\CoPs'
%   .hmmRoot    <cops_project>\output\hmm

% Main outputs:
%   .grand       mean/SEM/counts for each event category
%   .dayMeans    one within-day mean trace per category
%   .events      pooled event metadata, including animal and date
%   .audit       inclusion and trial/event counts for every selected day
%   .figure      two-panel grand-trace figure

% See also pupilHmmTransitions, mergeCoPsHmmStruct.


if nargin < 2
    dateFrom = [];
end
if nargin < 3
    dateTo = [];
end
% Convenience overload:
% pupilHmmTransitionsDays(animal, dateFrom, opts)
% treats a third-argument structure as opts and leaves dateTo unspecified.
optionsSuppliedInThird = nargin >= 3 && isstruct(dateTo) && ...
    (nargin < 4 || isempty(opts));
if optionsSuppliedInThird
    opts = dateTo;
    dateTo = [];
end
if (nargin < 4 && ~optionsSuppliedInThird) || isempty(opts)
    opts = struct();
elseif ~isstruct(opts) || ~isscalar(opts)
    error('pupilHmmTransitionsDays:BadOptions', ...
        'opts must be one scalar structure.');
end
opts = localDefaults(opts);
animal = localAnimal(animal);

[predictionFolder, predictionExpression] = localModelSpec(opts.model);
predictionDir = fullfile(char(opts.hmmRoot), predictionFolder, 'preds');
jobs = localPredictionJobs(predictionDir, predictionExpression, animal);
if isempty(jobs)
    error('pupilHmmTransitionsDays:NoFittedDates', ...
        'No fitted %s dates for %s were found in %s.', ...
        upper(opts.model), animal, predictionDir);
end
[rangeStart, rangeStop] = localDateRange(dateFrom, dateTo, jobs.dateValue);
jobs = jobs(jobs.dateValue >= rangeStart & jobs.dateValue <= rangeStop, :);
jobs = sortrows(jobs, 'dateValue');
if isempty(jobs)
    error('pupilHmmTransitionsDays:NoDatesInRange', ...
        'No fitted %s dates for %s fall between %s and %s.', ...
        upper(opts.model), animal, string(rangeStart, 'yyyy.MM.dd'), ...
        string(rangeStop, 'yyyy.MM.dd'));
end

fprintf(['pupilHmmTransitionsDays: %d fitted %s days for %s from %s ' ...
    'through %s; minimum %d trials/day; aggregation=%s.\n'], ...
    height(jobs), upper(opts.model), animal, ...
    string(rangeStart, 'yyyy.MM.dd'), string(rangeStop, 'yyyy.MM.dd'), ...
    opts.minTrials, opts.type);

categoryNames = localCategories();
transitionOpts = localTransitionOptions(opts);
mergeOpts = struct('model', opts.model, 'block', opts.block, ...
    'dataRoot', opts.dataRoot, 'hmmRoot', opts.hmmRoot);

auditRows = repmat(localEmptyAudit(), height(jobs), 1);
dayRows = repmat(localEmptyDayMean(), 0, 1);
eventTables = cell(0, 1);
eventTraces = cell(0, 1);
metricTables = cell(0, 1);
commonTime = [];
resolvedTransitionOpts = transitionOpts;

for dayIndex = 1:height(jobs)
    dateLabel = char(jobs.date(dayIndex));
    fprintf('[%d/%d] %s %s: ', dayIndex, height(jobs), animal, dateLabel);
    row = localEmptyAudit();
    row.animal = string(animal);
    row.date = string(dateLabel);
    row.predictionFile = jobs.predictionFile(dayIndex);
    started = tic;
    try
        mergeOpts.predictionFile = char(jobs.predictionFile(dayIndex));
        [ex, mergeReport] = mergeCoPsHmmStruct(animal, dateLabel, mergeOpts);
        row.nBlocks = mergeReport.nBlocks;
        row.nTrials = numel(ex.Trials);
        if row.nTrials < opts.minTrials
            row.status = "below-min-trials";
            row.message = sprintf('%d < %d trials', row.nTrials, opts.minTrials);
            fprintf('excluded (%s).\n', row.message);
            row.elapsedSec = toc(started);
            auditRows(dayIndex) = row;
            continue
        end

        dayTransitionOpts=transitionOpts;
        if opts.posCorrected
            dayTransitionOpts.posCorrected=true;
            dayTransitionOpts.posCorrectionAnimal=animal;
            dayTransitionOpts.posCorrectionDate=dateLabel;
            if ~isfield(dayTransitionOpts,'posCorrectionOpts')|| ...
                    isempty(dayTransitionOpts.posCorrectionOpts)
                dayTransitionOpts.posCorrectionOpts=struct();
            end
            dayTransitionOpts.posCorrectionOpts.dataRoot=opts.dataRoot;
        end
        dayOut = pupilHmmTransitions(ex, dayTransitionOpts);
        resolvedTransitionOpts = dayOut.opts;
        if isempty(commonTime)
            commonTime = dayOut.timeSec(:)';
        end
        traces = localResampleRows( ...
            dayOut.traces.combined, dayOut.timeSec, commonTime);
        events = dayOut.events;
        row.nTrialsWithHmm = dayOut.meta.nTrialsWithHmm;
        row.nEvents = height(events);
        row.status = "included";

        if ~isempty(events)
            events.animal = repmat(string(animal), height(events), 1);
            events.date = repmat(string(dateLabel), height(events), 1);
            eventTables{end+1, 1} = events; %#ok<AGROW>
            eventTraces{end+1, 1} = traces; %#ok<AGROW>
        end
        for categoryIndex = 1:numel(categoryNames)
            category = categoryNames(categoryIndex);
            if isempty(events)
                selected = false(0, 1);
            else
                selected = events.eventCategory == category;
            end
            nEvents = sum(selected);
            dayRow = localEmptyDayMean();
            dayRow.animal = string(animal);
            dayRow.date = string(dateLabel);
            dayRow.eventCategory = category;
            dayRow.nTrials = row.nTrials;
            dayRow.nEvents = nEvents;
            if nEvents > 0
                dayRow.meanTrace = mean(traces(selected, :), 1, 'omitnan');
            else
                dayRow.meanTrace = nan(1, numel(commonTime));
            end
            dayRows(end+1, 1) = dayRow; %#ok<AGROW>
        end
        if ~isempty(dayOut.summary)
            metrics = dayOut.summary;
            metrics.animal = repmat(string(animal), height(metrics), 1);
            metrics.date = repmat(string(dateLabel), height(metrics), 1);
            metrics.nTrials = repmat(row.nTrials, height(metrics), 1);
            metricTables{end+1, 1} = metrics; %#ok<AGROW>
        end
        fprintf('included: %d trials, %d retained events.\n', ...
            row.nTrials, row.nEvents);
    catch exception
        row.status = "failed";
        row.message = string(exception.identifier) + ": " + ...
            string(exception.message);
        fprintf('FAILED: %s\n', exception.message);
        if opts.failFast
            rethrow(exception)
        end
    end
    row.elapsedSec = toc(started);
    auditRows(dayIndex) = row;
end

audit = struct2table(auditRows);
included = audit.status == "included";
if ~any(included)
    error('pupilHmmTransitionsDays:NoEligibleDays', ...
        ['No days met opts.minTrials=%d and completed successfully. ' ...
         'Inspect the returned console audit or lower opts.minTrials.'], ...
        opts.minTrials);
end

if isempty(eventTables)
    events = table();
    pooledTraces = nan(0, numel(commonTime));
else
    events = vertcat(eventTables{:});
    pooledTraces = vertcat(eventTraces{:});
end
if isempty(dayRows)
    dayMeans = table();
else
    dayMeans = struct2table(dayRows);
end
if isempty(metricTables)
    dayMetrics = table();
else
    dayMetrics = vertcat(metricTables{:});
end

grand = localGrand(categoryNames, opts.type, dayMeans, events, pooledTraces);
figureHandle = [];
if opts.makePlot
    figureHandle = localPlot(commonTime, grand, resolvedTransitionOpts, ...
        animal, rangeStart, rangeStop, opts.type);
end

out = struct();
out.animal = string(animal);
out.dateFrom = rangeStart;
out.dateTo = rangeStop;
out.type = string(opts.type);
out.aggregationUnit = string(localAggregationUnit(opts.type));
out.timeSec = commonTime;
out.grand = grand;
out.dayMeans = dayMeans;
out.events = events;
out.traces = struct('event', pooledTraces);
out.dayMetrics = dayMetrics;
out.audit = audit;
out.figure = figureHandle;
out.opts = opts;
out.transitionOpts = resolvedTransitionOpts;
out.meta = struct( ...
    'nFittedDaysSelected', height(jobs), ...
    'nEligibleDays', nnz(included), ...
    'nExcludedBelowTrialMinimum', nnz(audit.status == "below-min-trials"), ...
    'nFailedDays', nnz(audit.status == "failed"), ...
    'nEvents', height(events), ...
    'minimumDailyTrials', opts.minTrials, ...
    'aggregationUnit', localAggregationUnit(opts.type));
end


function opts = localDefaults(opts)
defaults = struct( ...
    'minTrials', 200, ...
    'type', 'dayMean', ...
    'model', 'sm3', ...
    'block', 'all', ...
    'makePlot', true, ...
    'failFast', false, ...
    'posCorrected', true, ...
    'dataRoot', 'Y:\data\CoPs', ...
    'hmmRoot', fullfile( ...
        'C:\Users\zajkowskiwk\OneDrive - National Institutes of Health', ...
        'cops_project', 'output', 'hmm'));
names = fieldnames(defaults);
for index = 1:numel(names)
    if ~isfield(opts, names{index}) || isempty(opts.(names{index}))
        opts.(names{index}) = defaults.(names{index});
    end
end
opts.type = validatestring(char(string(opts.type)), {'dayMean','eventAgg'});
opts.model = lower(char(string(opts.model)));
if ~strcmp(opts.model, 'sm3')
    error('pupilHmmTransitionsDays:BadModel', ...
        ['Transition categories involving non-tracking require the SM3 ' ...
         'model; set opts.model=''sm3''.']);
end
if ~(isscalar(opts.minTrials) && isnumeric(opts.minTrials) && ...
        isfinite(opts.minTrials) && opts.minTrials >= 0 && ...
        opts.minTrials == round(opts.minTrials))
    error('pupilHmmTransitionsDays:BadMinTrials', ...
        'opts.minTrials must be a nonnegative integer.');
end
opts.makePlot = localLogical(opts.makePlot, 'makePlot');
opts.failFast = localLogical(opts.failFast, 'failFast');
opts.posCorrected = localLogical(opts.posCorrected, 'posCorrected');
end


function value = localLogical(value, name)
if ~(isscalar(value) && (islogical(value) || isnumeric(value)) && ...
        isfinite(double(value)) && ismember(double(value), [0 1]))
    error('pupilHmmTransitionsDays:BadOptions', ...
        'opts.%s must be logical or 0/1.', name);
end
value = logical(value);
end


function transitionOpts = localTransitionOptions(opts)
collectorFields = {'minTrials','type','model','block','makePlot','failFast', ...
    'dataRoot','hmmRoot'};
transitionOpts = opts;
present = intersect(fieldnames(transitionOpts), collectorFields);
if ~isempty(present)
    transitionOpts = rmfield(transitionOpts, present);
end
transitionOpts.makePlot = false;
transitionOpts.requireSm3 = true;
end


function animal = localAnimal(value)
key = lower(strtrim(char(string(value))));
switch key
    case {'ka','kaki'}
        animal = 'kaki';
    case {'ly','lychee'}
        animal = 'lychee';
    otherwise
        error('pupilHmmTransitionsDays:BadAnimal', ...
            'Unknown animal %s; use ka/kaki or ly/lychee.', key);
end
end


function [folder, expression] = localModelSpec(model)
switch model
    case 'sm3'
        folder = 'tidSM3';
        expression = ['^(kaki|lychee)_(\d{4}\.\d{2}\.\d{2})_' ...
            'targetidsens3_distance_gated_random_effect_cv' ...
            '(?:_v\d+)?_predictions\.csv$'];
    otherwise
        error('pupilHmmTransitionsDays:BadModel', 'Unsupported model %s.', model);
end
end


function jobs = localPredictionJobs(folder, expression, animal)
files = dir(fullfile(folder, '*_predictions.csv'));
rows = repmat(struct('animal', "", 'date', "", 'dateValue', NaT, ...
    'predictionFile', "", 'modified', NaT), 0, 1);
for index = 1:numel(files)
    token = regexp(files(index).name, expression, 'tokens', 'once');
    if isempty(token) || ~strcmp(token{1}, animal)
        continue
    end
    row = struct();
    row.animal = string(token{1});
    row.date = string(token{2});
    row.dateValue = datetime(token{2}, 'InputFormat', 'yyyy.MM.dd');
    row.predictionFile = string(fullfile(files(index).folder, files(index).name));
    row.modified = datetime(files(index).datenum, 'ConvertFrom', 'datenum');
    rows(end+1, 1) = row; %#ok<AGROW>
end
if isempty(rows)
    jobs = table();
    return
end
jobs = struct2table(rows);
jobs = sortrows(jobs, {'dateValue','modified'}, {'ascend','descend'});
[~, keep] = unique(jobs.date, 'stable');
jobs = jobs(sort(keep), :);
end


function [rangeStart, rangeStop] = localDateRange(fromValue, toValue, dates)
defaultYear = year(max(dates));
if nargin < 1 || isempty(fromValue) || ...
        (isstring(fromValue) && isscalar(fromValue) && strlength(strtrim(fromValue)) == 0)
    rangeStart = min(dates);
else
    rangeStart = localParseDate(fromValue, defaultYear);
end
if nargin < 2 || isempty(toValue) || ...
        (isstring(toValue) && isscalar(toValue) && strlength(strtrim(toValue)) == 0)
    rangeStop = max(dates);
else
    rangeStop = localParseDate(toValue, defaultYear);
end
if rangeStop < rangeStart && localIsShortDate(fromValue) && localIsShortDate(toValue)
    rangeStop = datetime(year(rangeStart) + 1, month(rangeStop), day(rangeStop));
end
if rangeStop < rangeStart
    error('pupilHmmTransitionsDays:BadDateRange', ...
        'dateTo must be on or after dateFrom.');
end
end


function parsed = localParseDate(value, defaultYear)
if isdatetime(value)
    parsed = datetime(year(value), month(value), day(value));
    return
end
text = strtrim(char(string(value)));
normalized = regexprep(text, '[-_]', '.');
try
    parsed = datetime(normalized, 'InputFormat', 'yyyy.MM.dd');
    return
catch
end
token = regexp(lower(text), ...
    ['^(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|' ...
     'jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|' ...
     'nov(?:ember)?|dec(?:ember)?)\s*([0-9]{1,2})$'], ...
    'tokens', 'once');
if isempty(token)
    error('pupilHmmTransitionsDays:BadDate', ...
        ['Dates must use YYYY.MM.DD or a month/day such as jun02, ' ...
         'June2, or july12.']);
end
monthNames = {'jan','feb','mar','apr','may','jun', ...
    'jul','aug','sep','oct','nov','dec'};
monthNo = find(strcmp(token{1}(1:3), monthNames), 1, 'first');
parsed = datetime(defaultYear, monthNo, str2double(token{2}));
end


function tf = localIsShortDate(value)
if isempty(value) || isdatetime(value)
    tf = false;
    return
end
tf = isempty(regexp(strtrim(char(string(value))), '^\d{4}[-._]', 'once'));
end


function tracesOut = localResampleRows(traces, sourceTime, destinationTime)
sourceTime = sourceTime(:)';
destinationTime = destinationTime(:)';
if isempty(traces)
    tracesOut = nan(0, numel(destinationTime));
elseif numel(sourceTime) == numel(destinationTime) && ...
        max(abs(sourceTime - destinationTime)) < 1e-10
    tracesOut = traces;
else
    tracesOut = nan(size(traces, 1), numel(destinationTime));
    for row = 1:size(traces, 1)
        tracesOut(row, :) = interp1(sourceTime, traces(row, :), ...
            destinationTime, 'linear', NaN);
    end
end
end


function grand = localGrand(categories, type, dayMeans, events, eventTraces)
rows = repmat(localEmptyGrand(), numel(categories), 1);
for index = 1:numel(categories)
    category = categories(index);
    if isempty(dayMeans)
        selectedDays = false(0, 1);
    else
        selectedDays = dayMeans.eventCategory == category & dayMeans.nEvents > 0;
    end
    if isempty(events)
        selectedEvents = false(0, 1);
    else
        selectedEvents = events.eventCategory == category;
    end
    if strcmp(type, 'dayMean')
        units = localTraceCells(dayMeans.meanTrace(selectedDays, :));
    else
        units = eventTraces(selectedEvents, :);
    end
    row = localEmptyGrand();
    row.eventCategory = category;
    row.nDays = sum(selectedDays);
    row.nEvents = sum(selectedEvents);
    row.nUnits = size(units, 1);
    row.meanTrace = localMean(units);
    row.semTrace = localSem(units);
    rows(index) = row;
end
grand = struct2table(rows);
end


function matrix = localTraceCells(values)
if isempty(values)
    matrix = nan(0, 0);
elseif iscell(values)
    matrix = vertcat(values{:});
else
    matrix = values;
end
end


function value = localMean(matrix)
if isempty(matrix)
    value = nan(1, size(matrix, 2));
else
    value = mean(matrix, 1, 'omitnan');
end
end


function value = localSem(matrix)
if isempty(matrix)
    value = nan(1, size(matrix, 2));
    return
end
count = sum(isfinite(matrix), 1);
value = std(matrix, 0, 1, 'omitnan') ./ sqrt(max(count, 1));
value(count < 2) = NaN;
end


function figureHandle = localPlot(time, grand, transitionOpts, ...
        animal, rangeStart, rangeStop, type)
figureHandle = figure('Color', 'w', ...
    'Name', 'Daily HMM-transition pupil responses', ...
    'Position', [100 50 760 920]);
colors = lines(4);
tiled = tiledlayout(figureHandle, 2, 1, ...
    'TileSpacing', 'compact', 'Padding', 'compact');
axesHandles = gobjects(2, 1);
axesHandles(1) = nexttile(tiled);
localPlotPanel(axesHandles(1), time, grand, ...
    [1 2], colors([3 4], :), 'Tracking acquisition and loss', ...
    transitionOpts.baselineWindowSec);
axesHandles(2) = nexttile(tiled);
localPlotPanel(axesHandles(2), time, grand, ...
    [3 4], colors([1 2], :), 'Switches between tracked targets', ...
    transitionOpts.baselineWindowSec);
linkaxes(axesHandles, 'x');
if isempty(transitionOpts.baselineWindowSec)
    yLabel = 'Pupil size (session-eye SD)';
    baselineText = 'no event baseline';
else
    yLabel = '\Delta pupil (session-eye SD)';
    baselineText = sprintf('baseline [%g, %g] s', ...
        transitionOpts.baselineWindowSec);
end
arrayfun(@(axisHandle) ylabel(axisHandle, yLabel), axesHandles);
title(tiled, sprintf('%s, %s to %s; %s (%s); %s', ...
    animal, string(rangeStart, 'yyyy.MM.dd'), ...
    string(rangeStop, 'yyyy.MM.dd'), type, ...
    localAggregationUnit(type), baselineText), 'Interpreter', 'none');

legendOrder = [1 2 3 4];
legendColors = colors([3 4 1 2], :);
plainLabels = ["non-tracking -> tracking", "tracking -> non-tracking", ...
    "closer -> farther", "farther -> closer"];
legendHandles = gobjects(4, 1);
legendLabels = strings(4, 1);
for index = 1:4
    legendHandles(index) = plot(axesHandles(1), NaN, NaN, ...
        'Color', legendColors(index,:), 'LineWidth', 2, ...
        'HandleVisibility', 'on');
    row = grand(legendOrder(index), :);
    if strcmp(type, 'dayMean')
        legendLabels(index) = sprintf('%s (days=%d; events=%d)', ...
            plainLabels(index), row.nDays, row.nEvents);
    else
        legendLabels(index) = sprintf('%s (events=%d)', ...
            plainLabels(index), row.nEvents);
    end
end
legend(axesHandles(1), legendHandles, legendLabels, ...
    'Location', 'northoutside', 'Orientation', 'horizontal', ...
    'NumColumns', 2, 'Interpreter', 'none');
end


function localPlotPanel(axisHandle, time, grand, indices, colors, ...
        panelTitle, baselineWindow)
hold(axisHandle, 'on');
for localIndex = 1:numel(indices)
    row = grand(indices(localIndex), :);
    average = row.meanTrace;
    sem = row.semTrace;
    if iscell(average)
        average = average{1};
    end
    if iscell(sem)
        sem = sem{1};
    end
    if ~isempty(average) && any(isfinite(average))
        fill(axisHandle, [time fliplr(time)], ...
            [average-sem fliplr(average+sem)], colors(localIndex,:), ...
            'FaceAlpha', .15, 'EdgeColor', 'none', ...
            'HandleVisibility', 'off');
        plot(axisHandle, time, average, ...
            'Color', colors(localIndex,:), 'LineWidth', 2, ...
            'HandleVisibility', 'off');
    end
end
if ~isempty(baselineWindow)
    yLimits = ylim(axisHandle);
    baselinePatch = patch(axisHandle, ...
        baselineWindow([1 2 2 1]), yLimits([1 1 2 2]), [.75 .75 .75], ...
        'FaceAlpha', .22, 'EdgeColor', 'none', ...
        'HandleVisibility', 'off');
    uistack(baselinePatch, 'bottom');
end
xline(axisHandle, 0, 'k--', 'HMM transition', ...
    'HandleVisibility', 'off');
yline(axisHandle, 0, 'Color', [.5 .5 .5], 'HandleVisibility', 'off');
xlabel(axisHandle, 'Time from transition (s)');
title(axisHandle, panelTitle);
grid(axisHandle, 'on');
pbaspect(axisHandle, [1.45 1 1]);
end


function categories = localCategories()
categories = ["nonTracking_to_tracking", "tracking_to_nonTracking", ...
    "closer_to_farther", "farther_to_closer"];
end


function unit = localAggregationUnit(type)
if strcmp(type, 'dayMean')
    unit = 'day';
else
    unit = 'event';
end
end


function row = localEmptyAudit()
row = struct('animal', "", 'date', "", 'status', "", ...
    'nBlocks', 0, 'nTrials', 0, 'nTrialsWithHmm', 0, 'nEvents', 0, ...
    'predictionFile', "", 'elapsedSec', NaN, 'message', "");
end


function row = localEmptyDayMean()
row = struct('animal', "", 'date', "", 'eventCategory', "", ...
    'nTrials', 0, 'nEvents', 0, 'meanTrace', []);
end


function row = localEmptyGrand()
row = struct('eventCategory', "", 'nDays', 0, 'nEvents', 0, ...
    'nUnits', 0, 'meanTrace', [], 'semTrace', []);
end
