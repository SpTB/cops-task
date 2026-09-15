function stepCap = computeStepCaptureMetrics(tRel, stepIdx, xPx, yPx, targetX, targetY, target2X, target2Y, inBounds, captureRadiusPx)
% Compute step-wise capture metrics for two-target CoPs tracking.
%
% Capture is defined as gaze entering a circular zone (captureRadiusPx)
% around either target during a stimulus step.


stepCap = struct();
stepCap.step = zeros(0,1);
stepCap.captured = false(0,1);
stepCap.timeToCaptureSec = NaN(0,1);
stepCap.capturedAtStepEnd = false(0,1);
stepCap.nSamplesPerStep = zeros(0,1);
stepCap.captureRadiusPx = captureRadiusPx;
stepCap.captureProb = NaN;
stepCap.medianTimeToCaptureSec = NaN;
stepCap.captureAtEndProb = NaN;
stepCap.nSteps = 0;

goodStep = isfinite(stepIdx);
uStep = unique(stepIdx(goodStep));
uStep = uStep(:);
nStep = numel(uStep);

captured = false(nStep,1);
timeToCaptureSec = NaN(nStep,1);
capturedAtStepEnd = false(nStep,1);
nSamplesPerStep = zeros(nStep,1);

for k = 1:nStep
    
    %select timepoints associated with current step k
    m = (stepIdx == k) & isfinite(tRel);
    if ~any(m)
        continue
    end

    % Sort within-step samples by time to make "step end" explicit.
    % filter by current step
    tS = tRel(m);
    xS = xPx(m);
    yS = yPx(m);
    t1x = targetX(m);
    t1y = targetY(m);
    t2x = target2X(m);
    t2y = target2Y(m);
    ib = inBounds(m);

    d1 = hypot(xS - t1x, yS - t1y); % euclidean dist (hypothenuse) 
    d2 = hypot(xS - t2x, yS - t2y);
    dMin = min(d1, d2);
    good = ib & isfinite(dMin);

    nSamplesPerStep(k) = nnz(good);
    if ~any(good)
        continue
    end

    dGood = dMin(good); %distance to target
    tGood = tS(good); % time (rel)
    t0 = min(tGood);

    ixCap = find(dGood <= captureRadiusPx, 1, 'first');
    if ~isempty(ixCap)
        captured(k) = true;
        timeToCaptureSec(k) = tGood(ixCap) - t0;
    end

    capturedAtStepEnd(k) = dGood(end) <= captureRadiusPx;
end

stepCap.step = uStep;
stepCap.captured = captured;
stepCap.timeToCaptureSec = timeToCaptureSec;
stepCap.capturedAtStepEnd = capturedAtStepEnd;
stepCap.nSamplesPerStep = nSamplesPerStep;
stepCap.nSteps = nStep;
stepCap.captureProb = mean(captured);
stepCap.captureAtEndProb = mean(capturedAtStepEnd);
if any(isfinite(timeToCaptureSec(captured)))
    stepCap.medianTimeToCaptureSec = median(timeToCaptureSec(timeToCaptureSec>0), 'omitnan');
end

end