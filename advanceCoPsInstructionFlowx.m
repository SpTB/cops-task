function [ex,shown] = advanceCoPsInstructionFlowx(ex)
% Present the next page only after the preceding practice feedback completes.
shown = false;
if ~isfield(ex.exp.CoPs,'instrOn') || ~ex.exp.CoPs.instrOn || ex.quit ~= 0
    return
end
if ~isfield(ex,'Instructions') || ~isfield(ex.Instructions,'Trials')
    return
end
completed = numel(ex.Instructions.Trials);
if completed == 0, return; end
if isfield(ex.Instructions.Trials,'practiceRepeatRequested') && ...
        isequal(ex.Instructions.Trials(end).practiceRepeatRequested,true)
    return
end
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
