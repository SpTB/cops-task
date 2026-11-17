function cleanup = openCoPsQuestionWindowx(screen,message)
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
cleanup = onCleanup(@() closeWindowLocal(window));
Screen('TextSize',window,max(14,min(28,floor(sizePx(2)/15))));
Screen('TextStyle',window,0);
Screen('FillRect',window,[80 0 0]);
DrawFormattedText(window,message,'center','center',255,42,[],[],1.25);
Screen('Flip',window,0,0,2);
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
