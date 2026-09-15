function [pass_eye,trEye,lastEyePos,tchosen] = checkEyexx(trEye,ex,targ,pass_eye,lastEyePos,tchosen,xPos,yPos)

% function [pass_eye,trEye,lastEyePos] = checkEye(trEye,ex,targetPos,pass_eye,lastEyePos,tchosen)
% checks whether eye position is in defined fixation window and whether
% saccade occurred if requested
%
% returns the updated Eye signals for this trial (in trEye), and whether
% fixation criteria (or else) were met
%
% ToDos: check for Saccades or microsaccades
%
% history
% 11/13/13  hn   wrote it
% 11/15/13  hn   added lastEyePos (in pixels)
% 05/01/14  hn   added check of target positions
% 07/26/14  hn   fixed bug for binocular eye positions
% 08/03/14  hn   included offset (Delta x, Delta y) to correct eye positions 
%                online
%                -bug-fix to deal with empty Buffer: function is only
%                performed if Buffer is not empty
% 08/26/14  hn   bug-fix to correct eye positions online
% 03/07/15  hn   bug-fix to re-center eye position online
% 07/05/22  hn   include freeViewing option
% 11/05/25  cmz  modified to work in the dome w/ deg/volt calib gain
%disp('in check eye')
if nargin < 7
    xPos = 0;
    yPos = 0;
end
    

Datapixx RegWrRd 
status = Datapixx ('GetAdcStatus') ;
n = trEye.n;
nBufFr = status.newBufferFrames;
if nBufFr>0
    [trEye.v(:, n+1:n+nBufFr) trEye.t(n+1:n+nBufFr)]=...
        Datapixx('ReadAdcBuffer',[nBufFr],-1);
    %trEye.v(trEye.v > 10) = trEye.v(trEye.v > 10) - 20;
    pass_eye = 0;
    tchosen = 0;
else
    disp('in no new frames')
    return
end

%% adjust coordinates for dome warping?
geomCorrect = isfield(ex.setup,"scal");


%% 6.3.2024, temporarilly invert the sign of horizontal eyes
if size(trEye.v,1)>3
    trEye.v([1,4],n+1:n+nBufFr) = ex.setup.horEyeSign * trEye.v([1,4],n+1:n+nBufFr);  
else
    trEye.v([1],n+1:n+nBufFr) = ex.setup.horEyeSign * trEye.v([1],n+1:n+nBufFr);  
end

if isempty(targ)  %% checking fixation is default
    if ~isempty(ex.eyeCal.LXPos)
        xTol = mean([ex.fix.WinW/ex.eyeCal.RXGain,ex.fix.WinW/ex.eyeCal.LXGain]) ;  % x-fixation tolerance in voltage
        yTol = mean([ex.fix.WinH/ex.eyeCal.RYGain,ex.fix.WinH/ex.eyeCal.LYGain]);  % y-fixation tolerance in voltage
    else
        xTol = ex.fix.WinW/ex.eyeCal.RXGain;  % x-fixation tolerance in voltage
        yTol = ex.fix.WinH/ex.eyeCal.RYGain;  % y-fixation tolerance in voltage
    end
    
    xPos = mean([xPos/ex.eyeCal.RXGain,xPos/ex.eyeCal.LXGain],2);
    yPos = mean([yPos/ex.eyeCal.RYGain,yPos/ex.eyeCal.LYGain],2);
    pass_eye = passEyeXY(ex,trEye,n,nBufFr,xTol,yTol,xPos,yPos,1); 

else % check whether eye is one of the targets

    % check for whether coordinates need to be warped
    if geomCorrect
        targPos = ex.targ.PosDeg;
    else
        %targPos = ex.targ.Pos;
        targPos = targ.Pos;
    end

    if ~isempty(ex.eyeCal.LXPos)
        xTol = mean([targ.WinW/ex.eyeCal.RXGain,targ.WinW/ex.eyeCal.LXGain]) ;  % x-target tolerance in voltage
        yTol = mean([targ.WinH/ex.eyeCal.RYGain,targ.WinH/ex.eyeCal.LYGain]);  % y-target tolerance in voltage
        xPos = mean([targPos(:,1)/ex.eyeCal.RXGain,targPos(:,1)/ex.eyeCal.LXGain],2);
        yPos = mean([targPos(:,2)/ex.eyeCal.RYGain,targPos(:,2)/ex.eyeCal.LYGain],2);
    else
        xTol = targ.WinW/ex.eyeCal.RXGain ;  
        yTol = targ.WinH/ex.eyeCal.RYGain;  
        xPos = targPos(:,1)/ex.eyeCal.RXGain;
        yPos = targPos(:,2)/ex.eyeCal.RYGain;
    end
    tchosen = zeros(1,size(targPos,1));
    for t = 1:size(targPos,1)  %% check each target position individually
        tchosen(t) = passEyeXY(ex,trEye,n,nBufFr,xTol,yTol,xPos(t),yPos(t),1);
    end

    if ex.passOn
        tchosen = [1 0];
    end
end


% compute last x,y eye position relative to the center in pixels
if ~isempty(ex.eyeCal.LXPos)
    lastEyePos = ...
        [(trEye.v(1,n+nBufFr)-ex.eyeCal.RX0-ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RX0)*ex.eyeCal.RXGain+ex.fix.PCtr(1),... %Rxpos
        (trEye.v(2,n+nBufFr)-ex.eyeCal.RY0-ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RY0)*ex.eyeCal.RYGain+ex.fix.PCtr(2); ...   %Rypos
        (trEye.v(4,n+nBufFr)-ex.eyeCal.LX0-ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).LX0)*ex.eyeCal.LXGain+ex.fix.PCtr(1),... %Lxpos
        (trEye.v(5,n+nBufFr)-ex.eyeCal.LY0-ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).LY0)*ex.eyeCal.LYGain+ex.fix.PCtr(2)]; %Lypos

    % compute last eye position in the dome. Must translate to pixels and
    % then take account of the warping because we're 
    if geomCorrect
            
        % first get in degrees
        lastEyePosDeg = ...
        [(trEye.v(1,n+nBufFr)-ex.eyeCal.RX0-ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RX0)*ex.eyeCal.RXGain,... %Rxpos
        (trEye.v(2,n+nBufFr)-ex.eyeCal.RY0-ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RY0)*ex.eyeCal.RYGain; ...   %Rypos
        (trEye.v(4,n+nBufFr)-ex.eyeCal.LX0-ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).LX0)*ex.eyeCal.LXGain,... %Lxpos
        (trEye.v(5,n+nBufFr)-ex.eyeCal.LY0-ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).LY0)*ex.eyeCal.LYGain]; %Lypos
        
        % now get in pixels pre-warping
        [lastEyePosPreWarp(:,1),lastEyePosPreWarp(:,2)] = deg2pixelxy(lastEyePosDeg(:,1),lastEyePosDeg(:,2),ex.setup);
        % now apply the warping, because eye position will be plotted in
        % the overly without automatic warping
        [lastEyePos(:,1),lastEyePos(:,2)] = geomCorrection(lastEyePosPreWarp(:,1),lastEyePosPreWarp(:,2),ex.setup);
    end


else
    lastEyePos = ...
        [(trEye.v(1,n+nBufFr)-ex.eyeCal.RX0-ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RX0)*ex.eyeCal.RXGain+ex.fix.PCtr(1),... %xpos
        (trEye.v(2,n+nBufFr)-ex.eyeCal.RY0-ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RY0)*ex.eyeCal.RYGain+ex.fix.PCtr(2)];   %ypos
end

trEye.n=trEye.n+nBufFr;  % update numberAcquiredFrames

if ex.passOn || ex.freeViewing == 1
    pass_eye =1;
end
%disp(['passeye:' num2str(pass_eye)])

%disp(pass_eye)

% ------------------------------------------------------------------------
% ------- subfunctions -----------------------------------------------------
% ------------------------------------------------------------------------
function pass_eye = passEyeXY(ex,trEye,n,nBufFr,xTol,yTol,xPos,yPos,checkRightOnly)
if ~isempty(ex.eyeCal.LXPos) %|| check both
    x = mean([trEye.v([1 4],n+1:n+nBufFr)-[ex.eyeCal.RX0 + ...
        ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RX0; ex.eyeCal.LX0+ ...
        ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).LX0]*ones(1,nBufFr)],1);
    y = mean([trEye.v([2 5],n+1:n+nBufFr)-[ex.eyeCal.RY0 + ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RY0; ...
        ex.eyeCal.LY0 + ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).LY0] ...
        *ones(1,nBufFr)],1)  ; 
    passX = sum(abs(x-xPos)>xTol);
    passY = sum(abs(y-yPos)>yTol);
    passXY = passX+passY;
    
else%|| checkRightOnly
    passX = sum(abs(trEye.v(1,n+1:n+nBufFr)-ex.eyeCal.RX0 - ...
        ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RX0-xPos)>xTol);
    passY = sum(abs(trEye.v(2,n+1:n+nBufFr)-ex.eyeCal.RY0 - ...
        ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RY0-yPos)>yTol);
    passXY = passX+passY;
end
pass_eye = 0;
if passXY==0
    pass_eye = 1;
end


