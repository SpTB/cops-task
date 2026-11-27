function [body, prompt, cap] = formatCoPsInstructionTextx(pay,stage,ctl,nTrials,version,train)
% Participant-approved copy; styling is applied separately by the renderer.
if nargin < 1, pay = struct(); end
if nargin < 2, stage = 'welcome'; end
if nargin < 3, ctl = struct(); end
pay = resolveCoPsPayx(pay);
% Standalone calls preview one reference hour; the renderer supplies the plan.
if nargin < 4, nTrials = pay.trials_per_hour; end
if nargin < 5, version = 'short'; end
if nargin < 6, train = struct(); end
version = validatestring(version,{'short','long'});
cap = getCoPsBonusCapx(nTrials,pay);
stage = validatestring(stage,{'welcome','targets','dynamic','training','ready'});
if strcmp(stage,'targets')
    body = sprintf(['In most trials, there will be two targets.\n\n' ...
        'You can follow either target and switch between them at any point, as often as you like. ' ...
        'Try to keep your gaze as close to a target''s center as possible as it moves.\n\n' ...
        'Let''s try a practice trial with two targets.\n\n']);
    prompt = 'Press the SPACE BAR to begin.';
    return
elseif strcmp(stage,'training')
    train = resolveCoPsTrainx(train);
    background = 'different backgrounds';
    if all(train.background_noise_lvl == -1)
        background = 'no background';
    elseif all(train.background_noise_lvl == 0)
        background = 'a static background';
    elseif all(train.background_noise_lvl > 0)
        background = 'a changing background';
    end
    plural = 's';
    if train.nreps == 1, plural = ''; end
    body = sprintf(['Before the main task, you will complete %d training trial%s with two targets ' ...
        'and %s.\n\n' ...
        'Follow either target, keeping your gaze close to its center. ' ...
        'You can switch between targets whenever you like.\n\n' ...
        'Training points do not count toward your winnings.\n\n'],train.nreps,plural,background);
    prompt = 'Press the SPACE BAR to begin training.';
    return
elseif strcmp(stage,'dynamic')
    body = sprintf(['Most trials will be more challenging. The targets will move against a changing, noisy background ' ...
        'and may appear clearer or more blurred, making them easier or harder to see.\n\n' ...
        'Your task remains the same: follow either target with your eyes, keeping your gaze close to its center. ' ...
        'You can switch between targets freely.\n\n' ...
        'Let''s try another practice trial with a changing background.\n\n']);
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
    body = sprintf(['%s\n\nPlease keep your head still throughout the task.\n\n'],body);
    prompt = 'Press the SPACE BAR to start the main task.';
    return
end
amount = sprintf('%.2f', cap.maxBonusDollars);
if cap.maxBonusDollars == fix(cap.maxBonusDollars)
    amount = sprintf('%.0f', cap.maxBonusDollars);
end
if strcmp(version,'long')
    body = sprintf(['Welcome!\n\n' ...
        'In this task, you will use your eyes to follow moving targets.\n\n' ...
        'Try to keep your gaze as close to the target''s center as possible as it moves.\n\n' ...
        'The more accurately you track a target, the more points you earn. ' ...
        'Your total points will determine your winnings, up to $%s for this session.\n\n' ...
        'When you follow a target closely for long enough, you earn a point and hear a beep.\n\n' ...
        'We''ll start with a short practice trial with one target.\n\n'],amount);
    prompt = 'Press the SPACE BAR to begin.';
    return
end
body = sprintf(['Welcome!\n\n' ...
    'In this task, you will use your eyes to follow moving targets.\n\n' ...
    'You can follow either target and switch between them freely. ' ...
    'Try to keep your gaze as close to a target''s center as possible as it moves.\n\n' ...
    'The more accurately you track a target, the more points you earn. ' ...
    'Your total points will determine your winnings, up to $%s for this session.\n\n' ...
    'When you follow a target closely for long enough, you earn a point and hear a beep.\n\n' ...
    'We''ll start with a short practice trial.\n\n'], amount);
prompt = 'Press the SPACE BAR to begin.';
end
