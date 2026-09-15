%% Plot the eye positions Load expt file

clear all
thisPath    = fullfile(fileparts(mfilename('fullpath')));
% fileName    = 'data/2025.11.05/t_17.09.EyeCal.mat';
% fileName    = 'data/2026.02.26/sh_14.21.EyeCal.mat';
fileName    = '/media/vpixx/DATA/CoPs/lychee/2026.04.01/ly_16.57.EyeCal/ly_16.57.EyeCal.mat';

load(fullfile(thisPath,fileName))

% ex.Trials.Eye.v:
% 1: RX
% 2: RY
% 3: RPupil
% 4: LX
% 5: LY
% 6: LPupil
% 7

keyboard
%%
sampleDur   = 0.1;    % in seconds
nSamples    = round(sampleDur*ex.setup.adc.Rate);

rEyeVFix = nan*zeros(nSamples,numel(ex.Trials));
lEyeVFix = nan*zeros(nSamples,numel(ex.Trials));

for iT = 1:numel(ex.Trials)
    targPosPixel(1,iT)  = ex.Trials(iT).targ.Pos(1)+ex.fix.PCtr(1);
    targPosPixel(2,iT)  = ex.Trials(iT).targ.Pos(2)+ex.fix.PCtr(2);
    %[tmpX, tmpY]        = pixel2degxy(targPosPixel(1,iT),targPosPixel(2,iT),ex.setup);
    tmpX = px2deg(targPosPixel(1,iT), ex.setup);
    tmpY = px2deg(targPosPixel(2,iT), ex.setup);

    targPosDeg(1,iT)    = tmpX;
    targPosDeg(2,iT)    = tmpY;

    rEyeV(:,:,iT)   = ex.Trials(iT).Eye.v(1:2,:); % is this by default in deg? no, voltages...
    lEyeV(:,:,iT)   = ex.Trials(iT).Eye.v(4:5,:);
    trialT(:,iT)    = ex.Trials(iT).Eye.t;

    lastIDX     = find(isnan(rEyeV(1,:,iT)),1);
    fixationIDX = max(1,lastIDX-nSamples):lastIDX-1;

    rEyeDegFix(1,iT,1:numel(fixationIDX))  = (ex.eyeCal.RX0-rEyeV(1,fixationIDX,iT))*ex.eyeCal.RXGain;
    rEyeDegFix(2,iT,1:numel(fixationIDX))  = (ex.eyeCal.RY0-rEyeV(2,fixationIDX,iT))*ex.eyeCal.RYGain;
    lEyeDegFix(1,iT,1:numel(fixationIDX))  = (ex.eyeCal.LX0-lEyeV(1,fixationIDX,iT))*ex.eyeCal.LXGain;
    lEyeDegFix(2,iT,1:numel(fixationIDX))  = (ex.eyeCal.LY0-lEyeV(2,fixationIDX,iT))*ex.eyeCal.LYGain;

    clf;
    cR = numel(fixationIDX):-1:1;
    cL = 1:numel(fixationIDX);
    subplot(2,2,1); hold on;
    % plot(trialT(:,iT),rEyeV(1,:,iT),'r');
    % plot(trialT(:,iT),lEyeV(1,:,iT),'b');
    plot(trialT(:,iT),(ex.eyeCal.RX0-rEyeV(1,:,iT))*ex.eyeCal.RXGain,'r--');
    plot(trialT(:,iT),(ex.eyeCal.LX0-lEyeV(1,:,iT))*ex.eyeCal.LXGain,'b--');
    xlabel('Time');
    ylabel('X position (deg)');

     subplot(2,2,2); hold on;
    % plot(trialT(:,iT),rEyeV(2,:,iT),'r');
    % plot(trialT(:,iT),lEyeV(2,:,iT),'b');
    plot(trialT(:,iT),(ex.eyeCal.RY0-rEyeV(2,:,iT))*ex.eyeCal.RYGain,'r--');
    plot(trialT(:,iT),(ex.eyeCal.LY0-lEyeV(2,:,iT))*ex.eyeCal.LYGain,'b--');
    xlabel('Time');
    ylabel('Y position (deg)');

    % maxDeg = 25;
    maxDeg = floor(max(targPosDeg(:)))+5;
    subplot(2,2,3:4); hold on; axis square
    plot(-targPosDeg(1,iT),-targPosDeg(2,iT),'ok','MarkerSize',10);
    plot(0,0,'or','MarkerSize',10);
    plot([-maxDeg maxDeg],[0 0],'-r');
    plot([0 0],[-maxDeg maxDeg],'-r');
    scatter((ex.eyeCal.RX0-rEyeV(1,fixationIDX,iT))*ex.eyeCal.RXGain,(ex.eyeCal.RY0-rEyeV(2,fixationIDX,iT))*ex.eyeCal.RYGain,[],cR);
    scatter((ex.eyeCal.LX0-lEyeV(1,fixationIDX,iT))*ex.eyeCal.LXGain,(ex.eyeCal.LY0-lEyeV(2,fixationIDX,iT))*ex.eyeCal.LYGain,[],cL);

    drawnow;
    % pause;
%%
end

%% plot final 

figure(2); clf
% maxDeg = 25;
maxDeg = floor(max(targPosDeg(:)))+5;

subplot(2,2,1); hold on;
[~,b] = sort(targPosDeg(1,:))
scatter(targPosDeg(1,b),targPosDeg(2,b),[],1:size(targPosDeg,2)); axis square
plot([-maxDeg maxDeg],[0 0],'-k');
plot([0 0],[-maxDeg maxDeg],'-k');
scatter(-nanmean(rEyeDegFix(1,b,:),3),-nanmean(rEyeDegFix(2,b,:),3),20,1:size(targPosDeg,2),'filled');
axis([-maxDeg maxDeg -maxDeg maxDeg]);
xlabel('Deg X');
ylabel('Deg Y');

subplot(2,2,2); hold on;
[~,b] = sort(targPosDeg(2,:))
scatter(targPosDeg(1,b),targPosDeg(2,b),[],1:size(targPosDeg,2)); axis square
plot([-maxDeg maxDeg],[0 0],'-k');
plot([0 0],[-maxDeg maxDeg],'-k');
scatter(-nanmean(rEyeDegFix(1,b,:),3),-nanmean(rEyeDegFix(2,b,:),3),20,1:size(targPosDeg,2),'filled');
axis([-maxDeg maxDeg -maxDeg maxDeg]);
xlabel('Deg X');
ylabel('Deg Y');

subplot(2,2,3); hold on;
title('X Position');
plot([-maxDeg maxDeg],[-maxDeg maxDeg],'-k'); axis square
plot(targPosDeg(1,:),-nanmean(rEyeDegFix(1,:,:),3),'or');
plot(targPosDeg(1,:),-nanmean(lEyeDegFix(1,:,:),3),'ob');
axis([-maxDeg maxDeg -maxDeg maxDeg]);
xlabel('Target position (deg)');
ylabel('Fixation position (deg)');

subplot(2,2,4); hold on;
title('Y Position');
plot([-maxDeg maxDeg],[-maxDeg maxDeg],'-k'); axis square
plot(targPosDeg(2,:),-nanmean(rEyeDegFix(2,:,:),3),'or');
plot(targPosDeg(2,:),-nanmean(lEyeDegFix(2,:,:),3),'ob');
axis([-maxDeg maxDeg -maxDeg maxDeg]);
xlabel('Target position (deg)');
ylabel('Fixation position (deg)');