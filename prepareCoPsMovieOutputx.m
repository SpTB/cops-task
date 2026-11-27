function ex = prepareCoPsMovieOutputx(ex)
% Resolve the movie folder without adding per-session subfolders.
directory = char(ex.setup.recording.outputDir);
if isempty(directory), directory = fullfile(fileparts(mfilename('fullpath')),'demo','movies'); end
if ~isfolder(directory)
    [ok,message] = mkdir(directory);
    if ~ok, error('recEx:OutputDirectory','Cannot create movie directory: %s',message); end
end
[ok,attributes] = fileattrib(directory);
if ~ok, error('recEx:OutputDirectory','Cannot resolve movie directory: %s',directory); end
ex.setup.recording.outputDirectory = attributes.Name;
fprintf('CoPs movies: %s\n',attributes.Name);
end
