function plan = getCoPsInstructionPlanx(instr,train)
% Missing versions retain the original flow for older saved configurations.
if nargin < 1, instr = struct(); end
if nargin < 2, train = struct(); end
train = resolveCoPsTrainx(train);
version = 'short';
if isfield(instr,'version'), version = validatestring(instr.version,{'short','long'}); end
plan = struct('version',version,'tutorialTrials',2,'maxRepeats',3,'trainingTrials',0);
if strcmp(version,'long')
    plan.tutorialTrials = 3;
    plan.trainingTrials = train.nreps;
end
plan.maxTutorialTrials = plan.tutorialTrials + plan.maxRepeats;
end
