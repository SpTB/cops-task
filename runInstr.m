function ex = runInstr(instrVersion)
% Preview instruction text on the local display, without hardware or trials.
%   runInstr()        % long instructions (default)
%   runInstr('long')  % welcome, targets, dynamic, training, ready
%   runInstr('short') % welcome, dynamic, ready
% SPACE advances each page; F4 closes the preview. Nothing is saved to disk.
arguments
    instrVersion (1,1) string {mustBeMember(instrVersion,["short","long"])} = "long"
end

evalc('ex = setDefaultsCoPs(struct());');
ex.exp.CoPs.instrOn = true;
ex.exp.CoPs.instr.version = char(instrVersion);
ex.exp.CoPs.sync.mode = 'off';
ex.exp.CoPs.pre.nreps = 0;
ex.exp.CoPs.tut.nreps = 0;
ex.exp.CoPs.pur.nreps = 0;
% Quote the configured bonus for one reference hour without making a plan.
ex.exp.nreps = ex.exp.CoPs.pay.trials_per_hour;
ex.j = 1;
ex.quit = 0;
ex.Trials = struct([]);
ex.setup = struct('inputMode','none','eyeTracker','none', ...
    'instructionsOnly',true,'guiWindow',true,'panelFitterOn',false, ...
    'keyboards',struct('separate',false));
ex.idx = struct('bg_lum',128,'white',255,'black',0);

screens = Screen('Screens');
% Linux screen 0 is the local desktop on the rig. Windows 0 spans monitors.
if IsWin && numel(screens) > 1, screens(screens==0) = []; end
ex.setup.screenNum = min(screens);
desktop = Screen('Rect',ex.setup.screenNum);
sizePx = min([1280 900],floor(0.8*(desktop(3:4)-desktop(1:2))));
origin = desktop(1:2)+round(((desktop(3:4)-desktop(1:2))-sizePx)/2);

oldSkip = Screen('Preference','SkipSyncTests');
oldVRAM = Screen('Preference','ConserveVRAM');
preferencesCleanup = onCleanup(@() restorePreferencesLocal(oldSkip,oldVRAM)); %#ok<NASGU>
Screen('Preference','SkipSyncTests',2); % text preview needs no timing validation
Screen('Preference','ConserveVRAM',bitor(oldVRAM,32));
window = Screen('OpenWindow',ex.setup.screenNum,ex.idx.bg_lum, ...
    [origin origin+sizePx],[],[],[],[],[],kPsychGUIWindow);
windowCleanup = onCleanup(@() closeWindowLocal(window)); %#ok<NASGU>
ex.setup.window = window;
ex.setup.screenRect = Screen('Rect',window);

stages = {'welcome','dynamic','ready'};
if instrVersion == "long"
    plan = getCoPsInstructionPlanx(ex.exp.CoPs.instr,ex.exp.CoPs.train);
    stages = {'welcome','targets','dynamic'};
    if plan.trainingTrials > 0, stages{end+1} = 'training'; end
    stages{end+1} = 'ready';
end
for k = 1:numel(stages)
    ex = showCoPsInstructionsx(ex,stages{k});
    if ex.quit ~= 0, break; end
end
end

function restorePreferencesLocal(oldSkip,oldVRAM)
Screen('Preference','SkipSyncTests',oldSkip);
Screen('Preference','ConserveVRAM',oldVRAM);
end

function closeWindowLocal(window)
% Close only this preview, including when text rendering or input fails.
try
    Screen('Close',window);
catch
    % Do not mask the original error if the window has already been closed.
end
end
