function out = decodeCoPsSyncx(trial, sampleTimes, voltage, options)
% Align a recorded photodiode trace to the submitted frame code, offline.
% out = decodeCoPsSyncx(ex.Trials(i)) uses recorded Analog/Eye data and channels.
% External traces: supply times and voltages; sameClock=true means PTB seconds.
% See docs/photodiode_sync.md for clock, confidence, and frame-drop limitations.
arguments
    trial struct
    sampleTimes double = []
    voltage double = []
    options.sameClock (1,1) logical = false
    options.thresholdV (1,1) double = NaN
    options.invert (1,1) logical = false
    options.maxLagSec (1,1) double {mustBePositive,mustBeFinite} = 0.25
    options.maxDriftPpm (1,1) double {mustBeNonnegative,mustBeFinite} = 2000
    options.minStableSamples (1,1) double {mustBeInteger,mustBePositive} = 2
    options.waveform (1,1) string {mustBeMember(options.waveform,["auto","continuous","pulsed"])} = "auto"
    options.plot (1,1) logical = false
end
if ~isfield(trial, 'sync') || ~strcmp(trial.sync.mode, 'binary')
    error('decodeCoPsSyncx:NotBinary', 'This trial does not contain a binary sync protocol.');
end
if isempty(sampleTimes) && isempty(voltage)
    if isfield(trial, 'Analog') && ~isempty(trial.Analog)
        analog = trial.Analog;
    elseif isfield(trial, 'inputSource') && strcmp(trial.inputSource, 'eye')
        analog = trial.Eye;
    else
        error('decodeCoPsSyncx:NoAnalog', ...
            'No ADC trace recorded. Supply a trace or record the photodiode through the existing eye-input ADC schedule.');
    end
    row = find(trial.adcChannels == trial.sync.physicalChannel, 1);
    if isempty(row), error('decodeCoPsSyncx:ChannelMissing', 'Photodiode channel was not recorded.'); end
    n = min(numel(analog.t), analog.n);
    sampleTimes = double(analog.t(1:n));
    voltage = double(analog.v(row,1:n));
end
if numel(sampleTimes) ~= numel(voltage)
    error('decodeCoPsSyncx:SizeMismatch', 'Provide one voltage for each sample timestamp.');
end
s = sampleTimes(:);
v = voltage(:);
good = isfinite(s) & isfinite(v);
s = s(good); v = v(good);
if numel(s) < 20 || any(diff(s) <= 0)
    error('decodeCoPsSyncx:InvalidSamples', 'Need at least 20 finite samples with strictly increasing timestamps.');
end
clockUncertainty = 0;
if ~options.sameClock
    if isfield(trial, 'syncClock') && isfinite(trial.syncClock.datapixxSec)
        s = s - trial.syncClock.datapixxSec + trial.syncClock.ptbSec;
        clockUncertainty = trial.syncClock.uncertaintySec;
    elseif isfield(trial, 'TrialStartDatapixx') && isfinite(trial.TrialStartDatapixx)
        s = s - trial.TrialStartDatapixx + trial.TrialStart;
        clockUncertainty = NaN;
    else
        error('decodeCoPsSyncx:NoClockReference', ...
            'No ADC/PTB clock reference. Convert external timestamps to PTB seconds and use sameClock=true.');
    end
end
t = double(trial.flip_info(:,1));
b = double(trial.frameSyncBit(:));
phase = trial.frameSyncPhase(:);
good = isfinite(t) & isfinite(b);
frameNumbers = find(good);
t = t(good); b = b(good); phase = phase(good);
if numel(t) < 3 || any(diff(t) <= 0) || nnz(phase == 3) < 10
    error('decodeCoPsSyncx:InsufficientCode', 'Need at least 10 logged payload frames with increasing flip timestamps.');
end
payloadStart = t(find(phase == 3, 1));
payloadEnd = t(find(phase == 3, 1, 'last'));
ifi = trial.sync.refreshIntervalSec;
if isfield(trial, 'syncOffTime') && trial.syncOffTime > t(end)
    t(end+1) = trial.syncOffTime; b(end+1) = 0;
end
inside = s >= t(1)-options.maxLagSec & s <= t(end)+options.maxLagSec;
s = s(inside); v = v(inside);
if numel(s) < 20, error('decodeCoPsSyncx:NoOverlap', 'ADC trace does not overlap the logged frame times.'); end
if options.waveform ~= "continuous"
    out = decodeAutomaticLocal(trial,s,v,options,clockUncertainty);
    return
end
levels = sort(v);
low = levels(max(1, round(0.1*numel(levels))));
high = levels(max(1, round(0.9*numel(levels))));
if high-low <= max(1e-9, eps(max(abs(levels))))
    error('decodeCoPsSyncx:NoContrast', 'Photodiode trace has no usable black/white contrast.');
end
threshold = options.thresholdV;
if isnan(threshold), threshold = (low+high)/2; end
logic = schmittLocal(v, threshold, 0.05*(high-low), options.minStableSamples);
if options.invert, logic = ~logic; end
observedEdgeIdx = find(diff(logic) ~= 0) + 1;
% The crossing occurred between the bracketing samples; using the first high
% sample would bias every fitted latency upward by about half a sample.
observedEdges = (s(observedEdgeIdx-1)+s(observedEdgeIdx))/2;
observedSign = sign(diff(double(logic)));
observedSign = observedSign(observedEdgeIdx-1);
edgeIdx = find(diff(b) ~= 0) + 1;
expectedEdges = t(edgeIdx);
expectedSign = sign(diff(b));
expectedSign = expectedSign(edgeIdx-1);
if numel(observedEdges) < 4 || numel(expectedEdges) < 4
    error('decodeCoPsSyncx:InsufficientEdges', 'Need at least four transitions to align a binary trace.');
end

% Search a bounded clock offset/drift, then refine using matched edges.
ref = t(1);
dt = median(diff(s));
lagGrid = linspace(-options.maxLagSec, options.maxLagSec, ...
    min(1001, max(3, ceil(2*options.maxLagSec/dt)+1)));
scaleGrid = unique(1 + linspace(-options.maxDriftPpm, options.maxDriftPpm, 9)*1e-6);
subset = unique(round(linspace(1, numel(s), min(2000,numel(s)))));
scores = -inf(numel(scaleGrid), numel(lagGrid));
for a = 1:numel(scaleGrid)
    for c = 1:numel(lagGrid)
        scores(a,c) = scoreLocal(t, b, s(subset), logic(subset), ref, ...
            lagGrid(c), scaleGrid(a), payloadStart, payloadEnd);
    end
end
[peak, best] = max(scores(:));
[a,c] = ind2sub(size(scores), best);
lag = lagGrid(c); scale = scaleGrid(a);
other = scores(:, abs(lagGrid-lag) > 2*ifi);
margin = Inf;
if ~isempty(other), margin = peak - max(other(:)); end
for k = 1:4
    [ei, oi] = matchEdgesLocal(expectedEdges, expectedSign, observedEdges, observedSign, ref, lag, scale, 0.45*ifi);
    if numel(ei) < 8, break; end
    x = expectedEdges(ei)-ref;
    y = observedEdges(oi)-ref;
    residual = y - (lag+scale*x);
    med = median(residual);
    keep = abs(residual-med) <= max(2*dt, 4*median(abs(residual-med)));
    if nnz(keep) < 8, break; end
    if options.maxDriftPpm == 0
        fit = [median(y(keep)-x(keep)); 1];
    else
        fit = [ones(nnz(keep),1), x(keep)] \ y(keep);
    end
    if abs(fit(2)-1)*1e6 > options.maxDriftPpm + 1, break; end
    lag = fit(1); scale = fit(2);
end
[matchFraction, coverage] = scoreLocal(t,b,s,logic,ref,lag,scale,payloadStart,payloadEnd);
[ei,oi] = matchEdgesLocal(expectedEdges,expectedSign,observedEdges,observedSign,ref,lag,scale,0.45*ifi);
residual = observedEdges(oi) - (ref+lag+scale*(expectedEdges(ei)-ref));

% Compare each frame at its actual hold midpoint, with fitted clock mapping.
frameEnd = [t(2:numel(frameNumbers)); t(numel(frameNumbers))+ifi];
if numel(t) > numel(frameNumbers), frameEnd(end) = t(end); end
midpoints = (t(1:numel(frameNumbers))+frameEnd)/2;
query = ref+lag+scale*(midpoints-ref);
observedBit = interp1(s, double(logic), query, 'previous', NaN);
mismatch = isfinite(observedBit) & observedBit ~= b(1:numel(frameNumbers));
intervals = diff(t(1:numel(frameNumbers)));
activeIntervals = phase(1:end-1) > 0 & phase(2:end) > 0;
long = find(activeIntervals & intervals > 1.5*ifi);
out = struct('lagSec', lag, 'clockDriftPpm', (scale-1)*1e6, ...
    'clockReferenceUncertaintySec', clockUncertainty, 'sampleIntervalSec', dt, ...
    'thresholdV', threshold, 'matchFraction', matchFraction, 'coverage', coverage, ...
    'alignmentPeakMargin', margin, ...
    'alignmentReliable', matchFraction >= 0.85 && coverage >= 0.8 && numel(ei) >= 8 && margin > 0.01, ...
    'nMatchedEdges', numel(ei), 'nUnmatchedExpectedEdges', numel(expectedEdges)-numel(ei), ...
    'edgeResidualSec', residual, 'expectedEdgeTimes', expectedEdges, ...
    'observedEdgeTimes', observedEdges, 'mismatchedFrameIndices', frameNumbers(mismatch), ...
    'longFlipIntervalFrameIndices', frameNumbers(long+1), ...
    'estimatedMissedRefreshes', sum(max(0,round(intervals(activeIntervals)/ifi)-1)), ...
    'maxActiveFlipIntervalSec', max([NaN; intervals(activeIntervals)], [], 'omitnan'));
out.waveform = 'continuous';
out.envelopeWindowSec = 0;
out.lagInterpretation = 'fitted light-level edge delay, including clock-reference error';
out.continuousMatchFraction = matchFraction;
out.envelopeMatchFraction = NaN;
out.signalInverted = options.invert;
if options.plot
    plotDecodedLocal(trial,s,v,[],out);
end
end

function out = decodeAutomaticLocal(trial,s,v,options,clockUncertainty)
% Try the legacy light-level decoder first. DLP projectors can pulse even
% while displaying white; decode the mean light envelope if levels fail.
inner = options; inner.sameClock = true; inner.plot = false; inner.waveform = "continuous";
continuous = []; continuousError = [];
if options.waveform == "auto"
    try
        args = namedargs2cell(inner);
        continuous = decodeCoPsSyncx(trial,s,v,args{:});
    catch err
        if ~ismember(err.identifier, {'decodeCoPsSyncx:InsufficientEdges','decodeCoPsSyncx:NoContrast'})
            rethrow(err)
        end
        continuousError = err;
    end
    if ~isempty(continuous) && continuous.alignmentReliable
        out = continuous; out.clockReferenceUncertaintySec = clockUncertainty;
        if options.plot, plotDecodedLocal(trial,s,v,[],out); end
        return
    end
end
try
    [envelope,threshold] = pulseEnvelopeLocal(trial,s,v,options.invert);
    if isnan(options.thresholdV), inner.thresholdV = threshold; end
    args = namedargs2cell(inner);
    pulsed = decodeCoPsSyncx(trial,s,envelope,args{:});
    pulsed.waveform = 'pulsed';
    pulsed.envelopeWindowSec = trial.sync.refreshIntervalSec;
    pulsed.envelopeMatchFraction = pulsed.matchFraction;
    pulsed.continuousMatchFraction = NaN;
    pulsed.lagInterpretation = ['alignment of a centred one-refresh light envelope; ' ...
        'not a direct measurement of the first optical pulse'];
catch err
    if ~ismember(err.identifier, {'decodeCoPsSyncx:InsufficientEdges','decodeCoPsSyncx:NoContrast'})
        rethrow(err)
    end
    if ~isempty(continuous)
        out = continuous; out.clockReferenceUncertaintySec = clockUncertainty;
        if options.plot, plotDecodedLocal(trial,s,v,[],out); end
        return
    end
    if ~isempty(continuousError), rethrow(continuousError); end
    rethrow(err)
end
out = pulsed;
if ~isempty(continuous)
    pulsed.continuousMatchFraction = continuous.matchFraction;
    if continuous.matchFraction > pulsed.matchFraction && ~pulsed.alignmentReliable
        out = continuous; envelope = [];
    else
        out = pulsed;
    end
end
out.clockReferenceUncertaintySec = clockUncertainty;
if options.plot, plotDecodedLocal(trial,s,v,envelope,out); end
end

function [envelope,threshold] = pulseEnvelopeLocal(trial,s,v,inverted)
% Integrate measured voltage in time, rather than counting high ADC samples.
% A centred window avoids introducing a fixed extra half-refresh delay.
w = trial.sync.refreshIntervalSec;
integral = [0; cumsum(diff(s).*(v(1:end-1)+v(2:end))/2)];
left = max(s(1),s-w/2); right = min(s(end),s+w/2);
envelope = (interp1(s,integral,right)-interp1(s,integral,left))./(right-left);
sorted = sort(envelope);
low = sorted(max(1,round(.1*numel(sorted))));
high = sorted(max(1,round(.75*numel(sorted))));
threshold = (low+high)/2;
% Learn white/black envelope levels from the independent GO marker and gap,
% rather than using the payload's expected bits to choose the threshold.
t = trial.flip_info(:,1); phase = trial.frameSyncPhase(:);
first = find(phase==1,1); gap = find(phase==2,1); payload = find(phase==3,1);
if ~isempty(first) && ~isempty(gap) && ~isempty(payload)
    white = envelope(s>=t(first)+w & s<=t(gap)-w);
    black = envelope(s>=t(gap)+w & s<=t(payload)-w);
    if numel(white)>=3 && numel(black)>=3
        hi = median(white); lo = median(black);
        direction = 1; if inverted, direction = -1; end
        span = sorted(max(1,round(.99*numel(sorted))))-sorted(max(1,round(.01*numel(sorted))));
        if direction*(hi-lo) > .1*span
            threshold = (hi+lo)/2;
        end
    end
end
end

function plotDecodedLocal(trial,s,v,envelope,out)
t = trial.flip_info(:,1); b = double(trial.frameSyncBit(:));
good = isfinite(t) & isfinite(b); t=t(good); b=b(good);
ref=t(1);
if isfield(trial,'syncOffTime') && trial.syncOffTime>t(end)
    t(end+1)=trial.syncOffTime; b(end+1)=0;
end
signal=v; if ~isempty(envelope), signal=envelope; end
levels=sort(signal); lo=levels(max(1,round(.1*numel(levels))));
hi=levels(max(1,round(.9*numel(levels))));
mapped=ref+out.lagSec+(1+out.clockDriftPpm*1e-6)*(t-ref);
if out.signalInverted, b=1-b; end
figure; plot(s-ref,v); hold on;
labels={'Recorded voltage'};
if ~isempty(envelope)
    plot(s-ref,envelope,'LineWidth',1); labels{end+1}='One-refresh light envelope';
end
stairs(mapped-ref,lo+(hi-lo)*b,'LineWidth',1); labels{end+1}='Aligned frame code';
yline(out.thresholdV,':'); labels{end+1}='Threshold';
xlabel('Time from first logged flip (s)'); ylabel('Photodiode voltage'); legend(labels);
title(sprintf('%s; match %.1f%%; alignment reliable=%d',out.waveform,100*out.matchFraction,out.alignmentReliable));
end

function logic = schmittLocal(v, threshold, halfWidth, stable)
logic = false(size(v));
state = v(1) >= threshold;
pending = 0;
for k = 1:numel(v)
    opposite = (~state && v(k) >= threshold+halfWidth) || (state && v(k) <= threshold-halfWidth);
    if opposite
        if pending == 0, pending = k; end
        if k-pending+1 >= stable
            state = ~state;
            logic(pending:k) = state;
            pending = 0;
        end
    else
        pending = 0;
    end
    logic(k) = state;
end
end

function [score, coverage] = scoreLocal(t,b,s,logic,ref,lag,scale,first,last)
query = ref+(s-ref-lag)/scale;
valid = query >= first & query <= last;
coverage = 0; score = -Inf;
if nnz(valid) < 20, return; end
expected = interp1(t,b,query(valid),'previous');
actual = logic(valid);
zero = expected == 0; one = expected == 1;
if ~any(zero) || ~any(one), return; end
score = (mean(~actual(zero))+mean(actual(one)))/2;
coverage = min(1, (max(query(valid))-min(query(valid))) / (last-first));
end

function [ei,oi] = matchEdgesLocal(expected,signE,observed,signO,ref,lag,scale,tolerance)
ei = []; oi = [];
predicted = ref+lag+scale*(expected-ref);
for k = 1:numel(expected)
    candidates = find(signO == signE(k));
    if isempty(candidates), continue; end
    [distance,j] = min(abs(observed(candidates)-predicted(k)));
    if distance <= tolerance
        ei(end+1,1) = k; oi(end+1,1) = candidates(j); %#ok<AGROW>
    end
end
[~,keep] = unique(oi,'stable');
ei = ei(keep); oi = oi(keep);
end
