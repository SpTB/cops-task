function [stimTextures, targPositions, timingInfo] = makeStimulusCoPsx(setup, ctl, dirs, posT, graph, trialNo)
% creates Continuous Psychophysics stimuli for the experiment
% based on syth_mask_test.m stimulus generation code
% Restructured version for better integration with VSgui framework
%
% inputs:
% setup: display setup structure
% ctl: control parameters for CoPs task
% dirs: directories with stimuli
% posT: target positions structure
% graph: graphical parameters
%
% outputs:
% stimTextures: preloaded texture handles
% targPositions: structure with target positions for each step
% timingInfo: lightweight profiling summary for stimulus generation
%
% history
% 11/12/25: Created from makeStimulus.m + syth_mask_test.m integration
% 11/25/25: Restructured for better error handling and framework integration
% 12/02/25: Added extra texture at the end (which is the same as the initial one, but with circles, to show in the prego period)
if nargin < 6 || isempty(trialNo)
    trialNo = NaN;
end

% Initialize outputs
totalTimer = tic;
stimTextures = [];
targPositions = struct();
timingInfo = struct();

% Get parameters from input structures
size_mult = graph.size_mult;
radius = graph.radius;
if isfield(ctl, 'targetHiddenBoundsFrac') && ~isempty(ctl.targetHiddenBoundsFrac)
    target_hidden_bounds_frac = double(ctl.targetHiddenBoundsFrac);
    target_hidden_bounds_frac = target_hidden_bounds_frac(1);
    if ~isfinite(target_hidden_bounds_frac)
        target_hidden_bounds_frac = 0;
    end
    target_hidden_bounds_frac = max(0, target_hidden_bounds_frac);
else
    target_hidden_bounds_frac = 0;
end
if isfield(graph, 'target_visibility')
    target_visibility = min(max(graph.target_visibility, 0), 1);
else
    target_visibility = 1;
end
if isfield(graph, 'target_mask_sigma_mult') && isfinite(graph.target_mask_sigma_mult) && graph.target_mask_sigma_mult > 0
    target_mask_sigma_mult = double(graph.target_mask_sigma_mult);
else
    target_mask_sigma_mult = 1;
end
background_noise_lvl = graph.background_noise_lvl;
trial_log_background_noise_lvl = localGetNumericScalarField(graph, 'trialLogBackgroundNoiseLvl', background_noise_lvl);
trial_log_target_visibility = localGetNumericScalarField(graph, 'trialLogTargetVisibility', target_visibility);
trial_log_run_phase = localGetTextField(graph, 'trialLogRunPhase', '');
full_as_background = graph.full_as_background;
fixed_background_trial = (background_noise_lvl == 0);
no_background_trial = (background_noise_lvl == -1);
dynamic_background_trial = isfinite(background_noise_lvl) && ...
    background_noise_lvl ~= 0 && background_noise_lvl ~= -1;
circle_target_loc = ctl.circle_target_loc;
target_num = ctl.target_num;
nsteps = ctl.nsteps;
if isfield(ctl, 'coherence')
    target_coherence = ctl.coherence;
else
    target_coherence = 1;
end
random_rotate_textures = localGetLogicalScalarField(graph, 'random_rotate_textures', false);
random_rotate_target_texture = localGetLogicalScalarField(graph, 'random_rotate_target_texture', random_rotate_textures);
random_rotate_background_texture = localGetLogicalScalarField(graph, 'random_rotate_background_texture', random_rotate_textures);
scheduled_texture_rotation_k = localGetRotationKField(graph, 'texture_rotation_k', NaN);
dynamic_background_normalization = localResolveDynamicBackgroundNormalizationMode(graph);
target_mean_normalization = localResolveTargetMeanNormalizationMode(graph);
target_mean_normalization_sd = localGetNumericScalarField(graph, 'target_mean_normalization_sd', 3);
if ~isfinite(target_mean_normalization_sd) || target_mean_normalization_sd <= 0
    target_mean_normalization_sd = 3;
end
scale_texture_on_draw = localGetLogicalScalarField(graph, 'scaleTextureOnDraw', true);
timingInfo = localInitStimTimingInfoLocal(nsteps, trialNo, scale_texture_on_draw);

% Get target positions
cx = posT.x1;
cy = posT.y1;
if target_num == 2
    cx2 = posT.x2;
    cy2 = posT.y2;
end

% Window setup
window_size = setup.screenRect;

setupTimer = tic;

% Resolve stimulus directory robustly for both mixed-noise and fixed
% background trials.
%
% Expected layout:
%   <root>/<stimulus_id>/noise5
%   <root>/<stimulus_id>/noise30
%   ...
%
% Trial-level noise selection chooses the inner noise folder. A sampled
% noise levels 0 and -1 mean "use fixed/no-background protocol", not "open
% a noise0/noise-1 directory". In those cases we still need a real stimulus
% folder, so we fall back to a concrete inner noise folder and then override
% the background behavior downstream.
dir_parts = strsplit(dirs, filesep);
last_part = dir_parts{end};

% Accept either a stimulus folder (.../desert1) or an already-selected
% inner noise folder (.../desert1/noise5) and normalize to the stimulus
% folder before selecting the per-trial noise directory.
root_noise_dir_name = '';
if ~isempty(regexp(last_part, '^noise\d+$', 'once'))
    root_noise_dir_name = last_part;
    dirs = fileparts(dirs);
end

available_noise_dirs = dir(fullfile(dirs, 'noise*'));
available_noise_dirs = available_noise_dirs([available_noise_dirs.isdir]);
available_noise_names = {available_noise_dirs.name};

if fixed_background_trial || no_background_trial
    if ~isempty(root_noise_dir_name) && ismember(root_noise_dir_name, available_noise_names)
        noise_dir_name = root_noise_dir_name;
    elseif ismember('noise1', available_noise_names)
        noise_dir_name = 'noise1';
    elseif ismember('noise5', available_noise_names)
        noise_dir_name = 'noise5';
    elseif ~isempty(available_noise_names)
        noise_dir_name = available_noise_names{1};
    else
        error('No inner noise directories found for fixed background trial: %s', dirs);
    end
    dirs = fullfile(dirs, noise_dir_name);
else
    noise_dir_name = ['noise', num2str(background_noise_lvl)];
    if ismember(noise_dir_name, available_noise_names)
        dirs = fullfile(dirs, noise_dir_name);
    else
        error('Requested noise directory does not exist: %s', fullfile(dirs, noise_dir_name));
    end
end




% Validate input directory
if isempty(dirs) || ~exist(dirs, 'dir')
    error('Stimulus directory does not exist: %s', dirs);
end

% Get file lists
% full_list = dir(fullfile(dirs, 'full', 'full*.mat'));
% scramble_list = dir(fullfile(dirs, 'scramble', 'scramble*.mat'));
if full_as_background
    target_word = 'scramble';
    background_word = 'full';
else
    target_word = 'full';
    background_word = 'scramble';
end

[target_dir_name, target_file_prefix] = resolveTargetCoherenceFolderLocal(dirs, target_word, target_coherence);

target_dir = fullfile(dirs, target_dir_name);
background_dir = fullfile(dirs, background_word);
target_list = dir(fullfile(target_dir, [target_file_prefix,'*.mat']));
background_list = dir(fullfile(background_dir, [background_word,'*.mat']));

% % Check if we have enough files
% if length(target_list) < nsteps || length(background_list) < nsteps
%     error('Not enough stimulus files. Need %d, have %d target and %d background files', ...
%         nsteps, length(target_list), length(background_list));
% end

% xxValidate that stimulus files exist (indices will wrap when nsteps is larger)
num_target_files = length(target_list);
num_background_files = length(background_list);
if num_target_files == 0 || num_background_files == 0
    error(['No stimulus files found. Have %d target and %d background files.\n' ...
        'Target folder: %s\nBackground folder: %s'], ...
        num_target_files, num_background_files, target_dir, background_dir);
end
target_files = cellfun(@(name) fullfile(target_dir, name), {target_list.name}, 'UniformOutput', false);
background_files = cellfun(@(name) fullfile(background_dir, name), {background_list.name}, 'UniformOutput', false);
timingInfo.setupSec = toc(setupTimer);
timingInfo.resolvedStimDir = char(string(dirs));
timingInfo.targetDir = char(string(target_dir));
timingInfo.backgroundDir = char(string(background_dir));
timingInfo.numTargetFiles = num_target_files;
timingInfo.numBackgroundFiles = num_background_files;


% Initialize arrays for textures
out_texs_cell = {};
targPositions = struct();
dynamic_background_reference_stats = struct();
dynamic_composite_reference_stats = struct();

% Generate stimuli for each step
for j = 1:nsteps+1 %add last image being same as first but with circles
    stepTimer = tic;
    
    % if j<=nsteps
    %     i = j;
    %     use_circles = circle_target_loc;
    % elseif j==(nsteps+1) % last step is done on first image
    %     i = 1;
    %     use_circles = 1;
    % endxx
    
     if j<=nsteps
        step_idx = j;
        target_idx = mod(j-1, num_target_files) + 1;
        use_circles = circle_target_loc;
    elseif j==(nsteps+1) % last step is done on first image
        step_idx = 1;
        target_idx = 1;
        use_circles = 1;
    end

    % Load texture files
   % target_file = fullfile(dirs, target_word, target_list(i).name);
    
    % if fixed_background_trial
    %     background_file = fullfile(dirs, background_word, background_list(1).name);
    % else
    %     background_file = fullfile(dirs, background_word, background_list(i).name);
    % end
    % xx

    if fixed_background_trial || no_background_trial
        background_idx = 1;
    else
        background_idx = mod(j-1, num_background_files) + 1;
    end

    loadTimer = tic;
    target_file = target_files{target_idx};
    background_file = background_files{background_idx};
    [targi, targetCacheHit] = loadStimulusFileCachedLocal(target_file);
    [backi, backgroundCacheHit] = loadStimulusFileCachedLocal(background_file);
    timingInfo.stepLoadSec(j) = toc(loadTimer);
    timingInfo.stepTargetCacheHit(j) = targetCacheHit;
    timingInfo.stepBackgroundCacheHit(j) = backgroundCacheHit;
    composeTimer = tic;

    extractTimer = tic;
    % Validate loaded data
    if ~isfield(backi, [background_word,'_tp'])
        error('Invalid stimulus file format in step %d', step_idx);
    end
    target_img = extractTargetImageLocal(targi, target_word, target_dir_name);
    background_img = backi.([background_word,'_tp']);
    if isfinite(scheduled_texture_rotation_k)
        target_rotation_k = scheduled_texture_rotation_k;
        background_rotation_k = scheduled_texture_rotation_k;
    else
        target_rotation_k = localSampleTextureRotationK(random_rotate_target_texture);
        background_rotation_k = localSampleTextureRotationK(random_rotate_background_texture);
    end
    if target_rotation_k ~= 0
        target_img = rot90(target_img, target_rotation_k);
    end
    if background_rotation_k ~= 0
        background_img = rot90(background_img, background_rotation_k);
    end
    if ~isequal(size(target_img), size(background_img))
        error(['Target/background texture sizes differ after rotation in step %d. ' ...
            'Independent 90-degree rotations require square source textures.'], step_idx);
    end
    timingInfo.stepExtractSec(j) = toc(extractTimer);

    backgroundPrepTimer = tic;
    if no_background_trial
        background_img = localGrayBackgroundLikeTarget(target_img);
    else
        background_img = matchImageMeanLocal(background_img, target_img);
    end
    if dynamic_background_trial && strcmp(dynamic_background_normalization, 'backgroundStats')
        if ~isfield(dynamic_background_reference_stats, 'mean')
            dynamic_background_reference_stats = localImageStats(background_img);
        end
        background_img = localMatchImageStats(background_img, dynamic_background_reference_stats);
    end
    timingInfo.stepBackgroundPrepSec(j) = toc(backgroundPrepTimer);

    maskTimer = tic;
    % Get image dimensions for coordinate conversion
    [img_height, img_width] = size(target_img);
    % Convert normalized coordinates to pixel coordinates
    [pixel_x1, pixel_y1] = pix_norm(cx(step_idx), cy(step_idx), img_width, img_height, radius, target_hidden_bounds_frac);
    % Create Gaussian masks with converted coordinates
    mask_sigma = (radius / 3) * target_mask_sigma_mult;
    gaussian_mask = target_visibility * gauss_mask(target_img, pixel_x1, pixel_y1, radius, mask_sigma);
    inv_mask = 1 - gaussian_mask;
    if target_num == 2
        [pixel_x2, pixel_y2] = pix_norm(cx2(step_idx), cy2(step_idx), img_width, img_height, radius, target_hidden_bounds_frac);
        gaussian_mask2 = target_visibility * gauss_mask(target_img, pixel_x2, pixel_y2, radius, mask_sigma);
        inv_mask2 = 1 - gaussian_mask2;
    end
    timingInfo.stepMaskSec(j) = toc(maskTimer);
    % % Create Gaussian masks
    % gaussian_mask = gauss_mask(fulli.full_tp, cx(i), cy(i), radius);
    % inv_mask = 1 - gaussian_mask;
    %
    % if target_num == 2
    %     gaussian_mask2 = gauss_mask(fulli.full_tp, cx2(i), cy2(i), radius);
    %     inv_mask2 = 1 - gaussian_mask2;
    % end
    
    % Create target and background using a normalized convex blend:
    % lower target_visibility weakens the target contribution but keeps
    % the local target/background weights summing to 1.
    target_img1 = target_img;
    target_mean_norm_delta1 = NaN;
    target_mean_norm_delta2 = NaN;
    backgroundMeanForTargetNorm = NaN;
    if strcmp(target_mean_normalization, 'localBackgroundMean3SD')
        backgroundMeanForTargetNorm = localFiniteMeanLocal(background_img(:));
    end
    targetMeanNormTimer = tic;
    if strcmp(target_mean_normalization, 'localBackgroundMean3SD')
        [target_img1, target_mean_norm_delta1] = localMatchTargetRegionMeanToBackground( ...
            target_img, background_img, pixel_x1, pixel_y1, mask_sigma, target_mean_normalization_sd, ...
            backgroundMeanForTargetNorm);
    end
    timingInfo.stepTargetMeanNormSec(j) = toc(targetMeanNormTimer);
    if target_num == 2
        target_img2 = target_img;
        targetMeanNormTimer = tic;
        if strcmp(target_mean_normalization, 'localBackgroundMean3SD')
            [target_img2, target_mean_norm_delta2] = localMatchTargetRegionMeanToBackground( ...
                target_img, background_img, pixel_x2, pixel_y2, mask_sigma, target_mean_normalization_sd, ...
                backgroundMeanForTargetNorm);
        end
        timingInfo.stepTargetMeanNormSec(j) = timingInfo.stepTargetMeanNormSec(j) + toc(targetMeanNormTimer);
    end

    blendTimer = tic;
    target = target_img1 .* gaussian_mask;
    background = background_img .* inv_mask;
    if target_num == 2
        target2 = target_img2 .* gaussian_mask2;
        background = background.* inv_mask2;
    end
    
    
    % Overlay images
    if target_num == 2
        comb_tex_raw = background + target + target2;
    else
        comb_tex_raw = background + target;
    end
    timingInfo.stepBlendSec(j) = toc(blendTimer);

    compositeNormTimer = tic;
    if dynamic_background_trial && strcmp(dynamic_background_normalization, 'compositeStats')
        if ~isfield(dynamic_composite_reference_stats, 'mean')
            dynamic_composite_reference_stats = localImageStats(comb_tex_raw);
        end
        comb_tex_raw = localMatchImageStats(comb_tex_raw, dynamic_composite_reference_stats);
    end
    timingInfo.stepCompositeNormSec(j) = toc(compositeNormTimer);

    comb_tex = comb_tex_raw;
    % Add circle indicators if requested
    circleTimer = tic;
    if use_circles
        if target_num == 2
            % Use the converted pixel coordinates for circles
            comb_tex = circles_mat(comb_tex, pixel_x1, pixel_y1, pixel_x2, pixel_y2, radius, 1, 1);
        else
            % Use the converted pixel coordinates for circle
            comb_tex = circle_mat(comb_tex, pixel_x1, pixel_y1, radius, 1, 1);
        end
    end
    timingInfo.stepCircleSec(j) = toc(circleTimer);

    resizeTimer = tic;
    sourceTexH = size(comb_tex, 1);
    sourceTexW = size(comb_tex, 2);

    % Keep textures at source size when requested. PTB can scale them at
    % draw time, which avoids expensive per-step MATLAB resizing.
    if scale_texture_on_draw
        comb_tex_res = comb_tex;
        drawnTexH = sourceTexH * size_mult;
        drawnTexW = sourceTexW * size_mult;
        if isfield(graph, 'texture_dims') && numel(graph.texture_dims) >= 2
            textureDims = double(graph.texture_dims(:)');
            if all(isfinite(textureDims(1:2))) && all(textureDims(1:2) > 0)
                drawnTexH = textureDims(1) * size_mult;
                drawnTexW = textureDims(2) * size_mult;
            end
        end
    else
        comb_tex_res = imresize(comb_tex, size_mult);
        drawnTexH = size(comb_tex_res, 1);
        drawnTexW = size(comb_tex_res, 2);
    end
    drawScaleX = drawnTexW / sourceTexW;
    drawScaleY = drawnTexH / sourceTexH;
    timingInfo.stepResizeSec(j) = toc(resizeTimer);

    % Texture is drawn centered on screen in DrawTexture; convert target
    % coordinates to absolute screen coordinates in that drawn frame.
    xshift = (window_size(3) - drawnTexW)/2;
    yshift = (window_size(4) - drawnTexH)/2;

    do_dynamic_background_normalization = dynamic_background_trial && ...
        ~strcmp(dynamic_background_normalization, 'none');
    rangeNormTimer = tic;
    if do_dynamic_background_normalization
        if strcmp(dynamic_background_normalization, 'compositeRange')
            comb_tex_res = localNormalizeTextureRange(comb_tex_res, 1, 254);
        end
    end
    timingInfo.stepRangeNormSec(j) = toc(rangeNormTimer);

    clipRgbTimer = tic;
    % Keep source luminance stable unless explicitly restoring the old
    % dynamic-background per-step normalization for comparison.
    comb_tex_res = clip(comb_tex_res, 1, 254);
    if max(comb_tex_res(:))>254
        % error('too white')
        keyboard
    elseif min(comb_tex_res(:)) < 1
        % error('too black')
        keyboard
    end
    % Create texture
    %tex_handle = Screen('MakeTexture', setup.window, comb_tex_res);
    %xx new: grayscale
    % Force grayscale textures to explicit RGB triplets so they remain
    % achromatic even when the display is configured in RGB mode for
    % overlay usage.
    tex_img = uint8(round(comb_tex_res));
    if ndims(tex_img) == 2 || (ndims(tex_img) == 3 && size(tex_img,3) == 1)
        tex_img = repmat(tex_img, 1, 1, 3);
    end
    timingInfo.stepClipRgbSec(j) = toc(clipRgbTimer);

    timingInfo.stepComposeSec(j) = toc(composeTimer);
    makeTextureTimer = tic;
    tex_handle = Screen('MakeTexture', setup.window, tex_img);
    timingInfo.stepMakeTextureSec(j) = toc(makeTextureTimer);

    if tex_handle <= 0
        error('Failed to create texture for step %d', step_idx);
    end
    
    out_texs_cell{end+1} = tex_handle;
    
    % % Store target positions (convert to screen coordinates)
    % targPositions(i).targ1.pos_abs = [window_size(1) + cx(i)*size_mult, ...
    %     window_size(2) + cy(i)*size_mult];
    % if target_num == 2
    %     targPositions(i).targ2.pos_abs = [window_size(1) + cx2(i)*size_mult, ...
    %         window_size(2) + cy2(i)*size_mult];
    % end
    
    % Store target positions (convert normalized to screen coordinates)
    % First convert to image pixel coordinates, then to screen coordinates
    % targPositions(j).targ1.pos_abs = [window_size(1) + pixel_x1*size_mult, ...
    %     window_size(2) + pixel_y1*size_mult];
    targPositions(j).targ1.pos_abs = [window_size(1) + xshift + pixel_x1*drawScaleX, ...
        window_size(2) + yshift + pixel_y1*drawScaleY];

    if target_num == 2
        % targPositions(j).targ2.pos_abs = [window_size(1) + pixel_x2*size_mult, ...
        %     window_size(2) + pixel_y2*size_mult];
        targPositions(j).targ2.pos_abs = [window_size(1) + xshift + pixel_x2*drawScaleX, ...
            window_size(2) + yshift + pixel_y2*drawScaleY];

    end
    % Also store the normalized coordinates for reference
    % targPositions(j).targ1.norm_pos = [cx(i), cy(i)];
    % if target_num == 2
    %     targPositions(j).targ2.norm_pos = [cx2(i), cy2(i)];
    % end
    % % Store additional info
    % targPositions(j).step = i;
    % targPositions(j).cx = cx(i);
    % targPositions(j).cy = cy(i);
    % if target_num == 2
    %     targPositions(j).cx2 = cx2(i);
    %     targPositions(j).cy2 = cy2(i);
    % end
    % 
    % fprintf('Step %d/%d created\n', i, nsteps);xx
    % Also store the normalized coordinates for reference
    targPositions(j).targ1.norm_pos = [cx(step_idx), cy(step_idx)];
    if target_num == 2
        targPositions(j).targ2.norm_pos = [cx2(step_idx), cy2(step_idx)];
    end
    % Store additional info
    targPositions(j).step = j;
    targPositions(j).image_idx = target_idx;
    targPositions(j).targetRotationDeg = 90 * target_rotation_k;
    targPositions(j).backgroundRotationDeg = 90 * background_rotation_k;
    targPositions(j).dynamicBackgroundNormalization = double(do_dynamic_background_normalization);
    targPositions(j).dynamicBackgroundNormalizationMode = dynamic_background_normalization;
    targPositions(j).targetMeanNormalizationMode = target_mean_normalization;
    targPositions(j).targetMeanNormalizationSD = target_mean_normalization_sd;
    targPositions(j).targetMeanNormalizationDelta1 = target_mean_norm_delta1;
    targPositions(j).targetMeanNormalizationDelta2 = target_mean_norm_delta2;
    targPositions(j).scaleTextureOnDraw = double(scale_texture_on_draw);
    targPositions(j).drawScaleX = drawScaleX;
    targPositions(j).drawScaleY = drawScaleY;
    targPositions(j).cx = cx(step_idx);
    targPositions(j).cy = cy(step_idx);
    if target_num == 2
        targPositions(j).cx2 = cx2(step_idx);
        targPositions(j).cy2 = cy2(step_idx);
    end
    
    if mod(j, 100) == 0
        if isfinite(trialNo)
            fprintf('Step %d/%d created (trial %d; bg %g; vis %g; %s)\n', ...
                j, nsteps, trialNo, trial_log_background_noise_lvl, ...
                trial_log_target_visibility, trial_log_run_phase);
        else
            fprintf('Step %d/%d created\n', j, nsteps);
        end
    end

    
    % catch err
    %     fprintf(2, 'Error creating stimulus step %d: %s\n', i, err.message);
    %     % Continue with next step if possible
    %     continue;
    % end
    timingInfo.stepTotalSec(j) = toc(stepTimer);
end

% Convert cell array to numeric array and preload textures
if ~isempty(out_texs_cell)
    try
        all_tex_handles = cell2mat(out_texs_cell);
        preloadTimer = tic;
        [resident, texidresident] = Screen('PreloadTextures', setup.window, all_tex_handles);
        timingInfo.preloadSec = toc(preloadTimer);
        timingInfo.preloadResident = resident;
        
        % success logging removed to reduce console overhead
        
        % Return preloaded textures
        stimTextures = all_tex_handles;
        
    catch err
        fprintf(2, 'Error preloading textures: %s\n', err.message);
        % Return individual textures if preloading fails
        stimTextures = out_texs_cell;
    end
else
    warning('No textures were created successfully');
    stimTextures = [];
end

timingInfo.nTextures = numel(out_texs_cell);
timingInfo.totalSec = toc(totalTimer);
timingInfo = localFinalizeStimTimingInfoLocal(timingInfo);

% completion logging removed to reduce console overhead

end


function timingInfo = localInitStimTimingInfoLocal(nsteps, trialNo, scaleTextureOnDraw)
nFrames = nsteps + 1;
timingInfo = struct();
timingInfo.trialNo = trialNo;
timingInfo.nSteps = nsteps;
timingInfo.nFrames = nFrames;
timingInfo.scaleTextureOnDraw = double(scaleTextureOnDraw);
timingInfo.setupSec = NaN;
timingInfo.stepLoadSec = NaN(1, nFrames);
timingInfo.stepComposeSec = NaN(1, nFrames);
timingInfo.stepExtractSec = NaN(1, nFrames);
timingInfo.stepBackgroundPrepSec = NaN(1, nFrames);
timingInfo.stepMaskSec = NaN(1, nFrames);
timingInfo.stepTargetMeanNormSec = NaN(1, nFrames);
timingInfo.stepBlendSec = NaN(1, nFrames);
timingInfo.stepCompositeNormSec = NaN(1, nFrames);
timingInfo.stepCircleSec = NaN(1, nFrames);
timingInfo.stepResizeSec = NaN(1, nFrames);
timingInfo.stepRangeNormSec = NaN(1, nFrames);
timingInfo.stepClipRgbSec = NaN(1, nFrames);
timingInfo.stepMakeTextureSec = NaN(1, nFrames);
timingInfo.stepTotalSec = NaN(1, nFrames);
timingInfo.stepTargetCacheHit = false(1, nFrames);
timingInfo.stepBackgroundCacheHit = false(1, nFrames);
timingInfo.preloadSec = NaN;
timingInfo.totalSec = NaN;
timingInfo.nTextures = 0;
end


function timingInfo = localFinalizeStimTimingInfoLocal(timingInfo)
timingInfo.totalLoadSec = localFiniteSumLocal(timingInfo.stepLoadSec);
timingInfo.totalComposeSec = localFiniteSumLocal(timingInfo.stepComposeSec);
timingInfo.totalExtractSec = localFiniteSumLocal(timingInfo.stepExtractSec);
timingInfo.totalBackgroundPrepSec = localFiniteSumLocal(timingInfo.stepBackgroundPrepSec);
timingInfo.totalMaskSec = localFiniteSumLocal(timingInfo.stepMaskSec);
timingInfo.totalTargetMeanNormSec = localFiniteSumLocal(timingInfo.stepTargetMeanNormSec);
timingInfo.totalBlendSec = localFiniteSumLocal(timingInfo.stepBlendSec);
timingInfo.totalCompositeNormSec = localFiniteSumLocal(timingInfo.stepCompositeNormSec);
timingInfo.totalCircleSec = localFiniteSumLocal(timingInfo.stepCircleSec);
timingInfo.totalResizeSec = localFiniteSumLocal(timingInfo.stepResizeSec);
timingInfo.totalRangeNormSec = localFiniteSumLocal(timingInfo.stepRangeNormSec);
timingInfo.totalClipRgbSec = localFiniteSumLocal(timingInfo.stepClipRgbSec);
timingInfo.totalMakeTextureSec = localFiniteSumLocal(timingInfo.stepMakeTextureSec);
timingInfo.totalStepSec = localFiniteSumLocal(timingInfo.stepTotalSec);
timingInfo.meanStepLoadSec = localFiniteMeanLocal(timingInfo.stepLoadSec);
timingInfo.meanStepComposeSec = localFiniteMeanLocal(timingInfo.stepComposeSec);
timingInfo.meanStepExtractSec = localFiniteMeanLocal(timingInfo.stepExtractSec);
timingInfo.meanStepBackgroundPrepSec = localFiniteMeanLocal(timingInfo.stepBackgroundPrepSec);
timingInfo.meanStepMaskSec = localFiniteMeanLocal(timingInfo.stepMaskSec);
timingInfo.meanStepTargetMeanNormSec = localFiniteMeanLocal(timingInfo.stepTargetMeanNormSec);
timingInfo.meanStepBlendSec = localFiniteMeanLocal(timingInfo.stepBlendSec);
timingInfo.meanStepCompositeNormSec = localFiniteMeanLocal(timingInfo.stepCompositeNormSec);
timingInfo.meanStepCircleSec = localFiniteMeanLocal(timingInfo.stepCircleSec);
timingInfo.meanStepResizeSec = localFiniteMeanLocal(timingInfo.stepResizeSec);
timingInfo.meanStepRangeNormSec = localFiniteMeanLocal(timingInfo.stepRangeNormSec);
timingInfo.meanStepClipRgbSec = localFiniteMeanLocal(timingInfo.stepClipRgbSec);
timingInfo.meanStepMakeTextureSec = localFiniteMeanLocal(timingInfo.stepMakeTextureSec);
timingInfo.meanStepTotalSec = localFiniteMeanLocal(timingInfo.stepTotalSec);
timingInfo.fracTargetCacheHit = mean(double(timingInfo.stepTargetCacheHit));
timingInfo.fracBackgroundCacheHit = mean(double(timingInfo.stepBackgroundCacheHit));
end


function value = localFiniteSumLocal(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    value = sum(x);
end
end


function value = localFiniteMeanLocal(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    value = mean(x);
end
end


function value = localGetLogicalScalarField(s, fieldName, defaultValue)
value = defaultValue;
if ~isstruct(s) || ~isfield(s, fieldName) || isempty(s.(fieldName))
    return
end

rawValue = s.(fieldName);
if islogical(rawValue)
    value = logical(rawValue(1));
elseif isnumeric(rawValue)
    value = isfinite(rawValue(1)) && rawValue(1) ~= 0;
elseif ischar(rawValue) || isstring(rawValue)
    textValue = lower(strtrim(char(string(rawValue))));
    value = ismember(textValue, {'1','true','yes','on','random','rotate'});
end
end


function value = localGetNumericScalarField(s, fieldName, defaultValue)
value = defaultValue;
if ~isstruct(s) || ~isfield(s, fieldName) || isempty(s.(fieldName))
    return
end

rawValue = s.(fieldName);
if isnumeric(rawValue) || islogical(rawValue)
    rawValue = double(rawValue);
    if ~isempty(rawValue) && isfinite(rawValue(1))
        value = rawValue(1);
    end
elseif ischar(rawValue) || isstring(rawValue)
    parsedValue = str2double(char(string(rawValue)));
    if isfinite(parsedValue)
        value = parsedValue;
    end
end
end


function value = localGetRotationKField(s, fieldName, defaultValue)
value = defaultValue;
rawValue = localGetNumericScalarField(s, fieldName, defaultValue);
if isfinite(rawValue)
    value = mod(round(rawValue), 4);
end
end


function value = localGetTextField(s, fieldName, defaultValue)
value = defaultValue;
if ~isstruct(s) || ~isfield(s, fieldName) || isempty(s.(fieldName))
    return
end
rawValue = s.(fieldName);
if ischar(rawValue)
    value = rawValue;
elseif iscell(rawValue) && ~isempty(rawValue)
    value = char(rawValue{1});
else
    value = char(rawValue);
end
end


function mode = localResolveDynamicBackgroundNormalizationMode(graph)
mode = 'none';
if ~isstruct(graph)
    return
end

if isfield(graph, 'dynamic_background_normalization') && ...
        ~isempty(graph.dynamic_background_normalization)
    mode = localCanonicalDynamicBackgroundNormalizationMode( ...
        graph.dynamic_background_normalization, 'backgroundStats');
    return
end

% Backward compatibility: the old boolean restored per-step min/max scaling
% of the final composite image for moving-background trials.
if localGetLogicalScalarField(graph, 'normalize_dynamic_background', false)
    mode = 'compositeRange';
end
end


function mode = localCanonicalDynamicBackgroundNormalizationMode(rawValue, trueMode)
mode = 'none';
if nargin < 2 || isempty(trueMode)
    trueMode = 'backgroundStats';
end

if islogical(rawValue) || isnumeric(rawValue)
    if isfinite(double(rawValue(1))) && rawValue(1) ~= 0
        mode = trueMode;
    end
    return
end

textValue = lower(strtrim(char(string(rawValue))));
textValue = regexprep(textValue, '[^a-z0-9]', '');
switch textValue
    case {'', '0', 'false', 'no', 'off', 'none'}
        mode = 'none';
    case {'1', 'true', 'yes', 'on', 'background', 'backgroundstats', ...
            'bg', 'bgstats', 'firstbackground', 'firstbg'}
        mode = 'backgroundStats';
    case {'composite', 'compositestats', 'firstcomposite', ...
            'firstfull', 'full', 'fullimage', 'image', 'stimulus'}
        mode = 'compositeStats';
    case {'range', 'minmax', 'compositerange', 'compositeminmax', ...
            'old', 'legacy', 'perframe', 'perstep'}
        mode = 'compositeRange';
    otherwise
        error('makeStimulusCoPsx:BadDynamicBackgroundNormalization', ...
            ['Unknown graph.dynamic_background_normalization value "%s". ' ...
            'Use none, backgroundStats, compositeStats, or compositeRange.'], ...
            char(string(rawValue)));
end
end


function mode = localResolveTargetMeanNormalizationMode(graph)
mode = 'none';
if ~isstruct(graph)
    return
end

rawValue = [];
if isfield(graph, 'target_mean_normalization') && ~isempty(graph.target_mean_normalization)
    rawValue = graph.target_mean_normalization;
elseif isfield(graph, 'targetMeanNormalization') && ~isempty(graph.targetMeanNormalization)
    rawValue = graph.targetMeanNormalization;
end
if isempty(rawValue)
    return
end

if islogical(rawValue) || isnumeric(rawValue)
    if isfinite(double(rawValue(1))) && rawValue(1) ~= 0
        mode = 'localBackgroundMean3SD';
    end
    return
end

textValue = lower(strtrim(char(string(rawValue))));
textValue = regexprep(textValue, '[^a-z0-9]', '');
switch textValue
    case {'', '0', 'false', 'no', 'off', 'none'}
        mode = 'none';
    case {'1', 'true', 'yes', 'on', 'localbackgroundmean', ...
            'localbackgroundmean3sd', 'backgroundmean', 'backgroundmean3sd', ...
            'targetregionbackgroundmean', 'targetregionbackgroundmean3sd', ...
            'targetbackgroundmean', 'targetbackgroundmean3sd', 'regionmean', ...
            'regionmean3sd'}
        mode = 'localBackgroundMean3SD';
    otherwise
        error('makeStimulusCoPsx:BadTargetMeanNormalization', ...
            ['Unknown graph.target_mean_normalization value "%s". ' ...
            'Use none or localBackgroundMean3SD.'], char(string(rawValue)));
end
end


function k = localSampleTextureRotationK(doRotate)
if doRotate
    k = randi(4) - 1;
else
    k = 0;
end
end


function imgOut = localNormalizeTextureRange(imgIn, outMin, outMax)
imgOut = double(imgIn);
finiteMask = isfinite(imgOut);
if ~any(finiteMask(:))
    imgOut(:) = (outMin + outMax) / 2;
    return
end

lo = min(imgOut(finiteMask));
hi = max(imgOut(finiteMask));
if hi <= lo
    imgOut(finiteMask) = (outMin + outMax) / 2;
    imgOut(~finiteMask) = outMin;
    return
end

imgOut = (imgOut - lo) ./ (hi - lo);
imgOut = imgOut .* (outMax - outMin) + outMin;
imgOut(~finiteMask) = outMin;
end


function stats = localImageStats(img)
vals = double(img(:));
vals = vals(isfinite(vals));
if isempty(vals)
    stats = struct('mean', NaN, 'std', NaN);
    return
end

stats = struct('mean', mean(vals), 'std', std(vals, 0));
end


function imgOut = localMatchImageStats(imgIn, refStats)
imgOut = double(imgIn);
if ~isstruct(refStats) || ~isfield(refStats, 'mean') || ~isfield(refStats, 'std') || ...
        ~isfinite(refStats.mean)
    return
end

finiteMask = isfinite(imgOut);
if ~any(finiteMask(:))
    return
end

vals = imgOut(finiteMask);
imgMean = mean(vals);
imgStd = std(vals, 0);
if isfinite(refStats.std) && refStats.std > 0 && isfinite(imgStd) && imgStd > 0
    imgOut(finiteMask) = ((vals - imgMean) ./ imgStd) .* refStats.std + refStats.mean;
else
    imgOut(finiteMask) = vals + (refStats.mean - imgMean);
end
end


function [imgOut, delta] = localMatchTargetRegionMeanToBackground(targetImg, backgroundImg, cx, cy, maskSigma, regionSigma, backgroundMean)
imgOut = double(targetImg);
delta = NaN;
if nargin < 7
    backgroundMean = NaN;
end

regionRadius = double(maskSigma) .* double(regionSigma);
if ~isfinite(regionRadius) || regionRadius <= 0 || ...
        ~isfinite(cx) || ~isfinite(cy) || ~isequal(size(targetImg), size(backgroundImg))
    return
end

[height, width] = size(imgOut);
cx = double(cx);
cy = double(cy);
xMin = max(1, floor(cx - regionRadius));
xMax = min(width, ceil(cx + regionRadius));
yMin = max(1, floor(cy - regionRadius));
yMax = min(height, ceil(cy + regionRadius));
if xMin > xMax || yMin > yMax
    return
end

[xPatchGrid, yPatchGrid] = meshgrid(xMin:xMax, yMin:yMax);
regionMask = ((xPatchGrid - cx).^2 + (yPatchGrid - cy).^2) <= regionRadius.^2;
patch = imgOut(yMin:yMax, xMin:xMax);
regionFinite = regionMask & isfinite(patch);
if ~any(regionFinite(:))
    return
end

targetRegionVals = patch(regionFinite);
targetRegionMean = mean(targetRegionVals);
if ~isfinite(backgroundMean)
    backgroundMean = localFiniteMeanLocal(backgroundImg(:));
end
if ~isfinite(targetRegionMean) || ~isfinite(backgroundMean)
    return
end

delta = backgroundMean - targetRegionMean;
patch(regionFinite) = patch(regionFinite) + delta;
imgOut(yMin:yMax, xMin:xMax) = patch;
end


function [dirName, filePrefix] = resolveTargetCoherenceFolderLocal(baseDir, targetWord, coherence)
coherence = min(max(double(coherence), 0), 1);

% Coherence manipulation applies to the standard full-target case.
% Preserve legacy behavior for other target folder modes.
if ~strcmp(targetWord, 'full')
    dirName = targetWord;
    filePrefix = targetWord;
    return
end

if abs(coherence - 1) < 1e-9
    dirName = 'full';
    filePrefix = 'full';
    return
end

cohPct = round(100 * coherence);
candidateDirNames = {sprintf('mix%02d', cohPct), sprintf('mix%d', cohPct)};
for i = 1:numel(candidateDirNames)
    if exist(fullfile(baseDir, candidateDirNames{i}), 'dir')
        dirName = candidateDirNames{i};
        filePrefix = candidateDirNames{i};
        return
    end
end

% Default to zero-padded naming if neither variant exists so the later
% missing-file error still points at a deterministic expected folder.
dirName = sprintf('mix%02d', cohPct);
filePrefix = dirName;
end


function img = extractTargetImageLocal(targetStruct, targetWord, targetDirName)
img = [];
candidateFields = {};

if strcmp(targetDirName, 'full')
    candidateFields{end+1} = [targetWord, '_tp']; %#ok<AGROW>
elseif startsWith(targetDirName, 'mix')
    candidateFields{end+1} = 'mix_tpi'; %#ok<AGROW>
    candidateFields{end+1} = [targetDirName, '_tp']; %#ok<AGROW>
    candidateFields{end+1} = [targetDirName, '_tpi']; %#ok<AGROW>
end
candidateFields{end+1} = [targetWord, '_tp']; %#ok<AGROW>

for i = 1:numel(candidateFields)
    if isfield(targetStruct, candidateFields{i})
        img = targetStruct.(candidateFields{i});
        return
    end
end

fieldNames = fieldnames(targetStruct);
for i = 1:numel(fieldNames)
    fieldVal = targetStruct.(fieldNames{i});
    if isnumeric(fieldVal) && ismatrix(fieldVal)
        img = fieldVal;
        return
    end
end

error('Could not resolve target image field for target folder %s.', targetDirName);
end


function imgOut = matchImageMeanLocal(imgIn, targetImg)
imgOut = double(imgIn);
targetMean = mean(double(targetImg(:)), 'omitnan');
imgMean = mean(imgOut(:), 'omitnan');

if ~isfinite(targetMean) || ~isfinite(imgMean)
    return
end

imgOut = imgOut + (targetMean - imgMean);
end


function imgOut = localGrayBackgroundLikeTarget(targetImg)
targetImg = double(targetImg);
targetMean = mean(targetImg(:), 'omitnan');
if ~isfinite(targetMean)
    targetMean = 0;
end
imgOut = ones(size(targetImg)) .* targetMean;
end


function [s, cacheHit] = loadStimulusFileCachedLocal(filePath)
% Cache loaded stimulus MAT files across calls so repeated trials reuse
% already-loaded source images instead of hitting disk each time.
persistent stimFileCache
if isempty(stimFileCache)
    stimFileCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
end

if ischar(filePath)
    key = filePath;
elseif isstring(filePath)
    key = char(filePath(1));
else
    key = char(string(filePath));
end
if isKey(stimFileCache, key)
    s = stimFileCache(key);
    cacheHit = true;
    return
end

s = load(key);
stimFileCache(key) = s;
cacheHit = false;
end
