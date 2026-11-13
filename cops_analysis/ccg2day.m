function out = ccg2day(subject, groupingArg, dateValue, opts)
% ccg2day  Collect and plot one-day CoPs CCG2 aggregates.
%
%   C = ccg2day('ka')
%   C = ccg2day('ka', 'vis')
%   C = ccg2day('ka', 'vis', 'Jun18')
%   C = ccg2day('ka', 'Jun18')
%   C = ccg2day('ka', 'vis', 'Jun18', opts)
%
% This is intentionally single-day only. By default it uses today's date.
%
% opts fields are passed to collectCCG2, except:
%   opts.date     : single date, if no dateValue argument is supplied
%   opts.plot     : true/false, whether to call plotCCG2Aggregate
%   opts.plotOpts : options struct passed to plotCCG2Aggregate
%   opts.showError: convenience alias for opts.plotOpts.showError
%   opts.semSource: 'chunk' (default), 'trial', or 'session' for the
%                   plotted uncertainty in this one-day wrapper
%   opts.trackingSource: target-identity source forwarded to CCG. Options:
%                   'hmmFiltered' (default), 'hmmSmoothed', or
%                   'hmmPredictive' use the corresponding hard HMM TLeft
%                   states; 'model-free' uses referenceTargetMode instead.
%                   Missing requested HMM predictions produce an error
%                   rather than falling back to model-free.
%   opts.hmmHardThreshold: minimum target probability for two-state HMM
%       assignment; three-state HMMs use winner-take-all across T1/T2/N;
%                   default 0.9
%   opts.minTrackingSec: minimum hard-HMM target run; default 0.1 s
%   opts.trackingBridgeMaxSec: maximum bridged internal tracking
%                   interruption; default 0.1 s
%   opts.interpBlinkSec: gaze-gap interpolation limit; default 0.15 s;
%                   set to 0 to keep blinks and missing gaze masked

if nargin < 1 || isempty(subject)
    error('ccg2day:MissingSubject', 'Provide a subject, e.g. ccg2day(''ka'').');
end
if nargin < 2
    groupingArg = [];
end
if nargin < 3
    dateValue = [];
end
if nargin < 4 || isempty(opts)
    opts = struct();
elseif ~isstruct(opts)
    error('ccg2day:BadOpts', 'opts must be a struct.');
end

if isstruct(groupingArg)
    opts = localMergeStructs(groupingArg, opts);
    groupingArg = [];
    dateValue = [];
elseif isstruct(dateValue)
    opts = localMergeStructs(dateValue, opts);
    dateValue = [];
    if localLooksLikeDate(groupingArg)
        dateValue = groupingArg;
        groupingArg = [];
    end
elseif isempty(dateValue) && localLooksLikeDate(groupingArg)
    dateValue = groupingArg;
    groupingArg = [];
end

[dayDate, opts] = localResolveDayDate(dateValue, opts);
[doPlot, plotOpts, collectOpts, semSource] = localSplitOptions(opts);

collectOpts.dateFrom = dayDate;
collectOpts.dateTo = dayDate;

A = collectCCG2(subject, groupingArg, collectOpts);
A = localApplyDaySemSource(A, semSource, collectOpts);
if doPlot
    P = plotCCG2Aggregate(A, plotOpts);
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
        error('ccg2day:DateConflict', 'dateValue and opts.date refer to different days.');
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
    error('ccg2day:DateRangeNotSingleDay', ...
        'ccg2day is only valid for one day; opts.dateFrom must match the selected date.');
end
if hasDateTo && ~localSameDay(dayDate, localParseDate(opts.dateTo))
    error('ccg2day:DateRangeNotSingleDay', ...
        'ccg2day is only valid for one day; opts.dateTo must match the selected date.');
end

opts = localRemoveFields(opts, {'date', 'dateFrom', 'dateTo'});
end


function [doPlot, plotOpts, collectOpts, semSource] = localSplitOptions(opts)
doPlot = true;
if isfield(opts, 'plot') && ~isempty(opts.plot)
    doPlot = logical(opts.plot(1));
end

plotOpts = struct();
if isfield(opts, 'plotOpts') && ~isempty(opts.plotOpts)
    if ~isstruct(opts.plotOpts)
        error('ccg2day:BadPlotOpts', 'opts.plotOpts must be a struct.');
    end
    plotOpts = opts.plotOpts;
end
if isfield(opts, 'showError') && ~isempty(opts.showError)
    plotOpts.showError = logical(opts.showError(1));
end

semSource = 'trial';
if isfield(opts, 'semSource') && ~isempty(opts.semSource)
    semSource = validatestring(char(string(opts.semSource)), {'chunk', 'trial', 'session'});
end

collectOpts = localRemoveFields(opts, {'plot', 'plotOpts', 'showError', 'semSource'});
end


function A = localApplyDaySemSource(A, semSource, collectOpts)
if ~isstruct(A) || ~isfield(A, 'groups') || isempty(A.groups)
    return
end
source = validatestring(char(string(semSource)), {'chunk', 'trial', 'session'});
switch source
    case 'session'
        return
    case 'trial'
        fieldName = 'ccg2D';
    otherwise
        fieldName = 'chunkCcg2D';
end

for iGroup = 1:numel(A.groups)
    label = "";
    if isfield(A, 'groupLabels') && numel(A.groupLabels) >= iGroup
        label = string(A.groupLabels(iGroup));
    elseif isstruct(A.groups{iGroup}) && isfield(A.groups{iGroup}, 'groupLabel')
        label = string(A.groups{iGroup}.groupLabel);
    end
    curves = localCollectDayRows(A, A.sessionOutputs, label, fieldName, collectOpts);
    A.groups{iGroup}.sem2D = localNanSem(curves);
end
if isfield(A, 'controlAggregate') && isstruct(A.controlAggregate) && ...
        isfield(A.controlAggregate, 'groups') && ~isempty(A.controlAggregate.groups)
    for iGroup = 1:numel(A.controlAggregate.groups)
        label = "";
        if isfield(A.controlAggregate, 'groupLabels') && numel(A.controlAggregate.groupLabels) >= iGroup
            label = string(A.controlAggregate.groupLabels(iGroup));
        elseif isstruct(A.controlAggregate.groups{iGroup}) && isfield(A.controlAggregate.groups{iGroup}, 'groupLabel')
            label = string(A.controlAggregate.groups{iGroup}.groupLabel);
        end
        curves = localCollectDayRows(A.controlAggregate, A.controlSessionOutputs, label, fieldName, collectOpts);
        A.controlAggregate.groups{iGroup}.sem2D = localNanSem(curves);
    end
end
if ~isfield(A, 'uncertainty')
    A.uncertainty = struct();
end
A.uncertainty.source = string(source);
end


function curves = localCollectDayRows(A, sessionOutputs, label, fieldName, collectOpts)
curves = NaN(0, numel(double(A.lagSec(:)')));
if nargin < 2 || isempty(sessionOutputs)
    return
end
referenceLagSec = double(A.lagSec(:)');
for iSession = 1:numel(sessionOutputs)
    U = sessionOutputs{iSession};
    if ~isstruct(U) || ~isfield(U, 'groups') || isempty(U.groups)
        continue
    end
    sessionLagSec = localSessionLagSec(U);
    if isempty(sessionLagSec)
        continue
    end
    sessionLabels = localOutputGroupLabels(U);
    for g = 1:numel(U.groups)
        if g > numel(sessionLabels)
            continue
        end
        if ~localGroupLabelMatches(sessionLabels(g), label)
            continue
        end
        group = U.groups{g};
        if ~isstruct(group) || ~isfield(group, fieldName) || isempty(group.(fieldName))
            continue
        end
        rows = double(group.(fieldName));
        rows = localRowsOnReferenceLag(rows, sessionLagSec, referenceLagSec, collectOpts);
        if ~isempty(rows)
            curves = [curves; rows]; %#ok<AGROW>
        end
        break
    end
end
end


function rowsOut = localRowsOnReferenceLag(rowsIn, sessionLagSec, referenceLagSec, collectOpts)
rowsOut = NaN(0, numel(referenceLagSec));
rowsIn = double(rowsIn);
sessionLagSec = double(sessionLagSec(:)');
referenceLagSec = double(referenceLagSec(:)');
if isempty(rowsIn) || isempty(sessionLagSec) || isempty(referenceLagSec)
    return
end
if size(rowsIn, 2) ~= numel(sessionLagSec)
    return
end
idx = localLagIndexMap(sessionLagSec, referenceLagSec, collectOpts);
if isempty(idx)
    return
end
rowsOut = NaN(size(rowsIn, 1), numel(referenceLagSec));
keep = isfinite(idx);
rowsOut(:, keep) = rowsIn(:, idx(keep));
end


function idx = localLagIndexMap(sessionLagSec, referenceLagSec, collectOpts)
idx = NaN(1, numel(referenceLagSec));
tol = 1e-6;
if isstruct(collectOpts) && isfield(collectOpts, 'lagToleranceSec') && ~isempty(collectOpts.lagToleranceSec)
    tol = double(collectOpts.lagToleranceSec(1));
end
for i = 1:numel(referenceLagSec)
    delta = abs(sessionLagSec - referenceLagSec(i));
    [minDelta, j] = min(delta);
    if ~isempty(j) && isfinite(minDelta) && minDelta <= tol
        idx(i) = j;
    end
end
end


function labels = localOutputGroupLabels(U)
labels = strings(0, 1);
if isstruct(U) && isfield(U, 'groupLabels') && ~isempty(U.groupLabels)
    labels = string(U.groupLabels(:));
elseif isstruct(U) && isfield(U, 'groups') && ~isempty(U.groups)
    labels = strings(numel(U.groups), 1);
    for i = 1:numel(U.groups)
        if isstruct(U.groups{i}) && isfield(U.groups{i}, 'groupLabel')
            labels(i) = string(U.groups{i}.groupLabel);
        end
    end
end
end


function lagSec = localSessionLagSec(U)
lagSec = [];
if isstruct(U) && isfield(U, 'lagSec') && ~isempty(U.lagSec)
    lagSec = double(U.lagSec(:)');
end
end


function tf = localGroupLabelMatches(a, b)
tf = strcmp(strtrim(string(a)), strtrim(string(b)));
end


function semRow = localNanSem(curves)
if isempty(curves)
    semRow = NaN(1, 0);
    return
end
semRow = NaN(1, size(curves, 2));
for i = 1:size(curves, 2)
    y = curves(:, i);
    y = y(isfinite(y));
    if numel(y) >= 2
        semRow(i) = std(y, 0) ./ sqrt(numel(y));
    elseif numel(y) == 1
        semRow(i) = NaN;
    end
end
end


function tf = localLooksLikeDate(value)
tf = false;
if isempty(value) || ~(ischar(value) || (isstring(value) && isscalar(value)) || isdatetime(value))
    return
end
if isdatetime(value)
    tf = true;
    return
end
s = strtrim(char(string(value)));
if strcmpi(s, 'today')
    tf = true;
    return
end
if ~isempty(regexp(s, '^\d{4}\.\d{2}\.\d{2}$', 'once'))
    tf = true;
    return
end
tf = ~isempty(regexp(lower(s), '^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s*[0-9]{1,2}$', 'once'));
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
    error('ccg2day:BadDate', ...
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
