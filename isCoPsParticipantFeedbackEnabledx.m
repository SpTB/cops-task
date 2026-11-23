function enabled = isCoPsParticipantFeedbackEnabledx(ex)
% One task setting controls the feedback page and its outro continuation text.
enabled = true;
if isfield(ex,'exp') && isfield(ex.exp,'CoPs') && isfield(ex.exp.CoPs,'fbOn')
    enabled = ex.exp.CoPs.fbOn;
elseif isfield(ex.setup,'participantFeedback')
    enabled = ex.setup.participantFeedback; % Compatibility with older session structs.
end
validateattributes(enabled,{'logical','numeric'},{'scalar','real','finite'});
enabled = logical(enabled);
end
