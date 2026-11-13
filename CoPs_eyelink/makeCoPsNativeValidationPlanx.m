function plan = makeCoPsNativeValidationPlanx(ex)
% Select degree-defined grids with valid.passes (1, 2, or [1 2]).
ex = resolveCalibrationValidationDisplaySizes(ex);
val = ex.valid;
offsets = {val.offsetsDeg, val.offsetsDeg};
if isfield(val, 'offsetsDeg2') && ~isempty(val.offsetsDeg2)
    offsets{2} = val.offsetsDeg2;
end
windows = {val.targetWin, val.targetWin2};
passes = 1:2; % compatibility with settings saved before pass selection
if isfield(val, 'passes')
    passes = val.passes;
end
validateattributes(passes, {'numeric'}, ...
    {'vector','nonempty','integer','>=',1,'<=',2});
passes = unique(passes(:)', 'stable');
plan = struct('pass', {}, 'repeat', {}, 'targetOffsetPx', {}, ...
    'targetPx', {}, 'targetWinPx', {});
for pass = passes
    p = round(visualDegToPx(double(offsets{pass}(:)) * val.distance_scaling, ex.setup));
    [x, y] = meshgrid(p);
    positions = [x(:), y(:)];
    for repetition = 1:val.nRepeat
        order = randperm(size(positions, 1));
        for i = order
            target = ex.fix.PCtr + positions(i,:);
            rect = ex.setup.screenRect;
            if any(target < rect(1:2)) || any(target >= rect(3:4))
                error('CoPs:ValidationTargetOffscreen', ...
                    'Validation target [%g %g] lies outside the display.', target(1), target(2));
            end
            plan(end+1) = struct('pass', pass, 'repeat', repetition, ...
                'targetOffsetPx', positions(i,:), 'targetPx', target, ...
                'targetWinPx', windows{pass}); %#ok<AGROW>
        end
    end
end
end
