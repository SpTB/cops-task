function ex = playRandomLines(ex)
% function ex = playCalibrationLines(ex)
%
% displays lines of random orientations with spacing pixels between them
% on left and right eye images to align projectors with
%%
xposb = round(rand(1,100)*ex.setup.screenRect(3));
yposb = round(rand(1,100)*ex.setup.screenRect(4));

xposw = round(rand(1,100)*ex.setup.screenRect(3));
yposw = round(rand(1,100)*ex.setup.screenRect(4));

widths = round(rand(1,100)*10)+1;
widths(find(widths>10)) = deal(10);


%%
linesXY_black = [xposb;yposb];
linesXY_white = [xposw;yposw];

if ex.setup.stereo.Display
    %disp('in stereodisplay')
    % Select right-eye image buffer for drawing:
    Screen('SelectStereoDrawBuffer', ex.setup.window, 0);
     Screen('FillRect',ex.setup.window,ex.idx.bg);  % background to start 
    % Draw right stim:
    
    Screen('DrawLines', ex.setup.window, linesXY_white, widths, ex.idx.white);
    Screen('DrawLines', ex.setup.window, linesXY_black, widths, ex.idx.black);
    
    % Select left-eye image buffer for drawing:
    Screen('SelectStereoDrawBuffer', ex.setup.window, 1);
    % Draw left stim:
    Screen('FillRect',ex.setup.window,ex.idx.bg);  % background to start
    Screen('DrawLines', ex.setup.window, linesXY_white, widths, ex.idx.white);
    Screen('DrawLines', ex.setup.window, linesXY_black, widths, ex.idx.black);
else
    Screen('FillRect',ex.setup.window,ex.idx.bg);  % background to start 
    % Draw right stim:
    
    Screen('DrawLines', ex.setup.window, linesXY_white, widths, ex.idx.white);
    Screen('DrawLines', ex.setup.window, linesXY_black, widths, ex.idx.black);
    
end



%%
Screen('Flip', ex.setup.window);

