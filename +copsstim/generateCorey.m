function output = generateCorey(animal, stimType, selection, opts)
%GENDailYSTIMCOREY Generate daily stimuli from Corey face/object templates.
%
% genDailyStimCorey('ka') uses 5 random face IDs and random samples.
% genDailyStimCorey('ka', 'face', 5) uses 5 random face IDs.
% genDailyStimCorey('ka', 'object', [3 4 5 6]) uses one random sample from
% each listed object ID.
% genDailyStimCorey('ka', 'face', ["fn_0001_sample02", "fn_0002_sample_05"])
% uses those explicit source PNGs.
% genDailyStimCorey() omits the animal label and starts session folder names
% with the date tag.
% genDailyStimCorey('local') uses bundled source PNGs and repo-local output.

if nargin < 1
    animal = '';
end
if nargin < 2
    stimType = 'both';
end
if nargin < 3
    selection = 10;
end
if nargin < 4
    opts = [];
end

localMode = (ischar(animal) || (isstring(animal) && isscalar(animal))) && ...
    strcmpi(strtrim(animal),'local');
if localMode, animal = ''; end
[stimType, selection, opts] = parseInputs(stimType, selection, opts, nargin);
animal = normalizeAnimal(animal);
opts = mergeOptions(opts, defaultOptions(localMode));
stimType = normalizeStimType(stimType);
noise_scalar = validateNoiseLevel(opts.noise_scalar);

% Synthesis dependencies are private to this package; no path changes needed.

sources = resolveSources(stimType, opts);
templates = listTemplates(sources);

selection_rng_seed = initializeRng(opts.rng_seed);
if isempty(selection)
    selection = opts.default_count;
end

date_tag = opts.date_tag;
if isempty(date_tag)
    date_tag = currentDateTag();
end

num_sessions = validateSessionCount(opts.sessions);
session_seeds = makeSessionSeeds(num_sessions);

output = struct();
output.source_dir = sourceOutputValue(sources);
output.stimType = stimType;
output.selection = {selection};
output.noiseLvl = noise_scalar;
output.date_tag = date_tag;
output.selection_rng_seed = selection_rng_seed;
output.localMode = localMode;
output.options = opts;
output.sessions = repmat(emptySessionOutput(), num_sessions, 1);

Nsc = opts.Nsc;
Nor = opts.Nor;
Na = opts.Na;
Niter = opts.Niter;
Ntp = opts.Ntp;
method = opts.method;
coh_lvls = opts.coh_lvls;
save_bool = opts.save_bool;
save_coh_lvl_only = opts.save_coh_lvl_only;

if ~ismember(method, [1 2 3])
    error('genDailyStimCorey:InvalidMethod', 'opts.method must be 1, 2, or 3.');
end

for session_idx = 1:num_sessions
    rng(session_seeds(session_idx), 'twister');
    selected_templates = selectTemplates(templates, selection);

    daily_dir = fullfile(opts.output_root, ...
        sessionFolderName(animal, date_tag, session_idx));
    if save_bool
        ensureFolder(daily_dir);
    end

    output.sessions(session_idx).session = session_idx;
    output.sessions(session_idx).daily_dir = daily_dir;
    output.sessions(session_idx).rng_seed = session_seeds(session_idx);
    output.sessions(session_idx).images = repmat(emptyImageOutput(), numel(selected_templates), 1);
    used_template_names = {};

    for i = 1:numel(selected_templates)
        template = selected_templates(i);
        future_template_names = {selected_templates(i+1:end).outputBaseName};
        tried_template_names = {};
        generated = false;

        for template_attempt = 1:opts.max_template_retries
            tried_template_names{end+1} = template.outputBaseName; %#ok<AGROW>
            try
                image_output = processTemplate(template, daily_dir, noise_scalar, opts, ...
                    Nsc, Nor, Na, Niter, Ntp, method, coh_lvls, save_bool, save_coh_lvl_only);
                generated = hasExpectedOutputs(image_output, Ntp, save_bool, save_coh_lvl_only, method);
            catch ME
                image_output = imageOutputForTemplate(template, daily_dir, noise_scalar);
                generated = false;
                warning('genDailyStimCorey:TemplateFailed', ...
                    'Template %s failed: %s', template.outputBaseName, ME.message);
            end

            if generated
                output.sessions(session_idx).images(i, 1) = image_output;
                used_template_names{end+1} = template.outputBaseName; %#ok<AGROW>
                fprintf('Generated session %d/%d, %s (%d/%d)\n', ...
                    session_idx, num_sessions, template.outputBaseName, i, numel(selected_templates));
                break
            end

            deleteGeneratedTextureFolder(image_output.folder, daily_dir);
            if template_attempt >= opts.max_template_retries
                break
            end

            excluded_names = [used_template_names, tried_template_names, future_template_names];
            template = drawReplacementTemplate(templates, excluded_names);
            fprintf('Retrying session %d/%d slot %d/%d with %s\n', ...
                session_idx, num_sessions, i, numel(selected_templates), template.outputBaseName);
        end

        if ~generated
            error('genDailyStimCorey:TemplateRetriesExhausted', ...
                'Could not generate a complete stimulus folder for session %d slot %d after %d template attempt(s).', ...
                session_idx, i, opts.max_template_retries);
        end
    end

    if save_bool
        manifest = struct('settings',opts,'localMode',localMode,'selection_rng_seed',selection_rng_seed, ...
            'session',output.sessions(session_idx));
        save(fullfile(daily_dir,'generation_manifest.mat'),'manifest');
    end
    fprintf('Saved session %d daily stimuli in %s\n', session_idx, daily_dir);
end

fprintf('Saved Corey daily stimuli in %d session folder(s)\n', num_sessions);

end

function image_output = processTemplate(template, daily_dir, noise_scalar, opts, ...
    Nsc, Nor, Na, Niter, Ntp, method, coh_lvls, save_bool, save_coh_lvl_only)

image_output = imageOutputForTemplate(template, daily_dir, noise_scalar);
image_name = image_output.image;
filedir = image_output.folder;
filedir_scramble = image_output.scrambleFolder;
filedir_full = image_output.fullFolder;
noise_dir = image_output.noiseFolder;

if method == 3
    filedir_mix = cell(numel(coh_lvls), 1);
    for lvl = 1:numel(coh_lvls)
        filedir_mix{lvl} = fullfile(noise_dir, sprintf('mix%.0f', coh_lvls(lvl) * 100));
    end
end

if save_bool
    ensureFolder(filedir);
    ensureFolder(filedir_scramble);
    ensureFolder(filedir_full);
    if method == 3
        for lvl = 1:numel(coh_lvls)
            ensureFolder(filedir_mix{lvl});
        end
    end
end

full_generic = readTemplateImage(template.path);
[Nsy, Nsx] = size(full_generic);
validateTemplateSize(template.path, [Nsy Nsx], Nsc, opts.mask_radius);

if save_bool
    copyfile(template.path, fullfile(filedir, template.name), 'f');
    save(fullfile(filedir, 'full_gen.mat'), 'full_generic');
end

params_paths = {fullfile(filedir, 'params.mat')};
[loaded_params, params] = loadSavedVar(params_paths, 'params');
if loaded_params && ~paramsMatchSettings(params, Nsc, Nor, Na)
    warning('genDailyStimCorey:CachedParamsMismatch', ...
        'Cached params do not match Nsc/Nor/Na. Recomputing params.');
    loaded_params = false;
end
if ~loaded_params
    params = textureAnalysis_wz(full_generic, Nsc, Nor, Na, 0);
end

seed_scramble = randomize_phase(full_generic, 1);
seed_scramble = seed_scramble * std(full_generic(:)) + mean(full_generic(:));
seed_scramble = clip(seed_scramble, 0, 255);

cx = randi([opts.mask_radius, size(full_generic, 1) - opts.mask_radius]);
cy = randi([opts.mask_radius, size(full_generic, 2) - opts.mask_radius]);
% The offline generator historically treated mask_radius as sigma. Pass it
% explicitly to the shared mask, then retain its unit-peak normalization.
gaussian_mask = copsstim.gaussMask(full_generic, cx, cy, opts.mask_radius, opts.mask_radius);
gaussian_mask = gaussian_mask / max(gaussian_mask(:));
inv_mask = 1 - gaussian_mask;
target = seed_scramble .* gaussian_mask;
background = full_generic .* inv_mask;
full_is_target = clip(target + background, 0, 255);
t2 = full_generic .* gaussian_mask;
b2 = seed_scramble .* inv_mask;
scr_is_target = clip(t2 + b2, 0, 255);

if save_bool
    save(fullfile(filedir, 'params.mat'), 'params');
    if save_coh_lvl_only == 0
        save(fullfile(filedir, 'seed.mat'), 'seed_scramble');
        save(fullfile(filedir, 'full_as_target.mat'), 'full_is_target');
        save(fullfile(filedir, 'scr_as_target.mat'), 'scr_is_target');
    end
end

scramble_tp = seed_scramble;

if method == 3
    params_mix = cell(numel(coh_lvls), 1);
    params_mix_loaded = false(numel(coh_lvls), 1);
    params_noise_paths = {fullfile(filedir, 'params_noise.mat')};
    [loaded_params_noise, params_noise] = loadSavedVar(params_noise_paths, 'params_noise');
    if loaded_params_noise && ~paramsMatchSettings(params_noise, Nsc, Nor, Na)
        warning('genDailyStimCorey:CachedNoiseParamsMismatch', ...
            'Cached noise params do not match Nsc/Nor/Na. Recomputing noise params.');
        loaded_params_noise = false;
    end

    for id = 1:numel(coh_lvls)
        mix_tag = num2str(round(coh_lvls(id) * 100));
        params_mix_paths = {fullfile(filedir, ['params_mix', mix_tag, '.mat'])};
        [params_mix_loaded(id), parid] = loadSavedVar(params_mix_paths, 'parid');
        if params_mix_loaded(id) && ~paramsMatchSettings(parid, Nsc, Nor, Na)
            warning('genDailyStimCorey:CachedMixParamsMismatch', ...
                'Cached mix params do not match Nsc/Nor/Na. Recomputing mix params.');
            params_mix_loaded(id) = false;
        end
        if params_mix_loaded(id)
            params_mix{id} = parid;
        end
    end

    if ~all(params_mix_loaded)
        if ~loaded_params_noise
            params_noise = textureAnalysis_wz(seed_scramble, Nsc, Nor, Na, 0);
            loaded_params_noise = true;
        end
        for id = 1:numel(coh_lvls)
            if ~params_mix_loaded(id)
                mixParams = coh_lvls(id) * struct2params(params) + ...
                    (1 - coh_lvls(id)) * struct2params(params_noise);
                params_mix{id} = params2struct(mixParams, Nsc, Nor, Na);
            end
        end
    end

    if save_bool
        if loaded_params_noise
            save(fullfile(filedir, 'params_noise.mat'), 'params_noise');
        end
        for id = 1:numel(coh_lvls)
            parid = params_mix{id};
            save(fullfile(filedir, ['params_mix', num2str(round(coh_lvls(id) * 100)), '.mat']), 'parid');
        end
    end
end

for tp = 1:Ntp
    fprintf('iteration %d\n', tp);
    retries = 0;
    success = false;
    while ~success && retries < opts.maxRetries
        try
            if method == 1
                full_tp = textureSynthesis_wz(params, [Nsy Nsx], Niter, [], [], [], seed_scramble);
                seed_scramble = seed_scramble + noise_scalar * randn(size(seed_scramble));
                seed_scramble = clip(seed_scramble, 0, 255);
                scramble_tp = randomize_phase(full_tp, 1);
            end

            if method == 2
                full_tp = textureSynthesis_wz(params, [Nsy Nsx], Niter, [], [], [], scramble_tp);
            end

            if method == 3
                full_tp = textureSynthesis_wz(params, [Nsy Nsx], Niter, [], [], [], seed_scramble);
                mix_tp = cell(numel(coh_lvls), 1);
                for lvl = 1:numel(coh_lvls)
                    mix_tp{lvl} = textureSynthesis_wz(params_mix{lvl}, [Nsy Nsx], Niter, [], [], [], scramble_tp);
                end
                seed_scramble = seed_scramble + noise_scalar * randn(size(seed_scramble));
                seed_scramble = clip(seed_scramble, 0, 255);
                scramble_tp = randomize_phase(full_tp, 1);
            end

            scramble_z = (scramble_tp - mean(scramble_tp(:))) / std(scramble_tp(:));
            scramble_tp = scramble_z * std(full_generic(:)) + mean(full_generic(:));

            full_z = (full_tp - mean(full_generic(:))) / std(full_generic(:));
            full_tp = full_z * std(full_generic(:)) + mean(full_generic(:));

            scramble_tp = clip(scramble_tp, 1, 254);
            full_tp = clip(full_tp, 1, 254);

            filename_full = sprintf('full_%04d.mat', tp);
            full_fnam = fullfile(filedir_full, filename_full);
            filename_scramble = sprintf('scramble_%04d.mat', tp);
            scramble_fnam = fullfile(filedir_scramble, filename_scramble);

            if save_bool
                if save_coh_lvl_only == 0
                    save(full_fnam, 'full_tp');
                    save(scramble_fnam, 'scramble_tp');
                else
                    save(full_fnam, 'full_tp');
                    if method == 3
                        save(scramble_fnam, 'scramble_tp');
                    end
                end
            end

            if method == 2
                scramble_tp = scramble_tp + noise_scalar * randn(size(scramble_tp));
            end

            if save_bool && method == 3
                for lvl = 1:numel(coh_lvls)
                    mix_z = (mix_tp{lvl} - mean(full_generic(:))) / std(full_generic(:));
                    mix_temp = mix_z * std(full_generic(:)) + mean(full_generic(:));
                    mix_tp{lvl} = clip(mix_temp, 1, 254);
                    filename_mix = sprintf('mix%.0f_%04d.mat', coh_lvls(lvl) * 100, tp);
                    mix_fnam = fullfile(filedir_mix{lvl}, filename_mix);
                    mix_tpi = mix_tp{lvl};
                    save(mix_fnam, 'mix_tpi');
                end
            end

            success = true;
        catch ME
            retries = retries + 1;
            disp(['Attempt ' num2str(retries) ' failed: ' ME.message]);
            if retries < opts.maxRetries
                pause(1);
            end
        end
    end

    if ~success
        warning('genDailyStimCorey:TrialFailed', ...
            'Skipping %s iteration %d after %d attempt(s).', image_name, tp, opts.maxRetries);
    end
end

end

function image_output = imageOutputForTemplate(template, daily_dir, noise_scalar)
image_name = template.outputBaseName;
filedir = fullfile(daily_dir, image_name);
noise_dir = fullfile(filedir, noiseFolderName(noise_scalar));

image_output = emptyImageOutput();
image_output.image = image_name;
image_output.imageId = template.id;
image_output.sample = template.sample;
image_output.sourceType = template.sourceType;
image_output.sourcePath = template.path;
image_output.folder = filedir;
image_output.noiseFolder = noise_dir;
image_output.fullFolder = fullfile(noise_dir, 'full');
image_output.scrambleFolder = fullfile(noise_dir, 'scramble');
end

function tf = hasExpectedOutputs(image_output, Ntp, save_bool, save_coh_lvl_only, method)
if ~save_bool || Ntp == 0
    tf = true;
    return
end

full_count = numel(dir(fullfile(image_output.fullFolder, 'full_*.mat')));
tf = full_count >= Ntp;

expects_scramble = save_coh_lvl_only == 0 || method == 3;
if expects_scramble
    scramble_count = numel(dir(fullfile(image_output.scrambleFolder, 'scramble_*.mat')));
    tf = tf && scramble_count >= Ntp;
end
end

function deleteGeneratedTextureFolder(folderPath, daily_dir)
if isempty(folderPath) || ~isfolder(folderPath)
    return
end

folderCanonical = canonicalPath(folderPath);
dailyCanonical = canonicalPath(daily_dir);
dailyPrefix = [dailyCanonical filesep];
folderPrefix = [folderCanonical filesep];

if ~startsWith(folderPrefix, dailyPrefix, 'IgnoreCase', ispc)
    error('genDailyStimCorey:UnsafeDeletePath', ...
        'Refusing to delete folder outside session folder: %s', folderPath);
end

rmdir(folderPath, 's');
fprintf('Deleted incomplete stimulus folder: %s\n', folderPath);
end

function template = drawReplacementTemplate(templates, excluded_names)
template_names = lowerCellstr({templates.outputBaseName});
excluded_names = lowerCellstr(excluded_names);
available = find(~ismember(template_names, excluded_names));
if isempty(available)
    error('genDailyStimCorey:NoReplacementTemplates', ...
        'No unused replacement templates are available.');
end

template = templates(available(randi(numel(available))));
end

function values = lowerCellstr(values)
values = cellfun(@lower, values, 'UniformOutput', false);
end

function pathText = canonicalPath(pathText)
pathText = char(java.io.File(pathText).getCanonicalPath());
end

function defaults = defaultOptions(localMode)
repoRoot = fileparts(fileparts(mfilename('fullpath')));
defaults.source_root = fullfile(repoRoot,'stimulus_sources');
if ~localMode
    environmentRoot = getenv('COPS_STIM_SOURCE_ROOT');
    if ~isempty(environmentRoot), defaults.source_root = environmentRoot; end
end
defaults.face_folder = 'faces_scrambled_raw';
defaults.object_folder = 'objects_scrambled_raw';
defaults.output_root = fullfile(repoRoot,'stimuli');
defaults.date_tag = '';
defaults.add_paths = false; % legacy option, accepted without changing the path
defaults.plot = 0;
defaults.save_bool = 1;
defaults.save_coh_lvl_only = 0;
defaults.Ntp = 100;
defaults.sessions = 3;
defaults.rng_seed = [];
defaults.default_count = 5;
defaults.noise_scalar = 1;
defaults.method = 1;
defaults.coh_lvls = linspace(.05, .95, 19);
defaults.Nsc = 4;
defaults.Nor = 4;
defaults.Na = 9;
defaults.Niter = 50;
defaults.maxRetries = 1;
defaults.max_template_retries = 10;
defaults.mask_radius = 20;
end

function [stimType, selection, opts] = parseInputs(stimType, selection, opts, numInputs)
if numInputs < 2
    stimType = 'face';
    selection = [];
    opts = struct();
    return
end

if isstruct(stimType) && numInputs < 3
    opts = stimType;
    stimType = 'face';
    selection = [];
    return
end

if isStimType(stimType)
    if numInputs < 3
        selection = [];
        opts = struct();
    elseif isstruct(selection) && numInputs < 4
        opts = selection;
        selection = [];
    elseif isempty(opts)
        opts = struct();
    end
    return
end

if isstruct(selection) && numInputs < 4
    opts = selection;
    selection = stimType;
    stimType = 'face';
    return
end

if numInputs >= 3 && ~isempty(selection)
    error('genDailyStimCorey:AmbiguousInputs', ...
        'When the second argument is a selection, the third argument must be opts.');
end

selection = stimType;
stimType = 'face';
if isempty(opts)
    opts = struct();
end
end

function opts = mergeOptions(opts, defaults)
if isempty(opts)
    opts = struct();
end
if ~isstruct(opts) || numel(opts) ~= 1
    error('genDailyStimCorey:InvalidOpts', 'opts must be a scalar struct.');
end

unknown = setdiff(fieldnames(opts), fieldnames(defaults));
if ~isempty(unknown)
    error('genDailyStimCorey:UnknownOption', ...
        'Unknown opts field(s): %s', strjoin(unknown, ', '));
end

fields = fieldnames(defaults);
for idx = 1:numel(fields)
    field = fields{idx};
    if ~isfield(opts, field) || isempty(opts.(field))
        opts.(field) = defaults.(field);
    end
end
end

function sources = resolveSources(stimType, opts)
switch stimType
    case 'face'
        sources = makeSource('face', fullfile(opts.source_root, opts.face_folder));
    case 'object'
        sources = makeSource('object', fullfile(opts.source_root, opts.object_folder));
    case 'both'
        sources = [ ...
            makeSource('face', fullfile(opts.source_root, opts.face_folder)); ...
            makeSource('object', fullfile(opts.source_root, opts.object_folder))];
end

for idx = 1:numel(sources)
    if ~isfolder(sources(idx).folder)
        error('genDailyStimCorey:SourceFolderMissing', ...
            'Could not find source folder: %s. Set opts.source_root or COPS_STIM_SOURCE_ROOT to the parent of the source-image folders.', sources(idx).folder);
    end
end
end

function source = makeSource(sourceType, folder)
source = struct('type', sourceType, 'folder', folder);
end

function value = sourceOutputValue(sources)
if numel(sources) == 1
    value = sources.folder;
else
    value = {sources.folder};
end
end

function templates = listTemplates(sources)
templates = repmat(emptyTemplate(), 0, 1);
for sourceIdx = 1:numel(sources)
    files = dir(fullfile(sources(sourceIdx).folder, '*.png'));
    for idx = 1:numel(files)
        [ok, image_id, sample] = parseTemplateFileName(files(idx).name);
        if ok
            [~, baseName] = fileparts(files(idx).name);
            template = emptyTemplate();
            template.id = image_id;
            template.sample = sample;
            template.name = files(idx).name;
            template.baseName = baseName;
            template.outputBaseName = sprintf('%s_%s', sources(sourceIdx).type, baseName);
            template.sourceType = sources(sourceIdx).type;
            template.path = fullfile(files(idx).folder, files(idx).name);
            templates(end+1, 1) = template; %#ok<AGROW>
        end
    end
end

if isempty(templates)
    error('genDailyStimCorey:NoTemplates', ...
        'No fn_####_sample_## PNG templates found in selected source folder(s).');
end

[~, order] = sort(arrayfun(@(template) ...
    sprintf('%s_%04d_%02d', template.sourceType, template.id, template.sample), ...
    templates, 'UniformOutput', false));
templates = templates(order);
end

function selected = selectTemplates(templates, selection)
if isnumeric(selection)
    selected = selectNumericTemplates(templates, selection);
elseif ischar(selection) || isstring(selection) || iscell(selection)
    selected = selectTextTemplates(templates, selection);
else
    error('genDailyStimCorey:InvalidSelection', ...
        'selection must be a count, image ID vector, string array, or cell array of names.');
end

names = {selected.outputBaseName};
if numel(unique(lower(names))) < numel(names)
    error('genDailyStimCorey:DuplicateSelection', ...
        'Selected templates contain duplicate output folder names.');
end
end

function selected = selectNumericTemplates(templates, selection)
validateattributes(selection, {'numeric'}, ...
    {'vector', 'real', 'finite', 'integer', 'positive'}, ...
    mfilename, 'selection');

groups = templateGroups(templates);
if isscalar(selection)
    nImages = double(selection);
    if nImages > numel(groups)
        error('genDailyStimCorey:TooManyImagesRequested', ...
            'Requested %d images, but only %d source/ID groups are available.', nImages, numel(groups));
    end
    selectedGroups = groups(randperm(numel(groups), nImages));
    selected = repmat(emptyTemplate(), numel(selectedGroups), 1);
    for idx = 1:numel(selectedGroups)
        selected(idx) = randomTemplateFromIndexes(templates, selectedGroups(idx).indexes);
    end
    return
end

ids = double(selection(:))';
sourceTypes = unique({templates.sourceType});
selected = repmat(emptyTemplate(), numel(ids), 1);
if numel(sourceTypes) > 1
    for idx = 1:numel(ids)
        matchingGroups = groups([groups.id] == ids(idx));
        if isempty(matchingGroups)
            error('genDailyStimCorey:ImageIdNotFound', ...
                'Could not find any samples for image ID %d.', ids(idx));
        end
        selectedGroup = matchingGroups(randi(numel(matchingGroups)));
        selected(idx) = randomTemplateFromIndexes(templates, selectedGroup.indexes);
    end
else
    for idx = 1:numel(ids)
        selected(idx) = randomSampleForId(templates, ids(idx));
    end
end
end

function selected = selectTextTemplates(templates, selection)
items = normalizeTextSelection(selection);
selected = repmat(emptyTemplate(), numel(items), 1);
for idx = 1:numel(items)
    selected(idx) = resolveTemplateSpec(templates, items{idx});
end
end

function items = normalizeTextSelection(selection)
if ischar(selection)
    matches = regexp(selection, '(?:(?:face|object)_)?fn_\d{1,4}(?:_sample_?\d{1,2})?(?:\.png)?', ...
        'match', 'ignorecase');
    if numel(matches) > 1
        items = matches(:);
    else
        items = {strtrim(selection)};
    end
elseif isstring(selection)
    items = cellstr(selection(:));
elseif iscell(selection)
    items = selection(:);
else
    error('genDailyStimCorey:InvalidTextSelection', ...
        'Text selection must be char, string, string array, or cell array.');
end

for idx = 1:numel(items)
    value = items{idx};
    if isstring(value)
        if ~isscalar(value)
            error('genDailyStimCorey:InvalidTextSelection', ...
                'Each selected template name must be a text scalar.');
        end
        value = char(value);
    end
    if ~ischar(value) || isempty(strtrim(value))
        error('genDailyStimCorey:InvalidTextSelection', ...
            'Each selected template name must be a non-empty text scalar.');
    end
    items{idx} = strtrim(value);
end
end

function template = resolveTemplateSpec(templates, spec)
[specSourceType, templateSpec] = splitSourcePrefix(spec);
[~, specBase, specExt] = fileparts(templateSpec);
if isempty(specExt)
    specName = [templateSpec '.png'];
else
    specName = templateSpec;
end

matchMask = strcmpi({templates.name}, specName) | ...
    strcmpi({templates.baseName}, specBase) | ...
    strcmpi({templates.outputBaseName}, specBase);
if ~isempty(specSourceType)
    matchMask = matchMask & strcmpi({templates.sourceType}, specSourceType);
end
idx = find(matchMask);
if ~isempty(idx)
    template = templates(idx(randi(numel(idx))));
    return
end

[specSourceType, image_id, sample] = parseTemplateSpec(spec);
if isempty(sample)
    idx = find([templates.id] == image_id);
    if ~isempty(specSourceType)
        idx = idx(strcmpi({templates(idx).sourceType}, specSourceType));
    end
    if isempty(idx)
        error('genDailyStimCorey:ImageIdNotFound', ...
            'Could not find any samples for image ID %d.', image_id);
    end
    template = templates(idx(randi(numel(idx))));
    return
end

idx = find([templates.id] == image_id & [templates.sample] == sample);
if ~isempty(specSourceType)
    idx = idx(strcmpi({templates(idx).sourceType}, specSourceType));
end
if isempty(idx)
    error('genDailyStimCorey:TemplateNotFound', ...
        'Could not find template fn_%04d_sample_%02d.', image_id, sample);
end
template = templates(idx(randi(numel(idx))));
end

function template = randomSampleForId(templates, image_id)
idx = find([templates.id] == image_id);
if isempty(idx)
    error('genDailyStimCorey:ImageIdNotFound', ...
        'Could not find any samples for image ID %d.', image_id);
end
idx = idx(randi(numel(idx)));
template = templates(idx);
end

function groups = templateGroups(templates)
keys = arrayfun(@(template) sprintf('%s_%04d', template.sourceType, template.id), ...
    templates, 'UniformOutput', false);
uniqueKeys = unique(keys, 'stable');
groups = repmat(emptyTemplateGroup(), numel(uniqueKeys), 1);
for idx = 1:numel(uniqueKeys)
    memberIdx = find(strcmp(keys, uniqueKeys{idx}));
    groups(idx).sourceType = templates(memberIdx(1)).sourceType;
    groups(idx).id = templates(memberIdx(1)).id;
    groups(idx).indexes = memberIdx;
end
end

function template = randomTemplateFromIndexes(templates, indexes)
idx = indexes(randi(numel(indexes)));
template = templates(idx);
end

function [ok, image_id, sample] = parseTemplateFileName(fileName)
tokens = regexp(fileName, '^fn_(\d{4})_sample_?(\d{1,2})\.png$', ...
    'tokens', 'once', 'ignorecase');
ok = ~isempty(tokens);
if ok
    image_id = str2double(tokens{1});
    sample = str2double(tokens{2});
else
    image_id = [];
    sample = [];
end
end

function [sourceType, image_id, sample] = parseTemplateSpec(spec)
tokens = regexp(spec, '^(?:(face|object)_)?fn_(\d{1,4})(?:_sample_?(\d{1,2}))?(?:\.png)?$', ...
    'tokens', 'once', 'ignorecase');
if isempty(tokens)
    error('genDailyStimCorey:InvalidTemplateName', ...
        'Template names must look like fn_0001_sample_02.');
end

sourceType = lower(tokens{1});
image_id = str2double(tokens{2});
sample = [];
if numel(tokens) >= 3 && ~isempty(tokens{3})
    sample = str2double(tokens{3});
end
end

function [sourceType, templateSpec] = splitSourcePrefix(spec)
tokens = regexp(spec, '^(face|object)_(fn_.*)$', 'tokens', 'once', 'ignorecase');
if isempty(tokens)
    sourceType = '';
    templateSpec = spec;
else
    sourceType = lower(tokens{1});
    templateSpec = tokens{2};
end
end

function full_generic = readTemplateImage(imagePath)
raw = imread(imagePath);
rawClass = class(raw);
if ndims(raw) == 3
    raw = rgb2gray(raw);
end

full_generic = double(raw);
if isinteger(raw)
    full_generic = full_generic / double(intmax(rawClass)) * 255;
elseif max(full_generic(:)) <= 1
    full_generic = full_generic * 255;
end
end

function validateTemplateSize(imagePath, imageSize, Nsc, mask_radius)
if any(imageSize < 2 * mask_radius + 1)
    error('genDailyStimCorey:ImageTooSmallForMask', ...
        '%s is too small for mask_radius=%d.', imagePath, mask_radius);
end

required_multiple = 2^(Nsc + 2);
if any(mod(imageSize, required_multiple) ~= 0)
    error('genDailyStimCorey:InvalidImageSize', ...
        '%s is %dx%d; dimensions must be multiples of %d for Nsc=%d.', ...
        imagePath, imageSize(1), imageSize(2), required_multiple, Nsc);
end
end

function seed = initializeRng(rng_seed)
if isempty(rng_seed)
    rng('shuffle');
else
    validateattributes(rng_seed, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'integer', 'nonnegative', '<=', 2^32 - 1}, ...
        mfilename, 'opts.rng_seed');
    rng(double(rng_seed), 'twister');
end
state = rng;
seed = state.Seed;
end

function session_seeds = makeSessionSeeds(num_sessions)
session_seeds = randi(2^31 - 1, num_sessions, 1);
while numel(unique(session_seeds)) < num_sessions
    session_seeds = randi(2^31 - 1, num_sessions, 1);
end
end

function num_sessions = validateSessionCount(sessions)
validateattributes(sessions, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'integer', 'positive'}, ...
    mfilename, 'opts.sessions');
num_sessions = double(sessions);
end

function noise_scalar = validateNoiseLevel(noiseLvl)
validateattributes(noiseLvl, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'nonnegative'}, mfilename, 'opts.noise_scalar');
noise_scalar = noiseLvl;
end

function folderName = sessionFolderName(animal, date_tag, session_idx)
if isempty(animal)
    folderName = sprintf('%s_stim%d', date_tag, session_idx);
else
    folderName = sprintf('%s_%s_stim%d', animal, date_tag, session_idx);
end
end

function animal = normalizeAnimal(animal)
if isempty(animal)
    animal = '';
    return
end

if isstring(animal)
    if ~isscalar(animal)
        error('genDailyStimCorey:InvalidAnimal', 'animal must be a 2-letter string.');
    end
    animal = char(animal);
end

if ~ischar(animal)
    error('genDailyStimCorey:InvalidAnimal', 'animal must be a 2-letter string.');
end

animal = strtrim(animal);
if isempty(animal)
    return
end

animal = lower(animal);
if numel(animal) ~= 2 || ~all(isstrprop(animal, 'alpha'))
    error('genDailyStimCorey:InvalidAnimal', 'animal must be a 2-letter string.');
end
end

function tf = isStimType(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    tf = false;
    return
end
key = lower(strtrim(char(value)));
tf = ismember(key, {'face', 'faces', 'faces_scrambled_raw', ...
    'object', 'objects', 'objects_scrambled_raw', 'both'});
end

function stimType = normalizeStimType(stimType)
if isempty(stimType)
    stimType = 'face';
end
if ~(ischar(stimType) || (isstring(stimType) && isscalar(stimType)))
    error('genDailyStimCorey:InvalidStimType', ...
        'stimType must be face, object, or both.');
end

key = lower(strtrim(char(stimType)));
switch key
    case {'face', 'faces', 'faces_scrambled_raw'}
        stimType = 'face';
    case {'object', 'objects', 'objects_scrambled_raw'}
        stimType = 'object';
    case 'both'
        stimType = 'both';
    otherwise
        error('genDailyStimCorey:InvalidStimType', ...
            'stimType must be face, object, or both.');
end
end

function tag = currentDateTag()
tomorrow_dt = datetime('today') + days(1);
month_name = month(tomorrow_dt, 'shortname');
tag = sprintf('%s%d', lower(month_name{1}), day(tomorrow_dt));
end

function folderName = noiseFolderName(noise_scalar)
folderName = ['noise' regexprep(num2str(noise_scalar), '\s+', '')];
end

function ensureFolder(folderPath)
if ~isfolder(folderPath)
    mkdir(folderPath);
end
end

function session_output = emptySessionOutput()
session_output = struct( ...
    'session', [], ...
    'daily_dir', '', ...
    'rng_seed', [], ...
    'images', repmat(emptyImageOutput(), 0, 1));
end

function image_output = emptyImageOutput()
image_output = struct( ...
    'image', '', ...
    'imageId', [], ...
    'sample', [], ...
    'sourceType', '', ...
    'sourcePath', '', ...
    'folder', '', ...
    'noiseFolder', '', ...
    'fullFolder', '', ...
    'scrambleFolder', '');
end

function template = emptyTemplate()
template = struct( ...
    'id', [], ...
    'sample', [], ...
    'name', '', ...
    'baseName', '', ...
    'outputBaseName', '', ...
    'sourceType', '', ...
    'path', '');
end

function group = emptyTemplateGroup()
group = struct( ...
    'sourceType', '', ...
    'id', [], ...
    'indexes', []);
end
