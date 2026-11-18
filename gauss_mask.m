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

% Keep the public API while the task and generator share one implementation.
if nargin < 5, sigma = []; end
mask = copsstim.gaussMask(image,cx,cy,radius,sigma);
end
