function files=plotCoPsHardwareBenchx(results)
% Export a compact overview and the raw optical/TTL traces without opening UI.
if ischar(results) || isstring(results)
    s=load(fullfile(char(results),'results.mat'),'results'); results=s.results;
end
folder=results.outputDir;
summary=results.summary;
labels=strcat(string(summary.scenario)," ",string(summary.version));
f=figure('Visible','off','Color','w','Position',[100 100 1100 700]);
closeFigure=onCleanup(@() close(f)); %#ok<NASGU>
tiledlayout(2,2,'TileSpacing','compact');
nexttile; bar(summary.pollHz); ylabel('Input polls / second'); title('Online input processing');
set(gca,'XTick',1:height(summary),'XTickLabel',labels); xtickangle(20); grid on;
nexttile; bar(summary.skippedRefreshes); ylabel('Extra refresh intervals'); title('Frame pacing');
set(gca,'XTick',1:height(summary),'XTickLabel',labels); xtickangle(20); grid on;
nexttile; bar(summary.rewardPulsesGO); ylabel('Measured GO reward pulses'); title('Actual digital-output pulses');
set(gca,'XTick',1:height(summary),'XTickLabel',labels); xtickangle(20); grid on;
nexttile; bar(summary.startToGoSec); ylabel('Seconds'); title('Trial start to GO');
set(gca,'XTick',1:height(summary),'XTickLabel',labels); xtickangle(20); grid on;
sgtitle('CoPs subject-free hardware comparison');
files.overview=fullfile(folder,'overview.png');
exportgraphics(f,files.overview,'Resolution',160);
exportgraphics(f,fullfile(folder,'overview.pdf'),'ContentType','vector');
clear closeFigure

n=numel(results.trials);
f=figure('Visible','off','Color','w','Position',[100 100 1250 250*n]);
closeFigure=onCleanup(@() close(f)); %#ok<NASGU>
tiledlayout(n,2,'TileSpacing','compact');
for j=1:n
    t=results.trials{j}; cfg=t.bench.config;
    a=t.bench.clockBefore; b=t.bench.clockAfter;
    convert=@(v) a(1)+(v-a(2))*(b(1)-a(1))/(b(2)-a(2));
    count=t.Eye.n;
    row=find(t.adcChannels==cfg.photodiodeChannel,1);
    pt=convert(t.Eye.t(1:count))-t.times.stimOn;
    nexttile;
    plot(pt,t.Eye.v(row,1:count),'Color',[.15 .35 .65]); hold on;
    yline(cfg.photodiodeThresholdV,'--','Threshold');
    xline(0,':k','Software GO');
    xlim([-.03 .35]); ylabel('Photodiode V'); xlabel('Seconds from GO'); grid on;
    title(sprintf('%s %s: raw light onset',cfg.scenario,cfg.version));
    nexttile;
    dt=convert(t.bench.dinTime)-t.times.stimOn;
    state=double(bitand(uint32(t.bench.dinData),uint32(1))~=0);
    if ~isempty(dt), stairs(dt,state,'Color',[.15 .45 .25]); else, plot(NaN,NaN); end
    hold on;
    requests=t.times.reward(isfinite(t.times.reward))-t.times.stimOn;
    if ~isempty(requests), scatter(requests,1.15*ones(size(requests)),10,'r','filled'); end
    xlim([-.3 t.bench.blankVbl-t.times.stimOn+.1]); ylim([-.1 1.3]);
    xlabel('Seconds from GO'); ylabel('Reward bit'); grid on;
    title('Recorded output (green); software requests (red)');
end
sgtitle('Raw optical signal and measured reward-output transitions');
files.traces=fullfile(folder,'traces.png');
exportgraphics(f,files.traces,'Resolution',160);
exportgraphics(f,fullfile(folder,'traces.pdf'),'ContentType','vector');
end
