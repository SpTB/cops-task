function hFig = plotCalibFunc(exOrFile, figNumber)
% plotCalib
% Plot calibration validation from the current vsg experiment format.
%
% Usage:
%   plotCalib(ex)
%   plotCalib('/path/to/file.mat')
%   plotCalib(ex, 2)

arguments
    exOrFile
    figNumber (1,1) double = 1
end

if isstruct(exOrFile)
    ex = exOrFile;
elseif ischar(exOrFile) || isstring(exOrFile)
    loaded = load(char(exOrFile), 'ex');
    if ~isfield(loaded, 'ex')
        error('plotCalib:MissingEx', ...
            'The file must contain variable ''ex''.');
    end
    ex = loaded.ex;
else
    error('plotCalib:InvalidInput', ...
        'Input must be an ex struct or a .mat file path.');
end

nTrials = numel(ex.Trials);
dpp = atan((ex.setup.monitorWidth / 2) / ex.setup.viewingDistance) * 180 / pi / ...
    (ex.setup.screenRect(3) / 2);

targPx = nan(nTrials, 2);
targDeg = nan(nTrials, 2);
rRaw = nan(nTrials, 2);
lRaw = nan(nTrials, 2);
rDeg = nan(nTrials, 2);
lDeg = nan(nTrials, 2);
reward = nan(nTrials, 1);

for iT = 1:nTrials
    Trial = ex.Trials(iT);
    targPx(iT, :) = Trial.targ.Pos(1:2);
    targDeg(iT, :) = targPx(iT, :) * dpp;
    reward(iT) = Trial.Reward;

    t = Trial.Eye.t - Trial.TrialStartDatapixx;
    if Trial.Reward
        idx = t >= Trial.times.reward - 0.15 & t <= Trial.times.reward - 0.05;
    else
        idx = t >= Trial.times.startFixation + 0.05 & ...
            t <= min([t(end) - 0.01, Trial.times.startFixation + 0.15]);
    end

    v = mean(Trial.Eye.v(:, idx), 2, 'omitnan');
    rRaw(iT, :) = v(1:2);
    rDeg(iT, :) = [(v(1) - ex.eyeCal.RX0) * ex.eyeCal.RXGain, ...
                   (v(2) - ex.eyeCal.RY0) * ex.eyeCal.RYGain] * dpp;

    if size(Trial.Eye.v, 1) > 3
        lRaw(iT, :) = v(4:5);
        lDeg(iT, :) = [(v(4) - ex.eyeCal.LX0) * ex.eyeCal.LXGain, ...
                       (v(5) - ex.eyeCal.LY0) * ex.eyeCal.LYGain] * dpp;
    end
end

rErr = rDeg - targDeg;
lErr = lDeg - targDeg;
lim = ceil(max(abs([targDeg(:); rDeg(:); lDeg(:)]), [], 'omitnan')) + 1;

hFig = figure(figNumber); clf
tiledlayout(2,2,'TileSpacing','compact','Padding','compact')

nexttile; hold on
plot([-lim lim], [-lim lim], 'k-')
scatter(targDeg(:,1), rDeg(:,1), 36, 'r', 'filled')
scatter(targDeg(:,1), lDeg(:,1), 36, 'b')
axis square
xlim([-lim lim]); ylim([-lim lim])
xlabel('Target X (deg)')
ylabel('Measured X (deg)')
title(sprintf('X   RMSE R=%.2f', sqrt(mean(rErr(:,1).^2, 'omitnan'))))

nexttile; hold on
plot([-lim lim], [-lim lim], 'k-')
scatter(targDeg(:,2), rDeg(:,2), 36, 'r', 'filled')
scatter(targDeg(:,2), lDeg(:,2), 36, 'b')
axis square
xlim([-lim lim]); ylim([-lim lim])
xlabel('Target Y (deg)')
ylabel('Measured Y (deg)')
title(sprintf('Y   RMSE R=%.2f', sqrt(mean(rErr(:,2).^2, 'omitnan'))))

nexttile; hold on
plot([-lim lim], [0 0], 'k-')
plot([0 0], [-lim lim], 'k-')
scatter(targDeg(:,1), targDeg(:,2), 70, 'k')
scatter(rDeg(:,1), rDeg(:,2), 36, 'r', 'filled')
scatter(lDeg(:,1), lDeg(:,2), 36, 'b')
axis square
xlim([-lim lim]); ylim([-lim lim])
xlabel('X (deg)')
ylabel('Y (deg)')
title('Target and measured position')

nexttile; hold on
plot([-lim lim], [0 0], 'k-')
plot([0 0], [-lim lim], 'k-')
scatter(rErr(:,1), rErr(:,2), 36, 'r', 'filled')
scatter(lErr(:,1), lErr(:,2), 36, 'b')
axis square
xlim([-lim lim]); ylim([-lim lim])
xlabel('X error (deg)')
ylabel('Y error (deg)')
title(sprintf('Bias R = [%.2f %.2f] deg', ...
    mean(rErr(:,1), 'omitnan'), mean(rErr(:,2), 'omitnan')))

sgtitle(sprintf('%s   n=%d', ex.fileName, nTrials), 'Interpreter', 'none')

end
