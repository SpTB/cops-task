function out = plotRewardSaccErr(rewardSaccTable, opts)
% plotRewardSaccErr  Plot reward-aligned saccade endpoint error over time.
%
%   out = plotRewardSaccErr(tbl)
%   out = plotRewardSaccErr(tbl, opts)
%
% Inputs
%   rewardSaccTable : out.rewardSaccades from rewardTriggeredSaccades()
%   opts            : optional struct with fields:
%       .windowSec   (default [-0.5 0.5])
%       .window      alias for .windowSec
%       .binWidthSec (default 0.05)
%       .errField    (default 'saccErrDeg')
%       .stat        (default 'mean') one of: 'mean', 'median'
%       .newFigure   (default true)
%       .lineColor   (default [0 0 0])
%       .lineWidth   (default 1.5)
%       .showDecor   (default true)
%
% Output
%   out.tBinCenterSec : bin centers
%   out.errTrace      : binned error statistic
%   out.nSaccPerBin   : number of saccades contributing to each bin
%   out.nRewards      : number of rewards included
%   out.binEdgesSec   : bin edges

if nargin < 2 || isempty(opts)
    opts = struct();
end

defaults = struct( ...
    'windowSec', [-0.5 2.5], ...
    'binWidthSec', 0.05, ...
    'errField', 'saccErrDeg', ...
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
    error('plotRewardSaccErr:InvalidTable', ...
        'rewardSaccTable must be a non-empty table, typically out.rewardSaccades.');
end

requiredVars = {'trial', 'rewardNo', 'tFromRewardSec', 'hasSaccade'};
missingVars = setdiff(requiredVars, rewardSaccTable.Properties.VariableNames, 'stable');
if ~isempty(missingVars)
    error('plotRewardSaccErr:MissingVars', ...
        'Missing required columns: %s', strjoin(missingVars, ', '));
end
errField = char(string(opts.errField));
if ~ismember(errField, rewardSaccTable.Properties.VariableNames)
    error('plotRewardSaccErr:MissingErrField', ...
        'Error field ''%s'' not found in rewardSaccTable.', errField);
end

windowSec = double(opts.windowSec(:)');
if numel(windowSec) ~= 2 || ~all(isfinite(windowSec)) || windowSec(2) <= windowSec(1)
    error('plotRewardSaccErr:BadWindow', ...
        'opts.windowSec must be a finite 1x2 increasing vector.');
end
binWidthSec = double(opts.binWidthSec);
if ~isscalar(binWidthSec) || ~isfinite(binWidthSec) || binWidthSec <= 0
    error('plotRewardSaccErr:BadBinWidth', ...
        'opts.binWidthSec must be a finite positive scalar.');
end
statName = validatestring(char(string(opts.stat)), {'mean', 'median'});

binEdgesSec = windowSec(1):binWidthSec:windowSec(2);
if binEdgesSec(end) < windowSec(2)
    binEdgesSec(end+1) = windowSec(2); %#ok<AGROW>
end
tBinCenterSec = binEdgesSec(1:end-1) + diff(binEdgesSec) / 2;

[rewardGroup, rewardInfo] = findgroups(rewardSaccTable(:, {'trial', 'rewardNo'})); %#ok<ASGLU>
nRewards = height(rewardInfo);
if nRewards < 1
    error('plotRewardSaccErr:NoRewards', 'No reward events found in rewardSaccTable.');
end

errTrace = NaN(1, numel(tBinCenterSec));
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
    x = double(rewardSaccTable.(errField)(keep));
    x = x(isfinite(x));
    nSaccPerBin(b) = numel(x);
    if isempty(x)
        continue
    end
    switch statName
        case 'mean'
            errTrace(b) = mean(x, 'omitnan');
        case 'median'
            errTrace(b) = median(x, 'omitnan');
    end
end

if opts.newFigure
    figure;
end
plot(tBinCenterSec, errTrace, 'Color', opts.lineColor, 'LineWidth', opts.lineWidth);
hold on
if logical(opts.showDecor)
    xline(0, ':', 'Color', [0.4 0.4 0.4]);
    yline(0, ':', 'Color', [0.4 0.4 0.4]);
    xlabel('Time From Reward Onset (s)');
    ylabel(sprintf('%s (%s)', errField, statName));
    title(sprintf('Reward-aligned saccade endpoint error (n rewards = %d)', nRewards));
    box off
end

out = struct();
out.tBinCenterSec = tBinCenterSec(:);
out.errTrace = errTrace(:);
out.nSaccPerBin = nSaccPerBin(:);
out.nRewards = nRewards;
out.binEdgesSec = binEdgesSec(:);
out.errField = string(errField);
out.stat = string(statName);
end
