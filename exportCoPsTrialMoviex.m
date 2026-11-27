function info = exportCoPsTrialMoviex(ex,textures,scene)
% Encode the generated stimulus sequence after the live trial, offscreen.
% This is a presentation export, not a reconstruction of display frame drops.
cfg = ex.setup.recording;
t = ex.Trials(ex.j);
displayReward = isfield(cfg,'displayReward') && cfg.displayReward;
rewardMarker = isfield(cfg,'rewardMarker') && cfg.rewardMarker;
markerDuration = 0.2;
if isfield(cfg,'rewardMarkerDuration'), markerDuration = cfg.rewardMarkerDuration; end
active = t.frameState == ex.states.GO & isfinite(t.frameStep) & isfinite(t.flip_info(:,1));
info = struct('status','noStimulus','file','','fps',cfg.fps,'frameCount',0, ...
    'durationSec',0,'requestedLengthSec',cfg.length,'sizePx',cfg.movieSizePx, ...
    'mouseVisible',cfg.mouseVisible,'mouseDrawnFrames',0,'completed',logical(t.trialCompleted), ...
    'displayReward',displayReward,'rewardTimes',[],'rewardBeepCount',0,'audioSampleRate',0, ...
    'rewardMarker',rewardMarker,'rewardMarkerDuration',markerDuration, ...
    'rewardMarkerFrames',false(0,1),'rewardMarkerFrameCount',0);
if ~any(active) || isempty(textures), return; end
startTime = t.flip_info(find(active,1),1);
lastStep = numel(textures);
duration = cfg.length;
if ~t.trialCompleted
    lastStep = min(lastStep,max(t.frameStep(active)));
    duration = min(duration,lastStep*t.waitSecs);
end
nFrames = max(1,round(duration*cfg.fps));
steps = min(lastStep,1+floor((0:nFrames-1)/(cfg.fps*t.waitSecs)));
movieTimes = (0:nFrames-1)'/cfg.fps;
[actualAnchors,nominalAnchors] = timelineLocal(t,active,lastStep);
times = interp1(nominalAnchors,actualAnchors,movieTimes,'linear','extrap');
mouse = sampleMouseLocal(t,times);
audio = [];
if displayReward || rewardMarker
    if ~isfield(t,'times') || ~isstruct(t.times) || ~isfield(t.times,'reward')
        error('recEx:RewardEvents','Reward cues require the trial reward-crossing timestamps.');
    end
    rewardTimes = interp1(actualAnchors,nominalAnchors,t.times.reward,'linear','extrap');
    info.rewardTimes = reshape(rewardTimes(isfinite(rewardTimes) & rewardTimes>=0 & rewardTimes<nFrames/cfg.fps),1,[]);
end
if displayReward
    info.audioSampleRate = 48000;
    [audio,info.rewardTimes] = makeCoPsMovieRewardAudiox(info.rewardTimes,nFrames/cfg.fps,info.audioSampleRate);
    info.rewardBeepCount = numel(info.rewardTimes);
end
markerFrames = false(nFrames,1);
if rewardMarker
    markerFrames = any(movieTimes>=info.rewardTimes & movieTimes<info.rewardTimes+markerDuration,2);
end
info.rewardMarkerFrames = markerFrames;
info.rewardMarkerFrameCount = nnz(markerFrames);
directory = cfg.outputDirectory;
stem = movieTitleLocal(cfg,t);
if cfg.nTrials > 1, stem = sprintf('%s_trial_%03d',stem,ex.j); end
file = fullfile(directory,[stem '.mp4']);
suffix = 2;
while isfile(file)
    file = fullfile(directory,sprintf('%s_%02d.mp4',stem,suffix));
    suffix = suffix+1;
end
logicalRect = ex.setup.screenRect;
logicalSize = logicalRect(3:4)-logicalRect(1:2);
scale = min(cfg.movieSizePx./logicalSize);
offset = (cfg.movieSizePx-scale*logicalSize)/2;
destination = scene.textureDestinationRect;
if isempty(destination)
    r = Screen('Rect',textures(1));
    sizePx = r(3:4)-r(1:2);
    origin = logicalRect(1:2)+(logicalSize-sizePx)/2;
    destination = [origin origin+sizePx];
end
canvas = Screen('OpenOffscreenWindow',ex.setup.window,0,[0 0 cfg.movieSizePx]);
canvasCleanup = onCleanup(@() closeCanvasLocal(canvas)); %#ok<NASGU>
% PTB requires an onscreen owner for CreateMovie, even when AddFrameToMovie
% reads the independently sized offscreen canvas.
writer = CoPsMovieWriterx(ex.setup.window,file,cfg.movieSizePx,cfg.fps,info.audioSampleRate);
writerCleanup = onCleanup(@() delete(writer)); %#ok<NASGU>
if displayReward, writer.addAudio(audio); end
fprintf('Encoding trial %d: %d frames at %g fps...\n',ex.j,nFrames,cfg.fps);
for k=1:nFrames
    Screen('FillRect',canvas,0);
    Screen('FillRect',canvas,scene.windowColor,mapRectLocal(logicalRect,logicalRect,scale,offset));
    Screen('FillRect',canvas,scene.textureColor,mapRectLocal(scene.textureRect,logicalRect,scale,offset));
    Screen('DrawTexture',canvas,textures(steps(k)),[],mapRectLocal(destination,logicalRect,scale,offset));
    if markerFrames(k)
        drawCoPsRewardMarkerx(canvas,mapRectLocal(scene.textureRect,logicalRect,scale,offset));
    end
    xy = mouse(k,:);
    if cfg.mouseVisible && all(isfinite(xy)) && all(xy >= logicalRect(1:2)) && all(xy < logicalRect(3:4))
        point = offset+scale*(xy-logicalRect(1:2));
        drawCursorLocal(canvas,point,max(0.5,cfg.movieSizePx(1)/1280));
        info.mouseDrawnFrames = info.mouseDrawnFrames+1;
    end
    writer.addFrame(canvas);
end
writer.finish();
written = dir(file);
if isempty(written) || written.bytes == 0
    error('recEx:MovieMissing','The encoder did not create a nonempty movie at %s.',file);
end
info.status = 'saved';
info.file = file;
info.frameCount = nFrames;
info.durationSec = nFrames/cfg.fps;
info.sourceSteps = steps;
info.firstStimulusTime = startTime;
info.mousePositions = mouse;
info.sourceSampleTimes = times;
end

function title = movieTitleLocal(cfg,t)
if isfield(cfg,'title') && strlength(cfg.title) > 0
    title = char(cfg.title);
    return;
end
switch t.background_noise_lvl
    case -1, background = 'null';
    case 0, background = 'fixed';
    otherwise, background = sprintf('%g',t.background_noise_lvl);
end
landscapes = {'flat','top-left','top-right','bottom-left','bottom-right'};
title = sprintf('targets-%d_bg-%s_coh-%g_vis-%g_landscape-%s', ...
    t.target_num,background,t.coherence,t.target_visibility,landscapes{cfg.rewardLandscape+1});
end

function [actual,nominal] = timelineLocal(t,active,lastStep)
rows = find(active);
[steps,first] = unique(t.frameStep(rows),'first');
actual = t.flip_info(rows(first),1);
nominal = (steps-1)*t.waitSecs;
[actual,keep] = unique(actual,'last');
nominal = nominal(keep);
stopTime = actual(end)+t.waitSecs;
if isfield(t,'syncOffTime') && isscalar(t.syncOffTime) && isfinite(t.syncOffTime) && t.syncOffTime>actual(end)
    stopTime = t.syncOffTime;
end
actual = [actual;stopTime];
nominal = [nominal;lastStep*t.waitSecs];
end

function positions = sampleMouseLocal(t,times)
positions = NaN(numel(times),2);
if ~isfield(t,'mousePositions') || isempty(t.mousePositions), return; end
m = t.mousePositions;
m = m(isfinite(m(:,3)),1:3); % preserve gaps when the mouse leaves the task window
if isempty(m), return; end
[sampleTimes,indices] = unique(m(:,3),'last');
if numel(indices)==1
    positions = repmat(m(indices,1:2),numel(times),1);
else
    positions = interp1(sampleTimes,m(indices,1:2),times,'previous','extrap');
end
end

function result = mapRectLocal(r,logicalRect,scale,offset)
result = (r-logicalRect([1 2 1 2]))*scale+offset([1 2 1 2]);
end

function drawCursorLocal(canvas,point,scale)
arrow = [0 0;0 27;6 21;11 32;17 29;11 18;23 18];
Screen('FillPoly',canvas,0,arrow*scale+point);
Screen('FillPoly',canvas,255,(arrow*0.8+[1.5 2])*scale+point);
end

function closeCanvasLocal(canvas)
try
    Screen('Close',canvas);
catch
end
end
