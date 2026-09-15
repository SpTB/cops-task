function px = normStep2px(normUnits, graph)
% normStep2px Convert CoPs normalized motion units to pixels.
%
%   px = normStep2px(normUnits, graph)
%
% Inputs
%   normUnits : numeric array in the normalized target-motion units used by
%               pos.dxmin/max, pos.dymin/max, and stepNoiseSigma.
%   graph     : CoPs graph struct with fields:
%               - texture_dims
%               - radius
%               - size_mult
%
% Notes
%   The target walk is defined in normalized coordinates in [-1, 1] and
%   converted to pixel coordinates by pix_norm(...), which uses the usable
%   half-range:
%
%       max_range_px = (img_width / 2) - radius
%
%   The displayed stimulus is then scaled by graph.size_mult.

arguments
    normUnits {mustBeNumeric}
    graph struct
end

requiredFields = {'texture_dims', 'radius', 'size_mult'};
for k = 1:numel(requiredFields)
    if ~isfield(graph, requiredFields{k})
        error('normStep2px:MissingGraphField', ...
            'graph.%s is required.', requiredFields{k});
    end
end

imgWidthPx = double(graph.texture_dims(1));
radiusPx = double(graph.radius);
sizeMult = double(graph.size_mult);

usableHalfRangePx = (imgWidthPx / 2) - radiusPx;
px = normUnits .* usableHalfRangePx * sizeMult;
end
