function out = plotRewardSwitchProb(rewardSwitchTable, opts)
% plotRewardSwitchProb  Plot reward-aligned switch probability over time.
%
% out = plotRewardSwitchProb(tbl)
% out = plotRewardSwitchProb(tbl, opts)
%
% Inputs
%   rewardSwitchTable : out.rewardSwitch from processCoPsEye
%   opts              : optional struct with fields:
%       .windowSec     (default [-0.5 0.5])
%       .window        alias for .windowSec
%       .binWidthSec   (default 0.05)
%       .newFigure     (default true)
%       .lineColor     (default [0 0 0])
%       .lineWidth     (default 1.5)
%
% Output
%   out.tBinCenterSec : bin centers
%   out.switchProb    : probability of at least one switch per reward/bin
%   out.nRewards      : number of rewards included
%   out.binEdgesSec   : bin edges

if nargin < 2 || isempty(opts)
    opts = struct();
end

defaults = struct( ...
    'windowSec', [-0.5 0.5], ...
    'binWidthSec', 0.05, ...
    'newFigure', true, ...
    'lineColor', [0 0 0], ...
    'lineWidth', 1.5);
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

if ~istable(rewardSwitchTable) || isempty(rewardSwitchTable)
    error('plotRewardSwitchProb:InvalidTable', ...
        'rewardSwitchTable must be a non-empty table, typically out.rewardSwitch.');
end

requiredVars = {'trial', 'rewardNo', 'tFromRewardSec', 'hasSwitch'};
missingVars = setdiff(requiredVars, rewardSwitchTable.Properties.VariableNames, 'stable');
if ~isempty(missingVars)
    error('plotRewardSwitchProb:MissingVars', ...
        'Missing required columns: %s', strjoin(missingVars, ', '));
end

windowSec = double(opts.windowSec(:)');
if numel(windowSec) ~= 2 || ~all(isfinite(windowSec)) || windowSec(2) <= windowSec(1)
    error('plotRewardSwitchProb:BadWindow', ...
        'opts.windowSec must be a finite 1x2 increasing vector.');
end
binWidthSec = double(opts.binWidthSec);
if ~isscalar(binWidthSec) || ~isfinite(binWidthSec) || binWidthSec <= 0
    error('plotRewardSwitchProb:BadBinWidth', ...
        'opts.binWidthSec must be a finite positive scalar.');
end

binEdgesSec = windowSec(1):binWidthSec:windowSec(2);
if binEdgesSec(end) < windowSec(2)
    binEdgesSec(end+1) = windowSec(2); %#ok<AGROW>
end
tBinCenterSec = binEdgesSec(1:end-1) + diff(binEdgesSec) / 2;

[rewardGroup, rewardInfo] = findgroups(rewardSwitchTable(:, {'trial', 'rewardNo'}));
nRewards = height(rewardInfo);
if nRewards < 1
    error('plotRewardSwitchProb:NoRewards', 'No reward events found in rewardSwitchTable.');
end

rewardHasSwitch = false(nRewards, numel(tBinCenterSec));
for i = 1:nRewards
    T = rewardSwitchTable(rewardGroup == i, :);
    rel = double(T.tFromRewardSec);
    rel = rel(logical(T.hasSwitch) & isfinite(rel));
    if isempty(rel)
        continue
    end
    binIdx = discretize(rel, binEdgesSec);
    binIdx = unique(binIdx(isfinite(binIdx)));
    rewardHasSwitch(i, binIdx) = true;
end

switchProb = mean(rewardHasSwitch, 1, 'omitnan');

if opts.newFigure
    figure;
end
plot(tBinCenterSec, switchProb, 'Color', opts.lineColor, 'LineWidth', opts.lineWidth);
hold on
xline(0, ':', 'Color', [0.4 0.4 0.4]);
yline(0, ':', 'Color', [0.4 0.4 0.4]);
xlabel('Time From Reward Onset (s)');
ylabel('Switch Probability');
title(sprintf('Reward-aligned switch probability (n rewards = %d)', nRewards));
box off

out = struct();
out.tBinCenterSec = tBinCenterSec(:);
out.switchProb = switchProb(:);
out.nRewards = nRewards;
out.binEdgesSec = binEdgesSec(:);
out.rewardHasSwitch = rewardHasSwitch;
end
