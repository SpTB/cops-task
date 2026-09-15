function deg = px2deg(px, setup)
% px2deg Convert display distance from pixels to visual degrees.
%
%   deg = px2deg(px)
%   deg = px2deg(px, cal)
%
% Inputs
%   px  : numeric array of pixel distances.
%   cal : (optional) conversion source. Supported forms:
%         - ex struct containing ex.setup
%         - setup struct with fields monitorWidth, viewingDistance, screenRect
%         - scalar degrees-per-pixel (dpp)
%
% Notes
%   If cal is omitted, the function attempts to read "ex" from caller
%   workspace. This supports calls like px2deg(trialSummary.meanDistPx)
%   from analysis scripts where ex is in scope.

arguments
    px {mustBeNumeric}
    setup = struct();
end

%setup = iResolveSetup(cal);

screenWidthPx = setup.screenRect(3);
dpp = atan((setup.monitorWidth / 2) / setup.viewingDistance) * 180 / pi / (screenWidthPx / 2);

deg = px .* dpp;

end

% function setup = iResolveSetup(cal)
% if isstruct(cal) && isfield(cal, 'setup')
%     setup = cal.setup;
% elseif isstruct(cal)
%     setup = cal;
% else
%     error('px2deg:InvalidCalibration', ...
%         'Second input must be ex, setup, or scalar dpp.');
% end
% 
% requiredFields = {'monitorWidth', 'viewingDistance', 'screenRect'};
% for k = 1:numel(requiredFields)
%     if ~isfield(setup, requiredFields{k})
%         error('px2deg:MissingSetupField', ...
%             'setup.%s is required to convert px to deg.', requiredFields{k});
%     end
% end
% end

