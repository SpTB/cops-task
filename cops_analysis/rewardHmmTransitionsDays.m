function out = rewardHmmTransitionsDays(animal,dateFrom,dateTo,opts)
% rewardHmmTransitionsDays  Aggregate transition-locked reward density.
if nargin<2,dateFrom=[];end
if nargin<3,dateTo=[];end
if nargin<4,opts=struct();end
out=eventDensityDays(animal,dateFrom,dateTo,'reward',opts);
end
