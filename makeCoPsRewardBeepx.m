function tone = makeCoPsRewardBeepx(sampleRate,frequencyHz,durationSecs,gain)
% Stereo reward cue shared by live playback and exported movie soundtracks.
if nargin < 2, frequencyHz = 800; end
if nargin < 3, durationSecs = 0.030; end
if nargin < 4, gain = 0.1; end
nSamples = max(2,round(durationSecs*sampleRate));
t = (0:nSamples-1)/sampleRate;
envelope = ones(1,nSamples);
nRamp = min(floor(nSamples/2),max(1,round(0.003*sampleRate)));
ramp = 0.5-0.5*cos(linspace(0,pi,nRamp));
envelope(1:nRamp) = ramp;
envelope(end-nRamp+1:end) = fliplr(ramp);
wave = gain*sin(2*pi*frequencyHz*t).*envelope;
tone = [wave;wave];
end
