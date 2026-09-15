function closeness = calc_closeness(current_pos, target_pos, max_distance)
% Calculate closeness of current position to target position
% Returns a value between 0 (far) and 1 (at target)
%
% inputs:
% current_pos: [x, y] current position
% target_pos: [x, y] target position  
% max_distance: distance at which closeness becomes 0
%
% output:
% closeness: 0-1 value indicating how close to target

% Calculate Euclidean distance
distance = sqrt((current_pos(1) - target_pos(1))^2 + ...
               (current_pos(2) - target_pos(2))^2);

% Convert to closeness (0-1 scale)
if distance >= max_distance
    closeness = 0;
else
    closeness = 1 - (distance / max_distance);
end

% Ensure bounds
closeness = max(0, min(1, closeness));

end