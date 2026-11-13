function initDatapixx(ex)

% function initDatapixx(ex)
% initializes Datapixx when starting VisStim
%
% history
% 12/31/14  hn: moved resetAdcBuffer(ex) to getDefaultSettings

Datapixx('Open');
Datapixx('StopAllSchedules');


%% initialize Audio Channels  %% still need to pre-load default waves
Datapixx('InitAudio'); 

%% initialize DigitalOut (for reward);  
Datapixx('EnableDoutDinLoopback');
Datapixx('DisableDinDebounce');    
Datapixx('SetDinLog');       
Datapixx('StartDinLog');   
Datapixx('SetDoutValues',0);
Datapixx('RegWrRd')

    

