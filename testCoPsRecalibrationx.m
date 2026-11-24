function tests = testCoPsRecalibrationx
% Mock tracker operations; exercise real checkpointing and calibration snapshots.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
folder=tempname; mkdir(folder);
testCase.TestData.folder=folder;
testCase.TestData.originalPath=path;
root=fileparts(mfilename('fullpath'));
addpath(fullfile(root,'CoPs_eyelink'),root,'-begin');
writeMock(folder,'Eyelink',[
    "function varargout=Eyelink(command,varargin)"
    "global COPS_RECAL_TEST"
    "COPS_RECAL_TEST.commands{end+1}=command;"
    "switch command"
    "case 'Message'"
    "    assert(all(cellfun(@(v) ischar(v) || isnumeric(v),varargin)), ..."
    "        'RecalTest:MessageType','EyeLink Message accepts character and numeric arguments, not logicals.');"
    "    COPS_RECAL_TEST.messages{end+1}=sprintf(varargin{:}); varargout={0};"
    "case {'StopRecording','SetOfflineMode'}, varargout={0};"
    "case 'StartRecording', varargout={COPS_RECAL_TEST.recordingStatus};"
    "case 'CalMessage', varargout={0,'GOOD calibration'};"
    "otherwise, error('RecalTest:UnexpectedTrackerCall','Must not reopen/close/receive the task EDF.');"
    "end"
    "end"]);
writeMock(folder,'EyelinkUpdateDefaults',[
    "function EyelinkUpdateDefaults(el)"
    "global COPS_RECAL_TEST"
    "COPS_RECAL_TEST.el=el;"
    "end"]);
writeMock(folder,'EyelinkDoTrackerSetup',[
    "function status=EyelinkDoTrackerSetup(el)"
    "global COPS_RECAL_TEST"
    "if ~isempty(COPS_RECAL_TEST.checkpoint)"
    "    s=load(COPS_RECAL_TEST.checkpoint,'ex');"
    "    COPS_RECAL_TEST.beforeSetup=s.ex;"
    "end"
    "rand(1,7); status=COPS_RECAL_TEST.setupStatus;"
    "end"]);
writeMock(folder,'validateCoPsNativeEyelinkx',[
    "function ex=validateCoPsNativeEyelinkx(ex)"
    "global COPS_RECAL_TEST"
    "COPS_RECAL_TEST.validationCalls=COPS_RECAL_TEST.validationCalls+1;"
    "COPS_RECAL_TEST.validationInput=ex;"
    "ex.eyeCal.RXGain=17;"
    "ex.eyeCal.validation=struct('completed',~COPS_RECAL_TEST.abort,'Trials',struct('ID',901));"
    "if COPS_RECAL_TEST.abort, ex.quit=4; end"
    "ex=saveCoPsNativeEyeCalx(ex);"
    "ex.j=999; ex.Trials=struct('ID',999); ex.totalPoints=999;"
    "end"]);
writeMock(folder,'calibrateEye2vx',[
    "function ex=calibrateEye2vx(ex)"
    "global COPS_RECAL_TEST"
    "COPS_RECAL_TEST.analogInput=ex;"
    "ex.eyeCal=makeCoPsMouseEyeCalx(); ex.eyeCal.RXGain=23;"
    "ex.j=999; ex.finish=999; ex.Trials=struct('ID',999);"
    "ex.Header.edfFileName='wrong.edf'; ex.Header.onlineFileName='wrong.mat';"
    "ex.totalPoints=999; ex.quit=4*double(COPS_RECAL_TEST.abort);"
    "end"]);
writeMock(folder,'GetSecs',[
    "function t=GetSecs"
    "global COPS_RECAL_TEST"
    "COPS_RECAL_TEST.time=COPS_RECAL_TEST.time+1; t=COPS_RECAL_TEST.time;"
    "end"]);
writeMock(folder,'WaitSecs',["function WaitSecs(varargin)";"end"]);
addpath(folder,'-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear Eyelink EyelinkUpdateDefaults EyelinkDoTrackerSetup validateCoPsNativeEyelinkx calibrateEye2vx GetSecs WaitSecs
folder=testCase.TestData.folder;
assert(strcmp(fileparts(folder),fileparts(tempname)));
rmdir(folder,'s');
clear global COPS_RECAL_TEST
end

function setup(~)
global COPS_RECAL_TEST
COPS_RECAL_TEST=struct('commands',{{}},'messages',{{}},'setupStatus',0,'recordingStatus',0, ...
    'abort',false,'time',100,'checkpoint','','validationCalls',0);
end

function testNativeRedoCheckpointsPreservesTaskAndKeepsSessionEdf(testCase)
global COPS_RECAL_TEST
ex=fixture(testCase); before=ex; randomState=rng;
file=fullfile(testCase.TestData.folder,'checkpoint.mat');
COPS_RECAL_TEST.checkpoint=file;
ex=perform(testCase,ex,file);
verifyEqual(testCase,ex.Trials,before.Trials);
verifyEqual(testCase,ex.Header,before.Header);
verifyEqual(testCase,[ex.j ex.finish ex.goodtrial ex.totalPoints], ...
    [before.j before.finish before.goodtrial before.totalPoints]);
verifyEqual(testCase,rng,randomState);
verifyEqual(testCase,COPS_RECAL_TEST.beforeSetup,before);
verifyEqual(testCase,ex.eyeCal.RXGain,1);
verifyEqual(testCase,COPS_RECAL_TEST.validationCalls,0);
verifyFalse(testCase,isfield(ex.eyeCal,'validation'));
verifyEqual(testCase,ex.eyeCal.native.edfHostName,'task.edf');
verifyEqual(testCase,ex.eyeCal.native.edfFile,fullfile(before.Header.onlineEdfDirName,'task.edf'));
verifyTrue(testCase,ex.eyeCal.native.edfSharedWithSession);
verifyTrue(testCase,isfile(ex.eyeCal.native.matFile));
snapshot=load(ex.eyeCal.native.matFile,'ex');
verifyEmpty(testCase,snapshot.ex.Trials);
verifyEqual(testCase,snapshot.ex.eyeCal,ex.eyeCal);
verifyEmpty(testCase,ex.Recalibration.pending);
verifyTrue(testCase,ex.Recalibration.history.completed);
verifyEqual(testCase,ex.quit,0);
verifyEqual(testCase,ex.Recalibration.history.nextTrial,3);
verifyEqual(testCase,ex.Recalibration.history.eyeCalBefore,before.eyeCal);
verifyEqual(testCase,COPS_RECAL_TEST.el.targetbeep,0);
verifyEqual(testCase,COPS_RECAL_TEST.el.feedbackbeep,0);
verifyEqual(testCase,ex.setup.el,before.setup.el);
verifyEqual(testCase,ex.setup.rewardSound,before.setup.rewardSound);
verifyEqual(testCase,COPS_RECAL_TEST.commands, ...
    {'Message','StopRecording','SetOfflineMode','CalMessage','StartRecording','Message'});
verifyEqual(testCase,COPS_RECAL_TEST.messages, ...
    {'COPS_RECALIBRATION_BEGIN NEXT_TRIAL 3','COPS_RECALIBRATION_END COMPLETED 1'});
saved=load(file,'ex'); verifyEqual(testCase,saved.ex,ex);
end

function testRepeatedRecalibrationsKeepHistoryAndSeparateSnapshots(testCase)
ex=fixture(testCase);
ex=perform(testCase,ex);
firstFile=ex.eyeCal.native.matFile;
ex.Recalibration.pending=struct('requestedAt',200,'nextTrial',4,'source','instructions:ready');
ex=perform(testCase,ex);
verifyNumElements(testCase,ex.Recalibration.history,2);
verifyEqual(testCase,[ex.Recalibration.history.nextTrial],[3 4]);
verifyNotEqual(testCase,ex.eyeCal.native.matFile,firstFile);
verifyTrue(testCase,isfile(firstFile));
end

function testTrackerFailureStopsAndSavesCompletedTrialData(testCase)
global COPS_RECAL_TEST
COPS_RECAL_TEST.setupStatus=1;
ex=fixture(testCase); before=ex;
file=fullfile(testCase.TestData.folder,'failure.mat');
warningState=warning('off','CoPs:RecalibrationFailed');
cleanup=onCleanup(@() warning(warningState)); %#ok<NASGU>
ex=perform(testCase,ex,file);
verifyEqual(testCase,ex.quit,4);
verifyFalse(testCase,ex.Recalibration.history.completed);
verifyEqual(testCase,ex.Recalibration.history.errorIdentifier,'CoPs:RecalibrationSetup');
verifyEqual(testCase,ex.lastError.identifier,'CoPs:RecalibrationSetup');
verifyEqual(testCase,ex.Trials,before.Trials);
verifyEqual(testCase,ex.eyeCal,before.eyeCal);
verifyEqual(testCase,COPS_RECAL_TEST.validationCalls,0);
saved=load(file,'ex'); verifyEqual(testCase,saved.ex,ex);
end

function testRecordingFailureDoesNotStartValidation(testCase)
global COPS_RECAL_TEST
COPS_RECAL_TEST.recordingStatus=1;
warningState=warning('off','CoPs:RecalibrationFailed');
cleanup=onCleanup(@() warning(warningState)); %#ok<NASGU>
ex=perform(testCase,fixture(testCase));
verifyEqual(testCase,ex.quit,4);
verifyEqual(testCase,COPS_RECAL_TEST.validationCalls,0);
verifyEqual(testCase,ex.Recalibration.history.errorIdentifier,'CoPs:RecalibrationRecording');
verifyEqual(testCase,ex.lastError.identifier,'CoPs:RecalibrationRecording');
end

function testNativeRedoDropsPreviousValidationAndCorrection(testCase)
global COPS_RECAL_TEST
% Even when initial validation fitted a correction, F6 must use the new
% tracker calibration without launching another custom grid.
COPS_RECAL_TEST.abort=true;
ex=fixture(testCase);
ex.eyeCal.validation=struct('completed',true,'Trials',struct('ID',901));
ex.eyeCal.correction=struct('enabled',true,'gain',2*ones(2));
before=ex;
ex=perform(testCase,ex);
verifyEqual(testCase,COPS_RECAL_TEST.validationCalls,0);
verifyEqual(testCase,ex.quit,0);
verifyTrue(testCase,ex.Recalibration.history.completed);
verifyFalse(testCase,isfield(ex.eyeCal,'validation'));
verifyFalse(testCase,isfield(ex.eyeCal,'correction'));
verifyEqual(testCase,ex.Trials,before.Trials);
verifyEqual(testCase,ex.Recalibration.history.eyeCalBefore,before.eyeCal);
verifyEqual(testCase,ex.Recalibration.history.errorIdentifier,'');
verifyEqual(testCase,COPS_RECAL_TEST.messages{end},'COPS_RECALIBRATION_END COMPLETED 1');
end

function testAnalogRedoRunsOnCopyWithFileLoadingDisabled(testCase)
global COPS_RECAL_TEST
ex=fixture(testCase); ex.setup.inputMode='eye'; before=ex;
ex=perform(testCase,ex);
verifyEqual(testCase,ex.Trials,before.Trials);
verifyEqual(testCase,ex.Header,before.Header);
verifyEqual(testCase,[ex.j ex.finish ex.totalPoints],[before.j before.finish before.totalPoints]);
verifyEqual(testCase,ex.eyeCal.RXGain,23);
verifyTrue(testCase,COPS_RECAL_TEST.analogInput.setup.inTaskRecalibration);
verifyEmpty(testCase,COPS_RECAL_TEST.analogInput.calib.file);
verifyFalse(testCase,COPS_RECAL_TEST.analogInput.calib.validate);
verifyEmpty(testCase,COPS_RECAL_TEST.commands);
end

function testAnalogAbortIsNotReset(testCase)
global COPS_RECAL_TEST
COPS_RECAL_TEST.abort=true;
ex=fixture(testCase); ex.setup.inputMode='eye';
ex=perform(testCase,ex);
verifyEqual(testCase,ex.quit,4);
verifyFalse(testCase,ex.Recalibration.history.completed);
end

function testNoRequestDoesNothing(testCase)
ex=fixture(testCase); ex=rmfield(ex,'Recalibration');
file=fullfile(testCase.TestData.folder,'unused.mat');
verifyEqual(testCase,completeCoPsPauseActionsx(ex,file),ex);
verifyFalse(testCase,isfile(file));
end

function ex=perform(testCase,ex,file)
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
clear Eyelink EyelinkUpdateDefaults EyelinkDoTrackerSetup validateCoPsNativeEyelinkx calibrateEye2vx GetSecs WaitSecs
if nargin < 3
    ex=recalibrateCoPsx(ex);
else
    ex=completeCoPsPauseActionsx(ex,file);
end
end

function ex=fixture(testCase)
ex=struct('j',3,'finish',10,'quit',0,'goodtrial',2,'totalPoints',4.2);
ex.Trials=struct('ID',{1,2},'times',{struct('reward',1:2),struct('reward',1:2)});
ex.setup=struct('inputMode','eyelink','window',7,'screenRect',[0 0 1920 1080], ...
    'monitorWidth',54,'viewingDistance',55,'filePrefix','recal_test', ...
    'dirRoot',fullfile(testCase.TestData.folder,'output'), ...
    'el',struct('binoc',true,'edfFileName','initial.edf','targetbeep',1,'feedbackbeep',1));
ex.setup.rewardSound=struct('enabled',true,'handle',37);
ex.Header=struct('animal','test','edfFileName','task.edf','onlineFileName','session.mat', ...
    'onlineEdfDirName',fullfile(testCase.TestData.folder,'edf'));
ex.eyeCal=makeCoPsMouseEyeCalx(); ex.eyeCal.RXGain=8;
ex.calib=struct('file','previous.mat','validate',false);
ex.Recalibration.pending=struct('requestedAt',50,'nextTrial',3,'source','trialFeedback');
end

function writeMock(folder,name,lines)
fid=fopen(fullfile(folder,[name '.m']),'w');
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',lines);
end
