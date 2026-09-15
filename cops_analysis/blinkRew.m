function out = blinkRew(ex, opts)
% blinkRew  Reward-release-locked blink-density diagnostic.
if nargin < 2, opts=struct(); end
out = blinkEventDensity(ex,'reward',opts);
end
