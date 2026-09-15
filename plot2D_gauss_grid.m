gauss_dim = 596;
sigma = 150
reward_mat = gauss_rew_land(gauss_dim, [gauss_dim/2, gauss_dim/2], sigma); % reward matrix
figure;
imagesc(reward_mat);          % M is your 2D Gaussian matrix
colorbar;            % Shows color scale
axis equal tight;    % Keep aspect ratio
title('2D Gaussian Heatmap');
