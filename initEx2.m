function ex = initEx2(run_trial, overlayOn, pixOn, rewOn, eyeOn, eyeStr, skipQuest)
% with full questionnaire...

arguments
    run_trial {mustBeNumericOrLogical} = true
    overlayOn  {mustBeNumericOrLogical} = true
    pixOn  {mustBeNumericOrLogical} = true
    rewOn {mustBeNumericOrLogical} = true
    eyeOn  {mustBeNumericOrLogical} = true
    eyeStr {mustBeText} = 'y'
    skipQuest {mustBeNumericOrLogical} = true
end

% Eyelink('Shutdown');
ex = struct();
if ~Datapixx('Open')
    initDatapixx(ex);
end

ex = setDefaultsCoPs(ex);

sequenceModeIm = false;
if isfield(ex.exp.CoPs.graph, 'sequenceMode_im') && ~isempty(ex.exp.CoPs.graph.sequenceMode_im)
    sequenceModeIm = ex.exp.CoPs.graph.sequenceMode_im;
elseif isfield(ex.exp.CoPs.graph, 'sequenceMode') && ~isempty(ex.exp.CoPs.graph.sequenceMode)
    sequenceModeIm = ex.exp.CoPs.graph.sequenceMode;
end
ex.stim.seq = makeSequencex(ex.exp.CoPs.dirs.all, 1, 1, ex.exp.CoPs.graph.imgs, sequenceModeIm);% can use ex.exp.nreps if want more than 1 trial ex=getDefaultSettingsx(ex, skipQuest);
ex=getDefaultSettingsx(ex, skipQuest);
ex.states.PREGO = 5.95

if eyeOn
    ex = initDisplayxx(ex, overlayOn);
else
    ex = initDisplayx(ex );%can run initDisplayx for normal view
end
pause(1)

if eyeOn
    
    ex.setup.VSdirRoot = pwd;
    % handles = initEyeHandlesx(ex);
    % ex = initEyelink(ex, handles);
    ex = initEyelink(ex);
    % ex.eyeCal = NaN;
    switch lower(eyeStr)
        
        case 'y'
            ex = calibrateEye_rev(ex)
            disp('eye calibration done')
            
        case 'l'
            % p = fileparts(ex.setup.VSdirRoot);
            % [fn,pth] = uigetfile(p);
            % exTemp=load(fullfile(pth,fn));
            
            % How to extract it depends on the mat struct...whether the whole ex is saved or just the eyeCal...
            exTemp=load('/home/vpixx/data/test/2026.01.19/t_10.59.EyeCal/')
            if isfield(exTemp, 'ex') % whole ex struct case
                ex.eyeCal = exTemp.ex.eyeCal;
            elseif isfield (exTemp, 'eyeCal')
                ex.eyeCal = exTemp.eyeCal;
            else
                error('eyeCal field not found')
            end
        otherwise
    end
end

%run Expt fill-ins
ex.j = 1;  % current trial number
ex.goodtrial = 0;  % counter for successful trials
ex.loopcnt = zeros(1, ex.finish);  % loop counter for each trial

if run_trial
    ex = runTrialTaskCoPsx(ex, pixOn, eyeOn, rewOn);
end

end
