function resetAdcBuffer(ex)

% function resetAdcBuffer(ex)
%
% empty the AdcBuffer such that not so many frames need to be sampled on
% the next call of Datapixx('ReadAdcBuffer',status.newBufferFrames,-1) to
% prevent slowdown
%
% history
% 11/13/13  hn written
% 07/11/14  hn: -included field 'setup' and moved setup parameters into it
%               new parameter name          old parameter name
%               ex.setup.adc                ex.adc


        
Datapixx('StopAdcSchedule')
if nargin<1
    Datapixx('SetAdcSchedule',0,500,0,[0:2;0,0,0],0,5e6); %monocular eye data
else
    Datapixx('SetAdcSchedule',0,ex.setup.adc.Rate,0,...
        [ex.setup.adc.Channels;ex.setup.adc.DiffChannels],...
        ex.setup.adc.BufferBaseAddress,ex.setup.adc.NumBufferFrames); 
end
Datapixx('StartAdcSchedule')
Datapixx('EnableAdcFreeRunning');
Datapixx('RegWrRd')
