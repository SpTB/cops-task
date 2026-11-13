function out = tmpDpPtbDurMismatch(ex)
% tmpDpPtbDurMismatch  Quick per-trial Datapixx-vs-PTB duration diagnostic.
%
% out = tmpDpPtbDurMismatch(ex)
%
% Returns:
%   out.trials  table with per-trial durations and mismatch
%   out.summary table with min/median/max/mean/std/n of mismatch

nTrials = numel(ex.Trials);
trial = (1:nTrials)';
ptbDurSec = NaN(nTrials, 1);
dpDurSec = NaN(nTrials, 1);
dpMinusPtbDurSec = NaN(nTrials, 1);

for j = 1:nTrials
    T = ex.Trials(j);

    if isfield(T, 'TrialEnd') && isfield(T, 'TrialStart') && ...
            isfinite(T.TrialEnd) && isfinite(T.TrialStart)
        ptbDurSec(j) = double(T.TrialEnd) - double(T.TrialStart);
    end

    if isfield(T, 'TrialEndDatapixx') && isfield(T, 'TrialStartDatapixx') && ...
            isfinite(T.TrialEndDatapixx) && isfinite(T.TrialStartDatapixx)
        dpDurSec(j) = double(T.TrialEndDatapixx) - double(T.TrialStartDatapixx);
    end

    dpMinusPtbDurSec(j) = dpDurSec(j) - ptbDurSec(j);
end

out = struct();
out.trials = table(trial, ptbDurSec, dpDurSec, dpMinusPtbDurSec);
out.summary = table( ...
    min(dpMinusPtbDurSec, [], 'omitnan'), ...
    median(dpMinusPtbDurSec, 'omitnan'), ...
    max(dpMinusPtbDurSec, [], 'omitnan'), ...
    mean(dpMinusPtbDurSec, 'omitnan'), ...
    std(dpMinusPtbDurSec, 'omitnan'), ...
    sum(isfinite(dpMinusPtbDurSec)), ...
    'VariableNames', {'min','median','max','mean','std','n'});

disp(out.summary);
end
