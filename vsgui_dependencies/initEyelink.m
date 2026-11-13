function ex=initEyelink(ex,varargin)

% function ex=initEyelink(ex)
% initializes Eyelink connection
% 07/11/14  hn: -included field 'setup' and moved setup parameters into it
%               new parameter name          old parameter name
%               ex.setup.el                 ex.el
%               ex.setup.stereo             ex.stereo
% 01/14/15  hn: included handles input to allow for optionally switching
%               off the corneal reflex

el =ex.setup.el;

ex.setup.el=EyelinkInitDefaults(ex.setup.window);
% Initialization of the connection with the Eyelink Gazetracker.
if ~ EyelinkInit()
    error('Eyelink cannot be initialized')
end

% open file for recording data
Eyelink('Openfile', el.edfFileName);

% Start Recording
Eyelink('StartRecording');
ex.setup.el.elstart = Eyelink('TrackerTime');
ex.setup.el.hasSamples = true; ex.setup.el.hasEvents = true;
Eyelink('Command', el.Cmd_SampleData); 
WaitSecs(0.5);
Eyelink('Command','inputword_is_window = ON');
WaitSecs(0.5);
if nargin>1
    handles = varargin{1};
    if get(handles.cornealReflexOff,'Value')    
        disp('switching corneal reflex measurements off')
        %% commands to switch off corneal reflex
        % iknew: 6.8.2022
        Eyelink('Command','force_corneal_reflection = OFF');
        WaitSecs(0.5);
        Eyelink('Command','allow_pupil_without_cr = ON');
        WaitSecs(0.5);
        Eyelink('Command','elcl_hold_if_no_corneal = OFF');
        WaitSecs(0.5);
        Eyelink('Command','elcl_search_if_no_corneal = OFF');
        WaitSecs(0.5);
        Eyelink('Command','elcl_use_pcr_matching = OFF');
        WaitSecs(0.5);
    end
end
names = fieldnames(el);
for n=1:length(names)
    eval(['ex.setup.el.' names{n} '= el.' names{n} ';']);
end


ex.setup.eyeTracker = 'Eyelink';





