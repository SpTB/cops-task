function ctr = getGaussianCenterPx(ex, T)
graph = ex.exp.CoPs.graph;
rew = ex.exp.CoPs.rew;
gaussDim = graph.texture_dims(1) * graph.size_mult;
xshift = (ex.setup.screenRect(3) - gaussDim) / 2;
yshift = (ex.setup.screenRect(4) - gaussDim) / 2;

if nargin > 1 && isfield(T, 'gaussRewardCenterNorm') && numel(T.gaussRewardCenterNorm) == 2 ...
        && all(isfinite(T.gaussRewardCenterNorm))
    ctrNorm = T.gaussRewardCenterNorm(:)';
else
    ctrNorm = [0.5, 0.5];
    if isfield(rew, 'gauss_center_positions_norm') && ~isempty(rew.gauss_center_positions_norm)
        idx = 1;
        if isfield(rew, 'gauss_center_idx') && isfinite(rew.gauss_center_idx)
            nCenters = size(rew.gauss_center_positions_norm, 1);
            idx = max(1, min(nCenters, round(rew.gauss_center_idx)));
        end
        ctrNorm = rew.gauss_center_positions_norm(idx, :);
    end
end

centerInMapPx = round(ctrNorm .* (gaussDim - 1)) + 1;
centerInMapPx = max(1, min(gaussDim, centerInMapPx));
ctr = [xshift + centerInMapPx(1), yshift + centerInMapPx(2)];
