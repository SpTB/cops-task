function [assignedTarget, available, isThreeState] = ...
    assignHmmTrackingStateCoPs(methodHmm, stepIdx, twoStateThreshold)
% assignHmmTrackingStateCoPs  Convert stepwise HMM probabilities to states.
%
% State coding is NaN=no probability estimate, 0=non-tracking/unassigned,
% 1=TLeft, and 2=TRight.
%
% Three-state models are detected from finite pTLeft, pTRight, and
% pNonTracking vectors. They use strict winner-take-all assignment; exact
% ties are coded 0. Two-state models use twoStateThreshold.

stepIdx = double(stepIdx(:));
assignedTarget = nan(size(stepIdx));
available = false;
isThreeState = false;
if ~isstruct(methodHmm) || ~isfield(methodHmm, 'pTLeft')
    return
end

pTLeft = double(methodHmm.pTLeft(:));
validStep = isfinite(stepIdx) & stepIdx == round(stepIdx) & ...
    stepIdx >= 1 & stepIdx <= numel(pTLeft);
isThreeState = isfield(methodHmm, 'pTRight') && ...
    isfield(methodHmm, 'pNonTracking') && ...
    numel(methodHmm.pTRight) == numel(pTLeft) && ...
    numel(methodHmm.pNonTracking) == numel(pTLeft) && ...
    any(isfinite(double(methodHmm.pNonTracking(:))));

if isThreeState
    pTRight = double(methodHmm.pTRight(:));
    pNonTracking = double(methodHmm.pNonTracking(:));
    left = nan(size(stepIdx));
    right = nan(size(stepIdx));
    nonTracking = nan(size(stepIdx));
    left(validStep) = pTLeft(stepIdx(validStep));
    right(validStep) = pTRight(stepIdx(validStep));
    nonTracking(validStep) = pNonTracking(stepIdx(validStep));
    defined = isfinite(left) & isfinite(right) & isfinite(nonTracking);
    assignedTarget(defined) = 0;
    assignedTarget(defined & left > right & left > nonTracking) = 1;
    assignedTarget(defined & right > left & right > nonTracking) = 2;
    available = any(defined);
    return
end

threshold = double(twoStateThreshold);
if ~isscalar(threshold) || ~isfinite(threshold) || ...
        threshold < 0.5 || threshold > 1
    error('assignHmmTrackingStateCoPs:BadThreshold', ...
        'The two-state threshold must be a finite scalar between 0.5 and 1.');
end
values = nan(size(stepIdx));
values(validStep) = pTLeft(stepIdx(validStep));
assignedTarget(isfinite(values)) = 0;
assignedTarget(values > threshold) = 1;
assignedTarget((1 - values) > threshold) = 2;
available = any(isfinite(values));
end
