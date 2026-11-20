function [cleanup,poll] = openCoPsQuestionWindowx(screen,message)
% A temporary informational GUI window on a specific Psychtoolbox screen.
oldVRAM = Screen('Preference','ConserveVRAM');
oldSkip = Screen('Preference','SkipSyncTests');
preferences = onCleanup(@() restorePreferencesLocal(oldVRAM,oldSkip)); %#ok<NASGU>
Screen('Preference','ConserveVRAM',bitor(oldVRAM,32));
Screen('Preference','SkipSyncTests',2);
r = Screen('Rect',screen);
sizePx = min([700 380],floor(0.8*(r(3:4)-r(1:2))));
origin = r(1:2)+round(((r(3:4)-r(1:2))-sizePx)/2);
window = Screen('OpenWindow',screen,[80 0 0],[origin origin+sizePx], ...
    [],[],[],[],[],kPsychGUIWindow);
isOpen = true;
cleanup = onCleanup(@closeWindow);
[~,~,buttons] = GetMouse(window);
mouseWasDown = ~isempty(buttons) && buttons(1);
poll = @pollCloseButton;
closeRect = [sizePx(1)-46 10 sizePx(1)-10 46];
Screen('TextSize',window,max(14,min(28,floor(sizePx(2)/15))));
Screen('TextStyle',window,0);
Screen('FillRect',window,[80 0 0]);
DrawFormattedText(window,message,'center','center',255,42,[],[],1.25);
% PTB GUI windows do not reliably expose a native title-bar close button.
Screen('FrameRect',window,255,closeRect,2);
DrawFormattedText(window,'X','center','center',255,[],[],[],1,[],closeRect);
Screen('Flip',window,0,0,2);

    function pollCloseButton
        if ~isOpen, return; end
        try
            [x,y,buttons] = GetMouse(window);
            down = ~isempty(buttons) && buttons(1);
            if down && ~mouseWasDown && x >= closeRect(1) && x <= closeRect(3) && ...
                    y >= closeRect(2) && y <= closeRect(4)
                closeWindow();
            end
            mouseWasDown = down;
        catch
            closeWindow(); % The window may already have been dismissed.
        end
    end

    function closeWindow
        if ~isOpen, return; end
        isOpen = false; % Avoid closing a later window that reuses this handle.
        closeWindowLocal(window);
    end
end

function restorePreferencesLocal(vram,skip)
Screen('Preference','ConserveVRAM',vram);
Screen('Preference','SkipSyncTests',skip);
end

function closeWindowLocal(window)
try
    Screen('Close',window);
catch
    % Do not mask a task error if the window was already closed by its user.
end
end
