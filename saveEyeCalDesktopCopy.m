function desktopFile = saveEyeCalDesktopCopy(sourceFile)
% Save a short-name desktop copy of an eye calibration MAT file.

desktopFile = '';
if nargin < 1 || isempty(sourceFile)
    return
end

sourceFile = char(string(sourceFile));
if ~exist(sourceFile, 'file')
    warning('saveEyeCalDesktopCopy:MissingSource', ...
        'Eye calibration source file was not found: %s', sourceFile);
    return
end

[~, baseName, ext] = fileparts(sourceFile);
prefix = regexp(baseName, '^[A-Za-z]{2}', 'match', 'once');
if isempty(prefix)
    prefix = baseName(1:min(2, numel(baseName)));
end
if isempty(prefix)
    warning('saveEyeCalDesktopCopy:BadSourceName', ...
        'Could not derive a desktop eye calibration name from: %s', sourceFile);
    return
end

desktopDir = '/home/vpixx/Desktop';
if ~exist(desktopDir, 'dir')
    mkdir(desktopDir);
end
desktopFile = fullfile(desktopDir, [lower(prefix), ext]);

[ok, message] = copyfile(sourceFile, desktopFile, 'f');
if ~ok
    warning('saveEyeCalDesktopCopy:CopyFailed', ...
        'Could not copy eye calibration file to desktop: %s', message);
end
end
