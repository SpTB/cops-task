function out = collectCoPsSessionSummaries(subject, opts)
% collectCoPsSessionSummaries
% Aggregate processCoPsEye sessionSummary outputs across CoPs session files
% for one subject.
%
% out = collectCoPsSessionSummaries('kaki')
% out = collectCoPsSessionSummaries('kaki', 'today')
% out = collectCoPsSessionSummaries('kaki', opts)
%
% Inputs
%   subject : subject folder name under opts.dataRoot
%   opts    : optional struct with fields, or the string 'today' to filter
%             only files whose saved timestamp is today
%       .dataRoot          root CoPs data directory
%       .dateFrom          inclusive start date ('YYYY.MM.DD', 'Mar27',
%                          or datetime)
%       .dateTo            inclusive end date ('YYYY.MM.DD', 'Mar27',
%                          or datetime)
%       .savedTodayOnly    when true, include only files whose saved
%                          timestamp is on the current date
%       .minTrials         minimum main-task trials in a session
%       .minTrialsPerDay   minimum pooled main-task trials in a day-group
%                          for that day to be included when
%                          opts.summaryType == 'day'
%       .analysisOpts      options struct passed into processCoPsEye
%       .requiredParams    struct of required session parameters
%                          supported fields:
%                          nsteps, waitSecs, gaussScalar, targetNum,
%                          rewardThreshold, tutorialThreshold,
%                          backgroundNoiseMain, backgroundNoiseTutorial,
%                          targetVisibility,
%                          freeViewing
%       .summaryType       aggregation mode: 'day' (default), 'session',
%                          or 'all'
%       .sessionConditions struct array with fields:
%                          path, op, value
%                          Example:
%                          struct('path','exp.CoPs.rew.threshold','op','>','value',100)
%       .verbose           print progress
%       .save              when true, save the output struct as a MAT file
%                          in cops_analysis/example_data
%
% Output
%   out.pooledSummary  : struct with tables .mean and .sd
%   out.trialAggregate : struct with tables .mean, .sd, and .se
%   out.trials         : concatenated per-trial rows from processCoPsEye
%                        with identifier columns for day/session/trial
%   out.iri            : concatenated inter-reward-interval rows from
%                        processCoPsEye with identifier columns for
%                        day/session/trial
%   out.fileTable      : candidate file inventory with inclusion status
%   out.meta           : provenance and parameter metadata
%   out.options        : resolved options

if nargin < 2 || isempty(opts)
    opts = struct();
elseif (ischar(opts) || isstring(opts)) && isscalar(string(opts))
    shorthand = lower(strtrim(string(opts)));
    if shorthand == "today"
        opts = struct('savedTodayOnly', true);
    else
        error('collectCoPsSessionSummaries:InvalidSecondArgument', ...
            'Second argument must be an options struct or the string ''today''.');
    end
end

if ~(ischar(subject) || isstring(subject))
    error('collectCoPsSessionSummaries:InvalidSubject', ...
        'subject must be a char vector or string scalar.');
end

defaultDataRoot = "/media/vpixx/DATA/CoPs";
if ~exist(char(defaultDataRoot), 'dir')
    defaultDataRoot = "Y:\data\CoPs";
end
defaults = struct( ...
    'dataRoot', defaultDataRoot, ...
    'dateFrom', [], ...
    'dateTo', [], ...
    'savedTodayOnly', false, ...
    'minTrials', 10, ...
    'minTrialsPerDay', 50, ...
    'analysisOpts', struct(), ...
    'requiredParams', struct(), ...
    'summaryType', 'day', ...
    'sessionConditions', [ ...
        struct('path', 'exp.CoPs.rew.threshold', 'op', '>', 'value', 100), ...
        struct('path', 'exp.CoPs.ctl.nsteps', 'op', '>=', 'value', 100)], ...
    'verbose', true, ...
    'save', false);
       % struct('path', 'exp.CoPs.ctl.reward_type', 'op', '==', 'value', 'mult')], ...
       % struct('path', 'exp.CoPs.graph.background_noise_lvl', 'op', '==', 'value', [0 5 50]), ...

defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field)
        opts.(field) = defaults.(field);
    end
end

if ~isscalar(opts.minTrials) || ~isnumeric(opts.minTrials) || opts.minTrials < 0
    error('collectCoPsSessionSummaries:InvalidMinTrials', ...
        'opts.minTrials must be a nonnegative numeric scalar.');
end
if ~isscalar(opts.minTrialsPerDay) || ~isnumeric(opts.minTrialsPerDay) || opts.minTrialsPerDay < 0
    error('collectCoPsSessionSummaries:InvalidMinTrialsPerDay', ...
        'opts.minTrialsPerDay must be a nonnegative numeric scalar.');
end
if ~isscalar(opts.savedTodayOnly) || ~(islogical(opts.savedTodayOnly) || isnumeric(opts.savedTodayOnly))
    error('collectCoPsSessionSummaries:InvalidSavedTodayOnly', ...
        'opts.savedTodayOnly must be a logical scalar.');
end
opts.savedTodayOnly = logical(opts.savedTodayOnly);
if ~isscalar(opts.save) || ~(islogical(opts.save) || isnumeric(opts.save))
    error('collectCoPsSessionSummaries:InvalidSave', ...
        'opts.save must be a logical scalar.');
end
opts.save = logical(opts.save);

opts.summaryType = validatestring(char(string(opts.summaryType)), {'day', 'session', 'all'});

subject = char(subject);
subjectDir = fullfile(char(opts.dataRoot), subject);
if ~exist(subjectDir, 'dir')
    error('collectCoPsSessionSummaries:SubjectNotFound', ...
        'Subject directory not found: %s', subjectDir);
end

dateFrom = parseDateBound(opts.dateFrom, false);
dateTo = parseDateBound(opts.dateTo, true);
todayDate = datetime('today');

sessionDirs = dir(subjectDir);
sessionDirs = sessionDirs([sessionDirs.isdir]);
sessionDirs = sessionDirs(~ismember({sessionDirs.name}, {'.', '..'}));

fileRows = struct([]);
summaryGroups = struct('groupKey', {}, 'sessionFolder', {}, 'sessionDate', {}, ...
    'startTime', {}, 'sessionNames', {}, 'filePaths', {}, 'fileRowIdx', {}, 'params', {}, 'procOutList', {});

analysisOpts = opts.analysisOpts;
if isempty(fieldnames(analysisOpts)) && opts.verbose
    fprintf('Using default processCoPsEye analysis options.\n');
end

for i = 1:numel(sessionDirs)
    sessionDir = sessionDirs(i);
    [sessionDate, hasDate] = parseSessionFolderDate(sessionDir.name);
    if ~hasDate
        continue
    end
    if ~isempty(dateFrom) && sessionDate < dateFrom
        continue
    end
    if ~isempty(dateTo) && sessionDate > dateTo
        continue
    end

    dateDir = fullfile(sessionDir.folder, sessionDir.name);
    candidateFiles = listSessionExFiles(dateDir);

    for k = 1:numel(candidateFiles)
        filePath = candidateFiles{k};
        if opts.verbose
            fprintf('Checking %s\n', filePath);
        end

        fileInfo = initFileRow(subject, sessionDir.name, sessionDate, filePath);
        if opts.savedTodayOnly && ~isFileTimestampOnDate(fileInfo.fileTimestamp, todayDate)
            fileInfo.status = "saved_date_filtered";
            fileInfo.message = sprintf('fileTimestamp=%s is not today (%s)', ...
                char(string(fileInfo.fileTimestamp)), char(string(todayDate)));
            fileRows = appendStructRow(fileRows, fileInfo);
            continue
        end
        try
            s = load(filePath);
        catch err
            fileInfo.status = "load_failed";
            fileInfo.message = string(err.message);
            fileRows = appendStructRow(fileRows, fileInfo);
            continue
        end

        if ~isfield(s, 'ex') || ~isstruct(s.ex) || ~isfield(s.ex, 'Trials')
            fileInfo.status = "missing_ex";
            fileInfo.message = "File does not contain ex.Trials";
            fileRows = appendStructRow(fileRows, fileInfo);
            continue
        end

        ex = s.ex;
        params = extractSessionParams(ex);
        fileInfo = applyParamsToFileRow(fileInfo, params);

        [matchesRequired, mismatchMsg] = matchesRequiredParams(params, opts.requiredParams);
        if ~matchesRequired
            fileInfo.status = "param_filtered";
            fileInfo.message = string(mismatchMsg);
            fileRows = appendStructRow(fileRows, fileInfo);
            continue
        end

        [matchesConditions, conditionMsg] = matchesSessionConditions(ex, opts.sessionConditions);
        if ~matchesConditions
            fileInfo.status = "condition_filtered";
            fileInfo.message = string(conditionMsg);
            fileRows = appendStructRow(fileRows, fileInfo);
            continue
        end

        nMainTrials = countMainTaskTrialsInEx(ex);
        fileInfo.nMainTrials = nMainTrials;
        if nMainTrials < opts.minTrials
            fileInfo.status = "too_few_trials";
            fileInfo.message = sprintf('nMainTrials=%d < minTrials=%d', nMainTrials, opts.minTrials);
            fileRows = appendStructRow(fileRows, fileInfo);
            continue
        end

        try
            procOut = processCoPsEye(ex, analysisOpts);
        catch err
            fileInfo.status = "summary_analysis_failed";
            fileInfo.message = string(err.message);
            fileRows = appendStructRow(fileRows, fileInfo);
            continue
        end

        fileInfo.status = "included_for_summary";
        fileInfo.message = "";
        fileRows = appendStructRow(fileRows, fileInfo);
        fileRowIdx = numel(fileRows);

        groupKey = getSummaryGroupKey(opts.summaryType, sessionDir.name, fileInfo.filePath);
        groupIdx = findSummaryGroup(summaryGroups, groupKey);
        if isempty(groupIdx)
            summaryGroups(end+1) = struct( ... %#ok<AGROW>
                'groupKey', groupKey, ...
                'sessionFolder', string(sessionDir.name), ...
                'sessionDate', sessionDate, ...
                'startTime', fileInfo.fileTimestamp, ...
                'sessionNames', {{char(fileInfo.fileName)}}, ...
                'filePaths', {{char(fileInfo.filePath)}}, ...
                'fileRowIdx', fileRowIdx, ...
                'params', {{params}}, ...
                'procOutList', {{procOut}});
        else
            summaryGroups(groupIdx).startTime = min(summaryGroups(groupIdx).startTime, fileInfo.fileTimestamp);
            summaryGroups(groupIdx).sessionNames{end+1} = char(fileInfo.fileName);
            summaryGroups(groupIdx).filePaths{end+1} = char(fileInfo.filePath);
            summaryGroups(groupIdx).fileRowIdx(end+1) = fileRowIdx;
            summaryGroups(groupIdx).params{end+1} = params;
            summaryGroups(groupIdx).procOutList{end+1} = procOut;
        end
    end
end

sessionMeanRows = struct([]);
sessionSdRows = struct([]);
trialMeanRows = struct([]);
trialSdRows = struct([]);
trialSeRows = struct([]);
metaRows = struct([]);
trialTables = cell(0, 1);
iriTables = cell(0, 1);
sessionInfoByPath = buildIncludedSessionInfoByPath(fileRows);
for i = 1:numel(summaryGroups)
    grp = summaryGroups(i);
    procOut = aggregateGroupProcOutputs(grp.procOutList);
    if strcmp(opts.summaryType, 'day') && procOut.sessionSummary.nTrials < opts.minTrialsPerDay
        continue
    end
    [groupSessionDate, groupStartTime] = getSummaryGroupDisplayTime(grp, opts.summaryType);
    groupId = initGroupIdRow(groupSessionDate, groupStartTime, numel(grp.procOutList), procOut.sessionSummary.nTrials);

    sessionMeanRows = appendStructRow(sessionMeanRows, ...
        assignFlatFields(groupId, flattenStructFields(procOut.sessionSummary.mean)));
    sessionSdRows = appendStructRow(sessionSdRows, ...
        assignFlatFields(groupId, flattenStructFields(procOut.sessionSummary.sd)));

    trialAgg = computeTrialAggregateSummary(procOut.trialSummary);
    trialMeanRows = appendStructRow(trialMeanRows, ...
        assignFlatFields(groupId, flattenStructFields(trialAgg.mean)));
    trialSdRows = appendStructRow(trialSdRows, ...
        assignFlatFields(groupId, flattenStructFields(trialAgg.sd)));
    trialSeRows = appendStructRow(trialSeRows, ...
        assignFlatFields(groupId, flattenStructFields(trialAgg.se)));

    metaRow = initGroupMetaRow(subject, grp, opts.summaryType);
    params = grp.params{1};
    metaRow = applyParamsToMetaRow(metaRow, params);
    metaRow = applyGroupParamVariationToMetaRow(metaRow, grp.params);
    metaRows = appendStructRow(metaRows, metaRow);

    groupTrialTable = buildGroupTrialsTable(grp, sessionInfoByPath);
    if ~isempty(groupTrialTable)
        trialTables{end+1, 1} = groupTrialTable; %#ok<AGROW>
    end

    groupIriTable = buildGroupIriTable(grp, sessionInfoByPath);
    if ~isempty(groupIriTable)
        iriTables{end+1, 1} = groupIriTable; %#ok<AGROW>
    end
end

sessionMeanTable = buildSummaryTable(sessionMeanRows);
sessionSdTable = buildSummaryTable(sessionSdRows);
trialMeanTable = buildSummaryTable(trialMeanRows);
trialSdTable = buildSummaryTable(trialSdRows);
trialSeTable = buildSummaryTable(trialSeRows);
if isempty(trialTables)
    trialsTable = table();
else
    trialsTable = vertcat(trialTables{:});
end

if isempty(iriTables)
    iriTable = table();
else
    iriTable = vertcat(iriTables{:});
end

if isempty(fileRows)
    fileTable = table();
else
    fileTable = struct2table(fileRows, 'AsArray', true);
    fileTable = sortrows(fileTable, {'sessionDate', 'fileName'});
end

if isempty(metaRows)
    groupTable = table();
else
    groupTable = struct2table(metaRows, 'AsArray', true);
    groupTable = sortrows(groupTable, {'sessionDate', 'startTime'});
end

out = struct();
out.pooledSummary = struct('mean', sessionMeanTable, 'sd', sessionSdTable, 'se', table());
out.trialAggregate = struct('mean', trialMeanTable, 'sd', trialSdTable, 'se', trialSeTable);
out.trials = trialsTable;
out.iri = iriTable;
out.fileTable = fileTable;
out.meta = struct( ...
    'groupTable', groupTable, ...
    'groupingUnit', string(opts.summaryType), ...
    'aggregationNotes', struct( ...
        'pooledSummary', 'Rows are grouped by out.meta.groupingUnit. Metrics are aggregated from pooled session-level outputs of processCoPsEye; mean and sd are descriptive pooled summaries, and se is intentionally not exported.', ...
        'trialAggregate', 'Rows are grouped by out.meta.groupingUnit. Metrics are aggregated across concatenated trialSummary rows within each group; mean, sd, and se are computed across trials.', ...
        'trials', 'Rows are individual trials concatenated from processCoPsEye outputs. Identifier columns include sessionDate, sessionNo (within day), and trialNo (within session).', ...
        'iri', 'Rows are inter-reward intervals concatenated from processCoPsEye outputs. Identifier columns include sessionDate, sessionNo (within day), and trialNo (within session).'));
out.options = opts;

if opts.save
    savePath = buildCollectSummarySavePath(subject, out);
    save(savePath, 'out');
end
end


function d = parseDateBound(value, useEndOfDay)
if isempty(value)
    d = [];
    return
end

if isdatetime(value)
    d = datetime(year(value), month(value), day(value));
else
    d = localParseCollectDateString(char(string(value)));
end

if useEndOfDay
    d = d + days(1) - seconds(eps);
end
end


function d = localParseCollectDateString(s)
s = strtrim(char(s));
if isempty(s)
    d = [];
    return
end

try
    d = datetime(s, 'InputFormat', 'yyyy.MM.dd');
    return
catch
end

tok = regexp(lower(s), '^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s*([0-9]{1,2})$', 'tokens', 'once');
if isempty(tok)
    error('collectCoPsSessionSummaries:InvalidDateBound', ...
        'Date bounds must be datetime, ''YYYY.MM.DD'', or month-day shorthand like ''Mar27''.');
end

monthMap = struct( ...
    'jan', 1, 'feb', 2, 'mar', 3, 'apr', 4, 'may', 5, 'jun', 6, ...
    'jul', 7, 'aug', 8, 'sep', 9, 'oct', 10, 'nov', 11, 'dec', 12);
monthNum = monthMap.(tok{1});
dayNum = str2double(tok{2});
yearNum = year(datetime('today'));

try
    d = datetime(yearNum, monthNum, dayNum);
catch
    error('collectCoPsSessionSummaries:InvalidDateBound', ...
        'Invalid month-day shorthand ''%s'' for year %d.', s, yearNum);
end
end


function [d, ok] = parseSessionFolderDate(folderName)
ok = false;
d = NaT;
tokens = regexp(folderName, '^\d{4}\.\d{2}\.\d{2}', 'match', 'once');
if isempty(tokens)
    return
end
d = datetime(tokens, 'InputFormat', 'yyyy.MM.dd');
ok = true;
end


function files = listSessionExFiles(dateDir)
files = {};

rootFiles = dir(fullfile(dateDir, '*.mat'));
rootFiles = rootFiles(~startsWith({rootFiles.name}, 'dailyLog'));
rootFiles = rootFiles(~contains({rootFiles.name}, 'EyeCal'));

for i = 1:numel(rootFiles)
    files{end+1} = fullfile(rootFiles(i).folder, rootFiles(i).name); %#ok<AGROW>
end

experimentalDir = fullfile(dateDir, 'experimental');
if exist(experimentalDir, 'dir')
    expFiles = dir(fullfile(experimentalDir, '*.mat'));
    for i = 1:numel(expFiles)
        files{end+1} = fullfile(expFiles(i).folder, expFiles(i).name); %#ok<AGROW>
    end
end

if ~isempty(files)
    files = unique(files, 'stable');
end
end


function savePath = buildCollectSummarySavePath(subject, out)
baseDir = '/home/vpixx/vsgui/vsg/cops_analysis/example_data';
if ~isfolder(baseDir)
    mkdir(baseDir);
end

dateLabel = '';
if isfield(out, 'meta') && isstruct(out.meta) && isfield(out.meta, 'groupTable') && istable(out.meta.groupTable) ...
        && ismember('sessionDate', out.meta.groupTable.Properties.VariableNames)
    dates = out.meta.groupTable.sessionDate;
    if isdatetime(dates)
        dates = dates(~isnat(dates));
        if ~isempty(dates)
            dateFrom = min(dates);
            dateTo = max(dates);
            if isequal(dateFrom, dateTo)
                dateLabel = formatCollectFileDate(dateFrom);
            else
                dateLabel = [formatCollectFileDate(dateFrom) formatCollectFileDate(dateTo)];
            end
        end
    end
end

parts = {char(subject)};
if ~isempty(dateLabel)
    parts{end+1} = dateLabel; %#ok<AGROW>
end
if isfield(out, 'options') && isstruct(out.options) && isfield(out.options, 'summaryType')
    parts{end+1} = char(string(out.options.summaryType)); %#ok<AGROW>
else
    parts{end+1} = 'summary'; %#ok<AGROW>
end
fileName = regexprep(strjoin(parts, '_'), '[^A-Za-z0-9_]', '');
savePath = fullfile(baseDir, [fileName '.mat']);
end


function s = formatCollectFileDate(dt)
s = datestr(datetime(year(dt), month(dt), day(dt)), 'mmmdd');
s(1) = upper(s(1));
end


function row = initFileRow(subject, sessionFolder, sessionDate, filePath)
[~, fileName, ext] = fileparts(filePath);
row = struct( ...
    'subject', string(subject), ...
    'sessionFolder', string(sessionFolder), ...
    'sessionDate', sessionDate, ...
    'fileTimestamp', getFileTimestamp(filePath), ...
    'fileName', string([fileName ext]), ...
    'filePath', string(filePath), ...
    'status', "", ...
    'message', "", ...
    'nMainTrials', NaN, ...
    'expNreps', NaN, ...
    'tutNreps', NaN, ...
    'totalNreps', NaN, ...
    'nsteps', NaN, ...
    'waitSecs', NaN, ...
    'gaussScalar', NaN, ...
    'targetNum', NaN, ...
    'rewardThreshold', NaN, ...
    'tutorialThreshold', NaN, ...
    'backgroundNoiseMain', NaN, ...
    'backgroundNoiseTutorial', NaN, ...
    'targetVisibility', NaN, ...
    'freeViewing', NaN);
end


function row = initGroupIdRow(sessionDate, startTimestamp, nSessions, nTrials)
row = struct( ...
    'sessionDate', sessionDate, ...
    'startTime', string(timeofdayString(startTimestamp)), ...
    'nSessions', nSessions, ...
    'nTrials', nTrials);
end


function row = initGroupMetaRow(subject, grp, summaryType)
[groupSessionDate, groupStartTime] = getSummaryGroupDisplayTime(grp, summaryType);
row = struct( ...
    'subject', string(subject), ...
    'sessionFolder', string(grp.sessionFolder), ...
    'sessionDate', groupSessionDate, ...
    'startTime', string(timeofdayString(groupStartTime)), ...
    'nSessions', numel(grp.procOutList), ...
    'nFiles', numel(grp.filePaths), ...
    'fileNames', string(strjoin(grp.sessionNames, '; ')), ...
    'filePaths', string(strjoin(grp.filePaths, '; ')), ...
    'expNreps', NaN, ...
    'tutNreps', NaN, ...
    'totalNreps', NaN, ...
    'nsteps', NaN, ...
    'waitSecs', NaN, ...
    'gaussScalar', NaN, ...
    'targetNum', NaN, ...
    'rewardThreshold', NaN, ...
    'tutorialThreshold', NaN, ...
    'backgroundNoiseMain', NaN, ...
    'backgroundNoiseTutorial', NaN, ...
    'targetVisibility', NaN, ...
    'freeViewing', NaN, ...
    'bindReferenceIndex', NaN, ...
    'bindIncludedSessions', NaN, ...
    'bindMismatchSessions', NaN, ...
    'bindMismatchChangedTotal', NaN, ...
    'bindMismatchAddedTotal', NaN, ...
    'bindMismatchRemovedTotal', NaN, ...
    'nVaryingBasicParams', NaN, ...
    'varyingBasicParams', "");
end


function [sessionDate, startTime] = getSummaryGroupDisplayTime(grp, summaryType)
sessionDate = grp.sessionDate;
startTime = grp.startTime;
if strcmp(summaryType, 'all')
    sessionDate = NaT;
    startTime = NaT;
end
end


function params = extractSessionParams(ex)
[waitSecs, waitHz] = resolveCoPsWaitSecs(ex, NaN);
params = struct( ...
    'expNreps', getNestedNumeric(ex, {'exp', 'nreps'}), ...
    'tutNreps', getNestedNumeric(ex, {'exp', 'CoPs', 'tut', 'nreps'}), ...
    'totalNreps', getNestedNumeric(ex, {'exp', 'total_nreps'}), ...
    'nsteps', getNestedNumeric(ex, {'exp', 'CoPs', 'ctl', 'nsteps'}), ...
    'waitSecs', waitSecs, ...
    'waitHz', waitHz, ...
    'gaussScalar', getFirstAvailableNestedNumeric(ex, { ...
        {'exp', 'CoPs', 'ctl', 'gauss_scalar'}, ...
        {'exp', 'CoPs', 'ctl', 'precision_weight'}}), ...
    'gaussCenterIdx', getNestedNumeric(ex, {'exp', 'CoPs', 'rew', 'gauss_center_idx'}), ...
    'targetNum', getNestedNumeric(ex, {'exp', 'CoPs', 'ctl', 'target_num'}), ...
    'rewardThreshold', getNestedNumeric(ex, {'exp', 'CoPs', 'rew', 'threshold'}), ...
    'rewardDuration', getNestedNumeric(ex, {'exp', 'CoPs', 'rew', 'duration'}), ...
    'gaussSigma', getNestedNumeric(ex, {'exp', 'CoPs', 'rew', 'gauss_sigma'}), ...
    'tutorialThreshold', getNestedNumeric(ex, {'exp', 'CoPs', 'tut', 'threshold'}), ...
    'backgroundNoiseMain', summarizeNumericValue(getNestedValue(ex, {'exp', 'CoPs', 'graph', 'background_noise_lvl'})), ...
    'backgroundNoiseTutorial', summarizeNumericValue(getNestedValue(ex, {'exp', 'CoPs', 'tut', 'background_noise_lvl'})), ...
    'targetVisibility', getDefaultedTargetVisibility(ex), ...
    'freeViewing', getNestedNumeric(ex, {'exp', 'CoPs', 'freeViewing'}));

if isnan(params.totalNreps)
    params.totalNreps = params.expNreps + params.tutNreps;
end
end


function value = getDefaultedTargetVisibility(ex)
value = summarizeNumericValue(getNestedValue(ex, {'exp', 'CoPs', 'graph', 'target_visibility'}));
if ~isfinite(value)
    value = 1;
end
end


function row = applyParamsToFileRow(row, params)
paramFields = fieldnames(params);
for i = 1:numel(paramFields)
    row.(paramFields{i}) = params.(paramFields{i});
end
end


function row = applyParamsToMetaRow(row, params)
row = applyParamsToFileRow(row, params);
end


function row = applyBindReportToDayRow(row, bindReport)
if isempty(bindReport)
    return
end

if isfield(bindReport, 'referenceIndex')
    row.bindReferenceIndex = bindReport.referenceIndex;
end
if isfield(bindReport, 'includedIndices')
    row.bindIncludedSessions = numel(bindReport.includedIndices);
end
if isfield(bindReport, 'excludedByMismatchIndices')
    row.bindMismatchSessions = numel(bindReport.excludedByMismatchIndices);
end
if isfield(bindReport, 'mismatchDetails') && ~isempty(bindReport.mismatchDetails)
    row.bindMismatchChangedTotal = sum([bindReport.mismatchDetails.changedCount]);
    row.bindMismatchAddedTotal = sum([bindReport.mismatchDetails.addedCount]);
    row.bindMismatchRemovedTotal = sum([bindReport.mismatchDetails.removedCount]);
else
    row.bindMismatchChangedTotal = 0;
    row.bindMismatchAddedTotal = 0;
    row.bindMismatchRemovedTotal = 0;
end
end


function row = applyGroupParamVariationToMetaRow(row, paramList)
if isempty(paramList)
    row.nVaryingBasicParams = 0;
    row.varyingBasicParams = "";
    return
end

fields = fieldnames(paramList{1});
varying = {};
for i = 1:numel(fields)
    field = fields{i};
    vals = cellfun(@(p) p.(field), paramList, 'UniformOutput', false);
    if ~all(cellfun(@isscalar, vals))
        continue
    end
    base = vals{1};
    same = cellfun(@(v) isequaln(v, base), vals);
    if ~all(same)
        varying{end+1} = field; %#ok<AGROW>
    end
end

row.nVaryingBasicParams = numel(varying);
if isempty(varying)
    row.varyingBasicParams = "";
else
    row.varyingBasicParams = string(strjoin(varying, ', '));
end
end


function ts = getFileTimestamp(filePath)
info = dir(filePath);
if isempty(info)
    ts = NaT;
    return
end
ts = datetime(info.datenum, 'ConvertFrom', 'datenum');
end


function tf = isFileTimestampOnDate(ts, targetDate)
if ~isdatetime(ts) || isnat(ts) || ~isdatetime(targetDate) || isnat(targetDate)
    tf = false;
    return
end
tf = datetime(year(ts), month(ts), day(ts)) == datetime(year(targetDate), month(targetDate), day(targetDate));
end


function s = timeofdayString(ts)
if ~isdatetime(ts) || isnat(ts)
    s = "";
    return
end
s = char(string(datestr(ts, 'HH:MM')));
end


function procOut = aggregateGroupProcOutputs(procOutList)
if isempty(procOutList)
    error('collectCoPsSessionSummaries:NoProcOutputs', ...
        'No processCoPsEye outputs available for aggregation.');
end

if numel(procOutList) == 1
    procOut = procOutList{1};
    return
end

trialTables = cellfun(@(p) p.trialSummary, procOutList, 'UniformOutput', false);
trialTables = trialTables(~cellfun(@isempty, trialTables));
if isempty(trialTables)
    trialSummary = table();
else
    trialTables = harmonizeTrialSummaryTables(trialTables);
    trialSummary = vertcat(trialTables{:});
end

sessionSummaries = cellfun(@(p) p.sessionSummary, procOutList, 'UniformOutput', false);
trialCounts = cellfun(@(s) getSessionTrialCount(s), sessionSummaries);
sessionSummary = aggregateNestedStructs(sessionSummaries, trialCounts);
sessionSummary.nTrials = height(trialSummary);

trackingAggregation = aggregateTrackingAggregation(procOutList);
sessionSummary = applyTrackingAggregationToSessionSummary(sessionSummary, trackingAggregation);

procOut = struct();
procOut.trialSummary = trialSummary;
procOut.sessionSummary = sessionSummary;
if isfield(procOutList{1}, 'meta') && isfield(procOutList{1}.meta, 'metricPrimacy')
    procOut.meta.metricPrimacy = procOutList{1}.meta.metricPrimacy;
end
procOut.meta.trackingAggregation = trackingAggregation;
end


function infoByPath = buildIncludedSessionInfoByPath(fileRows)
infoByPath = containers.Map('KeyType', 'char', 'ValueType', 'any');
if isempty(fileRows)
    return
end

fileTable = struct2table(fileRows, 'AsArray', true);
if isempty(fileTable) || ~ismember('status', fileTable.Properties.VariableNames)
    return
end

keep = strcmp(string(fileTable.status), "included_for_summary");
fileTable = fileTable(keep, :);
if isempty(fileTable)
    return
end

fileTable = sortrows(fileTable, {'sessionDate', 'fileTimestamp', 'fileName'});
sessionDates = fileTable.sessionDate;
sessionNo = zeros(height(fileTable), 1);
uniqueDates = unique(sessionDates);
for i = 1:numel(uniqueDates)
    dateMask = sessionDates == uniqueDates(i);
    sessionNo(dateMask) = 1:nnz(dateMask);
end

for i = 1:height(fileTable)
    info = struct( ...
        'sessionDate', fileTable.sessionDate(i), ...
        'sessionNo', sessionNo(i), ...
        'fileTimestamp', fileTable.fileTimestamp(i), ...
        'fileName', string(fileTable.fileName(i)), ...
        'gaussScalar', fileTable.gaussScalar(i), ...
        'gaussCenterIdx', getTableNumericOrNaN(fileTable, 'gaussCenterIdx', i), ...
        'rewardThreshold', fileTable.rewardThreshold(i), ...
        'freeViewing', fileTable.freeViewing(i), ...
        'rewardDuration', getTableNumericOrNaN(fileTable, 'rewardDuration', i), ...
        'gaussSigma', getTableNumericOrNaN(fileTable, 'gaussSigma', i), ...
        'targetVisibility', getTableNumericOrNaN(fileTable, 'targetVisibility', i));
    infoByPath(char(fileTable.filePath(i))) = info;
end
end


function trialsTable = buildGroupTrialsTable(grp, sessionInfoByPath)
trialPieces = cell(0, 1);
for i = 1:numel(grp.procOutList)
    sessionProcOut = grp.procOutList{i};
    if ~isfield(sessionProcOut, 'trialSummary') || isempty(sessionProcOut.trialSummary)
        continue
    end
    trialSummary = sessionProcOut.trialSummary;
    sessionPath = char(grp.filePaths{i});
    if ~isKey(sessionInfoByPath, sessionPath)
        continue
    end
    sessionInfo = sessionInfoByPath(sessionPath);
    T = trialSummary;
    if ismember('trial', T.Properties.VariableNames)
        T = renamevars(T, 'trial', 'trialNo');
    else
        T.trialNo = (1:height(T))';
    end
    T = addvars(T, ...
        repmat(sessionInfo.sessionDate, height(T), 1), ...
        repmat(sessionInfo.sessionNo, height(T), 1), ...
        'Before', 1, ...
        'NewVariableNames', {'sessionDate', 'sessionNo'});
    T = addvars(T, ...
        repmat(sessionInfo.gaussScalar, height(T), 1), ...
        repmat(sessionInfo.gaussCenterIdx, height(T), 1), ...
        repmat(sessionInfo.rewardThreshold, height(T), 1), ...
        repmat(sessionInfo.freeViewing, height(T), 1), ...
        repmat(sessionInfo.rewardDuration, height(T), 1), ...
        repmat(sessionInfo.gaussSigma, height(T), 1), ...
        repmat(sessionInfo.targetVisibility, height(T), 1), ...
        'After', 'trialNo', ...
        'NewVariableNames', {'gauss_scalar', 'gauss_center_idx', 'threshold', 'freeViewing', 'rew_duration', 'gauss_sigma', 'target_visibility_param'});
    trialPieces{end+1, 1} = T; %#ok<AGROW>
end

if isempty(trialPieces)
    trialsTable = table();
    return
end

trialsTable = vertcat(trialPieces{:});
trialsTable = movevars(trialsTable, 'trialNo', 'After', 'sessionNo');
trialsTable = sortrows(trialsTable, {'sessionDate', 'sessionNo', 'trialNo'});
end


function iriTable = buildGroupIriTable(grp, sessionInfoByPath)
iriPieces = cell(0, 1);
for i = 1:numel(grp.procOutList)
    sessionProcOut = grp.procOutList{i};
    if ~isfield(sessionProcOut, 'iri') || isempty(sessionProcOut.iri)
        continue
    end
    sessionPath = char(grp.filePaths{i});
    if ~isKey(sessionInfoByPath, sessionPath)
        continue
    end
    sessionInfo = sessionInfoByPath(sessionPath);
    T = sessionProcOut.iri;
    if ismember('trial', T.Properties.VariableNames)
        T = renamevars(T, 'trial', 'trialNo');
    end
    if ismember('sessionNo', T.Properties.VariableNames)
        T.sessionNo(:) = sessionInfo.sessionNo;
    else
        T = addvars(T, repmat(sessionInfo.sessionNo, height(T), 1), ...
            'Before', 1, 'NewVariableNames', {'sessionNo'});
    end
    T = addvars(T, repmat(sessionInfo.sessionDate, height(T), 1), ...
        'Before', 1, 'NewVariableNames', {'sessionDate'});
    iriPieces{end+1, 1} = T; %#ok<AGROW>
end

if isempty(iriPieces)
    iriTable = table();
    return
end

iriTable = vertcat(iriPieces{:});
if ismember('trialNo', iriTable.Properties.VariableNames)
    iriTable = movevars(iriTable, 'trialNo', 'After', 'sessionNo');
end
sortVars = intersect({'sessionDate', 'sessionNo', 'trialNo', 'iriNo'}, iriTable.Properties.VariableNames, 'stable');
if ~isempty(sortVars)
    iriTable = sortrows(iriTable, sortVars);
end
end


function value = getTableNumericOrNaN(T, varName, rowIdx)
value = NaN;
if ismember(varName, T.Properties.VariableNames)
    value = T.(varName)(rowIdx);
end
end


function nTrials = getSessionTrialCount(sessionSummary)
nTrials = NaN;
if isstruct(sessionSummary) && isfield(sessionSummary, 'nTrials') && isscalar(sessionSummary.nTrials)
    nTrials = sessionSummary.nTrials;
end
if ~isfinite(nTrials) || nTrials <= 0
    nTrials = 1;
end
end


function agg = aggregateNestedStructs(structList, weights)
agg = struct();
if isempty(structList)
    return
end

allFields = {};
for i = 1:numel(structList)
    if ~isstruct(structList{i}) || isempty(structList{i})
        continue
    end
    allFields = union(allFields, fieldnames(structList{i}), 'stable');
end

for i = 1:numel(allFields)
    field = allFields{i};
    values = cell(size(structList));
    isNested = false(size(structList));
    for j = 1:numel(structList)
        s = structList{j};
        if isstruct(s) && isfield(s, field)
            values{j} = s.(field);
            isNested(j) = isstruct(values{j}) && isscalar(values{j});
        else
            values{j} = [];
        end
    end

    if any(isNested)
        nestedList = values(isNested);
        nestedWeights = weights(isNested);
        agg.(field) = aggregateNestedStructs(nestedList, nestedWeights);
    else
        agg.(field) = aggregateLeafValues(field, values, weights);
    end
end
end


function value = aggregateLeafValues(fieldName, values, weights)
if strcmp(fieldName, 'nTrials')
    numericVals = cellfun(@coerceNumericScalar, values);
    value = sum(numericVals(isfinite(numericVals)), 'omitnan');
    return
end

numericVals = cellfun(@coerceNumericScalar, values);
value = weightedMeanOmitNaN(numericVals, weights);
end


function value = coerceNumericScalar(v)
if isempty(v) || ~isscalar(v) || ~(isnumeric(v) || islogical(v))
    value = NaN;
else
    value = double(v);
end
end


function meanVal = weightedMeanOmitNaN(values, weights)
valid = isfinite(values) & isfinite(weights) & weights > 0;
if ~any(valid)
    meanVal = NaN;
    return
end
meanVal = sum(values(valid) .* weights(valid), 'omitnan') / sum(weights(valid), 'omitnan');
end


function summary = computeTrialAggregateSummary(trialSummary)
summary = struct('mean', struct(), 'sd', struct(), 'se', struct());
if isempty(trialSummary)
    return
end

metricNames = setdiff(trialSummary.Properties.VariableNames, {'trial'}, 'stable');
for i = 1:numel(metricNames)
    metricName = metricNames{i};
    values = trialSummary.(metricName);
    if ~isnumeric(values) && ~islogical(values)
        continue
    end
    values = double(values(:));
    values = values(isfinite(values));
    if isempty(values)
        summary.mean.(metricName) = NaN;
        summary.sd.(metricName) = NaN;
        summary.se.(metricName) = NaN;
        continue
    end
    summary.mean.(metricName) = mean(values, 'omitnan');
    if numel(values) == 1
        summary.sd.(metricName) = 0;
        summary.se.(metricName) = 0;
    else
        summary.sd.(metricName) = std(values, 0, 'omitnan');
        summary.se.(metricName) = summary.sd.(metricName) / sqrt(numel(values));
    end
end

if ~ismember('backgroundNoiseLvl', trialSummary.Properties.VariableNames)
    return
end

noiseLevels = double(trialSummary.backgroundNoiseLvl(:));
validNoise = isfinite(noiseLevels);
if ~any(validNoise)
    return
end

distanceMetrics = intersect( ...
    {'meanDist1Deg', 'meanDist2Deg', 'meanDistDeg', ...
     'meanDistPx1', 'meanDistPx2', 'meanDistPx', 'isTracking'}, ...
    trialSummary.Properties.VariableNames, 'stable');
uniqueNoise = unique(noiseLevels(validNoise));
for i = 1:numel(uniqueNoise)
    noiseLevel = uniqueNoise(i);
    noiseMask = validNoise & noiseLevels == noiseLevel;
    suffix = makeNoiseLevelFieldSuffix(noiseLevel);
    for j = 1:numel(distanceMetrics)
        metricName = distanceMetrics{j};
        values = double(trialSummary.(metricName)(noiseMask));
        values = values(isfinite(values));
        fieldName = matlab.lang.makeValidName([metricName '_' suffix]);
        if isempty(values)
            summary.mean.(fieldName) = NaN;
            summary.sd.(fieldName) = NaN;
            summary.se.(fieldName) = NaN;
            continue
        end
        summary.mean.(fieldName) = mean(values, 'omitnan');
        if numel(values) == 1
            summary.sd.(fieldName) = 0;
            summary.se.(fieldName) = 0;
        else
            summary.sd.(fieldName) = std(values, 0, 'omitnan');
            summary.se.(fieldName) = summary.sd.(fieldName) / sqrt(numel(values));
        end
    end
end
end


function row = assignFlatFields(row, flatFields)
fields = fieldnames(flatFields);
for i = 1:numel(fields)
    row.(fields{i}) = flatFields.(fields{i});
end
end


function T = buildSummaryTable(rows)
if isempty(rows)
    T = table();
    return
end
T = struct2table(rows, 'AsArray', true);
T = sortrows(T, {'sessionDate', 'startTime'});
end


function tablesOut = harmonizeTrialSummaryTables(tablesIn)
tablesOut = tablesIn;
if isempty(tablesOut)
    return
end

allVars = {};
refTableByVar = struct();
for i = 1:numel(tablesOut)
    vars = tablesOut{i}.Properties.VariableNames;
    for j = 1:numel(vars)
        varName = vars{j};
        if ~ismember(varName, allVars)
            allVars{end+1} = varName; %#ok<AGROW>
            refTableByVar.(varName) = tablesOut{i};
        end
    end
end

for i = 1:numel(tablesOut)
    T = tablesOut{i};
    missingVars = setdiff(allVars, T.Properties.VariableNames, 'stable');
    for j = 1:numel(missingVars)
        varName = missingVars{j};
        exemplar = refTableByVar.(varName).(varName);
        T.(varName) = repmat(defaultLikeTableVar(exemplar), height(T), 1);
    end
    T = T(:, allVars);
    tablesOut{i} = T;
end
end


function value = defaultLikeTableVar(exemplar)
if isstring(exemplar)
    value = missing;
elseif isdatetime(exemplar)
    value = NaT;
elseif iscategorical(exemplar)
    value = categorical(missing);
elseif isnumeric(exemplar) || islogical(exemplar)
    value = NaN;
elseif iscell(exemplar)
    value = {[]};
else
    value = [];
end
end


function agg = aggregateTrackingAggregation(procOutList)
agg = struct('distanceBins', struct(), 'phaseBins', struct());
distanceStats = struct();
phaseStats = struct();
for i = 1:numel(procOutList)
    procOut = procOutList{i};
    if ~isfield(procOut, 'meta') || ~isfield(procOut.meta, 'trackingAggregation') || ...
            ~isstruct(procOut.meta.trackingAggregation)
        continue
    end

    if isfield(procOut.meta.trackingAggregation, 'distanceBins')
        binStats = procOut.meta.trackingAggregation.distanceBins;
        binNames = fieldnames(binStats);
        for j = 1:numel(binNames)
            binName = binNames{j};
            distanceStats.(binName) = combineTrackingStats(distanceStats, binName, binStats.(binName));
        end
    end

    if isfield(procOut.meta.trackingAggregation, 'phaseBins')
        binStats = procOut.meta.trackingAggregation.phaseBins;
        binNames = fieldnames(binStats);
        for j = 1:numel(binNames)
            binName = binNames{j};
            phaseStats.(binName) = combineTrackingStats(phaseStats, binName, binStats.(binName));
        end
    end
end
agg.distanceBins = distanceStats;
agg.phaseBins = phaseStats;
end


function sessionSummary = applyTrackingAggregationToSessionSummary(sessionSummary, trackingAggregation)
hasDistance = isfield(trackingAggregation, 'distanceBins') && ~isempty(fieldnames(trackingAggregation.distanceBins));
hasPhase = isfield(trackingAggregation, 'phaseBins') && ~isempty(fieldnames(trackingAggregation.phaseBins));
if ~hasDistance && ~hasPhase
    return
end

unitSuffix = 'Px';
if isfield(sessionSummary, 'mean') && ...
        isfield(sessionSummary.mean, 'trackBiasDeg')
    unitSuffix = 'Deg';
end
metricMap = { ...
    ['trackBias' unitSuffix], 'sumBias'; ...
    ['trackBiasX' unitSuffix], 'sumBiasX'; ...
    ['trackBiasY' unitSuffix], 'sumBiasY'; ...
    ['trackScreenCenterBias' unitSuffix], 'sumScreenCenterBias'; ...
    ['trackGaussSpecificBias' unitSuffix], 'sumGaussSpecificBias'; ...
    ['trackError' unitSuffix], 'sumErrDist'; ...
    ['trackVariability' unitSuffix], 'sumErrSq'};

if hasDistance
    binNames = fieldnames(trackingAggregation.distanceBins);
    for i = 1:numel(binNames)
        binName = binNames{i};
        stats = trackingAggregation.distanceBins.(binName);
        sessionSummary = assignTrackingAggregationBin(sessionSummary, metricMap, 'nTrackedSamples', binName, stats);
    end
end

if hasPhase
    phaseCountMap = struct('early', 'nTrackedSamplesEarly', 'late', 'nTrackedSamplesLate');
    binNames = fieldnames(trackingAggregation.phaseBins);
    for i = 1:numel(binNames)
        binName = binNames{i};
        stats = trackingAggregation.phaseBins.(binName);
        countField = 'nTrackedSamples';
        if isfield(phaseCountMap, binName)
            countField = phaseCountMap.(binName);
        end
        sessionSummary = assignTrackingAggregationBin(sessionSummary, metricMap, countField, binName, stats);
    end
end

    function ensureMetricStructs(metricName)
        if ~isfield(sessionSummary.mean, metricName) || ~isstruct(sessionSummary.mean.(metricName))
            sessionSummary.mean.(metricName) = struct();
        end
    end
end


function sessionSummary = assignTrackingAggregationBin(sessionSummary, metricMap, countField, binName, stats)
if ~isfield(sessionSummary, countField) || ~isstruct(sessionSummary.(countField))
    sessionSummary.(countField) = struct();
end
sessionSummary.(countField).(binName) = stats.n;

if ~isfield(sessionSummary, 'mean') || ~isstruct(sessionSummary.mean)
    return
end

for j = 1:size(metricMap, 1)
    metricName = metricMap{j, 1};
    ensureMetricStructs(metricName);
    if stats.n == 0
        sessionSummary.mean.(metricName).(binName) = NaN;
        continue
    end
    switch metricMap{j, 2}
        case 'sumBias'
            sessionSummary.mean.(metricName).(binName) = stats.sumBias / stats.n;
        case 'sumBiasX'
            sessionSummary.mean.(metricName).(binName) = stats.sumBiasX / stats.n;
        case 'sumBiasY'
            sessionSummary.mean.(metricName).(binName) = stats.sumBiasY / stats.n;
        case 'sumScreenCenterBias'
            sessionSummary.mean.(metricName).(binName) = stats.sumScreenCenterBias / stats.n;
        case 'sumGaussSpecificBias'
            sessionSummary.mean.(metricName).(binName) = stats.sumGaussSpecificBias / stats.n;
        case 'sumErrDist'
            if isfield(stats, 'nErrDist') && stats.nErrDist == stats.n
                sessionSummary.mean.(metricName).(binName) = stats.sumErrDist / stats.nErrDist;
            else
                sessionSummary.mean.(metricName).(binName) = sqrt(stats.sumErrSq / stats.n);
            end
        case 'sumErrSq'
            varX = (stats.sumErrXSq / stats.n) - (stats.sumErrX / stats.n).^2;
            varY = (stats.sumErrYSq / stats.n) - (stats.sumErrY / stats.n).^2;
            sessionSummary.mean.(metricName).(binName) = sqrt(max(0, varX) + max(0, varY));
    end
end

    function ensureMetricStructs(metricName)
        if ~isfield(sessionSummary.mean, metricName) || ~isstruct(sessionSummary.mean.(metricName))
            sessionSummary.mean.(metricName) = struct();
        end
    end
end


function statsOut = combineTrackingStats(distanceStats, binName, statsIn)
if isfield(distanceStats, binName)
    statsOut = distanceStats.(binName);
else
    statsOut = initTrackingStats();
end

fields = fieldnames(statsOut);
for i = 1:numel(fields)
    field = fields{i};
    if isfield(statsIn, field) && isfinite(statsIn.(field))
        statsOut.(field) = statsOut.(field) + statsIn.(field);
    end
end
end


function stats = initTrackingStats()
stats = struct( ...
    'n', 0, ...
    'sumBias', 0, ...
    'sumBiasX', 0, ...
    'sumBiasY', 0, ...
    'sumScreenCenterBias', 0, ...
    'sumGaussSpecificBias', 0, ...
    'sumErrDist', 0, ...
    'nErrDist', 0, ...
    'sumErrSq', 0, ...
    'sumErrX', 0, ...
    'sumErrY', 0, ...
    'sumErrXSq', 0, ...
    'sumErrYSq', 0);
end


function suffix = makeNoiseLevelFieldSuffix(noiseLevel)
noiseLabel = regexprep(num2str(noiseLevel, '%.15g'), '\.', 'p');
noiseLabel = regexprep(noiseLabel, '-', 'm');
suffix = char(matlab.lang.makeValidName(['noise' noiseLabel]));
end


function key = getSummaryGroupKey(summaryType, sessionFolder, filePath)
switch summaryType
    case 'day'
        key = string(sessionFolder);
    case 'session'
        key = string(filePath);
    case 'all'
        key = "all";
    otherwise
        error('collectCoPsSessionSummaries:InvalidSummaryType', ...
            'Unsupported opts.summaryType: %s', summaryType);
end
end


function idx = findSummaryGroup(summaryGroups, groupKey)
idx = [];
if isempty(summaryGroups)
    return
end
for i = 1:numel(summaryGroups)
    if strcmp(summaryGroups(i).groupKey, string(groupKey))
        idx = i;
        return
    end
end
end


function [tf, msg] = matchesRequiredParams(params, required)
tf = true;
msg = '';

if isempty(fieldnames(required))
    return
end

reqFields = fieldnames(required);
for i = 1:numel(reqFields)
    field = reqFields{i};
    if ~isfield(params, field)
        tf = false;
        msg = sprintf('Unsupported required parameter: %s', field);
        return
    end

    actual = params.(field);
    expected = required.(field);

    if isnumeric(expected)
        if ~ismember(actual, expected)
            tf = false;
            msg = sprintf('%s=%g did not match required values', field, actual);
            return
        end
    else
        if ~isequal(actual, expected)
            tf = false;
            msg = sprintf('%s did not match required value', field);
            return
        end
    end
end
end


function [tf, msg] = matchesSessionConditions(ex, conditions)
tf = true;
msg = '';

if isempty(conditions)
    return
end

if ~isstruct(conditions)
    error('collectCoPsSessionSummaries:InvalidSessionConditions', ...
        'opts.sessionConditions must be a struct array.');
end

for i = 1:numel(conditions)
    cond = conditions(i);
    if ~isfield(cond, 'path') || ~isfield(cond, 'op') || ~isfield(cond, 'value')
        error('collectCoPsSessionSummaries:InvalidSessionCondition', ...
            'Each session condition must contain path, op, and value.');
    end

    [actual, found] = getPathValue(ex, char(cond.path));
    if ~found
        tf = false;
        msg = sprintf('Missing field for condition: %s', cond.path);
        return
    end

    if ~evaluateCondition(actual, char(cond.op), cond.value)
        tf = false;
        msg = sprintf('Condition failed: %s %s %s', cond.path, cond.op, valueToString(cond.value));
        return
    end
end
end


function nMainTrials = countMainTaskTrialsInEx(ex)
nMainTrials = 0;
if ~isfield(ex, 'Trials') || isempty(ex.Trials)
    return
end

for i = 1:numel(ex.Trials)
    if isMainTaskTrial(ex, ex.Trials(i))
        nMainTrials = nMainTrials + 1;
    end
end
end


function tf = isMainTaskTrial(ex, T)
isFixationTrial = isfield(T, 'isFixationTrial') && logical(T.isFixationTrial);
isTutorialTrial = isfield(T, 'isTutorialTrial') && logical(T.isTutorialTrial);
if isFixationTrial || isTutorialTrial
    tf = false;
    return
end

if isfield(T, 'runPhase') && ~isempty(T.runPhase)
    tf = strcmp(string(T.runPhase), "main");
    return
end

% Backward-compatible inference for older sessions without runPhase.
if hasTwoTargets(T)
    tf = true;
    return
end

% Older tutorial-only sessions may keep a session-level tutorial flag.
if isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'tut') && ...
        isfield(ex.exp.CoPs.tut, 'enable') && logical(ex.exp.CoPs.tut.enable)
    tf = false;
    return
end

if isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'ctl') && ...
        isfield(ex.exp.CoPs.ctl, 'target_num') && isfinite(ex.exp.CoPs.ctl.target_num)
    tf = ex.exp.CoPs.ctl.target_num >= 2;
    return
end

tf = true;
end


function tf = hasTwoTargets(T)
tf = false;
if isfield(T, 'targetPositions') && ~isempty(T.targetPositions)
    tp = T.targetPositions;
    if isstruct(tp) && isfield(tp, 'targ2')
        tf = true;
        return
    end
end

if isfield(T, 'posT') && isstruct(T.posT) && isfield(T.posT, 'x2')
    tf = true;
end
end


function [value, found] = getPathValue(s, pathStr)
value = [];
found = false;

parts = strsplit(pathStr, '.');
cur = s;
for i = 1:numel(parts)
    field = parts{i};
    if ~isstruct(cur) || ~isfield(cur, field)
        return
    end
    cur = cur.(field);
end

value = cur;
found = true;
end


function tf = evaluateCondition(actual, op, expected)
switch op
    case {'==', 'eq'}
        tf = isequaln(actual, expected);
    case {'~=', '!=', 'ne'}
        tf = ~isequaln(actual, expected);
    case '>'
        tf = isnumeric(actual) && isnumeric(expected) && isscalar(actual) && isscalar(expected) && actual > expected;
    case '>='
        tf = isnumeric(actual) && isnumeric(expected) && isscalar(actual) && isscalar(expected) && actual >= expected;
    case '<'
        tf = isnumeric(actual) && isnumeric(expected) && isscalar(actual) && isscalar(expected) && actual < expected;
    case '<='
        tf = isnumeric(actual) && isnumeric(expected) && isscalar(actual) && isscalar(expected) && actual <= expected;
    case {'ismember', 'in'}
        tf = ismember(actual, expected);
    case {'contains'}
        tf = contains(string(actual), string(expected));
    otherwise
        error('collectCoPsSessionSummaries:UnsupportedConditionOp', ...
            'Unsupported session condition operator: %s', op);
end
end


function s = valueToString(v)
if isstring(v) || ischar(v)
    s = char(string(v));
elseif isnumeric(v) || islogical(v)
    s = mat2str(v);
else
    s = class(v);
end
end


function value = getNestedValue(s, fields)
value = NaN;
cur = s;
for i = 1:numel(fields)
    field = fields{i};
    if ~isstruct(cur) || ~isfield(cur, field)
        return
    end
    cur = cur.(field);
end
value = cur;
end


function value = getNestedNumeric(s, fields)
value = getNestedValue(s, fields);
if isempty(value)
    value = NaN;
elseif ~isscalar(value) || ~isnumeric(value)
    value = NaN;
end
end


function value = getFirstAvailableNestedNumeric(s, fieldSets)
value = NaN;
for i = 1:numel(fieldSets)
    candidate = getNestedNumeric(s, fieldSets{i});
    if isfinite(candidate)
        value = candidate;
        return
    end
end
end


function value = summarizeNumericValue(x)
if isempty(x) || ~isnumeric(x)
    value = NaN;
elseif isscalar(x)
    value = x;
else
    value = mean(x(:), 'omitnan');
end
end


function rows = appendStructRow(rows, row)
if isempty(rows)
    rows = row;
else
    fieldsRows = fieldnames(rows);
    fieldsRow = fieldnames(row);
    missingInRows = setdiff(fieldsRow, fieldsRows);
    missingInRow = setdiff(fieldsRows, fieldsRow);
    if ~isempty(missingInRows) || ~isempty(missingInRow)
        warning('collectCoPsSessionSummaries:StructFieldMismatch', ...
            ['Harmonizing struct fields before append.\n' ...
             'Missing in existing rows: %s\n' ...
             'Missing in new row: %s'], ...
            strjoin(missingInRows, ', '), strjoin(missingInRow, ', '));
    end
    rows = harmonizeStructFields(rows, row);
    row = harmonizeStructFields(row, rows(1));
    rows(end+1) = row; %#ok<AGROW>
end
end


function s = harmonizeStructFields(s, ref)
fieldsS = fieldnames(s);
fieldsRef = fieldnames(ref);
missingFields = setdiff(fieldsRef, fieldsS);
for i = 1:numel(missingFields)
    field = missingFields{i};
    exemplar = ref(1).(field);
    defaultValue = getDefaultLike(exemplar);
    for j = 1:numel(s)
        s(j).(field) = defaultValue;
    end
end
end


function value = getDefaultLike(exemplar)
if isstring(exemplar)
    value = "";
elseif ischar(exemplar)
    value = '';
elseif isdatetime(exemplar)
    value = NaT;
elseif isnumeric(exemplar) || islogical(exemplar)
    value = NaN;
elseif iscell(exemplar)
    value = {};
elseif isstruct(exemplar)
    value = struct();
else
    value = [];
end
end


function flat = flattenStructFields(s, prefix)
if nargin < 2
    prefix = '';
end

flat = struct();
if ~isstruct(s) || ~isscalar(s)
    return
end

fields = fieldnames(s);
for i = 1:numel(fields)
    field = fields{i};
    value = s.(field);
    if isempty(prefix)
        flatField = char(matlab.lang.makeValidName(field));
    else
        flatField = char(matlab.lang.makeValidName([prefix '_' field]));
    end

    if isstruct(value) && isscalar(value)
        nested = flattenStructFields(value, flatField);
        nestedFields = fieldnames(nested);
        for j = 1:numel(nestedFields)
            flat.(nestedFields{j}) = nested.(nestedFields{j});
        end
    else
        flat.(flatField) = value;
    end
end
end
