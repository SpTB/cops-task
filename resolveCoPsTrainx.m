function train = resolveCoPsTrainx(train)
% Defaults also support saved configurations from before train was introduced.
if nargin < 1, train = struct(); end
defaults = struct('nreps',10,'visibility',1,'background_noise_lvl',1);
for name = fieldnames(defaults)'
    if ~isfield(train,name{1}), train.(name{1}) = defaults.(name{1}); end
end
validateattributes(train.nreps,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
validateattributes(train.visibility,{'numeric'},{'vector','nonempty','real','finite','>=',0,'<=',1});
validateattributes(train.background_noise_lvl,{'numeric'},{'vector','nonempty','real','finite','integer','>=',-1});
train.visibility = train.visibility(:)';
train.background_noise_lvl = train.background_noise_lvl(:)';
end
