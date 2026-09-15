function leafDirs = getLeafDirs(topDir, levels_deep)
% getLeafDirs  Recursively find all leaf directories under topDir
%
% A leaf directory is defined as a folder that has no subfolders
% (excluding '.' and '..').
d = dir(topDir);
d = d([d.isdir]);  % keep only directories

% Remove '.' and '..'
names = {d.name};
d = d(~ismember(names, {'.','..'}));

leafDirs = {};

for k = 1:numel(d)
    thisDir = fullfile(d(k).folder, d(k).name);
    
    % Check for subdirectories
    sub = dir(thisDir);
    sub = sub([sub.isdir]);
    subNames = {sub.name};
    sub = sub(~ismember(subNames, {'.','..'}));
    
    if (isempty(sub) || levels_deep==1)
        % No subfolders → leaf directory
        leafDirs{end+1,1} = thisDir; %#ok<AGROW>
    else
        % Recurse deeper
        next_levels_deep = levels_deep - 1;
        deeper = getLeafDirs(thisDir, next_levels_deep);
        leafDirs = [leafDirs; deeper]; %#ok<AGROW>
    end
end

end
