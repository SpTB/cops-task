function dependencies = resolveCoPsRunDependenciesx(profileName, pixOn, eyeOn, rewOn, eyeSource, photodiodeRecord)
% Resolve optional hardware dependencies and the behavioral input source.
%
% The test1 and mouse_mini profiles are hardware-free unless photodiodeRecord
% is explicitly enabled (ADC only). Other profiles preserve
% the caller-provided switches. Keeping this policy in one place makes mixed
% dependency configurations easier to exercise without adding profile checks
% throughout the task code.

arguments
    profileName {mustBeText} = ''
    pixOn {mustBeNumericOrLogical} = true
    eyeOn {mustBeNumericOrLogical} = true
    rewOn {mustBeNumericOrLogical} = true
    eyeSource {mustBeMember(eyeSource, {'eyelink','analog'})} = 'eyelink'
    photodiodeRecord (1,1) logical = false
end

dependencies = struct();
dependencies.profile = lower(strtrim(char(profileName)));
dependencies.pixOn = logical(pixOn);
dependencies.eyeOn = logical(eyeOn);
dependencies.rewOn = logical(rewOn);

if ismember(dependencies.profile, {'test1', 'mouse_mini'})
    dependencies.pixOn = false;
    dependencies.eyeOn = false;
    dependencies.rewOn = false;
end

dependencies.eyeSource = char(eyeSource);
dependencies.photodiodeRecord = photodiodeRecord;
dependencies.adcOn = photodiodeRecord || (dependencies.eyeOn && ...
    (dependencies.pixOn || strcmp(eyeSource, 'analog')));
dependencies.datapixxOn = dependencies.pixOn || dependencies.adcOn || dependencies.rewOn;
%dependencies.datapixxOn = dependencies.pixOn || ...
    %dependencies.eyeOn || dependencies.rewOn;
dependencies.eyelinkOn = dependencies.eyeOn;

if dependencies.eyeOn
    dependencies.inputMode = 'eye';
    if strcmp(eyeSource, 'analog')
        dependencies.inputMode = 'eye';
    else
        dependencies.inputMode = 'eyelink';
    end
elseif ismember(dependencies.profile, {'test1', 'mouse_mini'})
    dependencies.inputMode = 'mouse';
else
    % Disabling eye hardware must never substitute a behavioral signal.
    dependencies.inputMode = 'none';
end
end
