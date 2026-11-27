function graph = resolveCoPsStimulusFieldx(graph, setup)
% Keep the centered square stimulus field at a fixed edge-to-edge angle.
% Call after opening the display and after detecting source texture dimensions.
% Missing/empty fieldSizeDeg retains legacy size_mult settings.

if ~isfield(graph, 'fieldSizeDeg') || isempty(graph.fieldSizeDeg)
    return
end

validateattributes(graph.fieldSizeDeg, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive', '<', 180}, mfilename, 'graph.fieldSizeDeg');
validateattributes(graph.texture_dims, {'numeric'}, ...
    {'vector', 'numel', 2, 'integer', 'positive'}, mfilename, 'graph.texture_dims');
if graph.texture_dims(1) ~= graph.texture_dims(2)
    error('resolveCoPsStimulusFieldx:NonSquareTexture', ...
        'Angular field sizing requires square source textures.');
end
validateattributes(setup.monitorWidth, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'}, mfilename, 'setup.monitorWidth');
validateattributes(setup.viewingDistance, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'}, mfilename, 'setup.viewingDistance');
validateattributes(setup.screenRect, {'numeric'}, ...
    {'vector', 'numel', 4, 'real', 'finite'}, mfilename, 'setup.screenRect');
displaySize = double(setup.screenRect(3:4) - setup.screenRect(1:2));
if any(displaySize <= 0)
    error('resolveCoPsStimulusFieldx:InvalidDisplaySize', ...
        'setup.screenRect must describe a positive display size.');
end

% Convert half the angular span to a screen-plane offset, then double it.
% Round once so the texture field and reward matrix use one integer size.
sidePx = round(2 * visualDegToPx(double(graph.fieldSizeDeg) / 2, setup));
if sidePx < 2 || sidePx > min(displaySize)
    error('resolveCoPsStimulusFieldx:FieldDoesNotFit', ...
        ['The %.4g deg stimulus field requires %d x %d pixels, but the display is ' ...
         '%g x %g. Check monitorWidth, viewingDistance, and screen resolution.'], ...
        graph.fieldSizeDeg, sidePx, sidePx, displaySize(1), displaySize(2));
end

graph.size_mult = sidePx / double(graph.texture_dims(1));
graph.fieldSizePx = sidePx;
graph.fieldSizeActualDeg = 2 * visualPxToDeg(sidePx / 2, setup);
end
