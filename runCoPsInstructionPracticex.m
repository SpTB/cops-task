function ex = runCoPsInstructionPracticex(ex,pixOn,eyeOn,rewOn,checkpointFile)
% Run instruction exercises and up to three voluntary dynamic repeats.
if ~ex.exp.CoPs.instrOn || ex.quit ~= 0, return; end
practiceDir = fullfile(fileparts(checkpointFile),'instruction_practice');
if ~isfolder(practiceDir), mkdir(practiceDir); end
ex.Header.onlineInstructionDirName = practiceDir;
ex.Instructions.Trials = struct([]);
ex.Instructions.loopcnt = [];
maxRepeats = 3;
for number = 1:(2 + maxRepeats)
    if ex.quit ~= 0, break; end
    % Reuse the trial engine on a copy: task plans, Trials, points and counters
    % remain intact. Only eye calibration and operator requests carry forward.
    practice = ex;
    practice.setup.instructionPractice = true;
    practice.setup.instructionPracticeCount = max(2,number);
    practice.setup.practiceRepeatsRemaining = 2 + maxRepeats - number;
    practice.j = number;
    practice.finish = max(2,number);
    practice.exp.total_nreps = practice.finish;
    practice.Trials = ex.Instructions.Trials;
    practice.loopcnt = ex.Instructions.loopcnt;
    practice.goodtrial = 0;
    practice.totalPoints = 0;
    try
        practice = prepareCoPsTrialParamSchedules(practice);
        practice.stim.seq = repmat(ex.stim.seq(1),1,practice.finish);
        if isfield(ex.setup,'dependencies') && ex.setup.dependencies.adcOn
            resetAdcBuffer(practice);
        end
        fprintf('Instruction practice %d (up to %d total)\n',number,2+maxRepeats);
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
    [ex,~] = advanceCoPsInstructionFlowx(ex);
    save(checkpointFile,'ex','-v7.3');
    ex = completeCoPsPauseActionsx(ex,checkpointFile);
    if number >= 2 && (ex.quit ~= 0 || ...
            numel(ex.Instructions.Trials) < number || ...
            ~ex.Instructions.Trials(number).practiceRepeatRequested)
        break
    end
end
end
