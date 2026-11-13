function out = blinkHmmTransitionsDays(animal,dateFrom,dateTo,opts)
% blinkHmmTransitionsDays  Aggregate HMM-transition blink density by day.
if nargin<2,dateFrom=[];end
if nargin<3,dateTo=[];end
if nargin<4,opts=struct();end
out=eventDensityDays(animal,dateFrom,dateTo,'blink',opts);
end
