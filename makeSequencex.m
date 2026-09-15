function out = makeSequencex(dirs, N, levels_deep, allowedImgs, sequenceModeIm, activeTrialMask)
% dirs: a character string with the path to all stim dirs
% N: number of trials
if nargin < 4
    allowedImgs = [];
end
if nargin < 5
    sequenceModeIm = false;
end
if nargin < 6
    activeTrialMask = [];
end

dirs = char(dirs);
if ~exist(dirs, 'dir')
    error('makeSequencex:MissingStimulusRoot', ...
        'Stimulus root folder does not exist: %s', dirs);
end

sequenceModeIm = localScalarLogical(sequenceModeIm, false);
activeTrialMask = localActiveTrialMask(activeTrialMask, N);
leafDirs = resolveCoPsStimulusDirs(dirs, levels_deep, allowedImgs, sequenceModeIm);

% Resample repeats if need more trials (N) than dirs. In sequence mode,
% cycle through the selected folders. If graph.imgs/allowedImgs is empty,
% the selected folders are simply all discovered stimulus folders.
numLeafDirs = numel(leafDirs);
idx = randi(numLeafDirs, 1, N);   % random fallback, including inactive trials
if sequenceModeIm
    activeIdx = find(activeTrialMask);
    idx(activeIdx) = mod(0:(numel(activeIdx) - 1), numLeafDirs) + 1;
end
out = leafDirs(idx);
end


function mask = localActiveTrialMask(mask, nTrials)
if isempty(mask)
    mask = true(1, nTrials);
    return
end
if isnumeric(mask) || islogical(mask)
    mask = logical(mask(:)');
else
    mask = true(1, nTrials);
    return
end
if numel(mask) < nTrials
    mask = [mask, false(1, nTrials - numel(mask))];
elseif numel(mask) > nTrials
    mask = mask(1:nTrials);
end
end


function value = localScalarLogical(value, defaultValue)
if nargin < 2
    defaultValue = false;
end
if isempty(value)
    value = defaultValue;
    return
end
if isstring(value)
    text = strtrim(char(value(1)));
    value = any(strcmpi(text, {'true', '1', 'yes', 'on'}));
elseif ischar(value)
    text = strtrim(value);
    value = any(strcmpi(text, {'true', '1', 'yes', 'on'}));
else
    value = logical(value(1));
end
end
