function out = plotCCGSacRew(ex, trialNo, opts, varargin)
% plotCCGSacRew  Wrapper around ccgSacRew() that always plots.
if nargin < 2
    trialNo = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
opts.plot = true;
if ischar(opts) || (isstring(opts) && isscalar(opts))
    if ~strcmpi(char(string(opts)), 'all')
        error('plotCCGSacRew:AxisRemoved', 'The axis selector was removed. plotCCGSacRew() now always plots both x and y.');
    end
    if ~isempty(varargin)
        opts = varargin{1};
    else
        opts = struct();
    end
    opts.plot = true;
end
out = ccgSacRew(ex, trialNo, opts);
