function reward_matrix = gauss_rew_land(xdim, center, sigma)
% Create Gaussian reward landscape
% Returns a 2D Gaussian reward matrix
%
% inputs:
% xdim: x dimension of the landscape
% center: [cx, cy] center of Gaussian
% sigma: standard deviation of Gaussian
%
% output:
% reward_matrix: 2D matrix with Gaussian reward landscape

% Create coordinate grids
[x, y] = meshgrid(1:xdim, 1:xdim);

% Calculate 2D Gaussian
dx = x - center(1);
dy = y - center(2);
exponent = -(dx.^2 + dy.^2) / (2 * sigma^2);
reward_matrix = exp(exponent);

% Normalize to 0-1 range
reward_matrix = reward_matrix / max(reward_matrix(:));

end