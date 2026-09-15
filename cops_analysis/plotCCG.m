function out = plotCCG(in, trialNo, opts, varargin)
% plotCCG  Wrapper around ccg() that always plots.
if nargin < 3 || isempty(opts)
    opts = struct();
end
opts.plot = true;
if ischar(opts) || (isstring(opts) && isscalar(opts))
    if ~strcmpi(char(string(opts)), 'all')
        error('plotCCG:AxisRemoved', 'The axis selector was removed. plotCCG() now always plots both x and y.');
    end
    if ~isempty(varargin)
        opts = varargin{1};
    else
        opts = struct();
    end
    opts.plot = true;
end
out = ccg(in, trialNo, opts);
