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
instr = struct();
if isfield(ex.exp.CoPs,'instr'), instr = ex.exp.CoPs.instr; end
train = struct();
if isfield(ex.exp.CoPs,'train'), train = ex.exp.CoPs.train; end
plan = getCoPsInstructionPlanx(instr,train);
if strcmp(plan.version,'long') && completed == 1
    stage = 'targets';
elseif completed < plan.tutorialTrials
    stage = 'dynamic';
elseif plan.trainingTrials > 0
    stage = 'training';
    if isfield(ex.Instructions,'trainingStartTrial') && ...
            ~isempty(ex.Instructions.trainingStartTrial) && completed >= ex.Instructions.trainingStartTrial
        if completed < ex.Instructions.trainingStartTrial + plan.trainingTrials - 1, return; end
        stage = 'ready';
    end
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
