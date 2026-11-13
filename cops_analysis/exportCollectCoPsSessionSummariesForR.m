function exportCollectCoPsSessionSummariesForR(matInput, outDir)
% Export collectCoPsSessionSummaries outputs to CSV files that R can read.

[out, sourceStem] = resolveExportInput(matInput);
if nargin < 2
    outDir = resolveDefaultExportOutDir(out, sourceStem);
else
    outDir = resolveExportOutDir(outDir);
end
if ~isfolder(outDir)
    mkdir(outDir);
end

trialAgg = stackSummaryTables(out.trialAggregate);
poolSum = stackSummaryTables(out.pooledSummary);
trials = extractTrialsTable(out);
iri = extractIriTable(out);
pars = extractGroupTable(out);

baseName = buildExportBaseName(sourceStem, out, outDir);
writetable(trialAgg, fullfile(outDir, [baseName '_trialAgg.csv']));
writetable(poolSum, fullfile(outDir, [baseName '_poolSum.csv']));
writetable(trials, fullfile(outDir, [baseName '_trials.csv']));
writetable(iri, fullfile(outDir, [baseName '_iri.csv']));
writetable(pars, fullfile(outDir, [baseName '_pars.csv']));
end


function [out, sourceStem] = resolveExportInput(matInput)
sourceStem = 'summary';

if isstruct(matInput)
    if isfield(matInput, 'pooledSummary') && isfield(matInput, 'trialAggregate')
        out = matInput;
        return
    end
    if isfield(matInput, 'out')
        out = matInput.out;
        sourceStem = 'out';
        return
    end
    if isfield(matInput, 'out2')
        out = matInput.out2;
        sourceStem = 'out2';
        return
    end
    error('exportCollectCoPsSessionSummariesForR:InvalidStructInput', ...
        'Struct input must be an exported summary struct or contain field ''out''/''out2''.');
end

if ~(ischar(matInput) || isstring(matInput))
    error('exportCollectCoPsSessionSummariesForR:InvalidInput', ...
        'First argument must be a MAT-file path or an output struct.');
end

matPath = char(string(matInput));
s = load(matPath);
if isfield(s, 'out')
    out = s.out;
elseif isfield(s, 'out2')
    out = s.out2;
else
    error('exportCollectCoPsSessionSummariesForR:MissingOut', ...
        'MAT file does not contain variable ''out'' or ''out2''.');
end
[~, sourceStem] = fileparts(matPath);
end


function outDir = resolveExportOutDir(outDirArg)
baseDir = '/home/vpixx/vsgui/vsg/cops_analysis/example_data';

if isstring(outDirArg) || ischar(outDirArg)
    outDirArg = char(string(outDirArg));
else
    error('exportCollectCoPsSessionSummariesForR:InvalidOutDir', ...
        'outDir must be a char vector or string scalar.');
end

tag = strtrim(outDirArg);
if isempty(tag)
    outDir = baseDir;
    return
end

if ~contains(tag, filesep) && ~contains(tag, '/') && ~contains(tag, '\')
    outDir = fullfile(baseDir, [tag '_csv']);
else
    outDir = tag;
end
end


function outDir = resolveDefaultExportOutDir(out, sourceStem)
baseDir = '/home/vpixx/vsgui/vsg/cops_analysis/example_data';
subjectId = inferSubjectIdForExport(out, sourceStem, '');
subjectDir = subjectIdToExportDirTag(subjectId);
outDir = fullfile(baseDir, [subjectDir '_csv']);
end


function stacked = stackSummaryTables(summaryStruct)
statNames = {'mean', 'sd', 'se'};
pieces = cell(0, 1);
for i = 1:numel(statNames)
    statName = statNames{i};
    if ~isfield(summaryStruct, statName)
        continue
    end
    T = summaryStruct.(statName);
    if ~istable(T) || isempty(T)
        continue
    end
    T.stat = repmat(string(statName), height(T), 1);
    pieces{end+1, 1} = movevars(T, 'stat', 'After', width(T)); %#ok<AGROW>
end

if isempty(pieces)
    stacked = table('Size', [0 1], ...
        'VariableTypes', {'string'}, ...
        'VariableNames', {'stat'});
    return
end

stacked = vertcat(pieces{:});
stacked.stat = categorical(stacked.stat, statNames, 'Ordinal', false);
end


function trials = extractTrialsTable(out)
if isfield(out, 'trials') && istable(out.trials)
    trials = out.trials;
else
    trials = table();
end
end


function iri = extractIriTable(out)
if isfield(out, 'iri') && istable(out.iri)
    iri = out.iri;
else
    iri = table();
end
end


function pars = extractGroupTable(out)
if isfield(out, 'meta') && isstruct(out.meta) && isfield(out.meta, 'groupTable') && istable(out.meta.groupTable)
    pars = out.meta.groupTable;
else
    pars = table();
end
end


function baseName = buildExportBaseName(sourceStem, out, outDir)
stem = char(string(sourceStem));
subjectId = inferSubjectIdForExport(out, stem, outDir);

summaryType = 'summary';
dateLabel = '';
if isfield(out, 'options') && isstruct(out.options)
    if isfield(out.options, 'summaryType') && ~isempty(out.options.summaryType)
        summaryType = char(string(out.options.summaryType));
    end
    dateLabel = buildDateRangeLabel(out.options);
end
dateLabel = finalizeExportDateLabel(dateLabel, out);
if isempty(dateLabel)
    dateLabel = inferDateRangeLabelFromOut(out);
end
if isempty(dateLabel)
    dateLabel = buildDateRangeLabelFromStem(stem, subjectId);
end

parts = {subjectId};
if ~isempty(dateLabel)
    parts{end+1} = dateLabel; %#ok<AGROW>
end
parts{end+1} = summaryType;
baseName = strjoin(parts, '_');
baseName = regexprep(baseName, '[^A-Za-z0-9_]', '');
end


function subjectId = inferSubjectIdForExport(out, sourceStem, outDir)
stem = char(string(sourceStem));
tokens = regexp(stem, '^([A-Za-z0-9]+)', 'tokens', 'once');
if isempty(tokens)
    subjectId = 'summary';
else
    subjectId = char(string(tokens{1}));
end
if strcmp(subjectId, 'summary') || strcmp(subjectId, 'out') || strcmp(subjectId, 'out2')
    subjectId = inferSubjectIdFromOutStruct(out, subjectId);
end
if (strcmp(subjectId, 'summary') || strcmp(subjectId, 'out') || strcmp(subjectId, 'out2')) && ~isempty(outDir)
    subjectId = inferSubjectIdFromOutDir(outDir, subjectId);
end
end


function subjectId = inferSubjectIdFromOutStruct(out, fallback)
subjectId = fallback;
if isfield(out, 'meta') && isstruct(out.meta) && isfield(out.meta, 'groupTable') && istable(out.meta.groupTable)
    T = out.meta.groupTable;
    candidateVars = {'subjectId', 'subject', 'monkey'};
    for i = 1:numel(candidateVars)
        v = candidateVars{i};
        if ismember(v, T.Properties.VariableNames) && ~isempty(T.(v))
            vals = string(T.(v));
            vals = vals(strlength(strtrim(vals)) > 0);
            if ~isempty(vals)
                subjectId = char(vals(1));
                return
            end
        end
    end
end
end


function tag = subjectIdToExportDirTag(subjectId)
subjectId = lower(char(string(subjectId)));
if startsWith(subjectId, 'ly')
    tag = 'ly';
elseif startsWith(subjectId, 'ka')
    tag = 'ka';
else
    tag = subjectId;
end
end


function subjectId = inferSubjectIdFromOutDir(outDir, fallback)
[~, leaf] = fileparts(char(string(outDir)));
leaf = char(string(leaf));
match = regexp(leaf, '^([A-Za-z0-9]+)_csv$', 'tokens', 'once');
if ~isempty(match)
    subjectId = match{1};
else
    subjectId = fallback;
end
end


function label = buildDateRangeLabel(opts)
label = '';
if ~isfield(opts, 'dateFrom') || ~isfield(opts, 'dateTo')
    return
end

dateFrom = coerceToDatetime(opts.dateFrom);
dateTo = coerceToDatetime(opts.dateTo);

if isempty(dateFrom) && isempty(dateTo)
    return
elseif ~isempty(dateFrom) && ~isempty(dateTo)
    label = [formatFileDate(dateFrom) formatFileDate(dateTo)];
elseif ~isempty(dateFrom)
    label = [formatFileDate(dateFrom) 'onward'];
else
    label = ['upto' formatFileDate(dateTo)];
end
end


function label = finalizeExportDateLabel(label, out)
label = char(string(label));
if isempty(label)
    return
end

if endsWith(label, 'onward') || startsWith(label, 'upto')
    inferredLabel = inferDateRangeLabelFromOut(out);
    if ~isempty(inferredLabel)
        label = inferredLabel;
        return
    end

    todayToken = formatFileDate(datetime('today'));
    if endsWith(label, 'onward')
        startToken = extractBefore(string(label), "onward");
        label = char(startToken + todayToken);
    elseif startsWith(label, 'upto')
        endToken = extractAfter(string(label), 4);
        label = char(todayToken + endToken);
    end
end
end


function label = buildDateRangeLabelFromStem(stem, subjectId)
label = '';
remainder = regexprep(stem, ['^' regexptranslate('escape', subjectId) '_?'], '');

match = regexp(remainder, '(\d{1,2}[A-Z][a-z]{2}\d{1,2}[A-Z][a-z]{2})', 'tokens', 'once');
if ~isempty(match)
    label = normalizeStemDateLabel(match{1});
    return
end

match = regexp(remainder, '(upto\d{1,2}[A-Z][a-z]{2})', 'tokens', 'once');
if ~isempty(match)
    label = ['upto' normalizeDdMonToken(extractAfter(string(match{1}), 4))];
    return
end

match = regexp(remainder, '(\d{1,2}[A-Z][a-z]{2}onward)', 'tokens', 'once');
if ~isempty(match)
    label = [normalizeDdMonToken(extractBefore(string(match{1}), "onward")) 'onward'];
end
end


function label = inferDateRangeLabelFromOut(out)
label = '';
dates = [];

if isfield(out, 'meta') && isstruct(out.meta) && isfield(out.meta, 'groupTable') && istable(out.meta.groupTable) ...
        && ismember('sessionDate', out.meta.groupTable.Properties.VariableNames)
    dates = out.meta.groupTable.sessionDate;
elseif isfield(out, 'fileTable') && istable(out.fileTable) && ismember('sessionDate', out.fileTable.Properties.VariableNames)
    dates = out.fileTable.sessionDate;
elseif isfield(out, 'trials') && istable(out.trials) && ismember('sessionDate', out.trials.Properties.VariableNames)
    dates = out.trials.sessionDate;
end

if isempty(dates) || ~isdatetime(dates)
    return
end

dates = dates(~isnat(dates));
if isempty(dates)
    return
end

dateFrom = min(dates);
dateTo = max(dates);
if isequal(dateFrom, dateTo)
    label = formatFileDate(dateFrom);
else
    label = [formatFileDate(dateFrom) formatFileDate(dateTo)];
end
end


function label = normalizeStemDateLabel(token)
token = char(string(token));
parts = regexp(token, '(\d{1,2}[A-Z][a-z]{2})(\d{1,2}[A-Z][a-z]{2})', 'tokens', 'once');
if isempty(parts)
    label = token;
    return
end
label = [normalizeDdMonToken(parts{1}) normalizeDdMonToken(parts{2})];
end


function tokenOut = normalizeDdMonToken(tokenIn)
tokenIn = char(string(tokenIn));
parts = regexp(tokenIn, '^(\d{1,2})([A-Z][a-z]{2})$', 'tokens', 'once');
if isempty(parts)
    tokenOut = tokenIn;
    return
end
tokenOut = [parts{2} parts{1}];
end


function dt = coerceToDatetime(value)
dt = [];
if isempty(value)
    return
end

if isa(value, 'datetime')
    dt = value;
    return
end

if ischar(value) || isstring(value)
    value = char(string(value));
    if isempty(strtrim(value))
        return
    end
    try
        dt = datetime(value, 'InputFormat', 'yyyy.MM.dd');
    catch
        dt = [];
    end
end
end


function s = formatFileDate(dt)
s = datestr(datetime(year(dt), month(dt), day(dt)), 'mmmdd');
s(1) = upper(s(1));
end
