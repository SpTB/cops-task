function [pixel_x, pixel_y] = pix_norm(norm_x, norm_y, img_width, img_height, radius, hiddenBoundsFrac)
% Convert normalized coordinates (-1 to 1) to pixel coordinates
% Ensures targets stay within image bounds considering radius, unless an
% optional hidden-bound fraction allows partial off-image targets.
%
% Inputs:
%   norm_x, norm_y: Normalized coordinates (-1 to 1)
%   img_width, img_height: Image dimensions
%   radius: Target radius in pixels
%   hiddenBoundsFrac: fraction of target diameter allowed outside bounds
%
% Outputs:
%   pixel_x, pixel_y: Pixel coordinates within image bounds
if nargin < 6 || isempty(hiddenBoundsFrac)
    hiddenBoundsFrac = 0;
end
hiddenBoundsFrac = double(hiddenBoundsFrac);
hiddenBoundsFrac = hiddenBoundsFrac(1);
if ~isfinite(hiddenBoundsFrac)
    hiddenBoundsFrac = 0;
end
hiddenBoundsFrac = max(0, hiddenBoundsFrac);

% Calculate center of image
center_x = img_width / 2;
center_y = img_height / 2;

% Calculate maximum allowed range (leaving room for radius)
max_x_range = (img_width / 2) - radius;
max_y_range = (img_height / 2) - radius;

% Convert normalized to pixel coordinates
pixel_x = center_x + norm_x * max_x_range;
pixel_y = center_y + norm_y * max_y_range;

% Safety clamp. hiddenBoundsFrac=0 is legacy fully-visible behavior;
% hiddenBoundsFrac=0.2 allows 20% of target diameter outside the texture.
hidden_px = 2 * radius * hiddenBoundsFrac;
pixel_x = max(radius - hidden_px, min(img_width - radius + hidden_px, pixel_x));
pixel_y = max(radius - hidden_px, min(img_height - radius + hidden_px, pixel_y));

end
