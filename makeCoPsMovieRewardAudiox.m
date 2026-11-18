function [audio,eventTimes] = makeCoPsMovieRewardAudiox(eventTimes,durationSec,sampleRate)
% Place one reward cue at each logged crossing, with silence between events.
if nargin < 3, sampleRate = 48000; end
nSamples = max(1,round(durationSec*sampleRate));
audio = zeros(2,nSamples);
eventTimes = reshape(eventTimes(isfinite(eventTimes) & eventTimes>=0 & eventTimes<durationSec),1,[]);
tone = makeCoPsRewardBeepx(sampleRate);
for k=1:numel(eventTimes)
    first = min(nSamples,round(eventTimes(k)*sampleRate)+1);
    count = min(size(tone,2),nSamples-first+1);
    idx = first:first+count-1;
    audio(:,idx) = audio(:,idx)+tone(:,1:count);
end
audio = max(-1,min(1,audio));
end
