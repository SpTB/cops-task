function out = blinkHmmTransitions(ex, opts)
% blinkHmmTransitions  HMM-transition-locked blink-density diagnostic.
if nargin < 2, opts=struct(); end
out = blinkEventDensity(ex,'hmm',opts);
end
