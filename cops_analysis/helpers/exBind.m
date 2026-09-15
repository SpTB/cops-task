function exOut = exBind(varargin)
% exBind Combine two or more ex structs for CoPs workflows.
%
% Backward-compatible two-session usage:
%   exAB = exBind(exA, exB)
%
% Multi-session usage:
%   exOut = exBind(ex1, ex2, ex3, ...)
%   exOut = exBind({ex1, ex2, ex3}, 'Include', [1 3])
%
% Name-value options:
%   'Include'             : Session indices/logical mask to include (default: all)
%   'Exclude'             : Session indices/logical mask to exclude (default: none)
%   'Reference'           : Baseline session index for CoPs settings (default: first included)
%   'RequireMatchingCoPs' : If true, only sessions identical to reference are allowed.
%                           (default: false)
%   'AutoExcludeMismatched': If true and RequireMatchingCoPs is true, mismatched sessions
%                            are auto-removed instead of throwing an error. (default: true)
%   'SessionNames'        : Optional names for reporting.
%
% Output:
%   exOut.Trials           : Concatenated trials from kept sessions
%   exOut.exp.CoPs         : CoPs settings copied from the reference session
%   exOut.exp.CoPsDiffs    : exD comparison output across all input sessions
%   exOut.exp.CoPsBindReport: Inclusion/exclusion bookkeeping and mismatch reasons

    [exList, args] = normalizeExInputs(varargin{:});
    n = numel(exList);

    p = inputParser;
    p.FunctionName = 'exBind';
    addParameter(p, 'Include', 1:n, @(x) isnumeric(x) || islogical(x));
    addParameter(p, 'Exclude', [], @(x) isnumeric(x) || islogical(x));
    addParameter(p, 'Reference', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1 && mod(x,1)==0));
    addParameter(p, 'RequireMatchingCoPs', false, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'AutoExcludeMismatched', true, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'SessionNames', {}, @(x) iscellstr(x) || ischar(x)); %#ok<ISCLSTR>
    parse(p, args{:});

    names = resolveSessionNames(p.Results.SessionNames, n);

    includeIdx = normalizeIndexSpec(p.Results.Include, n, 'Include');
    excludeIdx = normalizeIndexSpec(p.Results.Exclude, n, 'Exclude');

    keepMask = false(1, n);
    keepMask(includeIdx) = true;
    keepMask(excludeIdx) = false;

    if ~any(keepMask)
        error('exBind:NoSessionsSelected', 'No sessions selected after applying Include/Exclude.');
    end

    keepIdx = find(keepMask);

    refIdx = p.Results.Reference;
    if isempty(refIdx)
        refIdx = keepIdx(1);
    end
    if refIdx < 1 || refIdx > n
        error('exBind:ReferenceOutOfRange', 'Reference index (%d) exceeds number of sessions (%d).', refIdx, n);
    end
    if ~keepMask(refIdx)
        error('exBind:ReferenceExcluded', 'Reference session (%d) is excluded by Include/Exclude filters.', refIdx);
    end

    diffsAll = exD(exList, 'Reference', refIdx, 'SessionNames', names);

    excludedDueToMismatch = [];
    mismatchDetails = struct('index', {}, 'name', {}, 'changedCount', {}, 'addedCount', {}, 'removedCount', {});

    if p.Results.RequireMatchingCoPs
        for i = keepIdx
            if i == refIdx
                continue;
            end

            d = diffsAll.bySession(i);
            isMatch = d.isMatch;
            if ~isMatch
                if p.Results.AutoExcludeMismatched
                    keepMask(i) = false;
                    excludedDueToMismatch(end+1) = i; %#ok<AGROW>
                    mismatchDetails(end+1) = summarizeMismatch(d); %#ok<AGROW>
                else
                    error('exBind:CoPsMismatch', ...
                        'Session %d (%s) differs from reference CoPs settings. Set AutoExcludeMismatched=true to auto-drop it.', ...
                        i, names{i});
                end
            end
        end
    end

    keepIdx = find(keepMask);
    if ~any(keepMask)
        error('exBind:NoSessionsAfterMatchFilter', ...
            'All selected sessions were excluded after CoPs matching filter.');
    end

    exOut = exList{refIdx};
    trialCells = cell(1, numel(keepIdx));
    for i = 1:numel(keepIdx)
        trialCells{i} = getTrialsOrEmpty(exList{keepIdx(i)});
    end
    trialCells = harmonizeTrialCells(trialCells);
    exOut.Trials = vertcat(trialCells{:});

    if ~isfield(exOut, 'exp') || ~isstruct(exOut.exp)
        exOut.exp = struct();
    end
    if isfield(exList{refIdx}, 'exp') && isstruct(exList{refIdx}.exp) && isfield(exList{refIdx}.exp, 'CoPs')
        exOut.exp.CoPs = exList{refIdx}.exp.CoPs;
    end

    exOut.exp.CoPsDiffs = diffsAll;
    exOut.exp.CoPsBindReport = struct( ...
        'sessionNames', {names}, ...
        'referenceIndex', refIdx, ...
        'includedIndices', keepIdx, ...
        'excludedByUserIndices', setdiff(1:n, includeIdx), ...
        'excludedByExcludeIndices', intersect(includeIdx, excludeIdx), ...
        'excludedByMismatchIndices', excludedDueToMismatch, ...
        'mismatchDetails', mismatchDetails, ...
        'requireMatchingCoPs', p.Results.RequireMatchingCoPs, ...
        'autoExcludeMismatched', p.Results.AutoExcludeMismatched);
end

function m = summarizeMismatch(d)
    m = struct( ...
        'index', d.index, ...
        'name', d.name, ...
        'changedCount', numel(d.changed), ...
        'addedCount', numel(d.added), ...
        'removedCount', numel(d.removed));
end

function trials = getTrialsOrEmpty(ex)
    trials = [];

    if isstruct(ex) && isfield(ex, 'Trials') && ~isempty(ex.Trials)
        trials = ex.Trials(:);
    end
end

function trialCells = harmonizeTrialCells(trialCells)
    if isempty(trialCells)
        return
    end

    nonEmpty = ~cellfun(@isempty, trialCells);
    if ~any(nonEmpty)
        return
    end

    allFields = {};
    refByField = struct();
    for i = find(nonEmpty)
        fields = fieldnames(trialCells{i});
        for j = 1:numel(fields)
            field = fields{j};
            if ~ismember(field, allFields)
                allFields{end+1} = field; %#ok<AGROW>
                refByField.(field) = trialCells{i}(1).(field);
            end
        end
    end

    for i = find(nonEmpty)
        fields = fieldnames(trialCells{i});
        missing = setdiff(allFields, fields);
        for j = 1:numel(missing)
            field = missing{j};
            defaultValue = getDefaultLike(refByField.(field));
            [trialCells{i}.(field)] = deal(defaultValue);
        end
    end
end

function value = getDefaultLike(exemplar)
    if isstring(exemplar)
        value = "";
    elseif ischar(exemplar)
        value = '';
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

function [exList, remainder] = normalizeExInputs(varargin)
    if nargin < 1
        error('exBind:NotEnoughInputs', 'Provide at least one ex struct.');
    end

    if iscell(varargin{1})
        exList = varargin{1};
        remainder = varargin(2:end);
    else
        firstNv = find(cellfun(@isNameToken, varargin), 1, 'first');
        if isempty(firstNv)
            exList = varargin;
            remainder = {};
        else
            exList = varargin(1:firstNv-1);
            remainder = varargin(firstNv:end);
        end
    end

    if numel(exList) < 1
        error('exBind:NotEnoughInputs', 'Provide at least one ex struct.');
    end
end

function tf = isNameToken(v)
    tf = ischar(v) && any(strcmpi(v, ...
        {'Include', 'Exclude', 'Reference', 'RequireMatchingCoPs', 'AutoExcludeMismatched', 'SessionNames'}));
end

function idx = normalizeIndexSpec(spec, n, label)
    if isempty(spec)
        idx = [];
        return;
    end

    if islogical(spec)
        if numel(spec) ~= n
            error('exBind:Invalid%sMask', label, '%s logical mask must have %d elements.', label, n);
        end
        idx = find(spec);
    else
        idx = unique(spec(:)');
        if any(~isfinite(idx)) || any(idx < 1) || any(idx > n) || any(mod(idx,1) ~= 0)
            error('exBind:Invalid%sIndices', label, '%s indices must be integers in [1, %d].', label, n);
        end
    end
end

function names = resolveSessionNames(sessionNames, n)
    if isempty(sessionNames)
        names = arrayfun(@(k) sprintf('session_%d', k), 1:n, 'UniformOutput', false);
        return;
    end

    if ischar(sessionNames)
        sessionNames = {sessionNames};
    end

    if ~iscellstr(sessionNames) || numel(sessionNames) ~= n %#ok<ISCLSTR>
        error('exBind:InvalidSessionNames', 'SessionNames must contain one name per session (%d expected).', n);
    end

    names = sessionNames(:)';
end
