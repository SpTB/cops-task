function dependencies = resolveCoPsRunDependenciesx(profileName, pixOn, eyeOn, rewOn)
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

dependencies.datapixxOn = dependencies.pixOn || ...
    dependencies.eyeOn || dependencies.rewOn;
dependencies.eyelinkOn = dependencies.eyeOn;

if dependencies.eyeOn
    dependencies.inputMode = 'eye';
else
    dependencies.inputMode = 'mouse';
end
end
