function quadIdx = classifyQuadrantCoPs(xPx, yPx, ctrPx)
% Quadrant labels:
%   1 top-right
%   2 top-left
%   3 bottom-left
%   4 bottom-right

quadIdx = NaN(size(xPx));
valid = isfinite(xPx) & isfinite(yPx);
if ~any(valid)
    return
end

x = xPx(valid);
y = yPx(valid);

quadValid = NaN(size(x));
quadValid(x >= ctrPx(1) & y < ctrPx(2)) = 1;
quadValid(x < ctrPx(1) & y < ctrPx(2)) = 2;
quadValid(x < ctrPx(1) & y >= ctrPx(2)) = 3;
quadValid(x >= ctrPx(1) & y >= ctrPx(2)) = 4;

quadIdx(valid) = quadValid;
end
