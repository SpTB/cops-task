function data = checkCoPsPhotodiodeFlashx(options)
% Flash the bottom-right patch at known times while recording the photodiode.
%   pd = checkCoPsPhotodiodeFlashx(); % ADC0, white at 1:5 s for 200 ms each
%   pd = checkCoPsPhotodiodeFlashx(onsets=[1 2 4 6],pulseDurationSecs=0.25);
%   pd = checkCoPsPhotodiodeFlashx(channel=6,sampleRate=5000);
% Uses the experiment's fullscreen display/mapping, without EyeLink or trials.
% F4/Escape stops early. The comparison plot appears after the window closes.
% Background matches ex.idx.bg_lum; the patch switches from black to white.
% Flip timestamps reference scanout; physical onset also includes panel and
% bottom-right scanout delay. Run with the experiment/acquisition stopped.
arguments
    options.onsets (1,:) double {mustBeFinite,mustBePositive} = 1:5
    options.pulseDurationSecs (1,1) double {mustBeFinite,mustBePositive} = 0.2
    options.tailSecs (1,1) double {mustBeFinite,mustBePositive} = 1
    options.channel (1,1) double {mustBeInteger,mustBeNonnegative,mustBeFinite} = 0
    options.sampleRate (1,1) double {mustBeInteger,mustBePositive,mustBeFinite,mustBeLessThanOrEqual(options.sampleRate,200000)} = 2000
    options.patchSizePx (1,1) double {mustBeInteger,mustBePositive,mustBeFinite} = 60
    options.showPlot (1,1) logical = true
end
if isempty(options.onsets) || any(diff(options.onsets) <= options.pulseDurationSecs)
    error('checkCoPsPhotodiodeFlashx:Timing','Use increasing, nonoverlapping pulse onsets with a black gap between pulses.');
end
planned = reshape([options.onsets;options.onsets+options.pulseDurationSecs],[],1);
white = repmat([true;false],numel(options.onsets),1);
duration = planned(end)+options.tailSecs;

Datapixx('Open');
try
    Datapixx('RegWrRd');
    original = Datapixx('GetAdcStatus');
    if original.scheduleRunning
        error('checkCoPsPhotodiodeFlashx:AdcBusy','Stop the experiment/acquisition before starting this standalone test.');
    end
catch err
    Datapixx('Close');
    rethrow(err);
end
adcCleanup = onCleanup(@() closeAdcLocal(original)); %#ok<NASGU>

% Reuse the rig's verified ScreenToHead mapping and normal fullscreen path.
% Explicit test geometry avoids dialogs on unknown hosts; no ADC is opened by
% the settings helper, and this diagnostic does not use visual-angle units.
ex.setup = struct('testMode',true,'viewingDistance',55,'monitorWidth',54);
ex.exp.nreps = 0; % The settings helper expects this; no trials are run.
ex = getDefaultSettingsx(ex,true,initializeAdc=false);
backgroundColor = ex.idx.bg_lum;
blackColor = ex.idx.black;
whiteColor = ex.idx.white;
ex.setup.fullscreen = true;
ex.setup.showExperimenterOverlay = false;
ex.synch.PSz = options.patchSizePx;
oldSkip = Screen('Preference','SkipSyncTests');
preferencesCleanup = onCleanup(@() restoreSkipLocal(oldSkip)); %#ok<NASGU>
ex = initDisplayx(ex);
window = ex.setup.window; screen = ex.setup.screenNum;
displayCleanup = onCleanup(@() closeWindowLocal(window,screen)); %#ok<NASGU>
ifi = Screen('GetFlipInterval',window);
if any(diff(planned) < ifi-1e-9)
    error('checkCoPsPhotodiodeFlashx:Timing','Pulse widths and black gaps must each last at least one display refresh.');
end
r = ex.setup.screenRect;
if options.patchSizePx > min(r(3:4)-r(1:2))
    error('checkCoPsPhotodiodeFlashx:PatchSize','The patch must fit inside the display.');
end
patchRect = [r(3)-options.patchSizePx r(4)-options.patchSizePx r(3) r(4)];
HideCursor(screen);
KbName('UnifyKeyNames');
quitKeys = [KbName('F4') KbName('ESCAPE')];

% A finite hardware schedule also bounds recording if host code is interrupted.
maxFrames = ceil((duration+2)*options.sampleRate);
Datapixx('DisableDacAdcLoopback');
Datapixx('DisableAdcFreeRunning');
Datapixx('SetAdcSchedule',0,options.sampleRate,maxFrames,options.channel,4e6, ...
    min(maxFrames,max(10000,5*options.sampleRate)));
analog = struct('v',[],'t',[],'n',0);
Datapixx('StartAdcSchedule');
Datapixx('RegWrRd');
clockStart = clockReferenceLocal();
Screen('FillRect',window,backgroundColor);
Screen('FillRect',window,blackColor,patchRect);
timeZero = Screen('Flip',window);
flipInfo = NaN(numel(planned),4);
completedEdges = 0; aborted = false;
fprintf('Flashing bottom-right patch; ADC%d at %g Hz. F4/Escape stops.\n',options.channel,options.sampleRate);
fprintf('Requested white onsets (seconds): %s; pulse width %.3f s.\n',mat2str(options.onsets),options.pulseDurationSecs);
while completedEdges < numel(planned) || GetSecs < timeZero+duration
    [~,~,keys] = KbCheck(-1);
    if any(keys(quitKeys)), aborted = true; break; end
    analog = readCoPsAnalogx(analog);
    next = completedEdges+1;
    if next <= numel(planned) && GetSecs >= timeZero+planned(next)-2*ifi
        Screen('FillRect',window,backgroundColor);
        Screen('FillRect',window,blackColor+(whiteColor-blackColor)*double(white(next)),patchRect);
        [flipInfo(next,1),flipInfo(next,2),flipInfo(next,3),flipInfo(next,4)] = ...
            Screen('Flip',window,timeZero+planned(next)-0.5*ifi);
        completedEdges = next;
    else
        WaitSecs('YieldSecs',0.005);
    end
end
Screen('FillRect',window,backgroundColor);
Screen('FillRect',window,blackColor,patchRect);
finalBaselineTime = Screen('Flip',window);
clockEnd = clockReferenceLocal();
Datapixx('StopAdcSchedule');
Datapixx('RegWrRd');
analog = readCoPsAnalogx(analog);
clear displayCleanup preferencesCleanup adcCleanup % Release hardware before plotting.
if analog.n == 0
    error('checkCoPsPhotodiodeFlashx:NoSamples','No ADC samples received. Check the connection and ADC configuration.');
end

% Two bracketed references account for clock offset and linear drift.
ratio = (clockEnd.ptb-clockStart.ptb)/(clockEnd.datapixx-clockStart.datapixx);
if ~isfinite(ratio) || ratio <= 0
    error('checkCoPsPhotodiodeFlashx:Clock','Could not align the PTB and DataPixx clocks.');
end
ptbTime = clockStart.ptb+(analog.t-clockStart.datapixx)*ratio;
voltage = analog.v(1,:);
voltage(voltage>10) = voltage(voltage>10)-20; % Preserve raw values separately.
flipInfo = flipInfo(1:completedEdges,:);
events = table(planned(1:completedEdges),flipInfo(:,1)-timeZero, ...
    white(1:completedEdges),flipInfo(:,4), ...
    'VariableNames',{'plannedTime','actualTime','white','missed'});
data = struct('channel',options.channel,'sampleRate',options.sampleRate, ...
    'screen',screen,'patchRect',patchRect,'backgroundColor',backgroundColor,'refreshInterval',ifi, ...
    'patchLevels',[blackColor whiteColor], ...
    'timeZeroPtb',timeZero,'time',ptbTime-timeZero,'ptbTime',ptbTime, ...
    'datapixxTime',analog.t,'voltage',voltage,'rawVoltage',analog.v(1,:), ...
    'plannedOnsets',options.onsets,'pulseDurationSecs',options.pulseDurationSecs, ...
    'events',events,'flipInfo',flipInfo,'finalBaselineTime',finalBaselineTime-timeZero, ...
    'clockStart',clockStart,'clockEnd',clockEnd,'ptbPerDatapixxSecond',ratio, ...
    'completed',~aborted && completedEdges==numel(planned),'aborted',aborted);
data.actualOnsets = events.actualTime(events.white);
data.actualOffsets = events.actualTime(~events.white);
fprintf('Recorded %d samples, %d white onsets; voltage range %.4f to %.4f V.\n', ...
    analog.n,numel(data.actualOnsets),min(voltage),max(voltage));
fprintf('Clock-reference uncertainty: +/- %.3f ms (start), +/- %.3f ms (end).\n', ...
    1000*clockStart.uncertainty,1000*clockEnd.uncertainty);
if options.showPlot, plotComparisonLocal(data,duration); end
end

function closeAdcLocal(original)
try
    Datapixx('StopAdcSchedule');
    if original.freeRunning, Datapixx('EnableAdcFreeRunning');
    else, Datapixx('DisableAdcFreeRunning'); end
    if original.dacAdcLoopback, Datapixx('EnableDacAdcLoopback');
    else, Datapixx('DisableDacAdcLoopback'); end
    Datapixx('RegWr');
catch err
    fprintf(2,'ADC cleanup: %s\n',err.message);
end
try Datapixx('Close'); catch, end
end

function closeWindowLocal(window,screen)
try Screen('Close',window); catch, end
try ShowCursor('Arrow',screen); catch, end
end

function restoreSkipLocal(oldSkip)
try Screen('Preference','SkipSyncTests',oldSkip); catch, end
end

function reference = clockReferenceLocal()
reference = struct('ptb',NaN,'datapixx',NaN,'uncertainty',Inf);
for k=1:5
    before = GetSecs;
    Datapixx('RegWrRd');
    device = Datapixx('GetTime');
    after = GetSecs;
    uncertainty = (after-before)/2;
    if uncertainty < reference.uncertainty
        reference = struct('ptb',(before+after)/2,'datapixx',device,'uncertainty',uncertainty);
    end
end
end

function plotComparisonLocal(data,duration)
f = figure('Name','Photodiode flash timing','NumberTitle','off');
ax1 = subplot(2,1,1,'Parent',f);
onsets = data.plannedOnsets;
planned = reshape([onsets;onsets+data.pulseDurationSecs],[],1);
stairs(ax1,[0;planned;duration],[0;repmat([1;0],numel(onsets),1);0],'--','Color',[0.6 0.6 0.6]);
hold(ax1,'on');
stairs(ax1,[0;data.events.actualTime;data.finalBaselineTime], ...
    [0;double(data.events.white);0],'b','LineWidth',1.2);
ylim(ax1,[-0.1 1.1]); yticks(ax1,[0 1]); yticklabels(ax1,{'Black','White'});
legend(ax1,{'Requested schedule','Actual screen flips'},'Location','best'); grid(ax1,'on');
title(ax1,'Bottom-right patch');
ax2 = subplot(2,1,2,'Parent',f);
plot(ax2,data.time,data.voltage,'k'); hold(ax2,'on');
for k=1:height(data.events)
    xline(ax2,data.events.actualTime(k),':','Color',[0.3 0.5 0.9]);
end
xlabel(ax2,'Seconds after initial black-patch flip'); ylabel(ax2,sprintf('ADC%d voltage (V)',data.channel));
grid(ax2,'on'); title(ax2,'Measured photodiode voltage; blue lines mark screen flips');
linkaxes([ax1 ax2],'x'); xlim(ax2,[min(0,min(data.time)) max(duration,max(data.time))]);
end
