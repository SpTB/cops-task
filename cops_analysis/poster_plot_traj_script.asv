% save settings
%data_dir='/run/user/1000/gvfs/smb-share:server=lsr-isilon.nei.nih.gov,share=lsr-nienborg/projects/ongoing/CoPs/'
data_dir='Y:\data\CoPs/';
%local_dir = '/home/vpixx/vsgui/vsg/cops_analysis/poster/' 
local_dir = 'C:\Users\zajkowskiwk\OneDrive - National Institutes of Health\cops_project\output\posters\simco26\' 

fontsize=14;
fig_pos=[100 100 500 200];
fig_pos_single=[100 100 250 200];
%% plot traj example:
load('ka_15.57.t120_180-by-10Hz_steps_gs2.5_noiseMix0--0--1--1--1--1.mat')
plotTraj(ex, 17, 'xy_only')
fig = gcf;
  fig.Position = fig_pos;
 for ax = findall(gcf, 'Type', 'axes').'
    legend(ax, 'off');
end
exportgraphics(gcf, [data_dir,'traj/ka_example_xy.pdf'], 'ContentType', 'vector')

% plotTraj(ex, 17, 'y_only')
% fig = gcf;
% fig.Position = fig_pos_single;
% legend off
%exportgraphics(gcf, [data_dir,'traj/ka_example_y.pdf'], 'ContentType', 'vector')

plotTraj(ex, 17, '2d_only')
fig = gcf;
fig.Position = fig_pos_single;
legend off
exportgraphics(gcf, [data_dir,'traj/ka_example_2d.pdf'], 'ContentType', 'vector')

%% plot traj learning:

%day 1:
%load('/media/vpixx/DATA/CoPs/kaki/2026.03.12_good/ka_12.31.t69_10-by-0.5s_steps_pw0.5.mat')
load(data_dir+ "kaki/2026.03.12_good/ka_12.31.t69_10-by-0.5s_steps_pw0.5.mat")
plotTraj(ex,5, 'xy_only')
 fig = gcf;
  fig.Position = fig_pos;
 for ax = findall(gcf, 'Type', 'axes').'
    legend(ax, 'off');
end
exportgraphics(gcf, [data_dir,'traj/ka_day1.pdf'], 'ContentType', 'vector')


% day 1 (Mar 30) or 10:
load('/media/vpixx/DATA/CoPs/kaki/2026.03.30/ka_12.31.t100_120-by-0.15s_steps_gs4_noise5.mat')
plotTraj(ex,55, 'xy_only')
fig = gcf;
  fig.Position = fig_pos;
 for ax = findall(gcf, 'Type', 'axes').'
    legend(ax, 'off');
end
exportgraphics(gcf, [data_dir,'traj/ka_day10.pdf'], 'ContentType', 'vector')



% day 15/25 (currently used just for legend, but it's a good trial if
% needed)
load('/media/vpixx/DATA/CoPs/kaki/2026.04.27/experimental/ka_12.35.t120_120-by-0.15s_steps_gs5_noiseMix0---5--50.mat')
plotTraj(ex,15, 'xy_only');
%lgd = legend(...);

fig = gcf;
fig.Position = fig_pos;
%  for ax = findall(gcf, 'Type', 'axes').'
%     legend(ax, 'off');
% end
exportgraphics(gcf, [data_dir,'traj/ka_day30.pdf'], 'ContentType', 'vector')

%% traj for biased target selection?
% ka: s1
%load('/media/vpixx/DATA/CoPs/kaki/2026.06.18/experimental/ka_14.41.t125_540-by-30Hz_steps_gs2.5_noiseMixNull-1-1-1-1-1.mat')
load(data_dir+ "kaki/2026.06.18/experimental/ka_14.41.t125_540-by-30Hz_steps_gs2.5_noiseMixNull-1-1-1-1-1.mat")

plotTraj(ex, 60, 'xy')
fig = gcf;
fig.Position = fig_pos;
%  for ax = findall(gcf, 'Type', 'axes').'
legend off
exportgraphics(gcf, [data_dir,'traj/ka_xy_s1.pdf'], 'ContentType', 'vector')


% ka: s3
%load('/media/vpixx/DATA/CoPs/kaki/2026.06.18/experimental/ka_16.14.t125_540-by-30Hz_steps_gs2.5_noiseMixNull-1-1-1-1-1.mat')
load(data_dir+ "kaki/2026.06.18/experimental/ka_16.14.t125_540-by-30Hz_steps_gs2.5_noiseMixNull-1-1-1-1-1.mat")
plotTraj(ex, 50, 'xy') % or 35
fig = gcf;
fig.Position = fig_pos;
%  for ax = findall(gcf, 'Type', 'axes').'
legend off
exportgraphics(gcf, [data_dir,'traj/ka_xy_s3.pdf'], 'ContentType', 'vector')

%% new: unengaged example
load(data_dir+ "kaki/2026.06.18/experimental/ka_14.41.t125_540-by-30Hz_steps_gs2.5_noiseMixNull-1-1-1-1-1.mat")

plotTraj(ex, 4, 'xy')
fig = gcf;
fig.Position = fig_pos;
%  for ax = findall(gcf, 'Type', 'axes').'
legend off
exportgraphics(gcf, [local_dir,'traj/ka_unengaged.pdf'], 'ContentType', 'vector')

load(data_dir+ "lychee/2026.08.11/experimental/ly_14.16.t125_540-by-30Hz_steps_gs2.25_noiseMixNull-1-1-1-1-1")
plotTraj(ex, 83, 'xy')
fig = gcf;
fig.Position = fig_pos;
%  for ax = findall(gcf, 'Type', 'axes').'
legend off
exportgraphics(gcf, [local_dir,'traj/ly_disengaged.pdf'], 'ContentType', 'vector')

%% new: tracking close vs far (Lychee?)
load(data_dir+ "lychee/2026.08.11/experimental/ly_14.16.t125_540-by-30Hz_steps_gs2.25_noiseMixNull-1-1-1-1-1")

plotTraj(ex, 61, 'xy')
fig = gcf;
fig.Position = fig_pos;
%  for ax = findall(gcf, 'Type', 'axes').'
legend off
exportgraphics(gcf, [local_dir,'traj/ly_weak_track.pdf'], 'ContentType', 'vector')

%% new: reward pull
load(data_dir+ "lychee/2026.08.11/experimental/ly_14.16.t125_540-by-30Hz_steps_gs2.25_noiseMixNull-1-1-1-1-1")

plotTraj(ex, 67, 'xy')
fig = gcf;
fig.Position = fig_pos;
%  for ax = findall(gcf, 'Type', 'axes').'
legend off
exportgraphics(gcf, [local_dir,'traj/ly_rew_pull.pdf'], 'ContentType', 'vector')

%% tracking bias
o=[]
o.showRew=true
plotTraj(ex, 67, 'xy_only',o)
fig = gcf;
fig.Position = fig_pos;
%for ax = findall(gcf, 'Type', 'axes').'
delete(findall(fig, 'Type', 'legend'));
%end
exportgraphics(gcf, [local_dir,'traj/ly_trackB1.pdf'], 'ContentType', 'vector')

plotTraj(ex, 68, 'xy_only',o)
fig = gcf;
fig.Position = fig_pos;
%for ax = findall(gcf, 'Type', 'axes').'
delete(findall(fig, 'Type', 'legend'));
%end
exportgraphics(gcf, [local_dir,'traj/ly_track_t68.pdf'], 'ContentType', 'vector')

