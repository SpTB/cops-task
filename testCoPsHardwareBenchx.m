function tests=testCoPsHardwareBenchx
% Hardware-free checks for bench source isolation and measurement analysis.
tests=functiontests(localfunctions);
end

function testGeneratedRunnersPreserveProductionFiles(testCase)
folder=tempname; mkdir(folder);
cleanup=onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
root=fileparts(mfilename('fullpath'));
before=fileread(fullfile(root,'runTrialTaskCoPsx.m'));
names=makeCoPsBenchRunnerx(folder);
verifyEqual(testCase,fileread(fullfile(root,'runTrialTaskCoPsx.m')),before);
old=fileread(fullfile(folder,[names{1} '.m']));
new=fileread(fullfile(folder,[names{2} '.m']));
verifyTrue(testCase,contains(old,'ttime > lastframet + frametimestep'));
verifyFalse(testCase,contains(old,"Screen('AsyncFlipBegin'"));
verifyTrue(testCase,contains(new,"Screen('AsyncFlipBegin'"));
for source={old,new}
    verifyTrue(testCase,contains(source{1},'sampleCoPsBenchInputx('));
    verifyFalse(testCase,contains(source{1},"Eyelink('TrackerTime')"));
    verifyTrue(testCase,contains(source{1},'benchOutputCleanup'));
    verifyTrue(testCase,contains(source{1},'rewardOutput'));
    verifyTrue(testCase,contains(source{1},'benchBlankVbl'));
end
for k=1:2
    issues=checkcode(fullfile(folder,[names{k} '.m']),'-id');
    verifyFalse(testCase,any(strcmp({issues.id},'SYNER')),'Generated runner has a syntax error.');
end
end

function testAnalysisUsesHardwarePulsesAndFindsADCGaps(testCase)
t=fixture();
s=analyzeCoPsHardwareBenchx(t);
verifyEqual(testCase,s.rewardRequests,3);
verifyEqual(testCase,s.rewardPulsesGO,2);
verifyEqual(testCase,s.medianRewardWidthMs,250,'AbsTol',1e-9);
verifyEqual(testCase,s.pollHz,500,'AbsTol',1e-8);
verifyEqual(testCase,s.adcHz,500,'AbsTol',1e-8);
verifyEqual(testCase,s.adcGaps,1);
verifyEqual(testCase,s.skippedRefreshes,1);
end

function testClockSynchronizationPreservesTrialRandomStream(testCase)
folder=tempname; mkdir(folder);
originalPath=path; originalRng=rng;
cleanup=onCleanup(@() restoreClockMock(folder,originalPath,originalRng)); %#ok<NASGU>
fid=fopen(fullfile(folder,'PsychDataPixx.m'),'w');
fprintf(fid,['function [a,b,c]=PsychDataPixx(varargin)\n' ...
    'rand(1,randi(100)); a=rand; b=rand; c=rand;\nend\n']);
fclose(fid);
addpath(folder,'-begin'); clear PsychDataPixx
rng(12345); expected=rand(1,8);
rng(12345); anchor=getCoPsBenchClockAnchorx(); actual=rand(1,8);
verifySize(testCase,anchor,[1 3]);
verifyEqual(testCase,actual,expected);
end

function restoreClockMock(folder,originalPath,originalRng)
path(originalPath); clear PsychDataPixx
rng(originalRng); rmdir(folder,'s');
end

function testNoGoOrPulsesAreReportedWithoutInventingMeasurements(testCase)
t=fixture();
t.frameState(:)=0; t.times.stimOn=NaN;
t.bench.polls(:,5)=0;
t.bench.dinData=[]; t.bench.dinTime=[];
s=analyzeCoPsHardwareBenchx(t);
verifyFalse(testCase,s.goReached);
verifyEqual(testCase,s.rewardPulsesGO,0);
verifyTrue(testCase,isnan(s.pollHz));
verifyTrue(testCase,isnan(s.photodiodeOnsetDelayMs));
end

function t=fixture()
t.frameStateLookup.GO=6;
t.frameState=6*ones(10,1); t.frameStep=(1:10)';
t.flip_info=[(100+(0:9)'/120) nan(10,3)];
t.flip_info(6:end,1)=t.flip_info(6:end,1)+1/120;
t.displayRefreshIntervalSec=1/120;
t.times.stimOn=100; t.times.startTrial=98;
t.times.reward=[100.1 100.4 100.7];
t.adcChannels=6;
t.Eye.t=50+(0:599)*.002;
t.Eye.t(301:end)=t.Eye.t(301:end)+.002;
t.Eye.v=zeros(1,600); t.Eye.n=600;
t.bench.config=struct('version','vbl','scenario','fixed','pair',1,'markerMode','step', ...
    'rewardOutput',true,'photodiodeChannel',6,'photodiodePolarity',1,'photodiodeThresholdV',1);
t.bench.polls=zeros(100,14);
t.bench.polls(:,1)=100+(0:99)'*.002;
t.bench.polls(:,2)=t.bench.polls(:,1)+.0002;
t.bench.polls(:,5)=1;
t.bench.dinData=[1 0 1 0]; t.bench.dinTime=[50.1 50.35 50.5 50.75];
t.bench.clockBefore=[100 50 .00001]; t.bench.clockAfter=[102 52 .00001];
t.bench.tailUnderflow=0; t.bench.tailOverflow=0; t.bench.dinUnderflow=0;
t.bench.blankVbl=101; t.bench.marker=zeros(10,1); t.bench.aborted=false;
end
