function ex = prepareCoPsPauseSchedulex(ex)
% Draw one session-wide schedule of between-trial SPACE pauses.
ctl = ex.exp.CoPs.ctl;
average = 1;
spread = 0;
if isfield(ctl, 'between_trial_pause_mean'), average = ctl.between_trial_pause_mean; end
if isfield(ctl, 'between_trial_pause_range'), spread = ctl.between_trial_pause_range; end
validateattributes(average, {'numeric'}, {'scalar','real','finite','integer','positive'});
validateattributes(spread, {'numeric'}, {'scalar','real','finite','integer','nonnegative'});
if spread >= average
    error('prepareCoPsPauseSchedulex:InvalidRange', ...
        'between_trial_pause_range must be smaller than between_trial_pause_mean so every interval is at least one trial.');
end
validateattributes(ex.finish, {'numeric'}, {'scalar','real','finite','integer','positive'});
schedule = struct('meanTrials', average, 'rangeTrials', spread, ...
    'intervals', [], 'afterTrial', false(1, ex.finish));
enabled = ~isfield(ctl, 'advance_trial_with_space') || ctl.advance_trial_with_space;
if enabled
    boundary = 0;
    while true
        interval = average;
        if spread > 0
            interval = randi([average-spread, average+spread]);
        end
        boundary = boundary + interval;
        if boundary >= ex.finish, break; end
        schedule.intervals(end+1) = interval;
        schedule.afterTrial(boundary) = true;
    end
end
ex.exp.CoPs.pauseSchedule = schedule;
end
