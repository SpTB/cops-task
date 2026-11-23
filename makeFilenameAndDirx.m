function [fname, dirName, trDir] = makeFilenameAndDirx(ex, fileSuffix)
% Choose a session filename and reserve its per-trial directory.

if nargin < 2
    if isfield(ex, 'exp') && isfield(ex.exp, 'CoPs')
        fileSuffix = makeFilenameSuffixCoPsx(ex);
    else
        fileSuffix = makeFilenameSuffix(ex);
    end
end
fileSuffix = localText(fileSuffix, 'fileSuffix');
if ~isempty(regexp(fileSuffix, '[<>:"/\\|?*\x00-\x1F\x7F]', 'once'))
    error('makeFilenameAndDirx:InvalidSuffix', ...
        'fileSuffix must not contain path separators or invalid filename characters.');
end

header = struct();
if isfield(ex, 'Header')
    header = ex.Header;
end
hasAnimal = isfield(header, 'animal');
hasSubjectID = isfield(header, 'subjectID') && ~isempty(header.subjectID);
hasPrefix = isfield(ex.setup, 'filePrefix') && ~isempty(ex.setup.filePrefix);

if hasPrefix && (hasAnimal || hasSubjectID)
    % Explicit subject input takes priority over the old animal-name mapping.
    filePrefix = normalizeCoPsSubjectIDx(ex.setup.filePrefix);
elseif hasSubjectID
    filePrefix = normalizeCoPsSubjectIDx(header.subjectID);
elseif hasAnimal
    [filePrefix, ~] = localAnimalIdentity(header.animal);
else
    % Preserve the legacy prompt when only the automatic default prefix exists.
    enteredPrefix = input('Please input the file prefix (e.g. ma, ka, or a participant ID): ', 's');
    if isempty(strtrim(enteredPrefix))
        enteredPrefix = 't';
    end
    filePrefix = normalizeCoPsSubjectIDx(enteredPrefix);
end

if hasSubjectID
    % Keep all participant data together, including calibration and test runs.
    subjectFolder = normalizeCoPsSubjectIDx(header.subjectID);
elseif hasAnimal
    [~, subjectFolder] = localAnimalIdentity(header.animal);
else
    subjectFolder = localFolderForPrefix(filePrefix);
end

timestamp = now;
dateString = datestr(timestamp, 'yyyy.mm.dd');
timeString = datestr(timestamp, 'HH.MM');
if isfield(header, 'SessionID') && ~isempty(header.SessionID)
    timeString = [sanitizeCoPsFilePrefixx(header.SessionID) '_' timeString];
end
dirName = fullfile(localText(ex.setup.dirRoot, 'setup.dirRoot'), subjectFolder, dateString);
localMakeDirectory(dirName);

sessionNumber = 1;
while true
    sessionTime = timeString;
    if sessionNumber > 1
        sessionTime = sprintf('%s_%02d', timeString, sessionNumber);
    end
    stem = [filePrefix '_' sessionTime '.' fileSuffix];
    fname = [stem '.mat'];
    trDir = fullfile(dirName, stem);
    if exist(trDir, 'file') == 0 && ...
            exist(fullfile(dirName, fname), 'file') == 0 && ...
            exist(fullfile(dirName, 'experimental', fname), 'file') == 0
        break
    end
    sessionNumber = sessionNumber + 1;
end
localMakeDirectory(trDir);
end


function [prefix, folder] = localAnimalIdentity(animal)
animal = lower(strtrim(localText(animal, 'Header.animal')));
animals = {'kiwi', 'mango', 'kaki', 'lychee', 'lemieux', ...
    'tempura', 'hummus', 'shocktop', 'barnum', 'jocamo'};
prefixes = {'ki', 'ma', 'ka', 'ly', 'le', 'te', 'hu', 'sh', 'ba', 'jo'};
idx = find(strcmp(animal, animals), 1);
if isempty(idx)
    prefix = 't';
    folder = 'test';
else
    prefix = prefixes{idx};
    folder = animals{idx};
end
end


function folder = localFolderForPrefix(prefix)
prefixes = {'ki', 'ma', 'ka', 'ly', 'le', 'te', 'hu', 'sh', 'ba', 'jo'};
folders = {'kiwi', 'mango', 'kaki', 'lychee', 'lemieux', ...
    'tempura', 'hummus', 'shocktop', 'barnum', 'jocamo'};
idx = find(strcmpi(prefix, prefixes), 1);
if isempty(idx)
    folder = prefix;
else
    folder = folders{idx};
end
end


function value = localText(value, fieldName)
if isstring(value) && isscalar(value) && ~ismissing(value)
    value = char(value);
elseif ~(ischar(value) && (isrow(value) || isempty(value)))
    error('makeFilenameAndDirx:InvalidText', '%s must be a text scalar.', fieldName);
end
end


function localMakeDirectory(directory)
if exist(directory, 'dir') ~= 7
    [success, message] = mkdir(directory);
    if ~success
        error('makeFilenameAndDirx:CreateDirectoryFailed', ...
            'Could not create output directory %s: %s', directory, message);
    end
end
end
