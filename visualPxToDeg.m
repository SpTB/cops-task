function deg = visualPxToDeg(px, setup)
% Convert screen pixels to visual degrees using screen-plane geometry.

localRequireSetup(setup);
cm = double(px) .* double(setup.monitorWidth) ./ double(setup.screenRect(3));
deg = rad2deg(atan(cm ./ double(setup.viewingDistance)));
end

function localRequireSetup(setup)
requiredFields = {'monitorWidth', 'viewingDistance', 'screenRect'};
for k = 1:numel(requiredFields)
    if ~isstruct(setup) || ~isfield(setup, requiredFields{k}) || isempty(setup.(requiredFields{k}))
        error('visualPxToDeg:MissingSetupField', ...
            'setup.%s is required.', requiredFields{k});
    end
end
if numel(setup.screenRect) < 3 || ~isfinite(setup.screenRect(3)) || setup.screenRect(3) <= 0
    error('visualPxToDeg:InvalidScreenRect', ...
        'setup.screenRect must contain a positive screen width at element 3.');
end
end
