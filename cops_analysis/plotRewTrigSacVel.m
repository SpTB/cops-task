function out = plotRewTrigSacVel(in, trialSelection, opts)
% plotRewTrigSacVel  Alias for plotRewTrigVel().
if nargin < 2
    trialSelection = [];
end
if nargin < 3
    opts = struct();
end
out = plotRewTrigVel(in, trialSelection, opts);
