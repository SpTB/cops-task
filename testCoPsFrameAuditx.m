function tests=testCoPsFrameAuditx
% Known-count tests, including optical/timestamp disagreements and F4 saves.
tests=functiontests(localfunctions);
end

function testAgreementAndIntervalConvention(testCase)
[ex,index]=fixture(2,2);
before=rng;
out=auditCoPsFrameTimingx(ex,verbose=false);
a=out.Trials.frameAudit;
verifyEqual(testCase,rng,before);
verifyEqual(testCase,a.status,'complete');
verifyTrue(testCase,a.missed(index));
verifyEqual(testCase,a.classification(index),"missed");
verifyEqual(testCase,a.vblMissCount(index),2);
verifyEqual(testCase,a.photMedianCount(index),2);
verifyFalse(testCase,a.missVBL(index) || a.missPhot(index));
verifyTrue(testCase,isnan(a.vblMissCount(end)));
verifyEqual(testCase,out.frameAudit.summary.vblExtraRefreshes,2);
verifyEqual(testCase,ex.Trials.flip_info,out.Trials.flip_info);
verifyEqual(testCase,ex.Trials.Eye,out.Trials.Eye);
end

function testVBLOnlyAndPhotodiodeOnlyAreIndependent(testCase)
[ex,index]=fixture(2,0);
vblOnly=auditCoPsFrameTimingx(ex,verbose=false);
verifyTrue(testCase,vblOnly.Trials.frameAudit.missVBL(index));
verifyFalse(testCase,any(vblOnly.Trials.frameAudit.missPhot));
[ex,index]=fixture(0,2);
photOnly=auditCoPsFrameTimingx(ex,verbose=false);
verifyTrue(testCase,photOnly.Trials.frameAudit.missPhot(index));
verifyTrue(testCase,photOnly.Trials.frameAudit.flagged(index));
verifyFalse(testCase,any(photOnly.Trials.frameAudit.missVBL));
% Change only flip timestamps; all optical fits and estimates must stay put.
changed=ex; changed.Trials.flip_info(:,1)=changed.Trials.flip_info(:,1)+37;
shifted=auditCoPsFrameTimingx(changed,verbose=false);
verifyEqual(testCase,shifted.Trials.frameAudit.photMedianCount,photOnly.Trials.frameAudit.photMedianCount);
verifyEqual(testCase,shifted.Trials.frameAudit.photLowerCount,photOnly.Trials.frameAudit.photLowerCount);
verifyEqual(testCase,shifted.Trials.frameAudit.modelDiagnostics,photOnly.Trials.frameAudit.modelDiagnostics);
end

function testRepeatedBitsRemainUncertainButWindowCanAgree(testCase)
[ex,index]=fixture(1,1,true);
out=auditCoPsFrameTimingx(ex,verbose=false);
a=out.Trials.frameAudit;
verifyTrue(testCase,a.photUncertain(index));
verifyFalse(testCase,a.missed(index));
verifyFalse(testCase,a.missVBL(index));
verifyTrue(testCase,a.flagged(index));
verifyEqual(testCase,a.classification(index),"flagged");
w=double(a.windowIndex(index)); verifyGreaterThan(testCase,w,0);
verifyEqual(testCase,a.windows.vblMissCount(w),1);
verifyTrue(testCase,a.windows.exactCountAgreement(w));
verifyTrue(testCase,a.windowSupportedMissed(index));
end

function testAbsentDiodeDoesNotBecomeVBLOnlyDisagreement(testCase)
[ex,index]=fixture(2,0);
ex.Trials.Eye.v(:)=0;
out=auditCoPsFrameTimingx(ex,verbose=false);
a=out.Trials.frameAudit;
verifyEqual(testCase,a.status,'opticalUnavailable');
verifyTrue(testCase,a.flagged(index));
verifyFalse(testCase,any(a.missVBL));
verifyFalse(testCase,any(a.photCompared));
verifyEqual(testCase,out.frameAudit.summary.vblExtraRefreshes,2);
verifyEqual(testCase,out.frameAudit.summary.opticalTrials,0);
end

function testVeryEarlyF4AndEmptySessionAreSaved(testCase)
[ex,~]=fixture(0,0);
tr=ex.Trials; tr.flip_info=tr.flip_info(1:25,:);
tr.frameSyncBit=tr.frameSyncBit(1:25); tr.frameSyncPhase=tr.frameSyncPhase(1:25);
ex.Trials=tr; ex.Header.sessionEndReason='F4'; ex.Header.sessionEndQuitCode=4;
file=[tempname '.mat']; cleanup=onCleanup(@() deleteIfPresent(file));
out=saveCoPsSessionx(ex,file); saved=load(file,'ex');
verifyEqual(testCase,saved.ex,out);
verifyEqual(testCase,saved.ex.Header.sessionEndReason,'F4');
verifyEqual(testCase,saved.ex.Trials.frameAudit.reason,'CoPsFrameAudit:ShortCode');
verifyEqual(testCase,saved.ex.Trials.flip_info,tr.flip_info);
ex.Trials=struct([]);
out=saveCoPsSessionx(ex,file); saved=load(file,'ex');
verifyEqual(testCase,saved.ex,out);
verifyEqual(testCase,out.frameAudit.summary.trials,0);
end

function testNormalAndF4FinalSaveContainAudit(testCase)
[ex,~]=fixture(2,2);
file=[tempname '.mat']; cleanup=onCleanup(@() deleteIfPresent(file));
for reason={'completed','F4'}
    ex.Header.sessionEndReason=reason{1};
    out=saveCoPsSessionx(ex,file); saved=load(file,'ex');
    verifyEqual(testCase,saved.ex,out);
    verifyEqual(testCase,saved.ex.frameAudit.status,'complete');
    verifyEqual(testCase,saved.ex.Trials.frameAudit.status,'complete');
    verifyEqual(testCase,saved.ex.Header.sessionEndReason,reason{1});
    verifyTrue(testCase,any(saved.ex.Trials.frameAudit.missed));
end
end

function testTrialWithoutBinaryStillKeepsTimestampCount(testCase)
[ex,index]=fixture(3,0);
ex.Trials.sync.mode='off';
out=auditCoPsFrameTimingx(ex,verbose=false);
verifyEqual(testCase,out.Trials.frameAudit.reason,'CoPsFrameAudit:NotBinary');
verifyEqual(testCase,out.frameAudit.summary.vblExtraRefreshes,3);
verifyTrue(testCase,out.Trials.frameAudit.flagged(index));
verifyFalse(testCase,out.Trials.frameAudit.missVBL(index));
end

function [ex,index]=fixture(vblExtra,photExtra,repeated)
if nargin<3, repeated=false; end
ifi=1/120; sync=prepareCoPsSyncx(struct('mode','binary'),ifi);
bits=[ones(12,1);zeros(6,1);double(sync.sequence(2001:2512)')]; n=numel(bits);
if repeated
    candidates=find(bits(1:end-2)==bits(2:end-1) & bits(2:end-1)==bits(3:end))+1;
else
    candidates=find(bits(2:end-1)==1 & bits(1:end-2)==0 & bits(3:end)==0)+1;
end
index=candidates(find(candidates>180 & candidates<350,1));
vh=zeros(n,1); vh(index)=vblExtra;
ph=zeros(n,1); ph(index)=photExtra;
physical=[zeros(15,1);repelem(bits,1+ph);zeros(16,1)];
u=(0:1/10000:numel(physical)*ifi-1/10000)';
slot=floor(u/ifi)+1; phase=mod(u,ifi);
v=.01+.3*physical(slot).*(phase>=.001 & phase<.0031)+.002*sin((1:numel(u))'*1.791);
tr=struct('sync',sync,'displayRefreshIntervalSec',ifi,'adcChannels',6, ...
    'flip_info',[500+cumsum([0;1+vh(1:end-1)])*ifi zeros(n,3)], ...
    'frameSyncBit',bits,'frameSyncPhase',[ones(12,1);2*ones(6,1);3*ones(n-18,1)], ...
    'Eye',struct('n',numel(u),'t',(u+1000)','v',v'));
ex=struct('Trials',tr,'quit',0,'Header',struct());
end

function deleteIfPresent(file)
if isfile(file), delete(file); end
end
