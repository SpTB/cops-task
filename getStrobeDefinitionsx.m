function ex = getStrobeDefinitionsx(ex)

% function ex = getStrobeDefinitions(ex)
% here we define the meaning of the strobe words that are being sent from
% datapixx to ripple
% DO NOT USE values 1 through 10000 (they are reserved to send digits such
% as trial IDs or trial numbers)
% note that bit 1 is also used for the reward 

% history
% 08/05/14  hn; wrote it
% 12/05/17  hn: added strobes for sleep on/off


% reserved: 1:10000 for trial numbers etc.

ex.strobe.TRIAL_START       = 10001;
ex.strobe.TRIAL_END         = 10002;
ex.strobe.TRIAL_ID          = 10003; % should always be followed by 
%                                     6 digits representing clocktime YYYY MO DY HOUR MIN SEC
ex.strobe.TRIAL_NUMBER      = 10004;
ex.strobe.FILE_ID           = 10005; % followed by 6 digits representing clocktime YYYY MO DY HOUR MIN SEC
ex.strobe.EXPERIMENT_START  = 10006;
ex.strobe.EXPERIMENT_END    = 10007;

ex.strobe.FIXATION_START    = 10008;

ex.strobe.SLEEP_ON          = 10011;
ex.strobe.SLEEP_OFF         = 10012;

ex.strobe.SYNC_PULSE = 2;  % use the 2nd bit for the synchronization 
                            % between grapevine and datapixx
                            % this is usually not used as a strobe word

%ex.strobe.REWARD = 1;       % default strobe used for reward 





