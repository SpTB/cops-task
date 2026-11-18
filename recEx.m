function ex = recEx(varargin)
% Export presentation movies using the mouse_mini stimulus preview.
%   ex = recEx();
%   ex = recEx(length=5, targetNum=2, visibility=1, background=-1, mouseVisible=true);
%   ex = recEx(8, background=1, visibility=0.6, mouseVisible=false);
% rewardLandscape: 0=flat (default), 1=top-left, 2=top-right,
% 3=bottom-left, 4=bottom-right, using the configured corner peak positions.
% Optional displayReward=true embeds point-crossing beeps in each MP4.
% Optional rewardMarker=true flashes a green border around the stimulus.
% ex.MovieFiles contains absolute output paths.
if ~isempty(varargin) && isnumeric(varargin{1})
    varargin = [{'length',varargin{1}},varargin(2:end)];
end
ex = recordWithOptionsLocal(varargin{:});
end

function ex = recordWithOptionsLocal(options)
arguments
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
    options.filePrefix (1,1) string = "demo"
end
if any(mod(options.movieSizePx,2))
    error('recEx:MovieSize','MP4 width and height must be even numbers.');
end
ex = runEx('mouse_mini',testTrials=options.nTrials,instrOn=false, ...
    showCursor=options.mouseVisible,soundOn=false,syncMode='off',overlayOn=false, ...
    windowSizePx=options.windowSizePx,filePrefix=options.filePrefix,recording=options);
if isfield(ex,'lastError') && ~isempty(ex.lastError)
    rethrow(ex.lastError);
end
end
