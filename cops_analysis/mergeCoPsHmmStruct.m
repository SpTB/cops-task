function [ex, report] = mergeCoPsHmmStruct(ex, hmmInput, varargin)
% mergeCoPsHmmStruct  Attach step-aligned HMM predictions to ex.Trials.
%
%   ex = mergeCoPsHmmStruct(ex, hmm)
%   ex = mergeCoPsHmmStruct(ex, 'session_hmm_predictions.mat')
%   [ex, report] = mergeCoPsHmmStruct(...)
%   ex = mergeCoPsHmmStruct('ka', 'Jul19')
%   ex = mergeCoPsHmmStruct('ka', 'Jul19', opts)
%
% The monkey/date overload loads and binds all raw blocks represented in a
% saved day-level prediction CSV. opts.model is 'sm3' (default), 'sm', or
% 'tid'. It accepts the same path-selection fields as exportHMM, including
% opts.dataRoot, opts.hmmRoot, opts.predictionFile, and opts.block. It does
% not run processCoPsEye or write a CSV. opts.block defaults to 'all'; use
% opts.block=1 (or a vector such as [1 3]) to select specific blocks.
%
% The sidecar is produced by TwoTargetIndependentFit.ipynb. For every
% original trial, this creates:
%
%   ex.Trials(k).hmm.predictive.pTLeft
%   ex.Trials(k).hmm.predictive.pTRight
%   ex.Trials(k).hmm.predictive.pNonTracking
%   ex.Trials(k).hmm.predictive.pCloser
%   ex.Trials(k).hmm.predictive.hardTLeft
%   ex.Trials(k).hmm.predictive.hardCloser
%
% and the same four fields under .filtered and .smoothed. Each vector is
% indexed by the original target step. Missing/unpredicted steps are NaN.
% TLeft means the target leftmost at the first valid trial step; identities
% are retained for the rest of the trial. Fold labels are intentionally not
% stored because every retained value is one out-of-fold prediction.
% Hard-state coding is: NaN=no probability estimate, 0=no target tracked,
% 1=TLeft/closer, and 2=TRight/farther. For two-state models, 0 means that
% neither target exceeded the hard threshold. For SM3, 0 means that the
% non-tracking state had the highest probability (or there was a tie).

if (ischar(ex) || (isstring(ex) && isscalar(ex))) && ...
        (ischar(hmmInput) || (isstring(hmmInput) && isscalar(hmmInput)))
    if isempty(varargin)
        dayOpts = struct();
    elseif numel(varargin) == 1 && isstruct(varargin{1}) && isscalar(varargin{1})
        dayOpts = varargin{1};
    else
        error('mergeCoPsHmmStruct:BadDayOptions', ...
            'The optional third input must be one scalar opts structure.');
    end
    if ~isfield(dayOpts, 'model') || isempty(dayOpts.model)
        dayOpts.model = 'sm3';
    end
    dayOpts.writeOutput = false;
    [blockReport, ex] = exportHMM(ex, hmmInput, dayOpts);
    report = struct( ...
        'mode', 'day', 'model', char(string(dayOpts.model)), ...
        'nBlocks', height(blockReport), 'nTrials', numel(ex.Trials), ...
        'blocks', blockReport);
    return
elseif ~isempty(varargin)
    error('mergeCoPsHmmStruct:UnexpectedInput', ...
        'A third input is supported only for the monkey/date overload.');
end

if ~isstruct(ex) || ~isfield(ex, 'Trials')
    error('mergeCoPsHmmStruct:BadEx', 'ex must contain ex.Trials.');
end
hmm = localLoadHmm(hmmInput);
required = {'trialIdx', 'step', 'predictive', 'filtered', 'smoothed'};
for i = 1:numel(required)
    if ~isfield(hmm, required{i})
        error('mergeCoPsHmmStruct:BadSidecar', ...
            'HMM sidecar is missing field "%s".', required{i});
    end
end

trialIdx = double(hmm.trialIdx(:));
step = double(hmm.step(:));
nRows = numel(trialIdx);
if numel(step) ~= nRows
    error('mergeCoPsHmmStruct:SizeMismatch', ...
        'hmm.trialIdx and hmm.step must have the same number of elements.');
end

methods = {'predictive', 'filtered', 'smoothed'};
fields = {'pTLeft', 'pCloser', 'hardTLeft', 'hardCloser'};
for m = 1:numel(methods)
    method = methods{m};
    for f = 1:numel(fields)
        field = fields{f};
        if ~isfield(hmm.(method), field) || numel(hmm.(method).(field)) ~= nRows
            error('mergeCoPsHmmStruct:SizeMismatch', ...
                'hmm.%s.%s must match hmm.trialIdx in size.', method, field);
        end
    end
end

nTrials = numel(ex.Trials);
report = struct('nTrials', nTrials, 'nTrialsMatched', 0, ...
    'nPredictedSteps', 0, 'nRowsIgnored', 0);
validRow = isfinite(trialIdx) & trialIdx == round(trialIdx) & ...
    trialIdx >= 1 & trialIdx <= nTrials & ...
    isfinite(step) & step == round(step) & step >= 1;
report.nRowsIgnored = sum(~validRow);

for trialNo = 1:nTrials
    rows = find(validRow & trialIdx == trialNo);
    nSteps = localTrialStepCount(ex.Trials(trialNo));
    if ~isempty(rows)
        nSteps = max(nSteps, max(step(rows)));
        report.nTrialsMatched = report.nTrialsMatched + 1;
    end
    trialHmm = struct();
    trialHmm.step = (1:nSteps)';
    trialHmm.tRelSec = nan(nSteps, 1);
    for m = 1:numel(methods)
        method = methods{m};
        trialHmm.(method) = localEmptyMethod(nSteps);
    end

    if ~isempty(rows)
        stepRows = step(rows);
        [uniqueSteps, firstIndex] = unique(stepRows, 'stable');
        rows = rows(firstIndex);
        stepRows = uniqueSteps;
        if isfield(hmm, 'tRelSec') && numel(hmm.tRelSec) == nRows
            tRel = double(hmm.tRelSec(:));
            trialHmm.tRelSec(stepRows) = tRel(rows);
        end
        for m = 1:numel(methods)
            method = methods{m};
            for f = 1:numel(fields)
                field = fields{f};
                values = double(hmm.(method).(field)(:));
                trialHmm.(method).(field)(stepRows) = values(rows);
            end
            optionalFields = {'pTRight', 'pNonTracking'};
            for f = 1:numel(optionalFields)
                field = optionalFields{f};
                if isfield(hmm.(method), field) && ...
                        numel(hmm.(method).(field)) == nRows
                    values = double(hmm.(method).(field)(:));
                    trialHmm.(method).(field)(stepRows) = values(rows);
                end
            end
        end
        report.nPredictedSteps = report.nPredictedSteps + numel(stepRows);
    end
    ex.Trials(trialNo).hmm = trialHmm;
end

if isfield(hmm, 'meta')
    ex.hmmMeta = hmm.meta;
end
ex.hmmMeta.mergeReport = report;
end


function hmm = localLoadHmm(hmmInput)
if ischar(hmmInput) || (isstring(hmmInput) && isscalar(hmmInput))
    loaded = load(char(hmmInput));
    if ~isfield(loaded, 'hmm')
        error('mergeCoPsHmmStruct:MissingVariable', ...
            'The sidecar MAT file must contain a variable named hmm.');
    end
    hmm = loaded.hmm;
elseif isstruct(hmmInput) && isfield(hmmInput, 'hmm') && ...
        ~isfield(hmmInput, 'trialIdx')
    hmm = hmmInput.hmm;
else
    hmm = hmmInput;
end
if ~isstruct(hmm)
    error('mergeCoPsHmmStruct:BadSidecar', 'hmmInput must resolve to a struct.');
end
end


function nSteps = localTrialStepCount(T)
nSteps = 0;
if isfield(T, 'targetPositions') && ~isempty(T.targetPositions)
    nSteps = numel(T.targetPositions);
end
end


function method = localEmptyMethod(nSteps)
method = struct( ...
    'pTLeft', nan(nSteps, 1), ...
    'pTRight', nan(nSteps, 1), ...
    'pNonTracking', nan(nSteps, 1), ...
    'pCloser', nan(nSteps, 1), ...
    'hardTLeft', nan(nSteps, 1), ...
    'hardCloser', nan(nSteps, 1));
end
