function [ex] = runTrialTaskCoPsx(ex, pixOn, eyeOn, rewOn)
% run Trial Task CoPs - Continuous Psychophysics Exp (Restructured)
% Wojciech Zajkowski 20 Nov 25
% Restructured by Assistant 25 Nov 25

% Adapted from syth_mask_test.m for VSgui_v2 framework
% Mouse tracking instead of eye fixation, multi-step stimulus presentation

% Key restructuring:
% - Separated state updates from frame updates
% - Integrated continuous reward system
% - Frame-based timing instead of tic/toc loops
% - Proper integration with VSgui framework

% history
% 11/12/25: Created from runTrialTask.m + syth_mask_test.m integration
% 11/25/25: Restructured for framework consistency

% ------------------------------------------------------------------------
% PRETRIAL ALLOCATIONS, STIMULUS GENERATION AND SETUP
% ------------------------------------------------------------------------

arguments
    ex struct
    pixOn  {mustBeNumericOrLogical} = true
    eyeOn  {mustBeNumericOrLogical} = true
    rewOn {mustBeNumericOrLogical} = true
end

%temp

%debugging vars (filled with timestamps each time event happened)
been_here = [];
been_here2 = [];

dpp = atan(ex.setup.monitorWidth/2/ex.setup.viewingDistance)*180/pi/(ex.setup.screenRect(3)/2);
ppd = 1/dpp;

% point for photodiode synch pulse
spSz = ex.synch.PSz;
spCol =  ex.synch.Col; %[255 0 0]; %
spPos = [ex.setup.screenRect(3) - spSz/2; spSz/2];
spHalfSz = spSz / 2;
spRects = [spPos(1,:) - spHalfSz; spPos(2,:) - spHalfSz; ...
    spPos(1,:) + spHalfSz; spPos(2,:) + spHalfSz];
goSyncPulseDuration = 0.10; % seconds
goSyncPulseEndTime = -inf;


% Unpack CoPs parameters
dirs = ex.exp.CoPs.dirs;
pos = ex.exp.CoPs.pos;
graph = ex.exp.CoPs.graph;
ctl = ex.exp.CoPs.ctl;
rew = ex.exp.CoPs.rew;
if isfield(ex.exp.CoPs, 'ctr')
    ctr = ex.exp.CoPs.ctr;
else
    ctr = struct();
end
timing = ex.exp.CoPs.timing;
[graph, textureGeometryInfo] = localResolveGraphTextureGeometryFromStimulusLocal( ...
    graph, localCurrentStimulusDirLocal(ex));
[graph, radiusInfo] = localResolveGraphRadiusForDisplayLocal(graph, ex.setup);
ex.exp.CoPs.graph = graph;
[rew, gaussSigmaInfo] = localResolveRewardGaussianSigmaForDisplayLocal(rew, ex.setup);
ex.exp.CoPs.rew = rew;
[step_wait_secs_default, step_wait_hz_default] = resolveCoPsWaitSecs(ex, 0.1);
timing.waitHz = step_wait_hz_default;
timing.wait_secs = step_wait_secs_default;
ex.exp.CoPs.timing = timing;
tut = ex.exp.CoPs.tut;
if isfield(ex.exp.CoPs, 'pur')
    pur = ex.exp.CoPs.pur;
else
    pur = struct();
end

blockInfo = getCoPsTrialBlockInfox(ex);

% Tutorial trials always come first. Pursuit can run before or after main.
isTutorialTrial = any(ex.j == blockInfo.tutorialIdx);
isPursuitTrial = any(ex.j == blockInfo.pursuitIdx);
isPreTrial = any(ex.j == blockInfo.preIdx);

if isTutorialTrial && isfield(tut, 'threshold')
    reward_threshold = tut.threshold;
elseif isPursuitTrial && isfield(pur, 'threshold')
    reward_threshold = pur.threshold;
else
    reward_threshold = rew.threshold;
end

% One-shot override: run current trial as a center fixation trial.
useFixationTrial = isfield(ctl, 'next_fixation_trial') && logical(ctl.next_fixation_trial);

% Support mixed/randomized background noise levels across trials.
% Tutorial and main-task trials can use different noise settings.
% If the selected background_noise_lvl is a vector (e.g., [0 5 30]),
% sample one level per trial. By default, level 0 forces fixed background,
% while non-zero levels use dynamic background.
if isTutorialTrial && isfield(tut, 'background_noise_lvl')
    noise_levels = tut.background_noise_lvl;
else
    noise_levels = graph.background_noise_lvl;
end
scheduled_noise_lvl = getScheduledTrialParamValue(ex, 'background_noise_lvl');
if useFixationTrial
    graph.background_noise_lvl = 5;
    ex.Trials(ex.j).background_noise_lvl = 5;
elseif isfinite(scheduled_noise_lvl)
    graph.background_noise_lvl = scheduled_noise_lvl;
    ex.Trials(ex.j).background_noise_lvl = scheduled_noise_lvl;
elseif numel(noise_levels) > 1
    chosen_noise_lvl = noise_levels(randi(numel(noise_levels)));
    graph.background_noise_lvl = chosen_noise_lvl;
    ex.Trials(ex.j).background_noise_lvl = chosen_noise_lvl;
else
    graph.background_noise_lvl = noise_levels;
    ex.Trials(ex.j).background_noise_lvl = noise_levels;
end
ex.Trials(ex.j).fixed_background = double(ex.Trials(ex.j).background_noise_lvl == 0);
ex.Trials(ex.j).no_background = double(ex.Trials(ex.j).background_noise_lvl == -1);
if ~isTutorialTrial && ~isPursuitTrial && ex.Trials(ex.j).background_noise_lvl == -1 && ...
        isfield(rew, 'thresholdNoiseNull') && isfinite(rew.thresholdNoiseNull)
    reward_threshold = rew.thresholdNoiseNull;
elseif ~isTutorialTrial && ~isPursuitTrial && ex.Trials(ex.j).background_noise_lvl == -1 && ...
        isfield(rew, 'threshold_noiseNull') && isfinite(rew.threshold_noiseNull)
    reward_threshold = rew.threshold_noiseNull;
elseif ~isTutorialTrial && ~isPursuitTrial && ex.Trials(ex.j).background_noise_lvl == 0 && ...
        isfield(rew, 'threshold_noise0') && isfinite(rew.threshold_noise0)
    reward_threshold = rew.threshold_noise0;
end
ex.Trials(ex.j).reward_threshold = reward_threshold;

% Support mixed/randomized target visibility across trials. Fixed-background
% trials can use graph.target_visibility0; no-background (-1) trials can
% use graph.targetVisibilityNull/target_visibilityNull; other noise levels
% use graph.target_visibility.
if ex.Trials(ex.j).background_noise_lvl == -1 && isfield(graph, 'targetVisibilityNull')
    visibility_levels = graph.targetVisibilityNull;
elseif ex.Trials(ex.j).background_noise_lvl == -1 && isfield(graph, 'target_visibilityNull')
    visibility_levels = graph.target_visibilityNull;
elseif ex.Trials(ex.j).background_noise_lvl == 0 && isfield(graph, 'target_visibility0')
    visibility_levels = graph.target_visibility0;
elseif isfield(graph, 'target_visibility')
    visibility_levels = graph.target_visibility;
else
    visibility_levels = 1;
end
scheduled_target_visibility = getScheduledTrialParamValue(ex, 'target_visibility');
if isfinite(scheduled_target_visibility)
    chosen_target_visibility = scheduled_target_visibility;
elseif numel(visibility_levels) > 1
    chosen_target_visibility = visibility_levels(randi(numel(visibility_levels)));
else
    chosen_target_visibility = visibility_levels;
end
graph.target_visibility = chosen_target_visibility;
ex.Trials(ex.j).target_visibility = chosen_target_visibility;

% Balanced stimulus schedules can assign one texture rotation per trial.
scheduled_texture_rotation_k = getScheduledTrialParamValue(ex, 'texture_rotation_k');
if isfinite(scheduled_texture_rotation_k)
    scheduled_texture_rotation_k = mod(round(scheduled_texture_rotation_k), 4);
    graph.texture_rotation_k = scheduled_texture_rotation_k;
    ex.Trials(ex.j).textureRotationK = scheduled_texture_rotation_k;
    ex.Trials(ex.j).textureRotationDeg = 90 * scheduled_texture_rotation_k;
else
    ex.Trials(ex.j).textureRotationK = NaN;
    ex.Trials(ex.j).textureRotationDeg = NaN;
end

% Support mixed/randomized target mask width across trials.
% target_mask_sigma_mult scales the default Gaussian mask sigma
% (currently graph.radius / 3 in texture-image pixels).
if isfield(graph, 'target_mask_sigma_mult')
    target_mask_sigma_mult_levels = graph.target_mask_sigma_mult;
else
    target_mask_sigma_mult_levels = 1;
end
scheduled_target_mask_sigma_mult = getScheduledTrialParamValue(ex, 'target_mask_sigma_mult');
if isfinite(scheduled_target_mask_sigma_mult)
    chosen_target_mask_sigma_mult = scheduled_target_mask_sigma_mult;
elseif numel(target_mask_sigma_mult_levels) > 1
    chosen_target_mask_sigma_mult = target_mask_sigma_mult_levels(randi(numel(target_mask_sigma_mult_levels)));
else
    chosen_target_mask_sigma_mult = target_mask_sigma_mult_levels;
end
graph.target_mask_sigma_mult = chosen_target_mask_sigma_mult;
ex.Trials(ex.j).target_mask_sigma_mult = chosen_target_mask_sigma_mult;

% Support mixed/randomized target coherence across trials.
if isfield(ctl, 'coherence')
    coherence_levels = ctl.coherence;
else
    coherence_levels = 1;
end
scheduled_coherence = getScheduledTrialParamValue(ex, 'coherence');
if isfinite(scheduled_coherence)
    chosen_coherence = scheduled_coherence;
elseif numel(coherence_levels) > 1
    chosen_coherence = coherence_levels(randi(numel(coherence_levels)));
else
    chosen_coherence = coherence_levels;
end
ctl.coherence = chosen_coherence;
ex.Trials(ex.j).coherence = chosen_coherence;

% Support mixed/randomized number of targets across trials.
% Repeated values set the sampling proportion, e.g. [1 2 2 2] gives
% 25% one-target trials and 75% two-target trials.
if ex.Trials(ex.j).background_noise_lvl == -1 && isfield(ctl, 'target_numNULL')
    target_num_levels = ctl.target_numNULL;
elseif isfield(ctl, 'target_num')
    target_num_levels = ctl.target_num;
else
    target_num_levels = 2;
end
scheduled_target_num = getScheduledTrialParamValue(ex, 'target_num');
if isfinite(scheduled_target_num)
    chosen_target_num = scheduled_target_num;
elseif numel(target_num_levels) > 1
    chosen_target_num = target_num_levels(randi(numel(target_num_levels)));
else
    chosen_target_num = target_num_levels;
end
chosen_target_num = round(double(chosen_target_num));
if ~ismember(chosen_target_num, [1, 2])
    error('runTrialTaskCoPsx:BadTargetNum', ...
        'ctl.target_num must resolve per trial to 1 or 2; got %g.', chosen_target_num);
end
ctl.target_num = chosen_target_num;
ex.Trials(ex.j).target_num = chosen_target_num;

% Support mixed/randomized target step sizes across trials.
% Tutorial and main-task trials can use different step-size settings.
if isTutorialTrial && isfield(tut, 'step_size_mult')
    step_size_levels = tut.step_size_mult;
else
    step_size_levels = ctl.step_size_mult;
end
scheduled_step_size_mult = getScheduledTrialParamValue(ex, 'step_size_mult');
if isfinite(scheduled_step_size_mult)
    chosen_step_size_mult = scheduled_step_size_mult;
elseif numel(step_size_levels) > 1
    chosen_step_size_mult = step_size_levels(randi(numel(step_size_levels)));
else
    chosen_step_size_mult = step_size_levels;
end
ex.Trials(ex.j).step_size_mult = chosen_step_size_mult;

dx_range1 = chosen_step_size_mult * [pos.dxmin1, pos.dxmax1];
dy_range1 = chosen_step_size_mult * [pos.dymin1, pos.dymax1];
dx_range2 = chosen_step_size_mult * [pos.dxmin2, pos.dxmax2];
dy_range2 = chosen_step_size_mult * [pos.dymin2, pos.dymax2];
step_noise_sigma = chosen_step_size_mult * ctl.stepNoiseSigma;
if isTutorialTrial && isfield(tut, 'stepNoiseSigma')
    step_noise_sigma = chosen_step_size_mult * tut.stepNoiseSigma;
end
boundary_mode = getOptionalFieldLocal(ctl, 'boundaryMode', 'clip');
boundary_reject_max_attempts = getOptionalFieldLocal(ctl, 'boundaryRejectMaxAttempts', 50);
if isTutorialTrial
    boundary_mode = getOptionalFieldLocal(tut, 'boundaryMode', boundary_mode);
    boundary_reject_max_attempts = getOptionalFieldLocal(tut, 'boundaryRejectMaxAttempts', boundary_reject_max_attempts);
end
target_hidden_bounds_frac = getOptionalFieldLocal(ctl, 'targetHiddenBoundsFrac', 0);
if isTutorialTrial
    target_hidden_bounds_frac = getOptionalFieldLocal(tut, 'targetHiddenBoundsFrac', target_hidden_bounds_frac);
end
target_hidden_bounds_frac = double(target_hidden_bounds_frac);
target_hidden_bounds_frac = target_hidden_bounds_frac(1);
if ~isfinite(target_hidden_bounds_frac)
    target_hidden_bounds_frac = 0;
end
target_hidden_bounds_frac = max(0, target_hidden_bounds_frac);
target_position_bound = localTargetPositionBoundLocal(graph, target_hidden_bounds_frac);
ctl.targetHiddenBoundsFrac = target_hidden_bounds_frac;
ex.Trials(ex.j).boundaryMode = char(string(boundary_mode));
ex.Trials(ex.j).boundaryRejectMaxAttempts = boundary_reject_max_attempts;
ex.Trials(ex.j).targetHiddenBoundsFrac = target_hidden_bounds_frac;
ex.Trials(ex.j).targetPositionBound = target_position_bound;


if useFixationTrial
    ctl.target_num = 1;
    ex.Trials(ex.j).target_num = 1;
    pos.initx1 = 0;
    pos.inity1 = 0;
    pos.dxmin1 = 0;
    pos.dxmax1 = 0;
    pos.dymin1 = 0;
    pos.dymax1 = 0;
    ex.exp.CoPs.ctl.next_fixation_trial = 0; % consume one-shot flag
end

% Record trial-level eye recenter metadata for offline reference.
ex.Trials(ex.j).eyeRecenterCount = 0;
if isfield(ex, 'eyeCal') && isfield(ex.eyeCal, 'Delta') && ~isempty(ex.eyeCal.Delta) && ...
        isfield(ex.eyeCal.Delta, 'cnt') && ~isempty(ex.eyeCal.Delta(1).cnt)
    ex.Trials(ex.j).eyeDeltaCntStart = ex.eyeCal.Delta(1).cnt;
else
    ex.Trials(ex.j).eyeDeltaCntStart = NaN;
end
ex.Trials(ex.j).eyeDeltaCntEnd = ex.Trials(ex.j).eyeDeltaCntStart;


rew.alwaysOnEyeInBounds; % if yes, reward always given as long as eye traces
% are within screen bounds

% Optional tutorial mode: use one target with motion biased toward one corner.
if isTutorialTrial || isPursuitTrial
    ctl.target_num = 1;
    ex.Trials(ex.j).target_num = 1;
end
if isPursuitTrial
    ctl.gauss_scalar = 1;
end
ex.Trials(ex.j).gauss_scalar = ctl.gauss_scalar;
ex.Trials(ex.j).textureSourceDims = textureGeometryInfo.sourceDims;
ex.Trials(ex.j).textureGeometryAutoResolved = double(textureGeometryInfo.autoResolved);
ex.Trials(ex.j).textureGeometrySourceFile = textureGeometryInfo.sourceFile;


% Window and display setup
window_size = ex.setup.screenRect;
window_background_color = ex.idx.black;
texture_background_color = ex.idx.bg_lum;
texture_background_w = graph.texture_dims(2) * graph.size_mult;
texture_background_h = graph.texture_dims(1) * graph.size_mult;
texture_background_rect = CenterRectOnPointd([0 0 texture_background_w texture_background_h], ...
    mean(window_size([1 3])), mean(window_size([2 4])));
scaleTextureOnDraw = true;
if isfield(graph, 'scaleTextureOnDraw') && ~isempty(graph.scaleTextureOnDraw)
    scaleTextureOnDraw = localScalarLogicalLocal(graph.scaleTextureOnDraw, true);
end
textureDrawRect = [];
if scaleTextureOnDraw
    textureDrawRect = texture_background_rect;
end
step_wait_secs = step_wait_secs_default;
if isPursuitTrial
    pursuitUpdateHz = min(ex.setup.refreshRate, 60);
    step_wait_secs = 1 / pursuitUpdateHz;
    ex.Trials(ex.j).pursuitUpdateHz = pursuitUpdateHz;
else
    ex.Trials(ex.j).pursuitUpdateHz = NaN;
end
ex.Trials(ex.j).waitSecs = step_wait_secs;
ex.Trials(ex.j).waitHz = 1 / step_wait_secs;

% Calculate max distance for reward here...(could be moved to a sep func for more modularity...)
target_radius_px = graph.radius * graph.size_mult;
main_reward_radius_px = ctl.max_dist_mult * target_radius_px;
pursuit_radius_deg = 0.25;
if isfield(pur, 'size') && isfinite(pur.size) && pur.size > 0
    pursuit_radius_deg = double(pur.size);
end
pursuit_radius_px = max(1, round(pursuit_radius_deg * ppd));
ex.Trials(ex.j).targetRadiusTexturePx = graph.radius;
ex.Trials(ex.j).targetRadiusPx = target_radius_px;
ex.Trials(ex.j).targetRadiusDeg = target_radius_px / ppd;
ex.Trials(ex.j).targetRadiusUnits = char(radiusInfo.units);
ex.Trials(ex.j).targetRadiusReferenceMonitorWidth = radiusInfo.referenceMonitorWidth;
ex.Trials(ex.j).pursuitRadiusPx = pursuit_radius_px;
if isPursuitTrial
    max_distance_reward = main_reward_radius_px;
    ex.Trials(ex.j).pursuitRewardRadiusDeg = max_distance_reward / ppd;
else
    max_distance_reward = main_reward_radius_px;
    ex.Trials(ex.j).pursuitRewardRadiusDeg = NaN;
end
ex.Trials(ex.j).rewardRadiusPx = max_distance_reward;
ex.Trials(ex.j).mainRewardRadiusPx = main_reward_radius_px;
ex.Trials(ex.j).mainRewardRadiusDeg = main_reward_radius_px / ppd;
gauss_dim = graph.texture_dims(1)*graph.size_mult; % based on texture size

%reward_mat = gauss_rew_land(gauss_dim, [gauss_dim/2, gauss_dim/2], rew.gauss_sigma); % reward matrix
% Pick Gaussian reward center once per session: indexed center or free center.
[ctr, max_peak_dist_norm] = resolveMaxPeakDistanceNormLocal(ctr, gauss_dim, ppd, rew);
ex.exp.CoPs.ctr = ctr;
[rew, gaussCenterCache] = loadDailyGaussCenterCoordsLocal(ex, rew, ctr, max_peak_dist_norm);
[rew, selected_center_norm, center_px] = selectGaussRewardCenterCoPsx(rew, gauss_dim, max_peak_dist_norm);
[rew, gaussCenterCache] = saveDailyGaussCenterCoordsLocal(ex, rew, selected_center_norm, ctr, max_peak_dist_norm, gaussCenterCache);
rew.gauss_center_cache = gaussCenterCache;
ex.exp.CoPs.rew = rew;

reward_mat = gauss_rew_land(gauss_dim, center_px, rew.gauss_sigma); % reward matrix
xshift = (window_size(3) - gauss_dim)/2; %
yshift = (window_size(4) - gauss_dim)/2;

% gauss center marker settings
gauss_center_screen_px = [xshift + center_px(1), yshift + center_px(2)];

% Log center for trial-level data/debugging
ex.Trials(ex.j).gaussRewardCenterNorm = selected_center_norm;
ex.Trials(ex.j).gaussRewardCenterPx = center_px;
ex.Trials(ex.j).gauss_center_free = isfield(rew, 'gauss_center_free') && ...
    ~isempty(rew.gauss_center_free) && logical(rew.gauss_center_free(1));
ex.Trials(ex.j).gauss_center_coords = rew.gauss_center_coords;
ex.Trials(ex.j).maxPeakDistDeg = ctr.max_peak_dist_deg;
ex.Trials(ex.j).maxPeakDistNorm = max_peak_dist_norm;
ex.Trials(ex.j).gaussCenterCachePath = gaussCenterCache.path;
ex.Trials(ex.j).gaussCenterCacheStatus = gaussCenterCache.status;
ex.Trials(ex.j).gaussSigmaPx = gaussSigmaInfo.sigmaPx;
ex.Trials(ex.j).gaussSigmaDeg = gaussSigmaInfo.sigmaDeg;
ex.Trials(ex.j).gaussSigmaUnits = char(gaussSigmaInfo.units);
ex.Trials(ex.j).isPursuitTrial = isPursuitTrial;
ex.Trials(ex.j).isPreTrial = isPreTrial;
if useFixationTrial
    run_phase_label = 'fixation';
elseif isTutorialTrial
    run_phase_label = 'tut';
elseif isPursuitTrial
    run_phase_label = 'pur';
elseif isPreTrial
    run_phase_label = 'pre';
else
    run_phase_label = 'main';
end

if isfield(ctl, 'randomize_start_pos') && ctl.randomize_start_pos
    start_radius = hypot(pos.initx1, pos.inity1);
    start_theta = rand * (2*pi);

    pos.initx1 = start_radius * cos(start_theta);
    pos.inity1 = start_radius * sin(start_theta);
    if ctl.target_num == 2
        pos.initx2 = -pos.initx1;
        pos.inity2 = -pos.inity1;
    end
end


% Initialize target positions
posT = struct();
ex.Trials(ex.j).isTutorialTrial = isTutorialTrial;
ex.Trials(ex.j).rewardThreshold = reward_threshold;

if isPursuitTrial
    pursuitTrialOrdinal = find(blockInfo.pursuitIdx == ex.j, 1, 'first');
    if isempty(pursuitTrialOrdinal)
        pursuitTrialOrdinal = 1;
    end
    [pursuit_nsteps, pursuitMeta] = computeSmoothPursuitTrialMetaLocal( ...
        pursuitTrialOrdinal, rew, window_size, gauss_dim, xshift, yshift, ppd, step_wait_secs, pur);
    ctl.nsteps = pursuit_nsteps;
    ex.Trials(ex.j).nsteps = ctl.nsteps;
end

if useFixationTrial
    % Keep the one-shot fixation trial fully stationary at screen center,
    % including when tutorial mode is enabled.
    ex.Trials(ex.j).runPhase = 'fixation';
    target_corner = [0, 0];
    posT.x1 = repmat(0, 1, ctl.nsteps);
    posT.y1 = repmat(0, 1, ctl.nsteps);
    ex.Trials(ex.j).tutorialCornerIdx = 1;
    ex.Trials(ex.j).tutorialCornerTarget = target_corner;
elseif isTutorialTrial
    ex.Trials(ex.j).runPhase = 'tutorial';
    corner_targets = rew.gauss_center_positions_norm*2-1; %[0,0; -0.75, -0.75; 0.75, -0.75; -0.75, 0.75; 0.75, 0.75] % Center, TL, TR, BL, BR
    if  strcmpi(tut.corner_mode, 'fixed')
        corner_idx = min(max(1, tut.corner_idx), 5);
        
    % explicit sequence
    elseif strcmpi(tut.corner_mode, 'sequence')
        seq = tut.corner_sequence(:)';
        seq_counter = tut.sequence_counter;       
        seq_idx = mod(seq_counter, numel(seq)) + 1;
        corner_idx = seq(seq_idx);
        ex.exp.CoPs.tut.sequence_counter = seq_counter + 1;
    % else: random
    else
        corner_idx = randi(5);
    end
    target_corner = corner_targets(corner_idx, :);
    bias_strength = tut.bias_strength;
    jitter_std = tut.jitter_std;

    if tut.inplace
        posT.x1 = repmat(target_corner(1), 1, ctl.nsteps);
        posT.y1 = repmat(target_corner(2), 1, ctl.nsteps);
    else
        tutorial_init_xy = [0, 0];
        [posT.x1, posT.y1] = sim_targ_pos_biased_corner( ...
            ctl.nsteps, tutorial_init_xy, ...
            dx_range1, dy_range1, ...
            target_corner, bias_strength, jitter_std, ...
            tut.stepNoiseType, step_noise_sigma, tut.stepNoiseCapSigma, ...
            boundary_mode, boundary_reject_max_attempts, target_position_bound);
    end
   
    ex.Trials(ex.j).tutorialCornerIdx = corner_idx;
    ex.Trials(ex.j).tutorialCornerTarget = target_corner;
elseif isPursuitTrial
    ex.Trials(ex.j).runPhase = 'pursuit';
    [posT, targPositions] = buildSmoothPursuitTrialLocal(ctl.nsteps, pursuitMeta);
    ex.Trials(ex.j).tutorialCornerIdx = NaN;
    ex.Trials(ex.j).tutorialCornerTarget = [NaN, NaN];
    ex.Trials(ex.j).pursuitStartCornerIdx = pursuitMeta.startCornerIdx;
    ex.Trials(ex.j).pursuitEndCornerIdx = pursuitMeta.endCornerIdx;
    ex.Trials(ex.j).pursuitStartCornerNorm = pursuitMeta.startCornerNorm;
    ex.Trials(ex.j).pursuitEndCornerNorm = pursuitMeta.endCornerNorm;
    ex.Trials(ex.j).pursuitSpeedDegPerSec = pursuitMeta.speedDegPerSec;
    ex.Trials(ex.j).pursuitSizeDeg = pursuitMeta.sizeDeg;
    ex.Trials(ex.j).pursuitLenSec = pursuitMeta.lenSec;
    ex.Trials(ex.j).pursuitPathLengthDeg = pursuitMeta.pathLengthDeg;
else
    if isPreTrial
        ex.Trials(ex.j).runPhase = 'pre';
    else
        ex.Trials(ex.j).runPhase = 'main';
    end
    ex.Trials(ex.j).tutorialCornerIdx = NaN;
    ex.Trials(ex.j).tutorialCornerTarget = [NaN, NaN];
    posT.x1 = sim_targ_pos(ctl.nsteps, pos.initx1, dx_range1(1), dx_range1(2), ...
        ctl.stepNoiseType, step_noise_sigma, ctl.stepNoiseCapSigma, ...
        boundary_mode, boundary_reject_max_attempts, target_position_bound);
    posT.y1 = sim_targ_pos(ctl.nsteps, pos.inity1, dy_range1(1), dy_range1(2), ...
        ctl.stepNoiseType, step_noise_sigma, ctl.stepNoiseCapSigma, ...
        boundary_mode, boundary_reject_max_attempts, target_position_bound);
end


if ctl.target_num == 2
    posT.x2 = sim_targ_pos(ctl.nsteps, pos.initx2, dx_range2(1), dx_range2(2), ...
        ctl.stepNoiseType, step_noise_sigma, ctl.stepNoiseCapSigma, ...
        boundary_mode, boundary_reject_max_attempts, target_position_bound);
    posT.y2 = sim_targ_pos(ctl.nsteps, pos.inity2, dy_range2(1), dy_range2(2), ...
        ctl.stepNoiseType, step_noise_sigma, ctl.stepNoiseCapSigma, ...
        boundary_mode, boundary_reject_max_attempts, target_position_bound);
end
ex.Trials(ex.j).posT = posT;


% assign colors for eye and mouse positions (overlay dots: ol)
if ~isempty(ex.eyeCal.LXPos)
    if ~ ex.setup.stereo.Display
        olColBinoc = [ex.idx.overlayRed,ex.idx.overlayGreen,ex.idx.overlayBlue, ex.idx.overlayGreen]; % right,left,binoc, mouse
        olColBinoc = [olColBinoc'*ones(1,3)];
    else
        olColBinoc = [ex.idx.overlay,ex.idx.overlay ex.idx.overlay ex.idx.overlay]; % right, left, binoc, mouse
        olColBinoc = [olColBinoc'*ones(1,3)];
    end
    olPSz = 16; %[ceil(ex.setup.eyePSz/2)*ones(2,1); ex.setup.eyePSz; 2]; % eye (R,L,B), mouse
else olColBinoc = ex.idx.overlay*ones(1,3); %
    olPSz = 16;%[ex.setup.eyePSz; 2]; % eye, mouse pos
end

% Eye tolerance visualization (matches checkEyex default tolerance scalar)
tolerance_scalar = ctl.tolerance_scalar;
tolHalfW = ex.fix.WinW * tolerance_scalar;
tolHalfH = ex.fix.WinH * tolerance_scalar;
tolRect = CenterRectOnPointd([0 0 2*tolHalfW 2*tolHalfH], ex.fix.PCtr(1), ex.fix.PCtr(2));
tolRectColor = ex.idx.white;
tolRectPenW = 2;


% Optional experimenter-only target circles (not projected).
useOverlayTargetCircles = isfield(ctl,'circle_target_loc_overlay') && ctl.circle_target_loc_overlay;
if isPursuitTrial
    overlayCircleRadiusPx = pursuit_radius_px;
else
    overlayCircleRadiusPx = graph.radius * graph.size_mult;
end
overlayCirclePenW = 2;
overlayCircleColor = ex.idx.white;
useOverlayGaussCenterMarker = isfield(rew, 'show_gauss_center_marker_overlay') && ...
    ~isempty(rew.show_gauss_center_marker_overlay) && logical(rew.show_gauss_center_marker_overlay(1));
overlayGaussCenterMarkerHalfSz = 5;
if isfield(rew, 'gauss_center_marker_psz') && ~isempty(rew.gauss_center_marker_psz)
    overlayGaussCenterMarkerHalfSz = double(rew.gauss_center_marker_psz(1)) / 2;
end
overlayGaussCenterMarkerPenW = max(1, round(overlayGaussCenterMarkerHalfSz / 3));
if isfield(ex.idx, 'overlayGreen')
    overlayGaussCenterMarkerColor = ex.idx.overlayGreen;
else
    overlayGaussCenterMarkerColor = ex.idx.overlay;
end


% MAKE STIMULUS AND PRELOAD TEXTURES
stimTextures = [];
stimTiming = struct();
if ~isPursuitTrial
    try
        graph.trialLogBackgroundNoiseLvl = ex.Trials(ex.j).background_noise_lvl;
        graph.trialLogTargetVisibility = ex.Trials(ex.j).target_visibility;
        graph.trialLogRunPhase = run_phase_label;
        [stimTextures, targPositions, stimTiming] = makeStimulusCoPsx(ex.setup, ctl, ex.stim.seq{ex.j}, posT, graph, ex.j);
    catch err
        fprintf(2, '%s\n', getReport(err, 'extended'));
        error('Failed to create stimulus: %s', err.message);
    end
end
ex.Trials(ex.j).stimTiming = stimTiming;

% Stimulus generation can take substantial time. Clear the ADC buffer here
% so trial eye data begin close to the actual trial start, not at the
% earlier generic pretrial reset in runEx/runExptx.
if eyeOn
    resetAdcBuffer(ex);
end

% PRE-ALLOCATE MEMORY FOR TIMING AND DATA
frametimestep = 1/ex.setup.refreshRate;
eyetimestep = 1/ex.setup.adc.Rate;  % 500Hz is the fastest Eyelink sample binocularly
maxTrialDur = step_wait_secs * ctl.nsteps + 5 + ex.fix.waitstop; % add buffer time
frame_alloc_n = ceil(maxTrialDur*ex.setup.refreshRate);
flip_info = NaN(frame_alloc_n,4);
frameStep = NaN(frame_alloc_n,1);
frameState = NaN(frame_alloc_n,1);
frameSyncPulse = false(frame_alloc_n,1);
StimStart = NaN*ones(1,ceil(ex.setup.refreshRate*ex.fix.stimDuration));

flip_info_grow_chunk = ceil(10 * ex.setup.refreshRate); % grow by ~10s if trial runs longer than expected
stimstart_grow_chunk = ceil(2 * ex.setup.refreshRate);  % grow by ~2s as needed

% Initialize eye-related variables
if eyeOn
    centerEye_t0 = GetSecs; % hack to prevent several re-centerings of eye position per key-press
    trEye.v = NaN(length(ex.setup.adc.Channels),ceil(maxTrialDur*ex.setup.adc.Rate)); % pre-allocate memory
    trEye.t = NaN(1,ceil(maxTrialDur*ex.setup.adc.Rate));
    trEye.n = 0; % nAcquiredFrames
    trEye.sacc = [];
    pass_eye = 0;
    if isempty(ex.eyeCal.LXPos)
        lastEyePos = [0 0];
    else lastEyePos = [0 0; 0 0];
    end
    lasteyeposttime = 0;
end
rewardCenterOverlayToggle_t0 = -Inf; % debounce reward-center overlay toggle (F6)
targetCircleOverlayToggle_t0 = -Inf; % debounce target-circle overlay toggle (F8)
gazeHeatPlot_t0 = -Inf; % debounce gaze heat plot (F9)
overlayToggleDebounceSecs = 0.25;
scheduleFixTrial_t0 = -Inf; % debounce one-shot fixation trial scheduler (F3)
mousePos = [NaN,NaN];%[x+ex.setup.mouseXOffset,y];

% Initialize other trial variables
eyeInBounds = 0;
pass_eye = 0; % currently this one's init is doubled for convenience..
pass_eye_accum = 0; %number of eye frames that were passed in a row
%freeViewing = 0; % for checkEye, 0 for assessing fixation (switched off for GO state); 1 for skipping fixation assesment
mousePositions = [];
olPos = [NaN,NaN];
closeness_vec = [];
reward_vec = [];
scaled_reward_vec = [];
scaled_reward_vec_per_target = zeros(0, max(1, ctl.target_num));
current_step = 1;

% Time variables
time_startTrial = NaN;
time_fpOn = NaN;
time_stimOn = NaN;
time_choice = NaN;
time_reward = NaN; % analogue to time_earlyReward (replaces time_rewardGiven)
time_error = NaN;
time_goSyncPulseStart = NaN;
time_goSyncPulseEndPlanned = NaN;

% initialize misc
current_x = NaN;
current_y = NaN;
current_xy = [0,0];
gauss_reward = NaN;
% Initialize reward tracking
reward_accum_realized = 0; % total REALIZED (i.e., already rewarded) reward value across trial
reward_accum_since_last = 0; % total reward value since last reward delivery (or start of trial)
if isfield(ctl, 'independent_accumulation') && ctl.independent_accumulation && ctl.target_num > 1
    reward_accum_realized = zeros(1, ctl.target_num);
    reward_accum_since_last = zeros(1, ctl.target_num);
end
reward_start = 0;
reward_stop = 0;
reward_on = 0;
reward_cnt = 0;
% reward_dur = rew.duration;

% Fixation flash settings (dot flashes only during fixation period)
fixFlashHz = 5;      % flashes per second
fixFlashDuty = 0.5;  % proportion of cycle that stays visible
fixFlashEnabled = 0;


% Initialize state variables
stimulus_active = false;
reward_active = false; % xx add reward refractory period, maybe..


% Initialize loop counters
fi = 1; % frame index
si = 0; % stim frame index
ei = 1; % eye frame index
xi = 1; % eye frame index but only for GO (to check reward update freq)
lastframet = 0;
lasteyepostime = 0;
ex.loopcnt(ex.j) = 0;
ex.Trials(ex.j).to = 0; % default is no time-out
ex.Trials(ex.j).pa = 0; % default is no pause
ex.Trials(ex.j).isFixationTrial = useFixationTrial;
% ex.Trials(ex.j).dR = 0; % default is no decrease in reward size
% ex.Trials(ex.j).addInstructionTrials = 0;
% ------------------------------------------------------------------------
% TRIAL START
% ------------------------------------------------------------------------
% use clock time as unique trial ID
clocktime = fix(clock);

% get trial start times
tic
if pixOn
    tocBEFORESTROBES = toc;
    sendStrobes([ex.strobe.TRIAL_ID,fix(clock),ex.strobe.TRIAL_NUMBER,ex.j]);
    tocSENDSTROBES = toc;
end
if eyeOn
    trstart_Eyelink = Eyelink('TrackerTime');
    toc_trstartEYELINK = toc;
end
trstart = GetSecs;  % start of trial time
toc_trstartGETSECS = toc;

% this synchronizes the ripple and the datapixOnx clocks
if pixOn 
    sendStrobe(ex.strobe.TRIAL_START);
    toc_trstartSENDSTROBE = toc;
    % din-dependent: (ah...digital in...)
    % analogue version: Datapixx('GetAdcVoltages')..'StartAdcSchedule','SetAdcSchedule'
    [tmp, tmp, trstart_Datapixx] = getDatapixxDin(ex.strobe.TRIAL_START);
    %trstart_Datapixx = Datapixx('GetTime'); % this is USELESS!!
end

ttime = GetSecs-trstart;
state = ex.states.START;

% ------------------------------------------------------------------------
% MAIN TRIAL LOOP
% ------------------------------------------------------------------------
while state ~= ex.states.BREAKFIX &&...
        state ~= ex.states.TRIALCOMPLETE &&...
        state ~= ex.states.NOFIX &&...
        ex.quit == 0 && ttime > 0
    
    % --------------------------------------------------------------------
    % STATE UPDATE SECTION -----------------------------------------------
    % --------------------------------------------------------------------
    freeViewing = ex.exp.CoPs.freeViewing;
    % START -> FPON
    if state == ex.states.START && ttime > ex.fix.freeduration
        state = ex.states.FPON;
        stimulus_active = true;
        time_startTrial = GetSecs - trstart;
        %disp('in fixation dot on');
        %fprintf('in fixation dot on');
        time_fpOn = GetSecs - trstart;
    end
    
    % FPON -> FPHOLD (fixation acquired)
    if state == ex.states.FPON  && pass_eye && freeViewing == 0% && ttime < ex.fix.waitstop
        time_startFixation = GetSecs - trstart;
        
        % if ttime > 0.5 % brief fixation period
        state = ex.states.FPHOLD;
        if pixOn sendStrobe(ex.strobe.FIXATION_START);
          %  disp('in fixation acquired');
           % fprintf('in fixation acquired');
        end
    elseif state == ex.states.FPON && ttime < ex.fix.waitstop && freeViewing == 1 
        time_startFixation = GetSecs - trstart;
        % if ttime > 0.5 % brief fixation period
        state = ex.states.FPHOLD;
        if pixOn sendStrobe(ex.strobe.FIXATION_START);
        end
    elseif state == ex.states.FPON && ttime > ex.fix.waitstop && freeViewing == 1
        state = ex.states.NOFIX;
        disp('in no fixation acquired');
        fprintf('in no fixation acquired');
        time_breakFixation = GetSecs - trstart;
    end
    
    % FPHOLD -> FIXATIONCOMPLETE
    if state == ex.states.FPHOLD
        if  false %~pass_eye 
            state = ex.states.BREAKFIX;
            disp('in breakfix');
            %new
        elseif pass_eye && pass_eye_accum <= 500
           % disp('during fix')
            % time_breakFixation = GetSecs - trstart;
        elseif ttime > time_startTrial + ex.fix.duration && pass_eye_accum>500
            % current_step = current_step + 1;
            state = ex.states.PREGO;
            if ~rew.alwaysOnEyeInBounds
                Datapixx('SetDoutValues',1);
                Datapixx('RegWr');
            end
            time_prego = GetSecs - trstart;
            disp('fixation complete');
            fprintf('fixation complete');
        end
    end
    
    % FIXATIONCOMPLETE -> GO (start stimulus presentation)
    if state == ex.states.PREGO
       % reward_stop=1;
        if ttime > time_prego + timing.prego_delay
            state = ex.states.FIXATIONCOMPLETE;
            time_fixationComplete = GetSecs - trstart;
            disp('stimulus pre-presentation');
            fprintf('stimulus pre-presentation');
        end
    end
    % FIXATIONCOMPLETE -> GO (start stimulus presentation)
    if state == ex.states.FIXATIONCOMPLETE && ttime>0; % xx this can be increased for testing
        if ttime > time_fixationComplete + timing.go_delay
            state = ex.states.GO;
            time_goSyncPulseStart = GetSecs - trstart;
            time_goSyncPulseEndPlanned = time_goSyncPulseStart + goSyncPulseDuration;
            goSyncPulseEndTime = trstart + time_goSyncPulseEndPlanned;
            if ~rew.alwaysOnEyeInBounds
                Datapixx('SetDoutValues',0);
                Datapixx('RegWr');
            end
            freeViewing = 1; %because fixation no longer needed
            time_stimOn = GetSecs - trstart;
            reward_active = true;
            disp('stimulus presentation started');
            fprintf('stimulus presentation started');
        end
    end
    
    
    % --------------------------------------------------------------------
    % FRAME UPDATE SECTION -----------------------------------------------
    % --------------------------------------------------------------------
    % update eye position (fast)
    ttime = GetSecs-trstart;
    if eyeOn
        if ttime > lasteyepostime + eyetimestep

            [x,y] = GetMouse;
            %Prepare single screen call for all onscreen dots ( fp, eyepos, mousepos)
                if isempty(ex.eyeCal.LXPos) %monocular eye position
                    olPos = [lastEyePos;mousePos]; % eye pos; mouse pos
                    
                else %overlay dot positions: binocular eye positions; mouse
                    olPos = [lastEyePos;
                        mean(lastEyePos,1); ... % mean R/L eye position;
                        mousePos]; % mouse positions
                end
            % pass_eye =1;
            %xxsimEyes(trEye, lastEyePos)
            % simulate eye position here..
            if current_step == 5
                % fprintf('here')
            end
            
            %calc rew
            if state == ex.states.GO && reward_active
                % Get current mouse position
                % [current_x, current_y] = GetMouse();
                eyePts = lastEyePos(:,1:2);
                validEyeRows = all(isfinite(eyePts), 2);
                if any(validEyeRows)
                    % Use both eyes when available; fallback to single valid eye.
                    current_xy_abs = mean(eyePts(validEyeRows, :), 1);
                else
                    current_xy_abs = [NaN NaN];
                end

                currentEyeInBounds = all(isfinite(current_xy_abs)) && ...
                    current_xy_abs(1) >= ex.setup.screenRect(1) && current_xy_abs(1) <= ex.setup.screenRect(3) && ...
                    current_xy_abs(2) >= ex.setup.screenRect(2) && current_xy_abs(2) <= ex.setup.screenRect(4);
                % fprintf('current_xy = [%f %f]\n', current_xy(1), current_xy(2));
                % mousePositions = [mousePositions; current_x, current_y, GetSecs()];


                % Calculate closeness to targets ( [0-1] bound )
                if ctl.target_num == 1
                    closeness = calc_closeness(current_xy_abs, ...
                        targPositions(current_step).targ1.pos_abs, max_distance_reward);
                    closeness1 = closeness;
                    closeness2 = NaN;
                else
                    closeness1 = calc_closeness(current_xy_abs, ...
                        targPositions(current_step).targ1.pos_abs, max_distance_reward);
                    closeness2 = calc_closeness(current_xy_abs, ...
                        targPositions(current_step).targ2.pos_abs, max_distance_reward);
                    closeness = max(closeness1, closeness2);
                end
                
                if isPursuitTrial
                    gauss_reward = 1;
                    scaled_reward = closeness;
                    scaled_reward_target_vec = scaled_reward;
                else
                    % Map absolute screen coordinates to reward matrix coordinates
                    rel_x = round(current_xy_abs(1) - xshift);
                    rel_y = round(current_xy_abs(2) - yshift);
                    %is position (mouse/gaze) within the texture and on screen?
                    if currentEyeInBounds && ...
                            (rel_x >= 1 && rel_x <= size(reward_mat,2)) && ...
                            (rel_y >= 1 && rel_y <= size(reward_mat,1))
                        gauss_reward = reward_mat(rel_y, rel_x);
                    else
                        gauss_reward = 0;
                    end
                    gauss_reward = gauss_reward * (ctl.gauss_scalar-1) + 1;

                    % Calculate scaled reward
                    if strcmp(ctl.reward_type, 'add')  & isfield(ctl, 'precision_weight')
                        scaled_reward = closeness * ctl.precision_weight + gauss_reward * (1 - ctl.precision_weight);
                        if ctl.target_num == 1
                            scaled_reward_target_vec = scaled_reward;
                        else
                            scaled_reward_target_vec = [ ...
                                closeness1 * ctl.precision_weight + gauss_reward * (1 - ctl.precision_weight), ...
                                closeness2 * ctl.precision_weight + gauss_reward * (1 - ctl.precision_weight)];
                        end
                    elseif strcmp(ctl.reward_type, 'mult')  & isfield(ctl, 'gauss_scalar')
                        scaled_reward = closeness * gauss_reward;
                        if ctl.target_num == 1
                            scaled_reward_target_vec = scaled_reward;
                        else
                            scaled_reward_target_vec = [closeness1 * gauss_reward, closeness2 * gauss_reward];
                        end
                    else
                        disp('reward type not set properly!')
                        break
                    end
                end
                
                
                % Store data
                closeness_vec(end+1) = closeness;
                reward_vec(end+1) = gauss_reward;
                scaled_reward_vec(end+1) = scaled_reward;
                
                % Check for accumulated reward threshold
                if ~isempty(scaled_reward_vec)
                    if isfield(ctl, 'independent_accumulation') && ctl.independent_accumulation && ctl.target_num > 1
                        scaled_reward_vec_per_target(end+1, :) = scaled_reward_target_vec; %#ok<AGROW>
                        reward_accum_since_last = sum(scaled_reward_vec_per_target, 1) - reward_accum_realized;
                        reward_trigger_mask = reward_accum_since_last > reward_threshold;
                        if any(reward_trigger_mask) && ~reward_on
                            reward_accum_realized(reward_trigger_mask) = reward_accum_realized(reward_trigger_mask) + ...
                                reward_accum_since_last(reward_trigger_mask);
                            fprintf('\nReward delivered! Accumulated per target: [%s]\n', num2str(reward_accum_since_last, '%.2f '));
                            reward_cnt = reward_cnt + 1;
                            time_reward(reward_cnt) = GetSecs() - trstart;
                            reward_start = 1;
                        end
                    else
                        reward_accum_since_last = sum(scaled_reward_vec) - reward_accum_realized; % this workds because reward_accum_realized is updated only after;
                        if (reward_accum_since_last > reward_threshold)  && ~reward_on
                            reward_accum_realized = reward_accum_realized + reward_accum_since_last;
                            fprintf('\nReward delivered! Accumulated: %.2f\n', reward_accum_since_last);
                            % Trigger reward delivery
                            %if rewOn time_reward(ex.reward.time); end
                            reward_cnt = reward_cnt + 1;
                            time_reward(reward_cnt) = GetSecs() - trstart;
                            reward_start = 1;
                        end
                    end
                end
                
                % Check for error conditions (too far from targets)
                if current_step > 3
                    if length(closeness_vec)>rew.accum_len_fp
                        distance_window = 1 - closeness_vec(end-(rew.accum_len_fp):end);
                    else
                        distance_window = 1 -closeness_vec(1:end);
                    end
                    % if max(distance_window) > 0.95 || mean(distance_window) > 0.5
                    %     sprintf('Bad performance - ending trial');
                    %     state = ex.states.ERROR;
                    %     time_error = GetSecs() - trstart;
                    %     stimulus_active = false;
                    %     reward_active = false;
                    % end
                    
                end
                xi = xi+1;
            end
            
            % fprintf('Mouse X: %4d   Y: %4d\n', current_x, current_y);
            % fprintf('gauss_reward: %4d\n', gauss_reward);
            if state == ex.states.FPON
               %keyboard
            end
            % [pass_eye,trEye,lastEyePos] = checkEyex(trEye,ex,pass_eye,freeViewing, lastEyePos);
            [pass_eye,trEye,lastEyePos] = checkEyex(trEye,ex,pass_eye,freeViewing, lastEyePos, 0, 0, tolerance_scalar);
            if pass_eye==1
               pass_eye_accum = pass_eye_accum +1;
               % sprintf('were adding')
               % sprintf(pass_eye_accum);
            else
                pass_eye_accum = 0;
            end
            lasteyepostime = ttime;
            ei = ei+1;
        end
    else
        if ttime > .2 pass_eye = 1; end
    end
    
     % Check whether at least one tracked eye is visible and within display bounds.
    if eyeOn
        if isempty(ex.eyeCal.LXPos)
            eyePts = lastEyePos(1,1:2);
            validEyeRows = all(isfinite(eyePts), 2);
            eyeInBounds = any(validEyeRows) && ...
                all(eyePts(validEyeRows,1) >= ex.setup.screenRect(1) & eyePts(validEyeRows,1) <= ex.setup.screenRect(3)) && ...
                all(eyePts(validEyeRows,2) >= ex.setup.screenRect(2) & eyePts(validEyeRows,2) <= ex.setup.screenRect(4));
        else
            eyePts = lastEyePos(:,1:2);
            validEyeRows = all(isfinite(eyePts), 2);
            eyeInBounds = any(validEyeRows) && ...
                all(eyePts(validEyeRows,1) >= ex.setup.screenRect(1) & eyePts(validEyeRows,1) <= ex.setup.screenRect(3)) && ...
                all(eyePts(validEyeRows,2) >= ex.setup.screenRect(2) & eyePts(validEyeRows,2) <= ex.setup.screenRect(4));
        end
        %eyeInBounds = all(isfinite(eyePts(:))) && ...
         %   all(eyePts(:,1) >= ex.setup.screenRect(1) & eyePts(:,1) <= ex.setup.screenRect(3)) && ...
          %  all(eyePts(:,2) >= ex.setup.screenRect(2) & eyePts(:,2) <= ex.setup.screenRect(4));
    else
        eyeInBounds = false;
    end




    % give reward
    if rewOn
        if rew.alwaysOnEyeInBounds && state>5.5
            if eyeInBounds
                Datapixx('SetDoutValues',1);
                Datapixx('RegWr');
                reward_on = 1;
            elseif ~eyeInBounds || state <=5.5
                Datapixx('SetDoutValues',0);
                Datapixx('RegWr');
                reward_on = 0;
            end
        else
            if reward_start
                Datapixx('SetDoutValues',1);
                Datapixx('RegWr');
                reward_start = 0;
                reward_on = 1;
                %sprintf('rew now!')
            end
            if (current_step > ctl.nsteps) ||...
                    (reward_on && ttime > time_reward(reward_cnt) + rew.duration)%*rew.scale
                Datapixx('SetDoutValues',0);
                Datapixx('RegWr');
                reward_on = 0;
                % been_here2(end+1) = GetSecs() - trstart;
                %sprintf('rew over!')
            end
        end
    end
    % Screen('FillRect', ex.setup.overlay, ex.idx.bg);
% Screen('CopyWindow', ex.setup.overlay, ex.setup.window);
% Screen('Flip', ex.setup.window);
    if ttime > lastframet + frametimestep
        
        % --------------------------------------------------------------------
        % CONTINUOUS REWARD CALCULATION SECTION -------------------------------
        % --------------------------------------------------------------------
        % if state == ex.states.GO && reward_active
        %     % Get current mouse position
        %     [current_x, current_y] = GetMouse();
        %     % print([current_x, current_y]);
        %     mousePositions = [mousePositions; current_x, current_y, GetSecs()];
        %
        %     % Calculate closeness to targets ( [0-1] bound )
        %     if ctl.target_num == 1
        %         closeness = calc_closeness([current_x, current_y], ...
        %             targPositions(current_step).targ1.pos_abs, max_distance_reward);
        %     else
        %         closeness1 = calc_closeness([current_x, current_y], ...
        %             targPositions(current_step).targ1.pos_abs, max_distance_reward);
        %         closeness2 = calc_closeness([current_x, current_y], ...
        %             targPositions(current_step).targ2.pos_abs, max_distance_reward);
        %         closeness = max(closeness1, closeness2);
        %     end
        %
        %     % Map screen coordinates to reward matrix coordinates
        %     rel_x = uint16(current_x - xshift);
        %     rel_y = uint16(current_y - yshift);
        %     %is position (mouse/gaze) within the texture?
        %     if (rel_x>0 && rel_x<=size(reward_mat,1)) &&...
        %             (rel_y>0 && rel_y<=size(reward_mat,2))
        %         gauss_reward = reward_mat(rel_x, rel_y);
        %     else
        %         gauss_reward = 0;
        %     end
        %
        %     % Calculate scaled reward
        %     scaled_reward = closeness * ctl.precision_weight + gauss_reward * (1 - ctl.precision_weight);
        %
        %     % Store data
        %     closeness_vec(end+1) = closeness;
        %     reward_vec(end+1) = gauss_reward;
        %     scaled_reward_vec(end+1) = scaled_reward;
        %
        %     % Check for accumulated reward threshold
        %     if ~isempty(scaled_reward_vec)
        %         reward_accum_since_last = sum(scaled_reward_vec) - reward_accum_realized; % this workds because reward_accum_realized is updated only after;
        %         if (reward_accum_since_last > rew.threshold)  && ~reward_on
        %             reward_accum_realized = reward_accum_realized + reward_accum_since_last;
        %             fprintf('\nReward delivered! Accumulated: %.2f\n', reward_accum_since_last);
        %             % Trigger reward delivery
        %             %if rewOn time_reward(ex.reward.time); end
        %             reward_cnt = reward_cnt + 1;
        %             time_reward(reward_cnt) = GetSecs() - trstart;
        %             reward_start = 1;
        %         end
        %     end
        %
        %     % Check for error conditions (too far from targets)
        %     if current_step > 3
        %         if length(closeness_vec)>rew.accum_len_fp
        %             distance_window = 1 - closeness_vec(end-(rew.accum_len_fp):end);
        %         else
        %             distance_window = 1 -closeness_vec(1:end)
        %         end
        %         % if max(distance_window) > 0.95 || mean(distance_window) > 0.5
        %         %     sprintf('Bad performance - ending trial');
        %         %     state = ex.states.ERROR;
        %         %     time_error = GetSecs() - trstart;
        %         %     stimulus_active = false;
        %         %     reward_active = false;
        %         % end
        %
        %     end
        % end

        % Clear screen
        Screen('FillRect', ex.setup.window, window_background_color);
        Screen('FillRect', ex.setup.window, texture_background_color, texture_background_rect);
        
        %flash
        inFixationPeriod = (state == ex.states.FPON || state == ex.states.FPHOLD);
        showFixationDot = true;
        if inFixationPeriod && fixFlashEnabled && ~isnan(time_fpOn)
            flashPeriod = 1 / fixFlashHz;
            flashPhase = mod(ttime - time_fpOn, flashPeriod);
            showFixationDot = flashPhase <= (fixFlashDuty * flashPeriod);
        end
        
        frameStepToSave = NaN;
        frameStateToSave = state;
        frameSyncPulseToSave = false;

        % Draw fixation point (if no stim)
        if inFixationPeriod && ~stimulus_active && showFixationDot
        % if (state == ex.states.FPON || state == ex.states.FPHOLD) &&...
        %         ~stimulus_active
            Screen('DrawDots', ex.setup.window, ex.fix.PCtr, ex.fix.PSz, ex.idx.white);
        end
        
        % Draw stimulus if active
        if stimulus_active && (current_step <= ctl.nsteps)
            
            % Determine which step to show
            if state == ex.states.PREGO
                step_to_show = 1;  % Show the regular first stimulus texture during PREGO
            else
                step_to_show = current_step;
            end
            frameStepToSave = step_to_show;
            
            if isPursuitTrial
                pursuitPos = targPositions(step_to_show).targ1.pos_abs;
                pursuitRect = CenterRectOnPointd([0 0 2*pursuit_radius_px 2*pursuit_radius_px], pursuitPos(1), pursuitPos(2));
                Screen('FillOval', ex.setup.window, ex.idx.white, pursuitRect);
            else
                % Draw current stimulus texture XX pack into playStimulus? & add si update
                if scaleTextureOnDraw
                    Screen('DrawTexture', ex.setup.window, stimTextures(step_to_show), [], textureDrawRect);
                else
                    Screen('DrawTexture', ex.setup.window, stimTextures(step_to_show));
                end

                % During PREGO, cue the upcoming targets with fixation dots at
                % their centers instead of the old pre-rendered circles.
                if state == ex.states.PREGO
                    pregoDotPos = targPositions(step_to_show).targ1.pos_abs(:);
                    if ctl.target_num == 2
                        pregoDotPos = [pregoDotPos, targPositions(step_to_show).targ2.pos_abs(:)];
                    end
                    Screen('DrawDots', ex.setup.window, pregoDotPos, ex.fix.PSz, ex.idx.white);
                end
            end

            % Optional marker showing Gaussian reward center on stimulus screen.
            if ~isPursuitTrial && rew.show_gauss_center_marker & state == ex.states.GO
                markerHalfSz = rew.gauss_center_marker_psz / 2;
                markerPenW = max(1, round(rew.gauss_center_marker_psz / 6));
                Screen('DrawLine', ex.setup.window, ex.idx.white, ...
                    gauss_center_screen_px(1) - markerHalfSz, gauss_center_screen_px(2) - markerHalfSz, ...
                    gauss_center_screen_px(1) + markerHalfSz, gauss_center_screen_px(2) + markerHalfSz, markerPenW);
                Screen('DrawLine', ex.setup.window, ex.idx.white, ...
                    gauss_center_screen_px(1) - markerHalfSz, gauss_center_screen_px(2) + markerHalfSz, ...
                    gauss_center_screen_px(1) + markerHalfSz, gauss_center_screen_px(2) - markerHalfSz, markerPenW);
            end

            % draw fix on top of stim, if necessary
             if inFixationPeriod && showFixationDot
                Screen('DrawDots', ex.setup.window, ex.fix.PCtr, ex.fix.PSz, ex.idx.white);
            end
            
            % NEW: draw eye position
            %Screen('DrawDots', ex.setup.window, olPos, olPSz, olCol, [], 2);   % dot type 2 = anti-aliased circle% draw eye dots, mouse position
            if true
                % clear overlay
               % Screen('FillRect', ex.setup.overlay, ex.idx.bg);
               
                if isempty(ex.setup.overlay)
                    % Fallback if no overlay window is configured.
                    if state<5.5
                        Screen('FrameRect', ex.setup.window, tolRectColor, tolRect, tolRectPenW);
                    end
                else
                    % clear and redraw experimenter-only overlay
                    Screen('FillRect', ex.setup.overlay, ex.idx.bg);
                    if state<5.5
                        Screen('FrameRect', ex.setup.overlay, tolRectColor, tolRect, tolRectPenW);
                    end
                end
                
                % overlay: circle targets
                if ~isPursuitTrial && useOverlayTargetCircles
                    t1 = targPositions(step_to_show).targ1.pos_abs;
                    circ1 = CenterRectOnPointd([0 0 2*overlayCircleRadiusPx 2*overlayCircleRadiusPx], t1(1), t1(2));
                    if isempty(ex.setup.overlay)
                        Screen('FrameOval', ex.setup.window, overlayCircleColor, circ1, overlayCirclePenW);
                    else
                        Screen('FrameOval', ex.setup.overlay, overlayCircleColor, circ1, overlayCirclePenW);
                    end
                    if ctl.target_num == 2
                        t2 = targPositions(step_to_show).targ2.pos_abs;
                        circ2 = CenterRectOnPointd([0 0 2*overlayCircleRadiusPx 2*overlayCircleRadiusPx], t2(1), t2(2));
                        if isempty(ex.setup.overlay)
                            Screen('FrameOval', ex.setup.window, overlayCircleColor, circ2, overlayCirclePenW);
                        else
                            Screen('FrameOval', ex.setup.overlay, overlayCircleColor, circ2, overlayCirclePenW);
                        end
                    end
                end

                % overlay: Gaussian reward center marker, experimenter-only
                if ~isPursuitTrial && useOverlayGaussCenterMarker && state == ex.states.GO && ~isempty(ex.setup.overlay)
                    Screen('DrawLine', ex.setup.overlay, overlayGaussCenterMarkerColor, ...
                        gauss_center_screen_px(1) - overlayGaussCenterMarkerHalfSz, gauss_center_screen_px(2), ...
                        gauss_center_screen_px(1) + overlayGaussCenterMarkerHalfSz, gauss_center_screen_px(2), ...
                        overlayGaussCenterMarkerPenW);
                    Screen('DrawLine', ex.setup.overlay, overlayGaussCenterMarkerColor, ...
                        gauss_center_screen_px(1), gauss_center_screen_px(2) - overlayGaussCenterMarkerHalfSz, ...
                        gauss_center_screen_px(1), gauss_center_screen_px(2) + overlayGaussCenterMarkerHalfSz, ...
                        overlayGaussCenterMarkerPenW);
                end


    % pick the most recent column (use end or 1 depending on which column you want)
             %   eyePos = olPos(1:2, end);            % 2x1 vector [eyeX; eyeY]
             %   olPos(3:4,:) = 0; % eliminate mouse position...
                
             % Keep reward logic based on mean(valid eyes), but only show per-eye positions
                % on the experimenter overlay when both eyes are available.
                % if isempty(ex.eyeCal.LXPos)
                %     overlayPos = olPos(1:2,:); % monocular: single eye + mouse
                %     overlayColors = olColBinoc(1:2,:);
                % else
                %     overlayPos = olPos(1:2,:); % binocular: right + left eyes only
                %     overlayColors = olColBinoc(1:2,:);
                % end
                %keyboard
             
                if isempty(ex.setup.overlay)
                    Screen('Drawdots',ex.setup.window,olPos',olPSz',olColBinoc');
                    %Screen('Drawdots',ex.setup.window,overlayPos',olPSz',overlayColors');
                else
                   Screen('Drawdots',ex.setup.overlay,olPos',olPSz',olColBinoc');
                   %Screen('Drawdots',ex.setup.overlay,overlayPos',olPSz',overlayColors');
                end

            end
            
            % Draw synch pulse
            %Screen('DrawDots', ex.setup.window, spPos, spSz, spCol);
            
            %Draw synch pulse briefly when entering GO state
            if GetSecs <= goSyncPulseEndTime
                Screen('FillRect', ex.setup.window, spCol, spRects);
                frameSyncPulseToSave = true;
            end

            % Update stimulus step based on timing
            if state == ex.states.GO
                step_duration = GetSecs() - (time_stimOn + trstart);
                if step_duration > (current_step - 1) * step_wait_secs
                    current_step = current_step + 1;
                    %fprintf('Moving to step %d/%d\n', current_step, ctl.nsteps);
                end
                si = si + 1; % what is the purpose of keeping track of si?
            end
            % possibly to keep track of StimStart
        end
        
        
        if state == ex.states.GO && stimulus_active
            if fi > size(flip_info,1)
                flip_info(end+1:end+flip_info_grow_chunk, :) = NaN;
                frameStep(end+1:end+flip_info_grow_chunk, 1) = NaN;
                frameState(end+1:end+flip_info_grow_chunk, 1) = NaN;
                frameSyncPulse(end+1:end+flip_info_grow_chunk, 1) = false;
            end
            if si > numel(StimStart)
                StimStart(end+1:end+stimstart_grow_chunk) = NaN;
            end
            StimStart(si) = flip_info(fi,1);
        end
        

        
        % Draw reward indicator if reward was given XX (can this be only on experimenter screen?)
        if ~isnan(time_reward(1)) && ttime > time_reward(reward_cnt) && ttime < time_reward(reward_cnt) + 0.5
            %Screen('DrawText', ex.setup.window, 'REWARD', 100, 100, ex.idx.white);
            if isempty(ex.setup.overlay)
                Screen('DrawText', ex.setup.window, 'REWARD', 100, 100, ex.idx.white);
            else
                Screen('DrawText', ex.setup.overlay, 'REWARD', 100, 100, ex.idx.white);
            end

        end
        
        % Flip screen
        Screen('DrawingFinished', ex.setup.window);
         if fi > size(flip_info,1)
            flip_info(end+1:end+flip_info_grow_chunk, :) = NaN;
            frameStep(end+1:end+flip_info_grow_chunk, 1) = NaN;
            frameState(end+1:end+flip_info_grow_chunk, 1) = NaN;
            frameSyncPulse(end+1:end+flip_info_grow_chunk, 1) = false;
         end
        frameStep(fi) = frameStepToSave;
        frameState(fi) = frameStateToSave;
        frameSyncPulse(fi) = frameSyncPulseToSave;
        [flip_info(fi,1), flip_info(fi,2), flip_info(fi,3), flip_info(fi,4)] =...
            Screen('Flip', ex.setup.window);
        fi = fi + 1;
        if fi > 500 
            %keyboard
        end
        lastframet = ttime;
    end
    
    % --------------------------------------------------------------------
    % INPUT HANDLING SECTION ---------------------------------------------
    % --------------------------------------------------------------------
    [keyIsDown, secs, keyCode] = KbCheck;
    if ~isMatlabWindowFocusedLocal()
        keyCode = zeros(size(keyCode));
    end
    
    if strcmpi(KbName(keyCode),'F4')
        ex.quit = 4;
        state;
    elseif strcmpi(KbName(keyCode),'F1')
        ex.quit = 1;
        ex.Trials(ex.j).pa = 1;
        state;
    elseif strcmpi(KbName(keyCode),'F2')
        ex.quit = 2;
        ex.Trials(ex.j).to = 1;
    % F3: fixation trial next
    elseif strcmpi(KbName(keyCode),'F3')
        if GetSecs - scheduleFixTrial_t0 > 0.25
            ex.exp.CoPs.ctl.next_fixation_trial = 1;
            scheduleFixTrial_t0 = GetSecs;
            disp('next trial scheduled as center fixation trial (F3)');
        end
    
    % F6: reward-center overlay marker
    elseif strcmpi(KbName(keyCode),'F6')
        if GetSecs - rewardCenterOverlayToggle_t0 > overlayToggleDebounceSecs
            useOverlayGaussCenterMarker = ~useOverlayGaussCenterMarker;
            rew.show_gauss_center_marker_overlay = double(useOverlayGaussCenterMarker);
            ex.exp.CoPs.rew.show_gauss_center_marker_overlay = rew.show_gauss_center_marker_overlay;
            rewardCenterOverlayToggle_t0 = GetSecs;
            if useOverlayGaussCenterMarker
                disp('reward center overlay ON (F6)');
            else
                disp('reward center overlay OFF (F6)');
            end
        end
    %F7: recenter
    elseif strcmpi(KbName(keyCode),'F7')
        % to make sure we only re-center once per keyboard press
        if GetSecs - centerEye_t0 > .5
            ex=centerEye(ex);
            ex.Trials(ex.j).eyeRecenterCount = ex.Trials(ex.j).eyeRecenterCount + 1;
            if isfield(ex, 'eyeCal') && isfield(ex.eyeCal, 'Delta') && ~isempty(ex.eyeCal.Delta) && ...
                    isfield(ex.eyeCal.Delta, 'cnt') && ~isempty(ex.eyeCal.Delta(1).cnt)
                ex.Trials(ex.j).eyeDeltaCntEnd = ex.eyeCal.Delta(1).cnt;
            end
            disp(['eye recentering #: ' num2str(ex.eyeCal.Delta(1).cnt)])
            centerEye_t0 = GetSecs;
        end
     %F8: target circle overlay
    elseif strcmpi(KbName(keyCode),'F8')
        if GetSecs - targetCircleOverlayToggle_t0 > overlayToggleDebounceSecs
            useOverlayTargetCircles = ~useOverlayTargetCircles;
            ctl.circle_target_loc_overlay = double(useOverlayTargetCircles);
            ex.exp.CoPs.ctl.circle_target_loc_overlay = ctl.circle_target_loc_overlay;
            targetCircleOverlayToggle_t0 = GetSecs;
            if useOverlayTargetCircles
                disp('target circle overlay ON (F8)');
            else
                disp('target circle overlay OFF (F8)');
            end
        end
    %F9: plot gaze heat from completed trials
    elseif strcmpi(KbName(keyCode),'F9')
        if GetSecs - gazeHeatPlot_t0 > 1.0
            gazeHeatPlot_t0 = GetSecs;
            lastCompletedTrial = min(ex.j - 1, numel(ex.Trials));
            if lastCompletedTrial < 1
                disp('gazeHeat skipped (F9): no completed trials yet');
            else
                if exist('gazeHeat', 'file') ~= 2
                    thisFileDir = fileparts(mfilename('fullpath'));
                    addpath(fullfile(thisFileDir, 'cops_analysis'));
                end
                try
                    gazeHeat(ex, 1:lastCompletedTrial);
                    drawnow;
                    disp(['gazeHeat plotted trials 1-' num2str(lastCompletedTrial) ' (F9)']);
                catch err
                    warning('runTrialTaskCoPsx:gazeHeatF9', ...
                        'gazeHeat failed on F9: %s', err.message);
                end
            end
        end

    

    end
    
    % Check for trial completion
    if state == ex.states.GO && current_step > ctl.nsteps
        state = ex.states.TRIALCOMPLETE;
        Datapixx('SetDoutValues',0);
        Datapixx('RegWr');
        % been_here2(end+1) = GetSecs() - trstart;
        stimulus_active = false;
        reward_active = false;
        disp('trial complete');
    end
    
    ex.loopcnt(ex.j) = ex.loopcnt(ex.j) + 1;
end

% ------------------------------------------------------------------------
% TRIAL END AND DATA STORAGE
% ------------------------------------------------------------------------
% blank screen at the end of trial
Screen('FillRect', ex.setup.window, window_background_color);
Screen('FillRect', ex.setup.window, texture_background_color, texture_background_rect);
Screen('Flip', ex.setup.window);

% Store trial information
ex.Trials(ex.j).ID = fix(clock);
ex.Trials(ex.j).Eye = trEye;
ex.Trials(ex.j).adcChannels = ex.setup.adc.Channels;

% Store trial times
ex.Trials(ex.j).TrialEnd = GetSecs();
ex.Trials(ex.j).TrialStart = trstart;
if pixOn ex.Trials(ex.j).TrialStartDatapixx = trstart_Datapixx; end
if pixOn
    ex.Trials(ex.j).TrialEndDatapixx = Datapixx('GetTime');
else
    ex.Trials(ex.j).TrialEndDatapixx = NaN;
end
if eyeOn ex.Trials(ex.j).TrialStarteyelink = trstart_Eyelink; end
if eyeOn ex.Trials(ex.j).TrialEndEyelink = NaN; end % Would need actual eyelink time

ex.Trials(ex.j).times.startTrial = time_startTrial + trstart;
ex.Trials(ex.j).times.stimOn = time_stimOn + trstart;
ex.Trials(ex.j).times.choice = time_choice + trstart;
ex.Trials(ex.j).times.reward = time_reward + trstart;
ex.Trials(ex.j).times.error = time_error + trstart;
ex.Trials(ex.j).times.goSyncPulseStart = time_goSyncPulseStart + trstart;
ex.Trials(ex.j).times.goSyncPulseEndPlanned = time_goSyncPulseEndPlanned + trstart;

% Store CoPs specific data
% ex.Trials(ex.j).mousePositions = mousePositions;
% ex.Trials(ex.j).current_x = current_x_vec;
% ex.Trials(ex.j).current_y = current_y_vec;
ex.Trials(ex.j).closeness = closeness_vec;
ex.Trials(ex.j).reward = reward_vec;
ex.Trials(ex.j).scaledReward = scaled_reward_vec;
ex.Trials(ex.j).targetPositions = targPositions;
ex.Trials(ex.j).nsteps = ctl.nsteps;
ex.Trials(ex.j).rewardAccumulated = reward_accum_realized + reward_accum_since_last; % need to add the unrealised reward amount
if isfield(ctl, 'independent_accumulation') && ctl.independent_accumulation && ctl.target_num > 1
    ex.Trials(ex.j).scaledRewardPerTarget = scaled_reward_vec_per_target;
end

% Store behavioral performance
if state == ex.states.REWARD || ~isnan(time_reward(1))
    good = 1;
    if rewOn RewardSize = rew.duration; end
elseif state == ex.states.ERROR
    good = -1;
    if rewOn RewardSize = 0;end
else
    good = 0;
    if rewOn RewardSize = 0; end
end

ex.Trials(ex.j).Reward = good;
if rewOn ex.Trials(ex.j).RewardSize = RewardSize; end
if isfield(ex, 'eyeCal') && isfield(ex.eyeCal, 'Delta') && ~isempty(ex.eyeCal.Delta) && ...
        isfield(ex.eyeCal.Delta, 'cnt') && ~isempty(ex.eyeCal.Delta(1).cnt)
    ex.Trials(ex.j).eyeDeltaCntEnd = ex.eyeCal.Delta(1).cnt;
end

% number of successfully completed trials
ex.goodtrial = ex.goodtrial + abs(good);

% store display timing
ex.Trials(ex.j).flip_info = flip_info(1:fi-1,:);
ex.Trials(ex.j).frameStep = frameStep(1:fi-1);
ex.Trials(ex.j).frameState = frameState(1:fi-1);
ex.Trials(ex.j).frameSyncPulse = frameSyncPulse(1:fi-1);
ex.Trials(ex.j).frameStateLookup = ex.states;

% -------------------------------------------------------------------------
% TRIAL ONLINE OUTPUT FOR EXPERIMENTER
% -------------------------------------------------------------------------
% correct = length(find([ex.Trials.Reward]==1));
% disp(['# trials:' num2str(ex.goodtrial) '  %success:' ...
%     num2str(correct/ex.goodtrial) ])
% disp(['fileName: ' ex.Header.onlineFileName ])

% increase trial counter
ex.j = ex.j + 1;

% Close stimulus textures
if ~isempty(stimTextures)
    Screen('Close', stimTextures);
end

end


function [nsteps, meta] = computeSmoothPursuitTrialMetaLocal(pursuitTrialIdx, rew, window_size, gauss_dim, xshift, yshift, ppd, step_wait_secs, pur)
cornerIdxList = 2:5; % reward quadrants: TL, TR, BL, BR
pursuitTrialIdx = max(1, pursuitTrialIdx);
startListIdx = mod(pursuitTrialIdx - 1, numel(cornerIdxList)) + 1;
startCornerIdx = cornerIdxList(startListIdx);
endCornerIdx = 7 - startCornerIdx; % 2<->5, 3<->4

startNorm01 = rew.gauss_center_positions_norm(startCornerIdx, :);
endNorm01 = rew.gauss_center_positions_norm(endCornerIdx, :);

startPx = [window_size(1) + xshift, window_size(2) + yshift] + (round(startNorm01 .* (gauss_dim - 1)) + 1);
endPx = [window_size(1) + xshift, window_size(2) + yshift] + (round(endNorm01 .* (gauss_dim - 1)) + 1);
pathLengthDeg = norm(endPx - startPx) / ppd;

speedDegPerSec = 10;
if isfield(pur, 'speed') && isfinite(pur.speed) && pur.speed > 0
    speedDegPerSec = double(pur.speed);
end

lenSec = 5;
if isfield(pur, 'lenSec') && isfinite(pur.lenSec) && pur.lenSec > 0
    lenSec = double(pur.lenSec);
end

sizeDeg = 0.25;
if isfield(pur, 'size') && isfinite(pur.size) && pur.size > 0
    sizeDeg = double(pur.size);
end

nsteps = max(2, round(lenSec / step_wait_secs));

meta = struct();
meta.startCornerIdx = startCornerIdx;
meta.endCornerIdx = endCornerIdx;
meta.startCornerNorm = startNorm01;
meta.endCornerNorm = endNorm01;
meta.startPx = startPx;
meta.endPx = endPx;
meta.speedDegPerSec = speedDegPerSec;
meta.sizeDeg = sizeDeg;
meta.lenSec = lenSec;
meta.pathLengthDeg = pathLengthDeg;
meta.durationSecs = lenSec;
end


function [posT, targPositions] = buildSmoothPursuitTrialLocal(nsteps, meta)
segmentLenDeg = max(meta.pathLengthDeg, eps);
pathDistDeg = (0:(nsteps-1)) * (meta.speedDegPerSec * meta.lenSec / max(nsteps-1, 1));
cycleLenDeg = 2 * segmentLenDeg;
phaseDeg = mod(pathDistDeg, cycleLenDeg);

frac = phaseDeg / segmentLenDeg;
reverseMask = frac > 1;
frac(reverseMask) = 2 - frac(reverseMask);

pathNorm01X = meta.startCornerNorm(1) + frac * (meta.endCornerNorm(1) - meta.startCornerNorm(1));
pathNorm01Y = meta.startCornerNorm(2) + frac * (meta.endCornerNorm(2) - meta.startCornerNorm(2));
pathPxX = meta.startPx(1) + frac * (meta.endPx(1) - meta.startPx(1));
pathPxY = meta.startPx(2) + frac * (meta.endPx(2) - meta.startPx(2));

posT = struct();
posT.x1 = pathNorm01X * 2 - 1;
posT.y1 = pathNorm01Y * 2 - 1;

targPositions = struct([]);
for stepIdx = 1:nsteps
    targPositions(stepIdx).targ1.pos_abs = [pathPxX(stepIdx), pathPxY(stepIdx)];
    targPositions(stepIdx).targ1.norm_pos = [posT.x1(stepIdx), posT.y1(stepIdx)];
    targPositions(stepIdx).step = stepIdx;
    targPositions(stepIdx).image_idx = NaN;
    targPositions(stepIdx).cx = posT.x1(stepIdx);
    targPositions(stepIdx).cy = posT.y1(stepIdx);
end

% Match the texture-task layout so PREGO/GO indexing remains valid.
targPositions(nsteps + 1) = targPositions(1);
end


function value = getScheduledTrialParamValue(ex, fieldName)
value = NaN;
if ~isfield(ex, 'exp') || ~isfield(ex.exp, 'CoPs') || ...
        ~isfield(ex.exp.CoPs, 'trialParamSchedules')
    return
end

sched = ex.exp.CoPs.trialParamSchedules;
if ~isstruct(sched) || ~isfield(sched, fieldName)
    return
end

seq = sched.(fieldName);
if isempty(seq) || numel(seq) < ex.j
    return
end

candidate = seq(ex.j);
if isfinite(candidate)
    value = double(candidate);
end
end


function [ctr, max_peak_dist_norm] = resolveMaxPeakDistanceNormLocal(ctr, gauss_dim, ppd, rew)
if ~isstruct(ctr)
    ctr = struct();
end

fallback_norm = localDefaultGaussCenterRadiusNormLocal(rew);
fallback_deg = fallback_norm * (gauss_dim - 1) / ppd;
if ~isfield(ctr, 'max_peak_dist_deg') || isempty(ctr.max_peak_dist_deg) || ...
        ~isfinite(localScalarFieldValueLocal(ctr.max_peak_dist_deg, NaN)) || ...
        localScalarFieldValueLocal(ctr.max_peak_dist_deg, NaN) < 0
    ctr.max_peak_dist_deg = fallback_deg;
end

max_peak_dist_deg = localScalarFieldValueLocal(ctr.max_peak_dist_deg, fallback_deg);
if ~isfinite(max_peak_dist_deg) || max_peak_dist_deg < 0 || ~isfinite(ppd) || ppd <= 0 || gauss_dim <= 1
    max_peak_dist_norm = fallback_norm;
else
    max_peak_dist_norm = max_peak_dist_deg * ppd / (gauss_dim - 1);
end

if ~isfinite(max_peak_dist_norm) || max_peak_dist_norm < 0
    max_peak_dist_norm = fallback_norm;
end
end


function radius_norm = localDefaultGaussCenterRadiusNormLocal(rew)
radius_norm = 0;
center_origin = [0.5, 0.5];
if isstruct(rew) && isfield(rew, 'gauss_center_positions_norm') && ~isempty(rew.gauss_center_positions_norm)
    centers = double(rew.gauss_center_positions_norm);
    if size(centers, 2) >= 2
        offsets = centers(:, 1:2) - center_origin;
        radius_norm = max(sqrt(sum(offsets .^ 2, 2)));
    end
end
if ~isfinite(radius_norm) || radius_norm < 0
    radius_norm = 0;
end
end


function [rew, cacheInfo] = loadDailyGaussCenterCoordsLocal(ex, rew, ctr, max_peak_dist_norm)
cacheInfo = initGaussCenterCacheInfoLocal(ex);
if ~isFreeGaussCenterModeLocal(rew)
    cacheInfo.status = 'disabled';
    return
end
if hasExplicitGaussCenterCoordsLocal(rew)
    cacheInfo.status = 'explicit_coords';
    cacheInfo.coords = double(rew.gauss_center_coords(1:2));
    return
end
if isempty(cacheInfo.path)
    cacheInfo.status = 'no_cache_path';
    return
end
if ~exist(cacheInfo.path, 'file')
    cacheInfo.status = 'new';
    return
end

try
    cached = load(cacheInfo.path);
catch
    cacheInfo.status = 'load_failed';
    return
end

if ~isfield(cached, 'gauss_center_coords')
    cacheInfo.status = 'missing_coords';
    return
end
coords = double(cached.gauss_center_coords);
if numel(coords) < 2
    cacheInfo.status = 'bad_coords';
    return
end
coords = coords(1:2);
if any(~isfinite(coords))
    cacheInfo.status = 'bad_coords';
    return
end
if isfield(cached, 'animal') && ~isempty(cached.animal) && ...
        ~strcmpi(char(string(cached.animal)), cacheInfo.animal)
    cacheInfo.status = 'animal_mismatch';
    return
end
if isfield(cached, 'dateString') && ~isempty(cached.dateString) && ...
        ~strcmp(char(string(cached.dateString)), cacheInfo.dateString)
    cacheInfo.status = 'date_mismatch';
    return
end
if ~isCenterWithinPeakRadiusLocal(coords, max_peak_dist_norm)
    cacheInfo.status = 'outside_current_radius';
    return
end

rew.gauss_center_coords = coords;
cacheInfo.loaded = true;
cacheInfo.status = 'loaded';
cacheInfo.coords = coords;
if isfield(cached, 'max_peak_dist_deg') && ~isempty(cached.max_peak_dist_deg)
    cacheInfo.cachedMaxPeakDistDeg = localScalarFieldValueLocal(cached.max_peak_dist_deg, NaN);
else
    cacheInfo.cachedMaxPeakDistDeg = NaN;
end
cacheInfo.currentMaxPeakDistDeg = localScalarFieldValueLocal(ctr.max_peak_dist_deg, NaN);
end


function [rew, cacheInfo] = saveDailyGaussCenterCoordsLocal(ex, rew, selected_center_norm, ctr, max_peak_dist_norm, cacheInfo)
if strcmp(cacheInfo.status, 'explicit_coords')
    cacheInfo.coords = double(selected_center_norm(1:2));
    cacheInfo.currentMaxPeakDistDeg = localScalarFieldValueLocal(ctr.max_peak_dist_deg, NaN);
    return
end
if ~isFreeGaussCenterModeLocal(rew) || cacheInfo.loaded || isempty(cacheInfo.path)
    return
end

coords = double(selected_center_norm(1:2));
if any(~isfinite(coords)) || ~isCenterWithinPeakRadiusLocal(coords, max_peak_dist_norm)
    cacheInfo.status = 'not_saved_bad_coords';
    return
end

cacheDir = fileparts(cacheInfo.path);
if ~exist(cacheDir, 'dir')
    try
        mkdir(cacheDir);
    catch
        cacheInfo.status = 'mkdir_failed';
        return
    end
end

animal = cacheInfo.animal;
dateString = cacheInfo.dateString;
gauss_center_coords = coords; %#ok<NASGU>
max_peak_dist_deg = localScalarFieldValueLocal(ctr.max_peak_dist_deg, NaN); %#ok<NASGU>
max_peak_dist_norm_saved = max_peak_dist_norm; %#ok<NASGU>
createdAt = datestr(now, 31); %#ok<NASGU>
sourceFile = '';
if isfield(ex, 'Header') && isfield(ex.Header, 'onlineFileName') && ~isempty(ex.Header.onlineFileName)
    sourceFile = char(string(ex.Header.onlineFileName));
end

try
    save(cacheInfo.path, 'gauss_center_coords', 'animal', 'dateString', ...
        'max_peak_dist_deg', 'max_peak_dist_norm_saved', 'createdAt', 'sourceFile');
catch
    cacheInfo.status = 'save_failed';
    return
end

rew.gauss_center_coords = coords;
cacheInfo.saved = true;
cacheInfo.status = 'saved';
cacheInfo.coords = coords;
cacheInfo.currentMaxPeakDistDeg = max_peak_dist_deg;
end


function cacheInfo = initGaussCenterCacheInfoLocal(ex)
cacheInfo = struct( ...
    'path', '', ...
    'animal', 'test', ...
    'dateString', strrep(datestr(date, 26), '/', '.'), ...
    'status', 'uninitialized', ...
    'loaded', false, ...
    'saved', false, ...
    'coords', [NaN NaN], ...
    'cachedMaxPeakDistDeg', NaN, ...
    'currentMaxPeakDistDeg', NaN);

if isfield(ex, 'Header') && isfield(ex.Header, 'animal') && ~isempty(ex.Header.animal)
    cacheInfo.animal = lower(strtrim(char(string(ex.Header.animal))));
end

dailyDir = '';
if isfield(ex, 'Header') && isfield(ex.Header, 'onlineDirName') && ~isempty(ex.Header.onlineDirName)
    dailyDir = char(string(ex.Header.onlineDirName));
elseif isfield(ex, 'setup') && isfield(ex.setup, 'dirRoot') && ~isempty(ex.setup.dirRoot)
    dailyDir = fullfile(char(string(ex.setup.dirRoot)), cacheInfo.animal, cacheInfo.dateString);
end

if ~isempty(dailyDir)
    cacheInfo.path = fullfile(dailyDir, 'CoPs_daily_gauss_center.mat');
end
end


function tf = isFreeGaussCenterModeLocal(rew)
tf = isstruct(rew) && isfield(rew, 'gauss_center_free') && ~isempty(rew.gauss_center_free) && ...
    logical(rew.gauss_center_free(1));
end


function tf = hasExplicitGaussCenterCoordsLocal(rew)
tf = isstruct(rew) && isfield(rew, 'gauss_center_coords') && ~isempty(rew.gauss_center_coords) && ...
    numel(rew.gauss_center_coords) >= 2 && all(isfinite(rew.gauss_center_coords(1:2)));
end


function tf = isCenterWithinPeakRadiusLocal(coords, max_peak_dist_norm)
coords = double(coords(1:2));
if any(~isfinite(coords)) || any(coords < 0) || any(coords > 1)
    tf = false;
    return
end
if ~isfinite(max_peak_dist_norm) || max_peak_dist_norm < 0
    tf = false;
    return
end
tf = norm(coords - [0.5, 0.5]) <= max_peak_dist_norm + 1e-12;
end


function value = getOptionalFieldLocal(s, fieldName, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);
end
end


function stimDir = localCurrentStimulusDirLocal(ex)
stimDir = '';
if isfield(ex, 'stim') && isstruct(ex.stim) && isfield(ex.stim, 'seq') && ...
        numel(ex.stim.seq) >= ex.j && ~isempty(ex.stim.seq{ex.j})
    stimDir = char(string(ex.stim.seq{ex.j}));
end
end


function [graph, info] = localResolveGraphTextureGeometryFromStimulusLocal(graph, stimDir)
info = struct();
info.autoResolved = false;
info.sourceDims = [NaN NaN];
info.sourceFile = "";

if ~isstruct(graph)
    return
end
autoTextureDims = true;
if isfield(graph, 'autoTextureDims') && ~isempty(graph.autoTextureDims)
    autoTextureDims = localScalarLogicalLocal(graph.autoTextureDims, true);
elseif isfield(graph, 'auto_texture_dims') && ~isempty(graph.auto_texture_dims)
    autoTextureDims = localScalarLogicalLocal(graph.auto_texture_dims, true);
end
if ~autoTextureDims || isempty(stimDir) || ~exist(stimDir, 'dir')
    return
end

[sourceDims, sourceFile] = localDetectSquareStimulusDimsLocal(stimDir);
info.sourceDims = sourceDims;
info.sourceFile = string(sourceFile);
if any(~isfinite(sourceDims)) || numel(sourceDims) < 2 || sourceDims(1) ~= sourceDims(2)
    return
end

oldTextureDims = localOptionalVectorFieldLocal(graph, 'texture_dims', [sourceDims(1), sourceDims(2)]);
if numel(oldTextureDims) < 2 || any(~isfinite(oldTextureDims(1:2))) || any(oldTextureDims(1:2) <= 0)
    oldTextureDims = [sourceDims(1), sourceDims(2)];
end
oldSizeMult = localOptionalScalarFieldLocal(graph, 'size_mult', 1);
if ~isfinite(oldSizeMult) || oldSizeMult <= 0
    oldSizeMult = 1;
end
oldRadius = localOptionalScalarFieldLocal(graph, 'radius', NaN);

oldScreenW = oldTextureDims(2) * oldSizeMult;
oldScreenH = oldTextureDims(1) * oldSizeMult;
newSizeMultW = oldScreenW / sourceDims(2);
newSizeMultH = oldScreenH / sourceDims(1);
newSizeMult = mean([newSizeMultW, newSizeMultH], 'omitnan');
if ~isfinite(newSizeMult) || newSizeMult <= 0
    return
end

oldRadiusScreenPx = oldRadius * oldSizeMult;
graph.texture_dim = sourceDims(1);
graph.texture_dims = sourceDims(:)';
graph.size_mult = newSizeMult;
if isfinite(oldRadiusScreenPx) && oldRadiusScreenPx > 0
    graph.radius = oldRadiusScreenPx / newSizeMult;
    if isfield(graph, 'radiusUnits') && localIsVisualDegUnitsLocal(graph.radiusUnits)
        graph.radiusOriginalTexturePx = graph.radius;
        graph.radiusReferenceTexturePx = graph.radius;
    end
end
graph.textureAutoResolved = true;
graph.textureAutoResolvedSourceFile = string(sourceFile);
info.autoResolved = true;
end


function [dims, sourceFile] = localDetectSquareStimulusDimsLocal(stimDir)
dims = [NaN NaN];
sourceFile = '';
matFiles = localCandidateStimulusMatFilesLocal(stimDir);
for i = 1:numel(matFiles)
    candidate = matFiles{i};
    try
        s = load(candidate);
    catch
        continue
    end
    img = localFirstNumericImageMatrixLocal(s);
    if isempty(img)
        continue
    end
    imgSize = size(img);
    dims = imgSize(1:2);
    if dims(1) ~= dims(2)
        continue
    end
    sourceFile = candidate;
    return
end
end


function matFiles = localCandidateStimulusMatFilesLocal(stimDir)
matFiles = {};
roots = {char(string(stimDir))};
[parentDir, leafName] = fileparts(char(string(stimDir)));
if ~isempty(regexp(leafName, '^noise\d+$', 'once')) && exist(parentDir, 'dir')
    roots{end+1} = parentDir; %#ok<AGROW>
end

for iRoot = 1:numel(roots)
    rootDir = roots{iRoot};
    matFiles = [matFiles, localMatFilesInDirLocal(fullfile(rootDir, 'full'))]; %#ok<AGROW>
    matFiles = [matFiles, localMatFilesInDirLocal(fullfile(rootDir, 'scramble'))]; %#ok<AGROW>
    mixDirs = dir(fullfile(rootDir, 'mix*'));
    mixDirs = mixDirs([mixDirs.isdir]);
    for i = 1:numel(mixDirs)
        matFiles = [matFiles, localMatFilesInDirLocal(fullfile(rootDir, mixDirs(i).name))]; %#ok<AGROW>
    end
    noiseDirs = dir(fullfile(rootDir, 'noise*'));
    noiseDirs = noiseDirs([noiseDirs.isdir]);
    for iNoise = 1:numel(noiseDirs)
        noiseRoot = fullfile(rootDir, noiseDirs(iNoise).name);
        matFiles = [matFiles, localMatFilesInDirLocal(fullfile(noiseRoot, 'full'))]; %#ok<AGROW>
        matFiles = [matFiles, localMatFilesInDirLocal(fullfile(noiseRoot, 'scramble'))]; %#ok<AGROW>
        noiseMixDirs = dir(fullfile(noiseRoot, 'mix*'));
        noiseMixDirs = noiseMixDirs([noiseMixDirs.isdir]);
        for iMix = 1:numel(noiseMixDirs)
            matFiles = [matFiles, localMatFilesInDirLocal(fullfile(noiseRoot, noiseMixDirs(iMix).name))]; %#ok<AGROW>
        end
    end
    matFiles = [matFiles, localMatFilesInDirLocal(rootDir)]; %#ok<AGROW>
end

if ~isempty(matFiles)
    [~, keepIdx] = unique(matFiles, 'stable');
    matFiles = matFiles(sort(keepIdx));
end
end


function matFiles = localMatFilesInDirLocal(dirName)
matFiles = {};
if ~exist(dirName, 'dir')
    return
end
files = dir(fullfile(dirName, '*.mat'));
files = files(~[files.isdir]);
for i = 1:numel(files)
    matFiles{end+1} = fullfile(dirName, files(i).name); %#ok<AGROW>
end
end


function img = localFirstNumericImageMatrixLocal(s)
img = [];
if ~isstruct(s)
    return
end
names = fieldnames(s);
isTextureField = cellfun(@(name) ~isempty(regexp(name, '_tp$', 'once')), names);
orderedNames = [names(isTextureField); names(~isTextureField)];
for i = 1:numel(orderedNames)
    value = s.(orderedNames{i});
    valueSize = size(value);
    if isnumeric(value) && ismatrix(value) && numel(valueSize) >= 2 && ...
            valueSize(1) > 1 && valueSize(2) > 1
        img = value;
        return
    end
end
end


function [graph, info] = localResolveGraphRadiusForDisplayLocal(graph, setup)
info = struct();
info.units = 'texturePx';
info.radiusDeg = NaN;
info.radiusTexturePx = NaN;
info.radiusScreenPx = NaN;
info.referenceMonitorWidth = NaN;
info.referenceViewingDistance = NaN;
info.referenceScreenWidthPx = NaN;

if ~isstruct(graph) || ~isfield(graph, 'radius') || isempty(graph.radius)
    return
end

radiusTexturePxInput = localScalarFieldValueLocal(graph.radius, NaN);
sizeMult = localOptionalScalarFieldLocal(graph, 'size_mult', 1);
if ~isfinite(radiusTexturePxInput) || radiusTexturePxInput <= 0 || ...
        ~isfinite(sizeMult) || sizeMult <= 0
    return
end

units = localOptionalTextFieldLocal(graph, 'radiusUnits', 'texturePx');
info.units = units;
if ~localIsVisualDegUnitsLocal(units)
    info.radiusTexturePx = radiusTexturePxInput;
    info.radiusScreenPx = radiusTexturePxInput * sizeMult;
    return
end

originalTexturePx = localOptionalScalarFieldLocal(graph, 'radiusOriginalTexturePx', NaN);
if ~isfinite(originalTexturePx) || originalTexturePx <= 0
    originalTexturePx = localOptionalScalarFieldLocal(graph, 'radiusReferenceTexturePx', radiusTexturePxInput);
end
if ~isfinite(originalTexturePx) || originalTexturePx <= 0
    originalTexturePx = radiusTexturePxInput;
end

refMonitorWidth = localOptionalScalarFieldLocal(graph, 'radiusReferenceMonitorWidth', 38.5);
refViewingDistance = localOptionalScalarFieldLocal(graph, 'radiusReferenceViewingDistance', setup.viewingDistance);
refScreenWidthPx = localOptionalScalarFieldLocal(graph, 'radiusReferenceScreenWidthPx', setup.screenRect(3));
radiusDeg = localOptionalScalarFieldLocal(graph, 'radiusDeg', NaN);
if ~isfinite(radiusDeg) || radiusDeg <= 0
    refDpp = localDegPerPixelLocal(refMonitorWidth, refViewingDistance, refScreenWidthPx);
    radiusDeg = originalTexturePx * sizeMult * refDpp;
end

currentScreenWidthPx = localSetupScreenWidthPxLocal(setup);
currentDpp = localDegPerPixelLocal(setup.monitorWidth, setup.viewingDistance, currentScreenWidthPx);
if ~isfinite(radiusDeg) || radiusDeg <= 0 || ~isfinite(currentDpp) || currentDpp <= 0
    error('runTrialTaskCoPsx:BadTargetRadiusDeg', ...
        'Could not resolve graph.radius in visual degrees. Check graph.radius* and setup monitor geometry fields.');
end

radiusTexturePx = radiusDeg / currentDpp / sizeMult;
if ~isfinite(radiusTexturePx) || radiusTexturePx <= 0
    error('runTrialTaskCoPsx:BadTargetRadiusPx', ...
        'Resolved graph.radius was invalid. Check graph.radiusDeg and setup monitor geometry fields.');
end

graph.radiusOriginalTexturePx = originalTexturePx;
graph.radiusReferenceTexturePx = originalTexturePx;
graph.radiusReferenceMonitorWidth = refMonitorWidth;
graph.radiusReferenceViewingDistance = refViewingDistance;
graph.radiusReferenceScreenWidthPx = refScreenWidthPx;
graph.radiusDeg = radiusDeg;
graph.radiusScreenPx = radiusTexturePx * sizeMult;
graph.radius = radiusTexturePx;

info.radiusDeg = radiusDeg;
info.radiusTexturePx = radiusTexturePx;
info.radiusScreenPx = graph.radiusScreenPx;
info.referenceMonitorWidth = refMonitorWidth;
info.referenceViewingDistance = refViewingDistance;
info.referenceScreenWidthPx = refScreenWidthPx;
end


function [rew, info] = localResolveRewardGaussianSigmaForDisplayLocal(rew, setup)
info = struct();
info.units = 'px';
info.sigmaPx = NaN;
info.sigmaDeg = NaN;

if ~isstruct(rew) || ~isfield(rew, 'gauss_sigma') || isempty(rew.gauss_sigma)
    return
end

sigmaInput = localScalarFieldValueLocal(rew.gauss_sigma, NaN);
if ~isfinite(sigmaInput) || sigmaInput <= 0
    return
end

units = localOptionalTextFieldLocal(rew, 'gauss_sigmaUnits', 'px');
currentScreenWidthPx = localSetupScreenWidthPxLocal(setup);
currentDpp = localDegPerPixelLocal(setup.monitorWidth, setup.viewingDistance, currentScreenWidthPx);

if localIsVisualDegUnitsLocal(units)
    sigmaDeg = localOptionalScalarFieldLocal(rew, 'gauss_sigmaDeg', sigmaInput);
    if ~isfinite(sigmaDeg) || sigmaDeg <= 0 || ~isfinite(currentDpp) || currentDpp <= 0
        error('runTrialTaskCoPsx:BadRewardGaussianSigmaDeg', ...
            'Could not resolve rew.gauss_sigma in visual degrees. Check rew.gauss_sigma* and setup monitor geometry fields.');
    end
    sigmaPx = sigmaDeg / currentDpp;

    rew.gauss_sigmaOriginal = sigmaInput;
    rew.gauss_sigmaUnitsOriginal = units;
    rew.gauss_sigma = sigmaPx;
    rew.gauss_sigmaUnits = 'px';
    rew.gauss_sigmaDeg = sigmaDeg;
    rew.gauss_sigmaPx = sigmaPx;
else
    sigmaPx = sigmaInput;
    sigmaDeg = NaN;
    if isfinite(currentDpp) && currentDpp > 0
        sigmaDeg = sigmaPx * currentDpp;
    end
    rew.gauss_sigma = sigmaPx;
    rew.gauss_sigmaUnits = 'px';
    rew.gauss_sigmaPx = sigmaPx;
    if ~isfield(rew, 'gauss_sigmaDeg') || isempty(rew.gauss_sigmaDeg) || ...
            ~isfinite(localScalarFieldValueLocal(rew.gauss_sigmaDeg, NaN))
        rew.gauss_sigmaDeg = sigmaDeg;
    else
        sigmaDeg = localScalarFieldValueLocal(rew.gauss_sigmaDeg, sigmaDeg);
    end
end

info.units = rew.gauss_sigmaUnits;
info.sigmaPx = sigmaPx;
info.sigmaDeg = sigmaDeg;
end


function tf = localIsVisualDegUnitsLocal(units)
units = lower(strtrim(localCharTextLocal(units)));
tf = any(strcmp(units, {'deg', 'dva', 'visdeg', 'visualdeg', 'visualdegrees'}));
end


function value = localOptionalScalarFieldLocal(s, fieldName, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = localScalarFieldValueLocal(s.(fieldName), defaultValue);
end
end


function value = localOptionalVectorFieldLocal(s, fieldName, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    rawValue = s.(fieldName);
    if isnumeric(rawValue) || islogical(rawValue)
        value = double(rawValue(:)');
    elseif iscell(rawValue) && ~isempty(rawValue)
        cellValue = cellfun(@(x) localScalarFieldValueLocal(x, NaN), rawValue);
        value = double(cellValue(:)');
    end
end
end


function value = localScalarFieldValueLocal(rawValue, defaultValue)
value = defaultValue;
if isnumeric(rawValue) || islogical(rawValue)
    rawValue = double(rawValue);
    if ~isempty(rawValue)
        value = rawValue(1);
    end
elseif ischar(rawValue) || isstring(rawValue)
    parsedValue = str2double(char(rawValue));
    if isfinite(parsedValue)
        value = parsedValue;
    end
end
end


function tf = localScalarLogicalLocal(rawValue, defaultValue)
tf = logical(defaultValue);
if isempty(rawValue)
    return
end
if isnumeric(rawValue) || islogical(rawValue)
    candidate = double(rawValue(1));
    if isfinite(candidate)
        tf = candidate ~= 0;
    end
elseif ischar(rawValue) || isstring(rawValue) || iscell(rawValue)
    text = lower(strtrim(localCharTextLocal(rawValue)));
    if any(strcmp(text, {'true', 'on', 'yes', '1'}))
        tf = true;
    elseif any(strcmp(text, {'false', 'off', 'no', '0'}))
        tf = false;
    end
end
end


function value = localOptionalTextFieldLocal(s, fieldName, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = localCharTextLocal(s.(fieldName));
end
end


function text = localCharTextLocal(value)
if ischar(value)
    text = value;
elseif isstring(value)
    text = char(value(1));
elseif iscell(value) && ~isempty(value)
    text = localCharTextLocal(value{1});
else
    text = char(value);
end
end


function dpp = localDegPerPixelLocal(monitorWidthCm, viewingDistanceCm, screenWidthPx)
dpp = NaN;
monitorWidthCm = double(monitorWidthCm);
viewingDistanceCm = double(viewingDistanceCm);
screenWidthPx = double(screenWidthPx);
if isfinite(monitorWidthCm) && monitorWidthCm > 0 && ...
        isfinite(viewingDistanceCm) && viewingDistanceCm > 0 && ...
        isfinite(screenWidthPx) && screenWidthPx > 0
    dpp = atan((monitorWidthCm / 2) / viewingDistanceCm) * 180 / pi / (screenWidthPx / 2);
end
end


function screenWidthPx = localSetupScreenWidthPxLocal(setup)
screenWidthPx = NaN;
if isstruct(setup) && isfield(setup, 'screenRect') && numel(setup.screenRect) >= 3
    screenRect = double(setup.screenRect);
    screenWidthPx = screenRect(3);
end
end


function bound = localTargetPositionBoundLocal(graph, hiddenFrac)
bound = 1;
if nargin < 2 || isempty(hiddenFrac)
    return
end
hiddenFrac = max(0, double(hiddenFrac));
hiddenFrac = hiddenFrac(1);
if hiddenFrac <= 0 || ~isfinite(hiddenFrac)
    return
end
if ~isstruct(graph) || ~isfield(graph, 'texture_dims') || ~isfield(graph, 'radius')
    return
end
texDims = double(graph.texture_dims(:)');
if isempty(texDims) || ~all(isfinite(texDims))
    return
end
if numel(texDims) < 2
    texDims = [texDims(1), texDims(1)];
end
radius = double(graph.radius);
visibleRange = min((texDims(1:2) / 2) - radius);
if isfinite(radius) && radius > 0 && isfinite(visibleRange) && visibleRange > 0
    bound = 1 + (2 * radius * hiddenFrac) / visibleRange;
end
end


function tf = isMatlabWindowFocusedLocal()
% Return true only when MATLAB desktop/main window is focused and not minimized.
% If focus cannot be determined (e.g., no desktop/Java), default to true.
tf = true;
if ~usejava('desktop') || ~desktop('-inuse')
    return
end
try
    desktopObj = com.mathworks.mde.desk.MLDesktop.getInstance;
    mainFrame = desktopObj.getMainFrame;
    if ~isempty(mainFrame)
        isFocused = logical(mainFrame.isActive());
        frameState = mainFrame.getExtendedState();
        isMinimized = bitand(frameState, java.awt.Frame.ICONIFIED) ~= 0;
        tf = isFocused && ~isMinimized;
    end
catch
    tf = true;
end
end
