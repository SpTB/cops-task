function out = plotGazeRewDistDay(subject, dateValue, opts)
% plotGazeRewDistDay  Plot one-day reward-distance trajectory.
%
%   T = plotGazeRewDistDay('ka')
%   T = plotGazeRewDistDay('ka', 'Jul3')
%   T = plotGazeRewDistDay('ka', 'Jul3', opts)
%   T = plotGazeRewDistDay('ka', opts)
%
% This is intentionally single-day only. It first binds the day's sessions
% via exDay, then calls plotGazeRewDist on the combined ex.
%
% opts fields are passed to plotGazeRewDist/gazeHeatTrajectory, except:
%   opts.date            : single date, if no dateValue argument is supplied
%   opts.dataRoot        : data root passed to exDay
%   opts.includeTrials   : trial phase passed to exDay (default 'main+pre')
%   opts.minTrialNum     : minimum selected trials per session passed to exDay
%   opts.showSessionLines : true/false, add vertical lines at session boundaries
%   opts.blockLineStyle   : line style for session boundaries (default '--')
%   opts.blockLineColor   : line color for session boundaries (default [0 0 0])
%   opts.blockLineWidth   : line width for session boundaries (default 1)

if nargin < 1 || isempty(subject)
    error('plotGazeRewDistDay:MissingSubject', ...
        'Provide a subject, e.g. plotGazeRewDistDay(''ka'', ''Jul3'').');
end
if nargin < 2
    dateValue = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
elseif ~isstruct(opts)
    error('plotGazeRewDistDay:BadOpts', 'opts must be a struct.');
end
if isstruct(dateValue)
    opts = localMergeStructs(dateValue, opts);
    dateValue = [];
end

[dayDate, opts] = localResolveDayDate(dateValue, opts);
[exOpts, plotOpts, lineOpts] = localSplitOptions(opts);
exOpts.subject = subject;

ex = exDay(dayDate, exOpts);
out = plotGazeRewDist(ex, [], plotOpts);

sessionBoundaryTrials = localSessionBoundaryTrials(ex);
sessionLineX = [];
if logical(lineOpts.showSessionLines)
    sessionLineX = localBoundaryLinePositions(out.trials, sessionBoundaryTrials);
    if ~isempty(sessionLineX)
        localDrawBoundaryLines(gca, sessionLineX, lineOpts);
    end
end

out.subject = string(subject);
out.date = dayDate;
out.dateLabel = string(datestr(dayDate, 'yyyy.mm.dd'));
if isfield(ex, 'exp') && isfield(ex.exp, 'exDay')
    out.exDay = ex.exp.exDay;
end
out.exDayOptions = exOpts;
out.sessionBoundaryTrials = sessionBoundaryTrials;
out.sessionLineX = sessionLineX;
out.sessionLineOptions = lineOpts;
end


function [dayDate, opts] = localResolveDayDate(dateValue, opts)
hasDateValue = ~isempty(dateValue);
hasDateField = isfield(opts, 'date') && ~isempty(opts.date);
hasDateFrom = isfield(opts, 'dateFrom') && ~isempty(opts.dateFrom);
hasDateTo = isfield(opts, 'dateTo') && ~isempty(opts.dateTo);

if hasDateValue
    dayDate = localParseDate(dateValue);
    if hasDateField && ~localSameDay(dayDate, localParseDate(opts.date))
        error('plotGazeRewDistDay:DateConflict', ...
            'dateValue and opts.date refer to different days.');
    end
elseif hasDateField
    dayDate = localParseDate(opts.date);
elseif hasDateFrom
    dayDate = localParseDate(opts.dateFrom);
elseif hasDateTo
    dayDate = localParseDate(opts.dateTo);
else
    dayDate = datetime('today');
end
dayDate = datetime(year(dayDate), month(dayDate), day(dayDate));

if hasDateFrom && ~localSameDay(dayDate, localParseDate(opts.dateFrom))
    error('plotGazeRewDistDay:DateRangeNotSingleDay', ...
        'plotGazeRewDistDay is only valid for one day; opts.dateFrom must match the selected date.');
end
if hasDateTo && ~localSameDay(dayDate, localParseDate(opts.dateTo))
    error('plotGazeRewDistDay:DateRangeNotSingleDay', ...
        'plotGazeRewDistDay is only valid for one day; opts.dateTo must match the selected date.');
end

opts = localRemoveFields(opts, {'date', 'dateFrom', 'dateTo'});
end


function [exOpts, plotOpts, lineOpts] = localSplitOptions(opts)
exFields = {'dataRoot', 'includeTrials', 'minTrialNum'};
lineDefaults = struct( ...
    'showSessionLines', true, ...
    'showBlockLines', [], ...
    'blockLineStyle', '--', ...
    'blockLineColor', [0 0 0], ...
    'blockLineWidth', 1);

exOpts = struct();
for i = 1:numel(exFields)
    name = exFields{i};
    if isfield(opts, name)
        exOpts.(name) = opts.(name);
    end
end
if ~isfield(exOpts, 'includeTrials') || isempty(exOpts.includeTrials)
    exOpts.includeTrials = 'main+pre';
end

lineOpts = lineDefaults;
lineNames = fieldnames(lineDefaults);
for i = 1:numel(lineNames)
    name = lineNames{i};
    if isfield(opts, name) && ~isempty(opts.(name))
        lineOpts.(name) = opts.(name);
    end
end
if ~isempty(lineOpts.showBlockLines)
    lineOpts.showSessionLines = lineOpts.showBlockLines;
end
lineOpts.showSessionLines = logical(lineOpts.showSessionLines(1));
lineOpts = rmfield(lineOpts, 'showBlockLines');

plotOpts = localRemoveFields(opts, [exFields, lineNames', {'blockLvls', 'blockEdges'}]);
end


function boundaryTrials = localSessionBoundaryTrials(ex)
boundaryTrials = [];
if ~isfield(ex, 'exp') || ~isfield(ex.exp, 'exDay') || ~isfield(ex.exp.exDay, 'fileTable')
    return
end
fileTable = ex.exp.exDay.fileTable;
if isempty(fileTable) || ~istable(fileTable) || ~ismember('dayTrialStop', fileTable.Properties.VariableNames)
    return
end
if ismember('status', fileTable.Properties.VariableNames)
    included = strcmp(string(fileTable.status), "included");
else
    included = true(height(fileTable), 1);
end
stops = double(fileTable.dayTrialStop(included));
stops = stops(isfinite(stops));
if numel(stops) > 1
    boundaryTrials = stops(1:end-1)';
end
end


function xPositions = localBoundaryLinePositions(trials, boundaryTrials)
trials = double(trials(:)');
xPositions = [];
for i = 1:numel(boundaryTrials)
    boundaryTrial = boundaryTrials(i);
    lastBefore = find(trials <= boundaryTrial, 1, 'last');
    firstAfter = find(trials > boundaryTrial, 1, 'first');
    if ~isempty(lastBefore) && ~isempty(firstAfter)
        xPositions(end+1) = mean(double([lastBefore firstAfter])); %#ok<AGROW>
    end
end
end


function localDrawBoundaryLines(ax, xPositions, opts)
if isempty(ax) || ~ishandle(ax)
    return
end
wasHeld = ishold(ax);
hold(ax, 'on');
for i = 1:numel(xPositions)
    x = xPositions(i);
    if exist('xline', 'file') == 2 || exist('xline', 'builtin') == 5
        xline(ax, x, char(string(opts.blockLineStyle)), ...
            'Color', opts.blockLineColor, ...
            'LineWidth', opts.blockLineWidth, ...
            'HandleVisibility', 'off');
    else
        yl = ylim(ax);
        plot(ax, [x x], yl, ...
            'LineStyle', char(string(opts.blockLineStyle)), ...
            'Color', opts.blockLineColor, ...
            'LineWidth', opts.blockLineWidth, ...
            'HandleVisibility', 'off');
        ylim(ax, yl);
    end
end
if ~wasHeld
    hold(ax, 'off');
end
end


function d = localParseDate(value)
if isdatetime(value)
    d = datetime(year(value), month(value), day(value));
    return
end
s = strtrim(char(string(value)));
if strcmpi(s, 'today')
    d = datetime('today');
    return
end
try
    d = datetime(s, 'InputFormat', 'yyyy.MM.dd');
    return
catch
end
tok = regexp(lower(s), '^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s*([0-9]{1,2})$', ...
    'tokens', 'once');
if isempty(tok)
    error('plotGazeRewDistDay:BadDate', ...
        'Date must be datetime, ''today'', ''YYYY.MM.DD'', or shorthand like ''Jun18''.');
end
months = struct('jan',1,'feb',2,'mar',3,'apr',4,'may',5,'jun',6, ...
    'jul',7,'aug',8,'sep',9,'oct',10,'nov',11,'dec',12);
d = datetime(year(datetime('today')), months.(tok{1}), str2double(tok{2}));
end


function tf = localSameDay(a, b)
a = datetime(year(a), month(a), day(a));
b = datetime(year(b), month(b), day(b));
tf = isequal(a, b);
end


function out = localMergeStructs(a, b)
out = a;
names = fieldnames(b);
for i = 1:numel(names)
    out.(names{i}) = b.(names{i});
end
end


function s = localRemoveFields(s, names)
for i = 1:numel(names)
    if isfield(s, names{i})
        s = rmfield(s, names{i});
    end
end
end
