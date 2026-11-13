function out = pupilHmmStateMeansDays(animal, dateFrom, dateTo, opts)
% pupilHmmStateMeansDays  Compare HMM-state pupil means across fitted days.
%
% out = pupilHmmStateMeansDays(animal, dateFrom, dateTo)
% out = pupilHmmStateMeansDays(animal, dateFrom, dateTo, opts)
%
% Examples
%   out = pupilHmmStateMeansDays('ka', 'jun02', 'jul12');
%   opts = struct('minTrials', 200, 'type', 'dayMean');
%   out = pupilHmmStateMeansDays('ly', [], [], opts);
%
% opts.aggBy controls the independent summary point:
%   'day'     (default) - one paired point per eligible animal-day.
%   'session'           - one paired point per original session/file.
%   'block'             - alias for 'session'.
%
% With aggBy='day', pupil preprocessing and normalization use the complete
% merged day. With aggBy='session', preprocessing and normalization are run
% independently within each original session/file identified by
% ex.Trials.sessionInDay. The plotted thin lines, confidence interval, and
% t test then use sessions rather than days as their independent units.
%
% opts.type:
%   'dayMean'  (default/legacy name) - equal weight for every selected
%                                      day or session aggregation unit.
%   'sampleAgg'          - descriptive pooled-sample state means; paired
%                          unit differences are still reported separately.
%
% opts.withinDayWeight (applied within the selected aggregation unit):
%   'sample' (default) - duration/sample-weighted mean within each day.
%   'trial'            - every trial has equal weight within each day.
%
% The figure uses paired slope plots rather than boxplots. Each thin line is
% one day or session; large markers and error bars show the grand summary.
% Panel 1 compares non-tracking with tracking and panel 2 compares tracking
% of the closer with the farther target.
%
% Day-selection options (defaults):
%   .minTrials       200; minimum trials per selected aggregation unit:
%                         per day for aggBy='day', per original session for
%                         aggBy='session'/'block'
%   .aggBy           'day' ('session' or 'block' also accepted)
%   .model           'sm3'
%   .block           'all'
%   .makePlot        true
%   .failFast        false
%   .dataRoot        'Y:\data\CoPs'
%   .hmmRoot         <cops_project>\output\hmm
%
% Other fields are forwarded to pupilHmmStateMeans; pairedOnly defaults to
% false so state means use every available sample. Dates accept YYYY.MM.DD,
% jun02/June2 style labels, or [] for the oldest/newest fitted date.
%
% Main outputs:
%   .grandStateMeans  across-unit or pooled mean for each state
%   .unitStateMeans   one state mean per selected day/session unit
%   .comparisons      paired across-unit differences and statistics
%   .unitComparisons  one paired difference per aggregation unit
%   .trialMeans       trial/state means with animal and date identifiers
%   .audit            included/excluded/failed fitted dates
%   .figure           paired slope plot
%
% See also pupilHmmStateMeans, pupilHmmTransitionsDays.

if nargin < 2
    dateFrom = [];
end
if nargin < 3
    dateTo = [];
end
if nargin < 4 || isempty(opts)
    opts = struct();
elseif ~isstruct(opts) || ~isscalar(opts)
    error('pupilHmmStateMeansDays:BadOptions', ...
        'opts must be one scalar structure.');
end
opts = localDefaults(opts);
animal = localAnimal(animal);

[modelFolder, predictionExpression] = localModelSpec(opts.model);
predictionDir = fullfile(char(opts.hmmRoot), modelFolder, 'preds');
jobs = localPredictionJobs(predictionDir, predictionExpression, animal);
if isempty(jobs)
    error('pupilHmmStateMeansDays:NoFittedDates', ...
        'No fitted %s dates for %s were found in %s.', ...
        upper(opts.model), animal, predictionDir);
end
[rangeStart, rangeStop] = localDateRange(dateFrom, dateTo, jobs.dateValue);
jobs = jobs(jobs.dateValue >= rangeStart & jobs.dateValue <= rangeStop, :);
jobs = sortrows(jobs, 'dateValue');
if isempty(jobs)
    error('pupilHmmStateMeansDays:NoDatesInRange', ...
        'No fitted dates for %s fall between %s and %s.', animal, ...
        string(rangeStart, 'yyyy.MM.dd'), string(rangeStop, 'yyyy.MM.dd'));
end

fprintf(['pupilHmmStateMeansDays: %d fitted %s days for %s from %s ' ...
    'through %s; minimum %d trials/%s; aggregation=%s.\n'], ...
    height(jobs), upper(opts.model), animal, ...
    string(rangeStart, 'yyyy.MM.dd'), string(rangeStop, 'yyyy.MM.dd'), ...
    opts.minTrials, opts.aggBy, opts.type);

stateOpts = localStateOptions(opts);
mergeOpts = struct('model', opts.model, 'block', opts.block, ...
    'dataRoot', opts.dataRoot, 'hmmRoot', opts.hmmRoot);
auditRows = repmat(localEmptyAudit(), height(jobs), 1);
dayStateTables = cell(0, 1);
dayComparisonTables = cell(0, 1);
trialTables = cell(0, 1);

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
        if strcmp(opts.aggBy, 'day') && row.nTrials < opts.minTrials
            row.status = "below-min-trials";
            row.message = sprintf('%d < %d trials', row.nTrials, opts.minTrials);
            fprintf('excluded (%s).\n', row.message);
            row.elapsedSec = toc(started);
            auditRows(dayIndex) = row;
            continue
        end

        dayStateOpts=stateOpts;
        if opts.posCorrected
            dayStateOpts.posCorrected=true;
            dayStateOpts.posCorrectionAnimal=animal;
            dayStateOpts.posCorrectionDate=dateLabel;
            if ~isfield(dayStateOpts,'posCorrectionOpts')|| ...
                    isempty(dayStateOpts.posCorrectionOpts)
                dayStateOpts.posCorrectionOpts=struct();
            end
            dayStateOpts.posCorrectionOpts.dataRoot=opts.dataRoot;
        end
        correctionScope='session';
        if isfield(dayStateOpts,'correctionScope')&& ...
                ~isempty(dayStateOpts.correctionScope)
            correctionScope=char(string(dayStateOpts.correctionScope));
        end
        useSacCorrection=isfield(dayStateOpts,'sacCor')&& ...
            logical(dayStateOpts.sacCor);
        if strcmpi(correctionScope,'session')&& ...
                (opts.posCorrected||useSacCorrection)
            correctionOpts=dayStateOpts;
            correctionOpts.animal=animal;
            correctionOpts.date=dateLabel;
            [ex,~]=applyPupilCorrectionsBySession(ex,correctionOpts);
            % Correct the complete day once so sessions sharing a calibration
            % are pooled before session-specific normalization below.
            dayStateOpts.posCorrected=false;
            dayStateOpts.sacCor=false;
        end

        if strcmp(opts.aggBy, 'day')
            sessionGroups = NaN;
        else
            allSessions = localTrialSessions(ex, (1:numel(ex.Trials))');
            sessionGroups = unique(allSessions(isfinite(allSessions)), 'stable');
            if isempty(sessionGroups)
                error('pupilHmmStateMeansDays:MissingSessionLabels', ...
                    ['Session aggregation requires numeric ' ...
                     'ex.Trials.sessionInDay labels.']);
            end
        end
        unitTrialTables = cell(0, 1);
        for groupIndex = 1:numel(sessionGroups)
            sessionNo = sessionGroups(groupIndex);
            if strcmp(opts.aggBy, 'day')
                groupOpts = dayStateOpts;
            else
                groupOpts = dayStateOpts;
                sessionTrials = find(allSessions == sessionNo)';
                nTrialsInUnit = numel(sessionTrials);
                if nTrialsInUnit < opts.minTrials
                    row.nUnitsBelowMinTrials = row.nUnitsBelowMinTrials + 1;
                    fprintf('session %g excluded: %d < %d trials.\n', ...
                        sessionNo, nTrialsInUnit, opts.minTrials);
                    continue
                end
                if isfield(groupOpts, 'trialList') && ~isempty(groupOpts.trialList)
                    sessionTrials = intersect( ...
                        double(groupOpts.trialList(:)'), sessionTrials, 'stable');
                end
                if isempty(sessionTrials)
                    continue
                end
                % This call performs pupil centering/scaling using only the
                % current original session, not the complete merged day.
                groupOpts.trialList = sessionTrials;
            end
            groupOut = pupilHmmStateMeans(ex, groupOpts);
            row.nTrialsWithHmm = row.nTrialsWithHmm + ...
                groupOut.meta.nTrialsWithHmm;
            groupTrialMeans = groupOut.trialMeans;
            if isempty(groupTrialMeans)
                continue
            end
            groupTrialMeans.animal = repmat( ...
                string(animal), height(groupTrialMeans), 1);
            groupTrialMeans.date = repmat( ...
                string(dateLabel), height(groupTrialMeans), 1);
            groupTrialMeans.sessionInDay = localTrialSessions( ...
                ex, groupTrialMeans.trial);
            unitTrialTables{end+1, 1} = groupTrialMeans; %#ok<AGROW>
            trialTables{end+1, 1} = groupTrialMeans; %#ok<AGROW>
            unitState = localUnitStateTable( ...
                groupTrialMeans, animal, dateLabel, row.nTrials, ...
                opts.aggBy, sessionNo, opts.withinDayWeight);
            dayStateTables{end+1, 1} = unitState; %#ok<AGROW>
            dayComparisonTables{end+1, 1} = ...
                localUnitComparisons(unitState); %#ok<AGROW>
            row.nUnitsIncluded = row.nUnitsIncluded + 1;
        end
        if isempty(unitTrialTables)
            row.status = "no-eligible-units";
            if strcmp(opts.aggBy, 'session') && row.nUnitsBelowMinTrials > 0
                row.message = sprintf( ...
                    'No sessions met the minimum of %d trials', opts.minTrials);
            else
                row.message = "No usable HMM-state pupil rows";
            end
            fprintf('excluded (%s).\n', row.message);
            row.elapsedSec = toc(started);
            auditRows(dayIndex) = row;
            continue
        end
        trialMeansForDay = vertcat(unitTrialTables{:});
        row.nStateTrialRows = height(trialMeansForDay);
        row.status = "included";
        fprintf('included: %d day trials, %d units, %d state/trial rows.\n', ...
            row.nTrials, row.nUnitsIncluded, row.nStateTrialRows);
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
    error('pupilHmmStateMeansDays:NoEligibleDays', ...
        ['No %s aggregation units met opts.minTrials=%d and completed ' ...
         'successfully. Inspect the console audit or lower opts.minTrials.'], ...
        opts.aggBy, opts.minTrials);
end
unitStateMeans = vertcat(dayStateTables{:});
unitComparisons = vertcat(dayComparisonTables{:});
if isempty(trialTables)
    trialMeans = table();
else
    trialMeans = vertcat(trialTables{:});
end

grandStateMeans = localGrandStateMeans( ...
    unitStateMeans, trialMeans, opts.type, opts.withinDayWeight);
comparisons = localGrandComparisons(unitComparisons);
figureHandle = [];
if opts.makePlot
    figureHandle = localPlot(unitStateMeans, grandStateMeans, comparisons, ...
        animal, rangeStart, rangeStop, opts);
end

out = struct();
out.animal = string(animal);
out.dateFrom = rangeStart;
out.dateTo = rangeStop;
out.type = string(opts.type);
out.aggBy = string(opts.aggBy);
out.unitStateMeans = unitStateMeans;
out.grandStateMeans = grandStateMeans;
out.unitComparisons = unitComparisons;
out.comparisons = comparisons;
if strcmp(opts.aggBy, 'day')
    out.dayStateMeans = unitStateMeans;
    out.dayComparisons = unitComparisons;
    out.sessionStateMeans = table();
    out.sessionComparisons = table();
else
    out.dayStateMeans = table();
    out.dayComparisons = table();
    out.sessionStateMeans = unitStateMeans;
    out.sessionComparisons = unitComparisons;
end
out.trialMeans = trialMeans;
out.audit = audit;
out.figure = figureHandle;
out.opts = opts;
out.meta = struct( ...
    'nFittedDaysSelected', height(jobs), ...
    'nEligibleDays', nnz(included), ...
    'nExcludedBelowTrialMinimum', nnz(audit.status == "below-min-trials"), ...
    'nUnitsExcludedBelowTrialMinimum', sum(audit.nUnitsBelowMinTrials), ...
    'nDaysWithNoEligibleUnits', nnz(audit.status == "no-eligible-units"), ...
    'nFailedDays', nnz(audit.status == "failed"), ...
    'minimumTrialsPerAggregationUnit', opts.minTrials, ...
    'primaryInferentialUnit', opts.aggBy, ...
    'nAggregationUnits', numel(unique(unitStateMeans.unitId)));
end


function opts = localDefaults(opts)
defaults = struct( ...
    'minTrials', 200, ...
    'aggBy', 'day', ...
    'type', 'dayMean', ...
    'withinDayWeight', 'sample', ...
    'model', 'sm3', ...
    'block', 'all', ...
    'makePlot', true, ...
    'failFast', false, ...
    'pairedOnly', false, ...
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
opts.type = validatestring(char(string(opts.type)), {'dayMean','sampleAgg'});
opts.aggBy = validatestring(lower(char(string(opts.aggBy))), ...
    {'day','session','block'});
if strcmp(opts.aggBy, 'block')
    opts.aggBy = 'session';
end
opts.withinDayWeight = validatestring(char(string(opts.withinDayWeight)), ...
    {'sample','trial'});
opts.model = lower(char(string(opts.model)));
if ~strcmp(opts.model, 'sm3')
    error('pupilHmmStateMeansDays:BadModel', ...
        'Tracking/non-tracking state means require opts.model=''sm3''.');
end
if ~(isscalar(opts.minTrials) && isnumeric(opts.minTrials) && ...
        isfinite(opts.minTrials) && opts.minTrials >= 0 && ...
        opts.minTrials == round(opts.minTrials))
    error('pupilHmmStateMeansDays:BadMinTrials', ...
        'opts.minTrials must be a nonnegative integer.');
end
opts.makePlot = localLogical(opts.makePlot, 'makePlot');
opts.failFast = localLogical(opts.failFast, 'failFast');
opts.posCorrected = localLogical(opts.posCorrected, 'posCorrected');
end


function value = localLogical(value, name)
if ~(isscalar(value) && (islogical(value) || isnumeric(value)) && ...
        isfinite(double(value)) && ismember(double(value), [0 1]))
    error('pupilHmmStateMeansDays:BadOptions', ...
        'opts.%s must be logical or 0/1.', name);
end
value = logical(value);
end


function stateOpts = localStateOptions(opts)
collector = {'minTrials','aggBy','type','withinDayWeight','model','block', ...
    'makePlot','failFast','dataRoot','hmmRoot'};
stateOpts = opts;
present = intersect(fieldnames(stateOpts), collector);
if ~isempty(present)
    stateOpts = rmfield(stateOpts, present);
end
stateOpts.makePlot = false;
stateOpts.requireSm3 = true;
end


function sessions = localTrialSessions(ex, trialNumbers)
trialNumbers = double(trialNumbers(:));
sessions = nan(size(trialNumbers));
for index = 1:numel(trialNumbers)
    trialNo = trialNumbers(index);
    if isfinite(trialNo) && trialNo == round(trialNo) && ...
            trialNo >= 1 && trialNo <= numel(ex.Trials) && ...
            isfield(ex.Trials(trialNo), 'sessionInDay')
        value = double(ex.Trials(trialNo).sessionInDay);
        if isscalar(value) && isfinite(value)
            sessions(index) = value;
        end
    end
end
end


function T = localUnitStateTable( ...
        trialMeans, animal, dateLabel, nTrialsDay, aggBy, sessionNo, weighting)
states = ["nonTracking"; "tracking"; "closer"; "farther"];
if strcmp(aggBy, 'day')
    unitId = string(dateLabel);
    sessionNo = NaN;
else
    unitId = string(dateLabel) + "_session" + string(sessionNo);
end
nTrialsUnit = numel(unique(trialMeans.trial));
T = table(repmat(string(animal), 4, 1), ...
    repmat(string(dateLabel), 4, 1), states, ...
    repmat(string(aggBy), 4, 1), repmat(unitId, 4, 1), ...
    repmat(sessionNo, 4, 1), repmat(nTrialsDay, 4, 1), ...
    repmat(nTrialsUnit, 4, 1), zeros(4,1), zeros(4,1), nan(4,1), ...
    'VariableNames', {'animal','date','state','aggregationUnit','unitId', ...
    'sessionInDay','nTrialsDay','nTrialsUnit', ...
    'nStateTrials','nSamples','meanPupilZ'});
for index = 1:numel(states)
    selected = trialMeans.state == states(index) & ...
        isfinite(trialMeans.meanPupilZ);
    if ~any(selected)
        continue
    end
    T.nStateTrials(index) = sum(selected);
    T.nSamples(index) = sum(trialMeans.nSamples(selected));
    if strcmp(weighting, 'sample')
        T.meanPupilZ(index) = localPooledMoments( ...
            trialMeans.meanPupilZ(selected), trialMeans.sdPupilZ(selected), ...
            trialMeans.nSamples(selected));
    else
        T.meanPupilZ(index) = mean(trialMeans.meanPupilZ(selected), 'omitnan');
    end
end
end


function T = localUnitComparisons(unitState)
pairs = ["tracking", "nonTracking"; "closer", "farther"];
names = ["tracking_minus_nonTracking"; "closer_minus_farther"];
rows = repmat(localEmptyDayComparison(), 2, 1);
for index = 1:2
    first = unitState(unitState.state == pairs(index,1), :);
    second = unitState(unitState.state == pairs(index,2), :);
    row = localEmptyDayComparison();
    row.animal = unitState.animal(1);
    row.date = unitState.date(1);
    row.aggregationUnit = unitState.aggregationUnit(1);
    row.unitId = unitState.unitId(1);
    row.sessionInDay = unitState.sessionInDay(1);
    row.comparison = names(index);
    row.firstState = pairs(index,1);
    row.secondState = pairs(index,2);
    row.firstMeanPupilZ = first.meanPupilZ;
    row.secondMeanPupilZ = second.meanPupilZ;
    row.differencePupilZ = first.meanPupilZ - second.meanPupilZ;
    row.firstNSamples = first.nSamples;
    row.secondNSamples = second.nSamples;
    rows(index) = row;
end
T = struct2table(rows);
end


function grand = localGrandStateMeans(dayState, trialMeans, type, weighting)
states = ["nonTracking"; "tracking"; "closer"; "farther"];
rows = repmat(localEmptyGrandState(), numel(states), 1);
for index = 1:numel(states)
    state = states(index);
    units = dayState(dayState.state == state & isfinite(dayState.meanPupilZ), :);
    row = localEmptyGrandState();
    row.state = state;
    row.nUnits = height(units);
    row.nDays = numel(unique(units.date));
    row.nSessions = nnz(isfinite(units.sessionInDay));
    row.nTrials = sum(units.nStateTrials);
    row.nSamples = sum(units.nSamples);
    if strcmp(type, 'dayMean')
        values = units.meanPupilZ;
        [row.meanPupilZ, row.sdPupilZ, row.semPupilZ, ci] = ...
            localMeanStats(values);
        row.ciLower = ci(1); row.ciUpper = ci(2);
    elseif ~isempty(trialMeans)
        selected = trialMeans.state == state;
        if strcmp(weighting, 'sample')
            [row.meanPupilZ, row.sdPupilZ] = localPooledMoments( ...
                trialMeans.meanPupilZ(selected), trialMeans.sdPupilZ(selected), ...
                trialMeans.nSamples(selected));
            row.semPupilZ = row.sdPupilZ / sqrt(max(row.nSamples, 1));
        else
            values = trialMeans.meanPupilZ(selected);
            [row.meanPupilZ, row.sdPupilZ, row.semPupilZ, ci] = ...
                localMeanStats(values);
            row.ciLower = ci(1); row.ciUpper = ci(2);
        end
        if ~isfinite(row.ciLower)
            row.ciLower = row.meanPupilZ - 1.96 * row.semPupilZ;
            row.ciUpper = row.meanPupilZ + 1.96 * row.semPupilZ;
        end
    end
    rows(index) = row;
end
grand = struct2table(rows);
end


function comparisons = localGrandComparisons(dayComparisons)
names = ["tracking_minus_nonTracking"; "closer_minus_farther"];
rows = repmat(localEmptyComparison(), 2, 1);
for index = 1:2
    selected = dayComparisons.comparison == names(index) & ...
        isfinite(dayComparisons.differencePupilZ);
    values = dayComparisons.differencePupilZ(selected);
    row = localEmptyComparison();
    row.comparison = names(index);
    row.nUnits = numel(values);
    row.nDays = numel(unique(dayComparisons.date(selected)));
    row.nSessions = nnz(isfinite(dayComparisons.sessionInDay(selected)));
    [row.meanDifferencePupilZ, row.sdDifferencePupilZ, ...
        row.semDifferencePupilZ, ci, row.tStatistic, ...
        row.degreesFreedom, row.pValue] = localMeanStats(values);
    row.ciLower = ci(1); row.ciUpper = ci(2);
    row.reject05 = isfinite(row.pValue) && row.pValue < .05;
    rows(index) = row;
end
comparisons = struct2table(rows);
end


function [average, sd, sem, ci, tStatistic, df, pValue] = localMeanStats(values)
values = double(values(:));
values = values(isfinite(values));
n = numel(values);
average = mean(values, 'omitnan');
sd = std(values, 0, 'omitnan');
sem = sd / sqrt(max(n, 1));
ci = [NaN NaN]; tStatistic = NaN; df = n - 1; pValue = NaN;
if n < 2
    return
elseif sem == 0
    tStatistic = sign(average) * Inf;
    if average == 0
        tStatistic = 0; pValue = 1;
    else
        pValue = 0;
    end
    ci = [average average];
    return
end
tStatistic = average / sem;
x = df / (df + tStatistic^2);
pValue = betainc(x, df / 2, .5);
xCritical = betaincinv(.05, df / 2, .5);
tCritical = sqrt(df * (1 - xCritical) / xCritical);
ci = average + [-1 1] * tCritical * sem;
end


function [average, sd] = localPooledMoments(means, sds, counts)
means = double(means(:)); sds = double(sds(:)); counts = double(counts(:));
valid = isfinite(means) & isfinite(counts) & counts > 0;
means = means(valid); sds = sds(valid); counts = counts(valid);
total = sum(counts);
if total == 0
    average = NaN; sd = NaN; return
end
average = sum(counts .* means) / total;
if total < 2
    sd = NaN; return
end
sds(~isfinite(sds)) = 0;
sumSquares = sum((counts - 1) .* sds.^2 + ...
    counts .* (means - average).^2);
sd = sqrt(max(0, sumSquares / (total - 1)));
end


function figureHandle = localPlot(dayState, grand, comparisons, ...
        animal, rangeStart, rangeStop, opts)
figureHandle = figure('Color', 'w', 'Name', 'Pupil size by HMM state across units', ...
    'Position', [100 100 1080 520]);
tiled = tiledlayout(figureHandle, 1, 2, ...
    'TileSpacing', 'compact', 'Padding', 'compact');
localPlotPair(nexttile(tiled), dayState, grand, comparisons(1,:), ...
    ["nonTracking", "tracking"], ["Non-tracking", "Tracking"], ...
    [0.45 0.45 0.45; 0.15 0.55 0.75], 'Tracking state');
localPlotPair(nexttile(tiled), dayState, grand, comparisons(2,:), ...
    ["farther", "closer"], ["Farther", "Closer"], ...
    [0.75 0.42 0.18; 0.25 0.60 0.30], 'Tracked target');
title(tiled, sprintf('%s, %s to %s; %s; aggBy=%s; within-unit %s weighted', ...
    animal, string(rangeStart, 'yyyy.MM.dd'), ...
    string(rangeStop, 'yyyy.MM.dd'), opts.type, opts.aggBy, ...
    opts.withinDayWeight), ...
    'Interpreter', 'none');
end


function localPlotPair(axisHandle, dayState, grand, comparison, ...
        states, labels, colors, panelTitle)
hold(axisHandle, 'on');
units = unique(dayState.unitId, 'stable');
for index = 1:numel(units)
    first = dayState(dayState.unitId == units(index) & ...
        dayState.state == states(1), :);
    second = dayState(dayState.unitId == units(index) & ...
        dayState.state == states(2), :);
    if isempty(first) || isempty(second) || ...
            ~isfinite(first.meanPupilZ) || ~isfinite(second.meanPupilZ)
        continue
    end
    plot(axisHandle, [1 2], [first.meanPupilZ second.meanPupilZ], '-o', ...
        'Color', [.78 .78 .78], 'MarkerFaceColor', [.78 .78 .78], ...
        'MarkerEdgeColor', 'none', 'LineWidth', .8, 'MarkerSize', 4, ...
        'HandleVisibility', 'off');
end
for index = 1:2
    selected = grand.state == states(index);
    average = grand.meanPupilZ(selected);
    lower = grand.ciLower(selected);
    upper = grand.ciUpper(selected);
    if isfinite(average)
        errorbar(axisHandle, index, average, average-lower, upper-average, ...
            'o', 'Color', colors(index,:), ...
            'MarkerFaceColor', colors(index,:), 'MarkerSize', 9, ...
            'LineWidth', 2.2, 'CapSize', 14, ...
            'DisplayName', sprintf('%s (%s=%d)', labels(index), ...
            dayState.aggregationUnit(1), grand.nUnits(selected)));
    end
end
xlim(axisHandle, [.65 2.35]); xticks(axisHandle, 1:2);
xticklabels(axisHandle, labels);
yline(axisHandle, 0, 'Color', [.65 .65 .65], 'HandleVisibility', 'off');
ylabel(axisHandle, 'Mean pupil size (session-eye SD)');
title(axisHandle, sprintf(['%s: paired %s difference = %+.3f SD\n' ...
    '95%% CI [%+.3f, %+.3f], p=%.3g, n=%d'], ...
    panelTitle, dayState.aggregationUnit(1), ...
    comparison.meanDifferencePupilZ, comparison.ciLower, ...
    comparison.ciUpper, comparison.pValue, comparison.nUnits));
grid(axisHandle, 'on'); pbaspect(axisHandle, [1 1 1]);
legend(axisHandle, 'Location', 'best');
end


function [folder, expression] = localModelSpec(model)
if strcmp(model, 'sm3')
    folder = 'tidSM3';
    expression = ['^(kaki|lychee)_(\d{4}\.\d{2}\.\d{2})_' ...
        'targetidsens3_distance_gated_random_effect_cv' ...
        '(?:_v\d+)?_predictions\.csv$'];
else
    error('pupilHmmStateMeansDays:BadModel', 'Unsupported model %s.', model);
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
    row = struct('animal', string(token{1}), 'date', string(token{2}), ...
        'dateValue', datetime(token{2}, 'InputFormat', 'yyyy.MM.dd'), ...
        'predictionFile', string(fullfile(files(index).folder, files(index).name)), ...
        'modified', datetime(files(index).datenum, 'ConvertFrom', 'datenum'));
    rows(end+1, 1) = row; %#ok<AGROW>
end
if isempty(rows)
    jobs = table(); return
end
jobs = struct2table(rows);
jobs = sortrows(jobs, {'dateValue','modified'}, {'ascend','descend'});
[~, keep] = unique(jobs.date, 'stable');
jobs = jobs(sort(keep), :);
end


function [rangeStart, rangeStop] = localDateRange(fromValue, toValue, dates)
defaultYear = year(max(dates));
if isempty(fromValue)
    rangeStart = min(dates);
else
    rangeStart = localParseDate(fromValue, defaultYear);
end
if isempty(toValue)
    rangeStop = max(dates);
else
    rangeStop = localParseDate(toValue, defaultYear);
end
if rangeStop < rangeStart && localIsShortDate(fromValue) && localIsShortDate(toValue)
    rangeStop = datetime(year(rangeStart) + 1, month(rangeStop), day(rangeStop));
end
if rangeStop < rangeStart
    error('pupilHmmStateMeansDays:BadDateRange', ...
        'dateTo must be on or after dateFrom.');
end
end


function parsed = localParseDate(value, defaultYear)
if isdatetime(value)
    parsed = datetime(year(value), month(value), day(value)); return
end
text = strtrim(char(string(value)));
try
    parsed = datetime(regexprep(text, '[-_]', '.'), ...
        'InputFormat', 'yyyy.MM.dd'); return
catch
end
token = regexp(lower(text), ...
    ['^(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|' ...
     'jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|' ...
     'nov(?:ember)?|dec(?:ember)?)\s*([0-9]{1,2})$'], ...
    'tokens', 'once');
if isempty(token)
    error('pupilHmmStateMeansDays:BadDate', ...
        'Use YYYY.MM.DD or a date such as jun02, June2, or july12.');
end
months = {'jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'};
monthNo = find(strcmp(token{1}(1:3), months), 1);
parsed = datetime(defaultYear, monthNo, str2double(token{2}));
end


function tf = localIsShortDate(value)
if isempty(value) || isdatetime(value)
    tf = false;
else
    tf = isempty(regexp(strtrim(char(string(value))), '^\d{4}[-._]', 'once'));
end
end


function animal = localAnimal(value)
switch lower(strtrim(char(string(value))))
    case {'ka','kaki'}
        animal = 'kaki';
    case {'ly','lychee'}
        animal = 'lychee';
    otherwise
        error('pupilHmmStateMeansDays:BadAnimal', ...
            'Use ka/kaki or ly/lychee.');
end
end


function row = localEmptyAudit()
row = struct('animal', "", 'date', "", 'status', "", ...
    'nBlocks', 0, 'nTrials', 0, 'nTrialsWithHmm', 0, ...
    'nUnitsIncluded', 0, 'nUnitsBelowMinTrials', 0, ...
    'nStateTrialRows', 0, 'predictionFile', "", ...
    'elapsedSec', NaN, 'message', "");
end


function row = localEmptyDayComparison()
row = struct('animal', "", 'date', "", 'aggregationUnit', "", ...
    'unitId', "", 'sessionInDay', NaN, 'comparison', "", ...
    'firstState', "", 'secondState', "", ...
    'firstMeanPupilZ', NaN, 'secondMeanPupilZ', NaN, ...
    'differencePupilZ', NaN, 'firstNSamples', 0, 'secondNSamples', 0);
end


function row = localEmptyGrandState()
row = struct('state', "", 'nUnits', 0, 'nDays', 0, 'nSessions', 0, ...
    'nTrials', 0, 'nSamples', 0, ...
    'meanPupilZ', NaN, 'sdPupilZ', NaN, 'semPupilZ', NaN, ...
    'ciLower', NaN, 'ciUpper', NaN);
end


function row = localEmptyComparison()
row = struct('comparison', "", 'nUnits', 0, 'nDays', 0, 'nSessions', 0, ...
    'meanDifferencePupilZ', NaN, 'sdDifferencePupilZ', NaN, ...
    'semDifferencePupilZ', NaN, 'ciLower', NaN, 'ciUpper', NaN, ...
    'tStatistic', NaN, 'degreesFreedom', NaN, 'pValue', NaN, ...
    'reject05', false);
end
