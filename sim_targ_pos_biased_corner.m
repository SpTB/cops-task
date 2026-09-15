function [xwalk, ywalk] = sim_targ_pos_biased_corner(nsteps, init_xy, dx_range, dy_range, corner_xy, bias_strength, jitter_std, stepNoiseType, stepNoiseSigma, stepNoiseCapSigma, boundaryMode, boundaryRejectMaxAttempts, positionBound)
% Simulate 2D target motion biased toward a selected image corner.
% Coordinates are normalized, with default bounds [-1, 1].
%
% inputs:
%   nsteps        : number of steps
%   init_xy       : [x0 y0] initial target position
%   dx_range      : [dxmin dxmax] unbiased x movement range
%   dy_range      : [dymin dymax] unbiased y movement range
%   corner_xy     : [xc yc] corner attractor location (e.g., [-0.85 -0.85])
%   bias_strength : attraction strength toward corner [0..1]
%   jitter_std    : Gaussian jitter (normalized units)
%   stepNoiseType : 'uniform' (default) or 'normal'/'gaussian'
%   stepNoiseSigma: Gaussian step sigma in normalized units
%   stepNoiseCapSigma: cap Gaussian steps at +/- this many sigma
%   boundaryMode  : 'clip' (legacy clamp) or 'reject' (redraw
%                   out-of-bounds steps)
%   boundaryRejectMaxAttempts: max redraw attempts for reject mode
%   positionBound : absolute normalized-position bound (default 1)
%
% outputs:
%   xwalk, ywalk  : biased random walk trajectories
if nargin < 8 || isempty(stepNoiseType)
    stepNoiseType = 'uniform';
end
if nargin < 9 || isempty(stepNoiseSigma)
    stepNoiseSigma = 0.07;
end
if nargin < 10 || isempty(stepNoiseCapSigma)
    stepNoiseCapSigma = 3.5;
end
if nargin < 11 || isempty(boundaryMode)
    boundaryMode = 'clip';
end
if nargin < 12 || isempty(boundaryRejectMaxAttempts)
    boundaryRejectMaxAttempts = 50;
end
if nargin < 13 || isempty(positionBound)
    positionBound = 1;
end

stepNoiseType = lower(char(stepNoiseType));
boundaryMode = validatestring(char(boundaryMode), {'clip', 'reject'});
boundaryRejectMaxAttempts = max(1, round(double(boundaryRejectMaxAttempts)));
positionBound = double(positionBound);
positionBound = positionBound(1);
if ~isfinite(positionBound) || positionBound <= 0
    positionBound = 1;
end

xwalk = zeros(1, nsteps);
ywalk = zeros(1, nsteps);

xwalk(1) = max(-positionBound, min(positionBound, init_xy(1)));
ywalk(1) = max(-positionBound, min(positionBound, init_xy(2)));

bias_strength = max(0, min(1, bias_strength));

for i = 2:nsteps
    [xwalk(i), ywalk(i)] = localNextBoundedPosition2d( ...
        xwalk(i-1), ywalk(i-1), dx_range, dy_range, corner_xy, bias_strength, ...
        jitter_std, stepNoiseType, stepNoiseSigma, stepNoiseCapSigma, ...
        boundaryMode, boundaryRejectMaxAttempts, positionBound);
end
end


function [newX, newY] = localNextBoundedPosition2d(oldX, oldY, dxRange, dyRange, cornerXY, biasStrength, jitterStd, stepNoiseType, stepNoiseSigma, stepNoiseCapSigma, boundaryMode, maxAttempts, positionBound)
switch boundaryMode
    case 'clip'
        [newX, newY] = localDrawCandidate(oldX, oldY, dxRange, dyRange, cornerXY, biasStrength, jitterStd, stepNoiseType, stepNoiseSigma, stepNoiseCapSigma);
        newX = max(-positionBound, min(positionBound, newX));
        newY = max(-positionBound, min(positionBound, newY));
    case 'reject'
        newX = NaN;
        newY = NaN;
        for attempt = 1:maxAttempts
            [candidateX, candidateY] = localDrawCandidate(oldX, oldY, dxRange, dyRange, cornerXY, biasStrength, jitterStd, stepNoiseType, stepNoiseSigma, stepNoiseCapSigma);
            if isfinite(candidateX) && isfinite(candidateY) && ...
                    candidateX >= -positionBound && candidateX <= positionBound && ...
                    candidateY >= -positionBound && candidateY <= positionBound
                newX = candidateX;
                newY = candidateY;
                break
            end
        end
        if ~isfinite(newX) || ~isfinite(newY)
            [newX, newY] = localDrawCandidate(oldX, oldY, dxRange, dyRange, cornerXY, biasStrength, jitterStd, stepNoiseType, stepNoiseSigma, stepNoiseCapSigma);
            newX = max(-positionBound, min(positionBound, newX));
            newY = max(-positionBound, min(positionBound, newY));
        end
end
end


function [newX, newY] = localDrawCandidate(oldX, oldY, dxRange, dyRange, cornerXY, biasStrength, jitterStd, stepNoiseType, stepNoiseSigma, stepNoiseCapSigma)
stepDx = localDrawStep(dxRange, stepNoiseType, stepNoiseSigma, stepNoiseCapSigma);
stepDy = localDrawStep(dyRange, stepNoiseType, stepNoiseSigma, stepNoiseCapSigma);

toCornerX = cornerXY(1) - oldX;
toCornerY = cornerXY(2) - oldY;

newX = oldX + stepDx + biasStrength * toCornerX + randn() * jitterStd;
newY = oldY + stepDy + biasStrength * toCornerY + randn() * jitterStd;
end


function stepVal = localDrawStep(stepRange, stepNoiseType, stepNoiseSigma, stepNoiseCapSigma)
switch stepNoiseType
    case 'uniform'
        stepVal = stepRange(1) + rand() * (stepRange(2) - stepRange(1));
    case {'normal', 'gaussian'}
        stepVal = randn() * stepNoiseSigma;
        if isfinite(stepNoiseCapSigma) && stepNoiseCapSigma > 0
            stepVal = max(-stepNoiseCapSigma * stepNoiseSigma, ...
                min(stepNoiseCapSigma * stepNoiseSigma, stepVal));
        end
    otherwise
        error('sim_targ_pos_biased_corner:BadStepNoiseType', ...
            'Unknown stepNoiseType: %s', stepNoiseType);
end
end
