function assign = assignTargetIdentityCoPs(distPx1, distPx2, inBounds, betweenMarginPx, stepIdx)
% Shared target-identity assignment for CoPs eye analysis.
%
% assignedSample:
%   1 = closer to target 1
%   2 = closer to target 2
%   0 = invalid / between targets
%
% assignedStep:
%   majority vote of non-zero sample assignments within each observed step.

distPx1 = distPx1(:);
distPx2 = distPx2(:);
inBounds = inBounds(:);

dd = abs(distPx1 - distPx2);
betweenSample = inBounds & isfinite(dd) & (dd <= betweenMarginPx);
validSample = inBounds & ~betweenSample & isfinite(distPx1) & isfinite(distPx2);

assignedSample = zeros(size(distPx1));
assignedSample(validSample & distPx1 < distPx2) = 1;
assignedSample(validSample & distPx2 < distPx1) = 2;

assign = struct();
assign.assignedSample = assignedSample;
assign.betweenSample = betweenSample;

if nargin < 5 || isempty(stepIdx)
    assign.step = zeros(0, 1);
    assign.assignedStep = zeros(0, 1);
    return
end

stepIdx = stepIdx(:);
goodStep = isfinite(stepIdx);
uStep = unique(stepIdx(goodStep));
uStep = uStep(:);
nStepObs = numel(uStep);
assignedStep = zeros(nStepObs, 1);

for k = 1:nStepObs
    m = (stepIdx == uStep(k));
    a = assignedSample(m);
    a = a(a > 0);
    if isempty(a)
        continue
    end
    n1 = sum(a == 1);
    n2 = sum(a == 2);
    if n1 > n2
        assignedStep(k) = 1;
    elseif n2 > n1
        assignedStep(k) = 2;
    end
end

assign.step = uStep;
assign.assignedStep = assignedStep;
end
