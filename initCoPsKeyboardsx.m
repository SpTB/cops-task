function [keyboards, cleanup] = initCoPsKeyboardsx(participantIndex, experimenterIndex)
% Isolate one Linux/X11 keyboard from desktop shortcuts for a task session.
% The returned cleanup object MUST remain alive until the session ends.
arguments
    participantIndex = []
    experimenterIndex = []
end
cleanup = [];
keyboards = struct('separate', false, 'participantIndex', [], ...
    'experimenterIndex', [], 'participantDeviceID', [], ...
    'participantAttachment', [], 'experimenterDeviceID', [], ...
    'participantName', '', 'experimenterName', '', ...
    'osKeysIsolated', false, 'isolation', 'shared-unprotected');
if isempty(participantIndex) && isempty(experimenterIndex)
    return
end
if isempty(participantIndex) || isempty(experimenterIndex)
    error('initCoPsKeyboardsx:MissingKeyboard', ...
        'Specify both participantKeyboard and experimenterKeyboard, or leave both empty for shared-keyboard testing.');
end
validateattributes(participantIndex, {'numeric'}, {'scalar','real','finite','integer','nonnegative'});
validateattributes(experimenterIndex, {'numeric'}, {'scalar','real','finite','integer','nonnegative'});
if participantIndex == experimenterIndex
    error('initCoPsKeyboardsx:SameKeyboard', 'Participant and experimenter must use different keyboard devices.');
end
if ~IsLinux || isempty(getenv('DISPLAY')) || strcmpi(getenv('XDG_SESSION_TYPE'), 'wayland')
    error('initCoPsKeyboardsx:UnsupportedPlatform', ...
        'Separate protected keyboards require Linux/X11. Shared-keyboard testing is available with both keyboard options empty.');
end
[indices, names, allInfos] = GetKeyboardIndices;
participantPosition = find(indices == participantIndex, 1);
experimenterPosition = find(indices == experimenterIndex, 1);
if isempty(participantPosition) || isempty(experimenterPosition)
    error('initCoPsKeyboardsx:KeyboardUnavailable', ...
        'A selected keyboard is unavailable. Run GetKeyboardIndices and select two currently attached physical keyboards.');
end
participant = allInfos{participantPosition};
experimenter = allInfos{experimenterPosition};
for position = [participantPosition experimenterPosition]
    if contains(lower(names{position}), 'xwayland') || contains(lower(names{position}), 'xtest')
        error('initCoPsKeyboardsx:VirtualKeyboard', 'Select physical keyboards, not XWayland or XTEST virtual devices.');
    end
end
participantID = participant.interfaceID;
experimenterID = experimenter.interfaceID;
attachment = participant.locationID;
validateattributes(participantID, {'numeric'}, {'scalar','real','finite','integer','positive'});
validateattributes(experimenterID, {'numeric'}, {'scalar','real','finite','integer','positive'});
validateattributes(attachment, {'numeric'}, {'scalar','real','finite','integer','positive'});
validateattributes(experimenter.locationID, {'numeric'}, {'scalar','real','finite','integer','positive'});
if participantID == experimenterID
    error('initCoPsKeyboardsx:SameKeyboard', 'The selected indices resolve to the same physical XInput device.');
end
[status, ~] = system('command -v xinput');
if status ~= 0
    error('initCoPsKeyboardsx:MissingXinput', 'Install xinput on the Linux/X11 rig before using separate keyboards.');
end
checkAttached(participantID, attachment);
checkAttached(experimenterID, experimenter.locationID);
% Open/cache both physical devices BEFORE floating the participant device.
% PTB indices refer to a cached device snapshot. Do not clear PsychHID or
% re-enumerate devices while the participant keyboard is detached.
participantDown = KbCheck(participantIndex);
if participantDown
    error('initCoPsKeyboardsx:KeysHeld', ...
        'Release all participant keyboard keys before starting separate-keyboard mode.');
end
KbCheck(experimenterIndex);
cleanup = onCleanup(@() restoreKeyboard(participantID, attachment));
[status, message] = system(sprintf('xinput float %d', participantID));
if status ~= 0
    error('initCoPsKeyboardsx:IsolationFailed', 'Cannot isolate participant keyboard: %s', strtrim(message));
end
[status, description] = system(sprintf('LC_ALL=C xinput list --short %d', participantID));
if status ~= 0 || isempty(regexp(description, '\[\s*floating slave\s*\]', 'once'))
    error('initCoPsKeyboardsx:IsolationFailed', 'XInput did not confirm a floating participant keyboard.');
end
keyboards.separate = true;
keyboards.participantIndex = double(participantIndex);
keyboards.experimenterIndex = double(experimenterIndex);
keyboards.participantDeviceID = double(participantID);
keyboards.participantAttachment = double(attachment);
keyboards.experimenterDeviceID = double(experimenterID);
keyboards.participantName = names{participantPosition};
keyboards.experimenterName = names{experimenterPosition};
keyboards.osKeysIsolated = true;
keyboards.isolation = 'linux-xinput-floating';
end

function checkAttached(deviceID, expectedAttachment)
[status, description] = system(sprintf('LC_ALL=C xinput list --short %d', deviceID));
token = regexp(description, '\[\s*slave keyboard\s*\(\s*(\d+)\s*\)\s*\]', 'tokens', 'once');
idPattern = ['id\s*=\s*' sprintf('%d', deviceID) '(\s|$)'];
if status ~= 0 || isempty(token) || isempty(regexp(description, idPattern, 'once')) || ...
        str2double(token{1}) ~= expectedAttachment
    error('initCoPsKeyboardsx:StaleDevice', ...
        'XInput keyboard %d is missing, detached, or changed. Reattach it and refresh keyboard indices before starting.', deviceID);
end
end

function restoreKeyboard(deviceID, attachment)
command = sprintf('xinput reattach %d %d', deviceID, attachment);
try
    [status, message] = system(command);
catch err
    status = 1;
    message = err.message;
end
if status ~= 0
    try
        warning('initCoPsKeyboardsx:RestoreFailed', ...
            'Could not restore participant keyboard: %s. Restore it from the experimenter keyboard with: %s', strtrim(message), command);
    catch
        % Even warning-as-error settings must not mask the original task error.
        fprintf(2, 'Keyboard restoration failed. Run from the experimenter keyboard: %s\n', command);
    end
end
end
