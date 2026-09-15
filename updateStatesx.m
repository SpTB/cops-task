function [trialTime, trialFlags] = updateStatesx(states, strobe, trialTime, trialFlags, expTime,expFlags)
% XX need to merge timing and exp.fix stuff into expTime
% xx think about high-level structure of ex.
arguments
    states struct
    strobe struct
    trialTime struct
    trialFlags struct
    expTime struct
    expFlags struct = struct( ...
        'eyeOn': true,...
        'pixOn': true...
        );
end

% START -> FPON
if trialFlags.state == states.START &&  trialTime.ttime > fix.freeduration
    trialFlags.stateNow = states.FPON;
    trialFlags.stimulus_active = true;
    trialTime.time_startTrial = GetSecs - trialTime.trstart;
    disp('in fixation dot on');
    fprintf('in fixation dot on');
    trialTime.time_fpOn = GetSecs - trialTime.trstart;
end

% FPON -> FPHOLD (fixation acquired)
if trialFlags.state == states.FPON && trialTime.ttime < fix.waitstop && trialFlags.pass_eye
    trialTime.time_startFixation = GetSecs - trialTime.trstart;
    % if ttime > 0.5 % brief fixation period
    trialFlags.state = states.FPHOLD;
    if pixOn sendStrobe(strobe.FIXATION_START)
        disp('in fixation acquired');
        fprintf('in fixation acquired');
    end
elseif trialFlags.state == states.FPON && trialTime.ttime > fix.waitstop
    trialFlags.state = states.NOFIX;
    disp('in no fixation acquired');
    fprintf('in no fixation acquired');
    trialTime.time_breakFixation = GetSecs - trialTime.trstart;
end

% FPHOLD -> FIXATIONCOMPLETE
if trialFlags.state == states.FPHOLD
    if ~ trialFlags.pass_eye
        trialFlags.state = states.BREAKFIX;
        disp('in breakfix');
        % time_breakFixation = GetSecs - trstart;
    elseif ttime > trialTime.time_startTrial + fix.duration && trialFlags.pass_eye
        % current_step = current_step + 1;
        trialFlags.state = states.PREGO;
        trialTime.time_prego = GetSecs - trialTime.trstart;
        disp('fixation complete');
        fprintf('fixation complete');
    end
end

% FIXATIONCOMPLETE -> GO (start stimulus presentation)
if trialFlags.state == states.PREGO
    if trialTime.ttime > trialTime.time_prego + expTime.prego_delay
        trialFlags.state = states.FIXATIONCOMPLETE;
        trialTime.time_fixationComplete = GetSecs - trialTime.trstart;
        disp('stimulus pre-presentation');
        fprintf('stimulus pre-presentation');
    end
end
% FIXATIONCOMPLETE -> GO (start stimulus presentation)
if trialFlags.state == states.FIXATIONCOMPLETE && trialTime.ttime>0; % xx this can be increased for testing
    if trialTime.ttime > trialTime.time_fixationComplete + expTime.go_delay
        trialFlags.state = states.GO;
        trialTime.time_stimOn = GetSecs - trialTime.trstart;
        trialFlags.reward_active = true;
        disp('stimulus presentation started');
        fprintf('stimulus presentation started');
    end
end
