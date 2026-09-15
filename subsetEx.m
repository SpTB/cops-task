function [exSubset, keepMask] = subsetEx(ex, expr)
% subsetEx  Subset ex.Trials using a trial-wise logical expression.
%
%   ex1 = subsetEx(ex, 'target_num==1')
%   ex2 = subsetEx(ex, 'gauss_scalar>=3')
%   [ex3, keep] = subsetEx(ex, 'target_num==1 & background_noise_lvl==0')
%
% The expression is evaluated once per trial. Trial fields are available by
% name, and common session-level CoPs parameters are also exposed as
% fallback variables (for example gauss_scalar, coherence, target_num,
% background_noise_lvl). Trial-level values take precedence when both
% exist.

arguments
    ex struct
    expr {mustBeTextScalar}
end

if ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('subsetEx:NoTrials', 'Input ex has no trials in ex.Trials.');
end

expr = char(string(expr));
nTr = numel(ex.Trials);
keepMask = false(nTr, 1);
sessionCtx = iBuildSessionContext(ex);

for j = 1:nTr
    trialCtx = iBuildTrialContext(ex.Trials(j), sessionCtx, j);
    keepMask(j) = iEvalExpression(expr, trialCtx, j);
end

exSubset = ex;
exSubset.Trials = ex.Trials(keepMask);
if isfield(exSubset, 'subset') && ~isstruct(exSubset.subset)
    exSubset = rmfield(exSubset, 'subset');
end
exSubset.subset = struct();
exSubset.subset.expression = string(expr);
exSubset.subset.keepMask = keepMask;
exSubset.subset.originalTrialIdx = find(keepMask);
end


function ctx = iBuildTrialContext(T, sessionCtx, trialIdx)
ctx = sessionCtx;
ctx.trial = double(trialIdx);

trialFields = fieldnames(T);
for k = 1:numel(trialFields)
    name = trialFields{k};
    if ~isvarname(name)
        continue
    end
    value = T.(name);
    if iIsSupportedValue(value)
        ctx.(name) = iNormalizeValue(value);
    end
end
end


function ctx = iBuildSessionContext(ex)
ctx = struct();

ctx.gauss_scalar = iGetFirstScalar(ex, { ...
    {'exp', 'CoPs', 'ctl', 'gauss_scalar'}, ...
    {'exp', 'CoPs', 'ctl', 'precision_weight'}});
ctx.gauss_center_idx = iGetScalar(ex, {'exp', 'CoPs', 'rew', 'gauss_center_idx'});
ctx.target_num = iGetScalar(ex, {'exp', 'CoPs', 'ctl', 'target_num'});
ctx.coherence = iGetScalar(ex, {'exp', 'CoPs', 'ctl', 'coherence'});
ctx.target_visibility = iGetScalar(ex, {'exp', 'CoPs', 'graph', 'target_visibility'});
ctx.background_noise_lvl = iGetScalar(ex, {'exp', 'CoPs', 'graph', 'background_noise_lvl'});
ctx.step_size_mult = iGetScalar(ex, {'exp', 'CoPs', 'ctl', 'step_size_mult'});
ctx.nsteps = iGetScalar(ex, {'exp', 'CoPs', 'ctl', 'nsteps'});
[ctx.wait_secs, ctx.waitHz] = resolveCoPsWaitSecs(ex, NaN);
ctx.gauss_sigma = iGetScalar(ex, {'exp', 'CoPs', 'rew', 'gauss_sigma'});
ctx.reward_threshold = iGetScalar(ex, {'exp', 'CoPs', 'rew', 'threshold'});
ctx.reward_duration = iGetScalar(ex, {'exp', 'CoPs', 'rew', 'duration'});
ctx.max_dist_mult = iGetScalar(ex, {'exp', 'CoPs', 'ctl', 'max_dist_mult'});
ctx.freeViewing = iGetScalar(ex, {'exp', 'CoPs', 'freeViewing'});
end


function tf = iEvalExpression(expr, ctx, trialIdx)
names = fieldnames(ctx);
for k = 1:numel(names)
    eval([names{k} ' = ctx.(names{k});']); %#ok<EVLDIR>
end

try
    out = eval(expr); %#ok<EVLDIR>
catch ME
    error('subsetEx:EvalFailed', ...
        'Failed to evaluate expression on trial %d: %s', trialIdx, ME.message);
end

if islogical(out) && isscalar(out)
    tf = out;
elseif isnumeric(out) && isscalar(out) && isfinite(out)
    tf = logical(out);
else
    error('subsetEx:NonScalarResult', ...
        'Expression must evaluate to a scalar logical/numeric per trial; trial %d returned %s.', ...
        trialIdx, class(out));
end
end


function tf = iIsSupportedValue(value)
tf = false;
if isempty(value)
    return
end
if isnumeric(value) || islogical(value)
    tf = isscalar(value) && isfinite(double(value));
elseif ischar(value)
    tf = isrow(value);
elseif isstring(value)
    tf = isscalar(value);
end
end


function value = iNormalizeValue(valueIn)
if isnumeric(valueIn) || islogical(valueIn)
    value = double(valueIn);
elseif isstring(valueIn)
    value = valueIn;
else
    value = valueIn;
end
end


function value = iGetFirstScalar(s, pathList)
value = NaN;
for k = 1:numel(pathList)
    value = iGetScalar(s, pathList{k});
    if isfinite(value)
        return
    end
end
end


function value = iGetScalar(s, fields)
value = NaN;
for k = 1:numel(fields)
    if ~isstruct(s) || ~isfield(s, fields{k})
        return
    end
    s = s.(fields{k});
end
if (isnumeric(s) || islogical(s)) && isscalar(s) && isfinite(double(s))
    value = double(s);
end
end
