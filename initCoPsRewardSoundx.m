function [audio, cleanup] = initCoPsRewardSoundx(soundOn)
% Preload a short stereo reward cue once per session.
arguments
    soundOn (1,1) logical = true
end
audio = struct('enabled', soundOn, 'handle', [], 'frequencyHz', 800, ...
    'durationSecs', 0.030, 'gain', 0.1, 'sampleRate', [], ...
    'overlapPolicy', 'coalesce');
cleanup = [];
if ~soundOn
    return
end
InitializePsychSound(1);
try
    handle = PsychPortAudio('Open', [], 1, 1, [], 2);
catch err
    error('initCoPsRewardSoundx:OpenFailed', ...
        'Cannot open reward audio: %s. Use soundOn=false to run without sound.', err.message);
end
cleanup = onCleanup(@() closeAudio(handle));
status = PsychPortAudio('GetStatus', handle);
audio.handle = handle;
audio.sampleRate = status.SampleRate;
tone = makeCoPsRewardBeepx(audio.sampleRate,audio.frequencyHz,audio.durationSecs,audio.gain);
PsychPortAudio('FillBuffer', handle, tone);
end

function closeAudio(handle)
try
    PsychPortAudio('Close', handle);
catch
    % Cleanup must not mask the task's original error.
end
end
