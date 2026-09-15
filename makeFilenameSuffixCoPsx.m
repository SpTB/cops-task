function sfx = makeFilenameSuffixCoPsx(ex)
ctl = ex.exp.CoPs.ctl;
[waitSecs, waitHz] = resolveCoPsWaitSecs(ex, NaN);

if isfield(ex.exp, 'total_nreps')
    total_nreps = ex.exp.total_nreps;
else
    total_nreps = getCoPsTotalRepsx(ex);
end
trialNo=['t',num2str(total_nreps)];
if isfinite(waitHz)
    trialLen=[num2str(ctl.nsteps),'-by-',num2str(waitHz),'Hz_steps'];
else
    trialLen=[num2str(ctl.nsteps),'-by-',num2str(waitSecs),'s_steps'];
end

if strcmp(ctl.reward_type, 'add') & isfield(ctl, 'precision_weight')
    rew_balancing=['pw',num2str(ctl.precision_weight)]; % precision weight
elseif strcmp(ctl.reward_type, 'mult') & isfield(ctl, 'gauss_scalar')
    rew_balancing=['gs',num2str(ctl.gauss_scalar)]; %gauss scalar
else
    reward_balancing = '';
end

noise_lvl = ex.exp.CoPs.graph.background_noise_lvl;
if numel(noise_lvl) > 1
    noise = ['noiseMix', localNoiseLevelsText(noise_lvl)];
else
    noise = ['noise', localNoiseLevelText(noise_lvl)];
end


sfx = [trialNo,'_', trialLen,'_', rew_balancing, '_',noise];
end


function text = localNoiseLevelsText(noiseLvl)
parts = arrayfun(@localNoiseLevelText, noiseLvl(:)', 'UniformOutput', false);
text = strjoin(parts, '-');
end


function text = localNoiseLevelText(noiseLvl)
if noiseLvl == -1
    text = 'Null';
elseif noiseLvl == 0
    text = '0';
else
    text = num2str(noiseLvl);
end
end
