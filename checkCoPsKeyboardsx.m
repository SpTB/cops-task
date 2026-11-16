function report = checkCoPsKeyboardsx(participantIndex, experimenterIndex, durationSecs)
% List keyboards or check participant/operator separation without a task run.
%
%   checkCoPsKeyboardsx()
%   report = checkCoPsKeyboardsx(participantID, experimenterID)
%   report = checkCoPsKeyboardsx(participantID, experimenterID, 60)
%
% IDs are the Psychtoolbox indices in the displayed inventory, not XInput IDs.
% The protected check requires two physical keyboards on Linux/X11. It floats
% only the participant keyboard and restores its original desktop attachment
% on normal return, errors, or an experimenter Ctrl+C interruption. Do not
% disconnect keyboards or clear PsychHID while the check is running.
arguments
    participantIndex = []
    experimenterIndex = []
    durationSecs (1,1) double {mustBeFinite, mustBePositive} = 30
end

if isempty(participantIndex) && isempty(experimenterIndex)
    [indices, names] = GetKeyboardIndices;
    report = table(indices(:), string(names(:)), ...
        'VariableNames', {'Index', 'Keyboard'});
    disp(report);
    fprintf(['Choose the participant and experimenter indices, then call:\n' ...
        '  checkCoPsKeyboardsx(participantID, experimenterID)\n' ...
        'Protected device separation requires Linux/X11; the standard Windows\n' ...
        'keyboard APIs merge keyboards. One display is sufficient.\n']);
    return
end

[keyboards, keyboardCleanup] = initCoPsKeyboardsx( ...
    participantIndex, experimenterIndex); %#ok<NASGU>
setup = struct('keyboards', keyboards);
fprintf('Participant keyboard: %s (PTB index %d)\n', ...
    keyboards.participantName, keyboards.participantIndex);
fprintf('Experimenter keyboard: %s (PTB index %d)\n', ...
    keyboards.experimenterName, keyboards.experimenterIndex);
fprintf(['Check duration: %.0f seconds.\n' ...
    'Participant: press SPACE, then try F4, letters, and Ctrl+C.\n' ...
    'Only SPACE should register; the other keys should not end the check.\n' ...
    'Experimenter: F4 ends the check; Ctrl+C remains an emergency interrupt.\n'], durationSecs);

report = struct('spacePresses', 0, 'operatorQuit', false, ...
    'elapsedSecs', 0, 'keyboards', keyboards);
[~, previousSpace] = readCoPsKeyboardx(setup);
quitKey = KbName('F4');
startTime = GetSecs;
while GetSecs - startTime < durationSecs
    [operatorKeys, spaceDown] = readCoPsKeyboardx(setup);
    if operatorKeys(quitKey)
        report.operatorQuit = true;
        fprintf('Experimenter F4 received. Ending keyboard check.\n');
        break
    end
    if spaceDown && ~previousSpace
        report.spacePresses = report.spacePresses + 1;
        fprintf('Participant SPACE: %d\n', report.spacePresses);
    end
    previousSpace = spaceDown;
    WaitSecs('YieldSecs', 0.01);
end
report.elapsedSecs = GetSecs - startTime;
% Restore before announcing completion, rather than waiting for function exit.
clear keyboardCleanup
fprintf('Keyboard check finished: %d SPACE press(es), %.1f seconds.\n', ...
    report.spacePresses, report.elapsedSecs);
end
