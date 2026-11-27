function ex = recEx(varargin)
% Export presentation movies using the mouse_mini stimulus preview.
%   ex = recEx();
%   ex = recEx("Tracking demo", length=5);
%   ex = recEx(length=5, targetNum=2, visibility=1, background=-1, mouseVisible=true);
%   ex = recEx("", length=8, background=1, visibility=0.6, mouseVisible=false);
%   ex = recEx(stimulusDir="stimuli/my_session");
% rewardLandscape: 0=flat (default), 1=top-left, 2=top-right,
% 3=bottom-left, 4=bottom-right, using the configured corner peak positions.
% Optional displayReward=true embeds point-crossing beeps in each MP4.
% Optional rewardMarker=true flashes a green border around the stimulus.
% Movies default to <repo>/demo/movies/, without session subfolders.
% An omitted/empty title names the movie from its trial parameters.
% ex.MovieFiles contains absolute output paths.
title = "";
% Name-value pairs have even length; an extra first argument is the title.
if mod(numel(varargin),2) == 1
    title = varargin{1};
    varargin = varargin(2:end);
end
if isempty(title), title = ""; end
if ~((isstring(title) && isscalar(title) && ~ismissing(title)) || ...
        (ischar(title) && isrow(title)))
    error('recEx:Title','The first argument must be a title string or empty. Use length= for duration.');
end
ex = recordWithOptionsLocal(string(title),varargin{:});
end

function ex = recordWithOptionsLocal(title,options)
arguments
    title (1,1) string
    options.length (1,1) double {mustBePositive,mustBeFinite} = 10
    options.targetNum (1,1) double {mustBeMember(options.targetNum,[1 2])} = 2
    options.visibility (1,1) double {mustBeFinite,mustBeGreaterThanOrEqual(options.visibility,0),mustBeLessThanOrEqual(options.visibility,1)} = 1
    options.background (1,1) double {mustBeInteger,mustBeFinite,mustBeGreaterThanOrEqual(options.background,-1)} = -1
    options.rewardLandscape (1,1) double {mustBeMember(options.rewardLandscape,0:4)} = 0
    options.mouseVisible (1,1) logical = true
    options.displayReward (1,1) logical = true
    options.rewardMarker (1,1) logical = true
    options.rewardMarkerDuration (1,1) double {mustBePositive,mustBeFinite} = 0.2
    options.nTrials (1,1) double {mustBeInteger,mustBePositive} = 1
    options.fps (1,1) double {mustBeInteger,mustBePositive,mustBeLessThanOrEqual(options.fps,240)} = 30
    options.movieSizePx (1,2) double {mustBeInteger,mustBePositive} = [1280 720]
    options.windowSizePx (1,2) double {mustBeInteger,mustBePositive} = [960 540]
    options.outputDir (1,1) string = ""
    options.stimulusDir (1,1) string = ""
    options.filePrefix (1,1) string = "demo"
end
if any(mod(options.movieSizePx,2))
    error('recEx:MovieSize','MP4 width and height must be even numbers.');
end
title = regexprep(strtrim(title),'(?i)\.mp4$','');
% Keep a title in one filename component while preserving readable spaces.
title = regexprep(title,'[<>:"/\\|?*\x00-\x1F\x7F]','_');
options.title = regexprep(title,'[. ]+$','');
ex = runEx('mouse_mini',testTrials=options.nTrials,instrOn=false, ...
    showCursor=options.mouseVisible,soundOn=false,syncMode='off',overlayOn=false, ...
    stimulusDir=options.stimulusDir, ...
    windowSizePx=options.windowSizePx,filePrefix=options.filePrefix,recording=options);
if isfield(ex,'lastError') && ~isempty(ex.lastError)
    rethrow(ex.lastError);
end
end
