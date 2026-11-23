function [nextEvent,cleanup] = startCoPsFeedbackInputx(setup)
% Capture text without echoing it into MATLAB's command window.
separate = isfield(setup,'keyboards') && setup.keyboards.separate;
isolated = separate && isfield(setup.keyboards,'osKeysIsolated') && setup.keyboards.osKeysIsolated;
if IsLinux && ~isempty(getenv('DISPLAY')) && ~strcmpi(getenv('XDG_SESSION_TYPE'),'wayland') && ~isolated
    % ListenChar cannot suppress the R2025a+ desktop. An X11 client must own
    % the keyboard events and forward characters, rather than only poll them.
    helper = fullfile(fileparts(mfilename('fullpath')),'tools','cops_feedback_keyboard.py');
    builder = javaObject('java.lang.ProcessBuilder',{'python3',helper});
    builder.redirectErrorStream(true);
    process = builder.start();
    cleanup = onCleanup(@() stopProcessLocal(process));
    reader = javaObject('java.io.BufferedReader', ...
        javaObject('java.io.InputStreamReader',process.getInputStream(),'UTF-8'));
    started = tic;
    while ~reader.ready() && process.isAlive() && toc(started)<5
        WaitSecs('YieldSecs',0.01);
    end
    if ~reader.ready()
        error('CoPs:FeedbackKeyboard','The feedback keyboard capture did not start.');
    end
    message = readLocal(reader);
    if ~isfield(message,'ready') || ~message.ready
        error('CoPs:FeedbackKeyboard','%s',message.error);
    end
    nextEvent = @() pollProcessLocal(process,reader);
    return
end
% A floated participant device already cannot type into desktop applications.
% Other platforms retain PTB's standard queue/suppression path.
device = [];
if separate, device = setup.keyboards.participantIndex; end
KbQueueCreate(device);
cleanup = onCleanup(@() releaseQueueLocal(device));
ListenChar(-1);
KbQueueStart(device);
nextEvent = @() KbEventGet(device);
end

function event = pollProcessLocal(process,reader)
event = [];
if reader.ready()
    event = readLocal(reader);
    if isfield(event,'error')
        error('CoPs:FeedbackKeyboard','%s',event.error);
    end
elseif ~process.isAlive()
    error('CoPs:FeedbackKeyboard','The feedback keyboard capture stopped unexpectedly.');
end
end

function message = readLocal(reader)
message = jsondecode(char(reader.readLine()));
end

function stopProcessLocal(process)
try
    stream = process.getOutputStream();
    stream.write(uint8([double('stop') 10]));
    stream.flush();
    stream.close(); % Release after held keys come up; EOF alone means parent failure.
    if ~process.waitFor(int64(2),java.util.concurrent.TimeUnit.SECONDS)
        process.destroy(); % X11 also releases the grab if its client exits.
    end
catch
    process.destroy();
end
end

function releaseQueueLocal(device)
try
    KbQueueRelease(device);
catch
    % Always restore desktop input, including after a partial queue setup.
end
ListenChar(0);
end
