function ex = recoverRunExCrashFromTrials(sessionDir, outFile)
% recoverRunExCrashFromTrials Rebuild a runEx session MAT from per-trial files.
%
%   ex = recoverRunExCrashFromTrials(sessionDir)
%   ex = recoverRunExCrashFromTrials(sessionDir, outFile)
%
% sessionDir should point to the crash-recovery directory that contains:
%   - <sessionName>.mat   initial checkpoint written before trials started
%   - tr1.mat, tr2.mat, ... per-trial saves written after each completed trial
%
% If outFile is omitted, the recovered file is written to:
%   <parent(sessionDir)>/experimental/<sessionName>.mat

if nargin < 2
    outFile = '';
end

sessionDir = char(sessionDir);
outFile = char(outFile);

if ~isfolder(sessionDir)
    error('recoverRunExCrashFromTrials:MissingSessionDir', ...
        'Session directory does not exist: %s', sessionDir);
end

[parentDir, leafName, leafExt] = fileparts(sessionDir);
sessionName = [leafName leafExt];
checkpointFile = fullfile(sessionDir, [sessionName '.mat']);
if ~isfile(checkpointFile)
    error('recoverRunExCrashFromTrials:MissingCheckpoint', ...
        'Checkpoint file not found: %s', checkpointFile);
end

s = load(checkpointFile);
if ~isfield(s, 'ex') || ~isstruct(s.ex)
    error('recoverRunExCrashFromTrials:InvalidCheckpoint', ...
        'Checkpoint file does not contain an ex struct: %s', checkpointFile);
end
ex0 = s.ex;
if isOctaveLocal()
    ex = sanitizeCheckpointEx(ex0);
else
    ex = ex0;
end

trialFiles = dir(fullfile(sessionDir, 'tr*.mat'));
if isempty(trialFiles)
    error('recoverRunExCrashFromTrials:NoTrialFiles', ...
        'No tr*.mat files found in %s', sessionDir);
end

trialNums = nan(numel(trialFiles), 1);
for i = 1:numel(trialFiles)
    tok = regexp(trialFiles(i).name, '^tr(\d+)\.mat$', 'tokens', 'once');
    if isempty(tok)
        error('recoverRunExCrashFromTrials:UnexpectedTrialFile', ...
            'Unexpected file in trial directory: %s', trialFiles(i).name);
    end
    trialNums(i) = str2double(tok{1});
end

[trialNums, sortIdx] = sort(trialNums);
trialFiles = trialFiles(sortIdx);

expectedNums = (1:max(trialNums))';
missingTrials = setdiff(expectedNums, trialNums);
if ~isempty(missingTrials)
    error('recoverRunExCrashFromTrials:MissingTrialFiles', ...
        'Missing trial files: %s', mat2str(missingTrials'));
end

trials = repmat(loadTrial(fullfile(sessionDir, trialFiles(1).name)), numel(trialFiles), 1);
trials(1) = loadTrial(fullfile(sessionDir, trialFiles(1).name));
for i = 2:numel(trialFiles)
    trials(i) = loadTrial(fullfile(sessionDir, trialFiles(i).name));
end

ex.Trials = trials(:);
ex.j = numel(ex.Trials) + 1;

if isfield(ex, 'finish') && isnumeric(ex.finish) && isscalar(ex.finish)
    nLoop = max(double(ex.finish), numel(ex.Trials));
else
    nLoop = numel(ex.Trials);
end
ex.goodtrial = sum(abs([ex.Trials.Reward]));
ex.loopcnt = nan(1, nLoop);
ex.changedBlock = 0;
ex.quit = 0;

if ~isfield(ex, 'times') || ~isstruct(ex.times)
    ex.times = struct();
end
ex.times.remappingSD = struct('norm', NaN, 'delta', NaN(1, numel(ex.Trials)));
ex.times.PTBvsDatapixxClockRatio = NaN;

expDir = fullfile(parentDir, 'experimental');
edfDir = fullfile(parentDir, 'edf');
if isempty(outFile)
    outFile = fullfile(expDir, [sessionName '.mat']);
else
    outFile = char(outFile);
end

[outDir, outName, outExt] = fileparts(outFile);
if isempty(outExt)
    outFile = fullfile(outDir, [outName '.mat']);
end

if ~isfolder(outDir)
    mkdir(outDir);
end

if ~isfield(ex, 'Header') || ~isstruct(ex.Header)
    ex.Header = struct();
end
ex.Header.onlineDirName = char(parentDir);
ex.Header.onlineExperimentalDirName = char(expDir);
ex.Header.onlineEdfDirName = char(edfDir);
ex.Header.onlineFileName = [outName '.mat'];

whosEx = whos('ex');
if isOctaveLocal()
    if whosEx.bytes < 1e9
        save('-mat', outFile, 'ex');
    else
        save('-mat7-binary', outFile, 'ex');
    end
else
    if whosEx.bytes < 1e9
        save(outFile, 'ex');
    else
        save(outFile, 'ex', '-v7.3');
    end
end
end

function trial = loadTrial(pathStr)
s = load(pathStr);
if ~isfield(s, 'Trials') || ~isstruct(s.Trials)
    error('recoverRunExCrashFromTrials:InvalidTrialFile', ...
        'Trial file does not contain struct Trials: %s', pathStr);
end
trial = s.Trials;
end

function ex = sanitizeCheckpointEx(ex0)
fields = fieldnames(ex0);
ex = struct();
for i = 1:numel(fields)
    name = fields{i};
    switch name
        case 'setup'
            ex.setup = sanitizeSetup(ex0.setup);
        case 'Header'
            ex.Header = sanitizeHeader(ex0.Header);
        otherwise
            ex.(name) = ex0.(name);
    end
end
end

function setup = sanitizeSetup(setup0)
fields = fieldnames(setup0);
setup = struct();
for i = 1:numel(fields)
    name = fields{i};
    if strcmp(name, 'filePrefix')
        setup.filePrefix = '';
    else
        setup.(name) = setup0.(name);
    end
end
end

function header = sanitizeHeader(header0)
fields = fieldnames(header0);
header = struct();
for i = 1:numel(fields)
    name = fields{i};
    if strcmp(name, 'experimenter')
        header.experimenter = '';
    else
        header.(name) = header0.(name);
    end
end
end

function tf = isOctaveLocal()
tf = (exist('OCTAVE_VERSION', 'builtin') ~= 0);
end
