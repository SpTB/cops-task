baseDir = '/home/vpixx/stim/cops/food';
folders = dir(baseDir);

for i = 1:length(folders)
    if folders(i).isdir && ~ismember(folders(i).name, {'.','..'})
        fullPath = fullfile(baseDir, folders(i).name, 'noise30', 'scramble');
        if exist(fullPath, 'dir')
            files = dir(fullfile(fullPath, '*'));
            files = files(~[files.isdir]); % remove directories
            fprintf('%s: %d files\n', folders(i).name, length(files));
        end
    end
end