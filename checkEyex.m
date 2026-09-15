function [pass_eye,trEye,lastEyePos] = checkEyex(trEye,ex,pass_eye,freeViewing,lastEyePos,xPos, yPos, tolerance_scalar)

arguments
    trEye struct
    ex struct
    pass_eye {mustBeNumericOrLogical}
    freeViewing {mustBeNumericOrLogical}
    lastEyePos = [0 0;0 0]
    xPos {mustBeNumeric} = 0
    yPos {mustBeNumeric} = 0
    tolerance_scalar {mustBeNumeric} = 3
end
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

%% 6.3.2024, temporarilly invert the sign of horizontal eyes
sizev = size(trEye.v);
if sizev(1) > 3 % binoc case
trEye.v([1,4],n+1:n+nBufFr) = ex.setup.horEyeSign * trEye.v([1,4],n+1:n+nBufFr);
else
trEye.v([1],n+1:n+nBufFr) = ex.setup.horEyeSign * trEye.v([1],n+1:n+nBufFr);
    end
if ~isempty(ex.eyeCal.LXPos)
    xTol = mean([ex.fix.WinW/ex.eyeCal.RXGain,ex.fix.WinW/ex.eyeCal.LXGain]) ;  % x-fixation tolerance in voltage
    yTol = mean([ex.fix.WinH/ex.eyeCal.RYGain,ex.fix.WinH/ex.eyeCal.LYGain]);  % y-fixation tolerance in voltage
    xPos = mean([xPos/ex.eyeCal.RXGain,xPos/ex.eyeCal.LXGain],2);
    yPos = mean([yPos/ex.eyeCal.RYGain,yPos/ex.eyeCal.LYGain],2);
else
    xTol = ex.fix.WinW/ex.eyeCal.RXGain;  % x-fixation tolerance in voltage
    yTol = ex.fix.WinH/ex.eyeCal.RYGain;  % y-fixation tolerance in voltage
    xPos = xPos/ex.eyeCal.RXGain;
    yPos = yPos/ex.eyeCal.RYGain;
end

xTol = xTol * tolerance_scalar;
yTol = yTol * tolerance_scalar;
%xPos = mean([xPos/ex.eyeCal.RXGain,xPos/ex.eyeCal.LXGain],2);
%yPos = mean([yPos/ex.eyeCal.RYGain,yPos/ex.eyeCal.LYGain],2);
pass_eye = passEyeXYx(ex,trEye,n,nBufFr,xTol,yTol,xPos,yPos,1);


% compute last x,y eye position relative to the center in pixels

%shifts by the center voltages X0 Y0 to calc difference from screen center, but then adds ex.fix.PCtr, which makes it in absolute pixel coords
% xx this needs to be it's own func
if ~isempty(ex.eyeCal.LXPos)
    lastEyePos = ...
        [(trEye.v(1,n+nBufFr)-ex.eyeCal.RX0-ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RX0)*ex.eyeCal.RXGain+ex.fix.PCtr(1),... %Rxpos
        (trEye.v(2,n+nBufFr)-ex.eyeCal.RY0-ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RY0)*ex.eyeCal.RYGain+ex.fix.PCtr(2); ...   %Rypos
        (trEye.v(4,n+nBufFr)-ex.eyeCal.LX0-ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).LX0)*ex.eyeCal.LXGain+ex.fix.PCtr(1),... %Lxpos
        (trEye.v(5,n+nBufFr)-ex.eyeCal.LY0-ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).LY0)*ex.eyeCal.LYGain+ex.fix.PCtr(2)]; %Lypos
    
else
    lastEyePos = ...
        [(trEye.v(1,n+nBufFr)-ex.eyeCal.RX0-ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RX0)*ex.eyeCal.RXGain+ex.fix.PCtr(1),... %xpos
        (trEye.v(2,n+nBufFr)-ex.eyeCal.RY0-ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RY0)*ex.eyeCal.RYGain+ex.fix.PCtr(2)];   %ypos
end

trEye.n=trEye.n+nBufFr;  % update numberAcquiredFrames

if ex.passOn || freeViewing == 1
    pass_eye =1;
end
%disp(['passeye:' num2str(pass_eye)])



% ------------------------------------------------------------------------
% ------- subfunctions -----------------------------------------------------
% ------------------------------------------------------------------------
function pass_eye = passEyeXYx(ex,trEye,n,nBufFr,xTol,yTol,xPos,yPos,checkRightOnly)
if ~isempty(ex.eyeCal.LXPos) %both eyes
    x = mean([trEye.v([1 4],n+1:n+nBufFr)-[ex.eyeCal.RX0 + ...
        ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RX0; ex.eyeCal.LX0+ ...
        ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).LX0]*ones(1,nBufFr)],1);
    y = mean([trEye.v([2 5],n+1:n+nBufFr)-[ex.eyeCal.RY0 + ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RY0; ...
        ex.eyeCal.LY0 + ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).LY0] ...
        *ones(1,nBufFr)],1)  ;
    passX = sum(abs(x-xPos)>xTol);
    passY = sum(abs(y-yPos)>yTol);
    passXY = passX+passY;
    %|| checkRightOnly
else
    passX = sum(abs(trEye.v(1,n+1:n+nBufFr)-ex.eyeCal.RX0 - ...
        ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RX0-xPos)>xTol);
    passY = sum(abs(trEye.v(2,n+1:n+nBufFr)-ex.eyeCal.RY0 - ...
        ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RY0-yPos)>yTol);
    passXY = passX+passY;
end

pass_eye = 0;
if passXY==0 && ~isnan(xPos) & ~isnan(yPos) % new conditions added to exclude nan positions
    pass_eye = 1;
end


