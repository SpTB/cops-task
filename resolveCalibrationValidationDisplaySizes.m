function ex = resolveCalibrationValidationDisplaySizes(ex)
% Convert calibration/validation degree/reference-pixel defaults to pixels.
%
% Fields are converted only when their corresponding Units field is 'deg'
% or 'referencePx'. Plain numeric pixel settings without that unit are
% treated as already specified for the current display.

if ~isstruct(ex) || ~isfield(ex, 'setup') || isempty(ex.setup)
    return
end

if isfield(ex, 'calib') && isstruct(ex.calib)
    ex.calib = localResolveField(ex.calib, 'Psz', 'PszUnits', ...
        'PszReferencePx', 'PszDisplayInfo', ex.setup);
end

if isfield(ex, 'valid') && isstruct(ex.valid)
    ex.valid = localResolveField(ex.valid, 'targetWin', 'targetWinUnits', ...
        'targetWinReferencePx', 'targetWinDisplayInfo', ex.setup);
    ex.valid = localResolveField(ex.valid, 'targetWin2', 'targetWin2Units', ...
        'targetWin2ReferencePx', 'targetWin2DisplayInfo', ex.setup);
end
end

function s = localResolveField(s, fieldName, unitsFieldName, referenceFieldName, infoFieldName, setup)
if ~isfield(s, fieldName) || isempty(s.(fieldName))
    return
end
if ~isfield(s, unitsFieldName) || isempty(s.(unitsFieldName))
    return
end

unitsValue = localUnits(s.(unitsFieldName));
switch unitsValue
    case 'referencepx'
        referencePx = s.(fieldName);
        ref = localReferenceDisplay(s);
        [currentPx, info] = resolveReferenceDisplayPx(referencePx, setup, ref);
        s.(referenceFieldName) = referencePx;

    case {'deg', 'degree', 'degrees'}
        sourceDeg = s.(fieldName);
        [currentPx, info] = localResolveDegPx(sourceDeg, setup, localRoundOutput(s));
        s.([fieldName 'Deg']) = sourceDeg;

    otherwise
        return
end

s.(fieldName) = currentPx;
s.(unitsFieldName) = 'px';
s.(infoFieldName) = info;
end

function unitsValue = localUnits(unitsValue)
if isstring(unitsValue)
    unitsValue = char(unitsValue);
end
if ischar(unitsValue)
    unitsValue = lower(strtrim(unitsValue));
else
    unitsValue = '';
end
end

function [pxOut, info] = localResolveDegPx(degIn, setup, roundOutput)
pxOut = visualDegToPx(degIn, setup);
if roundOutput
    finiteMask = isfinite(pxOut);
    pxOut(finiteMask) = round(pxOut(finiteMask));
end

info = struct();
info.sourceUnits = 'deg';
info.currentMonitorWidthCm = double(setup.monitorWidth);
info.currentViewingDistanceCm = double(setup.viewingDistance);
info.currentScreenWidthPx = double(setup.screenRect(3));
info.currentDegPerPx = visualPxToDeg(1, setup);
info.roundOutput = roundOutput;
end

function roundOutput = localRoundOutput(s)
roundOutput = localFieldOr(s, 'sizeRoundOutput', ...
    localFieldOr(s, 'sizeReferenceRoundOutput', true));
end

function ref = localReferenceDisplay(s)
ref = struct();
ref.monitorWidthCm = localFieldOr(s, 'sizeReferenceMonitorWidthCm', 38.5);
ref.viewingDistanceCm = localFieldOr(s, 'sizeReferenceViewingDistanceCm', 58);
ref.screenWidthPx = localFieldOr(s, 'sizeReferenceScreenWidthPx', 1920);
ref.roundOutput = localFieldOr(s, 'sizeReferenceRoundOutput', true);
end

function value = localFieldOr(s, fieldName, defaultValue)
if isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);
else
    value = defaultValue;
end
end

function localRequireSetup(setup)
requiredFields = {'monitorWidth', 'viewingDistance', 'screenRect'};
for k = 1:numel(requiredFields)
    if ~isstruct(setup) || ~isfield(setup, requiredFields{k}) || isempty(setup.(requiredFields{k}))
        error('resolveCalibrationValidationDisplaySizes:MissingSetupField', ...
            'setup.%s is required.', requiredFields{k});
    end
end
if numel(setup.screenRect) < 3 || ~isfinite(setup.screenRect(3)) || setup.screenRect(3) <= 0
    error('resolveCalibrationValidationDisplaySizes:InvalidScreenRect', ...
        'setup.screenRect must contain a positive screen width at element 3.');
end
end
