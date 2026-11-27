function ex = runCoPsInstructionPracticex(ex,pixOn,eyeOn,rewOn,checkpointFile)
% Run tutorials, optional dynamic repeats, and the long-version training block.
if ~ex.exp.CoPs.instrOn || ex.quit ~= 0, return; end
instr = struct();
if isfield(ex.exp.CoPs,'instr'), instr = ex.exp.CoPs.instr; end
train = struct();
if isfield(ex.exp.CoPs,'train'), train = ex.exp.CoPs.train; end
plan = getCoPsInstructionPlanx(instr,train);
practiceDir = fullfile(fileparts(checkpointFile),'instruction_practice');
if ~isfolder(practiceDir), mkdir(practiceDir); end
ex.Header.onlineInstructionDirName = practiceDir;
ex.Instructions.Trials = struct([]);
ex.Instructions.loopcnt = [];
ex.Instructions.trainingStartTrial = [];
ex.Instructions.trainingParamSchedules = struct();
trainingStart = Inf;
for number = 1:(plan.maxTutorialTrials + plan.trainingTrials)
    if ex.quit ~= 0, break; end
    % Reuse the trial engine on a copy: task plans, Trials, points and counters
    % remain intact. Only eye calibration and operator requests carry forward.
    practice = ex;
    practice.setup.instructionPractice = true;
    practice.setup.instructionPracticeCount = max(plan.tutorialTrials,number);
    isTraining = number >= trainingStart;
    if isTraining
        practice.setup.instructionPracticeCount = trainingStart+plan.trainingTrials-1;
    end
    practice.setup.instructionTrainingStart = trainingStart;
    practice.setup.practiceRepeatsRemaining = 0;
    if number >= plan.tutorialTrials && number < trainingStart
        practice.setup.practiceRepeatsRemaining = plan.maxTutorialTrials - number;
    end
    practice.j = number;
    practice.finish = practice.setup.instructionPracticeCount;
    practice.exp.total_nreps = practice.finish;
    practice.Trials = ex.Instructions.Trials;
    practice.loopcnt = ex.Instructions.loopcnt;
    practice.goodtrial = 0;
    practice.totalPoints = 0;
    try
        if isTraining && ~isempty(fieldnames(ex.Instructions.trainingParamSchedules))
            practice.exp.CoPs.trialParamSchedules = ex.Instructions.trainingParamSchedules;
        else
            practice = prepareCoPsTrialParamSchedules(practice);
            if isTraining
                ex.Instructions.trainingParamSchedules = practice.exp.CoPs.trialParamSchedules;
            end
        end
        practice.stim.seq = repmat(ex.stim.seq(1),1,practice.finish);
        if isfield(ex.setup,'dependencies') && ex.setup.dependencies.adcOn
            resetAdcBuffer(practice);
        end
        fprintf('Instruction practice %d (up to %d total)\n',number,plan.maxTutorialTrials+plan.trainingTrials);
        practice = runTrialTaskCoPsx(practice,pixOn,eyeOn,rewOn);
        ex.Instructions.Trials = practice.Trials;
        ex.Instructions.loopcnt = practice.loopcnt;
        ex.eyeCal = practice.eyeCal;
        ex.quit = practice.quit;
        for name = {'Recalibration','lastError'}
            if isfield(practice,name{1}), ex.(name{1}) = practice.(name{1}); end
        end
        if isfield(ex,'Recalibration') && ~isempty(ex.Recalibration.pending)
            ex.Recalibration.pending.nextTrial = ex.j;
            ex.Recalibration.pending.source = sprintf('instructionPractice:%d',number);
        end
        Trials = ex.Instructions.Trials(number); %#ok<NASGU>
        save(fullfile(practiceDir,sprintf('practice%d.mat',number)),'Trials','-v7.3');
    catch err
        ex.quit = 4;
        ex.lastError = err;
        fprintf(2,'Instruction practice %d failed: %s\n',number,getReport(err,'extended'));
    end
    save(checkpointFile,'ex','-v7.3');
    ex = completeCoPsPauseActionsx(ex,checkpointFile);
    tutorialDone = number >= plan.tutorialTrials && number < trainingStart && ...
        numel(ex.Instructions.Trials) >= number && ...
        ~ex.Instructions.Trials(number).practiceRepeatRequested;
    if tutorialDone && plan.trainingTrials > 0
        trainingStart = number + 1;
        ex.Instructions.trainingStartTrial = trainingStart;
    end
    [ex,~] = advanceCoPsInstructionFlowx(ex);
    save(checkpointFile,'ex','-v7.3');
    ex = completeCoPsPauseActionsx(ex,checkpointFile);
    if (tutorialDone && plan.trainingTrials == 0) || ...
            number == trainingStart + plan.trainingTrials - 1
        break
    end
end
end
