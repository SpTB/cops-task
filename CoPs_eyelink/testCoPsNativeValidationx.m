function tests = testCoPsNativeValidationx
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repo = fileparts(fileparts(mfilename('fullpath')));
testCase.TestData.path = path;
addpath(repo, fullfile(repo,'CoPs_eyelink'));
end

function teardownOnce(testCase)
path(testCase.TestData.path);
end

function testNativeMetadataDoesNotClaimToExportModel(testCase)
ex = fixtureLocal();
ec = makeCoPsNativeEyeCalx(ex.setup,0,0,'VALIDATION HV9 R GOOD',50);
verifyEqual(testCase,ec.source,'eyelink');
verifyEqual(testCase,ec.units,'pixels');
verifyFalse(testCase,ec.native.coefficientsExported);
verifyEqual(testCase,ec.native.screenPixelCoords,[0 0 1919 1079]);
verifyEqual(testCase,ec.native.lastMessage,'VALIDATION HV9 R GOOD');
verifyEqual(testCase,ec.native.viewingDistanceCm,58);
end

function testTwoLegacyGridsRepeatsAndWindows(testCase)
ex = fixtureLocal();
ex.valid.passes = [1 2];
plan = makeCoPsNativeValidationPlanx(ex);
verifyNumElements(testCase,plan,150);
verifyEqual(testCase,sum([plan.pass]==1),75);
verifyEqual(testCase,sum([plan.pass]==2),75);
for p=1:2
    idx=[plan.pass]==p;
    positions=vertcat(plan(idx).targetOffsetPx);
    verifySize(testCase,unique(positions,'rows'),[25 2]);
    n=accumarray(findgroups(positions(:,1),positions(:,2)),1);
    verifyEqual(testCase,n,3*ones(25,1));
end
resolved=resolveCalibrationValidationDisplaySizes(ex);
verifyEqual(testCase,plan(1).targetWinPx,resolved.valid.targetWin);
verifyEqual(testCase,plan(end).targetWinPx,resolved.valid.targetWin2);
end

function testOffscreenTargetsRejected(testCase)
ex=fixtureLocal();
ex.valid.passes=1;
ex.valid.offsetsDeg=[-80 80];
verifyError(testCase,@() makeCoPsNativeValidationPlanx(ex),'CoPs:ValidationTargetOffscreen');
end

function testDefaultUsesSecondGridAndItsWindowOnly(testCase)
ex=fixtureLocal();
verifyEqual(testCase,ex.valid.passes,2);
plan=makeCoPsNativeValidationPlanx(ex);
verifyNumElements(testCase,plan,75);
verifyTrue(testCase,all([plan.pass]==2));
resolved=resolveCalibrationValidationDisplaySizes(ex);
verifyEqual(testCase,plan(1).targetWinPx,resolved.valid.targetWin2);
positions=vertcat(plan.targetOffsetPx);
expected=round(visualDegToPx(ex.valid.offsetsDeg2,ex.setup));
verifyEqual(testCase,unique(positions(:,1)),expected(:));
ex.valid.nRepeat=1;
verifyNumElements(testCase,makeCoPsNativeValidationPlanx(ex),25);
end

function testBlinkAndLongGapRestartFixation(testCase)
v=repmat([100;200;10;100;200;10],1,5);
v(:,3)=NaN;
[start,finish,last]=updateCoPsNativeValidationHoldx( ...
    v, [10 10.05 10.1 10.15 10.2], [100 200], [5 5], .15, NaN, -Inf);
verifyEqual(testCase,start,10.15);
verifyTrue(testCase,isnan(finish));
verifyEqual(testCase,last,10.2);
[start,finish]=updateCoPsNativeValidationHoldx( ...
    v(:,[1 2]), [10.5 10.55], [100 200], [5 5], .15, start, last);
verifyEqual(testCase,start,10.5);
verifyTrue(testCase,isnan(finish));
end

function testValidSingleEyeCanHoldWithoutReusingInvalidEye(testCase)
v=repmat([100;200;10;NaN;NaN;NaN],1,5);
[start,finish]=updateCoPsNativeValidationHoldx( ...
    v, [10 10.05 10.1 10.15 10.2], [100 200], [5 5], .15, NaN, -Inf);
verifyEqual(testCase,start,10);
verifyTrue(testCase,isfinite(finish));
v(1,2)=200;
[start,finish]=updateCoPsNativeValidationHoldx( ...
    v, [10 10.05 10.1 10.15 10.2], [100 200], [5 5], .15, NaN, -Inf);
verifyEqual(testCase,start,10.1);
verifyTrue(testCase,isnan(finish));
end

function testSummaryUsesAcceptedWindowAndDegreePositionDifference(testCase)
ex=fixtureLocal();
target=ex.fix.PCtr + visualDegToPx([8 4],ex.setup);
gaze=ex.fix.PCtr + visualDegToPx([9 4],ex.setup);
T=struct('Reward',1,'targetPx',target,'fixationCompleteTrackerSec',10.4);
T.Eye.t=10:.002:10.5;
T.Eye.v=repmat([gaze(:);10;NaN;NaN;NaN],1,numel(T.Eye.t));
r=summarizeCoPsNativeValidationx(T,ex.setup,ex.fix.PCtr);
verifyEqual(testCase,r.errorDeg(1,:),[1 0],'AbsTol',1e-10);
verifyEqual(testCase,r.radialErrorDeg(1),1,'AbsTol',1e-10);
verifyGreaterThanOrEqual(testCase,r.nSamples(1),49);
verifyEqual(testCase,r.nSamples(2),0);
verifyTrue(testCase,all(isnan(r.errorDeg(2,:))));
T.Reward=0;
r=summarizeCoPsNativeValidationx(T,ex.setup,ex.fix.PCtr);
verifyTrue(testCase,all(isnan(r.errorDeg),'all'));
end

function testSaveRoundTripPreservesTaskTrialsAndStandaloneLayout(testCase)
ex=fixtureLocal();
ex.eyeCal=makeCoPsNativeEyeCalx(ex.setup,0,0,'OK',50);
file=[tempname '.mat'];
cleanup=onCleanup(@() delete(file)); %#ok<NASGU>
ex.eyeCal.native.matFile=file;
ex.Trials=struct('taskTrial',true);
ex.eyeCal.validation=struct('Trials',struct('validationTrial',true));
returned=saveCoPsNativeEyeCalx(ex);
saved=load(file,'ex');
verifyEqual(testCase,returned.Trials,ex.Trials);
verifyEqual(testCase,saved.ex.Trials,ex.eyeCal.validation.Trials);
verifyEqual(testCase,saved.ex.eyeCal,ex.eyeCal);
end

function testPixelRefitAndAnalysisMatchWithoutChangingRawSamples(testCase)
ex=fixtureLocal();
offset=[975 532;950 548];
slopes=[1.1 .9; .8 1.2];
points=[-100 -80;0 0;100 80;100 -80;-100 80];
s=struct('targetPx',{},'gazePx',{});
for i=1:size(points,1)
    s(i).targetPx=ex.fix.PCtr + points(i,:);
    s(i).gazePx=offset + slopes.*points(i,:);
end
c=fitCoPsNativeEyeCorrectionx(s,ex.fix.PCtr);
verifyTrue(testCase,c.enabled);
verifyTrue(testCase,all(c.fitted,'all'));
verifyEqual(testCase,c.offsetPx,offset,'AbsTol',1e-10);
verifyEqual(testCase,c.gain,1./slopes,'AbsTol',1e-10);
raw=[s(1).gazePx(1,:)';10;s(1).gazePx(2,:)';12];
ec=struct('correction',c);
corrected=applyCoPsNativeEyeCorrectionx(raw,ec);
verifyEqual(testCase,corrected([1 2]),s(1).targetPx','AbsTol',1e-10);
verifyEqual(testCase,corrected([4 5]),s(1).targetPx','AbsTol',1e-10);
verifyEqual(testCase,corrected([3 6]),raw([3 6]));
T=struct('TrialStart',50,'Eye',struct('source','eyelink','n',1, ...
    'v',raw,'t',10,'ptbStart',50,'trackerStart',10));
ex.eyeCal=ec;
repo=fileparts(fileparts(mfilename('fullpath')));
oldPath=path;
cleanup=onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(fullfile(repo,'cops_analysis','helpers'));
[x,y]=reconstructEyePx(ex,T,true);
verifyEqual(testCase,[x y],s(1).targetPx,'AbsTol',1e-10);
verifyEqual(testCase,T.Eye.v,raw);
ec.correction.enabled=false;
verifyEqual(testCase,applyCoPsNativeEyeCorrectionx(raw,ec),raw);
end

function testRefitLeavesUnobservedEyeAndUnderdeterminedAxesAlone(testCase)
s=struct('targetPx',{},'gazePx',{});
for i=1:3
    s(i).targetPx=[i 0];
    s(i).gazePx=[2*i+5 7;NaN NaN];
end
c=fitCoPsNativeEyeCorrectionx(s,[0 0]);
verifyEqual(testCase,c.fitted,[true false;false false]);
verifyEqual(testCase,c.gain,[.5 1;1 1],'AbsTol',1e-10);
verifyEqual(testCase,c.offsetPx,[5 0;0 0],'AbsTol',1e-10);
end

function ex=fixtureLocal()
ex=struct();
ex.setup=struct('screenRect',[0 0 1920 1080], ...
    'monitorWidth',47,'viewingDistance',58,'el',struct('edfFileName','c123456.edf'));
ex.fix.PCtr=[960 540];
ex.valid=setDefaultsValid();
end
