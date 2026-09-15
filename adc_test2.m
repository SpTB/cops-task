% Read voltages from a single channel for a few seconds and plot

AssertOpenGL;                   % We use PTB-3

 

Datapixx('Open');

Datapixx('StopAllSchedules');

Datapixx('RegWrRd');            % Synchronize DATAPixx registers to local register cache

 

adcSchedOnset = 0;                          % desired delay (in double precision seconds) between schedule initiation, and the first ADC sample acquisition

adcRate = 10000;                            % Acquire ADC data at 10kHz

adcSamplePeriod = 4;                        % number of seconds to acquire data

adcSamples = adcRate*adcSamplePeriod;       % Schedule ends when this number is reached

adcChannel = 0;                             % ADC Channel to sample

adcBuffBaseAddr = 4e6;                      % DATAPixx internal buffer address

adcBufferFrames = adcSamples;               % size of acquisition buffer on DataPixx; since acquiring only one channel, for a small amount of time, do not need to stream to host and equal to "maxScheduleFrames". 128MB available

Datapixx('SetAdcSchedule', adcSchedOnset, adcRate, adcSamples, adcChannel, adcBuffBaseAddr, adcBufferFrames);

 

Datapixx('DisableDacAdcLoopback');

Datapixx('DisableAdcFreeRunning');          % manually set acquisition rate (for microsecond-precise sample windows)

Datapixx('StartAdcSchedule');

Datapixx('RegWrRd');                        % This will cause the acquisition to start

 

WaitSecs(adcSamplePeriod+0.5);              % Wait for acquisition to complete

 

% Read Data

[adcData, timeData] = Datapixx('ReadAdcBuffer', adcSamples, adcBuffBaseAddr);
adcData(adcData>10)=adcData(adcData>10)-20;
 

% Create plot of adcChannel vs time

h = plot(timeData,adcData,"DisplayName","ch"+adcChannel);

 

% Add xlabel, ylabel, title, and legend

xlabel("timeData")

ylabel("adcChan: "+adcChannel)

title("adcData vs. timeData")

legend

 

Datapixx('StopAllSchedules');

Datapixx('RegWrRd');

 

Datapixx('Close');