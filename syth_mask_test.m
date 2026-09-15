%%trial test

% Make sure this is running on OpenGL Psychtoolbox:
clc;
clear all;
close all;
AssertOpenGL;

try
    %% settings
    %this path will change
   % cd 'C:\Users\zajkowskiwk\OneDrive - National Institutes of Health\cops_project\MATLAB\textureSynth\textureSynth-master'
    % task controlx:
    % set up from the gui
     precision_weight = .5 % weighting of closeness reward sensitivity, relative to reward landscape; by default reward and closeness contribute equally
    file_folder = 'test1_water_dep.jpg';%'test1_ants.jpg';%'test1_text.pgm';% determined once per session at the start (there will be more of these folder in the final version)
    circle_target_loc=0; % 1: shows a version where the target is illuminated
    full_as_background = 1; %s whether to have full stats image as background (1) or target (0)
   
   
    % graphical settings (also from GUI)
    size_mult=3; % image resize multiplier 
    xdim=192*size_mult; % image x dimension (in px)
    ydim=192*size_mult; 
    window_size =  [200, 500, xdim+200, ydim+500]; %left top right bottom; think that w(1)-w(3) is x length (left to right); w(2)-w(4) is y length (top:0 to bottom)
    window_background_color = [125,125,125]; % gray
   
    % trial settings
    target_num=2;
    nsteps = 10; % num of stim changes within trial (cannot be longer than the number of pregenerated images...)
    wait_secs=.5; 
    % movement speed in xy dir (in px)r
    dxmin = -10;
    dxmax =  10;
    dymin = -10;
    dymax =  10 ; 
    r=15;
    max_distance=r*3*size_mult; %maximum distance from center for which reward>0
    reward_mat = gauss_rew_land(xdim, [xdim/2, xdim/2], 150); % reward matrix

   %change location
   cd(file_folder);
    
    %window size and location
    wshape= []
    [w, w_size]  = Screen('OpenWindow', 0, window_background_color,window_size);
    
    %seed_im = pgmRead('nuts.pgm');
    % seed_im = load("full_noprior.mat")
    % seed_im = seed_im.full_generic;
    load('full_noprior.mat') % creates 'full_generic' variable; we load it here for knowing the dims
    % setup (center start)
    
    if target_num==2
        cx = size(full_generic,2)/2-50;
        cy = size(full_generic,1)/2; % !! y-axis is inverted: going down is up and vice versa
        cx2 = size(full_generic,2)/2+50;
        cy2 = size(full_generic,1)/2;
    else
        cx = size(full_generic,2)/2;
        cy = size(full_generic,1)/2;
    end
    

    %background texture
    full_list = dir("full/full*.mat");
    scramble_list = dir("scramble/scramble*.mat");
    full_texs = struct([]);
    targ_texs = struct([]);
    out_texs = struct([]); % overlaid textures
    out_texs_cell = {};
    for i=1:nsteps
        if i>1 % makes sure it starts at center
            dx = randi([dxmin, dxmax]);
            dy = randi([dymin, dymax]);
            cy = cy + dy;
            cx = cx + dx;
            
            if target_num==2
                dx2 = randi([dxmin, dxmax]);
                dy2 = randi([dymin, dymax]);
                cy2 = cy2 + dy2;
                cx2 = cx2 + dx2;
            end

        else
            dx = 0;
            dy=0;
        end

        fulli = load([  full_list(i).name]); % load full-stats image
        sci = load([ scramble_list(i).name]); % load scrambled image

        gaussian_mask = gauss_mask(fulli.full_tp, cx, cy, r); % gauss mask for target
        inv_mask = 1-gaussian_mask; % inverse mask for full image
        % second target
        if target_num==2
            gaussian_mask2 = gauss_mask(fulli.full_tp, cx2, cy2, r);
            inv_mask2 = 1-gaussian_mask2;
        end
        
        %target = mask_img(sci.scramble_tp, cx, cy, r);
        if full_as_background
            target = sci.scramble_tp.*gaussian_mask,size_mult;
            if target_num==2 
                target2 = sci.scramble_tp.*gaussian_mask2;
                background = fulli.full_tp.*inv_mask.*inv_mask2; % 2 holes
            else
                background = fulli.full_tp.*inv_mask; % for 1 target, background needs only 1 hole
            end
        else
            target = fulli.full_tp.*gaussian_mask;
            if target_num==2
                target2 = fulli.full_tp.*gaussian_mask2;
                background = sci.scramble_tp.*inv_mask.*inv_mask2;
            else
                background = sci.scramble_tp.*inv_mask;
            end
        end
        %overlay images
        if target_num==2
            comb_tex_raw=background+target+target2;
        else
            comb_tex_raw=background+target;
        end
        %standardize (between 0-255)
        comb_tex=(comb_tex_raw+abs(min(comb_tex_raw(:))));
        comb_tex=comb_tex/max(comb_tex(:))*255;
       
        %add circle
        if circle_target_loc
            if target_num==2
                comb_tex = circles_mat(comb_tex, cx, cy,cx2, cy2, r, 1, 1);
            else
                comb_tex = circle_mat(comb_tex, cx, cy, r, 1,1); % 
            end
        end
        
        %resize
        background_res = imresize(background, size_mult);
        target_res = imresize(target, size_mult);
        comb_tex_res = imresize(comb_tex, size_mult);

        if target_num==2
             target2_res = imresize(target2, size_mult);
             targ2_texs(i).tex =target2_res;
        end

        %save matrices
        full_texs(i).mat = background_res;
        targ_texs(i).mat =target_res;
        out_texs(i).mat=comb_tex_res;
        
        %test_texs(i).mat =circle_res;

        % save textures
        out_texs_cell{end+1}= Screen('MakeTexture', w, comb_tex_res);
        %out_texs(i).tex=Screen('MakeTexture', w, comb_tex_res);
            
        %save positions
        targ_texs(i).pos_abs = [window_size(1)+cx*size_mult, window_size(2)+cy*size_mult];
        if target_num==2
            targ2_texs(i).pos_abs = [window_size(1)+cx2*size_mult, window_size(2)+cy2*size_mult];
        end
    end % end i for-loop
    
    % --- Step 2: Convert the cell array to a numeric array ---
    % This step is the crucial fix for your error.
    all_tex_handles = cell2mat(out_texs_cell);
    
    % --- Step 3: Preload the numeric array of texture handles ---
    [resident, texidresident] = Screen('PreloadTextures', w, all_tex_handles);


   % texbox = Screen('Rect', all_tex_handles(1));
    Screen('DrawTexture', w  , all_tex_handles(1));%, texboxs
    Screen('Flip',w);   
    
    % Get the current mouse position and a timestamp
    mousePositions = [];
    closeness_vec = [];
    reward_vec = [];
    scaled_reward_vec = [];
    counter = 0; % calculates the amount of reward that was already 'rewarded' and resets the accumulated count
    %reward_rate_vec = [];
    %reward_accum_vec = [];
    
    KbWait; 
    for (tp=1:nsteps) 
        Screen('DrawTexture', w  , all_tex_handles(tp));%, texbox
        %Screen('Flip',w); 

        tic;
        while toc < wait_secs   
            [current_x, current_y] = GetMouse();
            timestamp = GetSecs();
        
            % Store the position and timestamp
            mousePositions = [mousePositions; current_x, current_y, timestamp];
            
            % calculating (momentary) reward
            closeness = calc_closeness([current_x, current_y], targ_texs(1).pos_abs, max_distance);
            if target_num==2
                closeness2 = calc_closeness([current_x, current_y], targ2_texs(1).pos_abs, max_distance);
                closeness = max(closeness, closeness2);
            end
            reward = reward_mat(uint16(current_x)-window_size(1), uint16(current_y)-window_size(2));
            scaled_reward = closeness * precision_weight + reward * (1-precision_weight);
            % save data
            closeness_vec(end+1)=closeness;
            reward_vec(end+1)=reward;
            scaled_reward_vec(end+1)=scaled_reward;
            
            %accumulated reward here...
            reward_accum = sum(scaled_reward_vec)-counter;
            %reward_rate(end+1) = reward_accum/length(scaled_reward);
            if reward_accum>20
                counter = counter + reward_accum;
                fprintf('\nReward!')
            end

            %error calc...
            if tp>2 % can't stop earlier than 2nd stim...
                distance_window = 1-closeness_vec(end-35:end); %relevant window
                if max(distance_window) > .95 | mean(distance_window) > .5;
                    sprintf('Bad!')
                    %abreak;
                end
            end


            % Display the position (optional)
            %fprintf('\nMouse at X: %d, Y: %.2f\n', current_x, current_y);
            %fprintf('\nprecision: %.2f', closeness);
            %fprintf('\nreward: %.2f', reward);
            % control frequency of updates
            WaitSecs(0.01);
        end % end while loop

        Screen('Flip',w); 
        %WaitSecs(wait_secs); % (.05  );          
    end % end tp for loop
    Screen('CloseAll');   
catch
    sca;
    psychrethrow(psychlasterror);
end
