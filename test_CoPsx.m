% TEST SCRIPT FOR RESTRUCTURED CoPs TASK
% This script demonstrates how to use the restructured CoPs functions
%
% Usage:
% 1. Initialize experiment structure with initEx2()
% 2. Set up CoPs specific parameters
% 3. Run trial with runTrialTaskCoPsx()

clear all;
close all;

fprintf('=== CoPs Task Test ===\n');

% Initialize experiment structure
try
    ex = initEx2(false, false, false, false, false);
    fprintf('✓ Experiment structure initialized\n');
catch err
    fprintf('✗ Failed to initialize experiment: %s\n', err.message);
    return;
end

% Set up CoPs specific parameters
ex.exp.CoPs.dirs.file_folder = '/home/nlab/Desktop/VSgui/test1_water_dep.jpg/'; % UPDATE THIS PATH
ex.exp.CoPs.pos.initx1 = 0;
ex.exp.CoPs.pos.inity1 = 0;
ex.exp.CoPs.pos.dxmin1 = -50;
ex.exp.CoPs.pos.dxmax1 = 50;
ex.exp.CoPs.pos.dymin1 = -50;
ex.exp.CoPs.pos.dymax1 = 50;

ex.exp.CoPs.pos.initx2 = 100;
ex.exp.CoPs.pos.inity2 = 0;
ex.exp.CoPs.pos.dxmin2 = -50;
ex.exp.CoPs.pos.dxmax2 = 50;
ex.exp.CoPs.pos.dymin2 = -50;
ex.exp.CoPs.pos.dymax2 = 50;

ex.exp.CoPs.graph.size_mult = 2;
ex.exp.CoPs.graph.radius = 30;
ex.exp.CoPs.graph.full_as_background = true;

ex.exp.CoPs.ctl.nsteps = 5;
ex.exp.CoPs.ctl.target_num = 2;
ex.exp.CoPs.ctl.circle_target_loc = true;
ex.exp.CoPs.ctl.reward_threshold = 10.0;

ex.stim.vals.precision_weight = 0.5;
ex.stim.vals.wait_secs = 1.0;

fprintf('✓ CoPs parameters configured\n');

% Initialize display (using minimal version without hardware dependencies)
try
    ex = initDisplayx(ex);
    fprintf('✓ Display initialized\n');
    
    % Additional color indices that may be needed
    if ~isfield(ex.idx, 'bg_lum') || isempty(ex.idx.bg_lum)
        ex.idx.bg_lum = ex.idx.bg;
    end
    
    fprintf('✓ Screen-dependent parameters set\n');
    
catch err
    fprintf('✗ Failed to initialize display: %s\n', err.message);
    return;
end

% Test helper functions
fprintf('\n=== Testing Helper Functions ===\n');

% Test simTargPos
try
    positions = simTargPosx(10, 0, -10, 10);
    fprintf('✓ simTargPos: Generated %d positions\n', length(positions));
catch err
    fprintf('✗ simTargPos failed: %s\n', err.message);
end

% Test calc_closeness
try
    closeness = calc_closeness([100, 100], [150, 150], 100);
    fprintf('✓ calc_closeness: Closeness = %.3f\n', closeness);
catch err
    fprintf('✗ calc_closeness failed: %s\n', err.message);
end

% Test gauss_mask
try
    test_image = zeros(200, 200);
    mask = gauss_mask(test_image, 100, 100, 30);
    fprintf('✓ gauss_mask: Created mask with size %dx%d\n', size(mask, 1), size(mask, 2));
catch err
    fprintf('✗ gauss_mask failed: %s\n', err.message);
end

% Test gauss_rew_land
try
    reward_land = gauss_rew_land(200, [100, 100], 50);
    fprintf('✓ gauss_rew_land: Created reward landscape %dx%d\n', size(reward_land, 1), size(reward_land, 2));
catch err
    fprintf('✗ gauss_rew_land failed: %s\n', err.message);
end

fprintf('\n=== Running CoPs Task ===\n');

% Check if stimulus folder exists and run the task
if exist(ex.exp.CoPs.dirs.file_folder, 'dir')
    fprintf('Stimulus folder found: %s\n', ex.exp.CoPs.dirs.file_folder);
    try
        fprintf('Running CoPs trial...\n');
        ex = runTrialTaskCoPsx(ex);
        fprintf('✓ CoPs trial completed successfully\n');
    catch err
        fprintf('✗ CoPs trial failed: %s\n', err.message);
        fprintf('Error occurred at line %d in %s\n', err.stack(1).line, err.stack(1).name);
    end
else
    fprintf('✗ Stimulus folder not found: %s\n', ex.exp.CoPs.dirs.file_folder);
    fprintf('Please update ex.exp.CoPs.dirs.file_folder with the correct path\n');
end

fprintf('\n=== Test Complete ===\n');
