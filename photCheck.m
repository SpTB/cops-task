function [ex, pd] = photCheck(options)
% One fullscreen task trial with binary photodiode playback and ADC recording.
%   [ex,pd] = photCheck(); % physical ADC0, 2000 Hz; mouse input, no EyeLink
%   [ex,pd] = photCheck(channel=6,framesPerBit=2);
% The patch switches between black and white in the bottom-right corner.
% No instructions, practice, reward hardware, or completion keypress is used.
% F4 stops the trial. Task data are saved in test_data/output/test as usual.
% pd.timing reports missed refreshes and whether the final ADC tail is complete.
arguments
    options.channel (1,1) double {mustBeInteger,mustBeNonnegative,mustBeFinite,mustBeLessThanOrEqual(options.channel,15)} = 0
    options.sampleRate (1,1) double {mustBeInteger,mustBePositive,mustBeFinite,mustBeLessThanOrEqual(options.sampleRate,200000)} = 2000
    options.framesPerBit (1,1) double {mustBeInteger,mustBePositive,mustBeFinite} = 1
    options.tailSecs (1,1) double {mustBePositive,mustBeFinite} = 0.1
    options.showPlot (1,1) logical = true
    options.filePrefix (1,1) string = "photCheck"
    options.stimulusDir (1,1) string = ""
end
ex = runEx('mouse_mini',testTrials=1,instrOn=false,jointBlocks=false, ...
    fullscreen=true,showCursor=true,overlayOn=false,soundOn=false, ...
    showEndScreen=false,syncMode='binary',syncFramesPerBit=options.framesPerBit, ...
    photodiodeRecord=true,photodiodeChannel=options.channel, ...
    photodiodeTailSecs=options.tailSecs, ...
    photodiodeSampleRate=options.sampleRate,filePrefix=options.filePrefix, ...
    stimulusDir=options.stimulusDir);
pd = struct();
if isfield(ex,'lastError') && ~isempty(ex.lastError)
    warning('photCheck:TrialFailed','Trial failed: %s',ex.lastError.message);
end
if ~isfield(ex,'Trials') || isempty(ex.Trials) || ...
        ~isfield(ex.Trials(1),'Analog') || isempty(ex.Trials(1).Analog)
    warning('photCheck:NoRecording','No recorded trial trace; inspect the returned ex for errors or early termination.');
    return
end
trial = ex.Trials(1);
row = find(trial.adcChannels==options.channel,1);
if isempty(row), error('photCheck:ChannelMissing','ADC%d was not recorded.',options.channel); end
n = min([trial.Analog.n,numel(trial.Analog.t),size(trial.Analog.v,2)]);
if n==0
    warning('photCheck:NoSamples','The trial contains no ADC samples.');
    return
end
clock = trial.syncClock;
if ~isfinite(clock.ptbSec) || ~isfinite(clock.datapixxSec)
    error('photCheck:Clock','The trial has no valid ADC/PTB clock reference.');
end
frames = isfinite(trial.flip_info(:,1)) & isfinite(trial.frameSyncBit(:));
if ~any(frames), warning('photCheck:NoFlips','No screen flips were logged.'); return; end
flipTimes = trial.flip_info(frames,1);
bits = trial.frameSyncBit(frames);
t0 = flipTimes(1);
rawVoltage = double(trial.Analog.v(row,1:n));
voltage = rawVoltage;
voltage(voltage>10) = voltage(voltage>10)-20;
pd = struct('channel',options.channel,'sampleRate',options.sampleRate, ...
    'time',double(trial.Analog.t(1:n))-clock.datapixxSec+clock.ptbSec-t0, ...
    'voltage',voltage,'rawVoltage',rawVoltage, ...
    'datapixxTime',trial.Analog.t(1:n),'timeZeroPtb',t0, ...
    'frameTime',flipTimes-t0,'frameBit',bits(:), ...
    'sync',trial.sync,'clockReference',clock);
pd.timing = assessCoPsSyncTimingx(trial);
pd.syncOffTime = trial.syncOffTime-t0;
fprintf('photCheck: recorded %d ADC%d samples at %g Hz; binary code at %.3f bits/s.\n', ...
    n,options.channel,options.sampleRate,trial.sync.bitRateHz);
status = 'FAIL';
if pd.timing.passed, status = 'PASS'; end
fprintf('Timing/coverage %s: %d missed refresh(es) across %d active intervals; %.1f ms ADC tail (requested %.1f ms).\n', ...
    status,pd.timing.missedRefreshes,pd.timing.nActiveIntervals, ...
    1000*pd.timing.capturedTailSecs,1000*pd.timing.requiredTailSecs);
fprintf('This checks timing and recording coverage; inspect the diode trace for the light response.\n');
if ~options.showPlot, return; end
f = figure('Name','Single-trial binary photodiode check','NumberTitle','off');
a = subplot(2,1,1,'Parent',f);
stairs(a,[pd.frameTime;pd.syncOffTime],[pd.frameBit;0],'b');
ylim(a,[-.1 1.1]); yticks(a,[0 1]); yticklabels(a,{'Black','White'});
ylabel(a,'Patch'); title(a,'Submitted binary sequence at actual screen-flip times'); grid(a,'on');
b = subplot(2,1,2,'Parent',f);
plot(b,pd.time,pd.voltage,'k');
ylabel(b,sprintf('ADC%d (V)',options.channel)); xlabel(b,'Seconds after first logged flip');
title(b,'Raw diode signal: display refresh pulses may be visible'); grid(b,'on');
linkaxes([a b],'x');
end
