function pass_eye = passEyeXY(ex,trEye,n,nBufFr,xTol,yTol,xPos,yPos,checkRightOnly)
if ~isempty(ex.eyeCal.LXPos) %|| checkRightOnly
    x = mean([trEye.v([1 4],n+1:n+nBufFr)-[ex.eyeCal.RX0 + ...
        ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RX0; ex.eyeCal.LX0+ ...
        ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).LX0]*ones(1,nBufFr)],1);
    y = mean([trEye.v([2 5],n+1:n+nBufFr)-[ex.eyeCal.RY0 + ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).RY0; ...
        ex.eyeCal.LY0 + ex.eyeCal.Delta(ex.eyeCal.Delta(1).cnt).LY0] ...
        *ones(1,nBufFr)],1)  ;
    passX = sum(abs(x-xPos)>xTol);
    passY = sum(abs(y-yPos)>yTol);
    passXY = passX+passY;
    
else
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


