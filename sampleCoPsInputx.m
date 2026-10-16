function [passEye, trEye, lastEyePos, sample] = sampleCoPsInputx( ...
    inputMode, trEye, ex, passEye, freeViewing, lastEyePos, toleranceScalar)
% Sample the active CoPs behavioral input through one common interface.
%
% inputMode='eye' reads the DataPixx-backed eye signal through checkEyex.
% inputMode='mouse' treats the Psychtoolbox pointer as simulated gaze.

arguments
    inputMode {mustBeText}
    trEye struct
    ex struct
    passEye {mustBeNumericOrLogical}
    freeViewing {mustBeNumericOrLogical}
    lastEyePos double
    toleranceScalar (1,1) double = 1
end

mode = lower(strtrim(char(inputMode)));
sample = struct( ...
    'source', mode, ...
    'position', [NaN NaN], ...
    'pointerPosition', [NaN NaN], ...
    'overlayPositions', zeros(0, 2), ...
    'inBounds', false, ...
    'timestamp', GetSecs);

switch mode
    case 'eye'
        [passEye, trEye, lastEyePos] = checkEyex( ...
            trEye, ex, passEye, freeViewing, lastEyePos, 0, 0, toleranceScalar);
        [mouseX, mouseY] = GetMouse(ex.setup.window);
        sample.pointerPosition = [mouseX mouseY];

        eyePoints = lastEyePos(:, 1:2);
        validRows = all(isfinite(eyePoints), 2);
        if any(validRows)
            sample.position = mean(eyePoints(validRows, :), 1);
        end

        if size(eyePoints, 1) > 1
            sample.overlayPositions = [eyePoints; sample.position; sample.pointerPosition];
        else
            sample.overlayPositions = [eyePoints; sample.pointerPosition];
        end

    case 'mouse'
        [mouseX, mouseY] = GetMouse(ex.setup.window);
        sample.position = [mouseX mouseY];
        sample.pointerPosition = sample.position;
        sample.overlayPositions = sample.position;
        lastEyePos = sample.position;

        withinFixation = abs(mouseX - ex.fix.PCtr(1)) <= ex.fix.WinW * toleranceScalar && ...
            abs(mouseY - ex.fix.PCtr(2)) <= ex.fix.WinH * toleranceScalar;
        passEye = logical(freeViewing) || withinFixation;

    otherwise
        error('sampleCoPsInputx:UnknownInputMode', ...
            'Unsupported CoPs input mode: %s', inputMode);
end

rect = ex.setup.screenRect;
sample.inBounds = all(isfinite(sample.position)) && ...
    sample.position(1) >= rect(1) && sample.position(1) <= rect(3) && ...
    sample.position(2) >= rect(2) && sample.position(2) <= rect(4);
end
