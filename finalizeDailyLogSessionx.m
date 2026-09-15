function dailyLog = finalizeDailyLogSessionx(dailyLog, dailyLog_old, ex, fname)
%FINALIZEDAILYLOGSESSIONX Update daily totals and append per-session metadata.
%
% Adds/updates:
%   - dailyLog.nTrialsPerDay
%   - dailyLog.nCorrectTrialsPerDay
%   - dailyLog.sessionHistory (struct array with per-session details)
%   - dailyLog.lastSessionSummary

dailyLog = ensureDailyLogFormatx(dailyLog);
dailyLog_old = ensureDailyLogFormatx(dailyLog_old);

nTrials = numel(ex.Trials);
nCorrectTrials = nnz([ex.Trials.Reward] == 1);


dailyLog.nTrialsPerDay = dailyLog_old.nTrialsPerDay + nTrials;
dailyLog.nCorrectTrialsPerDay = dailyLog_old.nCorrectTrialsPerDay + nCorrectTrials;

if ~isfield(dailyLog,'sessionHistory') || ~isstruct(dailyLog.sessionHistory)
    dailyLog.sessionHistory = struct([]);
end

sessionParams = collectKeySessionParams(ex);
paramChanges = struct([]);
if ~isempty(dailyLog.sessionHistory) && isfield(dailyLog.sessionHistory(end),'keyParams')
    paramChanges = diffSessionParams(dailyLog.sessionHistory(end).keyParams, sessionParams);
end

sessionEntry = struct();
sessionEntry.timestamp = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
sessionEntry.dataFile = fname;
sessionEntry.nTrials = nTrials;
sessionEntry.nCorrectTrials = nCorrectTrials;
sessionEntry.keyParams = sessionParams;
sessionEntry.paramChangesFromPrevious = paramChanges;

if isempty(dailyLog.sessionHistory)
    dailyLog.sessionHistory = sessionEntry;
else
    dailyLog.sessionHistory(end+1) = sessionEntry;
end
%dailyLog.lastSessionSummary = sessionEntry;
end

function params = collectKeySessionParams(ex)
candidatePaths = { ...
    %'setup.monkey', ...
    %'setup.eyeTracker', ...
    %'exp.taskType', ...
    %'exp.afc', ...
    %'exp.StimPerTrial', ...
    'exp.CoPs', ...
    % 'reward.type', ...
    % 'reward.rewardBias', ...
    % 'reward.switchTrials', ...
    % 'reward.durationMs', ...
    % 'fix.Duration', ...
    % 'fix.radius', ...
    % 'stim.vals.fixedSeed', ...
    % 'stim.vals.numPairs', ...
    % 'stim.vals.noiseLevel' ...
    };

params = struct();
for i = 1:numel(candidatePaths)
    path = candidatePaths{i};
    [found, value] = getNestedField(ex, path);
    if found
        safeName = regexprep(path,'[^a-zA-Z0-9_]','_');
        params.(safeName) = value;
    end
end
end

function changes = diffSessionParams(previousParams, currentParams)
prevFields = fieldnames(previousParams);
currFields = fieldnames(currentParams);
allFields = unique([prevFields; currFields]);

changes = struct('name',{},'previous',{},'current',{});
for i = 1:numel(allFields)
    fieldName = allFields{i};
    if isfield(previousParams, fieldName)
        prevVal = previousParams.(fieldName);
    else
        prevVal = [];
    end
    if isfield(currentParams, fieldName)
        currVal = currentParams.(fieldName);
    else
        currVal = [];
    end

    if ~isequaln(prevVal, currVal)
        changes(end+1).name = fieldName; %#ok<AGROW>
        changes(end).previous = prevVal;
        changes(end).current = currVal;
    end
end
end

function [found, value] = getNestedField(s, dottedPath)
parts = strsplit(dottedPath,'.');
value = s;
found = true;
for i = 1:numel(parts)
    part = parts{i};
    if isstruct(value) && isfield(value, part)
        value = value.(part);
    else
        found = false;
        value = [];
        return
    end
end
end