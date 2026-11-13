% save settings
%data_dir='/run/user/1000/gvfs/smb-share:server=lsr-isilon.nei.nih.gov,share=lsr-nienborg/projects/ongoing/CoPs/'
data_dir='Y:\data\CoPs/';

%local_dir = '/home/vpixx/vsgui/vsg/cops_analysis/poster/' 
local_dir = 'C:\Users\zajkowskiwk\OneDrive - National Institutes of Health\cops_project\output\posters\simco26\' 

fontsize=14;
fig_pos=[100 100 500 300];
fig_pos_single=[100 100 300 300]
o.peakField = 'density' %same as for gazeHeat; alt: 'gazeDensity': just gaze

%% gazeHeat: example
%load...
o = struct();
o.dateFrom = 'Jun18';
o.dateTo = 'Jun18';
o.waitHz = 30;
o.backgroundNoiseLvl = '>0';
o.blockLvls = [100, 200];
o.plotRotate45=false;

gh = collectGazeHeat('ka', [], o);

plotGazeHeatAggregate(gh, 'block');
fig = gcf;
fig.Position = [100 100 800 300];%fig_pos;
axs = findall(gcf, 'Type', 'axes');
for ax = axs.'
    ax.FontSize = fontsize;

    xlabel(ax, '');
    ylabel(ax, '');
    title(ax, '');

    % Only for MATLAB versions that support subtitles
    if isprop(ax, 'Subtitle')
        subtitle(ax, '');
    end
end
exportgraphics(gcf, [data_dir,'bias/ka_gazeHeat_example.pdf'], 'ContentType', 'vector')


%% gazeHeatTraj: example

%optional settings:
o.peakField = 'density' %same as for gazeHeat; alt: 'gazeDensity': just gaze
o.windowTrials=50;
o.stepTrials=25; 


ka = collectGazeHeatTrajectory('ka', [],o);
save([local_dir,'/bias/ka_densWalk_example.mat'], 'ka');

o.plotMode='trajectory'%trajectory%both
plotGazeHeatTrajectoryAggregate(ka,o)

fig = gcf;
fig.Position = fig_pos_single;
set(gca, 'FontSize', fontsize) 
 xlabel('');
  ylabel('');
  title('')
  subtitle('')
  sgtitle('')
exportgraphics(gcf, [data_dir,'bias/ka_densWalkTraj_example.pdf'], 'ContentType', 'vector')

o.plotMode='distance'%trajectory%both
plotGazeHeatTrajectoryAggregate(ka,o)
fig = gcf;
fig.Position = [100 100 400 300];%fig_pos;
set(gca, 'FontSize', fontsize) 
 xlabel('');
  ylabel('');
  title('')
  subtitle('')
  sgtitle('')
  legend off
exportgraphics(gcf, [data_dir,'bias/ka_densWalkDist_example.pdf'], 'ContentType', 'vector')

%% gazeHeat traj: sums
o.dateFrom = 'May02';
o.windowTrials=50;
o.stepTrials=25;
o.trajectoryBinSizeTrials=o.stepTrials;
kasx = collectGazeHeatTrajectory('ka', [],o);
save([local_dir,'/bias/ka_densWalk_full.mat'], 'kasx');

o.plotMode='distance'%trajectory%both
plotGazeHeatTrajectoryAggregate(kasx,o)
xlim([0,320])
fig=gcf;
fig.Position = [100 100 400 300];%fig_pos;
set(gca, 'FontSize', fontsize) 
 xlabel('');
  ylabel('');
  title('')
  subtitle('')
  sgtitle('')
  legend off
exportgraphics(gcf, [data_dir,'bias/ka_densWalkDist_full.pdf'], 'ContentType', 'vector')


o.waitHz = '<30';
o.dateFrom = 'May05';
lys = collectGazeHeatTrajectory('ly', [],o);

save([local_dir,'/bias/ly_densWalk_full.mat'], 'lys');

o.plotMode='distance'%trajectory%both
plotGazeHeatTrajectoryAggregate(lys,o)
xlim([0,320])
fig=gcf;
fig.Position = [100 100 400 300];%fig_pos;
set(gca, 'FontSize', fontsize) 
 xlabel('');
  ylabel('');
  title('')
  subtitle('')
  sgtitle('')
  legend off
exportgraphics(gcf, [data_dir,'bias/ly_densWalkDist_full.pdf'], 'ContentType', 'vector')

%% new: plotGazeRewDist
o=[];
o.dataRoot=data_dir
o.showSessions=false;
plotGazeRewDistDay('ka', 'jun18',o)
%plotGazeRewDistDay('ly', 'jun15',o)

fontsize=14;
fig_pos=[100 100 500 300];
xlim([0,320])
fig=gcf;
fig.Position = [100 100 400 200];%fig_pos;
set(gca, 'FontSize', fontsize) 
 xlabel('');
  ylabel('');
  title('')
  subtitle('')
  sgtitle('')
  legend off
exportgraphics(gcf, [local_dir,'learn/ka_rewDist_jun18.pdf'], 'ContentType', 'vector')

%summary
o=[];
o.dataRoot=data_dir;
o.showSessions=false;
plotGazeRewDistDays('ka', 'May02', 'Jul12',o)
xlim([0,320])
fig=gcf;
fig.Position = [100 100 400 200];%fig_pos;
set(gca, 'FontSize', fontsize) 
 xlabel('');
  ylabel('');
  title('')
  subtitle('')
  sgtitle('')
  legend off
exportgraphics(gcf, [local_dir,'learn/ka_rewDist_mayjun.pdf'], 'ContentType', 'vector')



plotGazeRewDistDays('ly', 'May02', 'Jul12',o)
xlim([0,320])
fig=gcf;
fig.Position = [100 100 400 200];%fig_pos;
set(gca, 'FontSize', fontsize) 
 xlabel('');
  ylabel('');
  title('')
  subtitle('')
  sgtitle('')
  legend off
exportgraphics(gcf, [local_dir,'learn/ly_rewDist_mayjun.pdf'], 'ContentType', 'vector')

