function [img, info] = plotTex(ex, opts)
% plotTex Plot the first-step CoPs texture for the current settings.
%
%   plotTex(ex)
%   [img, info] = plotTex(ex)
%
% This helper reuses the CoPs stimulus-generation logic for a single
% example frame without creating Psychtoolbox textures. It intentionally
% overrides trial-length parameters and uses the initial target positions.

if nargin < 2 || isempty(opts)
    opts = struct();
end

defaults = struct( ...
    'trialNo', 1, ...
    'showTargets', false, ...
    'useCircles', false, ...
    'targOnly', 1, ...
    'singleTargetCenter', 1, ...
    'uniformBlend', true, ...
    'targetHiddenBoundsFrac', [], ...
    'cropMarginMult', 1.5);
f = fieldnames(defaults);
for i = 1:numel(f)
    if ~isfield(opts, f{i})
        opts.(f{i}) = defaults.(f{i});
    end
end

graph = ex.exp.CoPs.graph;
ctl = ex.exp.CoPs.ctl;
pos = ex.exp.CoPs.pos;

backgroundNoiseLvl = localFirstScalar(graph.background_noise_lvl, 0);
targetVisibilityVals = localVector(graph.target_visibility, 1);
targetMaskSigmaMultVals = localVector(localFieldOrDefault(graph, 'target_mask_sigma_mult', 1), 1);
targetCoherenceVals = localVector(ctl.coherence, 1);

dirs = '';
if isfield(ex, 'stim') && isfield(ex.stim, 'seq') && numel(ex.stim.seq) >= opts.trialNo
    dirs = ex.stim.seq{opts.trialNo};
end
if isempty(dirs)
    sequenceModeIm = localFieldOrDefault(graph, 'sequenceMode_im', ...
        localFieldOrDefault(graph, 'sequenceMode', false));
    seq = makeSequencex(ex.exp.CoPs.dirs.all, 1, 1, graph.imgs, sequenceModeIm);
    dirs = seq{1};
end

imageName = string(localImageNameFromDir(dirs));
nCoh = numel(targetCoherenceVals);
nVis = numel(targetVisibilityVals);
nPanels = nCoh * nVis;

if nVis == 1 || nCoh == 1
    maxColsSingleRow = 6;
    nTileCols = min(nPanels, maxColsSingleRow);
    nTileRows = ceil(nPanels / nTileCols);
else
    nTileRows = nVis;
    nTileCols = nCoh;
end

imgPanels = cell(nVis, nCoh);
infoPanels = cell(nVis, nCoh);

figWidth = max(420, min(420 * nTileCols, 2200));
figHeight = max(420, min(420 * nTileRows, 1600));
figure('Position', [100 100 figWidth figHeight]);
tiledlayout(nTileRows, nTileCols, 'Padding', 'compact', 'TileSpacing', 'compact');
for iVis = 1:nVis
    for iCoh = 1:nCoh
        [imgPanels{iVis, iCoh}, infoPanels{iVis, iCoh}] = localBuildPanel( ...
            dirs, backgroundNoiseLvl, targetVisibilityVals(iVis), targetMaskSigmaMultVals(min(iVis, numel(targetMaskSigmaMultVals))), targetCoherenceVals(iCoh), ...
            graph, ctl, pos, opts);
        nexttile;
        imagesc(imgPanels{iVis, iCoh});
        axis image off;
        colormap(gray(256));
        hold on;
        if opts.showTargets
            targetRadiusPx = graph.radius * graph.size_mult;
            localDrawCircle(infoPanels{iVis, iCoh}.target1Px(1), infoPanels{iVis, iCoh}.target1Px(2), targetRadiusPx);
            if all(isfinite(infoPanels{iVis, iCoh}.target2Px))
                localDrawCircle(infoPanels{iVis, iCoh}.target2Px(1), infoPanels{iVis, iCoh}.target2Px(2), targetRadiusPx);
            end
        end
        title(sprintf('%s | coh=%.2f | vis=%.2f', imageName, targetCoherenceVals(iCoh), targetVisibilityVals(iVis)), ...
            'Interpreter', 'none');
    end
end

if nPanels == 1
    img = imgPanels{1,1};
    info = infoPanels{1,1};
else
    img = imgPanels;
    info = infoPanels;
end
end


function value = localFirstScalar(x, fallback)
if nargin < 2
    fallback = NaN;
end
if isempty(x)
    value = fallback;
elseif isscalar(x)
    value = double(x);
else
    value = double(x(1));
end
end


function values = localVector(x, fallback)
if nargin < 2
    fallback = NaN;
end
if isempty(x)
    values = fallback;
else
    values = double(x(:)');
end
end


function [img, info] = localBuildPanel(dirs, backgroundNoiseLvl, targetVisibility, targetMaskSigmaMult, targetCoherence, graph, ctl, pos, opts)
targetNum = ctl.target_num;
sizeMult = graph.size_mult;
radius = graph.radius;
fullAsBackground = graph.full_as_background;
maskSigma = (radius / 3) * targetMaskSigmaMult;
targetHiddenBoundsFrac = localFirstScalar(localFieldOrDefault(ctl, 'targetHiddenBoundsFrac', 0), 0);
if isfield(opts, 'targetHiddenBoundsFrac') && ~isempty(opts.targetHiddenBoundsFrac)
    targetHiddenBoundsFrac = localFirstScalar(opts.targetHiddenBoundsFrac, targetHiddenBoundsFrac);
end
if ~isfinite(targetHiddenBoundsFrac)
    targetHiddenBoundsFrac = 0;
end
targetHiddenBoundsFrac = max(0, targetHiddenBoundsFrac);

if fullAsBackground
    targetWord = 'scramble';
    backgroundWord = 'full';
else
    targetWord = 'full';
    backgroundWord = 'scramble';
end

noiseDir = localResolveNoiseDir(dirs, backgroundNoiseLvl);
[targetDirName, targetFilePrefix] = localResolveTargetCoherenceFolder(noiseDir, targetWord, targetCoherence);
targetDir = fullfile(noiseDir, targetDirName);
backgroundDir = fullfile(noiseDir, backgroundWord);

targetList = dir(fullfile(targetDir, [targetFilePrefix '*.mat']));
backgroundList = dir(fullfile(backgroundDir, [backgroundWord '*.mat']));
if targetCoherence <= 0
    if isempty(backgroundList)
        error('plotTex:MissingStimulusFiles', ...
            'No stimulus files found.\nBackground folder: %s', ...
            backgroundDir);
    end
elseif isempty(targetList) || isempty(backgroundList)
    error('plotTex:MissingStimulusFiles', ...
        'No stimulus files found.\nTarget folder: %s\nBackground folder: %s', ...
        targetDir, backgroundDir);
end

backgroundFile = fullfile(backgroundDir, backgroundList(1).name);
backi = load(backgroundFile);
backgroundImg = backi.([backgroundWord '_tp']);
if targetCoherence <= 0
    targetFile = '';
    targetImg = double(backgroundImg);
else
    targetFile = fullfile(targetDir, targetList(1).name);
    targi = load(targetFile);
    targetImg = localExtractTargetImage(targi, targetWord, targetDirName);
    backgroundImg = localMatchImageMean(backgroundImg, targetImg);
end

targetVisibility = min(max(targetVisibility, 0), 1);
[imgHeight, imgWidth] = size(targetImg);

if opts.uniformBlend
    combTex = targetVisibility * double(targetImg) + (1 - targetVisibility) * double(backgroundImg);
    pixelX1 = NaN;
    pixelY1 = NaN;
    pixelX2 = NaN;
    pixelY2 = NaN;
else
    cx1 = pos.initx1;
    cy1 = pos.inity1;
    cx2 = pos.initx2;
    cy2 = pos.inity2;
    if opts.targOnly && opts.singleTargetCenter
        cx1 = 0;
        cy1 = 0;
        targetNum = 1;
    end

    [pixelX1, pixelY1] = pix_norm(cx1, cy1, imgWidth, imgHeight, radius, targetHiddenBoundsFrac);
    gaussianMask1 = targetVisibility * gauss_mask(targetImg, pixelX1, pixelY1, radius, maskSigma);
    if opts.targOnly && opts.singleTargetCenter
        circleMask1 = localCircleMask(imgWidth, imgHeight, pixelX1, pixelY1, radius);
        invMask = circleMask1 .* (1 - gaussianMask1);
    else
        invMask = 1 - gaussianMask1;
    end
    target1 = targetImg .* gaussianMask1;
    background = backgroundImg .* invMask;

    pixelX2 = NaN;
    pixelY2 = NaN;
    if targetNum == 2
        [pixelX2, pixelY2] = pix_norm(cx2, cy2, imgWidth, imgHeight, radius, targetHiddenBoundsFrac);
        gaussianMask2 = targetVisibility * gauss_mask(targetImg, pixelX2, pixelY2, radius, maskSigma);
        invMask2 = 1 - gaussianMask2;
        target2 = targetImg .* gaussianMask2;
        background = background .* invMask2;
        if opts.targOnly
            combTex = target1 + target2;
        else
            combTex = background + target1 + target2;
        end
    else
        if opts.targOnly && ~opts.singleTargetCenter
            combTex = target1;
        else
            combTex = background + target1;
        end
    end
end

if opts.useCircles
    if targetNum == 2
        combTex = circles_mat(combTex, pixelX1, pixelY1, pixelX2, pixelY2, radius, 1, 1);
    else
        combTex = circle_mat(combTex, pixelX1, pixelY1, radius, 1, 1);
    end
end

img = imresize(combTex, sizeMult);
img = img - min(img(:));
img = img ./ max(img(:)) * 253 + 1;
if opts.useCircles
    img = clip(img, 1, 254);
end

displayTarget1Px = [pixelX1, pixelY1] * sizeMult;
displayTarget2Px = [NaN, NaN];
if opts.uniformBlend
    displayTarget1Px = [NaN, NaN];
elseif opts.targOnly && opts.singleTargetCenter
    img = localCropAroundTarget(img, displayTarget1Px, radius * sizeMult, opts.cropMarginMult);
    displayTarget1Px = [size(img, 2), size(img, 1)] / 2;
elseif targetNum == 2
    displayTarget2Px = [pixelX2, pixelY2] * sizeMult;
end

info = struct();
info.noiseDir = noiseDir;
info.targetDir = targetDir;
info.backgroundDir = backgroundDir;
info.targetFile = targetFile;
info.backgroundFile = backgroundFile;
info.target1Px = displayTarget1Px;
if targetNum == 2 && ~opts.singleTargetCenter && ~opts.uniformBlend
    info.target2Px = displayTarget2Px;
else
    info.target2Px = [NaN, NaN];
end
info.coherence = targetCoherence;
info.backgroundNoiseLvl = backgroundNoiseLvl;
info.targetVisibility = targetVisibility;
info.targetMaskSigmaMult = targetMaskSigmaMult;
info.targetHiddenBoundsFrac = targetHiddenBoundsFrac;
end


function value = localFieldOrDefault(s, fieldName, fallback)
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);
else
    value = fallback;
end
end


function noiseDir = localResolveNoiseDir(dirs, backgroundNoiseLvl)
dirParts = strsplit(dirs, filesep);
lastPart = dirParts{end};
rootNoiseDirName = '';
if ~isempty(regexp(lastPart, '^noise\\d+$', 'once'))
    rootNoiseDirName = lastPart;
    dirs = fileparts(dirs);
end

availableNoiseDirs = dir(fullfile(dirs, 'noise*'));
availableNoiseDirs = availableNoiseDirs([availableNoiseDirs.isdir]);
availableNoiseNames = {availableNoiseDirs.name};

if backgroundNoiseLvl == 0
    if ~isempty(rootNoiseDirName) && ismember(rootNoiseDirName, availableNoiseNames)
        noiseDirName = rootNoiseDirName;
    elseif ismember('noise1', availableNoiseNames)
        noiseDirName = 'noise1';
    elseif ismember('noise5', availableNoiseNames)
        noiseDirName = 'noise5';
    elseif ~isempty(availableNoiseNames)
        noiseDirName = availableNoiseNames{1};
    else
        error('plotTex:NoNoiseDir', 'No inner noise directories found: %s', dirs);
    end
else
    noiseDirName = ['noise' num2str(backgroundNoiseLvl)];
    if ~ismember(noiseDirName, availableNoiseNames)
        error('plotTex:NoiseDirMissing', 'Requested noise directory does not exist: %s', fullfile(dirs, noiseDirName));
    end
end

noiseDir = fullfile(dirs, noiseDirName);
end


function mask = localCircleMask(width, height, cx, cy, radius)
[x, y] = meshgrid(1:width, 1:height);
mask = double(((x - cx).^2 + (y - cy).^2) <= radius.^2);
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


function img = localExtractTargetImage(targetStruct, targetWord, targetDirName)
img = [];
candidateFields = {};
if strcmp(targetDirName, 'full')
    candidateFields{end+1} = [targetWord '_tp']; %#ok<AGROW>
elseif startsWith(targetDirName, 'mix')
    candidateFields{end+1} = 'mix_tpi'; %#ok<AGROW>
    candidateFields{end+1} = [targetDirName '_tp']; %#ok<AGROW>
    candidateFields{end+1} = [targetDirName '_tpi']; %#ok<AGROW>
end
candidateFields{end+1} = [targetWord '_tp']; %#ok<AGROW>

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

error('plotTex:TargetFieldMissing', 'Could not resolve target image field for target folder %s.', targetDirName);
end


function imgOut = localMatchImageMean(imgIn, targetImg)
imgOut = double(imgIn);
targetMean = mean(double(targetImg(:)), 'omitnan');
imgMean = mean(imgOut(:), 'omitnan');
if isfinite(targetMean) && isfinite(imgMean)
    imgOut = imgOut + (targetMean - imgMean);
end
end


function localDrawCircle(cx, cy, r)
rectangle('Position', [cx - r, cy - r, 2 * r, 2 * r], ...
    'Curvature', [1 1], 'EdgeColor', 'w', 'LineWidth', 1.5);
end


function imgCrop = localCropAroundTarget(img, targetPx, targetRadiusPx, cropMarginMult)
marginPx = max(1, round(targetRadiusPx * cropMarginMult));
x0 = max(1, round(targetPx(1) - marginPx));
x1 = min(size(img, 2), round(targetPx(1) + marginPx));
y0 = max(1, round(targetPx(2) - marginPx));
y1 = min(size(img, 1), round(targetPx(2) + marginPx));
imgCrop = img(y0:y1, x0:x1, :);
end


function imageName = localImageNameFromDir(dirs)
dirParts = strsplit(dirs, filesep);
lastPart = dirParts{end};
if ~isempty(regexp(lastPart, '^noise\\d+$', 'once')) && numel(dirParts) >= 2
    imageName = dirParts{end-1};
else
    imageName = lastPart;
end
end
