function result = coPsOverlayProcessx(action, varargin)
% Own the viewer and a nonblocking UDP sender outside the saved experiment.
persistent viewer
result = [];
switch action
    case 'open'
        coPsOverlayProcessx('close');
        setup = varargin{1};
        folder = tempname; mkdir(folder);
        token = char(java.util.UUID.randomUUID);
        display = regexprep(getenv('DISPLAY'),'\.\d+$','');
        display = sprintf('%s.%d',display,setup.overlayScreen);
        config = struct('token',token,'display',display,'windowRect',setup.overlayWindowRect, ...
            'screenRect',setup.screenRect,'rateHz',30,'parentPid',feature('getpid'), ...
            'backgroundColor',setup.overlayBackgroundColor,'readyFile',fullfile(folder,'ready.json'), ...
            'statusFile',fullfile(folder,'status.json'));
        fid = fopen(fullfile(folder,'config.json'),'w');
        if fid<0, error('CoPs:OverlayConfig','Cannot write viewer configuration.'); end
        fprintf(fid,'%s',jsonencode(config)); fclose(fid);
        helper = fullfile(fileparts(mfilename('fullpath')),'tools','cops_overlay_viewer.py');
        builder = javaObject('java.lang.ProcessBuilder',{'python3',helper,fullfile(folder,'config.json')});
        builder.redirectErrorStream(true);
        logFile = fullfile(folder,'viewer.log');
        builder.redirectOutput(javaObject('java.io.File',logFile));
        process = builder.start();
        viewer = struct('process',process,'channel',[],'folder',folder, ...
            'cleanup',onCleanup(@() process.destroyForcibly()));
        try
            deadline = tic;
            while ~isfile(config.readyFile)
                if ~process.isAlive() || toc(deadline)>10
                    error('CoPs:OverlayStartup','Preview did not start. Details: %s',fileread(logFile));
                end
                pause(.02); % Startup only; never used by the trial sender.
            end
            info = jsondecode(fileread(config.readyFile));
            channel = java.nio.channels.DatagramChannel.open();
            channel.configureBlocking(false);
            address = javaObject('java.net.InetSocketAddress','127.0.0.1',int32(info.port));
            viewer.channel = channel; viewer.address = address; viewer.token = token;
            viewer.sequence = 0; viewer.lastSent = -Inf; viewer.sent = 0; viewer.failed = 0;
            viewer.totalSendSec=0;viewer.maxSendSec=0;
            result = struct('port',info.port,'pid',info.pid,'token',token,'logFile',logFile, ...
                'statusFile',config.statusFile);
        catch err
            coPsOverlayProcessx('close');
            rethrow(err);
        end
    case 'send'
        if isempty(viewer) || isempty(viewer.channel), result=false; return; end
        setup=varargin{1};frame=varargin{2};force=false;
        if numel(varargin)>2, force=varargin{3}; end
        if ~strcmp(setup.overlayViewer.token,viewer.token), result=false; return; end
        now=GetSecs;
        if ~force && now-viewer.lastSent<1/setup.overlayDisplayRateHz, result=false; return; end
        viewer.lastSent=now; viewer.sequence=viewer.sequence+1;
        sendTimer=tic;
        packet=struct('token',viewer.token,'sequence',viewer.sequence,'frame',frame);
        try
            bytes=typecast(uint8(unicode2native(jsonencode(packet),'UTF-8')),'int8');
            buffer=java.nio.ByteBuffer.wrap(bytes);
            result=viewer.channel.send(buffer,viewer.address)>0;
            viewer.sent=viewer.sent+double(result);
        catch
            viewer.failed=viewer.failed+1; result=false;
        end
        elapsed=toc(sendTimer);viewer.totalSendSec=viewer.totalSendSec+elapsed;
        viewer.maxSendSec=max(viewer.maxSendSec,elapsed);
    case 'stats'
        if ~isempty(viewer) && isfield(viewer,'sent')
            result=struct('sent',viewer.sent,'failed',viewer.failed, ...
                'meanSendSec',viewer.totalSendSec/max(1,viewer.sequence),'maxSendSec',viewer.maxSendSec);
        end
    case 'close'
        if isempty(viewer), return; end
        old=viewer;viewer=[];
        try, if ~isempty(old.channel), old.channel.close(); end; catch, end
        try, old.process.destroyForcibly(); catch, end
        % The tiny logs/config are retained for diagnosing startup failures.
    otherwise
        error('CoPs:OverlayAction','Unknown preview action: %s',action);
end
end
