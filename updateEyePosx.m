function [trialEye] = updateEyePosx(states,trialPerf, trialTime, trialFlags, expFlags)
if trialTime.ttime > 0.2;%lasteyepostime + eyetimestep
    trialFlags.pass_eye =1;
    
    % Print to command line (optional)
    % fprintf('Mouse X: %4d   Y: %4d\n', current_x, current_y);
    fprintf('gauss_reward: %4d\n', trialPerf.gauss_reward);
    % if state== ex.states.GO | state == ex.states.CHOICE
    %     [pass_eye,trEye,lastEyePos,tchosen] = checkEye(trEye,ex,targ,pass_eye,lastEyePos,tchosen);
    % else
    %     [pass_eye,trEye,lastEyePos] = checkEye(trEye,ex,[],pass_eye,lastEyePos,tchosen);
    % end
    trialTime.lasteyepostime = trialTime.ttime;
    if expFlags.eyeOn trialCnt.ei = trialCnt.ei+1; end
end
