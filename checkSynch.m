function out = checkSynch(ex, trialNum, opts)
% checkSynch  Plot and summarize the CoPs photodiode sync signal.
%
% out = checkSynch(ex, trialNum)
% out = checkSynch(ex, trialNum, opts)
%
% Defaults use physical ADC channel 6 and threshold 0.3 V, matching the
% current CoPs photodiode GO-pulse settings.

if nargin < 2 || isempty(trialNum)
    trialNum = numel(ex.Trials);
end
if nargin < 3 || isempty(opts)
    opts = struct();
end

physicalChannel = localOptScalar(ex, opts, ...
    {'physicalChannel','photodiodePulsePhysicalChannel','syncPhysicalChannel'}, 6);
thresholdV = localOptScalar(ex, opts, ...
    {'thresholdV','photodiodePulseThresholdV','syncThreshold'}, 0.3);
minEdgeSepSec = localOptScalar(ex, opts, ...
    {'minEdgeSepSec','photodiodePulseMinPulseWidthSec','syncMinPulseWidthSec'}, 0.02);
pulseWindowSec = localOptScalar(ex, opts, ...
    {'pulseWindowSec','photodiodePulseWindowSec','syncPulseWindowSec'}, 0.5);
polarity = localOptText(opts, {'polarity','photodiodePulsePolarity','syncPolarity'}, 'rising');

trialNum = double(trialNum(:)');
rows = cell(numel(trialNum), 1);

figure;
tiledlayout(numel(trialNum), 1, 'TileSpacing', 'compact');

for iTrial = 1:numel(trialNum)
    trialNo = trialNum(iTrial);
    T = ex.Trials(trialNo);
    adcChannels = localAdcChannels(ex, T);
    rowIdx = find(adcChannels == physicalChannel, 1, 'first');
    if isempty(rowIdx)
        rowIdx = NaN;
    end
    row = localEmptyRow(trialNo, physicalChannel, rowIdx, thresholdV);

    nexttile;
    hold on;

    if ~isfinite(rowIdx) || ~isfield(T, 'Eye') || ~isfield(T.Eye, 'v') || ...
            ~isfield(T.Eye, 't') || isempty(T.Eye.v) || isempty(T.Eye.t)
        title(sprintf('Trial %d: no ADC data or channel %d not recorded', trialNo, physicalChannel));
        rows{iTrial} = row;
        continue
    end

    nSamples = min(size(T.Eye.v, 2), numel(T.Eye.t));
    if isfield(T.Eye, 'n') && ~isempty(T.Eye.n) && isfinite(T.Eye.n(1)) && T.Eye.n(1) > 0
        nSamples = min(nSamples, double(T.Eye.n(1)));
    end
    if nSamples < 2 || rowIdx > size(T.Eye.v, 1)
        title(sprintf('Trial %d: insufficient ADC samples', trialNo));
        rows{iTrial} = row;
        continue
    end

    sig = double(T.Eye.v(rowIdx, 1:nSamples));
    tt = double(T.Eye.t(1:nSamples));
    good = isfinite(sig) & isfinite(tt);
    sig = sig(good);
    tt = tt(good);
    if numel(sig) < 2
        title(sprintf('Trial %d: no finite sync samples', trialNo));
        rows{iTrial} = row;
        continue
    end

    [xSec, xLabel, stimLineSec] = localPlotTimeAxis(T, tt);
    expectedPulseSec = localExpectedPulsePlotSec(T, stimLineSec);
    [risingIdx, fallingIdx, logicSig] = localDetectEdges(sig, tt, thresholdV, polarity, minEdgeSepSec);
    plausibleRisingIdx = localPlausibleEdges(risingIdx, xSec, expectedPulseSec, pulseWindowSec);

    plot(xSec, sig, 'k-', 'LineWidth', 1);
    yline(thresholdV, '--r', sprintf('%.3g V', thresholdV));

    if ~isempty(risingIdx)
        plot(xSec(risingIdx), sig(risingIdx), 'go', 'MarkerFaceColor', 'g');
        xline(xSec(risingIdx(1)), ':g', 'first raw edge');
    end
    if ~isempty(plausibleRisingIdx)
        plot(xSec(plausibleRisingIdx(1)), sig(plausibleRisingIdx(1)), ...
            's', 'MarkerFaceColor', [1 0.6 0], 'MarkerEdgeColor', [0.8 0.3 0]);
        xline(xSec(plausibleRisingIdx(1)), '-', 'analysis edge', 'Color', [1 0.45 0]);
    end
    if ~isempty(fallingIdx)
        plot(xSec(fallingIdx), sig(fallingIdx), 'mo');
    end
    if isfinite(expectedPulseSec)
        xline(expectedPulseSec, ':c', sprintf('expected +/- %.2gs', pulseWindowSec));
    end
    if isfinite(stimLineSec)
        xline(stimLineSec, '--b', 'stimOn');
    end

    row.nSamples = numel(sig);
    row.durationSec = tt(end) - tt(1);
    row.minV = min(sig);
    row.maxV = max(sig);
    row.fracAboveThreshold = mean(sig >= thresholdV);
    row.nRising = numel(risingIdx);
    row.nFalling = numel(fallingIdx);
    row.nPlausibleRising = numel(plausibleRisingIdx);
    if ~isempty(risingIdx)
        row.firstEdgeDatapixxSec = tt(risingIdx(1));
        row.firstEdgePlotSec = xSec(risingIdx(1));
        row.firstEdgeBufferSec = tt(risingIdx(1)) - tt(1);
        trialStartDp = localFirstFiniteScalarField(T, 'TrialStartDatapixx');
        if isfinite(trialStartDp)
            row.firstEdgeTrialStartDpSec = tt(risingIdx(1)) - trialStartDp;
        end
        fallAfter = fallingIdx(fallingIdx > risingIdx(1));
        if ~isempty(fallAfter)
            row.firstPulseWidthSec = tt(fallAfter(1)) - tt(risingIdx(1));
        end
    end
    if ~isempty(plausibleRisingIdx)
        row.analysisEdgeDatapixxSec = tt(plausibleRisingIdx(1));
        row.analysisEdgePlotSec = xSec(plausibleRisingIdx(1));
        row.analysisEdgeBufferSec = tt(plausibleRisingIdx(1)) - tt(1);
    end
    row.stimOnTrialRelSec = localStimRelSec(T);
    row.expectedPulsePlotSec = expectedPulseSec;
    row.pulseWindowSec = pulseWindowSec;
    if isfinite(row.firstEdgeTrialStartDpSec) && isfinite(row.stimOnTrialRelSec)
        row.firstEdgeMinusStimOnSec = row.firstEdgeTrialStartDpSec - row.stimOnTrialRelSec;
    end
    if isfinite(row.analysisEdgePlotSec) && isfinite(row.stimOnTrialRelSec)
        row.analysisEdgeMinusStimOnSec = row.analysisEdgePlotSec - row.stimOnTrialRelSec;
    end
    row.isHighAtStart = logical(logicSig(1));
    row.isHighAtEnd = logical(logicSig(end));
    rows{iTrial} = row;

    title(sprintf('Trial %d ch%d row%d: %d rising, analysis %.4g s, first %.4g s', ...
        trialNo, physicalChannel, rowIdx, row.nRising, row.analysisEdgePlotSec, row.firstEdgePlotSec));
    ylabel('Photodiode (V)');
    if iTrial == numel(trialNum)
        xlabel(xLabel);
    end
    grid on;
end

out = struct2table(vertcat(rows{:}));
disp(out);
end


function row = localEmptyRow(trialNo, physicalChannel, rowIdx, thresholdV)
row = struct( ...
    'trial', trialNo, ...
    'physicalChannel', physicalChannel, ...
    'rowIdx', rowIdx, ...
    'thresholdV', thresholdV, ...
    'nSamples', 0, ...
    'durationSec', NaN, ...
    'minV', NaN, ...
    'maxV', NaN, ...
    'fracAboveThreshold', NaN, ...
    'nRising', 0, ...
    'nFalling', 0, ...
    'nPlausibleRising', 0, ...
    'firstEdgeDatapixxSec', NaN, ...
    'firstEdgePlotSec', NaN, ...
    'firstEdgeBufferSec', NaN, ...
    'firstEdgeTrialStartDpSec', NaN, ...
    'firstPulseWidthSec', NaN, ...
    'analysisEdgeDatapixxSec', NaN, ...
    'analysisEdgePlotSec', NaN, ...
    'analysisEdgeBufferSec', NaN, ...
    'stimOnTrialRelSec', NaN, ...
    'expectedPulsePlotSec', NaN, ...
    'pulseWindowSec', NaN, ...
    'firstEdgeMinusStimOnSec', NaN, ...
    'analysisEdgeMinusStimOnSec', NaN, ...
    'isHighAtStart', false, ...
    'isHighAtEnd', false);
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


function [xSec, xLabel, stimLineSec] = localPlotTimeAxis(T, tt)
stimLineSec = NaN;
trialStartDp = localFirstFiniteScalarField(T, 'TrialStartDatapixx');
if isfinite(trialStartDp)
    xSec = tt - trialStartDp;
    xLabel = 'Time from TrialStartDatapixx (s)';
    stimLineSec = localStimRelSec(T);
else
    xSec = tt - tt(1);
    xLabel = 'Time from ADC buffer start (s)';
    stimLineSec = localStimRelSec(T);
end
end


function stimRelSec = localStimRelSec(T)
stimRelSec = NaN;
if isfield(T, 'times') && isstruct(T.times) && isfield(T.times, 'stimOn') && ...
        isfield(T, 'TrialStart')
    stimOn = localFirstFiniteScalar(T.times.stimOn);
    trialStart = localFirstFiniteScalar(T.TrialStart);
    if isfinite(stimOn) && isfinite(trialStart)
        stimRelSec = stimOn - trialStart;
    end
end
end


function expectedPulseSec = localExpectedPulsePlotSec(T, fallbackSec)
expectedPulseSec = NaN;
frameRel = localFrameSyncPulseRelSec(T);
if isfinite(frameRel)
    expectedPulseSec = frameRel;
elseif isfinite(fallbackSec)
    expectedPulseSec = fallbackSec;
end
end


function frameRel = localFrameSyncPulseRelSec(T)
frameRel = NaN;
if ~(isstruct(T) && isfield(T, 'frameSyncPulse') && isfield(T, 'flip_info') && ...
        ~isempty(T.frameSyncPulse) && ~isempty(T.flip_info))
    return
end
syncMask = logical(T.frameSyncPulse(:));
flipInfo = double(T.flip_info);
n = min(numel(syncMask), size(flipInfo, 1));
if n <= 0 || size(flipInfo, 2) < 1
    return
end
idx = find(syncMask(1:n), 1, 'first');
trialStart = localFirstFiniteScalarField(T, 'TrialStart');
if ~isempty(idx) && isfinite(trialStart)
    frameRel = flipInfo(idx, 1) - trialStart;
end
end


function plausibleIdx = localPlausibleEdges(edgeIdx, xSec, expectedSec, windowSec)
plausibleIdx = [];
if isempty(edgeIdx) || ~isfinite(expectedSec) || ~isfinite(windowSec) || windowSec <= 0
    return
end
edgeTimes = xSec(edgeIdx);
keep = isfinite(edgeTimes) & abs(edgeTimes - expectedSec) <= windowSec;
plausibleIdx = edgeIdx(keep);
if isempty(plausibleIdx)
    return
end
[~, order] = sort(abs(xSec(plausibleIdx) - expectedSec), 'ascend');
plausibleIdx = plausibleIdx(order);
end


function value = localFirstFiniteScalarField(s, fieldName)
value = NaN;
if isstruct(s) && isfield(s, fieldName)
    value = localFirstFiniteScalar(s.(fieldName));
end
end


function value = localFirstFiniteScalar(x)
value = NaN;
if ~(isnumeric(x) || islogical(x)) || isempty(x)
    return
end
vals = double(x(:));
idx = find(isfinite(vals), 1, 'first');
if ~isempty(idx)
    value = vals(idx);
end
end


function [risingIdx, fallingIdx, logicSig] = localDetectEdges(sig, tt, thresholdV, polarity, minEdgeSepSec)
switch lower(char(string(polarity)))
    case 'falling'
        logicSig = sig <= thresholdV;
    otherwise
        logicSig = sig >= thresholdV;
end
risingIdx = find(diff(logicSig) == 1) + 1;
fallingIdx = find(diff(logicSig) == -1) + 1;

if minEdgeSepSec > 0 && ~isempty(risingIdx)
    keep = true(size(risingIdx));
    lastT = tt(risingIdx(1));
    for iEdge = 2:numel(risingIdx)
        if (tt(risingIdx(iEdge)) - lastT) < minEdgeSepSec
            keep(iEdge) = false;
        else
            lastT = tt(risingIdx(iEdge));
        end
    end
    risingIdx = risingIdx(keep);
end
end


function value = localOptScalar(ex, opts, names, defaultValue)
value = defaultValue;
for iName = 1:numel(names)
    name = names{iName};
    if isstruct(opts) && isfield(opts, name) && isnumeric(opts.(name)) && ~isempty(opts.(name)) && ...
            isfinite(opts.(name)(1))
        value = double(opts.(name)(1));
        return
    end
end
if isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && ...
        isfield(ex.exp.CoPs, 'analysis') && isstruct(ex.exp.CoPs.analysis)
    analysis = ex.exp.CoPs.analysis;
    for iName = 1:numel(names)
        name = names{iName};
        if isfield(analysis, name) && isnumeric(analysis.(name)) && ~isempty(analysis.(name)) && ...
                isfinite(analysis.(name)(1))
            value = double(analysis.(name)(1));
            return
        end
    end
end
end


function value = localOptText(opts, names, defaultValue)
value = defaultValue;
for iName = 1:numel(names)
    name = names{iName};
    if isstruct(opts) && isfield(opts, name) && ~isempty(opts.(name))
        value = char(string(opts.(name)));
        return
    end
end
end
