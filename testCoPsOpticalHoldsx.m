function tests = testCoPsOpticalHoldsx
% Offline checks with known physical refresh histories; no hardware required.
tests = functiontests(localfunctions);
end

function testNoHoldsAt500Hz(testCase)
[bits,s,v,ifi,anchors,truth]=fixture(500,zeros(530,1),.0021);
out=estimateCoPsOpticalHoldsx(bits,s,v,ifi,anchors);
verifyTrue(testCase,out.alignmentReliable);
verifyEqual(testCase,out.holdCount,truth);
verifyEqual(testCase,out.opticalRefreshHz,1/ifi,'AbsTol',.003);
end

function testKnownHoldsAndUnrelatedPreparationFlashes(testCase)
holds=zeros(530,1); holds([80 150 340])=[1 3 2];
[bits,s,v,ifi,anchors,truth]=fixture(500,holds,.0021);
out=estimateCoPsOpticalHoldsx(bits,s,v,ifi,anchors);
verifyTrue(testCase,out.alignmentReliable);
verifyEqual(testCase,out.holdCount,truth);
verifyEqual(testCase,truth,6);
verifyLessThanOrEqual(testCase,out.posteriorRange95(1),truth);
verifyGreaterThanOrEqual(testCase,out.posteriorRange95(2),truth);
end

function testHighRateAndDownsampledTraceAgree(testCase)
holds=zeros(530,1); holds([80 150 340])=[1 3 2];
[bits,s,v,ifi,anchors,truth]=fixture(10000,holds,.0015);
full=estimateCoPsOpticalHoldsx(bits,s,v,ifi,anchors);
verifyEqual(testCase,full.holdCount,truth);
for phase=[1 6 11 16]
    ix=phase:20:numel(s);
    low=estimateCoPsOpticalHoldsx(bits,s(ix),v(ix),ifi,anchors);
    verifyEqual(testCase,low.holdCount,truth);
end
end

function testIncorrectCodeIsRejected(testCase)
[bits,s,v,ifi,anchors]=fixture(10000,zeros(530,1),.0021);
wrong=bits; wrong(19:end)=circshift(wrong(19:end),97);
rises=find(wrong==1 & [true;wrong(1:end-1)==0]);
rises=rises(rises>40 & rises<numel(bits)-20);
out=estimateCoPsOpticalHoldsx(wrong,s,v,ifi,rises([1 end])');
verifyFalse(testCase,out.alignmentReliable);
end

function testNoContrastFailsAndRandomStateIsPreserved(testCase)
[bits,s,v,ifi,anchors]=fixture(500,zeros(530,1),.0021);
before=rng;
estimateCoPsOpticalHoldsx(bits,s,v,ifi,anchors);
verifyEqual(testCase,rng,before);
verifyError(testCase,@() estimateCoPsOpticalHoldsx(bits,s,zeros(size(v)),ifi,anchors), ...
    'CoPsOpticalHolds:Contrast');
end

function [bits,s,v,ifi,anchors,truth]=fixture(sampleHz,holds,pulseWidth)
ifi=1/120;
sync=prepareCoPsSyncx(struct('mode','binary'),ifi);
bits=[ones(12,1);zeros(6,1);double(sync.sequence(2001:2512)')];
rises=find(bits==1 & [true;bits(1:end-1)==0]);
rises=rises(rises>40 & rises<numel(bits)-20); anchors=rises([1 end])';
truth=sum(holds(anchors(1):anchors(2)-1));
% The early white run is unrelated to GO and must not select the code origin.
physical=[ones(3,1);zeros(12,1);repelem(bits,1+holds);zeros(16,1)];
s=(0:1/sampleHz:numel(physical)*ifi-1/sampleHz)';
slot=floor(s/ifi)+1; phase=mod(s,ifi);
light=physical(slot).*(phase>=.001 & phase<.001+pulseWidth);
v=.01+.3*light+.002*sin((1:numel(s))'*1.791);
s=s+1000;
end
