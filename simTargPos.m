% xx to be moved to helper
function [walk] = sim_targ_pos(nsteps, init_pos, dmin, dmax, stepNoiseType, stepNoiseSigma, stepNoiseCapSigma)
% Simulate target positions in normalized coordinates (-1 to 1)
% Creates random walk positions within specified normalized range
%
% inputs:
%   nsteps: number of steps to generate
%   init_pos: initial position in normalized coordinates (-1 to 1)
%   dmin: minimum movement in normalized coordinates
%   dmax: maximum movement in normalized coordinates
%   stepNoiseType: 'uniform' (default) or 'normal'/'gaussian'
%   stepNoiseSigma: Gaussian step sigma in normalized units
%   stepNoiseCapSigma: cap Gaussian steps at +/- this many sigma
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

stepNoiseType = lower(char(string(stepNoiseType)));
% Initialize position array
walk = zeros(1, nsteps);

% Set initial position (ensure within bounds)
walk(1) = max(-1, min(1, init_pos));

% Generate random walk for remaining steps
for i = 2:nsteps
    % Random movement within normalized range
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
    % Apply movement to previous position
    new_pos = walk(i-1) + movement;
    
    % Ensure bounds checking (-1 to 1)
    walk(i) = max(-1, min(1, new_pos));
end

end
