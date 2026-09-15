function mask = gauss_mask(image, cx, cy, radius, sigma)
% Create Gaussian mask for image processing
% Returns a circular Gaussian mask
%
% inputs:
% image: reference image (for size)
% cx: center x coordinate
% cy: center y coordinate  
% radius: radius of Gaussian mask
% sigma: optional Gaussian SD in image pixels (default radius/3)
%
% output:
% mask: 2D Gaussian mask

% Get image dimensions
[height, width] = size(image);

% Reuse coordinate grids across repeated mask calls for the same image size.
[x, y] = localGridForSize(height, width);

% Calculate distance from center
dx = x - cx;
dy = y - cy;
distance_sq = dx.^2 + dy.^2;

% Create Gaussian mask
if nargin < 5 || isempty(sigma)
    sigma = radius / 3; % Standard deviation
end

mask = exp(-distance_sq / (2 * sigma^2));

% Ensure mask is within 0-1 range
mask = max(0, min(1, mask));

end


function [x, y] = localGridForSize(height, width)
persistent gridCache
if isempty(gridCache)
    gridCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
end

key = sprintf('%dx%d', height, width);
if isKey(gridCache, key)
    grids = gridCache(key);
else
    [grids.x, grids.y] = meshgrid(1:width, 1:height);
    gridCache(key) = grids;
end
x = grids.x;
y = grids.y;
end
