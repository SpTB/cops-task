function out = plotTrackEpi(trackingTable, axisName, trialNo, intervalNo, opts)
% plotTrackEpi  Plot one tracking episode from out.tracking.
%
% out = plotTrackEpi(t, 'x')
% out = plotTrackEpi(t, 'x', 2, 15)
% out = plotTrackEpi(t, 'y', 2, 15)
% out = plotTrackEpi(t, 'xy', 2, 15)
%
% Inputs
%   trackingTable : out.tracking from processCoPsEye
%   axisName      : 'x' (default), 'y', or 'xy'
%   trialNo       : trial number; if omitted, a random available episode
%                   is chosen
%   intervalNo    : interval number within that trial
%   opts          : optional struct with fields:
%       .newFigure   (default true)
%       .gazeColor   (default [0 0.45 0.74])
%       .targetColor (default [0 0 0])
%       .lineWidth   (default 1.5)
%
% Output
%   out.episodeTable : rows for the selected episode
%   out.episodeInfo  : one-row table identifying the episode
%   out.trialNo      : selected trial number
%   out.intervalNo   : selected interval number
%   out.axisName     : plotted axis mode

if nargin < 2 || isempty(axisName)
    axisName = 'x';
end
if nargin < 5 || isempty(opts)
    if nargin >= 4 && isstruct(intervalNo)
        opts = intervalNo;
        intervalNo = [];
    elseif nargin >= 3 && isstruct(trialNo)
        opts = trialNo;
        trialNo = [];
        intervalNo = [];
    else
        opts = struct();
    end
end

axisName = validatestring(char(string(axisName)), {'x', 'y', 'xy'});

defaults = struct( ...
    'newFigure', true, ...
    'gazeColor', [0 0.45 0.74], ...
    'targetColor', [0 0 0], ...
    'lineWidth', 1.5);
defaultFields = fieldnames(defaults);
for i = 1:numel(defaultFields)
    field = defaultFields{i};
    if ~isfield(opts, field)
        opts.(field) = defaults.(field);
    end
end

if ~istable(trackingTable) || isempty(trackingTable)
    error('plotTrackEpi:InvalidTrackingTable', ...
        'trackingTable must be a non-empty table, typically out.tracking.');
end

requiredVars = {'trial', 'intervalNo', 'xPx', 'yPx', 'trackedTargetX', 'trackedTargetY'};
missingVars = setdiff(requiredVars, trackingTable.Properties.VariableNames, 'stable');
if ~isempty(missingVars)
    error('plotTrackEpi:MissingVars', ...
        'Missing required tracking columns: %s', strjoin(missingVars, ', '));
end

groupVars = {'trial', 'intervalNo'};
[groupIdx, episodeInfo] = findgroups(trackingTable(:, groupVars));
nEpisodes = height(episodeInfo);
if nEpisodes < 1
    error('plotTrackEpi:NoEpisodes', ...
        'trackingTable does not contain any episodes.');
end

if nargin < 3 || isempty(trialNo)
    pickIdx = randi(nEpisodes);
elseif nargin < 4 || isempty(intervalNo)
    error('plotTrackEpi:MissingIntervalNo', ...
        'If trialNo is specified, intervalNo must also be specified.');
else
    trialNo = double(trialNo);
    intervalNo = double(intervalNo);
    if ~isscalar(trialNo) || ~isfinite(trialNo) || trialNo ~= round(trialNo)
        error('plotTrackEpi:BadTrialNo', ...
            'trialNo must be a finite integer.');
    end
    if ~isscalar(intervalNo) || ~isfinite(intervalNo) || intervalNo ~= round(intervalNo)
        error('plotTrackEpi:BadIntervalNo', ...
            'intervalNo must be a finite integer.');
    end
    pickIdx = find(double(episodeInfo.trial) == trialNo & double(episodeInfo.intervalNo) == intervalNo, 1, 'first');
    if isempty(pickIdx)
        error('plotTrackEpi:EpisodeNotFound', ...
            'No tracking episode found for trial %d, interval %d.', trialNo, intervalNo);
    end
end

episodeTable = trackingTable(groupIdx == pickIdx, :);
if isempty(episodeTable)
    error('plotTrackEpi:EmptyEpisode', ...
        'No rows found for the requested episode.');
end

if ismember('sampleIdx', episodeTable.Properties.VariableNames)
    [~, order] = sort(double(episodeTable.sampleIdx), 'ascend');
    episodeTable = episodeTable(order, :);
elseif ismember('tRelSec', episodeTable.Properties.VariableNames)
    [~, order] = sort(double(episodeTable.tRelSec), 'ascend');
    episodeTable = episodeTable(order, :);
end

if ismember('tFromTrackingOnsetSec', episodeTable.Properties.VariableNames)
    xTime = double(episodeTable.tFromTrackingOnsetSec);
    xLabel = 'Time From Tracking Onset (s)';
elseif ismember('tRelSec', episodeTable.Properties.VariableNames)
    xTime = double(episodeTable.tRelSec);
    xLabel = 'Trial Time (s)';
else
    xTime = (1:height(episodeTable))';
    xLabel = 'Sample';
end

if opts.newFigure
    figure;
end

switch axisName
    case 'x'
        plotOneAxis(xTime, double(episodeTable.xPx), double(episodeTable.trackedTargetX), ...
            'X Position (px)', opts);
    case 'y'
        plotOneAxis(xTime, double(episodeTable.yPx), double(episodeTable.trackedTargetY), ...
            'Y Position (px)', opts);
    case 'xy'
        ax1 = subplot(2, 1, 1);
        plotOneAxis(xTime, double(episodeTable.xPx), double(episodeTable.trackedTargetX), ...
            'X Position (px)', opts);
        ax2 = subplot(2, 1, 2);
        plotOneAxis(xTime, double(episodeTable.yPx), double(episodeTable.trackedTargetY), ...
            'Y Position (px)', opts);
end

if strcmp(axisName, 'xy')
    linkaxes([ax1, ax2], 'x');
    xlabel(ax2, xLabel);
else
    xlabel(xLabel);
end

sgtitle(sprintf('Tracking Episode: trial %d, interval %d', ...
    episodeInfo.trial(pickIdx), episodeInfo.intervalNo(pickIdx)));

out = struct();
out.episodeTable = episodeTable;
out.episodeInfo = episodeInfo(pickIdx, :);
out.trialNo = double(episodeInfo.trial(pickIdx));
out.intervalNo = double(episodeInfo.intervalNo(pickIdx));
out.axisName = axisName;
end


function plotOneAxis(xTime, gazePos, targetPos, yLabelText, opts)
plot(xTime, targetPos, 'Color', opts.targetColor, 'LineWidth', opts.lineWidth);
hold on
plot(xTime, gazePos, 'Color', opts.gazeColor, 'LineWidth', opts.lineWidth);
if any(isfinite(xTime) & xTime == 0)
    xline(0, ':', 'Color', [0.4 0.4 0.4]);
end
ylabel(yLabelText);
legend({'Tracked target', 'Gaze'}, 'Location', 'best');
box off
end
