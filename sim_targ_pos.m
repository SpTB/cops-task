% xx to be moved to helper
function [walk] = sim_targ_pos(nsteps, init_pos, dmin, dmax, stepNoiseType, stepNoiseSigma, stepNoiseCapSigma, boundaryMode, boundaryRejectMaxAttempts, positionBound)
% Simulate target positions in normalized coordinates
% Creates random walk positions within specified normalized range
%
% inputs:
%   nsteps: number of steps to generate
%   init_pos: initial position in normalized coordinates
%   dmin: minimum movement in normalized coordinates
%   dmax: maximum movement in normalized coordinates
%   stepNoiseType: 'uniform' (default) or 'normal'/'gaussian'
%   stepNoiseSigma: Gaussian step sigma in normalized units
%   stepNoiseCapSigma: cap Gaussian steps at +/- this many sigma
%   boundaryMode: 'clip' (legacy clamp) or 'reject' (redraw
%                 out-of-bounds steps)
%   boundaryRejectMaxAttempts: max redraw attempts for reject mode
%   positionBound: absolute normalized-position bound (default 1)
%
% output:
%   walk: vector of normalized positions for each step
if nargin < 5 || isempty(stepNoiseType)
    stepNoiseType = 'uniform';
end
if nargin < 6 || isempty(stepNoiseSigma)
    stepNoiseSigma = 0.07;
end
if nargin < 7 || isempty(stepNoiseCapSigma)
    stepNoiseCapSigma = 3.5;
end
if nargin < 8 || isempty(boundaryMode)
    boundaryMode = 'clip';
end
if nargin < 9 || isempty(boundaryRejectMaxAttempts)
    boundaryRejectMaxAttempts = 50;
end
if nargin < 10 || isempty(positionBound)
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
% Initialize position array
walk = zeros(1, nsteps);

% Set initial position (ensure within bounds)
walk(1) = max(-positionBound, min(positionBound, init_pos));

% Generate random walk for remaining steps
for i = 2:nsteps
    walk(i) = localNextBoundedPosition( ...
        walk(i-1), dmin, dmax, stepNoiseType, stepNoiseSigma, ...
        stepNoiseCapSigma, boundaryMode, boundaryRejectMaxAttempts, positionBound);
end

end


function newPos = localNextBoundedPosition(oldPos, dmin, dmax, stepNoiseType, stepNoiseSigma, stepNoiseCapSigma, boundaryMode, maxAttempts, positionBound)
switch boundaryMode
    case 'clip'
        movement = localDrawStep(dmin, dmax, stepNoiseType, stepNoiseSigma, stepNoiseCapSigma);
        newPos = max(-positionBound, min(positionBound, oldPos + movement));
    case 'reject'
        newPos = NaN;
        for attempt = 1:maxAttempts
            movement = localDrawStep(dmin, dmax, stepNoiseType, stepNoiseSigma, stepNoiseCapSigma);
            candidate = oldPos + movement;
            if isfinite(candidate) && candidate >= -positionBound && candidate <= positionBound
                newPos = candidate;
                break
            end
        end
        if ~isfinite(newPos)
            movement = localDrawStep(dmin, dmax, stepNoiseType, stepNoiseSigma, stepNoiseCapSigma);
            newPos = max(-positionBound, min(positionBound, oldPos + movement));
        end
end
end


function movement = localDrawStep(dmin, dmax, stepNoiseType, stepNoiseSigma, stepNoiseCapSigma)
switch stepNoiseType
    case 'uniform'
        movement = (rand() * (dmax - dmin)) + dmin;
    case {'normal', 'gaussian'}
        movement = randn() * stepNoiseSigma;
        if isfinite(stepNoiseCapSigma) && stepNoiseCapSigma > 0
            movement = max(-stepNoiseCapSigma * stepNoiseSigma, ...
                min(stepNoiseCapSigma * stepNoiseSigma, movement));
        end
    otherwise
        error('sim_targ_pos:BadStepNoiseType', ...
            'Unknown stepNoiseType: %s', stepNoiseType);
end
end
