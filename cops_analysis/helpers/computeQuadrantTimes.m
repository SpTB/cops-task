function quadTimes = computeQuadrantTimes(xPx, yPx, ctrPx, validMask, dtSec)
if nargin < 5 || isempty(dtSec) || ~isfinite(dtSec)
    dtSec = 1;
end
quadTimes = zeros(1, 4);
m = validMask & isfinite(xPx) & isfinite(yPx);
if ~any(m)
    quadTimes(:) = NaN;
    return
end
quadIdx = classifyQuadrantCoPs(xPx(m), yPx(m), ctrPx);
quadTimes = (accumarray(quadIdx(:), 1, [4 1], @sum, 0) * dtSec).';

end
