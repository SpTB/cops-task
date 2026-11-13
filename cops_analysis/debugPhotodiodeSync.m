function out = debugPhotodiodeSync(ex, trialNums, opts)
%DEBUGPHOTODIODESYNC Summarize and optionally plot photodiode ADC pulses.
%
% out = debugPhotodiodeSync(ex, trialNums)
% out = debugPhotodiodeSync(ex, trialNums, opts)
%
% Defaults inspect physical ADC channel 6, the current CoPs photodiode
% sync channel. The row is resolved from T.adcChannels when available and
% falls back to ex.setup.adc.Channels.

if nargin < 2 || isempty(trialNums)
    trialNums = 1:numel(ex.Trials);
end
if nargin < 3 || isempty(opts)
    opts = struct();
end

physicalChannel = localGetScalar(opts, 'physicalChannel', 6);
doPlot = localGetLogical(opts, 'plot', true);

trialNums = double(trialNums(:)');
rows = cell(numel(trialNums), 1);

if doPlot
    figure;
    tiledlayout(numel(trialNums), 1, 'TileSpacing', 'compact');
end

for i = 1:numel(trialNums)
    trialNo = trialNums(i);
    T = ex.Trials(trialNo);
    adcChannels = localAdcChannels(ex, T);
    rowIdx = find(adcChannels == physicalChannel, 1, 'first');

    row = localEmptyRow(trialNo, physicalChannel, rowIdx);
    if isempty(rowIdx) || ~isfinite(rowIdx) || ~isfield(T, 'Eye') || ...
            ~isfield(T.Eye, 'v') || isempty(T.Eye.v) || ...
            ~isfield(T.Eye, 't') || isempty(T.Eye.t)
        rows{i} = row;
        continue
    end

    n = min(size(T.Eye.v, 2), numel(T.Eye.t));
    if isfield(T.Eye, 'n') && isfinite(T.Eye.n) && T.Eye.n > 0
        n = min(n, double(T.Eye.n));
    end
    if n < 2 || rowIdx > size(T.Eye.v, 1)
        rows{i} = row;
        continue
    end

    sig = double(T.Eye.v(rowIdx, 1:n));
    tt = double(T.Eye.t(1:n));
    good = isfinite(sig) & isfinite(tt);
    sig = sig(good);
    tt = tt(good);
    if numel(sig) < 2
        rows{i} = row;
        continue
    end

    lo = prctile(sig, 10);
    hi = prctile(sig, 90);
    thr = (lo + hi) ./ 2;
    isHigh = sig >= thr;
    rising = find(diff(isHigh) == 1) + 1;
    falling = find(diff(isHigh) == -1) + 1;

    row.nSamples = numel(sig);
    row.durationSec = tt(end) - tt(1);
    row.minV = min(sig);
    row.maxV = max(sig);
    row.p10V = lo;
    row.p90V = hi;
    row.thresholdV = thr;
    row.ampP90P10V = hi - lo;
    row.fracHigh = mean(isHigh);
    row.nRising = numel(rising);
    row.nFalling = numel(falling);

    if ~isempty(rising)
        firstRise = rising(1);
        row.firstRiseBufferSec = tt(firstRise) - tt(1);
        fallAfter = falling(falling > firstRise);
        if ~isempty(fallAfter)
            row.firstFallBufferSec = tt(fallAfter(1)) - tt(1);
            row.firstPulseWidthSec = tt(fallAfter(1)) - tt(firstRise);
        end
    end

    row.stimRelSec = localStimRel(T);
    if isfinite(row.firstRiseBufferSec) && isfinite(row.stimRelSec)
        row.firstRiseMinusStimSec = row.firstRiseBufferSec - row.stimRelSec;
    end
    if isfield(T, 'TrialStartDatapixx') && isfinite(T.TrialStartDatapixx) && ~isempty(rising)
        row.firstRiseTrialDpSec = tt(rising(1)) - double(T.TrialStartDatapixx);
    end

    rows{i} = row;

    if doPlot
        nexttile;
        plot(tt - tt(1), sig, 'k');
        hold on;
        yline(thr, '--r');
        if isfinite(row.stimRelSec)
            xline(row.stimRelSec, '--b');
        end
        if isfinite(row.firstRiseBufferSec)
            xline(row.firstRiseBufferSec, '-g');
        end
        ylabel(sprintf('T%d ch%d', trialNo, physicalChannel));
        if i == numel(trialNums)
            xlabel('Time from ADC buffer start (s)');
        end
        title(sprintf('row %g, rise %g, fracHigh %.3f, amp %.3g V', ...
            rowIdx, row.nRising, row.fracHigh, row.ampP90P10V));
    end
end

out = struct2table(vertcat(rows{:}));
end


function row = localEmptyRow(trialNo, physicalChannel, rowIdx)
row = struct( ...
    'trial', trialNo, ...
    'physicalChannel', physicalChannel, ...
    'rowIdx', rowIdx, ...
    'nSamples', 0, ...
    'durationSec', NaN, ...
    'minV', NaN, ...
    'maxV', NaN, ...
    'p10V', NaN, ...
    'p90V', NaN, ...
    'thresholdV', NaN, ...
    'ampP90P10V', NaN, ...
    'fracHigh', NaN, ...
    'nRising', 0, ...
    'nFalling', 0, ...
    'firstRiseBufferSec', NaN, ...
    'firstFallBufferSec', NaN, ...
    'firstPulseWidthSec', NaN, ...
    'stimRelSec', NaN, ...
    'firstRiseMinusStimSec', NaN, ...
    'firstRiseTrialDpSec', NaN);
end


function adcChannels = localAdcChannels(ex, T)
adcChannels = [];
if isstruct(T) && isfield(T, 'adcChannels') && isnumeric(T.adcChannels)
    adcChannels = double(T.adcChannels(:)');
elseif isstruct(T) && isfield(T, 'scheduledChannels') && isnumeric(T.scheduledChannels)
    adcChannels = double(T.scheduledChannels(:)');
elseif isfield(ex, 'setup') && isfield(ex.setup, 'adc') && ...
        isfield(ex.setup.adc, 'Channels') && isnumeric(ex.setup.adc.Channels)
    adcChannels = double(ex.setup.adc.Channels(:)');
end
end


function value = localStimRel(T)
value = NaN;
if isfield(T, 'times') && isstruct(T.times) && isfield(T.times, 'stimOn') && ...
        ~isempty(T.times.stimOn) && isfield(T, 'TrialStart') && ~isempty(T.TrialStart)
    value = double(T.times.stimOn(1)) - double(T.TrialStart(1));
end
end


function value = localGetScalar(s, fieldName, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName)) && isnumeric(s.(fieldName))
    candidate = double(s.(fieldName)(1));
    if isfinite(candidate)
        value = candidate;
    end
end
end


function value = localGetLogical(s, fieldName, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    rawValue = s.(fieldName);
    if islogical(rawValue)
        value = logical(rawValue(1));
    elseif isnumeric(rawValue)
        value = isfinite(rawValue(1)) && rawValue(1) ~= 0;
    end
end
end
