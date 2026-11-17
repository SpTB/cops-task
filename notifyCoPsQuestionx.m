function [request,cleanup] = notifyCoPsQuestionx(ex)
% Open a separate question window, routed to the experimenter's display.
message = sprintf(['The participant has a question.\n\nPlease come over to the participant.\n\n' ...
    'They have been asked to keep their head still.']);
request = struct('time',GetSecs,'target','');
cleanup = [];
fprintf('\nPARTICIPANT QUESTION: Please come over to the participant.\n');
try
    screen = [];
    if isfield(ex.setup,'screenNum')
        others = setdiff(Screen('Screens'),ex.setup.screenNum);
        if isfield(ex.setup,'overlayScreen') && ...
                isscalar(ex.setup.overlayScreen) && ismember(ex.setup.overlayScreen,others)
            screen = ex.setup.overlayScreen;
        else
            % Windows screen 0 spans monitors; it is not another monitor.
            if IsWin, others(others==0) = []; end
            if ~isempty(others), screen = min(others); end
        end
    end
    if ~isempty(screen)
        % A real GUI window, separate from both overlayWindow and its canvas.
        % Screen-local coordinates also work across Linux X screens.
        cleanup = openCoPsQuestionWindowx(screen,message);
        request.target = 'experimenterPopup';
        return
    end
catch err
    warning('notifyCoPsQuestionx:Display','Experimenter window unavailable: %s',err.message);
end
try
    options = struct('WindowStyle','non-modal','Interpreter','none');
    handle = msgbox(message,'Participant question','help',options);
    request.target = 'experimenterDesktop';
    cleanup = onCleanup(@() closeDialogLocal(handle));
catch err
    request.target = 'console';
    warning('notifyCoPsQuestionx:NoDialog','Question request logged; desktop popup could not open: %s',err.message);
end
end

function closeDialogLocal(handle)
if ~isempty(handle) && isgraphics(handle), delete(handle); end
end
