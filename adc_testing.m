% clear; clc;

try
    Datapixx('Open');
    Datapixx('StopAllSchedules');

    % -------- ADC configuration (adjust these) --------
    sampleRate   = 500;        % Hz (set to actual ADC schedule rate)
    adcChannels  = [0,1,3,4];     % channels in the order you want plotted
    bufferSize   = 10000;       % hardware buffer size (samples)
    windowSec     = 5;          % seconds shown on x-axis (rolling window)
    maxUpdateRate = 30;         % max plot updates per second

    nChannels = length(adcChannels);
    windowSamples = round(windowSec * sampleRate);

    % Set up ADC
    Datapixx('SetAdcSchedule', 0, sampleRate, bufferSize, adcChannels);
    Datapixx('StartAdcSchedule');
    Datapixx('RegWrRd');

    % ===== Rolling buffer state =====
    rollBuf = nan(nChannels, windowSamples);
    writePos = 1;               % next write column (1..windowSamples)
    totalSamplesSeen = 0;

    xFixed = linspace(-windowSec, 0, windowSamples);

    % ---- Plot setup ----
    figure('Name','Rolling Multi-Channel ADC','NumberTitle','off');
    hold on;
    hPlot = gobjects(nChannels,1);
    for ch = 1:nChannels
        hPlot(ch) = plot(xFixed, nan(1,windowSamples), 'LineWidth', 1.2);
    end
    xlabel('Time (s)');
    ylabel('Voltage (V)');
    title(sprintf('ADC channels: %s  |  Window = %d s', mat2str(adcChannels), windowSec));
    legend(arrayfun(@(c) sprintf('Ch %d', c), adcChannels, 'UniformOutput', false), ...
           'Location','northeastoutside');
    xlim([-windowSec 0]);
    grid on;

    lastPlotTime = tic;
    minPlotInterval = 1 / maxUpdateRate;

    fprintf('ADC sampling started. Showing last %d seconds on x-axis.\n', windowSec);
    fprintf('Press Ctrl+C or close figure to stop.\n');

    while ishandle(hPlot(1))
        Datapixx('RegWrRd');
        status = Datapixx('GetAdcStatus');
        newSamples = status.newBufferFrames;

        if newSamples > 0
            data = Datapixx('ReadAdcBuffer', newSamples);
            if size(data,1) > nChannels
                data = data(1:nChannels, :);
            end

            %data(data>10)=data(data>10)-20;
            nNew = size(data,2);
            totalSamplesSeen = totalSamplesSeen + nNew;

            % write into circular buffer (may wrap)
            remaining = nNew;
            srcStart = 1;
            while remaining > 0
                chunkLen = min(remaining, windowSamples - writePos + 1);
                rollBuf(:, writePos:(writePos+chunkLen-1)) = data(:, srcStart:(srcStart+chunkLen-1));
                writePos = writePos + chunkLen;
                if writePos > windowSamples
                    writePos = 1;
                end
                srcStart = srcStart + chunkLen;
                remaining = remaining - chunkLen;
            end
        end

        % update plot at limited rate
        if toc(lastPlotTime) >= minPlotInterval
            viewData = nan(nChannels, windowSamples);

            if totalSamplesSeen == 0
                % nothing to show yet — keep NaNs
            elseif totalSamplesSeen < windowSamples
                fillCols = totalSamplesSeen;
                % build 'recent' in chronological order (oldest → newest)
                if writePos == 1
                    % data written starting at col 1
                    recent = rollBuf(:, 1:fillCols);
                else
                    startIdx = writePos - fillCols;
                    if startIdx >= 1
                        recent = rollBuf(:, startIdx:(writePos-1));
                    else
                        % wrapped: take tail then head
                        recent = [rollBuf(:, (startIdx+windowSamples):windowSamples), ...
                                  rollBuf(:, 1:(writePos-1))];
                    end
                end
                nRecent = size(recent,2);
                % right-align the recent data into viewData
                viewData(:, end-nRecent+1:end) = recent;
            else
                % full window: chronological order starts at writePos
                idx = [writePos:windowSamples, 1:writePos-1];
                viewData = rollBuf(:, idx);
            end

            % update plots
            for ch = 1:nChannels
                set(hPlot(ch), 'XData', xFixed, 'YData', viewData(ch,:));
            end

            drawnow limitrate;
            lastPlotTime = tic;
        end

        pause(0.1);
    end

    Datapixx('StopAdcSchedule');
    Datapixx('Close');
    fprintf('Stopped (figure closed).\n');

catch ME
    try Datapixx('StopAdcSchedule'); Datapixx('Close'); end %#ok<TRYNC>
    rethrow(ME);
end