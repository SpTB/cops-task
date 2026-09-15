function info = validateCoPsStimulusSelection(ex)
% Validate selected CoPs stimulus folders before the experiment starts.

if ~isfield(ex, 'stim') || ~isfield(ex.stim, 'seq') || isempty(ex.stim.seq)
    error('validateCoPsStimulusSelection:MissingSequence', ...
        'ex.stim.seq is missing. Build the stimulus sequence before validation.');
end
if ~isfield(ex, 'exp') || ~isfield(ex.exp, 'CoPs')
    error('validateCoPsStimulusSelection:MissingCoPs', ...
        'ex.exp.CoPs settings are missing.');
end

graph = ex.exp.CoPs.graph;
ctl = ex.exp.CoPs.ctl;
trialIdx = localActiveStimTrialIdx(ex);
if isempty(trialIdx)
    info = localInfoStruct(0, 0, {});
    return
end

fullAsBackground = localScalarLogicalField(graph, 'full_as_background', false);
if fullAsBackground
    targetWord = 'scramble';
    backgroundWord = 'full';
else
    targetWord = 'full';
    backgroundWord = 'scramble';
end

checked = containers.Map('KeyType', 'char', 'ValueType', 'logical');
errors = {};
checkedDirs = {};

for iTrial = trialIdx(:)'
    stimDir = ex.stim.seq{iTrial};
    noiseValues = localTrialOrConfigValues(ex, 'background_noise_lvl', iTrial, ...
        localNumericVectorField(graph, 'background_noise_lvl', 5));
    coherenceValues = localTrialOrConfigValues(ex, 'coherence', iTrial, ...
        localNumericVectorField(ctl, 'coherence', 1));

    for iNoise = 1:numel(noiseValues)
        for iCoherence = 1:numel(coherenceValues)
            req = localResolveStimRequirement(stimDir, noiseValues(iNoise), ...
                targetWord, backgroundWord, coherenceValues(iCoherence));
            key = sprintf('%s|noise=%g|coh=%g|target=%s|background=%s', ...
                req.rootDir, req.backgroundNoiseLevel, req.coherence, ...
                req.targetDirName, req.backgroundWord);
            if isKey(checked, key)
                continue
            end
            checked(key) = true;
            checkedDirs{end+1} = req.rootDir; %#ok<AGROW>
            errors = [errors, localValidateRequirement(req)]; %#ok<AGROW>
        end
    end
end

if ~isempty(errors)
    error('validateCoPsStimulusSelection:InvalidStimuli', ...
        'CoPs stimulus validation failed:\n%s', strjoin(errors, newline));
end

info = localInfoStruct(numel(trialIdx), checked.Count, checkedDirs);
end


function idx = localActiveStimTrialIdx(ex)
nTrials = numel(ex.stim.seq);
activeMask = true(1, nTrials);
if isfield(ex.exp.CoPs, 'trialParamSchedules') && ...
        isfield(ex.exp.CoPs.trialParamSchedules, 'target_visibility')
    vis = ex.exp.CoPs.trialParamSchedules.target_visibility;
    activeMask = isfinite(double(vis(:)'));
end
if numel(activeMask) < nTrials
    activeMask = [activeMask, false(1, nTrials - numel(activeMask))];
elseif numel(activeMask) > nTrials
    activeMask = activeMask(1:nTrials);
end
idx = find(activeMask);
end


function values = localTrialOrConfigValues(ex, fieldName, trialIdx, fallbackValues)
values = [];
if isfield(ex.exp.CoPs, 'trialParamSchedules') && ...
        isfield(ex.exp.CoPs.trialParamSchedules, fieldName)
    schedule = ex.exp.CoPs.trialParamSchedules.(fieldName);
    if numel(schedule) >= trialIdx
        value = double(schedule(trialIdx));
        if isfinite(value)
            values = value;
        end
    end
end
if isempty(values)
    values = fallbackValues;
end
values = double(values(:)');
values = values(isfinite(values));
if isempty(values)
    values = NaN;
end
values = unique(values, 'stable');
end


function req = localResolveStimRequirement(stimDir, backgroundNoiseLevel, targetWord, backgroundWord, coherence)
stimDir = localCharText(stimDir);
req = struct();
req.inputDir = stimDir;
req.rootDir = stimDir;
req.backgroundNoiseLevel = backgroundNoiseLevel;
req.coherence = coherence;
req.targetWord = targetWord;
req.backgroundWord = backgroundWord;

[parentDir, leafName] = fileparts(stimDir);
rootNoiseDirName = '';
if ~isempty(regexp(leafName, '^noise\d+$', 'once'))
    rootNoiseDirName = leafName;
    req.rootDir = parentDir;
end

req.noiseDir = localResolveNoiseDir(req.rootDir, rootNoiseDirName, backgroundNoiseLevel);
[req.targetDirName, req.targetFilePrefix] = localResolveTargetCoherenceFolder( ...
    req.noiseDir, targetWord, coherence);
req.targetDir = fullfile(req.noiseDir, req.targetDirName);
req.backgroundDir = fullfile(req.noiseDir, backgroundWord);
req.targetPattern = [req.targetFilePrefix, '*.mat'];
req.backgroundPattern = [backgroundWord, '*.mat'];
end


function noiseDir = localResolveNoiseDir(rootDir, rootNoiseDirName, backgroundNoiseLevel)
if ~exist(rootDir, 'dir')
    noiseDir = fullfile(rootDir, 'noise_missing');
    return
end

noiseDirs = dir(fullfile(rootDir, 'noise*'));
noiseDirs = noiseDirs([noiseDirs.isdir]);
noiseNames = {noiseDirs.name};

if backgroundNoiseLevel == 0 || backgroundNoiseLevel == -1
    if ~isempty(rootNoiseDirName) && any(strcmp(rootNoiseDirName, noiseNames))
        noiseDirName = rootNoiseDirName;
    elseif any(strcmp('noise1', noiseNames))
        noiseDirName = 'noise1';
    elseif any(strcmp('noise5', noiseNames))
        noiseDirName = 'noise5';
    elseif ~isempty(noiseNames)
        noiseDirName = noiseNames{1};
    else
        noiseDirName = 'noise_missing';
    end
else
    noiseDirName = ['noise', num2str(backgroundNoiseLevel)];
end
noiseDir = fullfile(rootDir, noiseDirName);
end


function [dirName, filePrefix] = localResolveTargetCoherenceFolder(baseDir, targetWord, coherence)
coherence = min(max(double(coherence), 0), 1);
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
dirName = sprintf('mix%02d', cohPct);
filePrefix = dirName;
end


function errors = localValidateRequirement(req)
errors = {};
if ~exist(req.rootDir, 'dir')
    errors{end+1} = sprintf('Missing stimulus folder: %s', req.rootDir); %#ok<AGROW>
    return
end
if ~exist(req.noiseDir, 'dir')
    errors{end+1} = sprintf('Missing noise folder for %s: %s', req.rootDir, req.noiseDir); %#ok<AGROW>
    return
end

[targetFiles, targetErr] = localValidateMatFolder(req.targetDir, req.targetPattern, 'target');
[backgroundFiles, backgroundErr] = localValidateMatFolder(req.backgroundDir, req.backgroundPattern, 'background');
errors = [errors, targetErr, backgroundErr];
if ~isempty(errors)
    return
end

errors = [errors, localValidateTargetFileHeaders(targetFiles, req.targetWord, req.targetDirName)]; %#ok<AGROW>
errors = [errors, localValidateRequiredFieldHeaders(backgroundFiles, [req.backgroundWord, '_tp'], 'Background')]; %#ok<AGROW>
end


function [files, errors] = localValidateMatFolder(folderPath, pattern, label)
errors = {};
files = struct('name', {}, 'folder', {});
if ~exist(folderPath, 'dir')
    errors{end+1} = sprintf('Missing %s texture folder: %s', label, folderPath); %#ok<AGROW>
    return
end
files = dir(fullfile(folderPath, pattern));
files = files(~[files.isdir]);
if isempty(files)
    errors{end+1} = sprintf('No %s texture files matching %s in %s', ...
        label, pattern, folderPath); %#ok<AGROW>
end
end


function errors = localValidateTargetFileHeaders(files, targetWord, targetDirName)
errors = {};
candidateFields = {};
if strcmp(targetDirName, 'full')
    candidateFields{end+1} = [targetWord, '_tp']; %#ok<AGROW>
elseif strncmp(targetDirName, 'mix', 3)
    candidateFields{end+1} = 'mix_tpi'; %#ok<AGROW>
    candidateFields{end+1} = [targetDirName, '_tp']; %#ok<AGROW>
    candidateFields{end+1} = [targetDirName, '_tpi']; %#ok<AGROW>
end
candidateFields{end+1} = [targetWord, '_tp']; %#ok<AGROW>

for iFile = 1:numel(files)
    filePath = fullfile(files(iFile).folder, files(iFile).name);
    vars = localWhosMatFile(filePath);
    if isempty(vars)
        errors{end+1} = sprintf('Target file could not be inspected or is empty: %s', filePath); %#ok<AGROW>
        continue
    end
    if ~localHasCandidateImageVar(vars, candidateFields)
        errors{end+1} = sprintf('Target file has no usable image matrix: %s', filePath); %#ok<AGROW>
    end
end
end


function errors = localValidateRequiredFieldHeaders(files, fieldName, label)
errors = {};
for iFile = 1:numel(files)
    filePath = fullfile(files(iFile).folder, files(iFile).name);
    vars = localWhosMatFile(filePath);
    matchIdx = strcmp({vars.name}, fieldName);
    if ~any(matchIdx) || ~localWhosVarIsNumericMatrix(vars(find(matchIdx, 1, 'first')))
        errors{end+1} = sprintf('%s file is missing numeric matrix field %s: %s', ...
            label, fieldName, filePath); %#ok<AGROW>
    end
end
end


function vars = localWhosMatFile(filePath)
try
    vars = whos('-file', filePath);
catch
    vars = struct('name', {}, 'size', {}, 'class', {});
end
end


function tf = localHasCandidateImageVar(vars, candidateFields)
tf = false;
names = {vars.name};
for i = 1:numel(candidateFields)
    matchIdx = strcmp(names, candidateFields{i});
    if any(matchIdx) && localWhosVarIsNumericMatrix(vars(find(matchIdx, 1, 'first')))
        tf = true;
        return
    end
end
for i = 1:numel(vars)
    if localWhosVarIsNumericMatrix(vars(i))
        tf = true;
        return
    end
end
end


function tf = localWhosVarIsNumericMatrix(varInfo)
numericClasses = {'double', 'single', 'uint8', 'uint16', 'uint32', 'uint64', ...
    'int8', 'int16', 'int32', 'int64', 'logical'};
tf = isfield(varInfo, 'class') && any(strcmp(varInfo.class, numericClasses)) && ...
    isfield(varInfo, 'size') && numel(varInfo.size) == 2 && all(varInfo.size > 1);
end


function values = localNumericVectorField(s, fieldName, defaultValue)
values = defaultValue;
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    raw = s.(fieldName);
    if isnumeric(raw) || islogical(raw)
        values = double(raw(:)');
    end
end
end


function value = localScalarLogicalField(s, fieldName, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    raw = s.(fieldName);
    if isnumeric(raw) || islogical(raw)
        value = logical(raw(1));
    elseif ischar(raw) || iscell(raw)
        value = any(strcmpi(strtrim(localCharText(raw)), {'true', '1', 'yes', 'on'}));
    elseif exist('isstring', 'builtin') && isstring(raw)
        value = any(strcmpi(strtrim(localCharText(raw)), {'true', '1', 'yes', 'on'}));
    end
end
end


function text = localCharText(value)
if ischar(value)
    text = value;
elseif iscell(value) && ~isempty(value)
    text = localCharText(value{1});
elseif exist('isstring', 'builtin') && isstring(value)
    text = char(value(1));
else
    text = char(value);
end
end


function info = localInfoStruct(nActiveTrials, nUniqueRequirements, checkedDirs)
[uniqueDirs, ~] = unique(checkedDirs, 'stable');
info = struct();
info.nActiveTrials = nActiveTrials;
info.nUniqueRequirements = nUniqueRequirements;
info.nUniqueStimulusFolders = numel(uniqueDirs);
info.uniqueStimulusFolders = uniqueDirs(:)';
end
