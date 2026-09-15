function px = visualDegToPx(deg, setup)
% Convert visual degrees to screen pixels using screen-plane geometry.

localRequireSetup(setup);
px = double(setup.viewingDistance) .* tan(deg2rad(double(deg))) .* ...
    double(setup.screenRect(3)) ./ double(setup.monitorWidth);
end

function localRequireSetup(setup)
requiredFields = {'monitorWidth', 'viewingDistance', 'screenRect'};
for k = 1:numel(requiredFields)
    if ~isstruct(setup) || ~isfield(setup, requiredFields{k}) || isempty(setup.(requiredFields{k}))
        error('visualDegToPx:MissingSetupField', ...
            'setup.%s is required.', requiredFields{k});
    end
end
if numel(setup.screenRect) < 3 || ~isfinite(setup.screenRect(3)) || setup.screenRect(3) <= 0
    error('visualDegToPx:InvalidScreenRect', ...
        'setup.screenRect must contain a positive screen width at element 3.');
end
end
