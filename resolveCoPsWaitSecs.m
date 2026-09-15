function [waitSecs, waitHz] = resolveCoPsWaitSecs(in, fallbackWaitSecs)
% resolveCoPsWaitSecs Resolve CoPs step timing from new or legacy fields.
%
% New configs should set ex.exp.CoPs.timing.waitHz. Legacy configs with
% ex.exp.CoPs.timing.wait_secs remain supported.
if nargin < 2 || isempty(fallbackWaitSecs)
    fallbackWaitSecs = NaN;
end

waitSecs = NaN;
waitHz = NaN;
timing = struct();
ctl = struct();

if isstruct(in)
    if isfield(in, 'exp') && isfield(in.exp, 'CoPs')
        if isfield(in.exp.CoPs, 'timing') && isstruct(in.exp.CoPs.timing)
            timing = in.exp.CoPs.timing;
        end
        if isfield(in.exp.CoPs, 'ctl') && isstruct(in.exp.CoPs.ctl)
            ctl = in.exp.CoPs.ctl;
        end
    elseif isfield(in, 'timing') && isstruct(in.timing)
        timing = in.timing;
        if isfield(in, 'ctl') && isstruct(in.ctl)
            ctl = in.ctl;
        end
    else
        timing = in;
    end
end

waitHz = localFirstFinitePositiveField(timing, {'waitHz', 'wait_hz'});
if isfinite(waitHz)
    waitSecs = 1 / waitHz;
    return
end

waitSecs = localFirstFinitePositiveField(timing, {'wait_secs', 'waitSecs'});
if ~isfinite(waitSecs)
    waitSecs = localFirstFinitePositiveField(ctl, {'wait_secs', 'waitSecs', 'waitsecs'});
end
if isfinite(waitSecs)
    waitHz = 1 / waitSecs;
    return
end

fallbackWaitSecs = localFirstFinitePositive(fallbackWaitSecs);
if isfinite(fallbackWaitSecs)
    waitSecs = fallbackWaitSecs;
    waitHz = 1 / waitSecs;
end
end


function value = localFirstFinitePositiveField(s, names)
value = NaN;
if ~isstruct(s)
    return
end
for i = 1:numel(names)
    if isfield(s, names{i})
        value = localFirstFinitePositive(s.(names{i}));
        if isfinite(value)
            return
        end
    end
end
end


function value = localFirstFinitePositive(x)
value = NaN;
if isempty(x) || ~isnumeric(x)
    return
end
x = double(x(:));
x = x(isfinite(x) & x > 0);
if ~isempty(x)
    value = x(1);
end
end
