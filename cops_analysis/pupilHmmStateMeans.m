function out = pupilHmmStateMeans(ex, opts)
% pupilHmmStateMeans  Average normalized pupil size by HMM tracking state.
%
% out = pupilHmmStateMeans(ex)
% out = pupilHmmStateMeans(ex, opts)
%
% Uses the same HMM alignment and pupil preprocessing as
% pupilHmmTransitions. States are based on hardCloser:
%   nonTracking = 0; closer = 1; farther = 2; tracking = 1 or 2.
%
% The main outputs are:
%   out.summary     sample- and trial-weighted means for all four labels
%   out.trialMeans  one mean per trial and state
%   out.comparison  tracking-minus-nonTracking contrasts
%
% opts accepts the pupilHmmTransitions options. opts.makePlot (default true)
% controls this function's tracking/non-tracking plot. baselineWindowSec is
% irrelevant here because continuous pupil samples, rather than transition
% epochs, are summarized. Set opts.pairedOnly=true to retain only trials with
% usable tracking and non-tracking samples. Pupil remains robustly z-scored by
% session and eye. EyeCal position correction is enabled by default through
% pupilHmmTransitions; set opts.posCorrected=false to disable it.

if nargin < 2 || isempty(opts)
    opts = struct();
end
makePlot = true;
if isfield(opts, 'makePlot') && ~isempty(opts.makePlot)
    makePlot = logical(opts.makePlot);
end
transitionOpts = opts;
transitionOpts.makePlot = false;
base = pupilHmmTransitions(ex, transitionOpts);

out = base.statePupil;
out.meta = base.meta;
out.opts = base.opts;
out.figure = [];
if makePlot
    out.figure = localPlotStateMeans(out.trialMeans, out.summary, ...
        base.opts.hmmMethod, base.opts.pairedOnly);
end
end


function figureHandle = localPlotStateMeans( ...
        trialMeans, summary, hmmMethod, pairedOnly)
figureHandle = figure('Color', 'w', 'Name', 'Pupil size by HMM state');
hold on
states = ["nonTracking", "tracking"];
labels = ["Non-tracking", "Tracking"];
colors = [0.45 0.45 0.45; 0.15 0.55 0.75];
for i = 1:2
    selected = trialMeans.state == states(i) & isfinite(trialMeans.meanPupilZ);
    values = trialMeans.meanPupilZ(selected);
    if isempty(values)
        continue
    end
    boxchart(repmat(i, numel(values), 1), values, ...
        'BoxFaceColor', colors(i,:), 'MarkerStyle', 'none', ...
        'BoxWidth', 0.45, 'HandleVisibility', 'off');
    jitter = linspace(-0.12, 0.12, numel(values))';
    scatter(i + jitter, values, 18, colors(i,:), 'filled', ...
        'MarkerFaceAlpha', 0.16, 'MarkerEdgeAlpha', 0.10, ...
        'HandleVisibility', 'off');
    average = mean(values, 'omitnan');
    sem = std(values, 0, 'omitnan') / sqrt(numel(values));
    errorbar(i, average, sem, 'o', 'Color', colors(i,:), ...
        'MarkerFaceColor', colors(i,:), 'LineWidth', 2, 'CapSize', 12, ...
        'DisplayName', sprintf('%s (n=%d trials)', labels(i), numel(values)));
end
xlim([0.5 2.5]); xticks(1:2); xticklabels(labels);
yline(0, 'Color', [.65 .65 .65], 'HandleVisibility', 'off');
ylabel('Mean pupil size (session-eye SD)');
if pairedOnly
    title(sprintf('%s HMM state pupil means; paired trials only', hmmMethod));
else
    title(sprintf('%s HMM state pupil means', hmmMethod));
end
legend('Location', 'best'); grid on

% Put the sample-weighted values in the subtitle when supported.
nontracking = summary.state == "nonTracking";
tracking = summary.state == "tracking";
if any(nontracking) && any(tracking)
    difference = summary.sampleWeightedMeanPupilZ(tracking) - ...
        summary.sampleWeightedMeanPupilZ(nontracking);
    if exist('subtitle', 'file') == 2
        subtitle(sprintf('Sample-weighted tracking - non-tracking = %+.3f SD', ...
            difference));
    end
end
end
