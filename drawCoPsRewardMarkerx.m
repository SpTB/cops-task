function drawCoPsRewardMarkerx(window,rect)
% Draw a green outline entirely inside the stimulus square.
width = max(2,round(min(rect(3:4)-rect(1:2))/180));
inside = rect+(width/2)*[1 1 -1 -1];
if any(inside(3:4)<=inside(1:2)), return; end
Screen('FrameRect',window,[0 255 0],inside,width);
end
