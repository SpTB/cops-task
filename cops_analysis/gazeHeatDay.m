function out = gazeHeatDay(subject, dateValue, opts)
% gazeHeatDay  Collect and plot one-day CoPs gaze heat.
%
%   G = gazeHeatDay('ka')
%   G = gazeHeatDay('ka', 'Jun18')
%   G = gazeHeatDay('ka', 'Jun18', opts)
%   G = gazeHeatDay('ka', opts)
%
% This is intentionally single-day only. By default it uses today's date,
% no reward alignment, and no final 45-degree plot rotation.
%
% opts fields are passed to collectGazeHeat, except:
%   opts.date        : single date, if no dateValue argument is supplied
%   opts.groupingArg : groupingArg passed to collectGazeHeat/plotGazeHeatAggregate
%   opts.plot        : true/false, whether to call plotGazeHeatAggregate
%   opts.plotOpts    : options struct passed to plotGazeHeatAggregate

if nargin < 1 || isempty(subject)
    error('gazeHeatDay:MissingSubject', 'Provide a subject, e.g. gazeHeatDay(''ka'').');
end
if nargin < 2
    dateValue = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
elseif ~isstruct(opts)
    error('gazeHeatDay:BadOpts', 'opts must be a struct.');
end
if isstruct(dateValue)
    opts = localMergeStructs(dateValue, opts);
    dateValue = [];
end

[dayDate, opts] = localResolveDayDate(dateValue, opts);
[groupingArg, doPlot, plotOpts, collectOpts] = localSplitOptions(opts);

collectOpts.dateFrom = dayDate;
collectOpts.dateTo = dayDate;
collectOpts.alignRewardToTopLeft = localDefaultFalse(collectOpts, 'alignRewardToTopLeft');
collectOpts.plotRotate45 = localDefaultFalse(collectOpts, 'plotRotate45');

A = collectGazeHeat(subject, groupingArg, collectOpts);
if doPlot
    P = plotGazeHeatAggregate(A, groupingArg, plotOpts);
else
    P = [];
end

out = struct();
out.aggregate = A;
out.plot = P;
out.subject = string(subject);
out.date = dayDate;
out.dateLabel = string(datestr(dayDate, 'yyyy.mm.dd'));
out.groupingArg = groupingArg;
out.collectOptions = collectOpts;
out.plotOptions = plotOpts;
end


function [dayDate, opts] = localResolveDayDate(dateValue, opts)
hasDateValue = ~isempty(dateValue);
hasDateField = isfield(opts, 'date') && ~isempty(opts.date);
hasDateFrom = isfield(opts, 'dateFrom') && ~isempty(opts.dateFrom);
hasDateTo = isfield(opts, 'dateTo') && ~isempty(opts.dateTo);

if hasDateValue
    dayDate = localParseDate(dateValue);
    if hasDateField && ~localSameDay(dayDate, localParseDate(opts.date))
        error('gazeHeatDay:DateConflict', 'dateValue and opts.date refer to different days.');
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
    error('gazeHeatDay:DateRangeNotSingleDay', ...
        'gazeHeatDay is only valid for one day; opts.dateFrom must match the selected date.');
end
if hasDateTo && ~localSameDay(dayDate, localParseDate(opts.dateTo))
    error('gazeHeatDay:DateRangeNotSingleDay', ...
        'gazeHeatDay is only valid for one day; opts.dateTo must match the selected date.');
end

opts = localRemoveFields(opts, {'date', 'dateFrom', 'dateTo'});
end


function [groupingArg, doPlot, plotOpts, collectOpts] = localSplitOptions(opts)
groupingArg = [];
if isfield(opts, 'groupingArg') && ~isempty(opts.groupingArg)
    groupingArg = opts.groupingArg;
end

doPlot = true;
if isfield(opts, 'plot') && ~isempty(opts.plot)
    doPlot = logical(opts.plot(1));
end

plotOpts = struct();
if isfield(opts, 'plotOpts') && ~isempty(opts.plotOpts)
    if ~isstruct(opts.plotOpts)
        error('gazeHeatDay:BadPlotOpts', 'opts.plotOpts must be a struct.');
    end
    plotOpts = opts.plotOpts;
end

collectOpts = localRemoveFields(opts, {'groupingArg', 'plot', 'plotOpts'});
end


function value = localDefaultFalse(opts, fieldName)
if isfield(opts, fieldName) && ~isempty(opts.(fieldName))
    raw = opts.(fieldName);
    value = logical(raw(1));
else
    value = false;
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
tok = regexp(lower(s), '^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s*([0-9]{1,2})$', 'tokens', 'once');
if isempty(tok)
    error('gazeHeatDay:BadDate', ...
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
