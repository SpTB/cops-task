function stab = calcSwitching(tRel, stepIdx, xPx, yPx, distPx1, distPx2, inBounds, betweenMarginPx, nsteps, dtSec, setup, requireSaccade)
% Compute switching metrics from timestep-level target assignment.
%
% "Between" samples are those where the distance difference between targets
% is too small to confidently assign identity.

if nargin < 12 || isempty(requireSaccade)
    requireSaccade = false;
end

stab = struct();
%stab.assignment = zeros(0,1);      % 1=targ1, 2=targ2, 0=between/invalid
%stab.validMask = false(0,1);
%stab.betweenMask = false(0,1);
stab.bothFrac = NaN; % percent of time both targets are 'tracked' (similar distance)
%stab.switchCount = NaN;
stab.switchRateHz = NaN;
stab.transProbStep = NaN;
stab.meanDwellSteps = NaN;
stab.meanDwellSec = NaN;
stab.switchIndicators = false(0,1);
stab.stayIndicators = false(0,1);
stab.dwellSteps = zeros(0,1);
stab.dwellSec = zeros(0,1);
stab.trialDurSec = NaN;

assign = assignTargetIdentityCoPs(distPx1, distPx2, inBounds, betweenMarginPx, stepIdx);
assignedStep = assign.assignedStep;
steps = assign.step(:);

% fraction of timesteps without a valid unique assignment
stab.bothFrac = mean(assignedStep == 0, 'omitnan');

% switching
stepGazeX = aggregateStepwiseMeanLocal(stepIdx, xPx, steps);
stepGazeY = aggregateStepwiseMeanLocal(stepIdx, yPx, steps);
validAssignedStep = assignedStep > 0;
assigned = assignedStep(validAssignedStep); % removing uncertain timesteps

switched = diff(assigned) ~= 0;
if requireSaccade
    stepHasSaccade = aggregateStepwiseSaccadeLocal(stepIdx, steps, xPx, yPx, dtSec, setup);
    seqStepHasSaccade = stepHasSaccade(validAssignedStep);
    if numel(seqStepHasSaccade) > 1
        switched = switched & seqStepHasSaccade(2:end);
    else
        switched(:) = false;
    end
end
switchCount = sum(switched);
nTrans = max(numel(assigned) - 1, 1);
stab.transProbStep = switchCount / nTrans;
stab.switchIndicators = switched(:);
stab.stayIndicators = ~switched(:);

% Dwell run lengths in assigned timesteps, using the same qualified switch
% criterion as the switch count itself.
runStart = [true; switched(:)];
runIdx = cumsum(runStart);
dwellSteps = accumarray(runIdx, 1);
stab.meanDwellSteps = mean(dwellSteps, 'omitnan');
stab.dwellSteps = dwellSteps(:);

% Hz and secs
trialDur = max(tRel) - min(tRel);
stab.switchRateHz = switchCount / trialDur;
stepDurSec = trialDur / max(nsteps, 1);
stab.meanDwellSec = stab.meanDwellSteps * stepDurSec;
stab.dwellSec = dwellSteps(:) * stepDurSec;
stab.trialDurSec = trialDur;

end


function stepMeans = aggregateStepwiseMeanLocal(stepIdx, values, steps)
stepIdx = stepIdx(:);
values = values(:);
steps = steps(:);
stepMeans = NaN(size(steps));
for i = 1:numel(steps)
    mask = isfinite(stepIdx) & stepIdx == steps(i) & isfinite(values);
    if any(mask)
        stepMeans(i) = mean(values(mask), 'omitnan');
    end
end
end


function stepHasSaccade = aggregateStepwiseSaccadeLocal(stepIdx, steps, xPx, yPx, dtSec, setup)
steps = steps(:);
stepHasSaccade = false(size(steps));
[~, saccadeStops] = detectTrackingSaccadesCoPs(xPx, yPx, dtSec, setup);
if isempty(saccadeStops)
    return
end
saccadeStep = stepIdx(saccadeStops);
for i = 1:numel(steps)
    stepHasSaccade(i) = any(saccadeStep == steps(i));
end
end
