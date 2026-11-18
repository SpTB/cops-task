function [wasLoaded, value] = loadSavedVar(filePaths, varName)
%LOADSAVEDVAR Load a named variable from the first existing cache file.

wasLoaded = false;
value = [];
for pathIdx = 1:numel(filePaths)
    filePath = filePaths{pathIdx};
    if isfile(filePath)
        try
            loaded = load(filePath, varName);
        catch ME
            warning('process_imgs2:LoadCachedVarFailed', ...
                'Could not load %s from %s: %s', varName, char(filePath), ME.message);
            continue
        end
        if isfield(loaded, varName)
            value = loaded.(varName);
            wasLoaded = true;
            fprintf('Loaded %s from %s\n', varName, char(filePath));
            return
        end
        warning('process_imgs2:CachedVarMissing', ...
            '%s exists but does not contain variable %s.', char(filePath), varName);
    end
end

end
