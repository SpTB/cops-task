function T = comparePars(outOrDate, dateArg, opts)
% comparePars Compare session parameters across sessions for one day.
%
% Usage:
%   T = comparePars(out, '2-May-2026')
%   T = comparePars('2-May-2026')
%   T = comparePars(out, '2-May-2026', struct('show_diff', true))
%
% If the first argument is not a collected-summary struct, it is treated as
% the date input and the function tries to find a collected-summary struct
% in the base workspace (variables checked in order: out, ly, ka, lychee, kaki).

if nargin < 1
    error('comparePars:MissingInput', ...
        'Provide either comparePars(out, date) or comparePars(date).');
end

if nargin < 3 || isempty(opts)
    opts = struct();
end
if ~isfield(opts, 'show_diff')
    opts.show_diff = true;
end
opts.show_diff = logical(opts.show_diff);

if isstruct(outOrDate) && isfield(outOrDate, 'fileTable')
    out = outOrDate;
    if nargin < 2 || isempty(dateArg)
        error('comparePars:MissingDate', 'A date must be provided.');
    end
    dateInput = dateArg;
else
    out = resolveDefaultCollectedOutLocal();
    dateInput = outOrDate;
end

if ~isfield(out, 'fileTable') || ~istable(out.fileTable) || isempty(out.fileTable)
    error('comparePars:MissingFileTable', ...
        'Collected output must contain a non-empty out.fileTable.');
end

targetDate = parseCompareDateLocal(dateInput);
fileTable = out.fileTable;

if ismember('status', fileTable.Properties.VariableNames)
    keep = strcmp(string(fileTable.status), "included_for_summary");
    fileTable = fileTable(keep, :);
end
if isempty(fileTable)
    error('comparePars:NoIncludedSessions', 'No included sessions found in out.fileTable.');
end
if ~ismember('sessionDate', fileTable.Properties.VariableNames)
    error('comparePars:MissingSessionDate', 'out.fileTable must contain sessionDate.');
end

sessionDate = fileTable.sessionDate;
if ~isdatetime(sessionDate)
    error('comparePars:BadSessionDate', 'out.fileTable.sessionDate must be datetime.');
end
mask = year(sessionDate) == year(targetDate) & month(sessionDate) == month(targetDate) & day(sessionDate) == day(targetDate);
fileTable = fileTable(mask, :);

if isempty(fileTable)
    T = table();
    return
end

sortVars = intersect({'fileTimestamp', 'fileName'}, fileTable.Properties.VariableNames, 'stable');
if ~isempty(sortVars)
    fileTable = sortrows(fileTable, sortVars);
end

fileTable.sessionNo = (1:height(fileTable))';
fileTable = movevars(fileTable, 'sessionNo', 'After', 'sessionDate');

idVars = intersect({'sessionDate', 'sessionNo', 'fileTimestamp'}, fileTable.Properties.VariableNames, 'stable');
paramVars = setdiff(fileTable.Properties.VariableNames, ...
    {'subject', 'sessionFolder', 'sessionDate', 'sessionNo', 'filePath', 'fileName', 'fileTimestamp', 'status', 'message'}, ...
    'stable');

if opts.show_diff
    keepParam = false(size(paramVars));
    for i = 1:numel(paramVars)
        keepParam(i) = valuesDifferLocal(fileTable.(paramVars{i}));
    end
    paramVars = paramVars(keepParam);
end

T = fileTable(:, [idVars, paramVars]);

if nargout == 0
    disp(T);
end
end


function out = resolveDefaultCollectedOutLocal()
candidates = {'out', 'ly', 'ka', 'lychee', 'kaki'};
for i = 1:numel(candidates)
    varName = candidates{i};
    try
        exists = evalin('base', sprintf('exist(''%s'',''var'')', varName));
    catch
        exists = 0;
    end
    if exists == 1
        out = evalin('base', varName);
        if isstruct(out) && isfield(out, 'fileTable')
            return
        end
    end
end
error('comparePars:NoDefaultOut', ...
    'Could not find a collected-summary struct in the base workspace. Pass out explicitly.');
end


function dt = parseCompareDateLocal(value)
if isa(value, 'datetime')
    dt = datetime(year(value), month(value), day(value));
    return
end

if ~(ischar(value) || isstring(value))
    error('comparePars:BadDate', 'Date must be a string, char vector, or datetime.');
end

value = char(string(value));
fmts = {'d-MMM-yyyy', 'dd-MMM-yyyy', 'yyyy.MM.dd', 'yyyy-MM-dd'};
for i = 1:numel(fmts)
    try
        dt = datetime(value, 'InputFormat', fmts{i});
        dt = datetime(year(dt), month(dt), day(dt));
        return
    catch
    end
end

try
    dt = datetime(value);
    dt = datetime(year(dt), month(dt), day(dt));
catch
    error('comparePars:BadDate', 'Could not parse date: %s', value);
end
end


function tf = valuesDifferLocal(v)
if isnumeric(v) || islogical(v)
    if isempty(v)
        tf = false;
        return
    end
    tf = numel(unique(v(~isnan(double(v))))) > 1;
    if all(isnan(double(v)))
        tf = false;
    end
    return
end

if isdatetime(v)
    vv = v(~isnat(v));
    tf = numel(unique(vv)) > 1;
    return
end

if isstring(v) || ischar(v) || iscategorical(v)
    vals = string(v);
    vals = vals(strlength(strtrim(vals)) > 0 & vals ~= "<missing>");
    tf = numel(unique(vals)) > 1;
    return
end

if iscell(v)
    if isempty(v)
        tf = false;
        return
    end
    base = v{1};
    same = cellfun(@(x) isequaln(x, base), v);
    tf = ~all(same);
    return
end

tf = false;
end
