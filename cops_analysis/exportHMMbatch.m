function summary = exportHMMbatch(fromDate, toDate, opts)
% exportHMMbatch  Export fitted HMM outputs over an inclusive date range.
%
%   summary = exportHMMbatch('jun02')
%   summary = exportHMMbatch('jun06', 'july12')
%   summary = exportHMMbatch('2026.06.06', '2026.07.12', opts)
%
% With one date, exports every fitted animal-day from that date through the
% newest available fitted date. With two dates, both range endpoints are
% inclusive. Short dates are case-insensitive and accept abbreviated or
% full English month names. A short date uses the year of the newest fitted
% prediction available for the selected model.
%
% Batch options
%   opts.model       'sm3' (default) or 'sm'. TID is session-specific and
%                    does not have a reliable day-level filename scheme.
%   opts.animals     {'ka','ly'} (default), or selected animal aliases
%   opts.failFast    false (default); otherwise stop on first failed day
%   opts.dryRun      false (default); true only displays selected jobs
%
% All other opts fields are forwarded to exportHMM. Common examples are:
%   opts.block = 'all';          % default
%   opts.exportSelReg = 1;
%   opts.exportTrackReg = 1;
%   opts.exportPupilReg = 1; % default in exportHMM
%   opts.distanceUnits = 'deg'; % default; use 'px' for legacy output
%   opts.overwrite = false;      % default; existing complete outputs skip
%   opts.outDir = 'C:\my_output';
%
% The returned table contains one row per selected animal-day.

if nargin < 1 || isempty(fromDate)
    error('exportHMMbatch:MissingFromDate', ...
        'Provide a starting date such as ''jun02'' or ''2026.06.02''.');
end
if nargin < 2
    toDate = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
elseif ~isstruct(opts) || ~isscalar(opts)
    error('exportHMMbatch:BadOptions', 'opts must be a scalar structure.');
end
opts = localDefaults(opts);
if opts.exportTrackReg && ~opts.writeOutput
    error('exportHMMbatch:TrackRegRequiresOutput', ...
        ['opts.exportTrackReg=true requires opts.writeOutput=true. ' ...
         'Create a fresh options structure or reset o.writeOutput=true.']);
end

[modelFolder, predictionExpression] = localModelSpec(opts.model);
predictionDir = fullfile(char(opts.hmmRoot), modelFolder, 'preds');
jobs = localPredictionJobs(predictionDir, predictionExpression, opts.animals);
if isempty(jobs)
    error('exportHMMbatch:NoFittedDates', ...
        'No %s day-level prediction files were found in %s.', ...
        upper(opts.model), predictionDir);
end

newestDate = max(jobs.dateValue);
rangeStart = localParseBoundary(fromDate, year(newestDate));
if isempty(toDate) || (isstring(toDate) && isscalar(toDate) && ...
        strlength(strtrim(toDate)) == 0)
    rangeStop = newestDate;
else
    rangeStop = localParseBoundary(toDate, year(newestDate));
end
if rangeStop < rangeStart && localIsShortDate(fromDate) && localIsShortDate(toDate)
    rangeStop = dateshift(rangeStop, 'start', 'year', 'next') + ...
        calmonths(month(rangeStop) - 1) + caldays(day(rangeStop) - 1);
end
if rangeStop < rangeStart
    error('exportHMMbatch:BadDateRange', ...
        'The to date must be on or after the from date.');
end
jobs = jobs(jobs.dateValue >= rangeStart & jobs.dateValue <= rangeStop, :);
if isempty(jobs)
    warning('exportHMMbatch:NoJobsInRange', ...
        'No fitted %s animal-days fall between %s and %s.', ...
        upper(opts.model), string(rangeStart, 'yyyy.MM.dd'), ...
        string(rangeStop, 'yyyy.MM.dd'));
    summary = localEmptySummary();
    return
end
jobs = sortrows(jobs, {'dateValue', 'animal'});
fprintf('exportHMMbatch: selected %d %s animal-days from %s through %s.\n', ...
    height(jobs), upper(opts.model), string(rangeStart, 'yyyy.MM.dd'), ...
    string(rangeStop, 'yyyy.MM.dd'));
if isfield(opts, 'exportTrackReg') && logical(opts.exportTrackReg)
    fprintf('exportHMMbatch: tracking-regressor export is enabled.\n');
end
if opts.dryRun
    summary = jobs(:, {'animal', 'date', 'predictionFile'});
    summary.status = repmat("dry-run", height(summary), 1);
    disp(summary);
    return
end

forwardOpts = rmfield(opts, intersect(fieldnames(opts), ...
    {'animals', 'failFast', 'dryRun'}));
rows = repmat(localEmptyRow(), height(jobs), 1);
for index = 1:height(jobs)
    animal = char(jobs.animal(index));
    dateLabel = char(jobs.date(index));
    fprintf('\n[%d/%d] %s %s %s\n', ...
        index, height(jobs), upper(opts.model), animal, dateLabel);
    row = localEmptyRow();
    row.animal = string(animal);
    row.date = string(dateLabel);
    row.model = string(opts.model);
    row.predictionFile = jobs.predictionFile(index);
    started = tic;
    try
        dayOpts = forwardOpts;
        dayOpts.predictionFile = char(jobs.predictionFile(index));
        report = exportHMM(animal, dateLabel, dayOpts);
        row.nBlocks = height(report);
        row.trialFiles = strjoin(unique(report.outputFile), '; ');
        nonemptyChunks = unique(report.chunkFile(strlength(report.chunkFile) > 0));
        row.chunkFiles = strjoin(nonemptyChunks, '; ');
        nonemptyTracking = unique(report.trackingFile( ...
            strlength(report.trackingFile) > 0));
        row.trackingFiles = strjoin(nonemptyTracking, '; ');
        if opts.exportTrackReg
            if isempty(nonemptyTracking)
                error('exportHMMbatch:MissingTrackingOutput', ...
                    ['exportTrackReg=true and writeOutput=true, but exportHMM ' ...
                     'returned no tracking-regressor path. Effective block=%s; ' ...
                     'report status=%s.'], char(string(opts.block)), ...
                    strjoin(string(report.status), ','));
            end
            fprintf('Tracking regressors: %s\n', row.trackingFiles);
        end
        nonemptyPupil = unique(report.pupilEpisodeFile( ...
            strlength(report.pupilEpisodeFile) > 0));
        row.pupilEpisodeFiles = strjoin(nonemptyPupil, '; ');
        if all(report.status == "already-exists")
            row.status = "already-exists";
        else
            row.status = "completed";
        end
    catch exception
        row.status = "failed";
        row.message = string(exception.identifier) + ": " + string(exception.message);
        fprintf('exportHMMbatch: FAILED %s %s: %s\n', ...
            animal, dateLabel, exception.message);
        if opts.failFast
            rethrow(exception)
        end
    end
    row.elapsedSec = toc(started);
    rows(index) = row;
end
summary = struct2table(rows);
fprintf('\nexportHMMbatch complete: %d completed, %d already existed, %d failed.\n', ...
    nnz(summary.status == "completed"), ...
    nnz(summary.status == "already-exists"), ...
    nnz(summary.status == "failed"));
end


function opts = localDefaults(opts)
defaults = struct( ...
    'model', 'sm3', ...
    'animals', {{'ka', 'ly'}}, ...
    'failFast', false, ...
    'dryRun', false, ...
    'hmmRoot', fullfile( ...
        'C:\Users\zajkowskiwk\OneDrive - National Institutes of Health', ...
        'cops_project', 'output', 'hmm'), ...
    'block', 'all', ...
    'writeOutput', true, ...
    'overwrite', false, ...
    'exportSelReg', false, ...
    'exportTrackReg', false);
names = fieldnames(defaults);
for index = 1:numel(names)
    if ~isfield(opts, names{index}) || isempty(opts.(names{index}))
        opts.(names{index}) = defaults.(names{index});
    end
end
opts.model = lower(char(string(opts.model)));
if ~ismember(opts.model, {'sm', 'sm3'})
    error('exportHMMbatch:BadModel', ...
        'opts.model must be ''sm'' or ''sm3'' for day-level batch export.');
end
if ischar(opts.animals) || (isstring(opts.animals) && isscalar(opts.animals))
    opts.animals = cellstr(string(opts.animals));
elseif isstring(opts.animals)
    opts.animals = cellstr(opts.animals(:));
end
if ~iscell(opts.animals) || isempty(opts.animals)
    error('exportHMMbatch:BadAnimals', ...
        'opts.animals must contain one or more monkey aliases.');
end
opts.animals = unique(string(cellfun(@localAnimal, opts.animals, ...
    'UniformOutput', false)), 'stable');
opts.failFast = localLogicalScalar(opts.failFast, 'failFast');
opts.dryRun = localLogicalScalar(opts.dryRun, 'dryRun');
opts.writeOutput = localLogicalScalar(opts.writeOutput, 'writeOutput');
opts.exportTrackReg = localLogicalScalar( ...
    opts.exportTrackReg, 'exportTrackReg');
end


function value = localLogicalScalar(value, name)
if ~(isscalar(value) && (islogical(value) || isnumeric(value)) && ...
        isfinite(double(value)) && ismember(double(value), [0 1]))
    error('exportHMMbatch:BadOptions', 'opts.%s must be logical or 0/1.', name);
end
value = logical(value);
end


function animal = localAnimal(value)
key = lower(strtrim(char(string(value))));
switch key
    case {'ka', 'kaki'}
        animal = 'kaki';
    case {'ly', 'lychee'}
        animal = 'lychee';
    otherwise
        error('exportHMMbatch:BadAnimal', ...
            'Unknown monkey alias %s; use ka/kaki or ly/lychee.', key);
end
end


function [folder, expression] = localModelSpec(model)
switch model
    case 'sm'
        folder = 'tidSM';
        expression = ['^(kaki|lychee)_(\d{4}\.\d{2}\.\d{2})_' ...
            'targetidsens_random_effect_cv(?:_v\d+)?_predictions\.csv$'];
    case 'sm3'
        folder = 'tidSM3';
        expression = ['^(kaki|lychee)_(\d{4}\.\d{2}\.\d{2})_' ...
            'targetidsens3_distance_gated_random_effect_cv' ...
            '(?:_v\d+)?_predictions\.csv$'];
end
end


function jobs = localPredictionJobs(folder, expression, animals)
files = dir(fullfile(folder, '*_predictions.csv'));
rows = repmat(struct('animal', "", 'date', "", 'dateValue', NaT, ...
    'predictionFile', "", 'modified', NaT), 0, 1);
for index = 1:numel(files)
    token = regexp(files(index).name, expression, 'tokens', 'once');
    if isempty(token) || ~ismember(string(token{1}), animals)
        continue
    end
    row = struct();
    row.animal = string(token{1});
    row.date = string(token{2});
    row.dateValue = datetime(token{2}, 'InputFormat', 'yyyy.MM.dd');
    row.predictionFile = string(fullfile(files(index).folder, files(index).name));
    row.modified = datetime(files(index).datenum, 'ConvertFrom', 'datenum');
    rows(end + 1, 1) = row; %#ok<AGROW>
end
if isempty(rows)
    jobs = table();
    return
end
jobs = struct2table(rows);
jobs = sortrows(jobs, {'animal', 'dateValue', 'modified'}, ...
    {'ascend', 'ascend', 'descend'});
[~, keep] = unique(strcat(jobs.animal, "|", jobs.date), 'stable');
jobs = jobs(sort(keep), :);
end


function parsed = localParseBoundary(value, defaultYear)
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
    error('exportHMMbatch:BadDate', ...
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


function row = localEmptyRow()
row = struct('animal', "", 'date', "", 'model', "", 'status', "", ...
    'nBlocks', NaN, 'elapsedSec', NaN, 'predictionFile', "", ...
    'trialFiles', "", 'chunkFiles', "", 'trackingFiles', "", ...
    'pupilEpisodeFiles', "", ...
    'message', "");
end


function T = localEmptySummary()
T = struct2table(repmat(localEmptyRow(), 0, 1));
end
