function new_circles(window, targPositions, step_num, target_num, radius, circle_radius_mult, circle_color)
% Draw red circle OUTLINES around targets for PREGO state
line_width = 2;  % Outline width
circle_radius = radius * circle_radius_mult;
% Draw circle outline around target 1
if length(targPositions) >= step_num && isfield(targPositions(step_num), 'targ1')
    pos = targPositions(step_num).targ1.pos_abs;
    
    % Calculate rectangle bounds for circle
    rect = [pos(1) - circle_radius, pos(2) - circle_radius, ...
        pos(1) + circle_radius, pos(2) + circle_radius];
    
    % Draw circle outline using FrameRect
    Screen('FrameRect', window, circle_color, rect, line_width);
end

% Similar for target 2...
if length(targPositions) >= step_num && isfield(targPositions(step_num), 'targ2')
    pos = targPositions(step_num).targ2.pos_abs;
    
    % Calculate rectangle bounds for circle
    rect = [pos(1) - circle_radius, pos(2) - circle_radius, ...
        pos(1) + circle_radius, pos(2) + circle_radius];
    
    % Draw circle outline using FrameRect
    Screen('FrameRect', window, circle_color, rect, line_width);
end

%debugging..
test_rect = [pos(1)-5, pos(2)-5, pos(1)+5, pos(2)+5];
Screen('FrameRect', window, [0,1,0], test_rect, 1);  % Green test square
end
