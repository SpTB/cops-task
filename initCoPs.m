% configuration:::
function[ex]=initCoPs(ex)
%global ex
ex.exp.CoPs=struct();
% ex.exp.CoPs=1;
% task parameters

ex.exp.CoPs.ctl.precision_weight = 0.5;    % Closeness vs reward weighting
ex.exp.CoPs.ctl.target_num = 2;            % 1 or 2 targets
ex.exp.CoPs.ctl.nsteps = 10;                % Stimulus changes per trial
ex.exp.CoPs.ctl.wait_secs = 0.2;             % Duration per step

%ex.exp.CoPs.ctl.reward_mat = gauss_rew_land(ex.stim.vals.xdim, [ex.stim.vals.xdim/2, ex.stim.vals.ydim/2], 150);
ex.exp.CoPs.dirs.file_folder = 'test1_water_dep.jpg';  % Stimulus folder
% ex.exp.CoPs.dirs.full = [file_folder,'/full']% xx getfiles here would be nice
% positional parameters
ex.exp.CoPs.pos = struct();
% target 1
ex.exp.CoPs.pos.dxmin1=-10;
ex.exp.CoPs.pos.dxmax1=10;
ex.exp.CoPs.pos.dymin1=-10;
ex.exp.CoPs.pos.dymax1=10;
%target 2
ex.exp.CoPs.pos.dxmin2=-10;
ex.exp.CoPs.pos.dxmax2=10;
ex.exp.CoPs.pos.dymin2=-10;
ex.exp.CoPs.pos.dymax2=10;

% graphical parameters
ex.exp.CoPs.graph.size_mult=3;
ex.exp.CoPs.graph.full_as_background = 0;
ex.exp.CoPs.graph.radius = 15;
ex.exp.CoPs.ctl.circle_target_loc = 0;
StimStart = NaN*ones(1,ceil(ex.setup.refreshRate*ex.fix.stimDuration));

%initial target positions
ex.exp.CoPs.pos.initx1 = 192*ex.exp.CoPs.graph.size_mult;
ex.exp.CoPs.pos.inity1= 192*ex.exp.CoPs.graph.size_mult;
ex.exp.CoPs.pos.initx2 = 192*ex.exp.CoPs.graph.size_mult;
ex.exp.CoPs.pos.inity2= 192*ex.exp.CoPs.graph.size_mult;

% add to ex

ex.j = 1;  % Trial counter

ex.setup.stereo.Display = 1;
ex.setup.stereo.Mode = 8;
ex.setup.stereo.Multisampling = 8;


%ex = runTrialTaskCoPs(ex);  % Run one trial
% ex = runExpt(ex); % whole thing
end
