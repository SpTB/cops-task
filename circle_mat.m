function [circle_matrix] = circle_mat(image, cx, cy, radius, in_color,overlay_on_image)

[rows, cols] = size(image); % For grayscale; use size(im0,1), size(im0,2) for color
[X, Y] = meshgrid(1:cols, 1:rows);

circle_matrix=zeros(size(image));

% Calculate squared distance from the center for each point
squared_distance = (X - cx).^2 + (Y - cy).^2;

% Set values inside the circle to 1
%circle_matrix(squared_distance >= radius^2) = 1; %full inside
circle_matrix(squared_distance <= (radius+1)^2 & squared_distance >= radius^2) = 1;

if in_color
    if overlay_on_image
        imint = uint8(image);
        r=cat(3,imint, imint,imint);
        circle_mask = repmat(logical(circle_matrix), [1, 1, 3]);
        r(circle_mask) = 0;
        r(repmat(logical(circle_matrix), [1, 1, 1])) = 255;
        circle_matrix=r;
    else
    % Create the hollow circle logical mask
        rgbMatrix = zeros(size(image,1), size(image,2), 3);
        rgbMatrix(:,:,1)=circle_matrix;
        circle_matrix = rgbMatrix;
    end
end