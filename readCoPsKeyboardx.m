function [operatorKeys, spaceDown, timestamp] = readCoPsKeyboardx(setup)
% Read operator shortcuts separately from the participant's SPACE response.
% This filters task actions only. OS/MATLAB keyboard isolation is configured
% separately; filtering a key here does not suppress MATLAB's Ctrl+C.
arguments
    setup struct = struct()
end

persistent spaceKey controlKeys
if isempty(spaceKey)
    KbName('UnifyKeyNames');
    spaceKey = KbName('space');
    names = {'F1', 'F2', 'F3', 'F4', 'F6', 'F7', 'F8', 'F9'};
    controlKeys = cellfun(@KbName, names);
end

separate = isfield(setup, 'keyboards') && ...
    isfield(setup.keyboards, 'separate') && setup.keyboards.separate;
if separate
    [~, timestamp, operatorRaw] = KbCheck(setup.keyboards.experimenterIndex);
    [~, ~, participantRaw] = KbCheck(setup.keyboards.participantIndex);
else
    [~, timestamp, operatorRaw] = KbCheck;
    participantRaw = operatorRaw;
end
operatorKeys = false(size(operatorRaw));
operatorKeys(controlKeys) = logical(operatorRaw(controlKeys));
spaceDown = logical(participantRaw(spaceKey));
end
