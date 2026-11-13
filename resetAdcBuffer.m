function resetAdcBuffer(ex)

% empty the AdcBuffer such that not so many frames need to be sampled on
% the next call of Datapixx('ReadAdcBuffer', status.newBufferFrames,-1) to
% prevent slowdown

% 11/4/26 copied from VSGUI by Emily

Datapixx('StopAdcSchedule')
if nargin<1
    Datapixx('SetAdcSchedule',0,500,0,[0:2,0,0,0],0,5e6); % monocular eye data
else
    Datapixx('SetAdcSchedule',0,ex.setup.adc.Rate,0,...
        [ex.setup.adc.Channels;ex.setup.adc.DiffChannels],...
        ex.setup.adc.BufferBaseAddress,ex.setup.adc.NumBufferFrames);
end
Datapixx('StartAdcSchedule')
Datapixx('EnableAdcFreeRunning');
Datapixx('RegWrRd')