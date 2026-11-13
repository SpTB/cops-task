function [result, exMerged] = exportHMM(monkey, dateValue, opts)
% exportHMM  Merge held-out HMM predictions, process gaze, and export trials.
%
%   result = exportHMM(monkey, dateValue, opts)
%   result = exportHMM('kaki', 'Jul19', opts)
%
% Required options
%   opts.model             'tid', 'sm', or 'sm3'
%   opts.hmmHardThreshold  hard-state threshold for tid/sm (default 0.9).
%                          SM3 instead uses the most probable of T1/T2/N.
%   opts.distanceUnits     'deg' (default) or legacy 'px'; applied to both
%                          trial and optional chunk exports.
%
% Common optional fields
%   opts.outDir            destination for *_hmm_trials.csv files
%   opts.dataRoot          raw CoPs root (default Y:\data\CoPs)
%   opts.hmmRoot           fitted-model root (default ...\output\hmm)
%   opts.predictionFile    explicit prediction CSV (especially useful for tid)
%   opts.block             'all' (default), or chronological one-based
%                          block number(s), e.g. 1 or [1 3]
%   opts.overwrite         overwrite existing CSVs (default false). If all
%                          requested outputs exist, return immediately.
%   opts.processOpts       additional options passed to processCoPsEye
%   opts.exportSelReg      export tracking-chunk CSV via exportSelReg
%                          (default false; set to 1 or true to enable)
%                          If the trials CSV already exists and overwrite
%                          is false, it is preserved while a missing chunks
%                          CSV is added.
%   opts.selRegOpts        optional options passed to exportSelReg
%   opts.exportTrackReg    export tracking-outcome chunk CSV via
%                          exportTrackReg (default false)
%   opts.trackRegOpts      optional options passed to exportTrackReg
%   opts.exportPupilReg    export one-row-per-tracked-episode pupil/distance
%                          regressors (default true). Pupil is normalized
%                          once across all selected blocks (day-wide when
%                          opts.block='all'), then split by block for output.
%   opts.pupilRegOpts      optional options passed to
%                          exportPupilHmmRegressors
%   opts.posCorrected      EyeCal pupil-position correction (default true)
%   opts.correctionScope   'session' (default) groups blocks by their most
%                          recent calibration; 'day' preserves pooled fitting
%   opts.writeOutput       process and write trial CSVs (default true).
%                          False is used internally by the day-level
%                          mergeCoPsHmmStruct(monkey,date) overload.
%
% SM and SM3 prediction files contain all eligible blocks for a day. The
% function maps their block column to chronologically sorted raw session
% files. Legacy TID fits are session-specific; when the CSV has no block
% column, opts.block is required unless the block can be inferred from an
% '_sN' filename token or the day has only one raw session.
%
% dateValue accepts YYYY.MM.DD, YYYY-MM-DD, or a case-insensitive short
% month/day such as 'Jul19'. Short dates are resolved against the monkey's
% folders under opts.dataRoot; a repeated month/day across years is treated
% as ambiguous and requires the full date.
%
% The default output directory is:
%   <hmmRoot>\<model-folder>\processed
% Default filenames begin with the short monkey ID, for example:
%   ka_2026.07.19_b01_sm3_hmm_trials.csv
% With opts.block='all', all processed block tables are stacked into:
%   ka_2026.07.19_sm3_hmm_trials.csv
% and, when opts.exportSelReg=1:
%   ka_2026.07.19_sm3_hmm_chunks.csv
% The default pupil-regression output is:
%   ka_2026.07.19_sm3_hmm_pupil_episodes.csv
%
% result is one row per processed block and reports the raw input,
% prediction file, merge coverage, and output CSV path.

if nargin < 3 || isempty(opts)
    opts = struct();
end
if ~isstruct(opts) || ~isscalar(opts)
    error('exportHMM:BadOptions', 'opts must be a scalar structure.');
end
opts = localOptionDefaults(opts);

animal = localNormalizeAnimal(monkey);
dateLabel = localNormalizeDate(dateValue, opts.dataRoot, animal);
model = validatestring(lower(char(opts.model)), {'tid', 'sm', 'sm3'});
validateattributes(opts.hmmHardThreshold, {'numeric'}, ...
    {'scalar', 'real', 'finite', '>', 0.5, '<=', 1}, mfilename, ...
    'opts.hmmHardThreshold');
combineBlockOutput = localIsAllBlockOption(opts.block);
opts.block = localResolveBlockOption(opts.block);

[modelFolder, predictionPattern] = localModelLocation(model, animal, dateLabel);
if strlength(string(opts.outDir)) == 0
    outDir = fullfile(char(opts.hmmRoot), modelFolder, 'processed');
else
    outDir = char(opts.outDir);
end
if opts.writeOutput && ~isfolder(outDir)
    mkdir(outDir);
end

rawDir = fullfile(char(opts.dataRoot), animal, dateLabel, 'experimental');
rawFiles = localSessionFiles(rawDir);
predictionPath = localResolvePredictionFile(opts.predictionFile, ...
    opts.hmmRoot, modelFolder, predictionPattern);
predictions = readtable(predictionPath, 'VariableNamingRule', 'preserve');
predictions = localNormalizePredictionColumns(predictions);

if ismember('block', predictions.Properties.VariableNames)
    blocks = unique(double(predictions.block(isfinite(predictions.block))))';
else
    blocks = localTidBlock(predictionPath, rawFiles, opts.block);
    predictions.block = repmat(blocks, height(predictions), 1);
end
if ~isempty(opts.block)
    blocks = intersect(blocks, double(opts.block(:))', 'stable');
end
if isempty(blocks)
    error('exportHMM:NoSelectedBlocks', ...
        'No prediction rows matched the requested block selection.');
end

if opts.writeOutput && ~opts.overwrite
    [expectedTrials, expectedChunks, expectedTracking, expectedPupil] = localExpectedOutputPaths( ...
        outDir, animal, dateLabel, model, blocks, combineBlockOutput, ...
        opts.exportSelReg, opts.exportTrackReg, opts.exportPupilReg);
    requestedPaths = expectedTrials;
    unitCheckedPaths = expectedTrials;
    if opts.exportSelReg
        requestedPaths = [requestedPaths; expectedChunks];
        unitCheckedPaths = [unitCheckedPaths; expectedChunks];
    end
    if opts.exportTrackReg
        requestedPaths = [requestedPaths; expectedTracking];
        unitCheckedPaths = [unitCheckedPaths; expectedTracking];
    end
    if opts.exportPupilReg
        requestedPaths = [requestedPaths; expectedPupil];
    end
    localValidateExistingOutputUnits(unitCheckedPaths, opts.distanceUnits);
    if ~isempty(requestedPaths) && all(isfile(requestedPaths))
        fprintf('exportHMM: all requested output files already exist; nothing to do.\n');
        for index = 1:numel(requestedPaths)
            fprintf('  %s\n', requestedPaths(index));
        end
        result = localExistingOutputResult( ...
            animal, dateLabel, model, blocks, rawFiles, predictionPath, ...
            expectedTrials, expectedChunks, expectedTracking, expectedPupil, ...
            combineBlockOutput, opts.exportSelReg, opts.exportTrackReg, ...
            opts.exportPupilReg);
        exMerged = struct('Trials', []);
        return
    end
end


rows = repmat(localEmptyResult(), 0, 1);
exList = cell(0, 1);
sessionNames = cell(0, 1);
trialTables = cell(0, 1);
chunkTables = cell(0, 1);
trackTables = cell(0, 1);
pupilTables = cell(0, 1);
pupilExByBlock = cell(numel(rawFiles), 1);
pupilSessionNames = cell(numel(rawFiles), 1);
for block = blocks
    if block < 1 || block > numel(rawFiles) || block ~= round(block)
        error('exportHMM:BadBlock', ...
            'Prediction block %g does not map to raw sessions 1..%d.', ...
            block, numel(rawFiles));
    end
    blockPredictions = predictions(predictions.block == block, :);
    if isempty(blockPredictions)
        continue
    end
    blockPredictions = sortrows(blockPredictions, {'trial_no', 'step'});
    hmm = localPredictionTableToHmm(blockPredictions, ...
        opts.hmmHardThreshold, model, animal, dateLabel, block, predictionPath);

    rawPath = fullfile(rawFiles(block).folder, rawFiles(block).name);
    loaded = load(rawPath);
    ex = localResolveEx(loaded, rawPath);
    [ex, mergeReport] = mergeCoPsHmmStruct(ex, hmm);
    ex = localAnnotateMergedBlock(ex, block, rawPath);
    exList{end + 1, 1} = ex; %#ok<AGROW>
    sessionNames{end + 1, 1} = rawFiles(block).name; %#ok<AGROW>
    pupilExByBlock{block} = ex;
    pupilSessionNames{block} = rawFiles(block).name;

    outputPath = '';
    nTrialsExported = NaN;
    if opts.writeOutput
        processOpts = opts.processOpts;
        processOpts.trackingSource = 'hmmSmoothed';
        processOpts.hmmHardThreshold = opts.hmmHardThreshold;
        processOpts.distanceUnits = opts.distanceUnits;
        out = processCoPsEye(ex, processOpts);
        blockTrials = out.trialSummary;
        blockTrials.block = repmat(block, height(blockTrials), 1);
        blockTrials = movevars(blockTrials, 'block', 'Before', 1);
        nTrialsExported = height(blockTrials);
        blockChunks = table();
        if opts.exportSelReg
            selRegOpts = opts.selRegOpts;
            selRegOpts.writeCsv = false;
            selRegOpts.distanceUnits = opts.distanceUnits;
            selRegOpts.monkey = localAnimalPrefix(animal);
            selRegOpts.date = dateLabel;
            blockChunks = exportSelReg(ex, '', selRegOpts);
            blockChunks.block = repmat(block, height(blockChunks), 1);
            blockChunks = movevars(blockChunks, 'block', 'Before', 1);
        end
        blockTracking = table();
        if opts.exportTrackReg
            trackRegOpts = opts.trackRegOpts;
            trackRegOpts.writeCsv = false;
            trackRegOpts.distanceUnits = opts.distanceUnits;
            trackRegOpts.monkey = localAnimalPrefix(animal);
            trackRegOpts.date = dateLabel;
            blockTracking = exportTrackReg(ex, '', trackRegOpts);
            blockTracking.block = repmat(block, height(blockTracking), 1);
            blockTracking = movevars(blockTracking, 'block', 'Before', 1);
        end
        if combineBlockOutput
            trialTables{end + 1, 1} = blockTrials; %#ok<AGROW>
            if opts.exportSelReg
                chunkTables{end + 1, 1} = blockChunks; %#ok<AGROW>
            end
            if opts.exportTrackReg
                trackTables{end + 1, 1} = blockTracking; %#ok<AGROW>
            end
        else
            outputName = sprintf('%s_%s_b%02d_%s_hmm_trials.csv', ...
                localAnimalPrefix(animal), dateLabel, block, model);
            outputPath = fullfile(outDir, outputName);
            writeTrials = localShouldWriteOutput( ...
                outputPath, opts.overwrite, ...
                opts.exportSelReg || opts.exportTrackReg || opts.exportPupilReg);
            chunkPath = '';
            if opts.exportSelReg
                chunkName = sprintf('%s_%s_b%02d_%s_hmm_chunks.csv', ...
                    localAnimalPrefix(animal), dateLabel, block, model);
                chunkPath = fullfile(outDir, chunkName);
                writeChunks = localShouldWriteOutput( ...
                    chunkPath, opts.overwrite, true);
            end
            trackingPath = '';
            if opts.exportTrackReg
                trackingName = sprintf('%s_%s_b%02d_%s_hmm_tracking.csv', ...
                    localAnimalPrefix(animal), dateLabel, block, model);
                trackingPath = fullfile(outDir, trackingName);
                writeTracking = localShouldWriteOutput( ...
                    trackingPath, opts.overwrite, true);
            end
            if writeTrials
                writetable(blockTrials, outputPath);
            end
            if opts.exportSelReg && writeChunks
                writetable(blockChunks, chunkPath);
            end
            if opts.exportTrackReg && writeTracking
                writetable(blockTracking, trackingPath);
            end
        end
    end

    row = localEmptyResult();
    row.monkey = string(animal);
    row.date = string(dateLabel);
    row.model = string(model);
    row.block = block;
    row.rawFile = string(rawPath);
    row.predictionFile = string(predictionPath);
    row.outputFile = string(outputPath);
    if opts.writeOutput && opts.exportSelReg && ~combineBlockOutput
        row.chunkFile = string(chunkPath);
        row.nChunksExported = height(blockChunks);
    end
    if opts.writeOutput && opts.exportTrackReg && ~combineBlockOutput
        row.trackingFile = string(trackingPath);
        row.nTrackingChunksExported = height(blockTracking);
    end
    row.nPredictionRows = height(blockPredictions);
    row.nTrialsMatched = mergeReport.nTrialsMatched;
    row.nPredictedSteps = mergeReport.nPredictedSteps;
    row.nTrialsExported = nTrialsExported;
    row.status = "completed";
    rows(end + 1, 1) = row; %#ok<AGROW>
    if opts.writeOutput && ~combineBlockOutput
        if writeTrials
            fprintf('[%s %s block %d] saved %d trials to %s\n', ...
                upper(model), dateLabel, block, nTrialsExported, outputPath);
        else
            fprintf('[%s %s block %d] kept existing trials file %s\n', ...
                upper(model), dateLabel, block, outputPath);
        end
    elseif opts.writeOutput
        fprintf('[%s %s block %d] processed %d trials for combined output\n', ...
            upper(model), dateLabel, block, nTrialsExported);
    else
        fprintf('[%s %s block %d] merged %d predicted steps\n', ...
            upper(model), dateLabel, block, mergeReport.nPredictedSteps);
    end
end

exMerged = localBindMergedBlocks(exList, sessionNames, animal, dateLabel, model);
if opts.writeOutput && opts.exportPupilReg
    % Establish one pupil center/scale from every raw block in the day. Raw
    % blocks not requested for HMM output are included only for normalization;
    % without attached HMM states they cannot contribute episode rows.
    for normalizationBlock = 1:numel(rawFiles)
        if ~isempty(pupilExByBlock{normalizationBlock})
            continue
        end
        normalizationPath = fullfile( ...
            rawFiles(normalizationBlock).folder, rawFiles(normalizationBlock).name);
        normalizationLoaded = load(normalizationPath);
        normalizationEx = localResolveEx(normalizationLoaded, normalizationPath);
        normalizationEx = localAnnotateMergedBlock( ...
            normalizationEx, normalizationBlock, normalizationPath);
        pupilExByBlock{normalizationBlock} = normalizationEx;
        pupilSessionNames{normalizationBlock} = rawFiles(normalizationBlock).name;
    end
    pupilNormalizationEx = localBindMergedBlocks( ...
        pupilExByBlock, pupilSessionNames, animal, dateLabel, model);
    pupilRegOpts = opts.pupilRegOpts;
    pupilRegOpts.writeCsv = false;
    if ~isfield(pupilRegOpts,'posCorrected')||isempty(pupilRegOpts.posCorrected)
        pupilRegOpts.posCorrected=opts.posCorrected;
    end
    if ~isfield(pupilRegOpts,'correctionScope')||isempty(pupilRegOpts.correctionScope)
        pupilRegOpts.correctionScope=opts.correctionScope;
    end
    if ~isfield(pupilRegOpts,'posCorrectionSource')||isempty(pupilRegOpts.posCorrectionSource)
        pupilRegOpts.posCorrectionSource=opts.posCorrectionSource;
    end
    if ~isfield(pupilRegOpts,'sacCor')||isempty(pupilRegOpts.sacCor)
        pupilRegOpts.sacCor=opts.sacCor;
    end
    if ~isfield(pupilRegOpts,'sacCorrectionSource')||isempty(pupilRegOpts.sacCorrectionSource)
        pupilRegOpts.sacCorrectionSource=opts.sacCorrectionSource;
    end
    pupilRegOpts.posCorrectionAnimal=animal;
    pupilRegOpts.posCorrectionDate=dateLabel;
    if ~isfield(pupilRegOpts,'posCorrectionOpts')|| ...
            isempty(pupilRegOpts.posCorrectionOpts)
        pupilRegOpts.posCorrectionOpts=struct();
    end
    if ~isfield(pupilRegOpts.posCorrectionOpts,'dataRoot')|| ...
            isempty(pupilRegOpts.posCorrectionOpts.dataRoot)
        pupilRegOpts.posCorrectionOpts.dataRoot=opts.dataRoot;
    end
    dayPupil = exportPupilHmmRegressors( ...
        pupilNormalizationEx, '', pupilRegOpts);
    normalizationScope = "day";
    dayPupil.pupilNormalizationScope = repmat( ...
        normalizationScope, height(dayPupil), 1);
    dayPupil.nPupilNormalizationTrials = repmat( ...
        numel(pupilNormalizationEx.Trials), height(dayPupil), 1);
    pupilTables = cell(numel(rows), 1);
    for index = 1:numel(rows)
        block = rows(index).block;
        blockPupil = dayPupil(dayPupil.block == block, :);
        pupilTables{index} = blockPupil;
        if ~combineBlockOutput
            pupilName = sprintf('%s_%s_b%02d_%s_hmm_pupil_episodes.csv', ...
                localAnimalPrefix(animal), dateLabel, block, model);
            pupilPath = fullfile(outDir, pupilName);
            writePupil = localShouldWriteOutput( ...
                pupilPath, opts.overwrite, true);
            if writePupil
                writetable(blockPupil, pupilPath);
            end
            rows(index).pupilEpisodeFile = string(pupilPath);
            rows(index).nPupilEpisodesExported = height(blockPupil);
        end
    end
end

if opts.writeOutput && combineBlockOutput
    combinedTrials = vertcat(trialTables{:});
    outputName = sprintf('%s_%s_%s_hmm_trials.csv', ...
        localAnimalPrefix(animal), dateLabel, model);
    outputPath = fullfile(outDir, outputName);
    writeTrials = localShouldWriteOutput( ...
        outputPath, opts.overwrite, ...
        opts.exportSelReg || opts.exportTrackReg || opts.exportPupilReg);
    chunkPath = '';
    if opts.exportSelReg
        combinedChunks = vertcat(chunkTables{:});
        chunkName = sprintf('%s_%s_%s_hmm_chunks.csv', ...
            localAnimalPrefix(animal), dateLabel, model);
        chunkPath = fullfile(outDir, chunkName);
        writeChunks = localShouldWriteOutput( ...
            chunkPath, opts.overwrite, true);
    end
    trackingPath = '';
    if opts.exportTrackReg
        combinedTracking = vertcat(trackTables{:});
        trackingName = sprintf('%s_%s_%s_hmm_tracking.csv', ...
            localAnimalPrefix(animal), dateLabel, model);
        trackingPath = fullfile(outDir, trackingName);
        writeTracking = localShouldWriteOutput( ...
            trackingPath, opts.overwrite, true);
    end
    pupilPath = '';
    if opts.exportPupilReg
        combinedPupil = vertcat(pupilTables{:});
        pupilName = sprintf('%s_%s_%s_hmm_pupil_episodes.csv', ...
            localAnimalPrefix(animal), dateLabel, model);
        pupilPath = fullfile(outDir, pupilName);
        writePupil = localShouldWriteOutput(pupilPath, opts.overwrite, true);
    end
    if writeTrials
        writetable(combinedTrials, outputPath);
    end
    if opts.exportSelReg && writeChunks
        writetable(combinedChunks, chunkPath);
    end
    if opts.exportTrackReg && writeTracking
        writetable(combinedTracking, trackingPath);
    end
    if opts.exportPupilReg && writePupil
        writetable(combinedPupil, pupilPath);
    end
    for index = 1:numel(rows)
        rows(index).outputFile = string(outputPath);
        if opts.exportSelReg
            rows(index).chunkFile = string(chunkPath);
            rows(index).nChunksExported = height( ...
                chunkTables{index});
        end
        if opts.exportTrackReg
            rows(index).trackingFile = string(trackingPath);
            rows(index).nTrackingChunksExported = height(trackTables{index});
        end
        if opts.exportPupilReg
            rows(index).pupilEpisodeFile = string(pupilPath);
            rows(index).nPupilEpisodesExported = height(pupilTables{index});
        end
    end
    if writeTrials
        fprintf('[%s %s all blocks] saved %d trials from %d blocks to %s\n', ...
            upper(model), dateLabel, height(combinedTrials), numel(trialTables), ...
            outputPath);
    else
        fprintf('[%s %s all blocks] kept existing trials file %s\n', ...
            upper(model), dateLabel, outputPath);
    end
    if opts.exportSelReg
        fprintf('[%s %s all blocks] saved %d chunks to %s\n', ...
            upper(model), dateLabel, height(combinedChunks), chunkPath);
    end
    if opts.exportTrackReg
        fprintf('[%s %s all blocks] saved %d tracking chunks to %s\n', ...
            upper(model), dateLabel, height(combinedTracking), trackingPath);
    end
    if opts.exportPupilReg
        fprintf('[%s %s all blocks] saved %d pupil episodes to %s\n', ...
            upper(model), dateLabel, height(combinedPupil), pupilPath);
    end
end

result = struct2table(rows);
end


function localValidateExistingOutputUnits(paths, units)
paths = string(paths(:));
paths = paths(isfile(paths));
for i = 1:numel(paths)
    fid = fopen(paths(i), 'r');
    if fid < 0
        continue
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    header = fgetl(fid);
    if ~ischar(header)
        continue
    end
    hasPx = contains(header, 'Px') || contains(header, 'px');
    hasDeg = contains(header, 'Deg') || contains(header, 'deg');
    mismatch = (strcmp(units, 'deg') && hasPx) || ...
        (strcmp(units, 'px') && hasDeg && ~hasPx);
    if mismatch
        error('exportHMM:ExistingOutputUnits', ...
            ['Existing output uses different distance units: %s\n' ...
             'Set opts.overwrite=true to regenerate it with distanceUnits=''%s''.'], ...
            paths(i), units);
    end
end
end


function opts = localOptionDefaults(opts)
defaults = struct( ...
    'model', 'sm3', ...
    'hmmHardThreshold', 0.9, ...
    'distanceUnits', 'deg', ...
    'outDir', '', ...
    'dataRoot', 'Y:\data\CoPs', ...
    'hmmRoot', fullfile( ...
        'C:\Users\zajkowskiwk\OneDrive - National Institutes of Health', ...
        'cops_project', 'output', 'hmm'), ...
    'predictionFile', '', ...
    'block', 'all', ...
    'overwrite', false, ...
    'exportSelReg', false, ...
    'selRegOpts', struct(), ...
    'exportTrackReg', false, ...
    'trackRegOpts', struct(), ...
    'exportPupilReg', true, ...
    'correctionScope', 'session', ...
    'posCorrected', true, ...
    'posCorrectionSource', 'calibration', ...
    'sacCor', false, ...
    'sacCorrectionSource', 'calibration', ...
    'pupilRegOpts', struct(), ...
    'writeOutput', true, ...
    'processOpts', struct());
names = fieldnames(defaults);
for index = 1:numel(names)
    name = names{index};
    if ~isfield(opts, name) || isempty(opts.(name))
        opts.(name) = defaults.(name);
    end
end

if ~(ischar(opts.model) || (isstring(opts.model) && isscalar(opts.model)))
    error('exportHMM:BadModel', 'opts.model must be text.');
end
if ~(ischar(opts.distanceUnits) || ...
        (isstring(opts.distanceUnits) && isscalar(opts.distanceUnits)))
    error('exportHMM:BadOptions', 'opts.distanceUnits must be ''deg'' or ''px''.');
end
opts.distanceUnits = lower(strtrim(char(opts.distanceUnits)));
if ~ismember(opts.distanceUnits, {'deg', 'px'})
    error('exportHMM:BadOptions', 'opts.distanceUnits must be ''deg'' or ''px''.');
end
textFields = {'outDir', 'dataRoot', 'hmmRoot', 'predictionFile'};
for index = 1:numel(textFields)
    value = opts.(textFields{index});
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        error('exportHMM:BadOptions', 'opts.%s must be text.', textFields{index});
    end
end
if ~islogical(opts.overwrite) || ~isscalar(opts.overwrite)
    error('exportHMM:BadOptions', 'opts.overwrite must be a logical scalar.');
end
if ~(isscalar(opts.exportSelReg) && ...
        (islogical(opts.exportSelReg) || isnumeric(opts.exportSelReg)) && ...
        isfinite(double(opts.exportSelReg)) && ...
        ismember(double(opts.exportSelReg), [0 1]))
    error('exportHMM:BadOptions', ...
        'opts.exportSelReg must be a logical scalar or numeric 0/1.');
end
opts.exportSelReg = logical(opts.exportSelReg);
if ~isstruct(opts.selRegOpts) || ~isscalar(opts.selRegOpts)
    error('exportHMM:BadOptions', 'opts.selRegOpts must be a scalar structure.');
end
if ~(isscalar(opts.exportTrackReg) && ...
        (islogical(opts.exportTrackReg) || isnumeric(opts.exportTrackReg)) && ...
        isfinite(double(opts.exportTrackReg)) && ...
        ismember(double(opts.exportTrackReg), [0 1]))
    error('exportHMM:BadOptions', ...
        'opts.exportTrackReg must be a logical scalar or numeric 0/1.');
end
opts.exportTrackReg = logical(opts.exportTrackReg);
if ~isstruct(opts.trackRegOpts) || ~isscalar(opts.trackRegOpts)
    error('exportHMM:BadOptions', ...
        'opts.trackRegOpts must be a scalar structure.');
end
if ~(isscalar(opts.exportPupilReg) && ...
        (islogical(opts.exportPupilReg) || isnumeric(opts.exportPupilReg)) && ...
        isfinite(double(opts.exportPupilReg)) && ...
        ismember(double(opts.exportPupilReg), [0 1]))
    error('exportHMM:BadOptions', ...
        'opts.exportPupilReg must be a logical scalar or numeric 0/1.');
end
opts.exportPupilReg = logical(opts.exportPupilReg);
if ~(isscalar(opts.posCorrected) && ...
        (islogical(opts.posCorrected)||isnumeric(opts.posCorrected)) && ...
        isfinite(double(opts.posCorrected)) && ...
        ismember(double(opts.posCorrected),[0 1]))
    error('exportHMM:BadOptions', ...
        'opts.posCorrected must be a logical scalar or numeric 0/1.');
end
opts.posCorrected=logical(opts.posCorrected);
opts.correctionScope=validatestring( ...
    char(string(opts.correctionScope)),{'session','day'});
opts.posCorrectionSource=validatestring( ...
    char(string(opts.posCorrectionSource)),{'calibration','experimental'});
if ~(isscalar(opts.sacCor) && ...
        (islogical(opts.sacCor)||isnumeric(opts.sacCor)) && ...
        isfinite(double(opts.sacCor)) && ismember(double(opts.sacCor),[0 1]))
    error('exportHMM:BadOptions', ...
        'opts.sacCor must be a logical scalar or numeric 0/1.');
end
opts.sacCor=logical(opts.sacCor);
opts.sacCorrectionSource=validatestring( ...
    char(string(opts.sacCorrectionSource)),{'calibration','experimental'});
if ~isstruct(opts.pupilRegOpts) || ~isscalar(opts.pupilRegOpts)
    error('exportHMM:BadOptions', ...
        'opts.pupilRegOpts must be a scalar structure.');
end
if ~islogical(opts.writeOutput) || ~isscalar(opts.writeOutput)
    error('exportHMM:BadOptions', 'opts.writeOutput must be a logical scalar.');
end
if ~isstruct(opts.processOpts) || ~isscalar(opts.processOpts)
    error('exportHMM:BadOptions', 'opts.processOpts must be a scalar structure.');
end
end


function blocks = localResolveBlockOption(value)
if ischar(value) || (isstring(value) && isscalar(value))
    if strcmpi(strtrim(char(value)), 'all')
        blocks = [];
        return
    end
    error('exportHMM:BadBlock', ...
        'opts.block must be ''all'' or positive integer block number(s).');
end


validateattributes(value, {'numeric'}, ...
    {'vector', 'integer', 'positive', 'finite'}, mfilename, 'opts.block');
blocks = double(value(:))';
end


function tf = localIsAllBlockOption(value)
tf = (ischar(value) || (isstring(value) && isscalar(value))) ...
    && strcmpi(strtrim(char(value)), 'all');
end


function shouldWrite = localShouldWriteOutput(path, overwrite, allowExisting)
shouldWrite = true;
if isfile(path) && ~overwrite
    if allowExisting
        shouldWrite = false;
        fprintf('exportHMM: preserving existing file: %s\n', path);
        return
    end
    error('exportHMM:OutputExists', ...
        ['Output already exists: %s\nSet opts.overwrite=true or choose ' ...
         'a different opts.outDir.'], path);
end
end


function [trialPaths, chunkPaths, trackingPaths, pupilPaths] = localExpectedOutputPaths( ...
        outDir, animal, dateLabel, model, blocks, combineBlocks, ...
        includeChunks, includeTracking, includePupil)
prefix = localAnimalPrefix(animal);
if combineBlocks
    trialPaths = string(fullfile(outDir, sprintf( ...
        '%s_%s_%s_hmm_trials.csv', prefix, dateLabel, model)));
    if includeChunks
        chunkPaths = string(fullfile(outDir, sprintf( ...
            '%s_%s_%s_hmm_chunks.csv', prefix, dateLabel, model)));
    else
        chunkPaths = strings(0, 1);
    end
    if includePupil
        pupilPaths = string(fullfile(outDir, sprintf( ...
            '%s_%s_%s_hmm_pupil_episodes.csv', prefix, dateLabel, model)));
    else
        pupilPaths = strings(0, 1);
    end
    if includeTracking
        trackingPaths = string(fullfile(outDir, sprintf( ...
            '%s_%s_%s_hmm_tracking.csv', prefix, dateLabel, model)));
    else
        trackingPaths = strings(0, 1);
    end
    return
end
trialPaths = strings(numel(blocks), 1);
chunkPaths = strings(0, 1);
trackingPaths = strings(0, 1);
if includeChunks
    chunkPaths = strings(numel(blocks), 1);
end
if includeTracking
    trackingPaths = strings(numel(blocks), 1);
end
pupilPaths = strings(0, 1);
if includePupil
    pupilPaths = strings(numel(blocks), 1);
end
for index = 1:numel(blocks)
    trialPaths(index) = string(fullfile(outDir, sprintf( ...
        '%s_%s_b%02d_%s_hmm_trials.csv', ...
        prefix, dateLabel, blocks(index), model)));
    if includeChunks
        chunkPaths(index) = string(fullfile(outDir, sprintf( ...
            '%s_%s_b%02d_%s_hmm_chunks.csv', ...
            prefix, dateLabel, blocks(index), model)));
    end
    if includePupil
        pupilPaths(index) = string(fullfile(outDir, sprintf( ...
            '%s_%s_b%02d_%s_hmm_pupil_episodes.csv', ...
            prefix, dateLabel, blocks(index), model)));
    end
    if includeTracking
        trackingPaths(index) = string(fullfile(outDir, sprintf( ...
            '%s_%s_b%02d_%s_hmm_tracking.csv', ...
            prefix, dateLabel, blocks(index), model)));
    end
end
end


function result = localExistingOutputResult( ...
        animal, dateLabel, model, blocks, rawFiles, predictionPath, ...
        trialPaths, chunkPaths, trackingPaths, pupilPaths, combineBlocks, ...
        includeChunks, includeTracking, includePupil)
rows = repmat(localEmptyResult(), numel(blocks), 1);
for index = 1:numel(blocks)
    block = blocks(index);
    if block < 1 || block > numel(rawFiles) || block ~= round(block)
        error('exportHMM:BadBlock', ...
            'Prediction block %g does not map to raw sessions 1..%d.', ...
            block, numel(rawFiles));
    end
    if combineBlocks
        trialPath = trialPaths(1);
        if includeChunks
            chunkPath = chunkPaths(1);
        else
            chunkPath = "";
        end
        if includePupil
            pupilPath = pupilPaths(1);
        else
            pupilPath = "";
        end
        if includeTracking
            trackingPath = trackingPaths(1);
        else
            trackingPath = "";
        end
    else
        trialPath = trialPaths(index);
        if includeChunks
            chunkPath = chunkPaths(index);
        else
            chunkPath = "";
        end
        if includePupil
            pupilPath = pupilPaths(index);
        else
            pupilPath = "";
        end
        if includeTracking
            trackingPath = trackingPaths(index);
        else
            trackingPath = "";
        end
    end
    rows(index).monkey = string(animal);
    rows(index).date = string(dateLabel);
    rows(index).model = string(model);
    rows(index).block = block;
    rows(index).rawFile = string(fullfile( ...
        rawFiles(block).folder, rawFiles(block).name));
    rows(index).predictionFile = string(predictionPath);
    rows(index).outputFile = trialPath;
    rows(index).chunkFile = chunkPath;
    rows(index).trackingFile = trackingPath;
    rows(index).pupilEpisodeFile = pupilPath;
    rows(index).nPredictionRows = NaN;
    rows(index).nTrialsMatched = NaN;
    rows(index).nPredictedSteps = NaN;
    rows(index).nTrialsExported = NaN;
    rows(index).nChunksExported = NaN;
    rows(index).nTrackingChunksExported = NaN;
    rows(index).nPupilEpisodesExported = NaN;
    rows(index).status = "already-exists";
end
result = struct2table(rows);
end


function animal = localNormalizeAnimal(value)
animal = lower(strtrim(char(value)));
switch animal
    case {'ka', 'kaki'}
        animal = 'kaki';
    case {'ly', 'lychee'}
        animal = 'lychee';
    otherwise
        error('exportHMM:BadMonkey', ...
            'monkey must be kaki/ka or lychee/ly.');
end
end


function prefix = localAnimalPrefix(animal)
switch animal
    case 'kaki'
        prefix = 'ka';
    case 'lychee'
        prefix = 'ly';
    otherwise
        error('exportHMM:BadMonkey', 'Unknown normalized monkey %s.', animal);
end
end


function label = localNormalizeDate(value, dataRoot, animal)
text = regexprep(strtrim(char(value)), '[-_]', '.');
if ~isempty(regexp(text, '^[A-Za-z]{3}\d{1,2}$', 'once'))
    try
        monthDay = datetime(lower(text), 'InputFormat', 'MMMdd', ...
            'Locale', 'en_US');
    catch
        error('exportHMM:BadDate', ...
            'Could not interpret short date %s; use a value such as Jul19.', text);
    end
    animalDir = fullfile(char(dataRoot), animal);
    folders = dir(fullfile(animalDir, '????.??.??'));
    folders = folders([folders.isdir]);
    matches = strings(0, 1);
    for index = 1:numel(folders)
        try
            candidate = datetime(folders(index).name, ...
                'InputFormat', 'yyyy.MM.dd');
        catch
            continue
        end
        if month(candidate) == month(monthDay) && day(candidate) == day(monthDay)
            matches(end + 1, 1) = string(folders(index).name); %#ok<AGROW>
        end
    end
    matches = unique(matches);
    if isempty(matches)
        error('exportHMM:MissingShortDate', ...
            'No %s session folder matching %s was found under %s.', ...
            animal, text, animalDir);
    elseif numel(matches) > 1
        error('exportHMM:AmbiguousShortDate', ...
            ['Short date %s matches multiple years for %s: %s. ' ...
             'Specify the full YYYY.MM.DD date.'], ...
            text, animal, strjoin(cellstr(matches), ', '));
    end
    label = char(matches(1));
    return
end
try
    parsed = datetime(text, 'InputFormat', 'yyyy.MM.dd');
catch
    error('exportHMM:BadDate', ...
        ['date must use YYYY.MM.DD, YYYY-MM-DD, or a short month/day ' ...
         'such as Jul19.']);
end
if isnat(parsed)
    error('exportHMM:BadDate', 'Could not interpret date %s.', text);
end
label = char(string(parsed, 'yyyy.MM.dd'));
end


function [folder, pattern] = localModelLocation(model, animal, dateLabel)
switch model
    case 'tid'
        folder = 'tid';
        pattern = '*_tid_cv_predictions.csv';
    case 'sm'
        folder = 'tidSM';
        pattern = sprintf('%s_%s_targetidsens_random_effect_cv*_predictions.csv', ...
            animal, dateLabel);
    case 'sm3'
        folder = 'tidSM3';
        pattern = sprintf(['%s_%s_targetidsens3_distance_gated_' ...
            'random_effect_cv*_predictions.csv'], animal, dateLabel);
end
end


function path = localResolvePredictionFile(explicitPath, hmmRoot, folder, pattern)
if strlength(string(explicitPath)) > 0
    path = char(explicitPath);
    if ~isfile(path)
        error('exportHMM:MissingPredictions', ...
            'Prediction CSV does not exist: %s', path);
    end
    return
end
predictionDir = fullfile(char(hmmRoot), folder, 'preds');
matches = dir(fullfile(predictionDir, pattern));
matches = matches(~[matches.isdir]);
if isempty(matches)
    error('exportHMM:MissingPredictions', ...
        ['No prediction CSV matched %s in %s. For a session-specific TID ' ...
         'fit, set opts.predictionFile explicitly.'], pattern, predictionDir);
end
if numel(matches) > 1
    [~, newest] = max([matches.datenum]);
    warning('exportHMM:MultiplePredictions', ...
        'Found %d matching prediction files; using newest: %s', ...
        numel(matches), matches(newest).name);
    matches = matches(newest);
end
path = fullfile(matches.folder, matches.name);
end


function files = localSessionFiles(folder)
if ~isfolder(folder)
    error('exportHMM:MissingRawDirectory', ...
        'Raw experimental directory does not exist: %s', folder);
end
files = dir(fullfile(folder, '*.mat'));
keep = ~[files.isdir];
names = string({files.name});
keep = keep & ~startsWith(names, 'dailyLog', 'IgnoreCase', true) ...
    & ~contains(names, 'EyeCal', 'IgnoreCase', true) ...
    & ~endsWith(names, '_modelling_processed.mat', 'IgnoreCase', true) ...
    & ~contains(names, 'hmm_predictions', 'IgnoreCase', true);
files = files(keep);
if isempty(files)
    error('exportHMM:MissingRawSessions', ...
        'No raw session MAT files were found in %s.', folder);
end
keys = zeros(numel(files), 1);
for index = 1:numel(files)
    token = regexp(files(index).name, '^[A-Za-z]+_(\d{1,2})\.(\d{2})', ...
        'tokens', 'once');
    if isempty(token)
        keys(index) = 1e6 + files(index).datenum;
    else
        keys(index) = str2double(token{1}) * 60 + str2double(token{2});
    end
end
names = lower(string({files.name}))';
orderTable = table(keys, names, (1:numel(files))', ...
    'VariableNames', {'key', 'name', 'index'});
orderTable = sortrows(orderTable, {'key', 'name'});
files = files(orderTable.index);
end


function block = localTidBlock(predictionPath, rawFiles, requestedBlock)
if ~isempty(requestedBlock)
    if numel(requestedBlock) ~= 1
        error('exportHMM:TidMultipleBlocks', ...
            'A session-specific TID prediction CSV can map to only one block.');
    end
    block = double(requestedBlock);
    return
end
[~, name] = fileparts(predictionPath);
token = regexp(name, '_s(\d+)(?:_|$)', 'tokens', 'once', 'ignorecase');
if ~isempty(token)
    block = str2double(token{1});
elseif numel(rawFiles) == 1
    block = 1;
else
    error('exportHMM:TidBlockRequired', ...
        ['The TID prediction CSV has no block column and its filename does ' ...
         'not identify a session. Set opts.block to the chronological ' ...
         'one-based session number.']);
end
end


function tableOut = localNormalizePredictionColumns(tableIn)
tableOut = tableIn;
names = tableOut.Properties.VariableNames;
aliases = {
    'trial_idx', 'trial_no';
    'trialIdx', 'trial_no';
    't_rel', 'time_sec';
    'tRelSec', 'time_sec'
};
for index = 1:size(aliases, 1)
    if ismember(aliases{index, 1}, names) && ~ismember(aliases{index, 2}, names)
        tableOut.Properties.VariableNames{aliases{index, 1}} = aliases{index, 2};
        names = tableOut.Properties.VariableNames;
    end
end
required = {'trial_no', 'step', 'predictive_pTLeft', ...
    'filtered_pTLeft', 'smoothed_pTLeft', 'pCloser'};
missing = setdiff(required, tableOut.Properties.VariableNames);
if ~isempty(missing)
    error('exportHMM:BadPredictionCsv', ...
        'Prediction CSV is missing required columns: %s', strjoin(missing, ', '));
end
numericNames = intersect({'block', 'trial_no', 'step', 'time_sec', ...
    'predictive_pTLeft', 'predictive_pTRight', ...
    'filtered_pTLeft', 'filtered_pTRight', ...
    'smoothed_pTLeft', 'smoothed_pTRight', 'pCloser'}, ...
    tableOut.Properties.VariableNames, 'stable');
for index = 1:numel(numericNames)
    value = tableOut.(numericNames{index});
    if ~isnumeric(value)
        tableOut.(numericNames{index}) = str2double(string(value));
    end
end
end


function hmm = localPredictionTableToHmm(T, threshold, model, animal, ...
        dateLabel, block, predictionPath)
trialNo = double(T.trial_no(:));
step = double(T.step(:));
if any(~isfinite(trialNo) | trialNo < 1 | trialNo ~= round(trialNo)) ...
        || any(~isfinite(step) | step < 1 | step ~= round(step))
    error('exportHMM:BadPredictionIndex', ...
        'trial_no and step must contain positive integer indices.');
end
if height(unique(table(trialNo, step), 'rows')) ~= height(T)
    error('exportHMM:DuplicatePredictionRows', ...
        'Prediction CSV contains duplicate trial_no/step rows for block %d.', block);
end

smoothedLeft = double(T.smoothed_pTLeft(:));
smoothedRight = localRightProbability(T, 'smoothed', smoothedLeft);
pCloser = double(T.pCloser(:));
leftIsCloser = localInferCloserSide(trialNo, pCloser, ...
    smoothedLeft, smoothedRight);

hmm = struct();
hmm.trialIdx = int32(trialNo);
hmm.step = int32(step);
if ismember('time_sec', T.Properties.VariableNames)
    hmm.tRelSec = double(T.time_sec(:));
else
    hmm.tRelSec = nan(height(T), 1);
end
methods = {'predictive', 'filtered', 'smoothed'};
for index = 1:numel(methods)
    methodName = methods{index};
    left = double(T.([methodName '_pTLeft'])(:));
    right = localRightProbability(T, methodName, left);
    nonTracking = localNonTrackingProbability(T, methodName, left);
    closer = nan(size(left));
    farther = nan(size(left));
    known = isfinite(leftIsCloser);
    closer(known & leftIsCloser == 1) = left(known & leftIsCloser == 1);
    farther(known & leftIsCloser == 1) = right(known & leftIsCloser == 1);
    closer(known & leftIsCloser == 0) = right(known & leftIsCloser == 0);
    farther(known & leftIsCloser == 0) = left(known & leftIsCloser == 0);
    if strcmp(methodName, 'smoothed')
        closer(isfinite(pCloser)) = pCloser(isfinite(pCloser));
    end
    if strcmp(model, 'sm3')
        hardTarget = localWinningState(left, right, nonTracking);
        hardCloser = localWinningState(closer, farther, nonTracking);
    else
        hardTarget = localHardState(left, right, threshold);
        hardCloser = localHardState(closer, farther, threshold);
    end
    hmm.(methodName) = struct( ...
        'pTLeft', left, ...
        'pTRight', right, ...
        'pNonTracking', nonTracking, ...
        'pCloser', closer, ...
        'hardTLeft', hardTarget, ...
        'hardCloser', hardCloser);
end
hmm.meta = struct( ...
    'model', model, 'animal', animal, 'date', dateLabel, ...
    'block', block, 'predictionFile', predictionPath, ...
    'hardThreshold', threshold, 'predictionType', 'out-of-fold');
end


function right = localRightProbability(T, methodName, left)
rightName = [methodName '_pTRight'];
if ismember(rightName, T.Properties.VariableNames)
    right = double(T.(rightName)(:));
else
    right = 1 - left;
end
end


function probability = localNonTrackingProbability(T, methodName, left)
name = [methodName '_pNonTracking'];
if ismember(name, T.Properties.VariableNames)
    probability = double(T.(name)(:));
else
    probability = nan(size(left));
end
end


function leftIsCloser = localInferCloserSide(trialNo, pCloser, left, right)
leftIsCloser = nan(size(pCloser));
valid = isfinite(pCloser) & isfinite(left) & isfinite(right);
leftDifference = abs(pCloser - left);
rightDifference = abs(pCloser - right);
informative = valid & abs(leftDifference - rightDifference) > 1e-10;
leftIsCloser(informative) = leftDifference(informative) < rightDifference(informative);

% At exact probability ties the side is not identifiable from the exported
% posterior. Use the closest informative step within the same trial. This
% affects predictive/filtered pCloser only; the exported smoothed pCloser is
% retained exactly.
for value = unique(trialNo(:))'
    rows = find(trialNo == value);
    side = leftIsCloser(rows);
    if any(isfinite(side))
        side = fillmissing(side, 'nearest');
    end
    leftIsCloser(rows) = side;
end
end


function hard = localHardState(firstProbability, secondProbability, threshold)
hard = nan(size(firstProbability));
defined = isfinite(firstProbability) & isfinite(secondProbability);
hard(defined) = 0;
hard(defined & firstProbability > threshold) = 1;
hard(defined & secondProbability > threshold) = 2;
end


function hard = localWinningState(firstProbability, secondProbability, ...
        nonTrackingProbability)
hard = nan(size(firstProbability));
defined = isfinite(firstProbability) & isfinite(secondProbability) ...
    & isfinite(nonTrackingProbability);
hard(defined) = 0;
hard(defined & firstProbability > secondProbability ...
    & firstProbability > nonTrackingProbability) = 1;
hard(defined & secondProbability > firstProbability ...
    & secondProbability > nonTrackingProbability) = 2;
end


function ex = localResolveEx(loaded, path)
if isfield(loaded, 'ex') && isstruct(loaded.ex)
    ex = loaded.ex;
    return
end
names = fieldnames(loaded);
isCandidate = false(size(names));
for index = 1:numel(names)
    value = loaded.(names{index});
    isCandidate(index) = isstruct(value) && isfield(value, 'Trials');
end
candidateNames = names(isCandidate);
if numel(candidateNames) == 1
    ex = loaded.(candidateNames{1});
    return
end
error('exportHMM:MissingEx', ...
    'Could not identify one ex structure with a Trials field in %s.', path);
end


function ex = localAnnotateMergedBlock(ex, block, rawPath)
if ~isfield(ex, 'Trials')
    return
end
fields = { ...
    'trialInSession', NaN; 'originalTrialNo', NaN; ...
    'sessionInDay', NaN; 'sourceFileName', ""; 'sourceFilePath', ""};
for index = 1:size(fields, 1)
    if ~isfield(ex.Trials, fields{index, 1})
        [ex.Trials.(fields{index, 1})] = deal(fields{index, 2});
    end
end
[~, name, extension] = fileparts(rawPath);
for trialNo = 1:numel(ex.Trials)
    ex.Trials(trialNo).trialInSession = trialNo;
    ex.Trials(trialNo).originalTrialNo = trialNo;
    ex.Trials(trialNo).sessionInDay = block;
    ex.Trials(trialNo).sourceFileName = string([name extension]);
    ex.Trials(trialNo).sourceFilePath = string(rawPath);
end
end


function exMerged = localBindMergedBlocks(exList, sessionNames, animal, dateLabel, model)
if isempty(exList)
    exMerged = struct('Trials', []);
    return
elseif numel(exList) == 1
    exMerged = exList{1};
else
    helperDir = fullfile(fileparts(mfilename('fullpath')), 'helpers');
    if exist('exBind', 'file') ~= 2 && isfolder(helperDir)
        addpath(helperDir);
    end
    exMerged = exBind(exList, 'SessionNames', sessionNames);
end
dayTrial = 0;
for trialNo = 1:numel(exMerged.Trials)
    dayTrial = dayTrial + 1;
    exMerged.Trials(trialNo).trial = dayTrial;
    exMerged.Trials(trialNo).trialDay = dayTrial;
    exMerged.Trials(trialNo).dayTrial = dayTrial;
end
if ~isfield(exMerged, 'hmmMeta') || ~isstruct(exMerged.hmmMeta)
    exMerged.hmmMeta = struct();
end
exMerged.hmmMeta.dayMerge = struct( ...
    'animal', animal, 'date', dateLabel, 'model', model, ...
    'nBlocks', numel(exList), 'nTrials', numel(exMerged.Trials));
end


function row = localEmptyResult()
row = struct( ...
    'monkey', "", 'date', "", 'model', "", 'status', "", 'block', nan, ...
    'rawFile', "", 'predictionFile', "", 'outputFile', "", ...
    'chunkFile', "", 'trackingFile', "", 'pupilEpisodeFile', "", ...
    'nPredictionRows', 0, 'nTrialsMatched', 0, ...
    'nPredictedSteps', 0, 'nTrialsExported', 0, 'nChunksExported', 0, ...
    'nTrackingChunksExported', 0, ...
    'nPupilEpisodesExported', 0);
end
