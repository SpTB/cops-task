function total_nreps = getCoPsTotalRepsx(ex)
% Return total trials for a CoPs run.
% Special trial blocks run first, followed by main-task trials.

total_nreps = ex.exp.nreps;

if ~isfield(ex, 'exp') || ~isfield(ex.exp, 'CoPs')
    return
end

blockInfo = getCoPsTrialBlockInfox(ex);
total_nreps = blockInfo.totalN;
end
