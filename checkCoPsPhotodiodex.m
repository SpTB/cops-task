function data = checkCoPsPhotodiodex(durationSecs, options)
% Monitor the photodiode voltage without running the task or EyeLink.
%   data = checkCoPsPhotodiodex();                  % ADC0, 15 seconds
%   data = checkCoPsPhotodiodex(30);                % ADC0, 30 seconds
%   data = checkCoPsPhotodiodex(10, channel=6);      % another physical input
%   data = checkCoPsPhotodiodex(10, showPlot=false);
% Cover/uncover the sensor or change screen brightness to check its response.
% Close the plot or press Ctrl+C to stop. Run with the experiment stopped.
arguments
    durationSecs (1,1) double {mustBeFinite,mustBePositive} = 15
    options.channel (1,1) double {mustBeInteger,mustBeNonnegative,mustBeFinite} = 0
    options.sampleRate (1,1) double {mustBeInteger,mustBePositive,mustBeFinite,mustBeLessThanOrEqual(options.sampleRate,200000)} = 2000
    options.showPlot (1,1) logical = true
end

Datapixx('Open');
try
    Datapixx('RegWrRd');
    original = Datapixx('GetAdcStatus');
    if original.scheduleRunning
        error('checkCoPsPhotodiodex:AdcBusy', ...
            'An ADC schedule is already running. Stop the experiment/acquisition before this standalone test.');
    end
catch err
    Datapixx('Close');
    rethrow(err);
end
cleanup = onCleanup(@() closeAdcLocal(original)); %#ok<NASGU>
maxFrames = ceil(durationSecs * options.sampleRate);
bufferFrames = min(maxFrames,max(10000,5*options.sampleRate));
Datapixx('DisableDacAdcLoopback');
Datapixx('DisableAdcFreeRunning');
Datapixx('SetAdcSchedule',0,options.sampleRate,maxFrames,options.channel,4e6,bufferFrames);

figureHandle = [];
trace = [];
if options.showPlot
    figureHandle = figure('Name',sprintf('Photodiode: ADC%d',options.channel),'NumberTitle','off');
    ax = axes('Parent',figureHandle);
    trace = plot(ax,NaN,NaN,'LineWidth',1);
    xlabel(ax,'Time (s)'); ylabel(ax,'Voltage (V)'); grid(ax,'on');
    title(ax,'Cover/uncover the photodiode to check the response');
end

analog = struct('v',[],'t',[],'n',0);
Datapixx('StartAdcSchedule');
Datapixx('RegWrRd');
startTime = GetSecs;
fprintf('Monitoring ADC%d at %g Hz for %g s. Cover/uncover the sensor; close the plot or Ctrl+C to stop.\n', ...
    options.channel,options.sampleRate,durationSecs);
while GetSecs-startTime < durationSecs
    if options.showPlot && ~isgraphics(figureHandle), break; end
    analog = readCoPsAnalogx(analog);
    if options.showPlot && analog.n > 0
        % Show the last five seconds while retaining all samples in data.
        idx = max(1,analog.n-5*options.sampleRate+1):analog.n;
        t = analog.t(idx)-analog.t(1);
        v = voltageLocal(analog.v(1,idx));
        set(trace,'XData',t,'YData',v);
        xlim(ax,[max(0,t(end)-5) max(5,t(end))]);
        title(ax,sprintf('ADC%d: %.4f V',options.channel,v(end)));
        drawnow limitrate;
    end
    WaitSecs('YieldSecs',0.05);
end
% Capture the final buffered samples and release hardware before returning.
Datapixx('StopAdcSchedule');
Datapixx('RegWrRd');
analog = readCoPsAnalogx(analog);
clear cleanup
if analog.n == 0
    error('checkCoPsPhotodiodex:NoSamples','No ADC samples received. Check the DataPixx connection and ADC configuration.');
end
data = struct('channel',options.channel,'sampleRate',options.sampleRate, ...
    'time',analog.t-analog.t(1),'voltage',voltageLocal(analog.v(1,:)), ...
    'rawVoltage',analog.v(1,:),'datapixxTime',analog.t,'n',analog.n);
fprintf('ADC%d: %d samples; min %.4f V, max %.4f V, range %.4f V.\n', ...
    data.channel,data.n,min(data.voltage),max(data.voltage),max(data.voltage)-min(data.voltage));
if options.showPlot && isgraphics(figureHandle)
    set(trace,'XData',data.time,'YData',data.voltage);
    xlim(ax,[0 max(durationSecs,data.time(end))]);
    title(ax,sprintf('ADC%d: recorded voltage (test finished)',options.channel));
    drawnow;
end
end

function v = voltageLocal(v)
% This rig's MEX can wrap negative +/-10 V readings into the 10..20 V range.
v(v>10) = v(v>10)-20;
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
    warning('checkCoPsPhotodiodex:Cleanup','Could not restore ADC settings: %s',err.message);
end
Datapixx('Close');
end
