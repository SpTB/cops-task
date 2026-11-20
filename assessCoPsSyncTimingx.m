function out = assessCoPsSyncTimingx(trial)
% Check actual binary playback cadence and acquisition after the final flip.
% This assesses frame timing/recording coverage, not photodiode bit agreement.
ifi = trial.sync.refreshIntervalSec;
t = double(trial.flip_info(:,1));
phase = trial.frameSyncPhase(:);
valid = isfinite(t);
active = valid(1:end-1) & valid(2:end) & phase(1:end-1)>0 & phase(2:end)>0;
dt = diff(t);
intervals = dt(active);
late = find(active & dt>1.5*ifi)+1;
missed = sum(max(0,round(intervals/ifi)-1));
frameTimingPassed = ~isempty(intervals) && all(intervals>0) && missed==0;
requiredTail = 0.1;
if isfield(trial.sync,'captureTailSecs'), requiredTail = trial.sync.captureTailSecs; end
payloadFrames = nnz(valid & phase==3);
out = struct('refreshIntervalSec',ifi,'nActiveIntervals',nnz(active), ...
    'nPayloadFrames',payloadFrames, ...
    'missedRefreshes',missed,'longIntervalFrameIndices',late, ...
    'maxActiveIntervalSec',max([NaN;intervals],[],'omitnan'), ...
    'frameTimingPassed',frameTimingPassed, ...
    'requiredTailSecs',requiredTail,'capturedTailSecs',NaN, ...
    'tailComplete',false,'passed',false);
if ~isfield(trial,'Analog') || isempty(trial.Analog) || ...
        ~isfield(trial,'syncClock') || ~isfield(trial,'syncOffTime')
    return
end
a = trial.Analog;
n = min(numel(a.t),a.n);
if n<2, return; end
clock = trial.syncClock;
if ~isfinite(clock.ptbSec) || ~isfinite(clock.datapixxSec), return; end
sampleEnd = double(a.t(n))-clock.datapixxSec+clock.ptbSec;
sampleInterval = (double(a.t(n))-double(a.t(1)))/(n-1);
uncertainty = clock.uncertaintySec;
if ~isfinite(uncertainty), return; end
out.capturedTailSecs = sampleEnd-trial.syncOffTime;
out.tailComplete = sampleInterval>0 && isfinite(out.capturedTailSecs) && ...
    out.capturedTailSecs >= requiredTail - sampleInterval - uncertainty;
completed = isfield(trial,'trialCompleted') && isequal(trial.trialCompleted,true);
out.passed = completed && payloadFrames>=10 && out.frameTimingPassed && out.tailComplete;
end
