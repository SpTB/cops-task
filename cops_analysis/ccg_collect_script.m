% !! needs separate waitHz to calc correctly!!
animal='ka'
animal2='ly'
fontsize=14;
fig_pos=[100 100 500 250];
%data_dir='/run/user/1000/gvfs/smb-share:server=lsr-isilon.nei.nih.gov,share=lsr-nienborg/projects/ongoing/CoPs/'
data_dir='Y:\data\CoPs/';
%local_dir = '/home/vpixx/vsgui/vsg/cops_analysis/poster/' 
local_dir = 'C:\Users\zajkowskiwk\OneDrive - National Institutes of Health\cops_project\output\posters\simco26\' 

%ka basic
  o= struct();
  o.dateFrom = 'jul02'; % Kaki: from Jun08; Ly: Jun05
  o.dateTo = 'sep01';%'Sep01'; % Kaki: Jun29
 
  %o.targetNum = 2;
  o.dataRoot=data_dir;
  %o.backgroundNoiseLvl = '>0'; % Dynamic background; supports old level 5 and newer level 1.
  o.waitHz = 30;
  o.mergeHmm=true;
  o.hmmRoot = ['C:\Users\zajkowskiwk\OneDrive - National Institutes of Health\' ...
             'cops_project\output\hmm'];
o.hmmModel = 'sm3';
  %o.ccgOpts = opts;   % your usual plotCCG2/ccg opts
  %o.groupLevels = [0.5 0.7 0.8 0.9 1];
  %o.visLvls = [.8, .95]; % low < first cutoff; mid < second cutoff; high is the rest.
  %o.referenceTargetMode
  
%  Aa = collectCCG2(animal, 'visLvl3', o);      % all selected trials as one group
  Aa = collectCCG2(animal, 'vis', o); 
 Bb = collectCCG2(animal2, 'vis', o); 

  %B = collectCCG2('ka', 'vis', o);      % all selected trials as one group
  save([local_dir,'/ccg/',animal,'_',o.dateFrom, o.dateTo,'_coh.mat'], 'Aa');
    save([local_dir,'/ccg/',animal,'_',o.dateFrom, o.dateTo,'_coh.mat'], 'Bb');


plotCCG2Aggregate(Aa)
plotCCG2Aggregate(Bb)
set(gca,'FontSize',fontsize) 

sgtitle('')
title('')
subtitle('')
xlabel('')
 ylabel('')
fig = gcf;
fig.Position = [100 100 500 250];    % wider figure

ax = gca;
ax.Title.String = '';
ax.Position = [0.13 0.18 0.70 0.75]; % <-- FIXED plot size
xlim([-0.5 1.75])
legend off

% fig.Position(3) = fig.Position(3)*2.5;   % double width
  exportgraphics(gca, [local_dir,'ccg/ka.pdf'], 'ContentType', 'vector')


%lychee
o.dateFrom = 'Jun05'; 
Bb = collectCCG2('ly', 'visLvl3', o); 
save([local_dir,'/ccg/ly_coh.mat'], 'Bb')
 
plotCCG2Aggregate(Bb)
  set(gca,'FontSize',fontsize) 
  fig = gcf;
  fig.Position = fig_pos;
  sgtitle('')
  title('')
 xlabel('')
 ylabel('')
 legend off
 xlim([-0.5 2.5])
 ax = gca;
 ax.Position = [0.13 0.18 0.70 0.75]; % <-- FIXED plot size

 % fig.Position(3) = fig.Position(3)*2.5;   % double width
  exportgraphics(gca, [data_dir,'ccg/ly.pdf'], 'ContentType', 'vector')

  %% BIAS: tracking closer vs further
  
  % kaki
  o.dateFrom='Jun08'
  o.referenceTargetMode='targetCloser'% targetFarther
  Aclose = collectCCG2('ka', [], o);
  o.referenceTargetMode = 'targetFarther';
  Afar = collectCCG2('ka', [], o);
  save([local_dir,'/ka_close.mat'], 'Aclose', '-v7.3')
  save(fullfile(data_dir, 'ccg', 'ka_close.mat'), 'Aclose','-v7.3')

  % figure; hold on
  % plot(Aclose.lagSec, Aclose.groups{1}.aggregate2D, 'LineWidth', 2, 'Color', '#009E73');
  % plot(Afar.lagSec, Afar.groups{1}.aggregate2D, 'LineWidth', 2,'Color', '#7B3294');
  % xline(0, ':');
  % yline(0, ':');
  % legend({'target closer to reward', 'target farther from reward'}, ...
  %      'Location', 'eastoutside', ...
  %      'Orientation', 'vertical');
  % xlabel('Lag (s)');
  % ylabel('2D velocity xcorr');
  % box off
  % 
  % set(gca,'FontSize',fontsize) 
  % fig = gcf;
  % fig.Position = [100 100 350 250];
 
figure;
hold on

plot(Aclose.lagSec, Aclose.groups{1}.aggregate2D, ...
    'LineWidth',2,'Color','#009E73');

plot(Afar.lagSec, Afar.groups{1}.aggregate2D, ...
    'LineWidth',2,'Color','#7B3294');

xline(0,':');
yline(0,':');

xlabel('Lag (s)');
ylabel('2D velocity xcorr');
box off

set(gca,'FontSize',fontsize)

fig = gcf;
fig.Position = [100 100 500 250];    % wider figure
 xlim([-0.5 2.5])

ax = gca;
ax.Position = [0.10 0.10 0.70 0.75]; % <-- FIXED plot size

lgd = legend({'target closer to reward', ...
              'target farther from reward'}, ...
              'Box','off');

lgd.Units = 'normalized';
lgd.Position = [0.66 0.75 0.13 0.10];

  exportgraphics(gca, [data_dir,'ccg/ka_cloFar.pdf'], 'ContentType', 'vector')

%lychee
 o.dateFrom='Jun05'
  o.referenceTargetMode='targetCloser'% targetFarther
  Bclose = collectCCG2('ly', [], o);
  save([local_dir,'/ly_close.mat'], 'Bclose', '-v7.3')

  o.referenceTargetMode = 'targetFarther';
  Bfar = collectCCG2('ly', [], o);
  save([local_dir,'/ly_far.mat'], 'Bfar', '-v7.3')

  figure; hold on
  plot(Bclose.lagSec, Bclose.groups{1}.aggregate2D, 'LineWidth', 2, 'Color', '#009E73');
  plot(Bfar.lagSec, Bfar.groups{1}.aggregate2D, 'LineWidth', 2,'Color', '#7B3294');
  xline(0, ':');
  yline(0, ':');
  % legend({'target closer to reward', 'target farther from reward'}, ...
  %      'Location', 'eastoutside', ...
  %      'Orientation', 'vertical');
  %legend({'target closer to reward', 'target farther from reward'},'Interpreter', 'none');
  xlabel('Lag (s)');
  ylabel('2D velocity xcorr');
  box off

set(gca,'FontSize',fontsize)

fig = gcf;
fig.Position = fig_pos;    % wider figure

ax = gca;
ax.Position = [0.10 0.10 0.70 0.75]; % <-- FIXED plot size
xlim([-0.5 2.5])

  exportgraphics(gca, [data_dir,'ccg/ly_cloFar.pdf'], 'ContentType', 'vector')

  %% gaze Aggregation
  
  % gaze aggr
  load([local_dir,'/bias/ly_gazeAggr.mat'])
  load([local_dir,'/bias/ka_gazeAggr.mat'])

  o = struct();
  o.dateFrom = 'May02';
  o.dateTo = 'Jun18';
  o.waitHz = 30;
  o.backgroundNoiseLvl = '>0';
  o.blockLvls = [100, 200];

  B = collectGazeHeat('ly', [], o);
  plotGazeHeatAggregate(B, 'block');
  %set(gca,'FontSize',fontsize) 
  fig = gcf;
  fig.Position = [100 100 1200 500];
  exportgraphics(gcf, [data_dir,'bias/ly_gazeHeatAggr.pdf'], 'ContentType', 'vector')

  save([local_dir,'/bias/ly_gazeAggr.mat'], 'B')



  % kaki
   A = collectGazeHeat('ka', [], o);
  save([local_dir,'/bias/ka_gazeAggr.mat'], 'A')

  plotGazeHeatAggregate(A, 'block');

  %set(gca,'FontSize',fontsize) 
  fig = gcf;
  fig.Position = [100 100 1200 500];
  exportgraphics(gcf, [data_dir,'bias/ka_gazeHeatAggr.pdf'], 'ContentType', 'vector')

  save([local_dir,'/bias/ka_gazeAggr.mat'], 'A')



%% Collecting dens/gazeWalk: gazeHeatTrajectory

%plotGazeHeatTrajectory

  % vars =intersect({'fileName','status','message','waitHz','nSelectedTrials'}, ...
  %     A.fileTable.Properties.VariableNames, 'stable');
  % A.fileTable(:, vars)