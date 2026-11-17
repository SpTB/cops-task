function [ex,shown] = advanceCoPsInstructionFlowx(ex)
% Present the next page only after the preceding practice feedback completes.
shown = false;
if ~isfield(ex.exp.CoPs,'instrOn') || ~ex.exp.CoPs.instrOn || ex.quit ~= 0
    return
end
info = getCoPsTrialBlockInfox(ex);
completed = find(info.instructionIdx == ex.j-1,1);
if isempty(completed), return; end
if completed == 1
    stage = 'dynamic';
else
    stage = 'ready';
end
if isfield(ex,'Instructions') && isfield(ex.Instructions,'pages') && ...
        any(strcmp({ex.Instructions.pages.stage},stage) & [ex.Instructions.pages.acknowledged])
    return
end
ex = showCoPsInstructionsx(ex,stage);
shown = true;
end
