function ex = setDefaultsCoPs(ex)

% rewSwitches: block lengths and reward centers are generated at session
% start. Set jointBlocks=false to use the fixed-center task and exp.nreps.
ctl.jointBlocks = true;
ctl.numBlocks = 12;
ctl.blockMeanTrials = 30;
ctl.blockTransRange = 6; % integer uniform range: blockMeanTrials +/- this value
ctl.rewPeakDistFromPrev = 5; % minimum consecutive-peak distance in visual degrees

% do a intro minisession for Kaki: 5 pur; 10 normal (lo thresh) 5 Null (lo thresh) 

%drawRewPeak(6,10)

%main params
graph.texture_root = '/home/vpixx/stim';%;
%'/run/user/1000/gvfs/smb-share:server=lsr-isilon.nei.nih.gov,share=lsr-nienborg/data/CoPs'
graph.texture_folder = 'jul11_stim2';% -> /home/vpixx/stim/ly_jun5_stim

pre.nreps = 0; % numeric = total pre trials; 'all' = one trial per selected texture
pur.nreps = 0;
ex.exp.nreps = 120; % replaced by total block lengths when jointBlocks=true

%pur specific
pur.threshold = 250;
pur.speed = 12; % deg/sec
pur.size = .25; % radius in deg
pur.lenSec = 10; % fixed pursuit-trial duration
pur.priority = true; % true: run pursuit block before main trials

%thresholding
rew.threshold = 250; % kaki: 250->260bler; Lychee: 250 (at waitHz=20/30)
rew.threshold_noiseNull=325;%kaki: 300; Lychee: 325
rew.threshold_noise0 = 250;%kaki:300; Lychee: 350 % threshold for fixed-background (noise=0) trials
%0.8402, 0.5661
rew.gauss_center_free = true; % true: sample free [x y] center within current center radius
rew.gauss_center_coords = []; % resolved [x y] normalized coords when gauss_center_free=true
ctr.max_peak_dist_deg = 10; % max reward-peak eccentricity from image center, in visual degrees (8.77: where the original ones were)
ctl.gauss_scalar = 2.25; % [1,max], ly:2.25; ka: 2.25 valid for multiplicative rewards

graph.background_noise_lvl = [-1,1,1,1,1,1];
graph.target_mask_sigma_mult = 1; % multiplier on default Gaussian mask sigma (= graph.radius/3)
graph.target_mean_normalization = 'localBackgroundMean3SD'; % none/localBackgroundMean3SD
graph.target_mean_normalization_sd = 3; % region radius in Gaussian-mask SD units
graph.dynamic_background_normalization = 'compositeStats'; % none/backgroundStats/compositeStats/compositeRange
graph.normalize_dynamic_background = false; % legacy boolean: true => compositeRange if no mode is set

%step update pack
timing.waitHz = 30; % target update rate in Hz
ctl.step_size_mult = .4; %/2% 10hz: 1, 20hz: .6; 30Hz: .4
% 
% for controlling step size (.6 for 30Hz is roughly equal 1 for 10Hz in terms of area explored) General rule: dx_mult=sqrt(speed_mult)

timing.wait_secs = 1 / timing.waitHz; % derived legacy field for older analysis code
ctl.nsteps = 18*timing.waitHz;
%%%
graph.target_visibilityNull=1; %for no background
%graph.targetVisibilityNull = graph.target_visibilityNull;
graph.target_visibility0 =1;%[.2,.6, 1];%for fixed background linspace(.6, 1, 5);%[1,.8]; % [0,1] scales target/background blending without changing blend normalization
graph.target_visibility =[1,.9,.8,.7,.6];
graph.sequenceMode_vis = false; % true: target_visibility values are presented in listed order, cycling as needed

ctl.target_num = 2; % scalar or vector; e.g. [1 2 2 2] gives 25% single-target trials
ctl.target_numNULL = [1,2];
%kaki:    desert4, river3, ice2,river2(?)
% lychee: desert4, river3, sea1, river1,
% OUT: water1, desert1, desert3, ice1, ice3,river2
% KAKI OUT: sea1, river1
%new set: sand1? fog?(maybe too easy..) shore1?
graph.imgs = [];%{'desert4', 'sea1', 'river1', 'river3'}%, 'river1', 'river3','sea1'};%{'desert4', 'sea1', 'river1', 'river3'};%{'desert3','desert4','ice1','ice2','ice3','river1','river2','river3','sea1'};%['river1']; % empty = use all stimulus folders; otherwise restrict to named folders
graph.sequenceMode_im = 0; % true: graph.imgs are presented in listed order, cycling as needed
graph.balanceStimulusSchedule = true; % balance trials hierarchically by background, visibility, image, then rotation
graph.shuffleStimulusSchedule = true; % shuffle counterbalanced stimulus trials while preserving aligned factors
graph.texture_rotation_levels_deg = [0 90 180 270];

ex.exp.CoPs.freeViewing = 1; % whether fixation needed to start the trial

% CoPs specific parameters (required for runTrialTaskCoPs.m)
[dirs.all, graph.texture_folder] = resolveTextureFolderLocal(graph);
graph.texture_folder_resolved = dirs.all;

ctl.stepNoiseType = 'gaussian'; % 'uniform' (legacy) or 'normal'/'gaussian'
ctl.stepNoiseSigma = 0.07; % normalized-position units, used for Gaussian step noise
% 0.06 -> 0.2614 vis deg
ctl.stepNoiseCapSigma = 3.5; % clip Gaussian steps at +/- this many sigma
ctl.boundaryMode = 'reject'; % 'clip' legacy clamp, or 'reject' redraw out-of-bounds steps
ctl.boundaryRejectMaxAttempts = 50;
ctl.targetHiddenBoundsFrac = 0.2; % 0 disables; 0.2 allows up to 20% of target diameter outside visible texture
ctl.randomize_start_pos = 1; % randomize initial target angle while preserving center distance
% dirs.test_folder = '/home/vpixx/test1_water_dep.jpg/';  % Will need to be set to actual stimulus folder
ctl.circle_target_loc = 0; % draws circles around targets during the trial
ctl.circle_target_loc_overlay = 1; %overlay only 
ctl.max_dist_mult = 2.5; % multiplier for calculating max distance (max_dist*r*size_mult)
ctl.independent_accumulation = false; % if true, each target has its own reward accumulator
ctl.coherence =1;%[.95,.65,.35];%linspace(.05,.95,19);%[.5,.7]; % target coherence; 1 uses full/, values <1 use mixXX/ folders

ctl.reward_type = 'mult' % 'add' or 'mult'
%ctl.precision_weight = 0.5; % [0,1] only valid for additive reward func...
%ctl.gauss_scalar = 5; % [1,max], valid for multiplicative reward

% fixation control
ctl.next_fixation_trial = 0; % one-shot flag (set by F3) to force next trial to center fixation
ctl.tolerance_scalar = 8; % for fixation area (to start trial) if NOT freeViewing
% 8: whole screen (almost)
%ex.exp.CoPs.freeViewing = 1; % whether fixation needed to start the trial

timing.prego_delay = 0.20; % shorten to shorten reward time
timing.go_delay = 0.05;


% ex.timing.waitstop;
% ex.timing.stimDuration;
% ex.timing.duration;
% ex.timing.freeduration;
% ex.fix.PCtr;
% ex.fix.Psz;


%graphical settings
graph.autoTextureDims = true; % infer square source image size from selected stimulus folder
graph.texture_dim=320;
graph.size_mult = 1080/graph.texture_dim;
graph.scaleTextureOnDraw = true; % keep source-sized textures; PTB scales them when drawing
graph.full_as_background = 0;
graph.texture_dims = [graph.texture_dim graph.texture_dim]; %in px
graph.radius = 15 * (graph.texture_dim/192); % legacy reference radius in texture px, at monitorWidth=38.5 cm

graph.radiusUnits = 'deg'; % 'deg' preserves the old visual angle; 'texturePx' uses graph.radius directly
graph.radiusReferenceMonitorWidth = 38.5; % cm, previous rig calibration
graph.radiusReferenceViewingDistance = 58; % cm
graph.radiusReferenceScreenWidthPx = 1920;
graph.radiusDeg = graph.radius * graph.size_mult * ...
    atan((graph.radiusReferenceMonitorWidth / 2) / graph.radiusReferenceViewingDistance) * ...
    180 / pi / (graph.radiusReferenceScreenWidthPx / 2); 
%graph.background_noise_lvl = 5; % how much does the background change from one step to the next

% reward parameters
rew.alwaysOnEyeInBounds = 0; % 'Lychee mode': reward as long as looking
%rew.threshold = 250.0; % kaki: 250 on fixed; 200 on regular
rew.accum_len_fp = 180; % number of frames relevant for reward accumulation. Currently set to 45, since 2 full time-steps =~ 48 (based on fi; will be larger when updating by ei!)
rew.duration = 0.25; % in seconds
rew.gauss_sigma = 3.5; % sd of the 2D reward landscape
rew.gauss_sigmaUnits = 'deg'; % runTrialTaskCoPsx resolves this to px for reward_mat
rew.gauss_sigmaDeg = rew.gauss_sigma;

% Gaussian reward center options (normalized in [0,1] of reward matrix):
% center + 4 quadrant centers (not edge corners). In free mode, the maximum
% distance from center is derived from these configured center positions.
rew.gauss_center_positions_norm = [ ...
    0.50, 0.50; ... % center (1)
    0.25, 0.25; ... % top-left quadrant (2)
    0.75, 0.25; ... % top-right quadrant (3)
    0.25, 0.75; ... % bottom-left quadrant (4)
    0.75, 0.75  ... % bottom-right quadrant (5)
    ];

rew.gauss_center_mode = 'manual'; % 'random' or 'manual'
rew.gauss_center_idx = 4; % used when mode='manual' and gauss_center_free=false (1=center by default)
rew.show_gauss_center_marker = 0; % draw marker at active Gaussian center on stimulus window
rew.show_gauss_center_marker_overlay = 1; % draw green + at active Gaussian center on experimenter overlay
rew.gauss_center_marker_psz = 10;

% Normalized coordinates (-1 to 1) where 0,0 = center of image
pos.initx1 = -.5;    % 20% left of center
pos.inity1 = 0;    % Center vertically
pos.initx2 = 0.5;   % 20% right from center
pos.inity2 = 0;    % Same vertical level
% Movement ranges in normalized coordinates
pos.dxmin1 = -0.1;
pos.dxmax1 = 0.1;
pos.dymin1 = -0.1;
pos.dymax1 = 0.1;
pos.dxmin2 = -0.1;
pos.dxmax2 = 0.1;
pos.dymin2 = -0.1;
pos.dymax2 = 0.1;

% Tutorial mode (single target with corner-biased motion)
tut.nreps = 0;%120;
tut.threshold = 250;
tut.background_noise_lvl = 0; % only for tutorial

tut.inplace = 0; % true: immovable target (for fixation)
tut.corner_mode = 'sequence'; % 'random', 'fixed', or 'sequence'
tut.corner_idx = 1; % used when corner_mode='fixed' (1=TL,2=TR,3=BL,4=BR)
presequence = [repmat(rew.gauss_center_idx,1,2), setdiff(2:5,rew.gauss_center_idx)];
tut.corner_sequence = presequence(randperm(numel(presequence))); % used when corner_mode='sequence', wraps across trials
tut.corner_idx = 1; % used when corner_mode='fixed' (1=TL,2=TR,3=BL,4=BR)
tut.bias_strength = 0.2; % attraction to selected corner [0..1]
tut.jitter_std = 0.03; % zrandom jitter around biased walk
tut.sequence_counter = 0;
tut.step_size_mult = 1;

tut.stepNoiseType = ctl.stepNoiseType;
tut.stepNoiseSigma = ctl.stepNoiseSigma;
tut.stepNoiseCapSigma = ctl.stepNoiseCapSigma;
tut.boundaryMode = ctl.boundaryMode;
tut.boundaryRejectMaxAttempts = ctl.boundaryRejectMaxAttempts;
tut.targetHiddenBoundsFrac = ctl.targetHiddenBoundsFrac;

% pursuit task:
% Set pur.nreps near the top of this file; 0 disables pursuit trials.



if isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && ...
        isfield(ex.exp.CoPs, 'analysis') && isstruct(ex.exp.CoPs.analysis)
    analysis = ex.exp.CoPs.analysis;
else
    analysis = struct();
end
analysis.eyeTimeGoPulsePhysicalChannel = 6;
analysis.goPulsePhysicalChannel = 6;
analysis.photodiodePulsePhysicalChannel = 6;
analysis.photodiodePulseThresholdV = 0.3;
analysis.photodiodePulseWindowSec = 0.5;


ex.stim = struct();
ex.stim.type = 'texture';
%currently set using getDefaultSettingsx
% ex.exp.nreps = 2; % for makeSequencex (how many reps of stim type)
% ex.Header.animal = 'te'

%repackage:
ex.exp.CoPs.dirs = dirs;
ex.exp.CoPs.pos = pos;
ex.exp.CoPs.graph = graph;
ex.exp.CoPs.ctl = ctl;
ex.exp.CoPs.ctr = ctr;
ex.exp.CoPs.rew = rew;
ex.exp.CoPs.timing = timing;
ex.exp.CoPs.pre = pre;
ex.exp.CoPs.tut = tut;
ex.exp.CoPs.pur = pur;
ex.exp.CoPs.analysis = analysis;
end


function [dirsAll, folder] = resolveTextureFolderLocal(graph)
rootDir = localTextFieldLocal(graph, {'texture_root','stim_root','stimRoot'}, '/home/vpixx/stim');
folder = localTextFieldLocal(graph, ...
    {'texture_folder','textureFolder','stim_folder','stimFolder'}, '');
typoFolder = localTextFieldLocal(graph, {'textute_folder'}, '');
if ~isempty(typoFolder) && (isempty(folder) || strcmpi(localCharTextLocal(folder), 'cops'))
    folder = typoFolder;
end

rootDir = localCharTextLocal(rootDir);
folder = strtrim(localCharTextLocal(folder));
if isempty(folder)
    folder = 'cops';
end
folder = localStripTrailingFileSepLocal(folder);

if isAbsolutePathLocal(folder)
    dirsAll = folder;
else
    dirsAll = fullfile(rootDir, folder);
end

if ~localEndsWithLocal(dirsAll, filesep)
    dirsAll = [dirsAll filesep];
end
end


function value = localTextFieldLocal(s, fieldNames, defaultValue)
value = defaultValue;
if ~isstruct(s)
    return
end
for i = 1:numel(fieldNames)
    fieldName = fieldNames{i};
    if isfield(s, fieldName) && ~isempty(s.(fieldName))
        value = s.(fieldName);
        return
    end
end
end


function tf = isAbsolutePathLocal(pathText)
pathText = localCharTextLocal(pathText);
tf = strncmp(pathText, filesep, numel(filesep)) || ...
    ~isempty(regexp(pathText, '^[A-Za-z]:[\\/]', 'once'));
end


function text = localCharTextLocal(value)
if ischar(value)
    text = value;
elseif iscell(value) && ~isempty(value)
    text = localCharTextLocal(value{1});
else
    text = char(value);
end
end


function tf = localEndsWithLocal(text, suffix)
text = localCharTextLocal(text);
suffix = localCharTextLocal(suffix);
tf = numel(text) >= numel(suffix) && strcmp(text(end-numel(suffix)+1:end), suffix);
end


function text = localStripTrailingFileSepLocal(text)
text = localCharTextLocal(text);
while numel(text) > 1 && (strcmp(text(end), '/') || strcmp(text(end), '\'))
    text = text(1:end-1);
end
end
