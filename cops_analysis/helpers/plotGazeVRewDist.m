rb = out.meta.rewardByDistance;

figure('Color','w'); hold on;

% Optional: only show bins with enough samples
minN = 20;

gMask = rb.gaze.nPerBin >= minN & isfinite(rb.gaze.meanReward);
tMask = rb.target.nPerBin >= minN & isfinite(rb.target.meanReward);

plot(rb.gaze.binCentersPx(gMask), rb.gaze.meanReward(gMask), '-o', ...
    'LineWidth', 1.8, 'DisplayName', 'Gaze');

plot(rb.target.binCentersPx(tMask), rb.target.meanReward(tMask), '-s', ...
    'LineWidth', 1.8, 'DisplayName', 'Target (sum of both)');

xlabel('Distance from Gaussian center (px)');
ylabel('Mean reward');
title('Reward vs Distance from Gaussian Center');
legend('Location','best');
grid on;


figure('Color','w');
subplot(2,1,1);
bar(rb.gaze.binCentersPx, rb.gaze.nPerBin);
title('Gaze samples per distance bin'); ylabel('N'); grid on;

subplot(2,1,2);
bar(rb.target.binCentersPx, rb.target.nPerBin);
title('Target samples per distance bin'); xlabel('Distance (px)'); ylabel('N'); grid on;