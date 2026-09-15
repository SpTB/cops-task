function [gain, ratios] = signedEyeCalGain(targetPx, rawSignal, rawCenter, signedGain)
% Estimate signed eye calibration gain in pixels per raw eye-signal unit.
%
% The online eye transform is:
%   screenPx = (rawSignal - rawCenter) * gain + screenCenterPx
% Therefore gain must preserve the polarity of the raw channel.
%
% Set signedGain=false to restore legacy absolute-magnitude gain.

if nargin < 4 || isempty(signedGain)
    signedGain = true;
end

targetPx = double(targetPx(:));
rawSignal = double(rawSignal(:));
rawCenter = double(rawCenter);

n = min(numel(targetPx), numel(rawSignal));
targetPx = targetPx(1:n);
rawSignal = rawSignal(1:n);
rawDelta = rawSignal - rawCenter;

valid = isfinite(targetPx) & isfinite(rawDelta) & ...
    targetPx ~= 0 & rawDelta ~= 0;

if signedGain
    ratios = targetPx(valid) ./ rawDelta(valid);
else
    ratios = abs(targetPx(valid)) ./ abs(rawDelta(valid));
end
if isempty(ratios)
    gain = NaN;
else
    gain = median(ratios);
end
end
