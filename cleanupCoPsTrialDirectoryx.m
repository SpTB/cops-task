function cleanupCoPsTrialDirectoryx(trDir)
% Called after saving the session MAT. Practice subfolders remain permanent.
if ~isfolder(trDir), return; end
checkpoints = dir(fullfile(trDir,'*.mat'));
for k = find(~[checkpoints.isdir])
    delete(fullfile(trDir,checkpoints(k).name));
end
entries = dir(trDir);
entries = entries(~ismember({entries.name},{'.','..'}));
if isempty(entries)
    [removed,message] = rmdir(trDir);
    if ~removed
        warning('CoPs:TrialDirectoryCleanup','Could not remove empty trial directory: %s',message);
    end
end
end
