function changed = refreshCoPsPreviewWindowx(setup)
% Keep a resized desktop preview fitted to its fixed logical task canvas.

changed = false;
if ~isfield(setup, 'guiWindow') || ~setup.guiWindow || ...
        ~isfield(setup, 'panelFitterOn') || ~setup.panelFitterOn
    return
end

[width, height] = Screen('WindowSize', setup.window, 1);
physicalSize = double([width height]);
% Some window managers report a zero-sized framebuffer while minimized.
if any(~isfinite(physicalSize)) || any(physicalSize <= 0)
    return
end
sourceRect = double(setup.screenRect(:)');
logicalSize = sourceRect(3:4) - sourceRect(1:2);
if any(~isfinite(logicalSize)) || any(logicalSize <= 0)
    return
end

scale = min(physicalSize ./ logicalSize);
drawnSize = max([1 1], min(physicalSize, round(logicalSize .* scale)));
offset = round((physicalSize - drawnSize) ./ 2);
destinationRect = [offset, offset + drawnSize];

previous = Screen('PanelFitter', setup.window);
updated = previous(:)';
if numel(updated) < 11
    updated(end+1:11) = 0;
end
% Retain any rotation and other PTB parameters after the source/destination.
updated(1:8) = [sourceRect, destinationRect];
if isequal(updated, previous(:)')
    return
end
Screen('PanelFitter', setup.window, updated);
changed = true;
end
