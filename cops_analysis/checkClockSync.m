function out = checkClockSync(ex, trialNo, opts)
% checkClockSync  Summarize PTB/Datapixx/eye timing consistency in ex.
%
% out = checkClockSync(ex)
% out = checkClockSync(ex, trialNo)
% out = checkClockSync(ex, trialNo, opts)
%
% Inputs
%   ex       experiment struct
%   trialNo  [] or 'all' for all trials, or numeric trial indices
%   opts fields:
%       .verbose   (default true) print a short summary
%
% Output
%   out.global    : session-level timing metadata already stored in ex
%   out.perTrial  : one row per analyzed trial with timing diagnostics
%   out.summary   : compact session summary metrics

if nargin < 2
    trialNo = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
opts = localDefaultOpts(opts);

trialList = localResolveTrialList(ex, trialNo);
nTrials = numel(trialList);
rows = cell(nTrials, 1);

for i = 1:nTrials
    rows{i} = localCheckOneTrial(ex, trialList(i));
end

if isempty(rows)
    perTrial = table();
else
    perTrial = vertcat(rows{:});
end

out = struct();
out.global = localGlobalTimingInfo(ex);
out.perTrial = perTrial;
out.summary = localSummarizeTrials(perTrial, out.global);

if logical(opts.verbose)
    localPrintSummary(out.summary, out.global);
end
end


function opts = localDefaultOpts(opts)
if ~isfield(opts, 'verbose') || isempty(opts.verbose)
    opts.verbose = true;
end
end


function trialList = localResolveTrialList(ex, trialNo)
nTrials = numel(ex.Trials);
if isempty(trialNo) || (ischar(trialNo) && strcmpi(trialNo, 'all')) || ...
        (isstring(trialNo) && isscalar(trialNo) && strcmpi(char(trialNo), 'all'))
    trialList = 1:nTrials;
    return
end
trialList = unique(double(trialNo(:)'));
trialList = trialList(isfinite(trialList) & trialList >= 1 & trialList <= nTrials);
trialList = round(trialList);
end


function G = localGlobalTimingInfo(ex)
G = struct();
G.remappingSD = NaN;
G.remappingDelta = NaN(0, 1);
G.PTBvsDatapixxClockRatio = NaN;

if isfield(ex, 'times') && isstruct(ex.times)
    if isfield(ex.times, 'remappingSD') && ~isempty(ex.times.remappingSD)
        G.remappingSD = ex.times.remappingSD;
        if isstruct(ex.times.remappingSD) && isfield(ex.times.remappingSD, 'delta')
            G.remappingDelta = double(ex.times.remappingSD.delta(:));
        end
    end
    if isfield(ex.times, 'PTBvsDatapixxClockRatio') && ~isempty(ex.times.PTBvsDatapixxClockRatio)
        G.PTBvsDatapixxClockRatio = double(ex.times.PTBvsDatapixxClockRatio);
    end
end
end


function row = localCheckOneTrial(ex, trialIdx)
T = ex.Trials(trialIdx);

[eyeT, nEye, nFiniteEye] = localEyeTimeVector(T);
[eyeDtMed, eyeDtStd, nNonMonotonic, nLargeGap, eyeDur] = localEyeTimingStats(eyeT, ex);
[ptbDur, dpDur, startRemapErr, endRemapErr] = localTrialDurationStats(T, eyeT);
[stimRel, choiceRel, rewardRel, errorRel] = localEventTimesRelativeToTrialStart(T);
[firstFlipRel, flipCount, flipMissFrac, stimToFlip] = localFlipTimingStats(T, stimRel);
[stimInEye, choiceInEye, rewardInEye, errorInEye] = localEventInEyeRange( ...
    stimRel, choiceRel, rewardRel, errorRel, eyeDur);

row = table( ...
    double(trialIdx), ...
    nEye, nFiniteEye, ...
    eyeDtMed, eyeDtStd, nNonMonotonic, nLargeGap, eyeDur, ...
    ptbDur, dpDur, eyeDur - ptbDur, ...
    startRemapErr, endRemapErr, ...
    stimRel, choiceRel, rewardRel, errorRel, ...
    stimInEye, choiceInEye, rewardInEye, errorInEye, ...
    firstFlipRel, flipCount, flipMissFrac, stimToFlip, ...
    'VariableNames', { ...
    'trial', ...
    'nEyeSamples', 'nFiniteEyeTimes', ...
    'eyeDtMedianSec', 'eyeDtStdSec', 'nNonMonotonicEyeDt', 'nLargeEyeDtGaps', 'eyeDurSec', ...
    'ptbTrialDurSec', 'datapixxTrialDurSec', 'eyeMinusPtbDurSec', ...
    'trialStartRemapErrSec', 'trialEndRemapErrSec', ...
    'stimOnRelSec', 'choiceRelSec', 'rewardRelSec', 'errorRelSec', ...
    'stimOnInEyeRange', 'choiceInEyeRange', 'rewardInEyeRange', 'errorInEyeRange', ...
    'firstFlipRelSec', 'nFlips', 'flipMissFrac', 'stimOnToFirstFlipSec'});
end


function [eyeT, nEye, nFiniteEye] = localEyeTimeVector(T)
eyeT = NaN(0, 1);
nEye = 0;
nFiniteEye = 0;
if ~isfield(T, 'Eye') || isempty(T.Eye) || ~isfield(T.Eye, 't') || isempty(T.Eye.t)
    return
end
eyeT = double(T.Eye.t(:));
nEye = numel(eyeT);
nFiniteEye = nnz(isfinite(eyeT));
end


function [dtMed, dtStd, nNonMonotonic, nLargeGap, eyeDur] = localEyeTimingStats(eyeT, ex)
dtMed = NaN;
dtStd = NaN;
nNonMonotonic = 0;
nLargeGap = 0;
eyeDur = NaN;
eyeT = eyeT(isfinite(eyeT));
if numel(eyeT) < 2
    return
end
dt = diff(eyeT);
dtMed = median(dt, 'omitnan');
dtStd = std(dt, 'omitnan');
nNonMonotonic = nnz(dt <= 0);
fs = localInferFs(ex);
if isfinite(fs) && fs > 0
    dtNom = 1 / fs;
    nLargeGap = nnz(dt > 1.5 * dtNom);
end
eyeDur = eyeT(end) - eyeT(1);
end


function [ptbDur, dpDur, startRemapErr, endRemapErr] = localTrialDurationStats(T, eyeT)
ptbDur = NaN;
dpDur = NaN;
startRemapErr = NaN;
endRemapErr = NaN;

if isfield(T, 'TrialStart') && isfield(T, 'TrialEnd')
    ptbDur = double(T.TrialEnd) - double(T.TrialStart);
end

eyeT = eyeT(isfinite(eyeT));
if numel(eyeT) >= 2
    dpDur = eyeT(end) - eyeT(1);
end

if isfield(T, 'TrialStart_remappedGetSecs') && isfield(T, 'TrialStart')
    startRemapErr = double(T.TrialStart_remappedGetSecs) - double(T.TrialStart);
end
if isfield(T, 'TrialEnd_remappedGetSecs') && isfield(T, 'TrialEnd')
    endRemapErr = double(T.TrialEnd_remappedGetSecs) - double(T.TrialEnd);
end
end


function [stimRel, choiceRel, rewardRel, errorRel] = localEventTimesRelativeToTrialStart(T)
stimRel = NaN;
choiceRel = NaN;
rewardRel = NaN;
errorRel = NaN;

if ~isfield(T, 'times') || isempty(T.times) || ~isfield(T, 'TrialStart')
    return
end
trStart = double(T.TrialStart);
stimRel = localFirstFiniteRelative(T.times, 'stimOn', trStart);
choiceRel = localFirstFiniteRelative(T.times, 'choice', trStart);
rewardRel = localFirstFiniteRelative(T.times, 'reward', trStart);
errorRel = localFirstFiniteRelative(T.times, 'error', trStart);
end


function rel = localFirstFiniteRelative(S, fieldName, trStart)
rel = NaN;
if ~isfield(S, fieldName) || isempty(S.(fieldName))
    return
end
vals = double(S.(fieldName)(:));
vals = vals(isfinite(vals));
if isempty(vals)
    return
end
rel = vals(1) - trStart;
end


function [firstFlipRel, flipCount, flipMissFrac, stimToFlip] = localFlipTimingStats(T, stimRel)
firstFlipRel = NaN;
flipCount = 0;
flipMissFrac = NaN;
stimToFlip = NaN;
if ~isfield(T, 'flip_info') || isempty(T.flip_info) || ~isfield(T, 'TrialStart')
    return
end
flipInfo = double(T.flip_info);
if isempty(flipInfo) || size(flipInfo, 2) < 4
    return
end
flipT = flipInfo(:,1);
flipT = flipT(isfinite(flipT));
flipCount = numel(flipT);
if ~isempty(flipT)
    firstFlipRel = flipT(1) - double(T.TrialStart);
    if isfinite(stimRel)
        flipRel = flipT - double(T.TrialStart);
        idx = find(flipRel >= stimRel, 1, 'first');
        if ~isempty(idx)
            stimToFlip = flipRel(idx) - stimRel;
        end
    end
end
missCol = flipInfo(:,4);
missCol = missCol(isfinite(missCol));
if ~isempty(missCol)
    flipMissFrac = mean(missCol > 0, 'omitnan');
end
end


function [stimInEye, choiceInEye, rewardInEye, errorInEye] = localEventInEyeRange(stimRel, choiceRel, rewardRel, errorRel, eyeDur)
stimInEye = localTimeInRange(stimRel, eyeDur);
choiceInEye = localTimeInRange(choiceRel, eyeDur);
rewardInEye = localTimeInRange(rewardRel, eyeDur);
errorInEye = localTimeInRange(errorRel, eyeDur);
end


function tf = localTimeInRange(tRel, eyeDur)
tf = false;
if ~isfinite(tRel) || ~isfinite(eyeDur)
    return
end
tf = (tRel >= 0) && (tRel <= eyeDur);
end


function summary = localSummarizeTrials(T, globalInfo)
summary = table();
if isempty(T)
    return
end

summary.nTrials = height(T);
summary.fracTrialsWithEye = mean(T.nFiniteEyeTimes >= 2, 'omitnan');
summary.eyeDtMedianSec = median(T.eyeDtMedianSec, 'omitnan');
summary.eyeDtStdMedianSec = median(T.eyeDtStdSec, 'omitnan');
summary.fracTrialsNonMonotonicEyeTime = mean(T.nNonMonotonicEyeDt > 0, 'omitnan');
summary.fracTrialsWithLargeEyeGap = mean(T.nLargeEyeDtGaps > 0, 'omitnan');
summary.medianEyeMinusPtbDurSec = median(T.eyeMinusPtbDurSec, 'omitnan');
summary.medianStimOnToFirstFlipSec = median(T.stimOnToFirstFlipSec, 'omitnan');
summary.fracStimOnInEyeRange = mean(T.stimOnInEyeRange, 'omitnan');
summary.fracChoiceInEyeRange = mean(T.choiceInEyeRange, 'omitnan');
summary.fracRewardInEyeRange = mean(T.rewardInEyeRange, 'omitnan');
summary.fracTrialsWithAnyMissedFlip = mean(T.flipMissFrac > 0, 'omitnan');
summary.remappingClockRatio = globalInfo.PTBvsDatapixxClockRatio;

if isstruct(globalInfo.remappingSD) && isfield(globalInfo.remappingSD, 'norm')
    summary.remappingSdNorm = double(globalInfo.remappingSD.norm);
else
    summary.remappingSdNorm = NaN;
end
if ~isempty(globalInfo.remappingDelta)
    summary.remappingDeltaMedianSec = median(globalInfo.remappingDelta, 'omitnan');
    summary.remappingDeltaMaxAbsSec = max(abs(globalInfo.remappingDelta), [], 'omitnan');
else
    summary.remappingDeltaMedianSec = NaN;
    summary.remappingDeltaMaxAbsSec = NaN;
end
end


function localPrintSummary(summary, globalInfo)
if isempty(summary)
    fprintf('checkClockSync: no analyzed trials.\n');
    return
end

fprintf('Clock sync summary\n');
fprintf('  Trials analyzed: %d\n', summary.nTrials);
fprintf('  PTB vs Datapixx clock ratio: %.9g\n', summary.remappingClockRatio);
if isstruct(globalInfo.remappingSD) && isfield(globalInfo.remappingSD, 'norm')
    fprintf('  Remapping SD norm: %.6g\n', double(globalInfo.remappingSD.norm));
end
fprintf('  Median eye dt: %.6g s\n', summary.eyeDtMedianSec);
fprintf('  Trials with nonmonotonic eye time: %.1f%%\n', 100 * summary.fracTrialsNonMonotonicEyeTime);
fprintf('  Trials with large eye gaps: %.1f%%\n', 100 * summary.fracTrialsWithLargeEyeGap);
fprintf('  Median eye minus PTB trial duration: %.6g s\n', summary.medianEyeMinusPtbDurSec);
fprintf('  Median stimOn-to-firstFlip offset: %.6g s\n', summary.medianStimOnToFirstFlipSec);
fprintf('  StimOn within eye range: %.1f%% of trials\n', 100 * summary.fracStimOnInEyeRange);
fprintf('  Choice within eye range: %.1f%% of trials\n', 100 * summary.fracChoiceInEyeRange);
fprintf('  Reward within eye range: %.1f%% of trials\n', 100 * summary.fracRewardInEyeRange);
fprintf('  Trials with any missed flip: %.1f%%\n', 100 * summary.fracTrialsWithAnyMissedFlip);
end


function fs = localInferFs(ex)
fs = NaN;
if isfield(ex, 'setup') && isfield(ex.setup, 'adc') && isfield(ex.setup.adc, 'Rate')
    fs = double(ex.setup.adc.Rate);
end
end
