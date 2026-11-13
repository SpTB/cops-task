function correction = fitCoPsNativeEyeCorrectionx(summary, centerPx)
% Legacy-style per-axis gain/offset refit, now mapping native pixels to pixels.
% Fit measured = slope * targetRelative + offset; invert for online use.
correction = struct('source','CoPsValidation','inputUnits','pixels', ...
    'enabled',false,'centerPx',centerPx, ...
    'offsetPx',repmat(centerPx,2,1),'gain',ones(2,2), ...
    'fitted',false(2,2),'nPoints',zeros(2,2));
if isempty(summary), return; end
targets = vertcat(summary.targetPx) - centerPx;
for eye = 1:2
    measured = arrayfun(@(s) s.gazePx(eye,:),summary,'UniformOutput',false);
    measured = vertcat(measured{:});
    for axis = 1:2
        keep = isfinite(targets(:,axis)) & isfinite(measured(:,axis));
        correction.nPoints(eye,axis) = nnz(keep);
        if numel(unique(targets(keep,axis))) < 3
            continue
        end
        p = polyfit(targets(keep,axis),measured(keep,axis),1);
        if all(isfinite(p)) && p(1) > 0
            correction.offsetPx(eye,axis) = p(2);
            correction.gain(eye,axis) = 1/p(1);
            correction.fitted(eye,axis) = true;
        end
    end
end
correction.enabled = any(correction.fitted,'all');
end
