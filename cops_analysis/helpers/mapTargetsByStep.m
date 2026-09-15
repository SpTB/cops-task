function [targetX, targetY, target2X, target2Y,stepIdx] = mapTargetsByStep(ex, T, tRel)
% Map each sample to active step target in absolute display coordinates.

nS = numel(tRel);
targetX = NaN(nS,1);
targetY = NaN(nS,1);
target2X = NaN(nS,1);
target2Y = NaN(nS,1);
stepIdx = NaN(nS,1);

if nS == 0 || ~isfield(T, 'targetPositions') || isempty(T.targetPositions)
    return
end

nsteps = getfieldOrNaN(T, 'nsteps');
if ~isfinite(nsteps) || nsteps < 1
    nsteps = numel(T.targetPositions);
end
nsteps = min(nsteps, numel(T.targetPositions));
stepIdx = computeStepIndices(ex, T, tRel);

for i = 1:nS
    s = stepIdx(i);
    if ~isfinite(s), s = 1; end
    s = max(1, min(nsteps, s));
    stepIdx(i) = s;

    tp = T.targetPositions(s);
    if isfield(tp, 'targ1') && isfield(tp.targ1, 'pos_abs') && numel(tp.targ1.pos_abs) >= 2
        targetX(i) = tp.targ1.pos_abs(1);
        targetY(i) = tp.targ1.pos_abs(2);
    end

    if isfield(tp, 'targ2') && isfield(tp.targ1, 'pos_abs') && numel(tp.targ2.pos_abs) >= 2
        target2X(i) = tp.targ2.pos_abs(1);
        target2Y(i) = tp.targ2.pos_abs(2);
    end

    % Keep targ1 in targetX/targetY; two-target handling is done in
    % computeDistanceToTargets by taking min(distance to targ1, targ2).
end
end
