function [ctl,graph,rew] = configureCoPsPracticeTrialx(ctl,graph,rew,gray,practiceNumber,instr)
% Local overrides only; main-task settings and reward-center cache are retained.
if nargin < 5, practiceNumber = 1; end
if nargin < 6, instr = struct('targetVisibility',1); end
validateattributes(practiceNumber,{'numeric'},{'scalar','integer','>=',1,'<=',2});
ctl.target_num = 2;
ctl.gauss_scalar = 1;
ctl.reward_type = 'mult';
ctl.independent_accumulation = false;
ctl.coherence = 1;
if practiceNumber == 1
    graph.background_noise_lvl = -1;
    graph.nullBackgroundGray = gray;
    graph.target_visibility = 1;
else
    if ~isfield(instr,'targetVisibility'), instr.targetVisibility = 1; end
    validateattributes(instr.targetVisibility,{'numeric'},{'scalar','real','finite','>=',0,'<=',1});
    levels = graph.background_noise_lvl;
    levels = levels(isfinite(levels) & levels ~= -1 & levels ~= 0);
    if isempty(levels), levels = 1; end
    graph.background_noise_lvl = levels(1);
    graph.target_visibility = instr.targetVisibility;
    if isfield(graph,'nullBackgroundGray'), graph = rmfield(graph,'nullBackgroundGray'); end
end
rew.show_gauss_center_marker = false;
rew.show_gauss_center_marker_overlay = false;
rew.gauss_center_free = false;
rew.gauss_center_coords = [0.5 0.5];
end
