function payout = calculateCoPsPayoutx(trials,pay)
% Convert the average whole earned points per non-practice trial to a bonus.
% Both endpoints are exact; 'logit' denotes a normalized inverse-logit curve.
pay = resolveCoPsPayx(pay);
[total,points,mask] = getCoPsEarnedPointsx(trials);
n = nnz(mask);
average = 0;
if n > 0, average = total/n; end
x = max(0,min(1,(average-pay.minPointsPerTrial)/(pay.maxPointsPerTrial-pay.minPointsPerTrial)));
fraction = x;
if strcmp(pay.transform,'logit') && x > 0 && x < 1 && pay.logitSlope >= sqrt(eps)
    % Algebraically equivalent to normalized sigmoid, without exp overflow.
    a = tanh(pay.logitSlope/4);
    fraction = (tanh(pay.logitSlope*(x-0.5)/2)+a)/(2*a);
end
fraction = max(0,min(1,fraction));
capCents = round(100*pay.max_bonus_dollar);
rawCents = fraction*capCents;
% Correct only floating-point error at exact cents before flooring.
if abs(rawCents-round(rawCents)) <= 16*eps(max(1,abs(rawCents)))
    rawCents = round(rawCents);
end
bonusCents = floor(rawCents);
if average < pay.maxPointsPerTrial
    bonusCents = min(bonusCents,max(0,capCents-1));
end
if n == 0, bonusCents = 0; end
payout = struct('config',pay,'totalPoints',total,'nTrials',n, ...
    'trialPoints',points,'trialMask',mask,'averagePointsPerTrial',average, ...
    'normalizedPerformance',x,'bonusFraction',fraction, ...
    'bonusDollarsUnrounded',fraction*pay.max_bonus_dollar, ...
    'bonusCents',bonusCents,'bonusDollars',bonusCents/100);
end
