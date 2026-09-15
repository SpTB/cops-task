function data_corrected = correctAdcBuffer(data, scheduledChannels)
% data: nSchedChannels x nSamples (as returned by Datapixx('ReadAdcBuffer',...))
% scheduledChannels: 0-based vector of physical channel indices in same order used in SetAdcSchedule
% returns data_corrected same size as data, with values shifted into bipolar range when needed

if isempty(data)
    data_corrected = data;
    return;
end

% get hardware ranges (2 x Nphys)
ranges = Datapixx('GetAdcRanges'); % row1 = mins, row2 = maxs
% convert scheduledChannels to MATLAB 1-based indices
physIdx = scheduledChannels + 1;

[nRows, ~] = size(data);
if nRows ~= numel(physIdx)
    warning('Number of rows in data (%d) does not match scheduledChannels length (%d). Proceeding with min length.', nRows, numel(physIdx));
    nRows = min(nRows, numel(physIdx));
    data = data(1:nRows, :);
    physIdx = physIdx(1:nRows);
end

data_corrected = data; % initialize

tol = 1e-6; % small tolerance for floating comparisons

for r = 1:nRows
    p = physIdx(r);
    chMin = ranges(1,p);
    chMax = ranges(2,p);
    span = chMax - chMin;    % e.g., 20 for -10..+10
    % If span <= 0 something is wrong; skip correction
    if span <= 0
        continue;
    end
    % Identify samples that lie above the expected max (likely wrapped)
    idxWrap = data(r,:) > (chMax - tol);
    if any(idxWrap)
        % subtract full span for wrapped samples
        data_corrected(r, idxWrap) = data(r, idxWrap) - span;
    end
    % Also handle samples that might be below chMin + tol + not needed usually
    % (if for some reason values are below chMin you could add span, but not expected)
end
end