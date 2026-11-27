function tests = testRecEx
tests=functiontests(localfunctions);
end

function testNeuralRecordingFlagsDoNotEnableMovies(testCase)
ex.setup = struct();
verifyFalse(testCase,isCoPsMovieRecordingx(ex));
for flag = {false,true,0,1,struct(),struct('enabled',false)}
    ex.setup.recording = flag{1};
    verifyFalse(testCase,isCoPsMovieRecordingx(ex));
end
end

function testMovieConfigurationEnablesMovies(testCase)
ex.setup.recording = struct('enabled',true);
verifyTrue(testCase,isCoPsMovieRecordingx(ex));
end

function setupOnce(testCase)
folder=tempname; mkdir(folder);
testCase.TestData.folder=folder;
testCase.TestData.originalPath=path;
fid=fopen(fullfile(folder,'runEx.m'),'w');
fprintf(fid,'%s\n',[
    "function ex=runEx(profile,varargin)"
    "global COPS_RECEX_TEST"
    "COPS_RECEX_TEST=struct('profile',profile,'args',struct(varargin{:}));"
    "ex=struct('MovieFiles',{{'test.mp4'}});"
    "end"]);
fclose(fid);
addpath(fileparts(mfilename('fullpath')),folder,'-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath); clear runEx
folder=testCase.TestData.folder;
assert(strcmp(fileparts(folder),fileparts(tempname)));
rmdir(folder,'s');
clear global COPS_RECEX_TEST
end

function testDefaultsAreOneTenSecondTrialWithoutInstructionsOrHardware(testCase)
global COPS_RECEX_TEST
ex=invoke(testCase);
a=COPS_RECEX_TEST.args; c=a.recording;
verifyEqual(testCase,COPS_RECEX_TEST.profile,'mouse_mini');
verifyEqual(testCase,a.testTrials,1);
verifyFalse(testCase,a.instrOn);
verifyTrue(testCase,a.showCursor);
verifyFalse(testCase,a.soundOn);
verifyEqual(testCase,a.syncMode,'off');
verifyFalse(testCase,a.overlayOn);
verifyEqual(testCase,[c.length c.targetNum c.visibility c.background],[10 2 1 -1]);
verifyTrue(testCase,c.mouseVisible);
verifyTrue(testCase,c.displayReward);
verifyTrue(testCase,c.rewardMarker);
verifyEqual(testCase,c.rewardLandscape,0);
verifyEqual(testCase,c.rewardMarkerDuration,0.2);
verifyEqual(testCase,c.fps,30);
verifyEqual(testCase,c.title,"");
verifyEqual(testCase,ex.MovieFiles,{'test.mp4'});
end

function testNamedLengthAndPositionalTitleWithCustomControls(testCase)
global COPS_RECEX_TEST
invoke(testCase,length=8,targetNum=1,visibility=0.4,background=1,mouseVisible=false,nTrials=3);
c=COPS_RECEX_TEST.args.recording;
verifyEqual(testCase,[c.length c.targetNum c.visibility c.background c.nTrials],[8 1 0.4 1 3]);
verifyFalse(testCase,COPS_RECEX_TEST.args.showCursor);
invoke(testCase,"Tracking demo",length=2.5,fps=60,movieSizePx=[1920 1080]);
c=COPS_RECEX_TEST.args.recording;
verifyEqual(testCase,[c.length c.fps],[2.5 60]);
verifyEqual(testCase,c.movieSizePx,[1920 1080]);
verifyEqual(testCase,c.title,"Tracking demo");
invoke(testCase,'length',5);
verifyEqual(testCase,COPS_RECEX_TEST.args.recording.length,5);
verifyEqual(testCase,COPS_RECEX_TEST.args.recording.title,"");
invoke(testCase,"length",length=3);
verifyEqual(testCase,COPS_RECEX_TEST.args.recording.title,"length");
end

function testEmptyTitlesUseAutomaticNamesAndCustomTitlesStayInOneFile(testCase)
global COPS_RECEX_TEST
for title={"",'',[],"   "}
    invoke(testCase,title{1},length=5);
    verifyEqual(testCase,COPS_RECEX_TEST.args.recording.title,"");
end
invoke(testCase,"  Tracking/demo: 1.mp4  ");
verifyEqual(testCase,COPS_RECEX_TEST.args.recording.title,"Tracking_demo_ 1");
end

function testGeneratedStimulusDirectoryIsForwardedToRunEx(testCase)
global COPS_RECEX_TEST
folder=string(testCase.TestData.folder);
invoke(testCase,stimulusDir=folder);
verifyEqual(testCase,COPS_RECEX_TEST.args.stimulusDir,folder);
verifyEqual(testCase,COPS_RECEX_TEST.args.recording.stimulusDir,folder);
end

function testInvalidInputsFailBeforeStartingTask(testCase)
verifyError(testCase,@() invoke(testCase,8),'recEx:Title');
verifyError(testCase,@() invoke(testCase,length=0),'MATLAB:validators:mustBePositive');
verifyError(testCase,@() invoke(testCase,targetNum=3),'MATLAB:validators:mustBeMember');
verifyError(testCase,@() invoke(testCase,movieSizePx=[1279 720]),'recEx:MovieSize');
verifyError(testCase,@() invoke(testCase,rewardMarkerDuration=0),'MATLAB:validators:mustBePositive');
for value=[-1 1.5 5 NaN Inf]
    verifyError(testCase,@() invoke(testCase,rewardLandscape=value),'MATLAB:validators:mustBeMember');
end
end

function testRewardAudioDoesNotRequireLiveAudioCapture(testCase)
global COPS_RECEX_TEST
invoke(testCase,displayReward=true,mouseVisible=true,rewardMarker=false);
verifyTrue(testCase,COPS_RECEX_TEST.args.recording.displayReward);
verifyTrue(testCase,COPS_RECEX_TEST.args.showCursor);
verifyFalse(testCase,COPS_RECEX_TEST.args.soundOn);
verifyFalse(testCase,COPS_RECEX_TEST.args.recording.rewardMarker);
end

function testVisualRewardMarkerCanBeEnabledIndependently(testCase)
global COPS_RECEX_TEST
invoke(testCase,rewardMarker=true,rewardMarkerDuration=0.3,displayReward=false);
c=COPS_RECEX_TEST.args.recording;
verifyTrue(testCase,c.rewardMarker);
verifyEqual(testCase,c.rewardMarkerDuration,0.3);
verifyFalse(testCase,c.displayReward);
end

function testMouseAndRewardCuesCanAllBeDisabled(testCase)
global COPS_RECEX_TEST
invoke(testCase,mouseVisible=false,displayReward=false,rewardMarker=false);
a=COPS_RECEX_TEST.args;
verifyFalse(testCase,a.showCursor);
verifyFalse(testCase,a.recording.mouseVisible);
verifyFalse(testCase,a.recording.displayReward);
verifyFalse(testCase,a.recording.rewardMarker);
end

function testDefaultLandscapeHasNoSpatialRewardVariation(testCase)
global COPS_RECEX_TEST
invoke(testCase);
evalc('ex=setDefaultsCoPs(struct());');
ex.exp.CoPs.ctl.gauss_scalar=4;
ex=configureCoPsRecordingx(ex,COPS_RECEX_TEST.args.recording);
verifyEqual(testCase,ex.exp.CoPs.ctl.gauss_scalar,1);
verifyFalse(testCase,ex.exp.CoPs.rew.gauss_center_free);
[~,center,px]=selectGaussRewardCenterCoPsx(ex.exp.CoPs.rew,101,0);
verifyEqual(testCase,center,[0.5 0.5]);
multiplier=gauss_rew_land(101,px,8)*(ex.exp.CoPs.ctl.gauss_scalar-1)+1;
verifyEqual(testCase,multiplier,ones(101));
end

function testEveryCornerProducesTheRequestedGaussianPeak(testCase)
global COPS_RECEX_TEST
evalc('base=setDefaultsCoPs(struct());');
centers=[0.25 0.25;0.75 0.25;0.25 0.75;0.75 0.75];
for corner=1:4
    invoke(testCase,rewardLandscape=corner);
    ex=configureCoPsRecordingx(base,COPS_RECEX_TEST.args.recording);
    rew=ex.exp.CoPs.rew;
    verifyEqual(testCase,ex.setup.recording.rewardLandscape,corner);
    verifyFalse(testCase,rew.gauss_center_free);
    verifyEqual(testCase,rew.gauss_center_mode,'manual');
    verifyEqual(testCase,rew.gauss_center_coords,centers(corner,:));
    [~,center,px]=selectGaussRewardCenterCoPsx(rew,101,0);
    verifyEqual(testCase,center,centers(corner,:));
    multiplier=gauss_rew_land(101,px,8)*(ex.exp.CoPs.ctl.gauss_scalar-1)+1;
    [peak,index]=max(multiplier(:)); [y,x]=ind2sub(size(multiplier),index);
    verifyEqual(testCase,[x y],px);
    verifyEqual(testCase,peak,base.exp.CoPs.ctl.gauss_scalar);
    verifyGreaterThan(testCase,peak,multiplier(102-px(2),102-px(1)));
end
end

function testNullBackgroundVisibilityAndTargetCountOverrides(testCase)
global COPS_RECEX_TEST
invoke(testCase,length=2,targetNum=1,visibility=0.35,background=-1);
evalc('ex=setDefaultsCoPs(struct());');
ex.exp.nreps=1; ex.finish=1;
ex.exp.CoPs.pre.nreps=0; ex.exp.CoPs.tut.nreps=0; ex.exp.CoPs.pur.nreps=0;
ex=configureCoPsRecordingx(ex,COPS_RECEX_TEST.args.recording);
ex=prepareCoPsTrialParamSchedules(ex);
verifyEqual(testCase,ex.exp.CoPs.ctl.nsteps,60);
verifyEqual(testCase,ex.exp.CoPs.ctl.target_numNULL,1);
verifyEqual(testCase,ex.exp.CoPs.graph.targetVisibilityNull,0.35);
verifyEqual(testCase,ex.exp.CoPs.trialParamSchedules.background_noise_lvl,-1);
verifyEqual(testCase,ex.exp.CoPs.trialParamSchedules.target_visibility,0.35);
verifyEqual(testCase,ex.exp.CoPs.trialParamSchedules.target_num,1);
verifyFalse(testCase,ex.exp.CoPs.instrOn);
verifyFalse(testCase,ex.exp.CoPs.ctl.advance_trial_with_space);
end

function testOutputDirectoryResolvesAbsolutePathWithoutSessionSubfolder(testCase)
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
ex.Header=struct('onlineFileName','demo_session.mat','onlineDirName',testCase.TestData.folder);
ex.setup.recording.outputDir="my_movies";
ex=prepareCoPsMovieOutputx(ex);
verifyEqual(testCase,ex.setup.recording.outputDirectory, ...
    fullfile(testCase.TestData.folder,'my_movies'));
end

function ex=invoke(testCase,varargin)
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
clear runEx
ex=recEx(varargin{:});
end
