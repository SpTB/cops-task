function ex = prepareCoPsMovieOutputx(ex)
% Separate per-session movie folder, outside the temporary trial MAT folder.
[~,stem] = fileparts(ex.Header.onlineFileName);
base = char(ex.setup.recording.outputDir);
if isempty(base), base = fullfile(ex.Header.onlineDirName,'movies'); end
directory = fullfile(base,stem);
if ~isfolder(directory)
    [ok,message] = mkdir(directory);
    if ~ok, error('recEx:OutputDirectory','Cannot create movie directory: %s',message); end
end
[ok,attributes] = fileattrib(directory);
if ~ok, error('recEx:OutputDirectory','Cannot resolve movie directory: %s',directory); end
ex.setup.recording.outputDirectory = attributes.Name;
fprintf('CoPs movies: %s\n',attributes.Name);
end
