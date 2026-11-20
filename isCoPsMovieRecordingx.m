function enabled = isCoPsMovieRecordingx(ex)
% A legacy logical recording flag controls neural recording, not movies.
enabled = isfield(ex.setup,'recording') && isstruct(ex.setup.recording) && ...
    isfield(ex.setup.recording,'enabled') && ex.setup.recording.enabled;
end
