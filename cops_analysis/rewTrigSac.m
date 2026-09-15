function out = rewTrigSac(ex, trialSelection, opts)
% rewTrigSac  Abbreviated wrapper for reward-triggered saccade analysis.
%
%   out = rewTrigSac(ex)
%   out = rewTrigSac(ex, 1:120)
%   out = rewTrigSac(ex, 'bg')
%   out = rewTrigSac(ex, {'bg','vis'})
%   out = rewTrigSac(ex, [], opts)
%
% This is a thin wrapper around rewardTriggeredSaccades() that keeps the
% shorter call style used by the other CoPs analysis helpers.

if nargin < 2
    trialSelection = [];
end
if nargin < 3
    opts = struct();
end

out = rewardTriggeredSaccades(ex, trialSelection, opts);
end
