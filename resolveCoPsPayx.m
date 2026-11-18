function pay = resolveCoPsPayx(pay)
% Resolve and validate the complete bonus configuration (no toolboxes).
if nargin < 1, pay = struct(); end
defaults = struct('minPointsPerTrial',3,'maxPointsPerTrial',25, ...
    'max_bonus_dollar',25,'trials_per_hour',180,'transform','linear','logitSlope',10);
names = fieldnames(defaults);
for k=1:numel(names)
    if ~isfield(pay,names{k}), pay.(names{k})=defaults.(names{k}); end
end
validateattributes(pay.minPointsPerTrial,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(pay.maxPointsPerTrial,{'numeric'},{'scalar','real','finite','positive'});
if pay.maxPointsPerTrial <= pay.minPointsPerTrial
    error('resolveCoPsPayx:InvalidThresholds','pay.maxPointsPerTrial must exceed pay.minPointsPerTrial.');
end
validateattributes(pay.max_bonus_dollar,{'numeric'},{'scalar','real','finite','nonnegative'});
cents = pay.max_bonus_dollar*100;
if ~isfinite(cents) || abs(cents-round(cents)) > 1e-6
    error('resolveCoPsPayx:InvalidCurrencyPrecision','pay.max_bonus_dollar must specify a whole number of cents.');
end
pay.max_bonus_dollar = round(cents)/100;
validateattributes(pay.trials_per_hour,{'numeric'},{'scalar','real','finite','integer','positive'});
pay.transform = validatestring(pay.transform,{'linear','logit'});
validateattributes(pay.logitSlope,{'numeric'},{'scalar','real','finite','positive'});
end
