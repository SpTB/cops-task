function [participantIndex, experimenterIndex, mode] = resolveCoPsKeyboardSelectionx(setup, profile, requestedMode, participantIndex, experimenterIndex)
% Resolve rig keyboard defaults before initCoPsKeyboardsx isolates any device.
% Explicit indices override named defaults. Portable previews stay shared in
% auto mode; normal task profiles use the host's configured default mode.
arguments
    setup struct
    profile {mustBeText}
    requestedMode {mustBeMember(requestedMode, {'auto','shared','separate'})} = 'auto'
    participantIndex = []
    experimenterIndex = []
end
mode = char(requestedMode);
hasIndices = ~isempty(participantIndex) || ~isempty(experimenterIndex);
if strcmp(mode, 'shared')
    if hasIndices
        error('CoPs:KeyboardModeConflict', ...
            'keyboardMode="shared" cannot be combined with participantKeyboard or experimenterKeyboard.');
    end
    return
end
if hasIndices
    % Leave scalar, missing-role and same-device validation to the initializer.
    mode = 'separate';
    return
end
configured = isfield(setup, 'keyboardDefaults') && isstruct(setup.keyboardDefaults);
if strcmp(mode, 'auto')
    mode = 'shared';
    if ~ismember(lower(strtrim(char(profile))), {'test1','mouse_mini'}) && ...
            configured && isfield(setup.keyboardDefaults, 'mode')
        mode = char(setup.keyboardDefaults.mode);
    end
end
if strcmp(mode, 'shared'), return; end
if ~strcmp(mode, 'separate')
    error('CoPs:KeyboardDefaultMode', 'Rig keyboardDefaults.mode must be shared or separate.');
end
if ~configured || ~all(isfield(setup.keyboardDefaults, {'participantName','experimenterName'}))
    error('CoPs:KeyboardDefaultsMissing', ...
        'Separate mode requires both keyboard indices or configured participant/experimenter device names.');
end
[indices, names] = GetKeyboardIndices;
participantIndex = findNamedKeyboardLocal(indices, names, setup.keyboardDefaults.participantName, 'participant');
experimenterIndex = findNamedKeyboardLocal(indices, names, setup.keyboardDefaults.experimenterName, 'experimenter');
end

function index = findNamedKeyboardLocal(indices, names, deviceName, role)
positions = find(strcmp(names, char(deviceName)));
if isempty(positions)
    error('CoPs:DefaultKeyboardUnavailable', ...
        ['Configured %s keyboard "%s" is unavailable. Connect it, supply both keyboard indices, ' ...
         'or explicitly use keyboardMode="shared".'], role, char(deviceName));
end
if numel(positions) ~= 1
    error('CoPs:DefaultKeyboardAmbiguous', ...
        'More than one %s keyboard matches "%s". Supply both keyboard indices explicitly.', role, char(deviceName));
end
index = indices(positions);
end
