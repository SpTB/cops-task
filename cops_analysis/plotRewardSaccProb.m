function out = plotRewardSaccProb(rewardSaccTable, opts)
% plotRewardSaccProb  Plot reward-aligned saccade probability over time.
%
%   out = plotRewardSaccProb(tbl)
%   out = plotRewardSaccProb(tbl, opts)
%
% Inputs
%   rewardSaccTable : out.rewardSaccades from rewardTriggeredSaccades()
%   opts            : optional struct with fields:
%       .windowSec   (default [-0.5 0.5])
%       .window      alias for .windowSec
%       .binWidthSec (default 0.05)
%       .newFigure   (default true)
%       .lineColor   (default [0 0 0])
%       .lineWidth   (default 1.5)
%       .showDecor   (default true)
%
% Output
%   out.tBinCenterSec : bin centers
%   out.saccProb      : probability of at least one saccade per reward/bin
%   out.nRewards      : number of rewards included
%   out.binEdgesSec   : bin edges

if nargin < 2 || isempty(opts)
    opts = struct();
end

defaults = struct( ...
    'windowSec', [-0.5 2.5], ...
    'binWidthSec', 0.05, ...
    'newFigure', true, ...
    'lineColor', [0 0 0], ...
    'lineWidth', 1.5, ...
    'showDecor', true);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field)
        opts.(field) = defaults.(field);
    end
end

if isfield(opts, 'window') && ~isempty(opts.window)
    opts.windowSec = opts.window;
end

if ~istable(rewardSaccTable) || isempty(rewardSaccTable)
    error('plotRewardSaccProb:InvalidTable', ...
        'rewardSaccTable must be a non-empty table, typically out.rewardSaccades.');
end

requiredVars = {'trial', 'rewardNo', 'tFromRewardSec', 'hasSaccade'};
missingVars = setdiff(requiredVars, rewardSaccTable.Properties.VariableNames, 'stable');
if ~isempty(missingVars)
    error('plotRewardSaccProb:MissingVars', ...
        'Missing required columns: %s', strjoin(missingVars, ', '));
end

windowSec = double(opts.windowSec(:)');
if numel(windowSec) ~= 2 || ~all(isfinite(windowSec)) || windowSec(2) <= windowSec(1)
    error('plotRewardSaccProb:BadWindow', ...
        'opts.windowSec must be a finite 1x2 increasing vector.');
end
binWidthSec = double(opts.binWidthSec);
if ~isscalar(binWidthSec) || ~isfinite(binWidthSec) || binWidthSec <= 0
    error('plotRewardSaccProb:BadBinWidth', ...
        'opts.binWidthSec must be a finite positive scalar.');
end

binEdgesSec = windowSec(1):binWidthSec:windowSec(2);
if binEdgesSec(end) < windowSec(2)
    binEdgesSec(end+1) = windowSec(2); %#ok<AGROW>
end
tBinCenterSec = binEdgesSec(1:end-1) + diff(binEdgesSec) / 2;

[rewardGroup, rewardInfo] = findgroups(rewardSaccTable(:, {'trial', 'rewardNo'}));
nRewards = height(rewardInfo);
if nRewards < 1
    error('plotRewardSaccProb:NoRewards', 'No reward events found in rewardSaccTable.');
end

rewardHasSacc = false(nRewards, numel(tBinCenterSec));
for i = 1:nRewards
    T = rewardSaccTable(rewardGroup == i, :);
    rel = double(T.tFromRewardSec);
    rel = rel(logical(T.hasSaccade) & isfinite(rel));
    if isempty(rel)
        continue
    end
    binIdx = discretize(rel, binEdgesSec);
    binIdx = unique(binIdx(isfinite(binIdx)));
    rewardHasSacc(i, binIdx) = true;
end

saccProb = mean(rewardHasSacc, 1, 'omitnan');

if opts.newFigure
    figure;
end
plot(tBinCenterSec, saccProb, 'Color', opts.lineColor, 'LineWidth', opts.lineWidth);
hold on
if logical(opts.showDecor)
    xline(0, ':', 'Color', [0.4 0.4 0.4]);
    yline(0, ':', 'Color', [0.4 0.4 0.4]);
    xlabel('Time From Reward Onset (s)');
    ylabel('Saccade Probability');
    title(sprintf('Reward-aligned saccade probability (n rewards = %d)', nRewards));
    box off
end

out = struct();
out.tBinCenterSec = tBinCenterSec(:);
out.saccProb = saccProb(:);
out.nRewards = nRewards;
out.binEdgesSec = binEdgesSec(:);
out.rewardHasSacc = rewardHasSacc;
end
