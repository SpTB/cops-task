function out = rewardDistanceAccumulatorCoPs(mode, varargin)
% rewardDistanceAccumulatorCoPs
% Stateful helpers for pooled reward-vs-distance summaries.
%
% Usage:
%   acc = rewardDistanceAccumulatorCoPs('init', nBins, maxDistPx)
%   acc = rewardDistanceAccumulatorCoPs('update', acc, dist, reward)
%   curve = rewardDistanceAccumulatorCoPs('finalize', acc)

switch lower(mode)
    case 'init'
        nBins = varargin{1};
        maxDistPx = varargin{2};
        out = initAccumulator(nBins, maxDistPx);
    case 'update'
        acc = varargin{1};
        dist = varargin{2};
        reward = varargin{3};
        out = updateAccumulator(acc, dist, reward);
    case 'finalize'
        acc = varargin{1};
        out = finalizeAccumulator(acc);
    otherwise
        error('Unknown mode "%s". Expected init/update/finalize.', mode);
end
end

function acc = initAccumulator(nBins, maxDistPx)
edges = linspace(0, maxDistPx, nBins + 1);
acc = struct();
acc.binEdgesPx = edges;
acc.binCentersPx = (edges(1:end-1) + edges(2:end)) / 2;
acc.rewardSum = zeros(nBins, 1);
acc.nPerBin = zeros(nBins, 1);
end

function acc = updateAccumulator(acc, dist, reward)
if isempty(dist) || isempty(reward)
    return
end
valid = isfinite(dist) & isfinite(reward);
if ~any(valid)
    return
end
dist = dist(valid);
reward = reward(valid);
[~,~,bin] = histcounts(dist, acc.binEdgesPx);
inBin = bin > 0;
if ~any(inBin)
    return
end
bin = bin(inBin);
reward = reward(inBin);
acc.rewardSum = acc.rewardSum + accumarray(bin, reward, [numel(acc.rewardSum) 1], @sum, 0);
acc.nPerBin = acc.nPerBin + accumarray(bin, 1, [numel(acc.nPerBin) 1], @sum, 0);
end

function curve = finalizeAccumulator(acc)
curve = struct('binEdgesPx', acc.binEdgesPx, ...
    'binCentersPx', acc.binCentersPx, ...
    'meanReward', NaN(size(acc.nPerBin)), ...
    'nPerBin', acc.nPerBin);
hasData = acc.nPerBin > 0;
curve.meanReward(hasData) = acc.rewardSum(hasData) ./ acc.nPerBin(hasData);
end