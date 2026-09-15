function [walk] = simTargPos(nsteps, init_pos, dmin, dmax)
% Simulate target positions for continuous psychophysics task
% Creates random walk positions within specified range
%
% inputs:
% nsteps: number of steps to generate
% init_pos: initial position
% dmin: minimum movement range
% dmax: maximum movement range
%
% output:
% walk: vector of positions for each step

% Initialize position array
walk = zeros(1, nsteps);

% Set initial position
walk(1) = init_pos;

% Generate random walk for remaining steps
for i = 2:nsteps
    % Random movement within range
    movement = randi([dmin, dmax]);
    
    % Apply movement to previous position
    walk(i) = walk(i-1) + movement;
end

end