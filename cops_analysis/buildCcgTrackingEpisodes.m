function episodes = buildCcgTrackingEpisodes(ex, trialList, groupNo, opts)
% buildCcgTrackingEpisodes  Reuse ccg.m's sample-level preprocessing/chunks.
%
% This adapter lets CCG variants share gaze reconstruction, target mapping,
% HMM/model-free target selection, blink handling, minimum tracking runs,
% and no-tracking-gap bridging with ccg.m. Analysis-specific functions then
% operate on the returned position traces.

if nargin < 2 || isempty(trialList)
    trialList = 1:numel(ex.Trials);
end
if nargin < 3 || isempty(groupNo)
    groupNo = 1;
end
if nargin < 4 || isempty(opts)
    opts = struct();
end

sharedOpts = opts;
sharedOpts.ccgTimebase = 'sample';
sharedOpts.plot = false;
sharedOpts.newFigure = false;
sharedOpts.episodesOnly = true;
sharedOpts.refGroup = '';

base = ccg(ex, trialList, sharedOpts);
episodes = base.episodes;
if isempty(episodes)
    return
end

episodes.group(:) = double(groupNo);
names = episodes.Properties.VariableNames;
if ismember('nSteps', names)
    episodes.Properties.VariableNames{'nSteps'} = 'nSamples';
end
names = episodes.Properties.VariableNames;
if ismember('dtStepSec', names)
    episodes.Properties.VariableNames{'dtStepSec'} = 'dtSec';
end
end
