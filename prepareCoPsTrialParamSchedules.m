function ex = prepareCoPsTrialParamSchedules(ex)
% Precompute balanced per-trial parameter schedules for CoPs sessions.
% Vector-valued parameters are expanded to a full session schedule with
% proportions that match the supplied vector as closely as possible.

if ~isfield(ex, 'exp') || ~isfield(ex.exp, 'CoPs')
    return
end

blockInfo = getCoPsTrialBlockInfox(ex);
totalN = blockInfo.totalN;
if ~isfinite(totalN) || totalN <= 0
    return
end
tutN = blockInfo.tutN;
preN = blockInfo.preN;
mainN = blockInfo.mainN;

sched = struct();
sched.is_pre = zeros(1, totalN);
sched.stimulus_dir_idx = nan(1, totalN);
sched.texture_rotation_k = nan(1, totalN);
if ~isempty(blockInfo.preIdx)
    sched.is_pre(blockInfo.preIdx) = 1;
end

mainNoise = getNestedNumericVectorLocal(ex, {'exp', 'CoPs', 'graph', 'background_noise_lvl'});
tutNoise = getNestedNumericVectorLocal(ex, {'exp', 'CoPs', 'tut', 'background_noise_lvl'});
sched.background_noise_lvl = nan(1, totalN);
sched.background_noise_lvl(blockInfo.tutorialIdx) = buildBalancedValueScheduleLocal(tutNoise, tutN);
sched.background_noise_lvl(blockInfo.preIdx) = ones(1, preN);
sched.background_noise_lvl(blockInfo.mainIdx) = buildBalancedValueScheduleLocal(mainNoise, mainN);

targetVisibility = getNestedNumericVectorLocal(ex, {'exp', 'CoPs', 'graph', 'target_visibility'});
targetVisibility0 = getNestedNumericVectorLocal(ex, {'exp', 'CoPs', 'graph', 'target_visibility0'});
targetVisibilityNull = getNestedNumericVectorLocal(ex, {'exp', 'CoPs', 'graph', 'targetVisibilityNull'});
if isempty(targetVisibilityNull)
    targetVisibilityNull = getNestedNumericVectorLocal(ex, {'exp', 'CoPs', 'graph', 'target_visibilityNull'});
end
targetNum = getNestedNumericVectorLocal(ex, {'exp', 'CoPs', 'ctl', 'target_num'});
targetNumNull = getNestedNumericVectorLocal(ex, {'exp', 'CoPs', 'ctl', 'target_numNULL'});
sequenceModeVis = getNestedLogicalLocal(ex, {'exp', 'CoPs', 'graph', 'sequenceMode_vis'}, false);
sequenceModeIm = getNestedLogicalLocal(ex, {'exp', 'CoPs', 'graph', 'sequenceMode_im'}, ...
    getNestedLogicalLocal(ex, {'exp', 'CoPs', 'graph', 'sequenceMode'}, false));
visibilityBlockSize = 1;
if sequenceModeVis && sequenceModeIm
    nSequenceImages = getNestedTextCountLocal(ex, {'exp', 'CoPs', 'graph', 'imgs'});
    if nSequenceImages <= 0
        nSequenceImages = localResolvedStimulusDirCountLocal(ex);
    end
    if nSequenceImages > 0
        visibilityBlockSize = nSequenceImages;
    end
end
sched.target_visibility = buildConditionalVisibilityScheduleLocal( ...
    sched.background_noise_lvl, targetVisibility, targetVisibility0, targetVisibilityNull, ...
    sequenceModeVis, visibilityBlockSize);
if ~isempty(blockInfo.preIdx)
    sched.target_visibility(blockInfo.preIdx) = localMaxFiniteOrDefaultLocal(targetVisibility, 1);
end

balanceStimulusSchedule = getNestedLogicalLocal(ex, ...
    {'exp', 'CoPs', 'graph', 'balanceStimulusSchedule'}, true);
shuffleStimulusSchedule = getNestedLogicalLocal(ex, ...
    {'exp', 'CoPs', 'graph', 'shuffleStimulusSchedule'}, true);
nStimuli = localResolvedStimulusDirCountLocal(ex);
rotationKLevels = localTextureRotationKLevelsLocal(ex);
if balanceStimulusSchedule && nStimuli > 0
    [mainNoiseSeq, mainTargetNumSeq, mainVisSeq, mainStimSeq, mainRotSeq] = localBuildHierarchicalStimulusScheduleLocal( ...
        mainN, mainNoise, targetNum, targetNumNull, targetVisibility, targetVisibility0, targetVisibilityNull, ...
        nStimuli, rotationKLevels);
    sched.background_noise_lvl(blockInfo.mainIdx) = mainNoiseSeq;
    sched.target_num(blockInfo.mainIdx) = mainTargetNumSeq;
    sched.target_visibility(blockInfo.mainIdx) = mainVisSeq;
    sched.stimulus_dir_idx(blockInfo.mainIdx) = mainStimSeq;
    sched.texture_rotation_k(blockInfo.mainIdx) = mainRotSeq;
    if shuffleStimulusSchedule && ~isempty(blockInfo.mainIdx)
        sched = localPermuteScheduleFieldsLocal(sched, blockInfo.mainIdx, { ...
            'background_noise_lvl', 'target_num', 'target_visibility', 'stimulus_dir_idx', 'texture_rotation_k'});
    end
else
    sched.target_num = buildConditionalTargetNumScheduleLocal( ...
        sched.background_noise_lvl, targetNum, targetNumNull);
end
if ~isempty(blockInfo.preIdx) && nStimuli > 0
    [preStimSeq, preRotSeq] = localBuildImageRotationScheduleLocal(preN, nStimuli, rotationKLevels);
    sched.stimulus_dir_idx(blockInfo.preIdx) = preStimSeq;
    sched.texture_rotation_k(blockInfo.preIdx) = preRotSeq;
    if shuffleStimulusSchedule
        sched = localPermuteScheduleFieldsLocal(sched, blockInfo.preIdx, { ...
            'stimulus_dir_idx', 'texture_rotation_k'});
    end
end

targetMaskSigmaMult = getNestedNumericVectorLocal(ex, {'exp', 'CoPs', 'graph', 'target_mask_sigma_mult'});
sched.target_mask_sigma_mult = nan(1, totalN);
sched.target_mask_sigma_mult(blockInfo.tutorialIdx) = buildBalancedValueScheduleLocal(targetMaskSigmaMult, tutN);
sched.target_mask_sigma_mult(blockInfo.preIdx) = buildBalancedValueScheduleLocal(targetMaskSigmaMult, preN);
sched.target_mask_sigma_mult(blockInfo.mainIdx) = buildBalancedValueScheduleLocal(targetMaskSigmaMult, mainN);

coherence = getNestedNumericVectorLocal(ex, {'exp', 'CoPs', 'ctl', 'coherence'});
sched.coherence = nan(1, totalN);
sched.coherence(blockInfo.tutorialIdx) = buildBalancedValueScheduleLocal(coherence, tutN);
sched.coherence(blockInfo.preIdx) = buildBalancedValueScheduleLocal(coherence, preN);
sched.coherence(blockInfo.mainIdx) = buildBalancedValueScheduleLocal(coherence, mainN);

if ~isempty(blockInfo.preIdx)
    sched.target_num(blockInfo.preIdx) = 2;
end

mainStepSize = getNestedNumericVectorLocal(ex, {'exp', 'CoPs', 'ctl', 'step_size_mult'});
tutStepSize = getNestedNumericVectorLocal(ex, {'exp', 'CoPs', 'tut', 'step_size_mult'});
sched.step_size_mult = nan(1, totalN);
sched.step_size_mult(blockInfo.tutorialIdx) = buildBalancedValueScheduleLocal(tutStepSize, tutN);
sched.step_size_mult(blockInfo.preIdx) = buildBalancedValueScheduleLocal(mainStepSize, preN);
sched.step_size_mult(blockInfo.mainIdx) = buildBalancedValueScheduleLocal(mainStepSize, mainN);

ex.exp.CoPs.trialParamSchedules = sched;
end


function seq = buildBalancedValueScheduleLocal(values, nTrials)
seq = [];
if nTrials <= 0
    return
end

if isempty(values)
    seq = NaN(1, nTrials);
    return
end

values = values(:)';
nValues = numel(values);
nFull = floor(nTrials / nValues);
nRem = mod(nTrials, nValues);

seq = repmat(values, 1, nFull);
if nRem > 0
    remIdx = randperm(nValues, nRem);
    seq = [seq, values(remIdx)]; %#ok<AGROW>
end

seq = seq(randperm(numel(seq)));
end


function seq = buildConditionalVisibilityScheduleLocal(noiseSeq, visibilityLevels, visibility0Levels, visibilityNullLevels, sequenceModeVis, blockSize)
seq = NaN(size(noiseSeq));
if isempty(noiseSeq)
    return
end
if nargin < 5 || isempty(sequenceModeVis)
    sequenceModeVis = false;
end
if nargin < 6 || isempty(blockSize)
    blockSize = 1;
end

if isempty(visibilityLevels)
    visibilityLevels = 1;
end
if isempty(visibility0Levels)
    visibility0Levels = visibilityLevels;
end
if nargin < 4 || isempty(visibilityNullLevels)
    visibilityNullLevels = visibilityLevels;
end

noiseSeq = double(noiseSeq);
idxNoiseNull = find(isfinite(noiseSeq) & noiseSeq == -1);
idxNoise0 = find(isfinite(noiseSeq) & noiseSeq == 0);
idxNoiseOther = find(isfinite(noiseSeq) & noiseSeq ~= 0 & noiseSeq ~= -1);

if ~isempty(idxNoiseNull)
    seq(idxNoiseNull) = buildValueScheduleLocal(visibilityNullLevels, numel(idxNoiseNull), sequenceModeVis, blockSize);
end
if ~isempty(idxNoise0)
    seq(idxNoise0) = buildValueScheduleLocal(visibility0Levels, numel(idxNoise0), sequenceModeVis, blockSize);
end
if ~isempty(idxNoiseOther)
    seq(idxNoiseOther) = buildValueScheduleLocal(visibilityLevels, numel(idxNoiseOther), sequenceModeVis, blockSize);
end
end


function seq = buildValueScheduleLocal(values, nTrials, sequenceModeVis, blockSize)
if nargin < 3 || isempty(sequenceModeVis) || ~sequenceModeVis
    seq = buildBalancedValueScheduleLocal(values, nTrials);
    return
end

seq = [];
if nTrials <= 0
    return
end
if isempty(values)
    seq = NaN(1, nTrials);
    return
end

values = values(:)';
blockSize = max(1, round(double(blockSize(1))));
if ~isfinite(blockSize)
    blockSize = 1;
end
pattern = repelem(values, blockSize);
idx = mod(0:(nTrials - 1), numel(pattern)) + 1;
seq = pattern(idx);
end


function seq = buildConditionalTargetNumScheduleLocal(noiseSeq, targetNumLevels, targetNumNullLevels)
seq = NaN(size(noiseSeq));
if isempty(noiseSeq)
    return
end

if isempty(targetNumLevels)
    targetNumLevels = 2;
end
if nargin < 3 || isempty(targetNumNullLevels)
    targetNumNullLevels = targetNumLevels;
end

noiseSeq = double(noiseSeq);
idxNoiseNull = find(isfinite(noiseSeq) & noiseSeq == -1);
idxNoiseOther = find(isfinite(noiseSeq) & noiseSeq ~= -1);

if ~isempty(idxNoiseNull)
    seq(idxNoiseNull) = buildBalancedValueScheduleLocal(targetNumNullLevels, numel(idxNoiseNull));
end
if ~isempty(idxNoiseOther)
    seq(idxNoiseOther) = buildBalancedValueScheduleLocal(targetNumLevels, numel(idxNoiseOther));
end
end


function sched = localPermuteScheduleFieldsLocal(sched, idx, fieldNames)
if isempty(idx)
    return
end
idx = idx(:)';
perm = idx(randperm(numel(idx)));
for i = 1:numel(fieldNames)
    fieldName = fieldNames{i};
    if isfield(sched, fieldName) && numel(sched.(fieldName)) >= max(idx)
        original = sched.(fieldName);
        sched.(fieldName)(idx) = original(perm);
    end
end
end


function [noiseSeq, targetNumSeq, visSeq, stimSeq, rotSeq] = localBuildHierarchicalStimulusScheduleLocal( ...
    nTrials, noiseLevels, targetNumLevels, targetNumNullLevels, ...
    visibilityLevels, visibility0Levels, visibilityNullLevels, nStimuli, rotationKLevels)
noiseSeq = nan(1, nTrials);
targetNumSeq = nan(1, nTrials);
visSeq = nan(1, nTrials);
stimSeq = nan(1, nTrials);
rotSeq = nan(1, nTrials);
if nTrials <= 0
    return
end
if isempty(noiseLevels)
    noiseLevels = 1;
end

[noiseValues, noiseCounts] = localWeightedCountsByUniqueLevelLocal(noiseLevels, nTrials);
cursor = 1;
for iNoise = 1:numel(noiseValues)
    nNoise = noiseCounts(iNoise);
    if nNoise <= 0
        continue
    end
    noiseValue = noiseValues(iNoise);
    targetNumForNoise = localTargetNumLevelsForNoiseLocal(noiseValue, targetNumLevels, targetNumNullLevels);
    [targetNumValues, targetNumCounts] = localWeightedCountsByUniqueLevelLocal(targetNumForNoise, nNoise);
    for iTargetNum = 1:numel(targetNumValues)
        nTargetNum = targetNumCounts(iTargetNum);
        if nTargetNum <= 0
            continue
        end
        visLevels = localVisibilityLevelsForNoiseLocal( ...
            noiseValue, visibilityLevels, visibility0Levels, visibilityNullLevels);
        [visValues, visCounts] = localWeightedCountsByUniqueLevelLocal(visLevels, nTargetNum);
        for iVis = 1:numel(visValues)
            nVis = visCounts(iVis);
            if nVis <= 0
                continue
            end
            idx = cursor:(cursor + nVis - 1);
            [stimLocal, rotLocal] = localBuildImageRotationScheduleLocal(nVis, nStimuli, rotationKLevels);
            noiseSeq(idx) = noiseValue;
            targetNumSeq(idx) = targetNumValues(iTargetNum);
            visSeq(idx) = visValues(iVis);
            stimSeq(idx) = stimLocal;
            rotSeq(idx) = rotLocal;
            cursor = cursor + nVis;
        end
    end
end
end


function [stimSeq, rotSeq] = localBuildImageRotationScheduleLocal(nTrials, nStimuli, rotationKLevels)
stimSeq = nan(1, nTrials);
rotSeq = nan(1, nTrials);
if nTrials <= 0 || nStimuli <= 0
    return
end
if isempty(rotationKLevels)
    rotationKLevels = 0:3;
end
rotationKLevels = rotationKLevels(:)';
nRot = numel(rotationKLevels);
imageCounts = localEqualCountsLocal(nStimuli, nTrials);
cursor = 1;
for iStim = 1:nStimuli
    nThis = imageCounts(iStim);
    if nThis <= 0
        continue
    end
    idx = cursor:(cursor + nThis - 1);
    rotIdx = mod((idx - 1), nRot) + 1;
    stimSeq(idx) = iStim;
    rotSeq(idx) = rotationKLevels(rotIdx);
    cursor = cursor + nThis;
end
end


function counts = localEqualCountsLocal(nItems, nTrials)
counts = zeros(1, nItems);
if nItems <= 0 || nTrials <= 0
    return
end
baseCount = floor(nTrials / nItems);
remainder = mod(nTrials, nItems);
counts(:) = baseCount;
if remainder > 0
    counts(1:remainder) = counts(1:remainder) + 1;
end
end


function [values, counts] = localWeightedCountsByUniqueLevelLocal(levels, nTrials)
levels = double(levels(:)');
levels = levels(isfinite(levels));
if isempty(levels)
    values = NaN;
    counts = nTrials;
    return
end

values = unique(levels, 'stable');
weights = zeros(1, numel(values));
for i = 1:numel(values)
    weights(i) = sum(levels == values(i));
end
exactCounts = nTrials * weights / sum(weights);
counts = floor(exactCounts);
remainder = nTrials - sum(counts);
if remainder > 0
    frac = exactCounts - counts;
    [~, order] = sort(frac, 'descend');
    for i = 1:remainder
        counts(order(i)) = counts(order(i)) + 1;
    end
end
end


function values = localVisibilityLevelsForNoiseLocal(noiseValue, visibilityLevels, visibility0Levels, visibilityNullLevels)
if isfinite(noiseValue) && noiseValue == -1
    values = visibilityNullLevels;
elseif isfinite(noiseValue) && noiseValue == 0
    values = visibility0Levels;
else
    values = visibilityLevels;
end
if isempty(values)
    values = visibilityLevels;
end
if isempty(values)
    values = 1;
end
end


function values = localTargetNumLevelsForNoiseLocal(noiseValue, targetNumLevels, targetNumNullLevels)
if isfinite(noiseValue) && noiseValue == -1
    values = targetNumNullLevels;
else
    values = targetNumLevels;
end
if isempty(values)
    values = targetNumLevels;
end
if isempty(values)
    values = 2;
end
end


function rotationKLevels = localTextureRotationKLevelsLocal(ex)
rotationKLevels = [];
degLevels = getNestedNumericVectorLocal(ex, {'exp', 'CoPs', 'graph', 'texture_rotation_levels_deg'});
if ~isempty(degLevels)
    rotationKLevels = mod(round(degLevels(:)' / 90), 4);
else
    kLevels = getNestedNumericVectorLocal(ex, {'exp', 'CoPs', 'graph', 'texture_rotation_levels_k'});
    if ~isempty(kLevels)
        rotationKLevels = mod(round(kLevels(:)'), 4);
    end
end
if isempty(rotationKLevels)
    rotationKLevels = 0:3;
end
rotationKLevels = unique(rotationKLevels, 'stable');
end


function value = getNestedNumericLocal(s, path)
value = NaN;
node = s;
for i = 1:numel(path)
    key = path{i};
    if isstruct(node) && isfield(node, key)
        node = node.(key);
    else
        return
    end
end
if isnumeric(node) || islogical(node)
    if isscalar(node) && isfinite(double(node))
        value = double(node);
    end
end
end


function value = getNestedNumericVectorLocal(s, path)
value = [];
node = s;
for i = 1:numel(path)
    key = path{i};
    if isstruct(node) && isfield(node, key)
        node = node.(key);
    else
        return
    end
end
if isnumeric(node) || islogical(node)
    value = double(node(:)');
end
end


function count = getNestedTextCountLocal(s, path)
count = 0;
node = s;
for i = 1:numel(path)
    key = path{i};
    if isstruct(node) && isfield(node, key)
        node = node.(key);
    else
        return
    end
end
if ischar(node)
    if isempty(strtrim(node))
        count = 0;
    elseif size(node, 1) > 1
        count = size(node, 1);
    else
        count = 1;
    end
elseif isstring(node)
    node = node(:);
    count = sum(strlength(strtrim(node)) > 0);
elseif iscell(node)
    count = 0;
    for i = 1:numel(node)
        if ~isempty(strtrim(localCharTextLocal(node{i})))
            count = count + 1;
        end
    end
end
end


function count = localResolvedStimulusDirCountLocal(ex)
count = 0;
if ~isfield(ex.exp.CoPs, 'dirs') || ~isfield(ex.exp.CoPs.dirs, 'all')
    return
end
if isfield(ex.exp.CoPs.graph, 'imgs')
    allowedImgs = ex.exp.CoPs.graph.imgs;
else
    allowedImgs = [];
end
try
    stimDirs = resolveCoPsStimulusDirs(ex.exp.CoPs.dirs.all, 1, allowedImgs, true);
    count = numel(stimDirs);
catch
    count = 0;
end
end


function value = getNestedLogicalLocal(s, path, defaultValue)
value = defaultValue;
node = s;
for i = 1:numel(path)
    key = path{i};
    if isstruct(node) && isfield(node, key)
        node = node.(key);
    else
        return
    end
end
if islogical(node) || isnumeric(node)
    value = logical(node(1));
elseif ischar(node) || isstring(node)
    text = strtrim(localCharTextLocal(node));
    value = any(strcmpi(text, {'true', '1', 'yes', 'on'}));
end
end


function value = localMaxFiniteOrDefaultLocal(values, defaultValue)
if nargin < 2
    defaultValue = NaN;
end
values = double(values(:)');
values = values(isfinite(values));
if isempty(values)
    value = defaultValue;
else
    value = max(values);
end
end


function text = localCharTextLocal(value)
if ischar(value)
    text = value;
elseif iscell(value) && ~isempty(value)
    text = localCharTextLocal(value{1});
elseif isnumeric(value) || islogical(value)
    text = num2str(value(1));
else
    text = char(value);
end
end
