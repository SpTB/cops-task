function ex = completeCoPsPauseActionsx(ex,checkpointFile)
% Checkpoint before hardware setup, then save the result before another trial.
if ex.quit ~= 0 || ~isfield(ex,'Recalibration') || ...
        ~isfield(ex.Recalibration,'pending') || isempty(ex.Recalibration.pending)
    return
end
saveCheckpointLocal(checkpointFile,ex);
ex = recalibrateCoPsx(ex);
saveCheckpointLocal(checkpointFile,ex);
end

function saveCheckpointLocal(file,ex)
info = whos('ex');
if info.bytes < 1e9
    save(file,'ex');
else
    save(file,'ex','-v7.3');
end
end
