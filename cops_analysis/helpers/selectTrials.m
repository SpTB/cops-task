function sel = selectTrials(ex, T, tAbs, xPx, yPx, valid, opts)

inBounds = false(numel(xPx),1);
if ~isempty(xPx) && isfield(ex,'setup') && isfield(ex.setup,'screenRect')
    sr = ex.setup.screenRect;
    inBounds = valid & xPx >= sr(1)-50 & xPx <= sr(3)+50 & yPx >= sr(2)-50 & yPx <= sr(4)+50;
end

inBoundsFrac = mean(inBounds, 'omitnan');
if isnan(inBoundsFrac)
    inBoundsFrac = 0;
end

minInBoundsFrac = opts.minInBoundsFrac;

rewardPoints= getfieldOrNaN(T, 'rewardAccumulated'); %#ok<GFLD>
%rewardPointsTab = calcRewPerTp(ex, xPx, yPx, targetX, targetY, target2X, target2Y, inBounds);
%rewardPoints = sum(rewardPointsTab.scaledReward)

if isnan(rewardPoints)
    rewardPoints = 0;
end

sel = struct();
sel.keepTrial = inBoundsFrac >= minInBoundsFrac && rewardPoints >= opts.minRewardPoints;
sel.inBounds = inBounds;
sel.inBoundsFrac = inBoundsFrac;
sel.rewardPoints = rewardPoints;
end


