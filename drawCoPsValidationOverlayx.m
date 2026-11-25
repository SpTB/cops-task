function drawCoPsValidationOverlayx(ex, target, eyes)
% Keep the validation preview independent of participant-display coordinates.
if ~isfield(ex.setup,'overlayIsSeparate') || ~ex.setup.overlayIsSeparate, return; end
if isfield(ex.setup,'overlayBackend') && strcmp(ex.setup.overlayBackend,'process')
    frame=struct('backgroundColor',ex.valid.background_color,'active',true, ...
        'validationTarget',target,'validationTargetSize',ex.calib.Psz, ...
        'foregroundColor',ex.idx.white,'gazePositions',eyes, ...
        'gazeDotSize',ex.setup.eyePSz,'gazeColors',[255 0 0]);
    if ex.valid.showMouseTrace
        [mx,my]=GetMouse(ex.setup.window);frame.pointerPositions=[mx my];
    end
    coPsOverlayProcessx('send',ex.setup,frame);
    return
end
Screen('FillRect', ex.setup.overlay, ex.valid.background_color);
Screen('DrawDots', ex.setup.overlay, target', ex.calib.Psz, ex.idx.white, [], 2);
eyes=eyes(all(isfinite(eyes),2),:);
if ~isempty(eyes)
    Screen('DrawDots', ex.setup.overlay, eyes', ex.setup.eyePSz, [255 0 0], [], 2);
end
if ex.valid.showMouseTrace
    [mx,my]=GetMouse(ex.setup.window);
    Screen('DrawDots', ex.setup.overlay, [mx;my], 3, [0 255 0], [], 2);
end
end
