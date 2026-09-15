function dailyLog = ensureDailyLogFormatx(dailyLog)
%ENSUREDAILYLOGFORMATX Normalize dailyLog to a minimally compatible shape.

if nargin < 1 || ~isstruct(dailyLog)
    dailyLog = struct();
end

if ~isfield(dailyLog,'nTrialsPerDay') || ~isscalar(dailyLog.nTrialsPerDay) || ~isnumeric(dailyLog.nTrialsPerDay)
    dailyLog.nTrialsPerDay = 0;
end

if ~isfield(dailyLog,'nCorrectTrialsPerDay') || ~isscalar(dailyLog.nCorrectTrialsPerDay) || ~isnumeric(dailyLog.nCorrectTrialsPerDay)
    dailyLog.nCorrectTrialsPerDay = 0;
end

if ~isfield(dailyLog,'sessionHistory') || ~isstruct(dailyLog.sessionHistory)
    dailyLog.sessionHistory = struct([]);
end

if ~isfield(dailyLog,'lastSessionSummary')
    dailyLog.lastSessionSummary = struct([]);
end
end
