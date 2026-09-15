function seq = buildCoPsStimulusSequencex(ex, sequenceModeIm, activeTrialMask)
% Build the CoPs stimulus folder sequence, including any pre.nreps preblock.

if nargin < 2 || isempty(sequenceModeIm)
    sequenceModeIm = false;
end
if nargin < 3
    activeTrialMask = [];
end

seq = makeSequencex(ex.exp.CoPs.dirs.all, ex.exp.total_nreps, 1, ...
    ex.exp.CoPs.graph.imgs, sequenceModeIm, activeTrialMask);

if isfield(ex.exp.CoPs, 'trialParamSchedules') && ...
        isfield(ex.exp.CoPs.trialParamSchedules, 'stimulus_dir_idx')
    stimIdx = ex.exp.CoPs.trialParamSchedules.stimulus_dir_idx;
    scheduledMask = isfinite(double(stimIdx(:)'));
    if any(scheduledMask)
        stimDirs = resolveCoPsStimulusDirs(ex.exp.CoPs.dirs.all, 1, ex.exp.CoPs.graph.imgs, true);
        scheduledIdx = round(double(stimIdx(scheduledMask)));
        if any(scheduledIdx < 1 | scheduledIdx > numel(stimDirs))
            error('buildCoPsStimulusSequencex:BadStimulusIndex', ...
                'Scheduled stimulus_dir_idx contains values outside 1:%d.', numel(stimDirs));
        end
        seq(scheduledMask) = stimDirs(scheduledIdx);
    end
end

blockInfo = getCoPsTrialBlockInfox(ex);
if isempty(blockInfo.preIdx)
    return
end
if isfield(ex.exp.CoPs, 'trialParamSchedules') && ...
        isfield(ex.exp.CoPs.trialParamSchedules, 'stimulus_dir_idx')
    stimIdx = ex.exp.CoPs.trialParamSchedules.stimulus_dir_idx;
    if numel(stimIdx) >= max(blockInfo.preIdx) && ...
            all(isfinite(double(stimIdx(blockInfo.preIdx))))
        return
    end
end

preSeq = getCoPsPreStimulusDirsx(ex);
if numel(preSeq) ~= numel(blockInfo.preIdx)
    error('buildCoPsStimulusSequencex:PreblockSizeMismatch', ...
        'pre.nreps requested %d pre trials, but %d stimulus folders were resolved.', ...
        numel(blockInfo.preIdx), numel(preSeq));
end
seq(blockInfo.preIdx) = preSeq;
end
