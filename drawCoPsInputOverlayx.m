function drawCoPsInputOverlayx(window, positions, dotSize, colors)
% Draw available gaze points with a shared RGB color or one RGB row per point.
% Input rows are eye/pointer (monocular) or R/L/mean/pointer (binocular).
valid = all(isfinite(positions), 2);
if ~any(valid)
    return
end
if size(colors, 1) > 1
    if size(positions, 1) == 2 && size(colors, 1) == 4
        colors = colors([1 end], :); % monocular eye and pointer palette
    end
    colors = colors(valid, :);
end
Screen('DrawDots', window, positions(valid, :)', dotSize, colors');
end
