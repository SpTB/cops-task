function dependencies = resolveCoPsRunDependenciesx(profileName, pixOn, eyeOn, rewOn, eyeSource)
% Resolve optional hardware dependencies and the behavioral input source.
%
% The test1 profile is deliberately hardware-free. Other profiles preserve
% the caller-provided switches. Keeping this policy in one place makes mixed
% dependency configurations easier to exercise without adding profile checks
% throughout the task code.

arguments
    profileName {mustBeText} = ''
    pixOn {mustBeNumericOrLogical} = true
    eyeOn {mustBeNumericOrLogical} = true
    rewOn {mustBeNumericOrLogical} = true
    eyeSource {mustBeMember(eyeSource, {'eyelink','analog'})} = 'eyelink'
end

dependencies = struct();
dependencies.profile = lower(strtrim(char(profileName)));
dependencies.pixOn = logical(pixOn);
dependencies.eyeOn = logical(eyeOn);
dependencies.rewOn = logical(rewOn);

if strcmp(dependencies.profile, 'test1')
    dependencies.pixOn = false;
    dependencies.eyeOn = false;
    dependencies.rewOn = false;
end

dependencies.eyeSource = char(eyeSource);
dependencies.adcOn = dependencies.eyeOn && ...
    (dependencies.pixOn || strcmp(eyeSource, 'analog'));
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
else
    dependencies.inputMode = 'mouse';
end
end
