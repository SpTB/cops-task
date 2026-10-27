function [rew, blockIdx, blockTrialIdx] = applyCoPsJointBlockx(ex, rew, blockInfo)
% Resolve the reward peak and main-relative indices for a rewSwitches trial.
% Explicit block coordinates also keep the daily center cache from replacing
% or saving a switching peak. Special phases retain their existing center.

blockIdx = NaN;
blockTrialIdx = NaN;
if ~isfield(ex, 'exp') || ~isfield(ex.exp, 'CoPs') || ...
        ~isfield(ex.exp.CoPs, 'ctl')
    return
end
ctl = ex.exp.CoPs.ctl;
if ~isfield(ctl, 'jointBlocks') || isempty(ctl.jointBlocks)
    return
end
enabled = ctl.jointBlocks;
if ischar(enabled) || isstring(enabled)
    enabled = any(strcmpi(strtrim(char(string(enabled))), {'true', '1', 'yes', 'on'}));
else
    enabled = logical(enabled(1));
end
if ~enabled
    return
end
if nargin < 3
    blockInfo = getCoPsTrialBlockInfox(ex);
end
mainTrialIdx = find(blockInfo.mainIdx == ex.j, 1, 'first');
if isempty(mainTrialIdx)
    return
end

requiredFields = {'jointBlockStartMainTrials', 'jointBlockEndMainTrials', 'jointBlockCenters'};
if ~all(isfield(ctl, requiredFields))
    error('applyCoPsJointBlockx:JointBlocksNotPrepared', ...
        'Joint blocks must be initialized with prepareCoPsJointBlocksx before running trials.');
end
starts = double(ctl.jointBlockStartMainTrials(:)');
ends = double(ctl.jointBlockEndMainTrials(:)');
centers = double(ctl.jointBlockCenters);
if isempty(ends) || numel(starts) ~= numel(ends) || ...
        any(~isfinite([starts ends])) || any(starts ~= round(starts)) || ...
        any(ends ~= round(ends)) || any(ends < starts) || ...
        ~isequal(starts, [1 ends(1:end-1) + 1]) || ends(end) ~= blockInfo.mainN || ...
        size(centers, 1) ~= numel(ends) || size(centers, 2) ~= 2 || ...
        any(~isfinite(centers(:))) || any(centers(:) < 0 | centers(:) > 1)
    error('applyCoPsJointBlockx:BadJointBlockPlan', ...
        'Joint block ranges and centers must cover all main trials with finite [0,1] coordinates.');
end
blockIdx = find(mainTrialIdx <= ends, 1, 'first');
rew.gauss_center_free = true;
rew.gauss_center_coords = centers(blockIdx, :);
blockTrialIdx = mainTrialIdx - starts(blockIdx) + 1;
end
