function exOut = exDay(dateValue, opts)
% exDay  Load and bind all CoPs ex sessions for one date.
%
%   ex = exDay('Jun18')
%   ex = exDay('Jun18', opts)
%
% Options:
%   opts.subject       : subject folder/name or alias, e.g. 'ka', 'ly'.
%                        If empty, the date must exist under exactly one
%                        subject folder.
%   opts.dataRoot      : CoPs data root (default /media/vpixx/DATA/CoPs)
%   opts.includeTrials : 'main' (default), 'main+pre', 'all', 'pur',
%                        'pre', or 'tut'
%   opts.minTrialNum   : minimum selected trials for a session to be kept
%                        (default 5)
%
% Output uses exBind on filtered sessions and adds day-level trial metadata:
%   T.trial            : continuous day-level trial number after filtering
%   T.trialDay         : same as T.trial
%   T.dayTrial         : same as T.trial
%   T.trialInSession   : original trial index inside source session
%   T.sessionInDay     : included source-session index in chronological day

if nargin < 1 || isempty(dateValue)
    error('exDay:MissingDate', 'Provide a date such as ''Jun18'' or ''2026.06.18''.');
end
if nargin < 2 || isempty(opts)
    opts = struct();
elseif ~isstruct(opts)
    error('exDay:BadOpts', 'opts must be a struct.');
end

opts = localDefaults(opts);
dateInfo = localParseDate(dateValue);
localEnsureHelpersOnPath();

[subject, dateDirs] = localResolveDateDirs(dateInfo, opts);
files = localListSessionExFiles(dateDirs);
if isempty(files)
    error('exDay:NoSessionFiles', ...
        'No ex .mat files found for %s under subject %s.', dateInfo.folderPrefix, subject);
end

exList = {};
sessionNames = {};
rows = localEmptyRows();
dayTrialNo = 0;
includedSessionNo = 0;

for iFile = 1:numel(files)
    filePath = files{iFile};
    row = localInitRow(filePath);
    try
        S = load(filePath, 'ex');
    catch err
        row.status = "load_failed";
        row.message = string(err.message);
        rows = localAppendRow(rows, row);
        continue
    end
    if ~isfield(S, 'ex') || ~isstruct(S.ex) || ~isfield(S.ex, 'Trials') || isempty(S.ex.Trials)
        row.status = "missing_ex";
        row.message = "File does not contain ex.Trials";
        rows = localAppendRow(rows, row);
        continue
    end

    ex = S.ex;
    keep = localTrialPhaseMask(ex, opts.includeTrials);
    row.nRawTrials = numel(ex.Trials);
    row.nSelectedTrials = nnz(keep);
    if row.nSelectedTrials < opts.minTrialNum
        row.status = "too_few_trials";
        row.message = sprintf('nSelectedTrials=%d < minTrialNum=%d', row.nSelectedTrials, opts.minTrialNum);
        rows = localAppendRow(rows, row);
        continue
    end

    includedSessionNo = includedSessionNo + 1;
    selectedIdx = find(keep);
    ex.Trials = ex.Trials(selectedIdx);
    [ex.Trials, dayTrialNo] = localAnnotateTrials( ...
        ex.Trials, selectedIdx, dayTrialNo, includedSessionNo, filePath);

    row.status = "included";
    row.message = "";
    row.sessionInDay = includedSessionNo;
    row.dayTrialStart = dayTrialNo - numel(ex.Trials) + 1;
    row.dayTrialStop = dayTrialNo;
    rows = localAppendRow(rows, row);

    exList{end+1, 1} = ex; %#ok<AGROW>
    sessionNames{end+1, 1} = char(row.fileName); %#ok<AGROW>
end

if isempty(exList)
    error('exDay:NoIncludedSessions', ...
        'No sessions met includeTrials=''%s'' and minTrialNum=%d. Inspect fileTable via exDay with looser options.', ...
        opts.includeTrials, opts.minTrialNum);
end

exOut = exBind(exList, 'SessionNames', sessionNames);
if ~isfield(exOut, 'exp') || ~isstruct(exOut.exp)
    exOut.exp = struct();
end
exOut.exp.exDay = struct( ...
    'dateInput', string(dateValue), ...
    'dateFolderPrefix', string(dateInfo.folderPrefix), ...
    'subject', string(subject), ...
    'includeTrials', string(opts.includeTrials), ...
    'minTrialNum', opts.minTrialNum, ...
    'nIncludedSessions', numel(exList), ...
    'nTrials', numel(exOut.Trials), ...
    'fileTable', localRowsToTable(rows));
end


function opts = localDefaults(opts)
defaults = struct( ...
    'subject', [], ...
    'dataRoot', "/media/vpixx/DATA/CoPs", ...
    'includeTrials', 'main', ...
    'minTrialNum', 5);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(opts, names{i}) || isempty(opts.(names{i}))
        opts.(names{i}) = defaults.(names{i});
    end
end
opts.includeTrials = localCanonicalIncludeTrials(opts.includeTrials);
opts.minTrialNum = round(double(opts.minTrialNum));
if ~isfinite(opts.minTrialNum) || opts.minTrialNum < 0
    error('exDay:BadMinTrialNum', 'opts.minTrialNum must be a nonnegative scalar.');
end
end


function localEnsureHelpersOnPath()
helperDir = fullfile(fileparts(mfilename('fullpath')), 'helpers');
if exist('exBind', 'file') ~= 2 && exist(helperDir, 'dir')
    addpath(helperDir);
end
end


function code = localCanonicalIncludeTrials(value)
code = lower(strtrim(char(string(value))));
switch code
    case {'main', 'task'}
        code = 'main';
    case {'main+pre', 'pre+main', 'mainpre', 'task+pre'}
        code = 'main+pre';
    case {'all', ''}
        code = 'all';
    case {'pur', 'pursuit'}
        code = 'pur';
    case {'pre', 'preblock'}
        code = 'pre';
    case {'tut', 'tutorial'}
        code = 'tut';
    otherwise
        error('exDay:BadIncludeTrials', ...
            ['opts.includeTrials must be ''main'', ''main+pre'', ''all'', ' ...
            '''pur'', ''pre'', or ''tut''.']);
end
end


function dateInfo = localParseDate(value)
if isdatetime(value)
    d = datetime(year(value), month(value), day(value));
else
    s = strtrim(char(string(value)));
    try
        d = datetime(s, 'InputFormat', 'yyyy.MM.dd');
    catch
        tok = regexp(lower(s), '^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s*([0-9]{1,2})$', 'tokens', 'once');
        if isempty(tok)
            error('exDay:BadDate', 'Date must be datetime, ''YYYY.MM.DD'', or shorthand like ''Jun18''.');
        end
        months = struct('jan',1,'feb',2,'mar',3,'apr',4,'may',5,'jun',6, ...
            'jul',7,'aug',8,'sep',9,'oct',10,'nov',11,'dec',12);
        d = datetime(year(datetime('today')), months.(tok{1}), str2double(tok{2}));
    end
end
dateInfo.date = d;
dateInfo.folderPrefix = string(datestr(d, 'yyyy.mm.dd'));
end


function [subject, dateDirs] = localResolveDateDirs(dateInfo, opts)
dataRoot = char(opts.dataRoot);
if ~exist(dataRoot, 'dir')
    error('exDay:DataRootNotFound', 'Data root not found: %s', dataRoot);
end

if ~isempty(opts.subject)
    subject = localResolveSubject(opts.subject, dataRoot);
    dateDirs = localSubjectDateDirs(subject, dateInfo.folderPrefix, dataRoot);
    if isempty(dateDirs)
        error('exDay:DateNotFound', 'Date %s not found for subject %s.', dateInfo.folderPrefix, subject);
    end
    return
end

subjects = localSubjectFolders(dataRoot);
matches = struct('subject', {}, 'dateDirs', {});
for i = 1:numel(subjects)
    dirs = localSubjectDateDirs(subjects(i), dateInfo.folderPrefix, dataRoot);
    if ~isempty(dirs)
        matches(end+1) = struct('subject', subjects(i), 'dateDirs', {dirs}); %#ok<AGROW>
    end
end
if isempty(matches)
    error('exDay:DateNotFound', 'Date %s was not found under %s.', dateInfo.folderPrefix, dataRoot);
elseif numel(matches) > 1
    names = strjoin(string({matches.subject}), ', ');
    error('exDay:AmbiguousSubject', ...
        'Date %s exists for multiple subjects (%s). Set opts.subject, e.g. opts.subject=''ka''.', ...
        dateInfo.folderPrefix, names);
end
subject = matches(1).subject;
dateDirs = matches(1).dateDirs;
end


function subject = localResolveSubject(subjectValue, dataRoot)
subjectValue = lower(strtrim(string(subjectValue)));
switch subjectValue
    case {"ka", "kaki"}
        subject = "kaki";
    case {"ly", "lychee"}
        subject = "lychee";
    otherwise
        subject = subjectValue;
end
candidate = fullfile(dataRoot, char(subject));
if exist(candidate, 'dir')
    return
end
subjects = localSubjectFolders(dataRoot);
match = subjects(startsWith(lower(subjects), lower(subjectValue)));
if numel(match) == 1
    subject = match(1);
else
    error('exDay:SubjectNotFound', 'Subject folder not found for ''%s''.', subjectValue);
end
end


function subjects = localSubjectFolders(dataRoot)
raw = dir(dataRoot);
raw = raw([raw.isdir]);
raw = raw(~ismember({raw.name}, {'.', '..'}));
subjects = string({raw.name});
end


function dateDirs = localSubjectDateDirs(subject, folderPrefix, dataRoot)
subjectDir = fullfile(dataRoot, char(subject));
raw = dir(fullfile(subjectDir, [char(folderPrefix) '*']));
raw = raw([raw.isdir]);
raw = raw(~ismember({raw.name}, {'.', '..'}));
dateDirs = strings(numel(raw), 1);
for i = 1:numel(raw)
    dateDirs(i) = string(fullfile(raw(i).folder, raw(i).name));
end
dateDirs = sort(dateDirs);
end


function files = localListSessionExFiles(dateDirs)
files = strings(0, 1);
for iDir = 1:numel(dateDirs)
    dateDir = char(dateDirs(iDir));
    rootFiles = localMatFiles(dateDir);
    experimentalDir = fullfile(dateDir, 'experimental');
    expFiles = strings(0, 1);
    if exist(experimentalDir, 'dir')
        expFiles = localMatFiles(experimentalDir);
    end
    files = [files; rootFiles; expFiles]; %#ok<AGROW>
end
files = unique(files, 'stable');
files = localSortFilesBySessionTime(files);
end


function files = localMatFiles(folder)
info = dir(fullfile(folder, '*.mat'));
info = info(~startsWith({info.name}, 'dailyLog'));
info = info(~contains({info.name}, 'EyeCal'));
files = strings(numel(info), 1);
for i = 1:numel(info)
    files(i) = string(fullfile(info(i).folder, info(i).name));
end
end


function files = localSortFilesBySessionTime(files)
if isempty(files)
    return
end
sortKey = NaN(numel(files), 1);
names = strings(numel(files), 1);
for i = 1:numel(files)
    info = dir(char(files(i)));
    if ~isempty(info)
        names(i) = string(info.name);
        sortKey(i) = localSessionTimeSortKey(info.name);
        if ~isfinite(sortKey(i))
            sortKey(i) = info.datenum;
        end
    else
        names(i) = string(files(i));
        sortKey(i) = i;
    end
end
T = table(sortKey, names, files(:), 'VariableNames', {'sortKey','name','file'});
T = sortrows(T, {'sortKey','name'});
files = T.file;
end


function key = localSessionTimeSortKey(fileName)
key = NaN;
tok = regexp(char(fileName), '^[A-Za-z]+_(\d{1,2})\.(\d{2})', 'tokens', 'once');
if isempty(tok)
    return
end
hh = str2double(tok{1});
mm = str2double(tok{2});
if isfinite(hh) && isfinite(mm)
    key = hh .* 60 + mm;
end
end


function keep = localTrialPhaseMask(ex, includeTrials)
nTrials = numel(ex.Trials);
keep = false(1, nTrials);
for i = 1:nTrials
    T = ex.Trials(i);
    switch includeTrials
        case 'all'
            keep(i) = true;
        case 'main'
            keep(i) = localIsMainTrial(ex, T);
        case 'main+pre'
            keep(i) = localIsMainTrial(ex, T) || localIsPreTrial(T);
        case 'pur'
            keep(i) = localIsPursuitTrial(T);
        case 'pre'
            keep(i) = localIsPreTrial(T);
        case 'tut'
            keep(i) = localIsTutorialTrial(T);
    end
end
end


function tf = localIsMainTrial(ex, T)
if localIsFixationTrial(T) || localIsTutorialTrial(T)
    tf = false;
    return
end
phase = localRunPhase(T);
if strlength(phase) > 0
    tf = phase == "main";
    return
end
tf = ~localIsPursuitTrial(T) && ~localIsPreTrial(T);
if tf && isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'tut') && ...
        isfield(ex.exp.CoPs.tut, 'enable') && logical(ex.exp.CoPs.tut.enable)
    tf = false;
end
end


function tf = localIsPursuitTrial(T)
tf = localLogicalTrialFlag(T, 'isPursuitTrial');
phase = localRunPhase(T);
tf = tf || phase == "pursuit" || phase == "pur";
end


function tf = localIsPreTrial(T)
tf = localLogicalTrialFlag(T, 'isPreTrial');
phase = localRunPhase(T);
tf = tf || phase == "pre";
end


function tf = localIsTutorialTrial(T)
tf = localLogicalTrialFlag(T, 'isTutorialTrial');
phase = localRunPhase(T);
tf = tf || phase == "tutorial" || phase == "tut";
end


function tf = localIsFixationTrial(T)
tf = localLogicalTrialFlag(T, 'isFixationTrial');
phase = localRunPhase(T);
tf = tf || phase == "fix" || phase == "fixation";
end


function tf = localLogicalTrialFlag(T, fieldName)
tf = false;
if isfield(T, fieldName) && ~isempty(T.(fieldName))
    v = T.(fieldName);
    if isnumeric(v) || islogical(v)
        tf = isfinite(double(v(1))) && logical(v(1));
    end
end
end


function phase = localRunPhase(T)
phase = "";
if isfield(T, 'runPhase') && ~isempty(T.runPhase)
    phase = lower(strtrim(string(T.runPhase)));
end
end


function [trials, dayTrialNo] = localAnnotateTrials(trials, selectedIdx, dayTrialNo, sessionInDay, filePath)
[~, fileName, ext] = fileparts(char(filePath));
fileName = string([fileName ext]);
trials = localEnsureAnnotationFields(trials);
for i = 1:numel(trials)
    T = trials(i);
    if isfield(T, 'trial')
        T.originalTrialField = T.trial;
    end
    dayTrialNo = dayTrialNo + 1;
    T.trial = dayTrialNo;
    T.trialDay = dayTrialNo;
    T.dayTrial = dayTrialNo;
    T.trialInSession = selectedIdx(i);
    T.originalTrialNo = selectedIdx(i);
    T.sessionInDay = sessionInDay;
    T.sourceFileName = fileName;
    T.sourceFilePath = string(filePath);
    trials(i) = T;
end
end


function trials = localEnsureAnnotationFields(trials)
fields = { ...
    'originalTrialField', NaN; ...
    'trial', NaN; ...
    'trialDay', NaN; ...
    'dayTrial', NaN; ...
    'trialInSession', NaN; ...
    'originalTrialNo', NaN; ...
    'sessionInDay', NaN; ...
    'sourceFileName', ""; ...
    'sourceFilePath', ""};
for i = 1:size(fields, 1)
    fieldName = fields{i, 1};
    defaultValue = fields{i, 2};
    if ~isfield(trials, fieldName)
        [trials.(fieldName)] = deal(defaultValue);
    end
end
end


function rows = localEmptyRows()
rows = struct('fileName', {}, 'filePath', {}, 'status', {}, 'message', {}, ...
    'nRawTrials', {}, 'nSelectedTrials', {}, 'sessionInDay', {}, ...
    'dayTrialStart', {}, 'dayTrialStop', {});
end


function row = localInitRow(filePath)
[~, name, ext] = fileparts(char(filePath));
row = struct( ...
    'fileName', string([name ext]), ...
    'filePath', string(filePath), ...
    'status', "unchecked", ...
    'message', "", ...
    'nRawTrials', NaN, ...
    'nSelectedTrials', NaN, ...
    'sessionInDay', NaN, ...
    'dayTrialStart', NaN, ...
    'dayTrialStop', NaN);
end


function rows = localAppendRow(rows, row)
if isempty(rows)
    rows = row;
else
    rows(end+1) = row;
end
end


function T = localRowsToTable(rows)
if isempty(rows)
    T = table();
else
    T = struct2table(rows, 'AsArray', true);
end
end
