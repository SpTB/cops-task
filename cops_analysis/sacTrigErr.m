function out = sacTrigErr(ex, trialNo, opts)
% sacTrigErr  Compute saccade-triggered average error traces.
if nargin < 2
    trialNo = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
opts.plot = false;
opts.newFigure = false;
out = plotSacTrigErr(ex, trialNo, opts);
