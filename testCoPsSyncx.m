function tests = testCoPsSyncx
% No display, acquisition hardware, or optional MATLAB toolboxes required.
tests = functiontests(localfunctions);
end

function testGoPulseDefaultAndBitRates(testCase)
evalc('ex = setDefaultsCoPs(struct());');
verifyEqual(testCase, ex.exp.CoPs.sync.mode, 'goPulse');
for rate = [60 120 144]
    for holdFrames = [1 2 4]
        sync = prepareCoPsSyncx(struct('mode','binary','framesPerBit',holdFrames), 1/rate);
        verifyEqual(testCase, sync.bitRateHz, rate/holdFrames, 'AbsTol', 1e-10);
    end
end
end

function testReusedSequenceIsDeterministicAndDoesNotConsumeRng(testCase)
old = rng;
a = prepareCoPsSyncx(struct('mode','binary'), 1/60);
b = prepareCoPsSyncx(struct('mode','binary'), 1/120);
verifyEqual(testCase, a.sequence, b.sequence);
verifyEqual(testCase, numel(a.sequence), 32767);
verifyEqual(testCase, rng, old);
end

function testGeneratedCodeHasFullPeriod(testCase)
sync = prepareCoPsSyncx(struct('mode','binary'), 1/60);
bits = [sync.sequence sync.sequence(1:14)];
words = zeros(32767,1,'uint16');
for j = 1:15
    words = bitor(bitshift(words,1), uint16(bits(j:j+32766)'));
end
verifyEqual(testCase, numel(unique(words)), 32767);
verifyFalse(testCase, any(words == 0));
end

function testSuppliedSequenceAndValidation(testCase)
sync = prepareCoPsSyncx(struct('mode','binary','sequence',[0 1 1 0]), 1/60);
verifyEqual(testCase, sync.sequence, logical([0 1 1 0]));
for bits = {[0 2 1], [0 0 0], [1 1 1]}
    verifyError(testCase, @() prepareCoPsSyncx(struct('mode','binary','sequence',bits{1}),1/60), ...
        'prepareCoPsSyncx:InvalidSequence');
end
end

function testMarkerGapPayloadAndTrialReset(testCase)
sync = prepareCoPsSyncx(struct('mode','binary','framesPerBit',2,'sequence',[0 1 0 1]),1/60);
for trial = 1:2
    cursor = 0;
    [cursor,bit,index,phase] = advanceCoPsSyncx(sync,cursor,false);
    verifyEqual(testCase, [cursor bit double(phase)], [0 0 0]);
    verifyTrue(testCase, isnan(index));
    bits = []; indices = []; phases = [];
    for k = 1:17
        [cursor,bit,index,phase] = advanceCoPsSyncx(sync,cursor,true);
        bits(end+1) = bit; indices(end+1) = index; phases(end+1) = phase; %#ok<AGROW>
    end
    verifyEqual(testCase,bits,[ones(1,6) zeros(1,3) 0 0 1 1 0 0 1 1]);
    verifyEqual(testCase,phases,[ones(1,6) 2*ones(1,3) 3*ones(1,8)]);
    verifyEqual(testCase,indices(10:end),[1 1 2 2 3 3 4 4]);
    verifyError(testCase,@() advanceCoPsSyncx(sync,cursor,true),'advanceCoPsSyncx:SequenceExhausted');
end
end

function testNoisyTraceWithDelayAndClockDrift(testCase)
trial = trialFixture();
[s,v] = simulateTrace(trial,0.018,700);
out = decodeCoPsSyncx(trial,s,v,sameClock=true);
verifyTrue(testCase,out.alignmentReliable);
verifyGreaterThan(testCase,out.matchFraction,0.97);
verifyEqual(testCase,out.lagSec,0.018,'AbsTol',0.003);
verifyEqual(testCase,out.clockDriftPpm,700,'AbsTol',200);
verifyEqual(testCase,out.estimatedMissedRefreshes,0);
end

function testLateFlipStretchesOldBitWithoutSkippingSequence(testCase)
trial = trialFixture();
trial.flip_info(250:end,1) = trial.flip_info(250:end,1) + trial.sync.refreshIntervalSec;
trial.syncOffTime = trial.syncOffTime + trial.sync.refreshIntervalSec;
[s,v] = simulateTrace(trial,0.012,0);
out = decodeCoPsSyncx(trial,s,v,sameClock=true,maxDriftPpm=0);
verifyTrue(testCase,out.alignmentReliable);
verifyGreaterThan(testCase,out.matchFraction,0.98);
verifyEqual(testCase,out.estimatedMissedRefreshes,1);
verifyEqual(testCase,out.longFlipIntervalFrameIndices,250);
verifyEqual(testCase,trial.frameSyncIndex(250)-trial.frameSyncIndex(249),1);
end

function testPhysicalMismatchIsReported(testCase)
trial = trialFixture();
physicalBits = trial.frameSyncBit;
physicalBits(250:252) = 1-physicalBits(250:252);
[s,v] = simulateTrace(trial,0.016,0,physicalBits);
out = decodeCoPsSyncx(trial,s,v,sameClock=true,maxDriftPpm=0);
verifyTrue(testCase,any(ismember(out.mismatchedFrameIndices,250:252)));
verifyLessThan(testCase,out.matchFraction,1);
end

function testRecordedChannelAndClockReference(testCase)
trial = trialFixture();
[s,v] = simulateTrace(trial,0.018,0);
trial.syncClock = struct('ptbSec',100,'datapixxSec',5000,'uncertaintySec',0.0001);
trial.adcChannels = [7 6];
trial.Analog = struct('v',[zeros(size(v')); v'], 't',s'+4900,'n',numel(s));
out = decodeCoPsSyncx(trial,maxDriftPpm=0);
verifyTrue(testCase,out.alignmentReliable);
verifyEqual(testCase,out.lagSec,0.018,'AbsTol',0.003);
verifyEqual(testCase,out.clockReferenceUncertaintySec,0.0001);
end

function testMainEyeRecordingAndTrialStartClockReference(testCase)
for channels = {[0:5 6 7], [0:2 6]}
    trial = trialFixture();
    [s,v] = simulateTrace(trial,0.018,0);
    trial.adcChannels = channels{1};
    trial.inputSource = 'eye';
    trial.TrialStart = 100;
    trial.TrialStartDatapixx = 5000;
    raw = zeros(numel(trial.adcChannels),numel(s));
    raw(trial.adcChannels==trial.sync.physicalChannel,:) = v';
    trial.Eye = struct('v',raw,'t',s'+4900,'n',numel(s));
    out = decodeCoPsSyncx(trial,maxDriftPpm=0);
    verifyTrue(testCase,out.alignmentReliable);
    verifyEqual(testCase,out.lagSec,0.018,'AbsTol',0.003);
    verifyTrue(testCase,isnan(out.clockReferenceUncertaintySec));
end
end

function testInvertedSignal(testCase)
trial = trialFixture();
[s,v] = simulateTrace(trial,0.02,0);
out = decodeCoPsSyncx(trial,s,1-v,sameClock=true,invert=true,maxDriftPpm=0);
verifyTrue(testCase,out.alignmentReliable);
verifyGreaterThan(testCase,out.matchFraction,0.98);
end

function testMissingRecordingAndClockFailClearly(testCase)
trial = trialFixture();
verifyError(testCase,@() decodeCoPsSyncx(trial),'decodeCoPsSyncx:NoAnalog');
[s,v] = simulateTrace(trial,0,0);
verifyError(testCase,@() decodeCoPsSyncx(trial,s,v),'decodeCoPsSyncx:NoClockReference');
verifyError(testCase,@() decodeCoPsSyncx(trial,s,zeros(size(v)),sameClock=true), ...
    'decodeCoPsSyncx:NoContrast');
end

function testAmbiguousAlternatingCodeIsNotCalledReliable(testCase)
trial = trialFixture(repmat([0 1],1,256));
[s,v] = simulateTrace(trial,0.02,0);
out = decodeCoPsSyncx(trial,s,v,sameClock=true,maxDriftPpm=0);
verifyFalse(testCase,out.alignmentReliable);
verifyLessThan(testCase,out.alignmentPeakMargin,0.01);
end

function testHigherRefreshAndHeldBits(testCase)
for settings = [120 1 500; 144 1 2000; 60 2 500]'
    trial = trialFixture([],settings(1),settings(2));
    [s,v] = simulateTrace(trial,0.018,300,trial.frameSyncBit,settings(3));
    out = decodeCoPsSyncx(trial,s,v,sameClock=true);
    verifyTrue(testCase,out.alignmentReliable);
    verifyGreaterThan(testCase,out.matchFraction,0.94);
    verifyEmpty(testCase,out.mismatchedFrameIndices);
end
end

function trial = trialFixture(bits,refreshRate,framesPerBit)
if nargin < 2, refreshRate = 60; end
if nargin < 3, framesPerBit = 1; end
sync = prepareCoPsSyncx(struct('mode','binary','framesPerBit',framesPerBit),1/refreshRate);
if nargin == 0, bits = sync.sequence(2001:2512); end
if isempty(bits), bits = sync.sequence(2001:2512); end
sync.sequence = logical(bits);
sync = prepareCoPsSyncx(sync,1/refreshRate);
n = sync.preambleFrames+sync.gapFrames+numel(bits)*sync.framesPerBit+10;
trial = struct('sync',sync,'flip_info',NaN(n,4),'frameSyncBit',NaN(n,1), ...
    'frameSyncIndex',NaN(n,1),'frameSyncPhase',zeros(n,1,'uint8'));
cursor = 0;
for k = 1:n
    [cursor,trial.frameSyncBit(k),trial.frameSyncIndex(k),trial.frameSyncPhase(k)] = ...
        advanceCoPsSyncx(sync,cursor,k>10);
end
trial.flip_info(:,1) = 100+(0:n-1)'*sync.refreshIntervalSec;
trial.syncOffTime = trial.flip_info(end,1)+sync.refreshIntervalSec;
end

function [s,v] = simulateTrace(trial,lag,drift,physicalBits,sampleRate)
if nargin < 4, physicalBits = trial.frameSyncBit; end
if nargin < 5, sampleRate = 500; end
t = [trial.flip_info(:,1);trial.syncOffTime];
b = [physicalBits;0];
ref = t(1);
s = (ref-0.05:1/sampleRate:trial.syncOffTime+0.1)';
query = ref+(s-ref-lag)/(1+drift*1e-6);
v = interp1(t,b,query,'previous',0);
v = 0.1+0.9*v+0.02*sin((1:numel(v))'*1.791);
end
