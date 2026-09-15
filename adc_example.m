clear; clc;

Datapixx('Open');
Datapixx('StopAllSchedules');

% ---- Adjust to match your working plot function ----
sampleRate   = 500;          % use same rate as your working script
bufferSize   = 10000;
adcChannels  = 0:5;          % EXACT same channels as your working plot

Datapixx('SetAdcSchedule', 0, sampleRate, bufferSize, adcChannels);
Datapixx('StartAdcSchedule');
Datapixx('RegWrRd');

fprintf('Running ADC print test. Press Ctrl+C to stop.\n\n');

while true

    Datapixx('RegWrRd');
    status = Datapixx('GetAdcStatus');
    nFrames = status.newBufferFrames;

    if nFrames > 0

        % ---- Use the 4-output signature your MEX expects ----
        [data_raw, timetags, underflow, overflow] = ...
            Datapixx('ReadAdcBuffer', nFrames);

        % Compute raw mean for first scheduled channel
        rawMean = mean(data_raw(1,:));

        % ---- Apply wrap correction (±10 V case) ----
        data_corr = data_raw;
        data_corr(data_corr > 10) = data_corr(data_corr > 10) - 20;

        corrMean = mean(data_corr(1,:)); %mean voltage channel 1

        % Instantaneous reading
        vInst = Datapixx('GetAdcVoltages');

        % Physical channel corresponding to row 1:
        physIdx = adcChannels(1) + 1;   % convert 0-based to MATLAB index

        instVal = vInst(physIdx);

        fprintf('Raw: %8.4f   Corrected: %8.4f   Instant: %8.4f\n', ...
                rawMean, corrMean, instVal);

    end

    pause(0.05);
end
%Output:
%Raw:  18.5724   Corrected:  -1.4276   Instant:  -1.4334
%Raw:  18.5609   Corrected:  -1.4391   Instant:  -1.4398
%Raw:  18.5609   Corrected:  -1.4391   Instant:  -1.4374