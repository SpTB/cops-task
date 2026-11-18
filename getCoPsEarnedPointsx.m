function [totalPoints,trialPoints,countsForSession] = getCoPsEarnedPointsx(trials)
% Whole points are recorded reward crossings, independent of fractional score.
trialPoints = zeros(1,numel(trials));
countsForSession = true(1,numel(trials));
for k=1:numel(trials)
    t = trials(k);
    incomplete = isfield(t,'trialCompleted') && ~isempty(t.trialCompleted) && ~t.trialCompleted;
    if incomplete, countsForSession(k) = false; end
    if ~isfield(t,'times') || ~isstruct(t.times) || ~isfield(t.times,'reward')
        if incomplete, continue; end % an interrupted trial may have no reward log yet
        error('getCoPsEarnedPointsx:MissingRewardEvents','Trial %d has no reward-event timestamps; earned points cannot be inferred from fractional scores.',k);
    end
    trialPoints(k) = nnz(isfinite(t.times.reward));
    if isfield(t,'isInstructionTutorial') && ~isempty(t.isInstructionTutorial) && t.isInstructionTutorial
        countsForSession(k) = false;
    end
    if isfield(t,'pointsCountTowardTotal') && ~isempty(t.pointsCountTowardTotal) && ~t.pointsCountTowardTotal
        countsForSession(k) = false;
    end
end
totalPoints = sum(trialPoints(countsForSession));
end
