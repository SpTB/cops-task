function closeCoPsDisplayx()
% Safely release Psychtoolbox display state after a task run or error.

try
    Screen('CloseAll');
catch
    % Cleanup must never mask the original task error.
end

try
    ShowCursor;
catch
    % ShowCursor may be unavailable before Psychtoolbox initialization.
end
end
