function stimDirs = resolveCoPsStimulusDirs(rootDir, levelsDeep, allowedImgs, preserveAllowedOrder)
% Resolve CoPs stimulus folders after applying graph.imgs selection.

if nargin < 2 || isempty(levelsDeep)
    levelsDeep = 1;
end
if nargin < 3
    allowedImgs = [];
end
if nargin < 4 || isempty(preserveAllowedOrder)
    preserveAllowedOrder = false;
end

rootDir = char(rootDir);
if ~exist(rootDir, 'dir')
    error('resolveCoPsStimulusDirs:MissingStimulusRoot', ...
        'Stimulus root folder does not exist: %s', rootDir);
end

stimDirs = getLeafDirs(rootDir, levelsDeep);
if isempty(stimDirs)
    error('resolveCoPsStimulusDirs:NoStimulusFolders', ...
        'No stimulus folders were found under: %s', rootDir);
end

if isempty(allowedImgs)
    stimDirs = stimDirs(:)';
    return
end

allowedImgs = localNormalizeAllowedImgs(allowedImgs);
leafNames = cell(size(stimDirs));
for i = 1:numel(stimDirs)
    [~, leafNames{i}] = fileparts(stimDirs{i});
end

if preserveAllowedOrder
    orderedDirs = cell(1, numel(allowedImgs));
    for i = 1:numel(allowedImgs)
        matchIdx = find(strcmp(leafNames, allowedImgs{i}), 1, 'first');
        if isempty(matchIdx)
            error('resolveCoPsStimulusDirs:MissingSequenceStimulus', ...
                'Requested sequence stimulus "%s" was not found under: %s', allowedImgs{i}, rootDir);
        end
        orderedDirs{i} = stimDirs{matchIdx};
    end
    stimDirs = orderedDirs;
else
    keep = false(size(stimDirs));
    for i = 1:numel(stimDirs)
        keep(i) = any(strcmp(leafNames{i}, allowedImgs));
    end
    stimDirs = stimDirs(keep);
end

if isempty(stimDirs)
    error('resolveCoPsStimulusDirs:NoMatchingStimulusFolders', ...
        'No stimulus folders matched the requested graph.imgs selection under: %s', rootDir);
end
stimDirs = stimDirs(:)';
end


function allowed = localNormalizeAllowedImgs(allowedImgs)
if ischar(allowedImgs)
    allowed = cellstr(allowedImgs);
elseif isstring(allowedImgs)
    allowed = cellstr(allowedImgs(:));
elseif iscell(allowedImgs)
    allowed = cellfun(@char, allowedImgs(:), 'UniformOutput', false);
else
    error('resolveCoPsStimulusDirs:InvalidAllowedImgs', ...
        'allowedImgs must be char, string, or cell array of text.');
end
allowed = strtrim(allowed);
allowed = allowed(~cellfun(@isempty, allowed));
end
