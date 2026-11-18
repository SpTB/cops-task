classdef CoPsMovieWriterx < handle
    % Own a PTB/GStreamer encoder so errors and Ctrl+C still close the MP4.
    properties (Access=private)
        movie = []
    end
    methods
        function obj = CoPsMovieWriterx(window,file,sizePx,fps,audioSampleRate)
            if nargin < 5, audioSampleRate = 0; end
            % GStreamer's pipeline parser treats Windows backslashes as
            % escapes and requires quotes around filenames containing spaces.
            encoderFile = file;
            if ispc, encoderFile = strrep(encoderFile,'\','/'); end
            encoderFile = strrep(encoderFile,'\','\\');
            encoderFile = ['"' strrep(encoderFile,'"','\"') '"'];
            % A complete pipeline makes the 4:2:0/Main constraints explicit;
            % older PTB codec-option parsers can discard downstream caps.
            video = sprintf(['gst-launch appsrc name=ptbvideoappsrc format=3 do-timestamp=0 ' ...
                'stream-type=0 max-bytes=0 block=1 is-live=0 emit-signals=0 ' ...
                'caps="video/x-raw,format=RGB,width=(int)%d,height=(int)%d,framerate=%d/1" ' ...
                '! videorate ! videoconvert ! video/x-raw,format=I420 ' ...
                '! x264enc bitrate=12000 speed-preset=fast ! video/x-h264,profile=main'],sizePx(1),sizePx(2),fps);
            if audioSampleRate > 0
                % Unbounded encoded queues let either track be supplied first
                % without the muxer blocking the other appsrc during export.
                queue = 'queue max-size-buffers=0 max-size-bytes=0 max-size-time=0';
                codec = sprintf(['%s ! %s ! ptbmux. ' ...
                    'appsrc name=ptbaudioappsrc format=3 do-timestamp=0 stream-type=0 ' ...
                    'max-bytes=0 block=1 is-live=0 emit-signals=0 ' ...
                    'caps="audio/x-raw,format=F32LE,rate=(int)%d,channels=(int)2,layout=interleaved" ' ...
                    '! audioconvert ! avenc_aac bitrate=192000 ! aacparse ! %s ! ptbmux. ' ...
                    'mp4mux name=ptbmux ! filesink name=ptbfilesink async=0 location=%s'], ...
                    video,queue,audioSampleRate,queue,encoderFile);
            else
                codec = sprintf('%s ! mp4mux ! filesink name=ptbfilesink async=0 location=%s',video,encoderFile);
            end
            try
                obj.movie = Screen('CreateMovie',window,encoderFile,sizePx(1),sizePx(2),fps,codec,3);
            catch err
                error('recEx:Encoder','Cannot open MP4 encoder for %s. GStreamer needs x264enc/mp4mux, plus avenc_aac for reward audio. %s',file,err.message);
            end
        end
        function addFrame(obj,window)
            Screen('AddFrameToMovie',window,[],[],obj.movie,1);
        end
        function addAudio(obj,samples)
            Screen('AddAudioBufferToMovie',obj.movie,samples);
        end
        function finish(obj)
            movie = obj.movie;
            obj.movie = [];
            Screen('FinalizeMovie',movie);
        end
        function delete(obj)
            if ~isempty(obj.movie)
                try
                    Screen('FinalizeMovie',obj.movie);
                catch
                    % Do not mask the export error or user interruption.
                end
                obj.movie = [];
            end
        end
    end
end
