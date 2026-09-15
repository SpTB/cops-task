function [pxOut, info] = resolveReferenceDisplayPx(pxIn, setup, ref)
% Resolve reference-display pixels to current-display pixels.
%
% This preserves visual angle for values that were chosen in pixels on an
% older display geometry.

if nargin < 3 || isempty(ref)
    ref = struct();
end

refMonitorWidth = localFieldOr(ref, 'monitorWidthCm', 38.5);
refViewingDistance = localFieldOr(ref, 'viewingDistanceCm', 58);
refScreenWidthPx = localFieldOr(ref, 'screenWidthPx', 1920);
roundOutput = localFieldOr(ref, 'roundOutput', true);

localRequireSetup(setup);

currentScreenWidthPx = double(setup.screenRect(3));
referenceSetup = struct();
referenceSetup.monitorWidth = refMonitorWidth;
referenceSetup.viewingDistance = refViewingDistance;
referenceSetup.screenRect = [0 0 refScreenWidthPx NaN];

referenceDeg = visualPxToDeg(pxIn, referenceSetup);
pxOut = visualDegToPx(referenceDeg, setup);

if roundOutput
    finiteMask = isfinite(pxOut);
    pxOut(finiteMask) = round(pxOut(finiteMask));
end

info = struct();
info.referenceMonitorWidthCm = refMonitorWidth;
info.referenceViewingDistanceCm = refViewingDistance;
info.referenceScreenWidthPx = refScreenWidthPx;
info.currentMonitorWidthCm = double(setup.monitorWidth);
info.currentViewingDistanceCm = double(setup.viewingDistance);
info.currentScreenWidthPx = currentScreenWidthPx;
info.referenceDegPerPx = visualPxToDeg(1, referenceSetup);
info.currentDegPerPx = visualPxToDeg(1, setup);
info.scalePx = pxOut ./ double(pxIn);
info.roundOutput = roundOutput;
end

function value = localFieldOr(s, fieldName, defaultValue)
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);
else
    value = defaultValue;
end
end

function localRequireSetup(setup)
requiredFields = {'monitorWidth', 'viewingDistance', 'screenRect'};
for k = 1:numel(requiredFields)
    if ~isstruct(setup) || ~isfield(setup, requiredFields{k}) || isempty(setup.(requiredFields{k}))
        error('resolveReferenceDisplayPx:MissingSetupField', ...
            'setup.%s is required.', requiredFields{k});
    end
end
if numel(setup.screenRect) < 3 || ~isfinite(setup.screenRect(3)) || setup.screenRect(3) <= 0
    error('resolveReferenceDisplayPx:InvalidScreenRect', ...
        'setup.screenRect must contain a positive screen width at element 3.');
end
end
