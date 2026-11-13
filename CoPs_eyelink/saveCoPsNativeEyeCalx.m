function ex = saveCoPsNativeEyeCalx(ex, closeEdf)
% Save a legacy-style EyeCal MAT containing native metadata and validation.
% Retrieve the calibration EDF before runEx replaces it with the session EDF.
if nargin < 2, closeEdf = false; end
if ~isfield(ex.eyeCal.native, 'matFile')
    [fname, ~, calDir] = makeFilenameAndDirx(ex, 'EyeCal');
    ex.eyeCal.native.matFile = fullfile(calDir, fname);
    [~, stem] = fileparts(fname);
    ex.eyeCal.native.edfFile = fullfile(calDir, [stem '.edf']);
end
if closeEdf
    Eyelink('StopRecording');
    Eyelink('SetOfflineMode');
    Eyelink('CloseFile');
    destination = ex.eyeCal.native.edfFile;
    status = Eyelink('ReceiveFile', ex.eyeCal.native.edfHostName, destination, 0);
    ex.eyeCal.native.edfTransferStatus = status;
    if status <= 0 || ~isfile(destination)
        warning('CoPs:CalibrationEdfTransfer', ...
            'Calibration EDF transfer failed (status %g); host file: %s.', ...
            status, ex.eyeCal.native.edfHostName);
    end
end
file = ex.eyeCal.native.matFile;
% Match the old standalone EyeCal layout without mixing validation with task trials.
snapshot = ex;
[directory, stem, extension] = fileparts(file);
snapshot.fileName = [stem extension];
snapshot.dirName = directory;
snapshot.Header.onlineFileName = snapshot.fileName;
snapshot.Header.onlineDirName = directory;
if isfield(ex.eyeCal, 'validation')
    snapshot.Trials = ex.eyeCal.validation.Trials;
end
saveSnapshotLocal(file, snapshot);
end

function saveSnapshotLocal(file, ex)
save(file, 'ex');
end
