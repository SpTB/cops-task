function sync = extractVideoSyncFromTrial(trial, scheduledChannels, varargin)
%EXTRACTVIDEOSYNCFROMTRIAL Detect sync-pulse edges from a trial ADC channel.
%
% sync = extractVideoSyncFromTrial(trial, scheduledChannels, ...)
%
% Inputs
%   trial               struct with fields:
%                       - Eye.v : [nChannels x nSamples] ADC voltages
%                       - Eye.t : [1 x nSamples] Datapixx timestamps
%                       - TrialStartDatapixx (optional)
%   scheduledChannels   0-based physical ADC channel indices, in the same
%                       order used in SetAdcSchedule / ReadAdcBuffer.
%
% Name-value options
%   'PhysicalChannel'   Physical Datapixx channel to analyze (default: 6)
%   'Threshold'         Voltage threshold. If empty, auto-estimated.
%   'Polarity'          'rising' (default) or 'falling'
%   'MinPulseWidthSec'  Minimum time between consecutive edges (default: 0)
%
% Output struct
%   sync.physicalChannel
%   sync.rowIndex
%   sync.threshold
%   sync.edgeSampleIdx
%   sync.edgeTimeDatapixx
%   sync.edgeTimeFromTrialStart

p = inputParser;
p.addParameter('PhysicalChannel', 7, @(x) isnumeric(x) && isscalar(x));
p.addParameter('Threshold', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
p.addParameter('Polarity', 'rising', @(s) ischar(s) || isstring(s));
p.addParameter('MinPulseWidthSec', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.parse(varargin{:});
opt = p.Results;

if ~isfield(trial, 'Eye') || ~isfield(trial.Eye, 'v') || ~isfield(trial.Eye, 't')
    error('trial must contain Eye.v and Eye.t.');
end

v = trial.Eye.v;
t = trial.Eye.t(:)';


rowIdx = find(scheduledChannels == opt.PhysicalChannel, 1, 'first');
if isempty(rowIdx)
    error('PhysicalChannel %d not found in scheduledChannels.', opt.PhysicalChannel);
end

sig = v(rowIdx, :); % select camera channel
valid = ~isnan(sig) & ~isnan(t);
sig = sig(valid);
t = t(valid);


if isempty(opt.Threshold)
    lo = prctile(sig, 10);
    hi = prctile(sig, 90);
    thr = (lo + hi) / 2;
else
    thr = opt.Threshold;
end

pol = lower(string(opt.Polarity));
switch pol
    case "rising"
        logicSig = sig >= thr;
        edgeIdx = find(diff(logicSig) == 1) + 1;
    case "falling"
        logicSig = sig <= thr;
        edgeIdx = find(diff(logicSig) == 1) + 1;
    otherwise
        error('Polarity must be ''rising'' or ''falling''.');
end

if ~isempty(edgeIdx) && opt.MinPulseWidthSec > 0
    keep = true(size(edgeIdx));
    lastT = t(edgeIdx(1));
    for k = 2:numel(edgeIdx)
        if (t(edgeIdx(k)) - lastT) < opt.MinPulseWidthSec
            keep(k) = false;
        else
            lastT = t(edgeIdx(k));
        end
    end
    edgeIdx = edgeIdx(keep);
end

sync = initEmpty(opt.PhysicalChannel, rowIdx, thr);
sync.edgeSampleIdx = edgeIdx;
sync.edgeTimeDatapixx = t(edgeIdx);
if isfield(trial, 'TrialStartDatapixx') && ~isempty(trial.TrialStartDatapixx) && ~isnan(trial.TrialStartDatapixx)
    sync.edgeTimeFromTrialStart = sync.edgeTimeDatapixx - trial.TrialStartDatapixx;
else
    sync.edgeTimeFromTrialStart = [];
end

end

function s = initEmpty(physicalChannel, rowIdx, threshold)
s = struct();
s.physicalChannel = physicalChannel;
s.rowIndex = rowIdx;
s.threshold = threshold;
s.edgeSampleIdx = [];
s.edgeTimeDatapixx = [];
s.edgeTimeFromTrialStart = [];
end
