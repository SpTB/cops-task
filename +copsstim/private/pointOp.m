% RES = pointOp(IM, LUT, ORIGIN, INCREMENT, WARNINGS)
%
% Apply a point operation, specified by lookup table LUT, to image IM.
% LUT must be a row or column vector, and is assumed to contain
% (equi-spaced) samples of the function.  ORIGIN specifies the
% abscissa associated with the first sample, and INCREMENT specifies the
% spacing between samples.  Between-sample values are estimated via
% linear interpolation.  If WARNINGS is non-zero, the function prints
% a warning whenever the lookup table is extrapolated.
%
% This function is much faster than MatLab's interp1, and allows
% extrapolation beyond the lookup table domain.  The drawbacks are
% that the lookup table must be equi-spaced, and the interpolation is
% linear.

% Eero Simoncelli, 8/96.

function res = pointOp(im, lut, origin, increment, warnings)

% Portable vectorization of matlabPyrTools' pointOp.c. Use the native C
% interpolation expression and index truncation to preserve its numerics.
if nargin < 5, warnings = 1; end
if ~(increment > 0)
    res = repmat(lut(1),size(im));
    return
end
if numel(lut) < 2
    error('copsstim:LookupTable','The lookup table needs at least two entries.');
end
pos = (im(:)-origin)/increment;
index = fix(pos);
if warnings && any(index < 0)
    fprintf('Warning: Extrapolating to left of lookup table...\n');
end
if warnings && any(index > numel(lut)-2)
    fprintf('Warning: Extrapolating to right of lookup table...\n');
end
index = max(0,min(numel(lut)-2,index));
lut = lut(:);
res = lut(index+1)+(lut(index+2)-lut(index+1)).*(pos-index);
res = reshape(res,size(im));

