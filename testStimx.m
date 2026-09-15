% TEST STIMULUS TEXTURES - Step 1 Debugging
% This function tests the output of makeStimulusCoPsx by saving each generated texture as an image
% Usage: testStimx()
%
% Purpose: Debug why only one target shows when target_num=2

function testStimx()
    fprintf('=== Testing makeStimulusCoPsx Output ===\n');
    
    % Initialize experiment structure (minimal version)
    try
        ex = initEx2(false, false, false, false, false);
        fprintf('✓ Experiment structure initialized\n');
    catch err
        fprintf('✗ Failed to initialize experiment: %s\n', err.message);
        return;
    end
    
    % Set up CoPs parameters for testing
    ex.exp.CoPs.dirs.file_folder = '/home/nlab/Desktop/VSgui/test1_water_dep.jpg/';
    ex.exp.CoPs.pos.initx1 = 0;
    ex.exp.CoPs.pos.inity1 = 0;
    ex.exp.CoPs.pos.dxmin1 = -50;
    ex.exp.CoPs.pos.dxmax1 = 50;
    ex.exp.CoPs.pos.dymin1 = -50;
    ex.exp.CoPs.pos.dymax1 = 50;
    
    ex.exp.CoPs.pos.initx2 = 100;  % Second target far from first
    ex.exp.CoPs.pos.inity2 = 0;
    ex.exp.CoPs.pos.dxmin2 = -50;
    ex.exp.CoPs.pos.dxmax2 = 50;
    ex.exp.CoPs.pos.dymin2 = -50;
    ex.exp.CoPs.pos.dymax2 = 50;
    
    ex.exp.CoPs.graph.size_mult = 2;
    ex.exp.CoPs.graph.radius = 30;
    ex.exp.CoPs.graph.full_as_background = true;
    
    ex.exp.CoPs.ctl.nsteps = 3;  % Test with fewer steps
    ex.exp.CoPs.ctl.target_num = 2;  % This should create 2 targets
    ex.exp.CoPs.ctl.circle_target_loc = true;  % Show target circles
    ex.exp.CoPs.ctl.reward_threshold = 10.0;
    
    % Initialize display
    try
        ex = initDisplayx(ex);
        fprintf('✓ Display initialized\n');
    catch err
        fprintf('✗ Failed to initialize display: %s\n', err.message);
        return;
    end
    
    % Generate target positions
    posT = struct();
    posT.x1 = simTargPos(ex.exp.CoPs.ctl.nsteps, ex.exp.CoPs.pos.initx1, ex.exp.CoPs.pos.dxmin1, ex.exp.CoPs.pos.dxmax1);
    posT.y1 = simTargPos(ex.exp.CoPs.ctl.nsteps, ex.exp.CoPs.pos.inity1, ex.exp.CoPs.pos.dymin1, ex.exp.CoPs.pos.dymax1);
    
    if ex.exp.CoPs.ctl.target_num == 2
        posT.x2 = simTargPos(ex.exp.CoPs.ctl.nsteps, ex.exp.CoPs.pos.initx2, ex.exp.CoPs.pos.dxmin2, ex.exp.CoPs.pos.dxmax2);
        posT.y2 = simTargPos(ex.exp.CoPs.ctl.nsteps, ex.exp.CoPs.pos.inity2, ex.exp.CoPs.pos.dymin2, ex.exp.CoPs.pos.dymax2);
    end
    
    fprintf('Target positions for step 1:\n');
    fprintf('  Target 1: [%d, %d]\n', posT.x1(1), posT.y1(1));
    if ex.exp.CoPs.ctl.target_num == 2
        fprintf('  Target 2: [%d, %d]\n', posT.x2(1), posT.y2(1));
    end
    
    % Create stimulus textures
    try
        [stimTextures, targPositions] = makeStimulusCoPsx(ex.setup, ex.exp.CoPs.ctl, ex.exp.CoPs.dirs, posT, ex.exp.CoPs.graph);
        fprintf('✓ Stimulus textures created\n');
        fprintf('  Number of textures: %d\n', length(stimTextures));
    catch err
        fprintf('✗ Failed to create stimulus: %s\n', err.message);
        return;
    end
    
    % Create output directory for saved images
    output_dir = '/home/nlab/Desktop/VSgui/debug_output';
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    
    % Save each texture as an image file
    fprintf('\nSaving texture images...\n');
    for i = 1:length(stimTextures)
        try
            % Get the texture image from screen
            [tex_image, tex_alpha] = Screen('GetImage', ex.setup.window, stimTextures(i));
            
            % Convert to uint8 for saving
            if size(tex_image, 3) == 4  % RGBA
                tex_image = tex_image(:, :, 1:3);  % Remove alpha
            end
            tex_image_uint8 = uint8(tex_image);
            
            % Save as image file
            filename = sprintf('%s/texture_step_%d.png', output_dir, i);
            imwrite(tex_image_uint8, filename);
            
            fprintf('  Step %d: saved as %s\n', i, filename);
            
            % Also save texture information
            info_filename = sprintf('%s/texture_step_%d_info.txt', output_dir, i);
            fid = fopen(info_filename, 'w');
            fprintf(fid, 'Texture Step %d Information\n', i);
            fprintf(fid, '============================\n');
            fprintf(fid, 'Texture size: %dx%d\n', size(tex_image, 1), size(tex_image, 2));
            fprintf(fid, 'Data type: %s\n', class(tex_image));
            fprintf(fid, 'Value range: [%.3f, %.3f]\n', min(tex_image(:)), max(tex_image(:)));
            
            if isfield(targPositions, i) && isfield(targPositions(i), 'targ1')
                fprintf(fid, 'Target 1 position: [%.1f, %.1f]\n', targPositions(i).targ1.pos_abs(1), targPositions(i).targ1.pos_abs(2));
            end
            if isfield(targPositions, i) && isfield(targPositions(i), 'targ2')
                fprintf(fid, 'Target 2 position: [%.1f, %.1f]\n', targPositions(i).targ2.pos_abs(1), targPositions(i).targ2.pos_abs(2));
            end
            
            fclose(fid);
            
        catch err
            fprintf('  ✗ Failed to save texture %d: %s\n', i, err.message);
        end
    end
    
    % Display each texture on screen for visual inspection
    fprintf('\nDisplaying textures for visual inspection...\n');
    fprintf('Press SPACE to continue to next texture, Q to quit\n');
    
    for i = 1:length(stimTextures)
        try
            % Clear screen
            Screen('FillRect', ex.setup.window, ex.idx.bg_lum);
            
            % Draw texture centered on screen
            Screen('DrawTexture', ex.setup.window, stimTextures(i));
            
            % Add text overlay
            Screen('DrawText', ex.setup.window, sprintf('Step %d/%d - Press SPACE', i, length(stimTextures)), 50, 50, ex.idx.white);
            
            % Draw target position markers if available
            if isfield(targPositions, i)
                if isfield(targPositions(i), 'targ1')
                    Screen('DrawDots', ex.setup.window, targPositions(i).targ1.pos_abs, 10, [255, 0, 0]);  % Red marker
                end
                if isfield(targPositions(i), 'targ2')
                    Screen('DrawDots', ex.setup.window, targPositions(i).targ2.pos_abs, 10, [0, 255, 0]);  % Green marker
                end
            end
            
            % Flip to show
            Screen('Flip', ex.setup.window);
            
            % Wait for key press
            key_pressed = false;
            while ~key_pressed
                [keyIsDown, secs, keyCode] = KbCheck;
                if keyIsDown
                    if strcmpi(KbName(keyCode), 'space')
                        key_pressed = true;
                    elseif strcmpi(KbName(keyCode), 'q')
                        fprintf('User quit - stopping texture display\n');
                        break;
                    end
                end
                WaitSecs(0.01);
            end
            
            if strcmpi(KbName(keyCode), 'q')
                break;
            end
            
        catch err
            fprintf('  ✗ Failed to display texture %d: %s\n', i, err.message);
        end
    end
    
    % Clean up
    try
        if ~isempty(stimTextures)
            Screen('Close', stimTextures);
        end
        Screen('Close', ex.setup.window);
        fprintf('✓ Cleaned up resources\n');
    catch err
        fprintf('✗ Cleanup error: %s\n', err.message);
    end
    
    fprintf('\n=== Test Complete ===\n');
    fprintf('Check the saved images in: %s\n', output_dir);
    fprintf('Look for:\n');
    fprintf('  - Are both targets visible in each texture?\n');
    fprintf('  - Are the target positions correct?\n');
    fprintf('  - Is there sufficient contrast?\n');
    fprintf('  - Are the targets overlapping too much?\n');
    
end
