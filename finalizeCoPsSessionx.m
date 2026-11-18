function ex = finalizeCoPsSessionx(ex,checkpointFile)
% Finalize cash on every controlled session exit, before closing hardware.
ex.Payout = calculateCoPsPayoutx(ex.Trials,ex.exp.CoPs.pay);
endedEarly = ex.j <= ex.finish;
if ex.quit == 4 && ~isempty(ex.Trials) && isfield(ex.Trials,'trialCompleted')
    endedEarly = endedEarly || (~isempty(ex.Trials(end).trialCompleted) && ...
        ~ex.Trials(end).trialCompleted);
end
hasError = isfield(ex,'lastError') && ~isempty(ex.lastError);
ex.SessionEnd = struct('quitCode',ex.quit,'endedEarly',endedEarly, ...
    'completedPaidTrials',ex.Payout.nTrials);
% Save before waiting for the participant or issuing any shutdown commands.
saveCheckpointLocal(checkpointFile,ex);
alreadyShown = isfield(ex,'Outro') && isfield(ex.Outro,'on') && ...
    isscalar(ex.Outro.on) && isfinite(ex.Outro.on);
if ex.quit == 4 && ex.Payout.nTrials > 0 && ~alreadyShown && ~hasError
    color = ex.idx.bg_lum;
    if ~isempty(ex.Trials) && isfield(ex.Trials,'betweenTrialBackgroundGray') && ...
            ~isempty(ex.Trials(end).betweenTrialBackgroundGray)
        color = ex.Trials(end).betweenTrialBackgroundGray;
    end
    try
        ex = showCoPsOutrox(ex,color,endedEarly);
    catch err
        ex.outroError = err;
        warning('CoPs:OutroFailed','Payout was saved, but the end screen could not complete: %s',err.message);
    end
    saveCheckpointLocal(checkpointFile,ex);
end
end

function saveCheckpointLocal(file,ex)
info = whos('ex');
if info.bytes < 1e9
    save(file,'ex');
else
    save(file,'ex','-v7.3');
end
end
