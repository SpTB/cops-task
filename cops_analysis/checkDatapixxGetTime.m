function out = checkDatapixxGetTime(opts)
% checkDatapixxGetTime  Online sanity check for Datapixx clock semantics.
%
% out = checkDatapixxGetTime()
% out = checkDatapixxGetTime(opts)
%
% This verifies whether Datapixx('GetTime') behaves like a live Datapixx
% clock and whether ADC timetags are in the same clock basis. Do not run
% during a real trial: reading the ADC buffer consumes unread samples.
%
% opts.waitSec        default 0.5, wait duration for GetTime clock test
% opts.nRepeats       default 5, number of GetTime clock tests
% opts.readAdc        default true, also read current ADC buffer timetags
% opts.maxAdcFrames   default 2000, cap ADC frames read for the timetag test

if nargin < 1 || isempty(opts)
    opts = struct();
end

defaults = struct( ...
    'waitSec', 0.5, ...
    'nRepeats', 5, ...
    'readAdc', true, ...
    'maxAdcFrames', 2000);
fields = fieldnames(defaults);
for i = 1:numel(fields)
    f = fields{i};
    if ~isfield(opts, f)
        opts.(f) = defaults.(f);
    end
end

Datapixx('Open');
Datapixx('RegWrRd');

nRepeats = max(1, round(double(opts.nRepeats)));
waitSec = max(0, double(opts.waitSec));

ptbDeltaSec = NaN(nRepeats, 1);
dpDeltaSec = NaN(nRepeats, 1);
deltaErrorSec = NaN(nRepeats, 1);
dp0 = NaN(nRepeats, 1);
dp1 = NaN(nRepeats, 1);
ptb0 = NaN(nRepeats, 1);
ptb1 = NaN(nRepeats, 1);

for k = 1:nRepeats
    Datapixx('RegWrRd');
    ptb0(k) = GetSecs;
    dp0(k) = Datapixx('GetTime');
    localWait(waitSec);
    Datapixx('RegWrRd');
    ptb1(k) = GetSecs;
    dp1(k) = Datapixx('GetTime');
    ptbDeltaSec(k) = ptb1(k) - ptb0(k);
    dpDeltaSec(k) = dp1(k) - dp0(k);
    deltaErrorSec(k) = dpDeltaSec(k) - ptbDeltaSec(k);
end

clock = table((1:nRepeats)', ptb0, ptb1, dp0, dp1, ptbDeltaSec, dpDeltaSec, deltaErrorSec, ...
    'VariableNames', {'repeat','ptb0','ptb1','dp0','dp1','ptbDeltaSec','dpDeltaSec','deltaErrorSec'});

adc = table();
if logical(opts.readAdc)
    Datapixx('RegWrRd');
    status = Datapixx('GetAdcStatus');
    nFrames = min(double(status.newBufferFrames), max(0, round(double(opts.maxAdcFrames))));
    if nFrames > 0
        dpBeforeRead = Datapixx('GetTime');
        [~, adcTime] = Datapixx('ReadAdcBuffer', nFrames, -1);
        Datapixx('RegWrRd');
        dpAfterRead = Datapixx('GetTime');
        adcTime = double(adcTime(:));
        adcFirst = adcTime(1);
        adcLast = adcTime(end);
        adcSpanSec = adcLast - adcFirst;
        adcFirstMinusDpBeforeSec = adcFirst - dpBeforeRead;
        adcLastMinusDpAfterSec = adcLast - dpAfterRead;
        adc = table(nFrames, dpBeforeRead, dpAfterRead, adcFirst, adcLast, adcSpanSec, ...
            adcFirstMinusDpBeforeSec, adcLastMinusDpAfterSec, ...
            'VariableNames', {'nFrames','dpBeforeRead','dpAfterRead','adcFirst','adcLast', ...
            'adcSpanSec','adcFirstMinusDpBeforeSec','adcLastMinusDpAfterSec'});
    end
end

summary = struct();
summary.medianPtbDeltaSec = median(ptbDeltaSec, 'omitnan');
summary.medianDpDeltaSec = median(dpDeltaSec, 'omitnan');
summary.medianDeltaErrorSec = median(deltaErrorSec, 'omitnan');
summary.maxAbsDeltaErrorSec = max(abs(deltaErrorSec), [], 'omitnan');
summary.hasAdcTiming = ~isempty(adc);
if ~isempty(adc)
    summary.adcFirstMinusDpBeforeSec = adc.adcFirstMinusDpBeforeSec(1);
    summary.adcLastMinusDpAfterSec = adc.adcLastMinusDpAfterSec(1);
end

out = struct();
out.clock = clock;
out.adc = adc;
out.summary = summary;

disp(clock);
if ~isempty(adc)
    disp(adc);
end
fprintf('Median GetTime delta error: %.6g s\n', summary.medianDeltaErrorSec);
if ~isempty(adc)
    fprintf('ADC first - GetTime before read: %.6g s\n', summary.adcFirstMinusDpBeforeSec);
    fprintf('ADC last  - GetTime after read : %.6g s\n', summary.adcLastMinusDpAfterSec);
end
end


function localWait(waitSec)
if exist('WaitSecs', 'file') || exist('WaitSecs', 'builtin')
    WaitSecs(waitSec);
else
    pause(waitSec);
end
end
