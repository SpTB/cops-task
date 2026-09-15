function out = plotRewardSaccVel(rewardSaccTable, opts)
% plotRewardSaccVel  Plot reward-aligned saccade velocity over time.
%
%   out = plotRewardSaccVel(tbl)
%   out = plotRewardSaccVel(tbl, opts)

if nargin < 2 || isempty(opts)
    opts = struct();
end

defaults = struct( ...
    'windowSec', [-0.5 2.5], ...
    'binWidthSec', 0.05, ...
    'velField', 'peakSpeedDegPerSec', ...
    'stat', 'mean', ...
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
    error('plotRewardSaccVel:InvalidTable', ...
        'rewardSaccTable must be a non-empty table, typically out.rewardSaccades.');
end

requiredVars = {'trial', 'rewardNo', 'tFromRewardSec', 'hasSaccade'};
missingVars = setdiff(requiredVars, rewardSaccTable.Properties.VariableNames, 'stable');
if ~isempty(missingVars)
    error('plotRewardSaccVel:MissingVars', ...
        'Missing required columns: %s', strjoin(missingVars, ', '));
end
velField = char(string(opts.velField));
if ~ismember(velField, rewardSaccTable.Properties.VariableNames)
    error('plotRewardSaccVel:MissingVelField', ...
        'Velocity field ''%s'' not found in rewardSaccTable.', velField);
end

windowSec = double(opts.windowSec(:)');
if numel(windowSec) ~= 2 || ~all(isfinite(windowSec)) || windowSec(2) <= windowSec(1)
    error('plotRewardSaccVel:BadWindow', ...
        'opts.windowSec must be a finite 1x2 increasing vector.');
end
binWidthSec = double(opts.binWidthSec);
if ~isscalar(binWidthSec) || ~isfinite(binWidthSec) || binWidthSec <= 0
    error('plotRewardSaccVel:BadBinWidth', ...
        'opts.binWidthSec must be a finite positive scalar.');
end
statName = validatestring(char(string(opts.stat)), {'mean', 'median'});

binEdgesSec = windowSec(1):binWidthSec:windowSec(2);
if binEdgesSec(end) < windowSec(2)
    binEdgesSec(end+1) = windowSec(2); %#ok<AGROW>
end
tBinCenterSec = binEdgesSec(1:end-1) + diff(binEdgesSec) / 2;

[~, rewardInfo] = findgroups(rewardSaccTable(:, {'trial', 'rewardNo'}));
nRewards = height(rewardInfo);
if nRewards < 1
    error('plotRewardSaccVel:NoRewards', 'No reward events found in rewardSaccTable.');
end

velTrace = NaN(1, numel(tBinCenterSec));
nSaccPerBin = zeros(1, numel(tBinCenterSec));
for b = 1:numel(tBinCenterSec)
    leftEdge = binEdgesSec(b);
    rightEdge = binEdgesSec(b + 1);
    keep = logical(rewardSaccTable.hasSaccade) & ...
        isfinite(rewardSaccTable.tFromRewardSec) & ...
        double(rewardSaccTable.tFromRewardSec) >= leftEdge & ...
        double(rewardSaccTable.tFromRewardSec) < rightEdge;
    if b == numel(tBinCenterSec)
        keep = keep | (logical(rewardSaccTable.hasSaccade) & isfinite(rewardSaccTable.tFromRewardSec) & ...
            double(rewardSaccTable.tFromRewardSec) == rightEdge);
    end
    x = double(rewardSaccTable.(velField)(keep));
    x = x(isfinite(x));
    nSaccPerBin(b) = numel(x);
    if isempty(x)
        continue
    end
    switch statName
        case 'mean'
            velTrace(b) = mean(x, 'omitnan');
        case 'median'
            velTrace(b) = median(x, 'omitnan');
    end
end

if opts.newFigure
    figure;
end
plot(tBinCenterSec, velTrace, 'Color', opts.lineColor, 'LineWidth', opts.lineWidth);
hold on
if logical(opts.showDecor)
    xline(0, ':', 'Color', [0.4 0.4 0.4]);
    yline(0, ':', 'Color', [0.4 0.4 0.4]);
    xlabel('Time From Reward Onset (s)');
    ylabel(sprintf('%s (%s)', velField, statName));
    title(sprintf('Reward-aligned saccade velocity (n rewards = %d)', nRewards));
    box off
end

out = struct();
out.tBinCenterSec = tBinCenterSec(:);
out.velTrace = velTrace(:);
out.nSaccPerBin = nSaccPerBin(:);
out.nRewards = nRewards;
out.binEdgesSec = binEdgesSec(:);
out.velField = string(velField);
out.stat = string(statName);
end
