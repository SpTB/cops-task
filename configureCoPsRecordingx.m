function ex = configureCoPsRecordingx(ex,config)
% Local recording overrides; experimental defaults are never edited.
if ~isfield(config,'rewardLandscape'), config.rewardLandscape = 0; end
config.enabled = true;
ex.setup.recording = config;
ex.MovieFiles = {};
ex.exp.CoPs.instrOn = false;
ex.exp.CoPs.freeViewing = true;
ex.exp.CoPs.ctl.advance_trial_with_space = false;
ex.exp.CoPs.ctl.target_num = config.targetNum;
ex.exp.CoPs.ctl.target_numNULL = config.targetNum;
% Select the existing center/corner presets explicitly so a daily cached or
% free Gaussian center cannot override the requested recording landscape.
ex.exp.CoPs.rew.gauss_center_free = false;
ex.exp.CoPs.rew.gauss_center_mode = 'manual';
ex.exp.CoPs.rew.gauss_center_idx = config.rewardLandscape+1;
ex.exp.CoPs.rew.gauss_center_coords = ex.exp.CoPs.rew.gauss_center_positions_norm(config.rewardLandscape+1,:);
if config.rewardLandscape == 0
    ex.exp.CoPs.ctl.gauss_scalar = 1;
end
[~,hz] = resolveCoPsWaitSecs(ex);
ex.exp.CoPs.ctl.nsteps = max(2,round(config.length*hz));
ex.exp.CoPs.graph.background_noise_lvl = config.background;
ex.exp.CoPs.graph.target_visibility = config.visibility;
ex.exp.CoPs.graph.target_visibility0 = config.visibility;
ex.exp.CoPs.graph.target_visibilityNull = config.visibility;
ex.exp.CoPs.graph.targetVisibilityNull = config.visibility;
ex.exp.CoPs.rew.points_feedback_on = false;
end
