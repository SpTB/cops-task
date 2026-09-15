function rewTS = calcRewPerTp(ex, xPx, yPx, targetX, targetY, target2X, target2Y, inBounds, trial)
% Recompute reward components per sample from offline traces.
%
% Mirrors the online reward logic in runTrialTaskCoPsx.m:
%   closeness = max(closeness to targ1, closeness to targ2)
%   scaledReward = closeness * precision_weight + gauss_reward * (1-precision_weight)
%
% If gaussian reward map parameters are unavailable, gauss_reward is set to 0.

rewTS = struct();
rewTS.closeness = NaN(size(xPx));
rewTS.gaussReward = zeros(size(xPx));
rewTS.scaledReward = NaN(size(xPx));

ctl = ex.exp.CoPs.ctl;
graph=ex.exp.CoPs.graph;
rew = ex.exp.CoPs.rew;
if isfield(ctl, 'reward_type') && ~isempty(ctl.reward_type)
    rewardType = ctl.reward_type;
else
    % Backward compatibility for older CoPs sessions that predate the
    % explicit reward_type field.
    rewardType = 'mult';
end

if strcmp(rewardType, 'mult')
    if isfield(ctl, 'gauss_scalar') && ~isempty(ctl.gauss_scalar)
        precision_param = ctl.gauss_scalar;
    else
        precision_param = 1;
    end
else
    if isfield(ctl, 'precision_weight') && ~isempty(ctl.precision_weight)
        precision_param = ctl.precision_weight;
    else
        precision_param = 0.5;
    end
end
maxDistanceReward = ctl.max_dist_mult * graph.radius * graph.size_mult;
gaussDim = graph.texture_dims(1) * graph.size_mult;
gaussCenterPx = resolveGaussCenterPx(ex, gaussDim, trial);
rewardMat = gauss_rew_land(gaussDim, gaussCenterPx, rew.gauss_sigma);
xshift = (ex.setup.screenRect(3) - gaussDim) / 2;
yshift = (ex.setup.screenRect(4) - gaussDim) / 2;
%hasGauss = true;

d1 = hypot(xPx - targetX, yPx - targetY);
d2 = hypot(xPx - target2X, yPx - target2Y);
dMin = d1;
useT2 = isfinite(d2) & ((~isfinite(d1)) | d2 < d1);
dMin(useT2) = d2(useT2);

closeness = 1 - (dMin ./ maxDistanceReward);
closeness = max(0, min(1, closeness));

gaussReward = zeros(size(xPx));
relX = round(xPx - xshift);
relY = round(yPx - yshift);
onMap = inBounds & relX >= 1 & relX <= size(rewardMat,2) & relY >= 1 & relY <= size(rewardMat,1);
linIdx = sub2ind(size(rewardMat), relY(onMap), relX(onMap));
gaussReward(onMap) = rewardMat(linIdx);

if strcmp(rewardType, 'mult')
    scaledReward = closeness * precision_param;
else
    scaledReward = closeness * precision_param + gaussReward * (1 - precision_param);
end

scaledReward(~inBounds) = 0;
closeness(~inBounds) = 0;

rewTS.closeness = closeness;
rewTS.gaussReward = gaussReward;
rewTS.scaledReward = scaledReward;

end

function centerPx = resolveGaussCenterPx(ex, gaussDim, trial)
if nargin < 3
    trial = struct();
end

if isfield(trial, 'gaussRewardCenterNorm') && numel(trial.gaussRewardCenterNorm) == 2 ...
        && all(isfinite(trial.gaussRewardCenterNorm))
    centerNorm = trial.gaussRewardCenterNorm(:)';
else
    rew = ex.exp.CoPs.rew;
    if isfield(rew, 'gauss_center_positions_norm') && ~isempty(rew.gauss_center_positions_norm)
        nCenters = size(rew.gauss_center_positions_norm, 1);
        idx = 1;
        if isfield(rew, 'gauss_center_idx') && isfinite(rew.gauss_center_idx)
            idx = max(1, min(nCenters, round(rew.gauss_center_idx)));
        end
        centerNorm = rew.gauss_center_positions_norm(idx, :);
    else
        centerNorm = [0.5, 0.5];
    end
end

centerPx = round(centerNorm .* (gaussDim - 1)) + 1;
centerPx = max(1, min(gaussDim, centerPx));
end
