function updated = drawCoPsTrialOverlayx(setup, frame)
% Draw one trial preview, skipping all desktop graphics work between updates.
% Separate previews use native window pixels; frame geometry is in stimulus pixels.
persistent lastContext lastUpdate
updated = false;
if isfield(setup,'overlayBackend') && strcmp(setup.overlayBackend,'process')
    updated = coPsOverlayProcessx('send',setup,frame);
    return
end
separate = isfield(setup, 'overlayIsSeparate') && setup.overlayIsSeparate;
scale = [1 1];
origin = [0 0];
if separate
    window = setup.overlayWindow;
    context = [window setup.overlayOpenedAt];
    now = GetSecs;
    if isequal(context, lastContext) && now - lastUpdate < 1/setup.overlayDisplayRateHz
        return
    end
    scale = setup.overlayScale;
    origin = setup.screenRect(1:2);
elseif isempty(setup.overlay)
    window = setup.window;
else
    window = setup.overlay;
end
sizeScale = min(scale);

% Never clear the participant window when drawing a legacy inline overlay.
if separate || (frame.active && ~isempty(setup.overlay))
    Screen('FillRect', window, frame.backgroundColor);
end
if frame.active
    if frame.showFixation
        rect = (frame.fixationRect - [origin origin]) .* [scale scale];
        Screen('FrameRect', window, frame.foregroundColor, rect, ...
            max(1, frame.fixationPenWidth*sizeScale));
    end
    radius = frame.circleRadiusPx .* scale;
    for j = 1:size(frame.targetPositions, 1)
        point = (frame.targetPositions(j,:) - origin) .* scale;
        Screen('FrameOval', window, frame.circleColor, [point-radius point+radius], ...
            max(1, frame.circlePenWidth*sizeScale));
    end
    if frame.showCenter && ~isempty(setup.overlay)
        point = (frame.centerPx - origin) .* scale;
        halfSize = frame.centerHalfSizePx .* scale;
        pen = max(1, frame.centerPenWidth*sizeScale);
        Screen('DrawLine', window, frame.centerColor, ...
            point(1)-halfSize(1), point(2), point(1)+halfSize(1), point(2), pen);
        Screen('DrawLine', window, frame.centerColor, ...
            point(1), point(2)-halfSize(2), point(1), point(2)+halfSize(2), pen);
    end
    positions = (frame.gazePositions - origin) .* scale;
    drawCoPsInputOverlayx(window, positions, max(1, frame.gazeDotSize*sizeScale), frame.gazeColors);
end
if frame.showReward
    point = ([100 100] - origin) .* scale;
    Screen('DrawText', window, 'REWARD', point(1), point(2), frame.foregroundColor);
end
if separate
    % The desktop backbuffer is already the small preview canvas: no texture copy.
    Screen('Flip', window, 0, 0, 2);
    lastContext = context;
    % Schedule from completion so a slow update never triggers catch-up drawing.
    lastUpdate = GetSecs;
end
updated = true;
end
