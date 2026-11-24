function tests = testCoPsInstructionPracticex
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
folder=tempname; mkdir(folder);
testCase.TestData.folder=folder;
testCase.TestData.originalPath=path;
addpath(fileparts(mfilename('fullpath')),'-begin');
writeMock(folder,'runTrialTaskCoPsx',[
    "function ex=runTrialTaskCoPsx(ex,varargin)"
    "global COPS_PRACTICE_TEST"
    "COPS_PRACTICE_TEST.inputs{end+1}=ex;"
    "assert(ex.j~=COPS_PRACTICE_TEST.failAt,'PracticeTest:Failure','Injected trial failure');"
    "ex.Trials(ex.j).trialNumber=ex.j;"
    "ex.Trials(ex.j).Eye=struct('v',ex.j*ones(6,5),'t',1:5,'n',5);"
    "ex.Trials(ex.j).isInstructionTutorial=true;"
    "ex.Trials(ex.j).pointsCountTowardTotal=false;"
    "ex.Trials(ex.j).practiceRepeatRequested=ismember(ex.j,COPS_PRACTICE_TEST.repeatAt) && ex.setup.practiceRepeatsRemaining>0;"
    "ex.loopcnt(ex.j)=10; ex.goodtrial=99; ex.totalPoints=99;"
    "if COPS_PRACTICE_TEST.recalibrate"
    "    ex.Recalibration.pending=struct('nextTrial',ex.j+1,'source','trialFeedback');"
    "end"
    "if ex.j==COPS_PRACTICE_TEST.abortAt, ex.quit=4; end"
    "ex.j=ex.j+1;"
    "end"]);
writeMock(folder,'advanceCoPsInstructionFlowx',[
    "function [ex,shown]=advanceCoPsInstructionFlowx(ex)"
    "global COPS_PRACTICE_TEST"
    "shown=ex.quit==0 && ~ex.Instructions.Trials(end).practiceRepeatRequested;"
    "if shown, COPS_PRACTICE_TEST.pages(end+1)=numel(ex.Instructions.Trials); end"
    "end"]);
writeMock(folder,'recalibrateCoPsx',[
    "function ex=recalibrateCoPsx(ex)"
    "global COPS_PRACTICE_TEST"
    "COPS_PRACTICE_TEST.calibrationInputs{end+1}=ex;"
    "ex.eyeCal.RXGain=ex.eyeCal.RXGain+1; ex.Recalibration.pending=[];"
    "end"]);
addpath(folder,'-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear runTrialTaskCoPsx advanceCoPsInstructionFlowx recalibrateCoPsx
rmdir(testCase.TestData.folder,'s');
clear global COPS_PRACTICE_TEST
end

function setup(~)
global COPS_PRACTICE_TEST
COPS_PRACTICE_TEST=struct('inputs',{{}},'calibrationInputs',{{}}, ...
    'pages',[],'abortAt',0,'failAt',0,'recalibrate',false,'repeatAt',[]);
end

function testPracticeDataAndNumbersAreSeparateFromTaskPlan(testCase)
global COPS_PRACTICE_TEST
ex=fixture(); before=ex;
[ex,file]=runPractice(testCase,ex);
verifyEqual(testCase,ex.Trials,before.Trials);
verifyEqual(testCase,[ex.j ex.finish ex.goodtrial ex.totalPoints],[1 3 0 0]);
verifyEqual(testCase,ex.exp,before.exp);
verifyEqual(testCase,ex.stim,before.stim);
verifyEqual(testCase,ex.loopcnt,before.loopcnt);
verifyEqual(testCase,[ex.Instructions.Trials.trialNumber],[1 2]);
verifyEqual(testCase,COPS_PRACTICE_TEST.pages,[1 2]);
for k=1:2
    input=COPS_PRACTICE_TEST.inputs{k};
    info=getCoPsTrialBlockInfox(input);
    verifyEqual(testCase,info.instructionIdx,[1 2]);
    verifyEmpty(testCase,info.mainIdx);
    snapshot=load(fullfile(ex.Header.onlineInstructionDirName,sprintf('practice%d.mat',k)));
    verifyEqual(testCase,snapshot.Trials.Eye,ex.Instructions.Trials(k).Eye);
end
verifyFalse(testCase,isfile(fullfile(fileparts(file),'tr1.mat')));
saved=load(file,'ex'); verifyEqual(testCase,saved.ex,ex);
end

function testVoluntaryRepeatsStopAtThreeAndKeepTaskTrialOne(testCase)
global COPS_PRACTICE_TEST
COPS_PRACTICE_TEST.repeatAt=2:10;
ex=fixture(); before=ex;
[ex,file]=runPractice(testCase,ex);
verifyNumElements(testCase,ex.Instructions.Trials,5);
verifyEqual(testCase,[ex.Instructions.Trials.trialNumber],1:5);
verifyEqual(testCase,[ex.Instructions.Trials.practiceRepeatRequested],[false true true true false]);
verifyEqual(testCase,COPS_PRACTICE_TEST.pages,[1 5]);
verifyEqual(testCase,ex.exp,before.exp);
verifyEmpty(testCase,ex.Trials);
verifyEqual(testCase,[ex.j ex.finish ex.goodtrial ex.totalPoints],[1 3 0 0]);
for k=2:5
    input=COPS_PRACTICE_TEST.inputs{k};
    verifyEqual(testCase,input.exp.CoPs.trialParamSchedules.background_noise_lvl(k),1);
    verifyEqual(testCase,input.setup.practiceRepeatsRemaining,5-k);
    verifyTrue(testCase,isfile(fullfile(ex.Header.onlineInstructionDirName,sprintf('practice%d.mat',k))));
end
saved=load(file,'ex'); verifyEqual(testCase,saved.ex,ex);
end

function testSpaceAfterOneRepeatContinuesToReady(testCase)
global COPS_PRACTICE_TEST
COPS_PRACTICE_TEST.repeatAt=2;
[ex,~]=runPractice(testCase,fixture());
verifyNumElements(testCase,ex.Instructions.Trials,3);
verifyEqual(testCase,COPS_PRACTICE_TEST.pages,[1 3]);
verifyEqual(testCase,ex.j,1);
end

function testAbortDuringRepeatPreservesAllPractice(testCase)
global COPS_PRACTICE_TEST
COPS_PRACTICE_TEST.repeatAt=[2 3];
COPS_PRACTICE_TEST.abortAt=3;
[ex,file]=runPractice(testCase,fixture());
verifyEqual(testCase,ex.quit,4);
verifyNumElements(testCase,ex.Instructions.Trials,3);
verifyEmpty(testCase,ex.Trials);
saved=load(file,'ex'); verifyEqual(testCase,saved.ex,ex);
end

function testPracticeF6PreservesDataAndUpdatesNextPracticeAndTaskCalibration(testCase)
global COPS_PRACTICE_TEST
COPS_PRACTICE_TEST.recalibrate=true;
[ex,~]=runPractice(testCase,fixture());
verifyEqual(testCase,ex.eyeCal.RXGain,3);
verifyEqual(testCase,COPS_PRACTICE_TEST.inputs{2}.eyeCal.RXGain,2);
for k=1:2
    input=COPS_PRACTICE_TEST.calibrationInputs{k};
    verifyEmpty(testCase,input.Trials);
    verifyNumElements(testCase,input.Instructions.Trials,k);
    verifyEqual(testCase,input.Recalibration.pending.nextTrial,1);
end
end

function testAbortPreservesPracticeAndStopsBeforeTask(testCase)
global COPS_PRACTICE_TEST
COPS_PRACTICE_TEST.abortAt=1;
[ex,file]=runPractice(testCase,fixture());
verifyEqual(testCase,ex.quit,4);
verifyEqual(testCase,ex.j,1);
verifyNumElements(testCase,ex.Instructions.Trials,1);
verifyEmpty(testCase,ex.Trials);
verifyEmpty(testCase,COPS_PRACTICE_TEST.pages);
saved=load(file,'ex'); verifyEqual(testCase,saved.ex,ex);
end

function testErrorPreservesCompletedPracticeCheckpoint(testCase)
global COPS_PRACTICE_TEST
COPS_PRACTICE_TEST.failAt=2;
[ex,file]=runPractice(testCase,fixture());
verifyEqual(testCase,ex.quit,4);
verifyEqual(testCase,ex.lastError.identifier,'PracticeTest:Failure');
verifyNumElements(testCase,ex.Instructions.Trials,1);
verifyEmpty(testCase,ex.Trials);
saved=load(file,'ex'); verifyEqual(testCase,saved.ex,ex);
end

function testDisabledInstructionsLeaveSessionAlone(testCase)
ex=fixture(); ex.exp.CoPs.instrOn=false;
[actual,~]=runPractice(testCase,ex);
verifyEqual(testCase,actual,ex);
end

function ex=fixture()
evalc('ex=setDefaultsCoPs(struct());');
ex.exp.CoPs.instrOn=true;
ex.exp.CoPs.pre.nreps=0; ex.exp.CoPs.tut.nreps=0; ex.exp.CoPs.pur.nreps=0;
ex.exp.nreps=3; ex.exp.total_nreps=3;
ex.j=1; ex.finish=3; ex.quit=0; ex.goodtrial=0; ex.totalPoints=0;
ex.Trials=struct([]); ex.loopcnt=[];
ex.setup=struct('dependencies',struct('adcOn',false));
ex.eyeCal=struct('RXGain',1);
ex.Instructions=struct('acknowledged',true);
ex.stim.seq={'first','second','third'};
end

function [ex,file]=runPractice(testCase,ex)
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
clear runTrialTaskCoPsx advanceCoPsInstructionFlowx recalibrateCoPsx
file=fullfile(testCase.TestData.folder,'session.mat');
ex=runCoPsInstructionPracticex(ex,false,false,false,file);
end

function writeMock(folder,name,lines)
fid=fopen(fullfile(folder,[name '.m']),'w');
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',lines);
end
