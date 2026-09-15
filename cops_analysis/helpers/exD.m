function diffs = exD(varargin)
% exD Compare ex.exp.CoPs settings across two or more ex structs.
%
% Two-session usage (backward-compatible):
%   diffs = exD(exA, exB)
%
% Multi-session usage:
%   diffs = exD(ex1, ex2, ex3, ...)
%   diffs = exD({ex1, ex2, ex3}, 'Reference', 1, 'SessionNames', {'s1','s2','s3'})
%
% Name-value options:
%   'Reference'    : Index of session used as comparison baseline (default: 1)
%   'SessionNames' : Cellstr names for sessions (default: {'session_1', ...})
%
% Output fields:
%   pairwise.changed/added/removed : same schema as historical exD(exA, exB)
%                                    (reference vs second session when N>1)
%   referenceIndex                 : baseline session index
%   sessionNames                   : resolved session names
%   bySession(k)                   : per-session comparison to reference
%       .index, .name
%       .changed/.added/.removed
%       .isMatch
%   allMatchReference              : true if every compared session matches reference

    [exList, args] = normalizeExInputs(varargin{:});

    p = inputParser;
    p.FunctionName = 'exD';
    addParameter(p, 'Reference', 1, @(x) validateattributes(x, {'numeric'}, {'scalar', 'integer', '>=', 1}));
    addParameter(p, 'SessionNames', {}, @(x) iscellstr(x) || isstring(x)); %#ok<ISCLSTR>
    parse(p, args{:});

    n = numel(exList);
    refIdx = p.Results.Reference;
    if refIdx > n
        error('exD:ReferenceOutOfRange', 'Reference index (%d) exceeds number of sessions (%d).', refIdx, n);
    end

    names = resolveSessionNames(p.Results.SessionNames, n);

    diffs = struct();
    diffs.referenceIndex = refIdx;
    diffs.sessionNames = names;

    % Keep legacy field names for drop-in compatibility.
    if n >= 2
        legacyAgainst = 2;
        if refIdx == 2
            legacyAgainst = 1;
        end
        legacy = compareTwoEx(exList{refIdx}, exList{legacyAgainst});
        diffs.changed = legacy.changed;
        diffs.added = legacy.added;
        diffs.removed = legacy.removed;
    else
        diffs.changed = emptyChanged();
        diffs.added = emptySingleValue();
        diffs.removed = emptySingleValue();
    end

    bySession = repmat(struct( ...
        'index', 0, ...
        'name', '', ...
        'changed', emptyChanged(), ...
        'added', emptySingleValue(), ...
        'removed', emptySingleValue(), ...
        'isMatch', true), 1, n);

    allMatch = true;
    for i = 1:n
        bySession(i).index = i;
        bySession(i).name = names{i};

        if i == refIdx
            continue;
        end

        one = compareTwoEx(exList{refIdx}, exList{i});
        bySession(i).changed = one.changed;
        bySession(i).added = one.added;
        bySession(i).removed = one.removed;
        bySession(i).isMatch = isempty(one.changed) && isempty(one.added) && isempty(one.removed);
        allMatch = allMatch && bySession(i).isMatch;
    end

    diffs.bySession = bySession;
    diffs.allMatchReference = allMatch;
    diffs.comparedSessionIndices = setdiff(1:n, refIdx);
end

function out = compareTwoEx(exA, exB)
    copsA = getCoPs(exA);
    copsB = getCoPs(exB);

    out = struct( ...
        'changed', emptyChanged(), ...
        'added', emptySingleValue(), ...
        'removed', emptySingleValue());

    out = compareNode(copsA, copsB, 'ex.exp.CoPs', out);
end

function diffs = compareNode(a, b, path, diffs)
    if isstruct(a) && isstruct(b)
        fieldsA = fieldnames(a);
        fieldsB = fieldnames(b);

        commonFields = intersect(fieldsA, fieldsB);
        addedFields = setdiff(fieldsB, fieldsA);
        removedFields = setdiff(fieldsA, fieldsB);

        for i = 1:numel(commonFields)
            f = commonFields{i};
            childPath = [path, '.', f];
            diffs = compareNode(a.(f), b.(f), childPath, diffs);
        end

        for i = 1:numel(addedFields)
            f = addedFields{i};
            childPath = [path, '.', f];
            diffs.added(end+1) = struct('variable', childPath, 'value', {b.(f)}); %#ok<AGROW>
        end

         for i = 1:numel(removedFields)
            f = removedFields{i};
            childPath = [path, '.', f];
            diffs.removed(end+1) = struct('variable', childPath, 'value', {a.(f)}); %#ok<AGROW>
        end

    else
        if ~isequaln(a, b)
            diffs.changed(end+1) = struct('variable', path, 'valueA', {a}, 'valueB', {b}); %#ok<AGROW>
        end
    end
end

function cops = getCoPs(ex)
    cops = struct();

    if isstruct(ex) && isfield(ex, 'exp') && isstruct(ex.exp) && isfield(ex.exp, 'CoPs')
        cops = ex.exp.CoPs;
    end
end

function s = emptyChanged()
    s = struct('variable', {}, 'valueA', {}, 'valueB', {});
end

function s = emptySingleValue()
    s = struct('variable', {}, 'value', {});
end

function [exList, remainder] = normalizeExInputs(varargin)
    if nargin < 1
        error('exD:NotEnoughInputs', 'Provide at least one ex struct.');
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
        error('exD:NotEnoughInputs', 'Provide at least one ex struct.');
    end
end

function tf = isNameToken(v)
    tf = ischar(v) && any(strcmpi(v, {'Reference', 'SessionNames'}));
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
        error('exD:InvalidSessionNames', 'SessionNames must contain one name per session (%d expected).', n);
    end

    names = sessionNames(:)';
end
