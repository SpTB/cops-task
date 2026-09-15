function out = eccentricityHmmTransitionsDays(animal,dateFrom,dateTo,opts)
% eccentricityHmmTransitionsDays  Aggregate transition-aligned eccentricity.
if nargin<2,dateFrom=[];end
if nargin<3,dateTo=[];end
if nargin<4,opts=struct();end
out=eventDensityDays(animal,dateFrom,dateTo,'eccentricity',opts);
end
