function played = playCoPsRewardSoundx(audio)
% Request one cue without waiting for playback or interrupting an active cue.
played = false;
if ~audio.enabled
    return
end
status = PsychPortAudio('GetStatus', audio.handle);
% Very closely spaced crossings share the active cue rather than blocking
% the stimulus loop or repeatedly restarting the sound.
if status.Active
    return
end
PsychPortAudio('Start', audio.handle, 1, 0, 0);
played = true;
end
