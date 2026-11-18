function cap = getCoPsBonusCapx(nTrials,pay)
% Scale the hourly bonus rate by paid trial count, independent of clock time.
pay = resolveCoPsPayx(pay);
validateattributes(nTrials,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
hours = double(nTrials)/pay.trials_per_hour;
dollars = pay.max_bonus_dollar*hours;
cents = dollars*100;
if abs(cents-round(cents)) <= 16*eps(max(1,abs(cents)))
    cents = round(cents);
end
cap = struct('equivalentHours',hours,'maxBonusDollarsUnrounded',dollars, ...
    'maxBonusCents',floor(cents),'maxBonusDollars',floor(cents)/100);
end
