function out = plotCCGSacAmp(ex, trialNo, opts, varargin)
% plotCCGSacAmp  Wrapper around ccgSacAmp() that always plots.
if nargin < 3 || isempty(opts)
    opts = struct();
end
opts.plot = true;
if ischar(opts) || (isstring(opts) && isscalar(opts))
    if ~strcmpi(char(string(opts)), 'all')
        error('plotCCGSacAmp:AxisRemoved', ...
            'The axis selector was removed. plotCCGSacAmp() now always plots both x and y.');
    end
    if ~isempty(varargin)
        opts = varargin{1};
    else
        opts = struct();
    end
    opts.plot = true;
end
out = ccgSacAmp(ex, trialNo, opts);
