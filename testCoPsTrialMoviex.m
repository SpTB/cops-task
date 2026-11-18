function tests = testCoPsTrialMoviex
tests=functiontests(localfunctions);
end

function setupOnce(testCase)
folder=tempname; mkdir(folder);
testCase.TestData.folder=folder; testCase.TestData.originalPath=path;
fid=fopen(fullfile(folder,'Screen.m'),'w');
fprintf(fid,'%s\n',[
    "function varargout=Screen(command,varargin)"
    "global COPS_MOVIE_TEST"
    "s=COPS_MOVIE_TEST; s.calls{end+1}=[{command} varargin];"
    "switch lower(command)"
    "case 'rect', varargout={[0 0 1080 1080]};"
    "case 'openoffscreenwindow', varargout={701};"
    "case 'createmovie'"
    "    if s.failCreate, error('MovieTest:Create','Simulated encoder failure.'); end"
    "    file=varargin{2}; if file(1)==char(34), file=file(2:end-1); end"
    "    fid=fopen(file,'w'); fwrite(fid,uint8('mockmovie')); fclose(fid); varargout={501};"
    "case 'addframetomovie'"
    "    s.nFrames=s.nFrames+1;"
    "    COPS_MOVIE_TEST=s;"
    "    if s.nFrames==s.failFrame, error('MovieTest:Frame','Simulated frame failure.'); end"
    "case 'addaudiobuffertomovie', s.audio=varargin{2};"
    "case {'finalizemovie','fillrect','framerect','drawtexture','fillpoly','close'}"
    "otherwise, error('MovieTest:Screen','Unexpected Screen call.');"
    "end"
    "COPS_MOVIE_TEST=s;"
    "end"]);
fclose(fid);
addpath(fileparts(mfilename('fullpath')),folder,'-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath); clear Screen
folder=testCase.TestData.folder;
assert(strcmp(fileparts(folder),fileparts(tempname)));
rmdir(folder,'s'); clear global COPS_MOVIE_TEST
end

function setup(~)
global COPS_MOVIE_TEST
COPS_MOVIE_TEST=struct('calls',{{}},'nFrames',0,'failCreate',false,'failFrame',-1,'audio',[]);
end

function testDefaultMovieIsExactlyFiveSecondsAndIncludesMouse(testCase)
global COPS_MOVIE_TEST
[ex,scene,textures]=fixture(testCase);
info=exportMovie(testCase,ex,textures,scene);
verifyEqual(testCase,[info.frameCount info.durationSec info.fps],[150 5 30]);
verifyEqual(testCase,info.sourceSteps,1:150);
verifyEqual(testCase,info.mouseDrawnFrames,150);
verifyTrue(testCase,isfile(info.file));
verifyEqual(testCase,COPS_MOVIE_TEST.nFrames,150);
creates=calls('CreateMovie');
verifyEqual(testCase,creates{1}{2},ex.setup.window); % encoder owner must be onscreen
verifySubstring(testCase,creates{1}{7},'profile=main'); % widely supported 4:2:0 H.264
verifySubstring(testCase,creates{1}{7},'format=I420');
verifyEqual(testCase,numel(calls('FinalizeMovie')),1);
verifyEqual(testCase,numel(calls('Close')),1);
draws=calls('DrawTexture');
verifyEqual(testCase,draws{1}{5},[280 0 1000 720],'AbsTol',1e-10);
cursors=calls('FillPoly');
verifyEqual(testCase,cursors{1}{4}(1,:),[640 360],'AbsTol',1e-10);
verifyEmpty(testCase,calls('AddAudioBufferToMovie'));
end

function testRewardCrossingsBecomeBeepEventsInMovieAudio(testCase)
global COPS_MOVIE_TEST
[ex,scene,textures]=fixture(testCase);
ex.setup.recording.displayReward=true;
ex.Trials.times.reward=[NaN 50.5 51.75 60];
info=exportMovie(testCase,ex,textures,scene);
verifyEqual(testCase,info.rewardBeepCount,2);
verifyEqual(testCase,info.rewardTimes,[0.5 1.75],'AbsTol',1e-12);
verifyEqual(testCase,info.audioSampleRate,48000);
verifySize(testCase,COPS_MOVIE_TEST.audio,[2 240000]);
tone=makeCoPsRewardBeepx(48000);
verifyEqual(testCase,COPS_MOVIE_TEST.audio(:,24001:25440),tone,'AbsTol',1e-12);
verifyEqual(testCase,COPS_MOVIE_TEST.audio(:,1:20000),zeros(2,20000));
creates=calls('CreateMovie');
verifySubstring(testCase,creates{1}{7},'name=ptbaudioappsrc');
verifySubstring(testCase,creates{1}{7},'avenc_aac');
verifyNumElements(testCase,calls('AddAudioBufferToMovie'),1);
end

function testRewardBeepTracksStimulusStepWhenPreviewHasTimingDelays(testCase)
[ex,scene,textures]=fixture(testCase);
ex.setup.recording.displayReward=true;
% Two seconds of actual display time correspond to one second of exported steps.
ex.Trials.flip_info(:,1)=50+(0:149)'/15;
ex.Trials.syncOffTime=60;
ex.Trials.times.reward=52;
ex.Trials.mousePositions=[960 540 50;1100 600 52;1100 600 60];
info=exportMovie(testCase,ex,textures,scene);
verifyEqual(testCase,info.rewardTimes,1,'AbsTol',1e-12);
verifyEqual(testCase,info.mousePositions(31,:),[1100 600]);
verifyEqual(testCase,info.durationSec,5);
end

function testEnabledRewardTrackIsSilentWithoutCrossings(testCase)
global COPS_MOVIE_TEST
[ex,scene,textures]=fixture(testCase);
ex.setup.recording.displayReward=true; ex.Trials.times.reward=NaN;
info=exportMovie(testCase,ex,textures,scene);
verifyEqual(testCase,info.rewardBeepCount,0);
verifyFalse(testCase,any(COPS_MOVIE_TEST.audio(:)));
end

function testRewardTrackRequiresActualEventsInsteadOfFractionalPoints(testCase)
[ex,scene,textures]=fixture(testCase); ex.setup.recording.displayReward=true;
ex.Trials.pointsEarned=99.9;
verifyError(testCase,@() exportMovie(testCase,ex,textures,scene),'recEx:RewardEvents');
end

function testMarkerOutlinesStimulusSquareAtCrossingsWithoutAudio(testCase)
[ex,scene,textures]=fixture(testCase);
ex.setup.recording.rewardMarker=true;
ex.Trials.times.reward=[NaN 50.5 52];
info=exportMovie(testCase,ex,textures,scene);
expected=false(150,1); expected([16:21 61:66])=true;
verifyEqual(testCase,info.rewardMarkerFrames,expected);
verifyEqual(testCase,info.rewardMarkerFrameCount,12);
verifyEqual(testCase,info.rewardTimes,[0.5 2],'AbsTol',1e-12);
borders=calls('FrameRect');
verifyNumElements(testCase,borders,12);
verifyEqual(testCase,borders{1}(2:end),{701,[0 255 0],[282 2 998 718],4});
verifyEmpty(testCase,calls('AddAudioBufferToMovie'));
end

function testMarkerDurationAndBeepUseSameRetimedCrossing(testCase)
[ex,scene,textures]=fixture(testCase);
ex.setup.recording.rewardMarker=true; ex.setup.recording.rewardMarkerDuration=0.1;
ex.setup.recording.displayReward=true;
ex.Trials.flip_info(:,1)=50+(0:149)'/15;
ex.Trials.syncOffTime=60; ex.Trials.times.reward=52;
info=exportMovie(testCase,ex,textures,scene);
verifyEqual(testCase,info.rewardTimes,1,'AbsTol',1e-12);
verifyEqual(testCase,info.rewardBeepCount,1);
verifyEqual(testCase,find(info.rewardMarkerFrames),(31:33)');
end

function testMarkerDoesNotFlashWithoutCrossings(testCase)
[ex,scene,textures]=fixture(testCase);
ex.setup.recording.rewardMarker=true; ex.Trials.times.reward=NaN;
info=exportMovie(testCase,ex,textures,scene);
verifyEqual(testCase,info.rewardMarkerFrameCount,0);
verifyEmpty(testCase,calls('FrameRect'));
end

function testHigherFrameRateRepeatsStepsWithoutChangingDuration(testCase)
[ex,scene,textures]=fixture(testCase); ex.setup.recording.fps=60;
info=exportMovie(testCase,ex,textures,scene);
verifyEqual(testCase,[info.frameCount info.durationSec],[300 5]);
verifyEqual(testCase,info.sourceSteps,repelem(1:150,2));
end

function testMouseVisibilityCanBeDisabled(testCase)
[ex,scene,textures]=fixture(testCase); ex.setup.recording.mouseVisible=false;
info=exportMovie(testCase,ex,textures,scene);
verifyEqual(testCase,info.mouseDrawnFrames,0);
verifyEmpty(testCase,calls('FillPoly'));
end

function testMouseMovesAndLeavesWindowInRecordedPath(testCase)
[ex,scene,textures]=fixture(testCase);
ex.Trials.mousePositions=[960 540 50;1100 600 51;NaN NaN 52;960 540 54];
info=exportMovie(testCase,ex,textures,scene);
verifyEqual(testCase,info.mousePositions(1,:),[960 540]);
verifyEqual(testCase,info.mousePositions(31,:),[1100 600]);
verifyTrue(testCase,all(isnan(info.mousePositions(61,:))));
verifyEqual(testCase,info.mouseDrawnFrames,90);
end

function testAbortExportsOnlyTheStimulusStepsReached(testCase)
[ex,scene,textures]=fixture(testCase);
ex.Trials.trialCompleted=false;
ex.Trials.frameStep=(1:60)'; ex.Trials.frameState=6*ones(60,1);
ex.Trials.flip_info=[50+(0:59)'/30 zeros(60,3)];
info=exportMovie(testCase,ex,textures,scene);
verifyEqual(testCase,[info.frameCount info.durationSec],[60 2]);
verifyFalse(testCase,info.completed);
verifyEqual(testCase,info.sourceSteps,1:60);
end

function testNoMovieBeforeStimulusOrForEmptyTextures(testCase)
[ex,scene,textures]=fixture(testCase); ex.Trials.frameState(:)=0;
info=exportMovie(testCase,ex,textures,scene);
verifyEqual(testCase,info.status,'noStimulus');
verifyEmpty(testCase,calls('CreateMovie'));
end

function testExportDoesNotOverwriteAnExistingMovie(testCase)
[ex,scene,textures]=fixture(testCase);
first=exportMovie(testCase,ex,textures,scene);
second=exportMovie(testCase,ex,textures,scene);
verifyNotEqual(testCase,first.file,second.file);
verifyTrue(testCase,isfile(first.file)); verifyTrue(testCase,isfile(second.file));
end

function testEncoderAndCanvasCloseWhenFrameWritingFails(testCase)
global COPS_MOVIE_TEST
[ex,scene,textures]=fixture(testCase); COPS_MOVIE_TEST.failFrame=3;
verifyError(testCase,@() exportMovie(testCase,ex,textures,scene),'MovieTest:Frame');
verifyNumElements(testCase,calls('FinalizeMovie'),1);
verifyNumElements(testCase,calls('Close'),1);
end

function testMoviePathsWithSpacesAreQuotedForGStreamer(testCase)
[ex,scene,textures]=fixture(testCase);
ex.setup.recording.outputDirectory=fullfile(testCase.TestData.folder,'directory with spaces');
mkdir(ex.setup.recording.outputDirectory);
info=exportMovie(testCase,ex,textures,scene);
verifyTrue(testCase,isfile(info.file));
creates=calls('CreateMovie'); path=creates{1}{3};
verifyEqual(testCase,path([1 end]),'""');
verifySubstring(testCase,path,'directory with spaces');
if ispc, verifyFalse(testCase,contains(path,'\')); end
end

function testCanvasClosesWhenEncoderCannotOpen(testCase)
global COPS_MOVIE_TEST
[ex,scene,textures]=fixture(testCase); COPS_MOVIE_TEST.failCreate=true;
verifyError(testCase,@() exportMovie(testCase,ex,textures,scene),'recEx:Encoder');
verifyEmpty(testCase,calls('FinalizeMovie'));
verifyNumElements(testCase,calls('Close'),1);
end

function result=calls(command)
global COPS_MOVIE_TEST
result=COPS_MOVIE_TEST.calls(cellfun(@(c) strcmpi(c{1},command),COPS_MOVIE_TEST.calls));
end

function info=exportMovie(testCase,ex,textures,scene)
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
clear Screen
info=exportCoPsTrialMoviex(ex,textures,scene);
end

function [ex,scene,textures]=fixture(testCase)
ex=struct('j',1,'states',struct('GO',6));
ex.setup=struct('window',7,'screenRect',[0 0 1920 1080]);
ex.setup.recording=struct('fps',30,'length',5,'movieSizePx',[1280 720], ...
    'mouseVisible',true,'outputDirectory',testCase.TestData.folder);
ex.Trials=struct('trialCompleted',true,'waitSecs',1/30, ...
    'frameState',6*ones(150,1),'frameStep',(1:150)', ...
    'flip_info',[50+(0:149)'/30 zeros(150,3)], ...
    'mousePositions',[960 540 50;960 540 55]);
textures=1001:1150;
scene=struct('windowColor',0,'textureColor',128,'textureRect',[420 0 1500 1080], ...
    'textureDestinationRect',[420 0 1500 1080]);
end
