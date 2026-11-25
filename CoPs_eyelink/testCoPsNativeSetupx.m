function tests=testCoPsNativeSetupx
tests=functiontests(localfunctions);
end
function setupOnce(testCase)
folder=tempname;mkdir(folder);testCase.TestData.folder=folder;testCase.TestData.oldPath=path;
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'CoPs_eyelink'));
write(folder,'EyelinkInit',["function [ok,dummy]=EyelinkInit";"ok=true;dummy=false;";"end"]);
write(folder,'EyelinkInitDefaults',[
 "function el=EyelinkInitDefaults(window)"
 "global COPS_NATIVE_SETUP_TEST"
 "callback='nativeSetupCallback';if COPS_NATIVE_SETUP_TEST.noCallback,callback=[];end"
 "el=struct('window',window,'callback',callback,'targetbeep',1,'feedbackbeep',1,'ppa_pahandle',[]);"
 "el.cal_target_beep=[1250 0.6 0.05];"
 "el.drift_correction_target_beep=[1250 0.8 0.05];"
 "el.calibration_failed_beep=[400 0.8 0.25];"
 "el.calibration_success_beep=[800 0.8 0.25];"
 "el.drift_correction_failed_beep=[400 0.8 0.25];"
 "el.drift_correction_success_beep=[800 0.8 0.25];"
 "end"]);
write(folder,'nativeSetupCallback',[
 "function nativeSetupCallback(el)"
 "global COPS_NATIVE_SETUP_TEST"
 "COPS_NATIVE_SETUP_TEST.callbackSettings=el;"
 "COPS_NATIVE_SETUP_TEST.callbackUpdates=COPS_NATIVE_SETUP_TEST.callbackUpdates+1;"
 "end"]);
write(folder,'EyelinkUpdateDefaults',[
 "function EyelinkUpdateDefaults(varargin)"
 "error('NativeSetupTest:AudioOwner','Display/keyboard updates must not auto-open protected EyeLink audio.');"
 "end"]);
write(folder,'PsychPortAudio',[
 "function varargout=PsychPortAudio(varargin)"
 "error('NativeSetupTest:UnexpectedAudio','Keyboard routing must not open or close audio streams.');"
 "end"]);
write(folder,'EyelinkDoTrackerSetup',[
 "function status=EyelinkDoTrackerSetup(el)"
 "global COPS_NATIVE_SETUP_TEST"
 "COPS_NATIVE_SETUP_TEST.trackerSettings=el;"
 "status=0;"
 "end"]);
write(folder,'Eyelink',[
 "function varargout=Eyelink(command,varargin)"
 "global COPS_NATIVE_SETUP_TEST"
 "COPS_NATIVE_SETUP_TEST.trackerCalls{end+1}=command;"
 "if strcmp(command,'CalMessage'),varargout={0,'Calibration successful'};else,varargout={0};end"
 "end"]);
write(folder,'KbCheck',[
 "function [down,t,keys]=KbCheck(device)"
 "global COPS_NATIVE_SETUP_TEST"
 "COPS_NATIVE_SETUP_TEST.keyboardDevice=device;down=false;t=0;keys=false(1,256);"
 "end"]);
write(folder,'GetSecs',["function t=GetSecs";"t=123;";"end"]);
write(folder,'WaitSecs',["function WaitSecs(varargin)";"end"]);
addpath(folder,'-begin');
end
function teardownOnce(testCase)
path(testCase.TestData.oldPath);
clear EyelinkInit EyelinkInitDefaults nativeSetupCallback EyelinkUpdateDefaults PsychPortAudio EyelinkDoTrackerSetup Eyelink KbCheck GetSecs WaitSecs
rmdir(testCase.TestData.folder,'s');clear global COPS_NATIVE_SETUP_TEST
end
function setup(~)
global COPS_NATIVE_SETUP_TEST
COPS_NATIVE_SETUP_TEST=struct('noCallback',false,'callbackSettings',[], ...
 'callbackUpdates',0,'trackerSettings',[],'keyboardDevice',[], 'trackerCalls',{{}});
end
function testSeparateKeyboardUpdateDoesNotCreateProtectedAudioOwner(testCase)
global COPS_NATIVE_SETUP_TEST
ex=fixture();ex.setup.keyboards=struct('separate',true,'experimenterIndex',4);
ex=initialize(testCase,ex);
verifyEqual(testCase,COPS_NATIVE_SETUP_TEST.callbackUpdates,1);
verifyEqual(testCase,COPS_NATIVE_SETUP_TEST.callbackSettings.devicenumber,4);
verifyEqual(testCase,COPS_NATIVE_SETUP_TEST.callbackSettings.backgroundcolour,128);
verifyEqual(testCase,COPS_NATIVE_SETUP_TEST.keyboardDevice,4);
verifyEqual(testCase,COPS_NATIVE_SETUP_TEST.trackerSettings.devicenumber,4);
verifyEqual(testCase,COPS_NATIVE_SETUP_TEST.callbackSettings.targetbeep,1);
verifyEqual(testCase,COPS_NATIVE_SETUP_TEST.callbackSettings.feedbackbeep,1);
verifyEqual(testCase,COPS_NATIVE_SETUP_TEST.callbackSettings.cal_target_beep,[1250 0.1 0.05]);
verifyEqual(testCase,COPS_NATIVE_SETUP_TEST.callbackSettings.calibration_success_beep,[800 0.1 0.25]);
verifyEqual(testCase,COPS_NATIVE_SETUP_TEST.callbackSettings.calibration_failed_beep,[400 0.1 0.25]);
verifyEmpty(testCase,COPS_NATIVE_SETUP_TEST.callbackSettings.ppa_pahandle);
verifyEqual(testCase,ex.setup.eyeTracker,'Eyelink');
verifyEqual(testCase,ex.eyeCal.source,'eyelink');
verifyTrue(testCase,any(strcmp(COPS_NATIVE_SETUP_TEST.trackerCalls,'StartRecording')));
end
function testSharedKeyboardUpdatesBackgroundAndRetainsAudioSetup(testCase)
global COPS_NATIVE_SETUP_TEST
ex=fixture();ex.setup.keyboards=struct('separate',false);
ex.idx.bg_lum=97; % Prove setup follows the task color, not a hardcoded gray.
ex.setup.el.calibrationBeepVolume=0.05;
ex=initialize(testCase,ex);
verifyEqual(testCase,COPS_NATIVE_SETUP_TEST.callbackUpdates,1);
verifyEqual(testCase,COPS_NATIVE_SETUP_TEST.callbackSettings.backgroundcolour,97);
verifyEqual(testCase,COPS_NATIVE_SETUP_TEST.trackerSettings.backgroundcolour,97);
verifyEqual(testCase,COPS_NATIVE_SETUP_TEST.callbackSettings.cal_target_beep,[1250 0.05 0.05]);
verifyEqual(testCase,COPS_NATIVE_SETUP_TEST.trackerSettings.drift_correction_target_beep,[1250 0.05 0.05]);
verifyEqual(testCase,ex.setup.el.calibrationBeepVolume,0.05);
verifyEmpty(testCase,COPS_NATIVE_SETUP_TEST.keyboardDevice);
verifyEqual(testCase,ex.setup.el.targetbeep,1);
verifyEqual(testCase,ex.setup.el.feedbackbeep,1);
end
function testKeyboardSelectionWorksWithLegacyEmptyCallback(testCase)
global COPS_NATIVE_SETUP_TEST
COPS_NATIVE_SETUP_TEST.noCallback=true;
ex=fixture();ex.setup.keyboards=struct('separate',true,'experimenterIndex',4);
ex=initialize(testCase,ex);
verifyEqual(testCase,COPS_NATIVE_SETUP_TEST.callbackUpdates,0);
verifyEqual(testCase,COPS_NATIVE_SETUP_TEST.trackerSettings.devicenumber,4);
end
function ex=fixture()
ex=struct('idx',struct('bg_lum',128),'setup',struct('window',101,'screenRect',[0 0 1920 1080], ...
 'monitorWidth',54,'viewingDistance',65,'el',struct('edfFileName','test.edf', ...
 'binoc',1,'Cmd_SampleData','link_sample_data = LEFT,RIGHT,GAZE,AREA,INPUT,HTARGET')));
end
function ex=initialize(testCase,ex)
original=pwd;cd(testCase.TestData.folder);cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
ex=initCoPsEyelinkx(ex);
end
function write(folder,name,lines)
fid=fopen(fullfile(folder,[name '.m']),'w');cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',lines);
end
