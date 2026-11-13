function ex = finalizeCoPsPointsx(ex, evidence, threshold, trialCompleted, trialScored)

%save reward derived points for the current trial and update the session
%sum, preserve the existing score: sum of nonnegative finite evidence /
%threshold
validateattributes(threshold, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});
evidence(~isfinite(evidence) | evidence < 0) = 0;
pointTrace = cumsum(evidence) ./ threshold;
pointsEarned = 0;
if trialScored && ~isempty(pointTrace)
    pointsEarned = pointTrace(end);
end
if ~isfield(ex, 'totalPoints') || isempty(ex.totalPoints) || ...
        ~isscalar(ex.totalPoints) || ~isfinite(ex.totalPoints)
    ex.totalPoints = 0;
end
ex.totalPoints = ex.totalPoints + pointsEarned;
ex.Trials(ex.j).rawPointsEvidence = sum(evidence);
ex.Trials(ex.j).pointTrace = pointTrace;
ex.Trials(ex.j).pointsEarned = pointsEarned;
ex.Trials(ex.j).totalPoints = ex.totalPoints;
ex.Trials(ex.j).trialCompleted = logical(trialCompleted);
ex.Trials(ex.j).trialScored = logical(trialScored);
end

