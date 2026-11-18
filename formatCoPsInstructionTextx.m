function [body, prompt, cap] = formatCoPsInstructionTextx(pay,stage,ctl,nTrials)
% Participant-approved copy; styling is applied separately by the renderer.
if nargin < 1, pay = struct(); end
if nargin < 2, stage = 'welcome'; end
if nargin < 3, ctl = struct(); end
pay = resolveCoPsPayx(pay);
% Standalone calls preview one reference hour; the renderer supplies the plan.
if nargin < 4, nTrials = pay.trials_per_hour; end
cap = getCoPsBonusCapx(nTrials,pay);
stage = validatestring(stage,{'welcome','dynamic','ready'});
if strcmp(stage,'dynamic')
    body = sprintf(['Most trials will be more challenging. The targets will move against a changing, noisy background ' ...
        'and may appear clearer or more blurred, making them easier or harder to see.\n\n' ...
        'Your task remains the same: follow either target with your eyes, keeping your gaze close to its center. ' ...
        'You can switch between targets freely.\n\n' ...
        'Let''s try another practice trial with a changing background.\n\n' ...
        'To ask a question, press Q and keep your head still while waiting for the experimenter.']);
    prompt = 'Press the SPACE BAR to begin.';
    return
elseif strcmp(stage,'ready')
    average = 1; spread = 0;
    if isfield(ctl,'between_trial_pause_mean'), average = ctl.between_trial_pause_mean; end
    if isfield(ctl,'between_trial_pause_range'), spread = ctl.between_trial_pause_range; end
    validateattributes(average,{'numeric'},{'scalar','finite','integer','positive'});
    validateattributes(spread,{'numeric'},{'scalar','finite','integer','nonnegative'});
    if spread >= average
        error('formatCoPsInstructionTextx:InvalidPauseRange','The pause range must be smaller than the mean.');
    end
    enabled = ~isfield(ctl,'advance_trial_with_space') || ctl.advance_trial_with_space;
    body = 'You''re now ready to start the main task!';
    if ~enabled
        body = sprintf('%s\n\nTrials will start automatically, one after another.',body);
    else
        if average > 1 || spread > 0
            body = sprintf('%s\n\nBetween breaks, trials will start automatically, one after another.',body);
        end
        if spread > 0
            pauseText = sprintf(['You''ll have a break after an average of %d trials. ' ...
                'The number of trials between breaks will range from %d to %d.'],average,average-spread,average+spread);
        elseif average == 1
            pauseText = 'You''ll have a break after every trial.';
        else
            pauseText = sprintf('You''ll have a break every %d trials.',average);
        end
        body = sprintf(['%s\n\n%s\n\nBreaks are self-paced. Take as much time as you need, ' ...
            'then press the SPACE BAR to continue.'],body,pauseText);
    end
    body = sprintf(['%s\n\nPlease keep your head still throughout the task.\n\n' ...
        'If you have any questions, press Q now or during any break and wait for the experimenter to come to you.'],body);
    prompt = 'Press the SPACE BAR to start the main task.';
    return
end
amount = sprintf('%.2f', cap.maxBonusDollars);
if cap.maxBonusDollars == fix(cap.maxBonusDollars)
    amount = sprintf('%.0f', cap.maxBonusDollars);
end
body = sprintf(['Welcome!\n\n' ...
    'In this task, you will use your eyes to follow moving texture patches, called targets.\n\n' ...
    'You can follow either target and switch between them freely. ' ...
    'Try to keep your gaze as close to a target''s center as possible as it moves.\n\n' ...
    'The more accurately you track a target, the more points you earn. ' ...
    'Your total points will determine your winnings, up to $%s for this session.\n\n' ...
    'When you follow a target closely for long enough, you earn a point and hear a beep.\n\n' ...
    'We''ll start with a short practice trial.\n\n' ...
    'To ask a question, press Q and keep your head still while waiting for the experimenter.'], amount);
prompt = 'Press the SPACE BAR to begin.';
end
