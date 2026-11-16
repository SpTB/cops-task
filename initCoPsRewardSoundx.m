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
nSamples = max(2, round(audio.durationSecs * audio.sampleRate));
t = (0:nSamples-1) / audio.sampleRate;
envelope = ones(1, nSamples);
nRamp = min(floor(nSamples / 2), max(1, round(0.003 * audio.sampleRate)));
ramp = 0.5 - 0.5 * cos(linspace(0, pi, nRamp));
envelope(1:nRamp) = ramp;
envelope(end-nRamp+1:end) = fliplr(ramp);
tone = audio.gain * sin(2 * pi * audio.frequencyHz * t) .* envelope;
PsychPortAudio('FillBuffer', handle, [tone; tone]);
end

function closeAudio(handle)
try
    PsychPortAudio('Close', handle);
catch
    % Cleanup must not mask the task's original error.
end
end
