function summary = summarizeCoPsValidationCheckx(ex)
% Use the same accepted time window and mean estimator as normal validation.
summary = table();
if ~isfield(ex, 'Trials'), return; end
labels = {'RX'; 'RY'; 'LX'; 'LY'};
rows = [1 2 4 5]; axes = [1 2 1 2];
if isempty(ex.eyeCal.LXPos)
    labels = labels(1:2); rows = rows(1:2); axes = axes(1:2);
end
for k = 1:numel(ex.Trials)
    trial = ex.Trials(k);
    t = trial.Eye.t - trial.TrialStartDatapixx;
    selected = false(size(t));
    if ~isempty(t)
        if trial.Reward
            selected = t >= trial.times.reward - 0.15 & t <= trial.times.reward - 0.05;
        elseif isfinite(trial.times.startFixation)
            selected = t >= trial.times.startFixation + 0.05 & ...
                t <= min(t(end) - 0.01, trial.times.startFixation + 0.15);
        end
    end
    for j = 1:numel(labels)
        channel = labels(j); nSamples = nnz(selected);
        meanV = NaN; errorPx = NaN; sdPx = NaN;
        if nSamples >= 20
            v = trial.Eye.v(rows(j), selected);
            meanV = mean(v, 'omitnan');
            prefix = labels{j};
            delta = ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).([prefix '0']);
            gain = ex.eyeCal.([prefix 'Gain']);
            errorPx = (meanV - ex.eyeCal.([prefix '0']) - delta) * gain ...
                - trial.targ.Pos(axes(j));
            sdPx = std(v, 'omitnan') * abs(gain);
        end
        row = table(k, trial.targ.Pos(1), trial.targ.Pos(2), logical(trial.Reward), ...
            channel, nSamples, meanV, errorPx, sdPx, ...
            'VariableNames', {'trial', 'targetXpx', 'targetYpx', 'reward', ...
            'channel', 'nSamples', 'meanV', 'errorPx', 'sdPx'});
        summary = [summary; row]; %#ok<AGROW>
    end
end
end
