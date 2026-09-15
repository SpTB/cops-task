function out = collectCCG2(subject, groupingArg, opts)
% collectCCG2  Collect and aggregate plotCCG2 outputs across sessions.
%
%   A = collectCCG2('ka')
%   A = collectCCG2('ka', 'vis')
%   A = collectCCG2('ka', {'bg','vis'}, opts)
%
% groupingArg is passed to plotCCG2 after each session is filtered by the
% requested trial/session conditions. Empty grouping means all selected
% trials are one group.
%
% To define aggregate group order/levels a priori for one named grouping:
%   opts.groupLevels = [0.5 0.7 0.8 0.9 1];
%   A = collectCCG2('ka', 'vis', opts);
%
% Numeric trial filters accept numeric lists or simple comparison strings:
%   opts.backgroundNoiseLvl = '>0';  % dynamic background, excluding 0/-1
%
% opts.datadir is the CoPs data directory containing the subject folders:
%   opts.datadir = 'Y:\data\CoPs';  % contains kaki/ and lychee/
% opts.dataRoot is retained as a backward-compatible alias for datadir.
%
% To merge day-level HMM prediction CSVs before building each session CCG:
%   opts.mergeHmm = true;
%   opts.hmmRoot = fullfile('C:\Users\...', 'cops_project','output','hmm');
% The default model is sm3. Optional opts.hmmMergeOpts fields are passed to
% mergeCoPsHmmStruct's subject/date overload (for example predictionFile).
%
% For groupingArg='visLvl3', opts.visLvls sets the low/mid/high cutoffs:
%   opts.visLvls = [0.75 0.9];  % low < .75, mid < .9, high otherwise
%
% Top-level opts.referenceTargetMode/Choice and opts.trackingSource are
% forwarded to plotCCG2 unless opts.ccgOpts already defines them.
%
% By default, collectCCG2 also sends bg=-1 controls through plotCCG2,
% separately for each target number and requested visibility grouping, so
% plotCCG2Aggregate can overlay them with matching visibility colors. The
% separation lets plotCCG2 retain model-free one-target controls even when
% two-target controls have no HMM predictions.
%
% aggregateAcrossSessions='pooled' sums the per-session CCG numerator and
% denominator, matching a pooled/concatenated chunk-level CCG when lag grids
% and preprocessing settings are identical across sessions.

if nargin < 2
    groupingArg = [];
end
if nargin < 3 || isempty(opts)
    if isstruct(groupingArg) && ~localLooksLikeGroupingArg(groupingArg)
        opts = groupingArg;
        groupingArg = [];
    else
        opts = struct();
    end
elseif ~isstruct(opts)
    error('collectCCG2:BadOpts', 'opts must be a struct.');
end

opts = localDefaults(opts);
subject = localResolveSubject(subject, opts);
subjectDir = fullfile(char(opts.datadir), char(subject));
if ~exist(subjectDir, 'dir')
    error('collectCCG2:SubjectNotFound', 'Subject directory not found: %s', subjectDir);
end

dateFrom = localParseDateBound(opts.dateFrom, false);
dateTo = localParseDateBound(opts.dateTo, true);
sessionDirs = localSessionDirs(subjectDir, dateFrom, dateTo);

sessionOut = cell(0, 1);
controlSessionOut = cell(0, 1);
controlGroupingArg = localControlGroupingArg(groupingArg);
sessionRows = localEmptyFileRows();

for iDir = 1:numel(sessionDirs)
    sessionDir = sessionDirs(iDir);
    [dayHmm, dayHmmReport, dayHmmError] = localLoadDayHmm( ...
        subject, sessionDir.date, opts);
    files = localListSessionExFiles(fullfile(sessionDir.folder, sessionDir.name));
    for iFile = 1:numel(files)
        filePath = files{iFile};
        row = localInitFileRow(subject, sessionDir.name, sessionDir.date, filePath);
        try
            S = load(filePath, 'ex');
        catch err
            row.status = "load_failed";
            row.message = string(err.message);
            sessionRows = localAppendFileRow(sessionRows, row);
            continue
        end
        if ~isfield(S, 'ex') || ~isstruct(S.ex) || ~isfield(S.ex, 'Trials') || isempty(S.ex.Trials)
            row.status = "missing_ex";
            row.message = "File does not contain ex.Trials";
            sessionRows = localAppendFileRow(sessionRows, row);
            continue
        end

        ex = S.ex;
        if logical(opts.mergeHmm)
            if strlength(dayHmmError) > 0
                row.status = "hmm_merge_failed";
                row.message = dayHmmError;
                row.hmmMergeStatus = "day_merge_failed";
                sessionRows = localAppendFileRow(sessionRows, row);
                continue
            end
            try
                [ex, hmmSessionReport] = localAttachSessionHmm( ...
                    ex, filePath, dayHmm, dayHmmReport);
                row.hmmMergeStatus = "merged";
                row.hmmMergeReport = {hmmSessionReport};
            catch err
                row.status = "hmm_merge_failed";
                row.message = string(err.identifier) + ": " + string(err.message);
                row.hmmMergeStatus = "session_merge_failed";
                sessionRows = localAppendFileRow(sessionRows, row);
                continue
            end
        end
        [waitSecs, waitHz] = localResolveWait(ex);
        row.waitSecs = waitSecs;
        row.waitHz = waitHz;
        [ok, msg] = localSessionMatches(ex, waitSecs, waitHz, opts);
        if ~ok
            row.status = "session_filtered";
            row.message = msg;
            sessionRows = localAppendFileRow(sessionRows, row);
            continue
        end

        [exSub, keepMask, filterDiag] = localSubsetTrials(ex, opts);
        row.filterDiagnostics = {filterDiag};
        row.nSelectedTrials = nnz(keepMask);
        if row.nSelectedTrials < opts.minTrials
            row.status = "too_few_selected_trials";
            row.message = localSelectionFailureMessage(row.nSelectedTrials, opts.minTrials, filterDiag);
            sessionRows = localAppendFileRow(sessionRows, row);
            continue
        end

        ccgOpts = opts.ccgOpts;
        ccgOpts.plot = false;
        if ~isempty(opts.referenceTargetMode) && ...
                (~isfield(ccgOpts, 'referenceTargetMode') || isempty(ccgOpts.referenceTargetMode))
            ccgOpts.referenceTargetMode = opts.referenceTargetMode;
        end
        if ~isempty(opts.referenceTargetChoice) && ...
                (~isfield(ccgOpts, 'referenceTargetChoice') || isempty(ccgOpts.referenceTargetChoice))
            ccgOpts.referenceTargetChoice = opts.referenceTargetChoice;
        end
        if ~isempty(opts.trackingSource) && ...
                (~isfield(ccgOpts, 'trackingSource') || isempty(ccgOpts.trackingSource))
            ccgOpts.trackingSource = opts.trackingSource;
        end
        if ~isempty(opts.hmmHardThreshold) && ...
                (~isfield(ccgOpts, 'hmmHardThreshold') || isempty(ccgOpts.hmmHardThreshold))
            ccgOpts.hmmHardThreshold = opts.hmmHardThreshold;
        end
        trackingOptionNames = {'minTrackingSec', 'trackingBridgeMaxSec', ...
            'interpBlinkSec', 'minChunkSec'};
        for iTrackingOption = 1:numel(trackingOptionNames)
            optionName = trackingOptionNames{iTrackingOption};
            if ~isempty(opts.(optionName)) && ...
                    (~isfield(ccgOpts, optionName) || isempty(ccgOpts.(optionName)))
                ccgOpts.(optionName) = opts.(optionName);
            end
        end
        if ~isfield(ccgOpts, 'refGroup')
            ccgOpts.refGroup = '';
        end
        if isfield(opts, 'visLvls') && ~isempty(opts.visLvls) && ...
                (~isfield(ccgOpts, 'visLvls') || isempty(ccgOpts.visLvls))
            ccgOpts.visLvls = opts.visLvls;
        end
        try
            U = plotCCG2(exSub, groupingArg, ccgOpts);
        catch err
            row.status = "ccg2_failed";
            row.message = string(err.message);
            sessionRows = localAppendFileRow(sessionRows, row);
            continue
        end

        row.nCcgTrials = numel(localFlattenTrialGroups(U));
        if row.nCcgTrials < opts.minTrials
            row.status = "too_few_ccg_trials";
            row.message = sprintf('nCcgTrials=%d < minTrials=%d', row.nCcgTrials, opts.minTrials);
            sessionRows = localAppendFileRow(sessionRows, row);
            continue
        end

        row.status = "included";
        row.message = "";
        sessionRows = localAppendFileRow(sessionRows, row);
        U.collect = struct( ...
            'filePath', string(filePath), ...
            'fileName', string(row.fileName), ...
            'sessionFolder', string(sessionDir.name), ...
            'sessionDate', sessionDir.date, ...
            'waitSecs', waitSecs, ...
            'waitHz', waitHz, ...
            'originalTrialIdx', find(keepMask));
        sessionOut{end+1, 1} = U; %#ok<AGROW>

        if logical(opts.collectControls)
            controlTargetNums = double(opts.controlTargetNums(:)');
            controlTargetNums = unique(controlTargetNums(isfinite(controlTargetNums)), 'stable');
            for iControlTarget = 1:numel(controlTargetNums)
                controlTargetNum = controlTargetNums(iControlTarget);
                controlKeep = localControlTargetMask(ex, opts, controlTargetNum);
                if ~any(controlKeep)
                    continue
                end
                controlOpts = ccgOpts;
                controlOpts.plot = false;
                controlOpts.refGroup = '';
                if abs(controlTargetNum - 1) <= 1e-9
                    controlOpts.trackingSource = 'model-free';
                end
                try
                    [controlTrialArg, controlLevelLabels] = localControlTrialGroups( ...
                        ex, controlKeep, groupingArg, opts);
                    C = plotCCG2(ex, controlTrialArg, controlOpts);
                    C = localRelabelControlOutput(C, controlGroupingArg, ...
                        opts.controlBackgroundNoiseLvl, controlTargetNum, ...
                        controlLevelLabels);
                    C.collect = struct( ...
                        'filePath', string(filePath), ...
                        'fileName', string(row.fileName), ...
                        'sessionFolder', string(sessionDir.name), ...
                        'sessionDate', sessionDir.date, ...
                        'waitSecs', waitSecs, ...
                        'waitHz', waitHz, ...
                        'originalTrialIdx', find(controlKeep));
                    controlSessionOut{end+1, 1} = C; %#ok<AGROW>
                catch err
                    if opts.verbose
                        if abs(controlTargetNum - 1) <= 1e-9
                            fprintf('Skipped target_num=1 control CCG for %s:\n%s\n', ...
                                row.fileName, getReport(err, 'extended', 'hyperlinks', 'off'));
                        else
                            fprintf('Skipped target_num=%g control CCG for %s: %s\n', ...
                                controlTargetNum, row.fileName, err.message);
                        end
                    end
                end
            end
        end

        if opts.verbose
            fprintf('Included %s: %d selected trials, %d CCG trials\n', row.fileName, row.nSelectedTrials, row.nCcgTrials);
        end
    end
end

aggregate = localAggregateSessionOutputs(sessionOut, groupingArg, opts);

out = aggregate;
out.subject = string(subject);
out.groupingArg = groupingArg;
out.sessionOutputs = sessionOut;
out.controlSessionOutputs = controlSessionOut;
out.controlGroupingArg = controlGroupingArg;
out.controlAggregate = localAggregateSessionOutputs(controlSessionOut, controlGroupingArg, opts);
if isempty(sessionRows)
    out.fileTable = table();
else
    out.fileTable = struct2table(sessionRows, 'AsArray', true);
end
out.diagnostics = localBuildDiagnostics(out.fileTable, sessionOut, aggregate);
out.options = opts;
if opts.verbose && isempty(out.groups)
    fprintf('collectCCG2: no aggregate groups were built. Inspect A.fileTable and A.diagnostics.\n');
end
end


function tf = localLooksLikeGroupingArg(value)
tf = ischar(value) || isstring(value) || isnumeric(value) || iscell(value);
end


function controlGroupingArg = localControlGroupingArg(groupingArg)
controlGroupingArg = {'bg', 'tnum'};
codes = localGroupingCodeList(groupingArg);
visibilityCode = "";
for i = 1:numel(codes)
    code = localCanonicalGroupingCode(codes{i});
    if strcmp(code, "vislvl3") || strcmp(code, "vis")
        visibilityCode = code;
        break
    end
end
if strlength(visibilityCode) > 0
    controlGroupingArg = {'bg', char(visibilityCode), 'tnum'};
end
end


function C = localRelabelControlOutput(C, controlGroupingArg, bgLevel, targetNum, levelLabels)
labels = localOutputGroupLabels(C);
for iGroup = 1:numel(C.groups)
    mainLabel = "";
    if numel(levelLabels) >= iGroup
        mainLabel = levelLabels(iGroup);
    elseif numel(labels) >= iGroup
        mainLabel = labels(iGroup);
    end
    label = localControlLabel(controlGroupingArg, mainLabel, ...
        double(bgLevel(1)), double(targetNum));
    C.groups{iGroup}.groupLabel = label;
    labels(iGroup) = label;
end
C.groupLabels = labels;
C.groupingArg = controlGroupingArg;
end


function label = localControlLabel(controlGroupingArg, mainLabel, bgLevel, targetNum)
codes = localGroupingCodeList(controlGroupingArg);
parts = strings(0, 1);
for iCode = 1:numel(codes)
    code = localCanonicalGroupingCode(codes{iCode});
    value = "";
    switch code
        case "bg"
            if isfinite(bgLevel)
                value = string(sprintf('%.15g', bgLevel));
            end
        case "tnum"
            if isfinite(targetNum)
                value = string(sprintf('%.15g', targetNum));
            end
        otherwise
            value = localGroupLabelValue(mainLabel, code);
    end
    if strlength(value) > 0 && ~ismissing(value)
        parts(end+1, 1) = code + ": " + value; %#ok<AGROW>
    end
end
label = strjoin(parts, " | ");
end


function value = localGroupLabelValue(label, requestedCode)
value = "";
parts = split(string(label), "|");
for iPart = 1:numel(parts)
    [code, valueText] = localSplitGroupLabel(parts(iPart));
    if strcmpi(localCanonicalGroupingCode(code), localCanonicalGroupingCode(requestedCode))
        value = valueText;
        return
    end
end
end


function codes = localGroupingCodeList(groupingArg)
codes = {};
if ischar(groupingArg) || (isstring(groupingArg) && isscalar(groupingArg))
    codes = {char(string(groupingArg))};
elseif iscell(groupingArg)
    codes = cell(0, 1);
    for i = 1:numel(groupingArg)
        item = groupingArg{i};
        if ischar(item) || (isstring(item) && isscalar(item))
            codes{end+1, 1} = char(string(item)); %#ok<AGROW>
        end
    end
end
end


function opts = localDefaults(opts)
defaultDatadir = "/media/vpixx/DATA/CoPs";
if ~exist(char(defaultDatadir), 'dir')
    defaultDatadir = "Y:\data\CoPs";
end
if ~isfield(opts, 'datadir') || isempty(opts.datadir)
    if isfield(opts, 'dataRoot') && ~isempty(opts.dataRoot)
        opts.datadir = opts.dataRoot;
    else
        opts.datadir = defaultDatadir;
    end
end
defaults = struct( ...
    'datadir', defaultDatadir, ...
    'mergeHmm', false, ...
    'hmmRoot', fullfile( ...
        'C:\Users\zajkowskiwk\OneDrive - National Institutes of Health', ...
        'cops_project', 'output', 'hmm'), ...
    'hmmModel', 'sm3', ...
    'hmmMergeOpts', struct(), ...
    'dateFrom', [], ...
    'dateTo', [], ...
    'targetNum', [], ...
    'backgroundNoiseLvl', [], ...
    'waitSecs', [], ...
    'waitHz', [], ...
    'waitTolSec', 1e-4, ...
    'waitHzTol', 1e-4, ...
    'lagToleranceSec', 1e-6, ...
    'targetVisibility', [], ...
    'imageName', [], ...
    'groupLevels', [], ...
    'visLvls', [0.75 0.9], ...
    'collectControls', true, ...
    'controlBackgroundNoiseLvl', -1, ...
    'controlTargetNums', [1 2], ...
    'referenceTargetMode', [], ...
    'referenceTargetChoice', [], ...
    'trackingSource', 'hmmFiltered', ...
    'hmmHardThreshold', 0.9, ...
    'minTrackingSec', 0.1, ...
    'trackingBridgeMaxSec', 0.1, ...
    'interpBlinkSec', 0.15, ...
    'minChunkSec', 0.1, ...
    'minTrials', 1, ...
    'ccgOpts', struct(), ...
    'aggregateAcrossSessions', 'pooled', ...
    'verbose', true);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(opts, names{i})
        opts.(names{i}) = defaults.(names{i});
    end
end
if ~(ischar(opts.datadir) || (isstring(opts.datadir) && isscalar(opts.datadir))) || ...
        strlength(strtrim(string(opts.datadir))) == 0
    error('collectCCG2:BadDatadir', 'opts.datadir must be a nonempty path text scalar.');
end
opts.datadir = string(opts.datadir);
% Normalize the legacy name so saved options describe the directory used.
opts.dataRoot = opts.datadir;
if ~(isscalar(opts.mergeHmm) && ...
        (islogical(opts.mergeHmm) || isnumeric(opts.mergeHmm)) && ...
        isfinite(double(opts.mergeHmm)) && ismember(double(opts.mergeHmm), [0 1]))
    error('collectCCG2:BadMergeHmm', 'opts.mergeHmm must be logical true/false or numeric 0/1.');
end
opts.mergeHmm = logical(opts.mergeHmm);
if ~(ischar(opts.hmmRoot) || (isstring(opts.hmmRoot) && isscalar(opts.hmmRoot)))
    error('collectCCG2:BadHmmRoot', 'opts.hmmRoot must be a path text scalar.');
end
opts.hmmRoot = string(opts.hmmRoot);
if ~(ischar(opts.hmmModel) || (isstring(opts.hmmModel) && isscalar(opts.hmmModel)))
    error('collectCCG2:BadHmmModel', 'opts.hmmModel must be a text scalar.');
end
opts.hmmModel = string(validatestring(lower(char(string(opts.hmmModel))), ...
    {'sm3', 'sm', 'tid'}));
if ~isstruct(opts.hmmMergeOpts) || ~isscalar(opts.hmmMergeOpts)
    error('collectCCG2:BadHmmMergeOpts', 'opts.hmmMergeOpts must be a scalar struct.');
end
opts.aggregateAcrossSessions = validatestring(char(string(opts.aggregateAcrossSessions)), ...
    {'pooled', 'session', 'trial', 'support'});
if isempty(opts.ccgOpts)
    opts.ccgOpts = struct();
end
if ~isstruct(opts.ccgOpts)
    error('collectCCG2:BadCcgOpts', 'opts.ccgOpts must be a struct.');
end
opts.minTrials = round(double(opts.minTrials));
if ~isfinite(opts.minTrials) || opts.minTrials < 1
    opts.minTrials = 1;
end
end


function subject = localResolveSubject(subject, opts)
if ~(ischar(subject) || (isstring(subject) && isscalar(subject)))
    error('collectCCG2:BadSubject', 'subject must be a text scalar.');
end
subject = lower(strtrim(string(subject)));
switch subject
    case {"ka", "kaki"}
        subject = "kaki";
    case {"ly", "lychee"}
        subject = "lychee";
end
candidate = fullfile(char(opts.datadir), char(subject));
if ~exist(candidate, 'dir')
    rootInfo = dir(char(opts.datadir));
    rootInfo = rootInfo([rootInfo.isdir]);
    names = string({rootInfo.name});
    match = names(startsWith(lower(names), lower(subject)) & ~ismember(names, [".", ".."]));
    if numel(match) == 1
        subject = match(1);
    end
end
end


function [dayHmm, report, errorMessage] = localLoadDayHmm(subject, sessionDate, opts)
dayHmm = struct('Trials', []);
report = struct();
errorMessage = "";
if ~logical(opts.mergeHmm)
    return
end
if exist('mergeCoPsHmmStruct', 'file') ~= 2
    errorMessage = "collectCCG2:MissingHmmMerger: mergeCoPsHmmStruct.m was not found on the MATLAB path.";
    return
end

mergeOpts = opts.hmmMergeOpts;
mergeOpts.dataRoot = char(opts.datadir);
if ~isfield(mergeOpts, 'hmmRoot') || isempty(mergeOpts.hmmRoot)
    mergeOpts.hmmRoot = char(opts.hmmRoot);
end
if ~isfield(mergeOpts, 'model') || isempty(mergeOpts.model)
    mergeOpts.model = char(opts.hmmModel);
end
if ~isfield(mergeOpts, 'block') || isempty(mergeOpts.block)
    mergeOpts.block = 'all';
end

dateLabel = datestr(sessionDate, 'yyyy.mm.dd');
try
    [dayHmm, report] = mergeCoPsHmmStruct(char(subject), dateLabel, mergeOpts);
catch err
    errorMessage = string(err.identifier) + ": " + string(err.message);
end
end


function [ex, report] = localAttachSessionHmm(ex, filePath, dayHmm, dayReport)
if ~isstruct(dayHmm) || ~isfield(dayHmm, 'Trials') || isempty(dayHmm.Trials)
    error('collectCCG2:EmptyHmmDay', 'The HMM merge returned no trials for this day.');
end
if ~isfield(dayHmm.Trials, 'hmm')
    error('collectCCG2:MissingHmmTrials', 'The merged day does not contain trial-level HMM probabilities.');
end

targetPath = localComparablePath(filePath);
match = false(numel(dayHmm.Trials), 1);
if isfield(dayHmm.Trials, 'sourceFilePath')
    sourcePaths = string({dayHmm.Trials.sourceFilePath})';
    match = localComparablePath(sourcePaths) == targetPath;
end
if ~any(match) && isfield(dayHmm.Trials, 'sourceFileName')
    [~, fileName, extension] = fileparts(filePath);
    sourceNames = string({dayHmm.Trials.sourceFileName})';
    match = strcmpi(sourceNames, string([fileName extension]));
end
indices = find(match);
if isempty(indices)
    error('collectCCG2:HmmSessionNotFound', ...
        'No HMM prediction block matched session file %s.', filePath);
end
if numel(indices) ~= numel(ex.Trials)
    error('collectCCG2:HmmTrialCountMismatch', ...
        'HMM block for %s has %d trials, but the ex file has %d.', ...
        filePath, numel(indices), numel(ex.Trials));
end

for trialNo = 1:numel(ex.Trials)
    ex.Trials(trialNo).hmm = dayHmm.Trials(indices(trialNo)).hmm;
end
if isfield(dayHmm, 'hmmMeta')
    ex.hmmMeta = dayHmm.hmmMeta;
end

report = struct( ...
    'filePath', string(filePath), ...
    'nTrialsMatched', numel(indices), ...
    'predictionFile', strings(0, 1), ...
    'block', []);
if isstruct(dayReport) && isfield(dayReport, 'blocks') && istable(dayReport.blocks)
    blocks = dayReport.blocks;
    blockMatch = true(height(blocks), 1);
    if ismember('rawFile', blocks.Properties.VariableNames)
        blockMatch = localComparablePath(string(blocks.rawFile)) == targetPath;
    end
    if any(blockMatch) && ismember('predictionFile', blocks.Properties.VariableNames)
        report.predictionFile = unique(string(blocks.predictionFile(blockMatch)), 'stable');
    end
    if any(blockMatch) && ismember('block', blocks.Properties.VariableNames)
        report.block = double(blocks.block(blockMatch));
    end
end
end


function path = localComparablePath(path)
path = lower(replace(string(path), '/', '\'));
end


function d = localParseDateBound(value, useEndOfDay)
if isempty(value)
    d = [];
    return
end
if isdatetime(value)
    d = datetime(year(value), month(value), day(value));
else
    d = localParseDateString(char(string(value)));
end
if useEndOfDay
    d = d + days(1) - seconds(eps);
end
end


function d = localParseDateString(s)
s = strtrim(char(s));
try
    d = datetime(s, 'InputFormat', 'yyyy.MM.dd');
    return
catch
end
tok = regexp(lower(s), '^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s*([0-9]{1,2})$', 'tokens', 'once');
if isempty(tok)
    error('collectCCG2:BadDate', 'Date must be ''YYYY.MM.DD'', datetime, or shorthand like ''Jun10''.');
end
months = struct('jan',1,'feb',2,'mar',3,'apr',4,'may',5,'jun',6, ...
    'jul',7,'aug',8,'sep',9,'oct',10,'nov',11,'dec',12);
d = datetime(year(datetime('today')), months.(tok{1}), str2double(tok{2}));
end


function sessionDirs = localSessionDirs(subjectDir, dateFrom, dateTo)
raw = dir(subjectDir);
raw = raw([raw.isdir]);
raw = raw(~ismember({raw.name}, {'.', '..'}));
sessionDirs = struct('name', {}, 'folder', {}, 'date', {});
for i = 1:numel(raw)
    [d, ok] = localParseSessionFolderDate(raw(i).name);
    if ~ok
        continue
    end
    if ~isempty(dateFrom) && d < dateFrom
        continue
    end
    if ~isempty(dateTo) && d > dateTo
        continue
    end
    sessionDirs(end+1) = struct('name', raw(i).name, 'folder', raw(i).folder, 'date', d); %#ok<AGROW>
end
if ~isempty(sessionDirs)
    [~, order] = sort([sessionDirs.date]);
    sessionDirs = sessionDirs(order);
end
end


function [d, ok] = localParseSessionFolderDate(folderName)
ok = false;
d = NaT;
token = regexp(folderName, '^\d{4}\.\d{2}\.\d{2}', 'match', 'once');
if isempty(token)
    return
end
d = datetime(token, 'InputFormat', 'yyyy.MM.dd');
ok = true;
end


function files = localListSessionExFiles(dateDir)
files = {};
rootFiles = dir(fullfile(dateDir, '*.mat'));
rootFiles = rootFiles(~startsWith({rootFiles.name}, 'dailyLog'));
rootFiles = rootFiles(~contains({rootFiles.name}, 'EyeCal'));
rootFiles = rootFiles(~contains({rootFiles.name}, 'hmm_predictions', 'IgnoreCase', true));
rootFiles = rootFiles(~endsWith({rootFiles.name}, '_modelling_processed.mat', 'IgnoreCase', true));
for i = 1:numel(rootFiles)
    files{end+1, 1} = fullfile(rootFiles(i).folder, rootFiles(i).name); %#ok<AGROW>
end
experimentalDir = fullfile(dateDir, 'experimental');
if exist(experimentalDir, 'dir')
    expFiles = dir(fullfile(experimentalDir, '*.mat'));
    expFiles = expFiles(~startsWith({expFiles.name}, 'dailyLog'));
    expFiles = expFiles(~contains({expFiles.name}, 'EyeCal'));
    expFiles = expFiles(~contains({expFiles.name}, 'hmm_predictions', 'IgnoreCase', true));
    expFiles = expFiles(~endsWith({expFiles.name}, '_modelling_processed.mat', 'IgnoreCase', true));
    for i = 1:numel(expFiles)
        files{end+1, 1} = fullfile(expFiles(i).folder, expFiles(i).name); %#ok<AGROW>
    end
end
files = unique(files, 'stable');
end


function [waitSecs, waitHz] = localResolveWait(ex)
waitSecs = NaN;
waitHz = NaN;
if exist('resolveCoPsWaitSecs', 'file') == 2
    try
        [waitSecs, waitHz] = resolveCoPsWaitSecs(ex, NaN);
        return
    catch
    end
end
waitHz = localGetNestedNumeric(ex, {'exp', 'CoPs', 'timing', 'waitHz'});
if isfinite(waitHz) && waitHz > 0
    waitSecs = 1 ./ waitHz;
    return
end
waitSecs = localGetNestedNumeric(ex, {'exp', 'CoPs', 'timing', 'wait_secs'});
if ~isfinite(waitSecs)
    waitSecs = localGetNestedNumeric(ex, {'timing', 'wait_secs'});
end
if isfinite(waitSecs) && waitSecs > 0
    waitHz = 1 ./ waitSecs;
end
end


function [ok, msg] = localSessionMatches(~, waitSecs, waitHz, opts)
ok = true;
msg = "";
if ~isempty(opts.waitSecs)
    target = double(opts.waitSecs(:));
    if ~isfinite(waitSecs) || ~any(abs(waitSecs - target) <= double(opts.waitTolSec))
        ok = false;
        msg = sprintf('waitSecs %.6g did not match requested values', waitSecs);
        return
    end
end
if ~isempty(opts.waitHz)
    target = double(opts.waitHz(:));
    if ~isfinite(waitHz) || ~any(abs(waitHz - target) <= double(opts.waitHzTol))
        ok = false;
        msg = sprintf('waitHz %.6g did not match requested values', waitHz);
        return
    end
end
end


function [exSub, keep, filterDiag] = localSubsetTrials(ex, opts)
nTrials = numel(ex.Trials);
keep = true(nTrials, 1);
filterDiag = struct('name', {}, 'requested', {}, 'nBefore', {}, 'nMatch', {}, 'nAfter', {}, 'available', {});
if ~isempty(opts.targetNum)
    values = localTrialNumericValues(ex, 'target_num');
    match = localNumericMember(values, opts.targetNum);
    [keep, filterDiag] = localApplyTrialFilter(keep, match, filterDiag, 'targetNum', opts.targetNum, values);
end
if ~isempty(opts.backgroundNoiseLvl)
    values = localTrialNumericValues(ex, 'background_noise_lvl');
    match = localNumericMember(values, opts.backgroundNoiseLvl);
    [keep, filterDiag] = localApplyTrialFilter(keep, match, filterDiag, 'backgroundNoiseLvl', opts.backgroundNoiseLvl, values);
end
if ~isempty(opts.targetVisibility)
    values = localTrialNumericValues(ex, 'target_visibility');
    match = localNumericMember(values, opts.targetVisibility);
    [keep, filterDiag] = localApplyTrialFilter(keep, match, filterDiag, 'targetVisibility', opts.targetVisibility, values);
end
if ~isempty(opts.imageName)
    values = localTrialStringValues(ex, 'imageName');
    match = localStringMember(values, opts.imageName);
    [keep, filterDiag] = localApplyTrialFilter(keep, match, filterDiag, 'imageName', opts.imageName, values);
end
exSub = ex;
exSub.Trials = ex.Trials(keep);
exSub.collectSubset = struct('keepMask', keep, 'originalTrialIdx', find(keep));
end


function keep = localControlTargetMask(ex, opts, targetNum)
nTrials = numel(ex.Trials);
keep = true(nTrials, 1);
if ~isempty(opts.controlBackgroundNoiseLvl)
    values = localTrialNumericValues(ex, 'background_noise_lvl');
    keep = keep & localNumericMember(values, opts.controlBackgroundNoiseLvl);
end
values = localTrialNumericValues(ex, 'target_num');
keep = keep & localNumericMember(values, targetNum);
end


function [trialArg, levelLabels] = localControlTrialGroups(ex, keep, groupingArg, opts)
trialArg = find(keep)';
levelLabels = "all";
codes = localGroupingCodeList(groupingArg);
visibilityCode = "";
for iCode = 1:numel(codes)
    code = localCanonicalGroupingCode(codes{iCode});
    if strcmp(code, "vis") || strcmp(code, "vislvl3")
        visibilityCode = code;
        break
    end
end
if strlength(visibilityCode) == 0
    return
end

values = localTrialNumericValues(ex, 'target_visibility');
groups = cell(0, 1);
levelLabels = strings(0, 1);
if strcmp(visibilityCode, "vis")
    levels = unique(values(keep & isfinite(values)), 'sorted');
    for iLevel = 1:numel(levels)
        trials = find(keep & abs(values - levels(iLevel)) <= 1e-9)';
        if isempty(trials)
            continue
        end
        groups{end+1, 1} = trials; %#ok<AGROW>
        levelLabels(end+1, 1) = "vis: " + string(sprintf('%.15g', levels(iLevel))); %#ok<AGROW>
    end
else
    cutoffs = double(opts.visLvls(:)');
    if numel(cutoffs) < 2 || any(~isfinite(cutoffs(1:2))) || cutoffs(2) <= cutoffs(1)
        error('collectCCG2:BadVisLvls', 'opts.visLvls must contain two increasing finite cutoffs.');
    end
    masks = {values < cutoffs(1), ...
        values >= cutoffs(1) & values < cutoffs(2), ...
        values >= cutoffs(2)};
    names = ["low", "mid", "high"];
    for iLevel = 1:3
        trials = find(keep & masks{iLevel} & isfinite(values))';
        if isempty(trials)
            continue
        end
        groups{end+1, 1} = trials; %#ok<AGROW>
        levelLabels(end+1, 1) = "vislvl3: " + names(iLevel); %#ok<AGROW>
    end
end
if isempty(groups)
    trialArg = find(keep)';
    levelLabels = "all";
elseif numel(groups) == 1
    trialArg = groups{1};
else
    trialArg = groups;
end
end


function [keep, filterDiag] = localApplyTrialFilter(keep, match, filterDiag, name, requested, values)
nBefore = nnz(keep);
nMatch = nnz(match);
keep = keep & match;
filterDiag(end+1) = struct( ...
    'name', string(name), ...
    'requested', localValueListText(requested), ...
    'nBefore', nBefore, ...
    'nMatch', nMatch, ...
    'nAfter', nnz(keep), ...
    'available', localAvailableValueText(values)); %#ok<AGROW>
end


function msg = localSelectionFailureMessage(nSelected, minTrials, filterDiag)
msg = sprintf('nSelectedTrials=%d < minTrials=%d', nSelected, minTrials);
if isempty(filterDiag)
    return
end
parts = strings(numel(filterDiag), 1);
for i = 1:numel(filterDiag)
    parts(i) = sprintf('%s requested [%s], available [%s], before=%d, match=%d, after=%d', ...
        filterDiag(i).name, filterDiag(i).requested, filterDiag(i).available, ...
        filterDiag(i).nBefore, filterDiag(i).nMatch, filterDiag(i).nAfter);
end
msg = sprintf('%s; %s', msg, strjoin(parts, '; '));
end


function txt = localValueListText(values)
if isnumeric(values) || islogical(values)
    values = double(values(:));
    values = values(isfinite(values));
    if isempty(values)
        txt = '';
    else
        txt = strjoin(compose('%.15g', values), ',');
    end
elseif ischar(values) || isstring(values)
    txt = strjoin(localTextTokens(values), ',');
elseif iscell(values)
    parts = strings(numel(values), 1);
    for i = 1:numel(values)
        parts(i) = string(localValueListText(values{i}));
    end
    txt = strjoin(parts, ',');
else
    txt = strjoin(strtrim(string(values(:))), ',');
end
txt = char(txt);
end


function txt = localAvailableValueText(values)
if isnumeric(values) || islogical(values)
    values = double(values(:));
    values = values(isfinite(values));
    values = unique(values, 'stable');
    if isempty(values)
        txt = '';
    else
        txt = strjoin(compose('%.15g', values), ',');
    end
else
    values = strtrim(string(values(:)));
    values = values(strlength(values) > 0 & ~ismissing(values));
    values = unique(values, 'stable');
    txt = strjoin(values, ',');
end
txt = char(txt);
end


function values = localTrialNumericValues(ex, fieldName)
nTrials = numel(ex.Trials);
values = NaN(nTrials, 1);
fallback = localTrialFieldFallback(ex, fieldName);
for i = 1:nTrials
    T = ex.Trials(i);
    if isfield(T, fieldName) && isnumeric(T.(fieldName)) && isscalar(T.(fieldName))
        values(i) = double(T.(fieldName));
    elseif isfinite(fallback)
        values(i) = fallback;
    end
end
end


function fallback = localTrialFieldFallback(ex, fieldName)
fallback = NaN;
switch fieldName
    case 'target_num'
        fallback = localGetNestedNumeric(ex, {'exp', 'CoPs', 'ctl', 'target_num'});
    case 'background_noise_lvl'
        fallback = localGetNestedNumeric(ex, {'exp', 'CoPs', 'graph', 'background_noise_lvl'});
    case 'target_visibility'
        fallback = localGetNestedNumeric(ex, {'exp', 'CoPs', 'graph', 'target_visibility'});
end
end


function values = localTrialStringValues(ex, fieldName)
nTrials = numel(ex.Trials);
values = strings(nTrials, 1);
for i = 1:nTrials
    T = ex.Trials(i);
    if isfield(T, fieldName) && (ischar(T.(fieldName)) || isstring(T.(fieldName)))
        values(i) = string(T.(fieldName));
    end
end
end


function mask = localNumericMember(values, requested)
mask = false(size(values));
if isempty(requested)
    return
end
if isnumeric(requested) || islogical(requested)
    requested = double(requested(:));
    requested = requested(isfinite(requested));
    for i = 1:numel(requested)
        mask = mask | abs(values - requested(i)) <= 1e-9;
    end
    return
end
if iscell(requested)
    for i = 1:numel(requested)
        mask = mask | localNumericMember(values, requested{i});
    end
    return
end
if ischar(requested) || isstring(requested)
    requested = localTextTokens(requested);
    for i = 1:numel(requested)
        mask = mask | localNumericFilterMask(values, requested(i));
    end
    return
end
error('collectCCG2:BadNumericFilter', ...
    'Numeric filters must be numeric values or comparison strings such as ''>0''.');
end


function tokens = localTextTokens(value)
if ischar(value)
    tokens = strtrim(string(value));
else
    tokens = strtrim(string(value(:)));
end
tokens = tokens(strlength(tokens) > 0 & ~ismissing(tokens));
end


function mask = localNumericFilterMask(values, expr)
expr = strtrim(string(expr));
tok = regexp(char(expr), ...
    '^\s*(>=|<=|==|~=|!=|>|<|=)?\s*([-+]?(?:(?:\d+\.?\d*)|(?:\.\d+))(?:[eE][-+]?\d+)?)\s*$', ...
    'tokens', 'once');
if isempty(tok)
    error('collectCCG2:BadNumericFilter', ...
        'Could not parse numeric filter ''%s''. Use forms like ''>0'', ''<=5'', or ''==1''.', expr);
end
op = tok{1};
threshold = str2double(tok{2});
if isempty(op)
    op = '==';
elseif strcmp(op, '=')
    op = '==';
elseif strcmp(op, '!=')
    op = '~=';
end
switch op
    case '>'
        mask = values > threshold;
    case '>='
        mask = values >= threshold;
    case '<'
        mask = values < threshold;
    case '<='
        mask = values <= threshold;
    case '=='
        mask = abs(values - threshold) <= 1e-9;
    case '~='
        mask = isfinite(values) & abs(values - threshold) > 1e-9;
    otherwise
        error('collectCCG2:BadNumericFilter', ...
            'Unsupported numeric filter operator ''%s''.', op);
end
end


function mask = localStringMember(values, requested)
requested = string(requested);
requested = requested(:);
requested = requested(strlength(strtrim(requested)) > 0);
mask = false(size(values));
for i = 1:numel(requested)
    mask = mask | strcmpi(strtrim(values), strtrim(requested(i)));
end
end


function aggregate = localAggregateSessionOutputs(sessionOut, groupingArg, opts)
aggregate = struct();
aggregate.lagSec = [];
aggregate.groups = {};
aggregate.groupLabels = strings(0, 1);
aggregate.aggregateAcrossSessions = string(opts.aggregateAcrossSessions);
aggregate.nSessions = numel(sessionOut);
if isempty(sessionOut)
    return
end

lagSec = [];
for i = 1:numel(sessionOut)
    if isfield(sessionOut{i}, 'lagSec') && ~isempty(sessionOut{i}.lagSec)
        lagSec = double(sessionOut{i}.lagSec(:)');
        break
    end
end
if isempty(lagSec)
    return
end
requestedLabels = localRequestedGroupLabels(groupingArg, opts);
discoveredLabels = localUnionGroupLabels(sessionOut);
recordLabels = strings(0, 1);
recordCurves = cell(0, 1);
recordWeights = zeros(0, 1);
recordNTrials = zeros(0, 1);
recordNChunks = zeros(0, 1);
recordSupport = zeros(0, 1);
recordAccumRows = cell(0, 1);
recordWeightRows = cell(0, 1);
recordSupportRows = cell(0, 1);
recordFileNames = strings(0, 1);

for iSession = 1:numel(sessionOut)
    U = sessionOut{iSession};
    sessionLagSec = localSessionLagSec(U);
    if isempty(sessionLagSec)
        continue
    end
    sessionLabels = strtrim(localOutputGroupLabels(U));
    for g = 1:numel(U.groups)
        if g > numel(sessionLabels)
            continue
        end
        label = strtrim(sessionLabels(g));
        if strlength(label) == 0 || ismissing(label)
            continue
        end
        group = U.groups{g};
        curve = localCurveOnReferenceLag(group, sessionLagSec, lagSec, opts);
        if isempty(curve) || numel(curve) ~= numel(lagSec) || ~any(isfinite(curve))
            continue
        end
        nTrials = numel(localGetGroupTrials(group));
        nChunks = localFiniteSum(localGetGroupField(group, 'nChunks2D'));
        support = localFiniteSum(localGetGroupField(group, 'support2D'));
        [accumRow, weightRow, supportRow] = localPooledRowsOnReferenceLag(group, sessionLagSec, lagSec, opts, curve);
        weight = localSessionWeight(opts.aggregateAcrossSessions, nTrials, support);
        recordLabels(end+1, 1) = label; %#ok<AGROW>
        recordCurves{end+1, 1} = curve; %#ok<AGROW>
        recordWeights(end+1, 1) = weight; %#ok<AGROW>
        recordNTrials(end+1, 1) = nTrials; %#ok<AGROW>
        recordNChunks(end+1, 1) = nChunks; %#ok<AGROW>
        recordSupport(end+1, 1) = support; %#ok<AGROW>
        recordAccumRows{end+1, 1} = accumRow; %#ok<AGROW>
        recordWeightRows{end+1, 1} = weightRow; %#ok<AGROW>
        recordSupportRows{end+1, 1} = supportRow; %#ok<AGROW>
        if isfield(U, 'collect') && isfield(U.collect, 'fileName')
            recordFileNames(end+1, 1) = string(U.collect.fileName); %#ok<AGROW>
        else
            recordFileNames(end+1, 1) = "session " + string(iSession); %#ok<AGROW>
        end
    end
end

if isempty(requestedLabels)
    labels = localUniqueStableStrings(recordLabels);
else
    labels = requestedLabels;
end
if isempty(labels) && ~isempty(discoveredLabels)
    labels = discoveredLabels;
end

groups = cell(numel(labels), 1);
for iLabel = 1:numel(labels)
    idx = find(localGroupLabelMatches(recordLabels, labels(iLabel)));
    if isempty(idx) && isempty(requestedLabels)
        idx = find(strcmp(recordLabels, labels(iLabel)));
    end
    if isempty(idx)
        groups{iLabel} = localBuildAggregateGroup(labels(iLabel), [], [], [], [], [], strings(0, 1), lagSec, opts.aggregateAcrossSessions, [], [], []);
    else
        curves = vertcat(recordCurves{idx});
        accumRows = vertcat(recordAccumRows{idx});
        weightRows = vertcat(recordWeightRows{idx});
        supportRows = vertcat(recordSupportRows{idx});
        groups{iLabel} = localBuildAggregateGroup(labels(iLabel), curves, recordWeights(idx), ...
            recordNTrials(idx), recordNChunks(idx), recordSupport(idx), recordFileNames(idx), ...
            lagSec, opts.aggregateAcrossSessions, accumRows, weightRows, supportRows);
    end
end

aggregate.lagSec = lagSec;
aggregate.groups = groups;
aggregate.groupLabels = labels(:);
aggregate.discoveredGroupLabels = discoveredLabels(:);
aggregate.groupingArg = groupingArg;
aggregate.aggregateRecords = table(recordLabels(:), recordFileNames(:), recordNTrials(:), recordNChunks(:), recordSupport(:), ...
    'VariableNames', {'groupLabel', 'fileName', 'nTrials', 'nChunks', 'support'});
end


function lagSec = localSessionLagSec(U)
lagSec = [];
if isstruct(U) && isfield(U, 'lagSec') && ~isempty(U.lagSec)
    lagSec = double(U.lagSec(:)');
    lagSec = lagSec(isfinite(lagSec));
end
end


function curve = localCurveOnReferenceLag(group, sessionLagSec, referenceLagSec, opts)
curve = [];
if ~isstruct(group) || ~isfield(group, 'aggregate2D') || isempty(group.aggregate2D)
    return
end
y = double(group.aggregate2D(:)');
sessionLagSec = double(sessionLagSec(:)');
referenceLagSec = double(referenceLagSec(:)');
if numel(y) ~= numel(sessionLagSec) || isempty(y)
    return
end
tol = double(opts.lagToleranceSec);
if ~isfinite(tol) || tol < 0
    tol = 1e-6;
end
if numel(sessionLagSec) == numel(referenceLagSec) && ...
        max(abs(sessionLagSec - referenceLagSec), [], 'omitnan') <= tol
    curve = y;
    return
end
finite = isfinite(sessionLagSec) & isfinite(y);
if nnz(finite) < 2
    return
end
[x, order] = sort(sessionLagSec(finite));
yFinite = y(finite);
yFinite = yFinite(order);
[xUnique, ia] = unique(x, 'stable');
yUnique = yFinite(ia);
if numel(xUnique) < 2
    return
end
curve = interp1(xUnique, yUnique, referenceLagSec, 'linear', NaN);
end


function [accumRow, weightRow, supportRow] = localPooledRowsOnReferenceLag(group, sessionLagSec, referenceLagSec, opts, curve)
nLag = numel(referenceLagSec);
accumRow = NaN(1, nLag);
weightRow = NaN(1, nLag);
supportRow = NaN(1, nLag);
if ~isstruct(group)
    return
end
supportCandidate = localGroupFieldOnReferenceLag(group, 'support2D', sessionLagSec, referenceLagSec, opts);
if ~isempty(supportCandidate)
    supportRow = supportCandidate;
end
weightCandidate = localGroupFieldOnReferenceLag(group, 'weightSum2D', sessionLagSec, referenceLagSec, opts);
if ~isempty(weightCandidate)
    weightRow = weightCandidate;
elseif ~isempty(supportCandidate)
    weightRow = supportCandidate;
end
accumCandidate = localGroupFieldOnReferenceLag(group, 'accum2D', sessionLagSec, referenceLagSec, opts);
if ~isempty(accumCandidate)
    accumRow = accumCandidate;
elseif ~isempty(curve) && numel(curve) == nLag && ~all(isnan(weightRow))
    accumRow = curve(:)' .* weightRow;
end
end


function row = localGroupFieldOnReferenceLag(group, fieldName, sessionLagSec, referenceLagSec, opts)
row = [];
if ~isstruct(group) || ~isfield(group, fieldName) || isempty(group.(fieldName))
    return
end
y = double(group.(fieldName)(:)');
sessionLagSec = double(sessionLagSec(:)');
referenceLagSec = double(referenceLagSec(:)');
if numel(y) ~= numel(sessionLagSec) || isempty(y)
    return
end
tol = double(opts.lagToleranceSec);
if ~isfinite(tol) || tol < 0
    tol = 1e-6;
end
if numel(sessionLagSec) == numel(referenceLagSec) && ...
        max(abs(sessionLagSec - referenceLagSec), [], 'omitnan') <= tol
    row = y;
    return
end
finite = isfinite(sessionLagSec) & isfinite(y);
if nnz(finite) < 2
    return
end
[x, order] = sort(sessionLagSec(finite));
yFinite = y(finite);
yFinite = yFinite(order);
[xUnique, ia] = unique(x, 'stable');
yUnique = yFinite(ia);
if numel(xUnique) < 2
    return
end
row = interp1(xUnique, yUnique, referenceLagSec, 'linear', NaN);
end


function labels = localUnionGroupLabels(sessionOut)
labels = strings(0, 1);
for i = 1:numel(sessionOut)
    these = localOutputGroupLabels(sessionOut{i});
    for j = 1:numel(these)
        label = strtrim(these(j));
        if strlength(label) == 0 || ismissing(label)
            continue
        end
        if ~any(strcmp(labels, label))
            labels(end+1, 1) = label; %#ok<AGROW>
        end
    end
end
end


function labels = localUniqueStableStrings(values)
values = string(values(:));
labels = strings(0, 1);
for i = 1:numel(values)
    value = strtrim(values(i));
    if strlength(value) == 0 || ismissing(value)
        continue
    end
    if ~any(strcmp(labels, value))
        labels(end+1, 1) = value; %#ok<AGROW>
    end
end
end


function labels = localRequestedGroupLabels(groupingArg, opts)
labels = strings(0, 1);
if ~(ischar(groupingArg) || (isstring(groupingArg) && isscalar(groupingArg)))
    return
end
code = localCanonicalGroupingCode(groupingArg);
if strcmp(code, "vislvl3") && (~isfield(opts, 'groupLevels') || isempty(opts.groupLevels))
    labels = ["visLvl3: low"; "visLvl3: mid"; "visLvl3: high"];
    return
end
if ~isfield(opts, 'groupLevels') || isempty(opts.groupLevels)
    return
end
if ~ismember(code, ["bg", "vis", "vislvl3", "tnum", "im"])
    return
end
levels = opts.groupLevels;
if isstruct(levels)
    if isfield(levels, code)
        levels = levels.(code);
    else
        return
    end
end
levelText = localLevelTextList(levels);
labels = strings(numel(levelText), 1);
for i = 1:numel(levelText)
    labels(i) = string(code) + ": " + levelText(i);
end
end


function tf = localGroupLabelMatches(candidateLabels, requestedLabel)
candidateLabels = string(candidateLabels(:));
requestedLabel = strtrim(string(requestedLabel));
tf = strcmpi(strtrim(candidateLabels), requestedLabel);
if any(tf)
    return
end

[requestedCode, requestedValueText] = localSplitGroupLabel(requestedLabel);
requestedValue = str2double(requestedValueText);
if strlength(requestedCode) == 0
    return
end

for i = 1:numel(candidateLabels)
    [candidateCode, candidateValueText] = localSplitGroupLabel(candidateLabels(i));
    if ~strcmpi(candidateCode, requestedCode)
        continue
    end
    if strcmpi(strtrim(candidateValueText), strtrim(requestedValueText))
        tf(i) = true;
        continue
    end
    candidateValue = str2double(candidateValueText);
    if isfinite(requestedValue) && isfinite(candidateValue) && abs(candidateValue - requestedValue) <= 1e-9
        tf(i) = true;
    end
end
end


function [code, valueText] = localSplitGroupLabel(label)
label = strtrim(string(label));
code = "";
valueText = "";
parts = split(label, "|");
part = strtrim(parts(1));
tok = regexp(char(part), '^\s*([^:]+)\s*:\s*(.*?)\s*$', 'tokens', 'once');
if isempty(tok)
    return
end
code = lower(strtrim(string(tok{1})));
valueText = strtrim(string(tok{2}));
end


function code = localCanonicalGroupingCode(value)
code = lower(strtrim(string(value)));
switch code
    case {"background", "backgroundnoise", "backgroundnoiselvl", "background_noise_lvl"}
        code = "bg";
    case {"visibility", "targetvisibility", "target_visibility"}
        code = "vis";
    case {"vislvl3", "vislevel3", "visibilitylvl3", "visibilitylevel3"}
        code = "vislvl3";
    case {"targetnum", "target_num", "targetnumber", "target_number"}
        code = "tnum";
    case {"image", "imagename", "image_name"}
        code = "im";
end
end


function txt = localLevelTextList(levels)
if isnumeric(levels) || islogical(levels)
    vals = double(levels(:));
    vals = vals(isfinite(vals));
    txt = strings(numel(vals), 1);
    for i = 1:numel(vals)
        txt(i) = string(vals(i));
    end
elseif iscell(levels)
    txt = strings(numel(levels), 1);
    for i = 1:numel(levels)
        txt(i) = strtrim(string(levels{i}));
    end
else
    txt = strtrim(string(levels(:)));
end
txt = txt(strlength(txt) > 0 & ~ismissing(txt));
end


function labels = localOutputGroupLabels(U)
nGroup = numel(U.groups);
labels = strings(nGroup, 1);
if isfield(U, 'groupLabels') && numel(U.groupLabels) >= nGroup
    raw = string(U.groupLabels(:));
    labels(:) = strtrim(raw(1:nGroup));
    return
end
for g = 1:nGroup
    if isfield(U.groups{g}, 'groupLabel') && ~isempty(U.groups{g}.groupLabel)
        labels(g) = strtrim(string(U.groups{g}.groupLabel));
    else
        labels(g) = "group " + string(g);
    end
end
end


function weight = localSessionWeight(mode, nTrials, support)
switch char(mode)
    case 'trial'
        weight = max(0, nTrials);
    case 'support'
        weight = max(0, support);
    otherwise
        weight = 1;
end
if ~isfinite(weight) || weight <= 0
    weight = 1;
end
end


function group = localBuildAggregateGroup(label, curves, weights, nTrialsBySession, nChunksBySession, supportBySession, fileNames, lagSec, mode, accumRows, weightRows, supportRows)
if nargin < 9 || isempty(mode)
    mode = 'session';
end
if nargin < 10
    accumRows = [];
end
if nargin < 11
    weightRows = [];
end
if nargin < 12
    supportRows = [];
end
group = struct();
group.groupLabel = label;
group.lagSec = lagSec;
group.sessionCurves = curves;
group.sessionWeights = weights;
group.sessionAccum2D = accumRows;
group.sessionWeightSum2D = weightRows;
group.sessionSupport2D = supportRows;
group.fileNames = fileNames;
group.nSessions = size(curves, 1);
group.nTrialsBySession = nTrialsBySession;
group.nChunksBySession = nChunksBySession;
group.supportBySession = supportBySession;
group.nTrials = localFiniteSum(nTrialsBySession);
group.nChunks = localFiniteSum(nChunksBySession);
group.support = localFiniteSum(supportBySession);
group.accum2D = localColumnNanSum(accumRows);
group.weightSum2D = localColumnNanSum(weightRows);
group.support2D = localColumnNanSum(supportRows);
switch char(string(mode))
    case 'pooled'
        group.aggregate2D = localSafeDivideRows(group.accum2D, group.weightSum2D);
    case 'support'
        group.aggregate2D = localWeightedNanMeanRows(curves, supportRows);
    otherwise
        group.aggregate2D = localWeightedNanMean(curves, weights);
end
group.sem2D = localNanSem(curves);
end


function row = localColumnNanSum(M)
if isempty(M)
    row = NaN(1, 0);
    return
end
row = NaN(1, size(M, 2));
for i = 1:size(M, 2)
    x = M(:, i);
    x = x(isfinite(x));
    if ~isempty(x)
        row(i) = sum(x);
    end
end
end


function row = localSafeDivideRows(num, denom)
if isempty(num) || isempty(denom) || numel(num) ~= numel(denom)
    row = NaN(1, 0);
    return
end
row = NaN(size(num));
mask = isfinite(num) & isfinite(denom) & denom > 0;
row(mask) = num(mask) ./ denom(mask);
end


function meanRow = localWeightedNanMeanRows(curves, weights)
if isempty(curves)
    meanRow = NaN(1, 0);
    return
end
if isempty(weights) || ~isequal(size(weights), size(curves))
    meanRow = localWeightedNanMean(curves, ones(size(curves, 1), 1));
    return
end
meanRow = NaN(1, size(curves, 2));
for i = 1:size(curves, 2)
    y = curves(:, i);
    w = weights(:, i);
    keep = isfinite(y) & isfinite(w) & w > 0;
    if any(keep)
        meanRow(i) = sum(y(keep) .* w(keep)) ./ sum(w(keep));
    end
end
end


function meanRow = localWeightedNanMean(curves, weights)
if isempty(curves)
    meanRow = NaN(1, 0);
    return
end
weights = double(weights(:));
meanRow = NaN(1, size(curves, 2));
for i = 1:size(curves, 2)
    y = curves(:, i);
    keep = isfinite(y) & isfinite(weights) & weights > 0;
    if any(keep)
        meanRow(i) = sum(y(keep) .* weights(keep)) ./ sum(weights(keep));
    end
end
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


function value = localFiniteSum(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    value = 0;
else
    value = sum(x);
end
end


function value = localGetGroupField(group, fieldName)
if isstruct(group) && isfield(group, fieldName) && ~isempty(group.(fieldName))
    value = group.(fieldName);
else
    value = [];
end
end


function trials = localGetGroupTrials(group)
if isstruct(group) && isfield(group, 'trials') && ~isempty(group.trials)
    trials = double(group.trials(:));
else
    trials = [];
end
end


function trials = localFlattenTrialGroups(U)
trials = [];
if ~isfield(U, 'trialGroups') || isempty(U.trialGroups)
    return
end
pieces = cell(numel(U.trialGroups), 1);
for i = 1:numel(U.trialGroups)
    pieces{i} = double(U.trialGroups{i}(:));
end
pieces = pieces(~cellfun(@isempty, pieces));
if ~isempty(pieces)
    trials = unique(vertcat(pieces{:}));
end
end


function rows = localEmptyFileRows()
rows = struct('subject', {}, 'sessionFolder', {}, 'sessionDate', {}, ...
    'fileName', {}, 'filePath', {}, 'status', {}, 'message', {}, ...
    'waitSecs', {}, 'waitHz', {}, 'nSelectedTrials', {}, 'nCcgTrials', {}, ...
    'filterDiagnostics', {}, 'hmmMergeStatus', {}, 'hmmMergeReport', {});
end


function row = localInitFileRow(subject, sessionFolder, sessionDate, filePath)
[~, name, ext] = fileparts(filePath);
row = struct( ...
    'subject', string(subject), ...
    'sessionFolder', string(sessionFolder), ...
    'sessionDate', sessionDate, ...
    'fileName', string([name ext]), ...
    'filePath', string(filePath), ...
    'status', "unchecked", ...
    'message', "", ...
    'waitSecs', NaN, ...
    'waitHz', NaN, ...
    'nSelectedTrials', NaN, ...
    'nCcgTrials', NaN, ...
    'filterDiagnostics', {[]}, ...
    'hmmMergeStatus', "not_requested", ...
    'hmmMergeReport', {[]});
end


function rows = localAppendFileRow(rows, row)
if isempty(rows)
    rows = row;
else
    rows(end+1) = row;
end
end


function value = localGetNestedNumeric(s, fields)
value = NaN;
for i = 1:numel(fields)
    if ~isstruct(s) || ~isfield(s, fields{i})
        return
    end
    s = s.(fields{i});
end
if (isnumeric(s) || islogical(s)) && isscalar(s) && isfinite(double(s))
    value = double(s);
end
end


function diagnostics = localBuildDiagnostics(fileTable, sessionOut, aggregate)
diagnostics = struct();
diagnostics.nSessionOutputs = numel(sessionOut);
diagnostics.nAggregateGroups = numel(aggregate.groups);
diagnostics.statusCounts = table();
diagnostics.failedMessages = table();
diagnostics.filterTable = table();
if isempty(fileTable) || ~istable(fileTable) || ~ismember('status', fileTable.Properties.VariableNames)
    return
end
statuses = string(fileTable.status);
uniqueStatus = unique(statuses, 'stable');
counts = zeros(numel(uniqueStatus), 1);
for i = 1:numel(uniqueStatus)
    counts(i) = nnz(statuses == uniqueStatus(i));
end
diagnostics.statusCounts = table(uniqueStatus(:), counts, ...
    'VariableNames', {'status', 'count'});
if ismember('message', fileTable.Properties.VariableNames)
    keep = statuses ~= "included" & strlength(string(fileTable.message)) > 0;
    if any(keep)
        vars = intersect({'fileName', 'status', 'message', 'waitHz', 'nSelectedTrials', 'nCcgTrials'}, ...
            fileTable.Properties.VariableNames, 'stable');
        diagnostics.failedMessages = fileTable(keep, vars);
    end
end
diagnostics.filterTable = localFlattenFilterDiagnostics(fileTable);
end


function T = localFlattenFilterDiagnostics(fileTable)
T = table();
if ~ismember('filterDiagnostics', fileTable.Properties.VariableNames)
    return
end
rows = struct('fileName', {}, 'status', {}, 'filter', {}, 'requested', {}, ...
    'available', {}, 'nBefore', {}, 'nMatch', {}, 'nAfter', {});
for i = 1:height(fileTable)
    diag = localFilterDiagnosticsForRow(fileTable, i);
    if isempty(diag)
        continue
    end
    for j = 1:numel(diag)
        rows(end+1) = struct( ... %#ok<AGROW>
            'fileName', string(fileTable.fileName(i)), ...
            'status', string(fileTable.status(i)), ...
            'filter', string(diag(j).name), ...
            'requested', string(diag(j).requested), ...
            'available', string(diag(j).available), ...
            'nBefore', double(diag(j).nBefore), ...
            'nMatch', double(diag(j).nMatch), ...
            'nAfter', double(diag(j).nAfter));
    end
end
if ~isempty(rows)
    T = struct2table(rows, 'AsArray', true);
end
end


function diag = localFilterDiagnosticsForRow(fileTable, rowIdx)
diag = [];
try
    raw = fileTable.filterDiagnostics{rowIdx};
catch
    raw = fileTable.filterDiagnostics(rowIdx);
end
while iscell(raw) && numel(raw) == 1
    raw = raw{1};
end
if isstruct(raw)
    diag = raw(:);
elseif iscell(raw)
    pieces = cell(0, 1);
    for i = 1:numel(raw)
        if isstruct(raw{i})
            pieces{end+1, 1} = raw{i}(:); %#ok<AGROW>
        end
    end
    if ~isempty(pieces)
        diag = vertcat(pieces{:});
    end
end
end
