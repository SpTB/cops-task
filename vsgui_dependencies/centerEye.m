function ex=centerEye(ex)

% function centerEye(ex)
%
% computes an offset (delta x and delta y) by which the current zero
% position of the eyes should be corrected to account for drift happening
% during the experiment.

% history
% 08/02/14  hn: wrote it

Datapixx RegWrRd ;
status = Datapixx ('GetAdcStatus') ;
v = Datapixx('ReadAdcBuffer',[status.newBufferFrames],-1);

% added by IK: 06.04.2024
v([1,4],:) = v([1,4],:) * ex.setup.horEyeSign;

% smoothing over up to 10 samples (20ms)
if size(v,2)>10
    vv = v(:,end-10:end);
else
    vv = v;
end

% getting 0 position
if size(v,1)>=5
    RX0 = mean(vv(1,:));  
    RY0 = mean(vv(2,:));
    LX0 = mean(vv(4,:));  
    LY0 = mean(vv(5,:));
else 
    RX0 = mean(vv(1,:));  
    RY0 = mean(vv(2,:));
    LX0 = [];  
    LY0 = [];
end


% counter for the number of centering corrections
ex.eyeCal.Delta(1).cnt = ex.eyeCal.Delta(1).cnt+1;

% Delta X/Y by which the eye position from calibration should be corrected
ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RX0 = RX0 - ex.eyeCal.RX0;
ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RY0 = RY0 - ex.eyeCal.RY0;
if ~isempty(LX0)
    ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).LX0 = LX0 - ex.eyeCal.LX0;
    ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).LY0 = LY0 - ex.eyeCal.LY0;
end

% keep track of when this re-centering happened;
ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).TrialNo = ex.j;
ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).Time = GetSecs;

    
