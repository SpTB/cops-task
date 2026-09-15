function out = plotCCGsac(ex, trialNo, opts, varargin)
% plotCCGsac  Wrapper around ccgSac() that always plots.
if nargin < 3 || isempty(opts)
    opts = struct();
end
opts.plot = true;
if ischar(opts) || (isstring(opts) && isscalar(opts))
    if ~strcmpi(char(string(opts)), 'all')
        error('plotCCGsac:AxisRemoved', 'The axis selector was removed. plotCCGsac() now always plots both x and y.');
    end
    if ~isempty(varargin)
        opts = varargin{1};
    else
        opts = struct();
    end
    opts.plot = true;
end
out = ccgSac(ex, trialNo, opts);
