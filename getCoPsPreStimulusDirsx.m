function stimDirs = getCoPsPreStimulusDirsx(ex)
% Return the sequential preblock stimulus folders requested by pre.nreps.

stimDirs = {};
if ~isfield(ex, 'exp') || ~isfield(ex.exp, 'CoPs')
    return
end

[rawNreps, hasPreNreps, legacyCycles] = localPreNrepsRaw(ex);
if ~hasPreNreps
    return
end
if isempty(rawNreps) || (isnumeric(rawNreps) && all(double(rawNreps(:)) <= 0)) || ...
        (islogical(rawNreps) && ~any(rawNreps(:)))
    return
end

if ~isfield(ex.exp.CoPs, 'dirs') || ~isfield(ex.exp.CoPs.dirs, 'all')
    error('getCoPsPreStimulusDirsx:MissingStimulusRoot', ...
        'ex.exp.CoPs.dirs.all is required when pre.nreps is nonzero.');
end

graph = ex.exp.CoPs.graph;
if isfield(graph, 'imgs')
    allowedImgs = graph.imgs;
else
    allowedImgs = [];
end

baseDirs = resolveCoPsStimulusDirs(ex.exp.CoPs.dirs.all, 1, allowedImgs, true);
nPre = localResolvePreNreps(rawNreps, numel(baseDirs), legacyCycles);
if nPre <= 0
    return
end

idx = mod(0:(nPre - 1), numel(baseDirs)) + 1;
stimDirs = baseDirs(idx);
end


function [value, hasValue, legacyCycles] = localPreNrepsRaw(ex)
value = [];
hasValue = false;
legacyCycles = false;
if isfield(ex.exp.CoPs, 'pre') && isstruct(ex.exp.CoPs.pre) && ...
        isfield(ex.exp.CoPs.pre, 'nreps') && ~isempty(ex.exp.CoPs.pre.nreps)
    value = ex.exp.CoPs.pre.nreps;
    hasValue = true;
    return
end

% Legacy fallback: older configs used ctl.pre as cycles through all images.
if isfield(ex.exp.CoPs, 'ctl') && isfield(ex.exp.CoPs.ctl, 'pre') && ...
        ~isempty(ex.exp.CoPs.ctl.pre)
    value = ex.exp.CoPs.ctl.pre;
    hasValue = true;
    legacyCycles = true;
end
end


function nPre = localResolvePreNreps(value, nBaseDirs, legacyCycles)
if legacyCycles
    nCycles = round(double(value(1)));
    if isfinite(nCycles) && nCycles > 0
        nPre = nCycles * nBaseDirs;
    else
        nPre = 0;
    end
    return
end
nPre = localPreNrepsValue(value, nBaseDirs);
end


function nPre = localPreNrepsValue(value, nBaseDirs)
if ischar(value) || (isstring(value) && isscalar(value))
    text = lower(strtrim(char(value)));
    if strcmp(text, 'all')
        nPre = nBaseDirs;
        return
    end
    nPre = str2double(text);
else
    nPre = double(value(1));
end
nPre = round(nPre);
if ~isfinite(nPre) || nPre < 0
    nPre = 0;
end
end
