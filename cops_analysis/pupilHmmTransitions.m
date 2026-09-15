function out = pupilHmmTransitions(ex, opts)
% pupilHmmTransitions  Event-related pupil responses around HMM transitions.
%
% out = pupilHmmTransitions(ex)
% out = pupilHmmTransitions(ex, opts)
%
% Requires step-aligned HMM predictions attached by mergeCoPsHmmStruct.
% The default analysis uses ex.Trials(k).hmm.smoothed.hardCloser, coded as
% 0=non-tracking, 1=reward-closer target, 2=reward-farther target, and
% NaN=no estimate. Detailed event labels retain the tracked target, while
% the default plot pools acquisition and loss as nonTracking->tracking and
% tracking->nonTracking.
%
% Raw channel convention:
%   Eye.v(3,:) = right pupil; Eye.v(6,:) = left pupil.
%
% Important options (defaults):
%   .hmmMethod              'smoothed' ('filtered'/'predictive' also allowed)
%   .preSec                 1.5
%   .postSec                3.0
%   .baselineWindowSec      [-1.5 -1.0] ([] = no event baseline correction)
%   .anticipatoryWindowSec  [-0.5 0]
%   .earlyWindowSec         [0.2 1.0]
%   .lateWindowSec          [1.0 2.5]
%   .minStateDwellSec       0.10
%   .minEventSeparationSec  0.50
%   .blinkPaddingSec        0.10
%   .blinkWindowSec         [-0.5 2.0]
%   .blinkEvents            'include' ('exclude'/'blink-only')
%   .maxInterpGapSec        0.15
%   .smoothWindowSec        0.10
%   .excludeOutsideScreen   true
%   .screenPaddingPx        0
%   .minBaselineValidFrac   0.70
%   .minEpochValidFrac      0.60
%   .pairedOnly             false (state-pupil summaries only)
%   .posCorrected           true; automatically fit/apply EyeCal correction
%   .posCorrectionSource    'calibration' or 'experimental'
%   .correctionScope        'session' (default) or legacy 'day'
%   .posCorrectionModel     optional pre-fitted fitPupilPositionBias output
%   .posCorrectionAnimal    optional animal override used for auto-fit
%   .posCorrectionDate      optional date override used for auto-fit
%   .posCorrectionOpts      options forwarded to fitPupilPositionBias
%   .sacCor                 false; subtract EyeCal saccade pupil template
%   .sacCorrectionSource    'calibration' or 'experimental'
%   .corMethod             'subtraction' (default) or 'deconvolution'
%   .deconvBinSec           0.05; FIR temporal resolution
%   .deconvSaccadeWindowSec [-0.5 1.0]
%   .deconvBlinkWindowSec   [-0.5 2.0]
%   .deconvRewardWindowSec  [-1.5 3.0]
%   .deconvDriftOrder       3; polynomial session-time drift
%   .deconvRidge            1; FIR ridge penalty
%   .sacCorrectionTemplate  optional precomputed pupilEyeCalSaccades output
%   .sacCorrectionOpts      options forwarded to pupilEyeCalSaccades
%   .makePlot               true
%
% Pupil channels are robustly z-scored within session and eye before the
% binocular mean is formed. By default, event traces use subtractive baseline
% correction; set opts.baselineWindowSec=[] to retain normalized pupil size
% without event-wise baseline subtraction.
% The early baseline is deliberate: a baseline immediately before the switch
% could remove pupil dilation related to pre-saccadic motor preparation.

if nargin < 2 || isempty(opts)
    opts = struct();
end
defaults = struct( ...
    'hmmMethod', 'smoothed', ...
    'useEyeTime', true, ...
    'trialList', [], ...
    'preSec', 1.5, ...
    'postSec', 3.0, ...
    'baselineWindowSec', [-1.5 -1.0], ...
    'anticipatoryWindowSec', [-0.5 0], ...
    'earlyWindowSec', [0.2 1.0], ...
    'lateWindowSec', [1.0 2.5], ...
    'minStateDwellSec', 0.10, ...
    'minEventSeparationSec', 0.50, ...
    'blinkPaddingSec', 0.10, ...
    'blinkWindowSec', [-0.5 2.0], ...
    'blinkEvents', 'include', ...
    'maxInterpGapSec', 0.15, ...
    'smoothWindowSec', 0.10, ...
    'excludeOutsideScreen', true, ...
    'screenPaddingPx', 0, ...
    'outlierMad', 6, ...
    'minBaselineValidFrac', 0.70, ...
    'minEpochValidFrac', 0.60, ...
    'requireSm3', true, ...
    'pairedOnly', false, ...
    'correctionScope', 'session', ...
    'posCorrected', true, ...
    'posCorrectionSource', 'calibration', ...
    'posCorrectionModel', [], ...
    'posCorrectionAnimal', '', ...
    'posCorrectionDate', '', ...
    'posCorrectionOpts', struct(), ...
    'sacCor', false, ...
    'sacCorrectionSource', 'calibration', ...
    'sacCorrectionTemplate', [], ...
    'sacCorrectionOpts', struct(), ...
    'corMethod', 'subtraction', ...
    'deconvBinSec', 0.05, ...
    'deconvSaccadeWindowSec', [-0.5 1.0], ...
    'deconvBlinkWindowSec', [-0.5 2.0], ...
    'deconvRewardWindowSec', [-1.5 3.0], ...
    'deconvDriftOrder', 3, ...
    'deconvRidge', 1, ...
    'makePlot', true);
opts = localFillDefaults(opts, defaults);
opts.hmmMethod = validatestring( ...
    char(string(opts.hmmMethod)), {'smoothed','filtered','predictive'});
opts.blinkEvents = validatestring( ...
    char(string(opts.blinkEvents)), {'include','exclude','blink-only'});
opts.posCorrectionSource=validatestring(char(string(opts.posCorrectionSource)), ...
    {'calibration','experimental'});
opts.sacCorrectionSource=validatestring(char(string(opts.sacCorrectionSource)), ...
    {'calibration','experimental'});
opts.correctionScope=validatestring(char(string(opts.correctionScope)), ...
    {'session','day'});
opts.corMethod=validatestring(char(string(opts.corMethod)), ...
    {'subtraction','deconvolution'});
useSubtractionSacCorrection=opts.sacCor&&strcmp(opts.corMethod,'subtraction');
if ~(isscalar(opts.posCorrected) && ...
        (islogical(opts.posCorrected) || isnumeric(opts.posCorrected)) && ...
        isfinite(double(opts.posCorrected)) && ...
        ismember(double(opts.posCorrected),[0 1]))
    error('pupilHmmTransitions:BadPositionCorrectionOption', ...
        'opts.posCorrected must be logical or numeric 0/1.');
end
opts.posCorrected=logical(opts.posCorrected);
if ~(isscalar(opts.sacCor) && ...
        (islogical(opts.sacCor) || isnumeric(opts.sacCor)) && ...
        isfinite(double(opts.sacCor)) && ismember(double(opts.sacCor),[0 1]))
    error('pupilHmmTransitions:BadSaccadeCorrectionOption', ...
        'opts.sacCor must be logical or numeric 0/1.');
end
opts.sacCor=logical(opts.sacCor);
localValidateWindows(opts);

if ~isstruct(ex) || ~isfield(ex, 'Trials') || isempty(ex.Trials)
    error('pupilHmmTransitions:BadEx', 'ex must contain ex.Trials.');
end
hasSessionProvenance=isfield(ex.Trials,'sourceFilePath')&& ...
    any(strlength(string({ex.Trials.sourceFilePath}))>0);
sessionScoped=strcmp(opts.correctionScope,'session')&&hasSessionProvenance&& ...
    (opts.posCorrected||useSubtractionSacCorrection|| ...
    strcmp(opts.corMethod,'deconvolution'));
sessionCorrection=[];
if sessionScoped
    sessionOpts=opts;
    sessionOpts.sacCor=useSubtractionSacCorrection;
    [sessionOpts.animal,sessionOpts.date]=localPositionCorrectionIdentity(ex,opts);
    [ex,sessionCorrection]=applyPupilCorrectionsBySession(ex,sessionOpts);
end
correctionModel=[];
positionCorrection = struct('requested',logical(opts.posCorrected), ...
    'applied',false,'source',"none",'eyeCalPaths',strings(0,1), ...
    'nRightCorrected',0,'nLeftCorrected',0);
if sessionScoped&&opts.posCorrected
    positionCorrection.applied=true;
    positionCorrection.source=string(opts.posCorrectionSource)+ ...
        " correction fitted by calibration-defined session group";
    positionCorrection.sessionGroups=sessionCorrection.groups;
    positionCorrection.nRightCorrected=sum(sessionCorrection.groups.nPositionRight);
    positionCorrection.nLeftCorrected=sum(sessionCorrection.groups.nPositionLeft);
elseif logical(opts.posCorrected)
    if isfield(ex,'pupilPositionCorrection')
        positionCorrection.applied=true;
        positionCorrection.source="already present in ex";
        if isfield(ex.pupilPositionCorrection,'eyeCalPaths')
            positionCorrection.eyeCalPaths=string(ex.pupilPositionCorrection.eyeCalPaths);
        end
    else
        correctionModel=opts.posCorrectionModel;
        if isempty(correctionModel)
            [correctionAnimal,correctionDate]=localPositionCorrectionIdentity(ex,opts);
            fitOpts=opts.posCorrectionOpts;
            if ~isstruct(fitOpts)||~isscalar(fitOpts)
                error('pupilHmmTransitions:BadPositionCorrectionOptions', ...
                    'opts.posCorrectionOpts must be a scalar structure.');
            end
            fitOpts.makePlot=false;
            if strcmp(opts.posCorrectionSource,'experimental')
                correctionModel=fitPupilExperimentalPositionBias(ex,fitOpts);
                positionCorrection.source="automatically fitted experimental model";
            else
                correctionModel=fitPupilPositionBias( ...
                    correctionAnimal,correctionDate,fitOpts);
                positionCorrection.source="automatically fitted EyeCal model";
            end
        else
            positionCorrection.source="opts.posCorrectionModel";
        end
        [ex,correctionReport]=applyPupilPositionBias(ex,correctionModel);
        positionCorrection.applied=true;
        if isfield(correctionModel,'eyeCalPaths')
            positionCorrection.eyeCalPaths=string(correctionModel.eyeCalPaths);
        end
        positionCorrection.nRightCorrected=sum(correctionReport.nRightCorrected);
        positionCorrection.nLeftCorrected=sum(correctionReport.nLeftCorrected);
    end
end
saccadeCorrection=struct('requested',opts.sacCor,'applied',false, ...
    'source',"none",'nSaccades',0,'nRightCorrected',0,'nLeftCorrected',0);
if sessionScoped&&useSubtractionSacCorrection
    saccadeCorrection.applied=true;
    saccadeCorrection.source=string(opts.sacCorrectionSource)+ ...
        " correction fitted by calibration-defined session group";
    saccadeCorrection.sessionGroups=sessionCorrection.groups;
    saccadeCorrection.nSaccades=sum(sessionCorrection.groups.nSaccades);
    saccadeCorrection.nRightCorrected=sum(sessionCorrection.groups.nSaccadeRight);
    saccadeCorrection.nLeftCorrected=sum(sessionCorrection.groups.nSaccadeLeft);
elseif useSubtractionSacCorrection
    if isfield(ex,'pupilSaccadeCorrection')
        saccadeCorrection.applied=true;
        saccadeCorrection.source="already present in ex";
    else
        saccadeSource=opts.sacCorrectionTemplate;
        if isempty(saccadeSource)
            [correctionAnimal,correctionDate]=localPositionCorrectionIdentity(ex,opts);
            saccadeOpts=opts.sacCorrectionOpts;
            if ~isstruct(saccadeOpts)||~isscalar(saccadeOpts)
                error('pupilHmmTransitions:BadSaccadeCorrectionOptions', ...
                    'opts.sacCorrectionOpts must be a scalar structure.');
            end
            saccadeOpts.makePlot=false;
            if ~isempty(correctionModel) && strcmp(opts.sacCorrectionSource,'calibration')
                saccadeOpts.calibrationModel=correctionModel;
            end
            if strcmp(opts.sacCorrectionSource,'experimental')
                % ex has already received the requested position correction;
                % do not apply correctionModel a second time here.
                saccadeSource=fitPupilExperimentalSaccadeKernel(ex,saccadeOpts);
                saccadeCorrection.source="automatically fitted experimental saccade template";
            else
                saccadeSource=pupilEyeCalSaccades( ...
                    correctionAnimal,correctionDate,saccadeOpts);
                saccadeCorrection.source="automatically fitted EyeCal saccade template";
            end
        else
            saccadeCorrection.source="opts.sacCorrectionTemplate";
        end
        [ex,saccadeReport]=applyPupilSaccadeCorrection(ex,saccadeSource);
        saccadeCorrection.applied=true;
        saccadeCorrection.nSaccades=sum(saccadeReport.nSaccades);
        saccadeCorrection.nRightCorrected=sum(saccadeReport.nRightCorrected);
        saccadeCorrection.nLeftCorrected=sum(saccadeReport.nLeftCorrected);
    end
end
screenRect = localScreenRect(ex, opts.excludeOutsideScreen);
fs = inferFs(ex);
if ~isfinite(fs) || fs <= 0
    error('pupilHmmTransitions:BadSamplingRate', ...
        'Could not determine a positive eye sampling rate.');
end
dtSec = 1 / fs;
trialList = localTrialList(opts.trialList, numel(ex.Trials));
[pupilCenter, pupilScale] = localSessionPupilScale( ...
    ex, trialList, opts, screenRect);
timeSec = (-round(opts.preSec * fs):round(opts.postSec * fs)) ./ fs;

eventRows = repmat(localEmptyEventRow(), 0, 1);
combinedTraces = cell(0, 1);
leftTraces = cell(0, 1);
rightTraces = cell(0, 1);
combinedRawTraces = cell(0, 1);
stateTrialRows = repmat(localEmptyStateTrialRow(), 0, 1);
samplePupilRows = cell(0, 1);
deconvTrialRows = cell(0, 1);
nTrialsWithHmm = 0;
nCandidates = 0;
nRejectedSeparation = 0;
nRejectedPupil = 0;
nRejectedBlinkFilter = 0;
nOutsideScreenSamples = 0;

for trialNo = trialList(:)'
    T = ex.Trials(trialNo);
    if ~localHasHmmMethod(T, opts.hmmMethod)
        continue
    end
    methodHmm = T.hmm.(opts.hmmMethod);
    if opts.requireSm3 && ~localHasNonTrackingProbability(methodHmm)
        continue
    end
    nTrialsWithHmm = nTrialsWithHmm + 1;

    eyeOpts = struct();
    [xPx, yPx, tRel, ~, gazeValid] = reconstructEyePx( ...
        ex, T, opts.useEyeTime, eyeOpts);
    [~, ~, ~, ~, stepIdx] = mapTargetsByStep(ex, T, tRel);
    [leftRaw, rightRaw, leftValid, rightValid] = localRawPupil(T);
    n = min([numel(tRel), numel(stepIdx), numel(leftRaw), numel(rightRaw)]);
    if n < 2
        continue
    end
    xPx = xPx(1:n); yPx = yPx(1:n); tRel = tRel(1:n);
    gazeValid = gazeValid(1:n); stepIdx = stepIdx(1:n);
    leftRaw = leftRaw(1:n); rightRaw = rightRaw(1:n);
    leftValid = leftValid(1:n); rightValid = rightValid(1:n);
    bilateralBlink = localBilateralBlinkMask( ...
        leftRaw, rightRaw, leftValid, rightValid, pupilCenter, pupilScale, ...
        opts.outlierMad);
    insideScreen = localInsideScreen( ...
        xPx, yPx, gazeValid, screenRect, opts.screenPaddingPx);
    hardExclude = opts.excludeOutsideScreen & ~insideScreen;
    nOutsideScreenSamples = nOutsideScreenSamples + sum(hardExclude);
    gazeValid = gazeValid & insideScreen;

    left = localPreprocessPupil( ...
        leftRaw, leftValid, pupilCenter.left, pupilScale.left, fs, opts, ...
        hardExclude);
    right = localPreprocessPupil( ...
        rightRaw, rightValid, pupilCenter.right, pupilScale.right, fs, opts, ...
        hardExclude);
    combined = localNanMeanPair(left, right);
    leftRawProcessed = localRestoreRawUnits( ...
        left, pupilCenter.left, pupilScale.left);
    rightRawProcessed = localRestoreRawUnits( ...
        right, pupilCenter.right, pupilScale.right);
    combinedRawUnits = localNanMeanPair(leftRawProcessed, rightRawProcessed);

    sampleState = nan(n, 1);
    validStep = isfinite(stepIdx) & stepIdx == round(stepIdx) & ...
        stepIdx >= 1 & stepIdx <= numel(methodHmm.hardCloser);
    hardCloser = double(methodHmm.hardCloser(:));
    sampleState(validStep) = hardCloser(stepIdx(validStep));
    sampleState(~ismember(sampleState, [0 1 2])) = NaN;
    sampleTargetState = nan(n, 1);
    if isfield(methodHmm, 'hardTLeft') && ~isempty(methodHmm.hardTLeft)
        hardTarget = double(methodHmm.hardTLeft(:));
        validTargetStep = validStep & stepIdx <= numel(hardTarget);
        sampleTargetState(validTargetStep) = hardTarget(stepIdx(validTargetStep));
        sampleTargetState(~ismember(sampleTargetState, [0 1 2])) = NaN;
    end
    samplePupilRows{end+1, 1} = table( ... %#ok<AGROW>
        trialNo, {double(tRel(:))}, {double(combined(:))}, ...
        {double(combinedRawUnits(:))}, ...
        {double(xPx(:))}, {double(yPx(:))}, {double(stepIdx(:))}, ...
        {double(sampleTargetState(:))}, {double(sampleState(:))}, ...
        'VariableNames', {'trial','tRelSec','pupilZ','pupilRaw', ...
        'gazeXPx','gazeYPx','step','hardTarget','hardCloser'});
    stateTrialRows = localAccumulateStatePupil( ...
        stateTrialRows, combined, sampleState, trialNo, T, fs);
    [saccadeStarts, saccadeStops] = detectTrackingSaccadesCoPs( ...
        xPx, yPx, dtSec, ex.setup, []);
    blinkOnsets=find(bilateralBlink&~[false;bilateralBlink(1:end-1)]);
    rewardTimes=localRewardTimesRelative(T,tRel);
    sessionNo=localTrialScalar(T,{'sessionInDay'});
    if ~isfinite(sessionNo),sessionNo=1;end
    correctionGroup=sessionNo;
    if ~isempty(sessionCorrection)
        correctionGroup=localCorrectionGroup(sessionCorrection.groups,sessionNo);
    end
    deconvTrialRows{end+1,1}=struct('trial',trialNo,'session',sessionNo, ...
        'correctionGroup',correctionGroup, ...
        'timeSec',double(tRel(:)), ...
        'pupilZ',double(combined(:)),'saccadeTimes',double(tRel(saccadeStarts)), ...
        'blinkTimes',double(tRel(blinkOnsets)),'rewardTimes',double(rewardTimes(:))); %#ok<AGROW>
    candidates = localTransitionCandidates( ...
        sampleState, sampleTargetState, tRel, opts);
    nCandidates = nCandidates + numel(candidates);
    if isempty(candidates)
        continue
    end
    eventTimes = [candidates.timeSec];
    for c = 1:numel(candidates)
        previousInterval = inf;
        nextInterval = inf;
        if c > 1
            previousInterval = eventTimes(c) - eventTimes(c-1);
        end
        if c < numel(candidates)
            nextInterval = eventTimes(c+1) - eventTimes(c);
        end
        if strcmp(opts.corMethod,'subtraction')&& ...
                min(previousInterval, nextInterval) < opts.minEventSeparationSec
            nRejectedSeparation = nRejectedSeparation + 1;
            continue
        end
        eventTime = candidates(c).timeSec;
        blinkMask = tRel >= eventTime + opts.blinkWindowSec(1) & ...
            tRel <= eventTime + opts.blinkWindowSec(2);
        hasBlinkInWindow = any(bilateralBlink(blinkMask));
        if strcmp(opts.corMethod,'subtraction')&& ...
                ((strcmp(opts.blinkEvents,'exclude') && hasBlinkInWindow) || ...
                (strcmp(opts.blinkEvents,'blink-only') && ~hasBlinkInWindow) ...
                )
            nRejectedBlinkFilter = nRejectedBlinkFilter + 1;
            continue
        end
        queryTime = eventTime + timeSec;
        combinedRaw = interp1(tRel, combined, queryTime, 'linear', NaN);
        leftEpoch = interp1(tRel, left, queryTime, 'linear', NaN);
        rightEpoch = interp1(tRel, right, queryTime, 'linear', NaN);
        useBaseline = ~isempty(opts.baselineWindowSec);
        if useBaseline
            baselineMask = localWindowMask(timeSec, opts.baselineWindowSec);
            baselineCoverage = mean(isfinite(combinedRaw(baselineMask)));
        else
            baselineMask = false(size(timeSec));
            baselineCoverage = 1;
        end
        if strcmp(opts.corMethod,'subtraction')&& ...
                (baselineCoverage < opts.minBaselineValidFrac || ...
                mean(isfinite(combinedRaw)) < opts.minEpochValidFrac ...
                )
            nRejectedPupil = nRejectedPupil + 1;
            continue
        end
        if useBaseline
            combinedBaseline = mean(combinedRaw(baselineMask), 'omitnan');
            leftBaseline = mean(leftEpoch(baselineMask), 'omitnan');
            rightBaseline = mean(rightEpoch(baselineMask), 'omitnan');
            combinedEpoch = combinedRaw - combinedBaseline;
            leftEpoch = leftEpoch - leftBaseline;
            rightEpoch = rightEpoch - rightBaseline;
        else
            combinedBaseline = NaN;
            combinedEpoch = combinedRaw;
        end

        step = round(stepIdx(candidates(c).sample));
        [pCloser, pFarther, pNonTracking] = localStateProbabilities( ...
            methodHmm, step);
        [nearestSaccadeLatency, nearestSaccadeAmplitudeDeg] = ...
            localNearestSaccade( ...
                candidates(c).sample, tRel, xPx, yPx, ...
                saccadeStarts, saccadeStops, ex.setup);
        row = localEmptyEventRow();
        row.trial = trialNo;
        row.eventType = string(candidates(c).eventType);
        row.eventCategory = localEventCategory( ...
            candidates(c).sourceState, candidates(c).destinationState);
        row.eventTimeSec = eventTime;
        row.sourceState = candidates(c).sourceState;
        row.destinationState = candidates(c).destinationState;
        row.destinationTrackedTarget = candidates(c).destinationTrackedTarget;
        row.sourceDwellSec = candidates(c).sourceDwellSec;
        row.destinationDwellSec = candidates(c).destinationDwellSec;
        row.previousEventIntervalSec = previousInterval;
        row.nextEventIntervalSec = nextInterval;
        row.step = step;
        row.pCloser = pCloser;
        row.pFarther = pFarther;
        row.pNonTracking = pNonTracking;
        row.backgroundNoiseLvl = localTrialScalar(T, ...
            {'backgroundNoiseLvl','background','bg'});
        row.targetVisibility = localTrialScalar(T, ...
            {'targetVisibility','visibility','vis'});
        row.baselinePupilZ = combinedBaseline;
        row.anticipatoryPupilChangeZ = localWindowMean( ...
            combinedEpoch, timeSec, opts.anticipatoryWindowSec);
        row.earlyPupilChangeZ = localWindowMean( ...
            combinedEpoch, timeSec, opts.earlyWindowSec);
        row.latePupilChangeZ = localWindowMean( ...
            combinedEpoch, timeSec, opts.lateWindowSec);
        responseMask = localWindowMask(timeSec, [0.2 opts.lateWindowSec(2)]);
        row.peakPostPupilChangeZ = max( ...
            combinedEpoch(responseMask), [], 'omitnan');
        row.validEpochFrac = mean(isfinite(combinedRaw));
        row.nearestSaccadeLatencySec = nearestSaccadeLatency;
        row.nearestSaccadeAmplitudeDeg = nearestSaccadeAmplitudeDeg;
        row.gazeValidAtTransition = logical(gazeValid(candidates(c).sample));
        row.hasBlinkInWindow = hasBlinkInWindow;
        eventRows(end+1, 1) = row; %#ok<AGROW>
        combinedTraces{end+1, 1} = combinedEpoch; %#ok<AGROW>
        leftTraces{end+1, 1} = leftEpoch; %#ok<AGROW>
        rightTraces{end+1, 1} = rightEpoch; %#ok<AGROW>
        combinedRawTraces{end+1, 1} = combinedRaw; %#ok<AGROW>
    end
end

if isempty(eventRows)
    events = struct2table(localEmptyEventRow());
    events(1, :) = [];
    combined = nan(0, numel(timeSec));
    left = combined; right = combined; combinedRaw = combined;
else
    events = struct2table(eventRows);
    combined = vertcat(combinedTraces{:});
    left = vertcat(leftTraces{:});
    right = vertcat(rightTraces{:});
    combinedRaw = vertcat(combinedRawTraces{:});
end
summary = localSummarize(events);
deconvolution=[];
if strcmp(opts.corMethod,'deconvolution')&&~isempty(events)
    deconvolution=fitPupilTransitionDeconvolution( ...
        deconvTrialRows,events,timeSec,opts);
    combined=localKernelsForEvents(events,deconvolution,timeSec);
    left=nan(size(combined));right=nan(size(combined));
    combinedRaw=combined;
    summary=localSummarizeDeconvolution(events,deconvolution,opts);
    saccadeCorrection.source="joint FIR deconvolution nuisance regressor";
    saccadeCorrection.mode="deconvolution";
end
figureHandle = [];
if opts.makePlot
    figureHandle = localPlot(timeSec, events, combined, opts);
end

out = struct();
out.events = events;
out.timeSec = timeSec(:)';
out.traces = struct( ...
    'combined', combined, 'left', left, 'right', right, ...
    'combinedUncorrectedZ', combinedRaw);
out.summary = summary;
out.deconvolution = deconvolution;
out.statePupil = localStatePupilOutput(stateTrialRows, opts.pairedOnly);
if isempty(samplePupilRows)
    out.samplePupil = table(zeros(0,1), cell(0,1), cell(0,1), cell(0,1), ...
        cell(0,1), cell(0,1), cell(0,1), cell(0,1), cell(0,1), ...
        'VariableNames', {'trial','tRelSec','pupilZ','pupilRaw', ...
        'gazeXPx','gazeYPx','step','hardTarget','hardCloser'});
else
    out.samplePupil = vertcat(samplePupilRows{:});
end
out.figure = figureHandle;
out.opts = opts;
out.meta = struct( ...
    'samplingRateHz', fs, ...
    'hmmMethod', opts.hmmMethod, ...
    'pupilChannelRight', 3, ...
    'pupilChannelLeft', 6, ...
    'pupilCenter', pupilCenter, ...
    'pupilScale', pupilScale, ...
    'excludeOutsideScreen', opts.excludeOutsideScreen, ...
    'screenRectPx', screenRect, ...
    'screenPaddingPx', opts.screenPaddingPx, ...
    'nOutsideScreenSamplesExcluded', nOutsideScreenSamples, ...
    'nTrialsRequested', numel(trialList), ...
    'nTrialsWithHmm', nTrialsWithHmm, ...
    'nTransitionCandidates', nCandidates, ...
    'nRejectedEventSeparation', nRejectedSeparation, ...
    'nRejectedPupilCoverage', nRejectedPupil, ...
    'nRejectedBlinkFilter', nRejectedBlinkFilter, ...
    'blinkEvents', string(opts.blinkEvents), ...
    'blinkWindowSec', double(opts.blinkWindowSec), ...
    'positionCorrection', positionCorrection, ...
    'saccadeCorrection', saccadeCorrection, ...
    'corMethod', string(opts.corMethod), ...
    'nEventsRetained', height(events));
end


function [animal,dateLabel]=localPositionCorrectionIdentity(ex,opts)
animal=char(string(opts.posCorrectionAnimal));
dateLabel=char(string(opts.posCorrectionDate));
texts=strings(0,1);
for name={'dirName','fileName'}
    if isfield(ex,name{1})
        value=string(ex.(name{1}));texts=[texts;value(:)]; %#ok<AGROW>
    end
end
if isfield(ex,'Header')&&isstruct(ex.Header)
    for name={'onlineDirName','onlineFileName','edfFileName'}
        if isfield(ex.Header,name{1})
            value=string(ex.Header.(name{1}));texts=[texts;value(:)]; %#ok<AGROW>
        end
    end
end
joined=lower(strjoin(texts," "));
if isempty(animal)
    if contains(joined,'kaki')||~isempty(regexp(joined,'(^|[^a-z])ka[_\-.]','once'))
        animal='kaki';
    elseif contains(joined,'lychee')||~isempty(regexp(joined,'(^|[^a-z])ly[_\-.]','once'))
        animal='lychee';
    else
        error('pupilHmmTransitions:CannotInferCorrectionAnimal', ...
            'Set opts.posCorrectionAnimal to ka/kaki or ly/lychee.');
    end
end
if isempty(dateLabel)
    token=regexp(joined,'(20\d{2})[._-](\d{2})[._-](\d{2})','tokens','once');
    if isempty(token)
        error('pupilHmmTransitions:CannotInferCorrectionDate', ...
            'Set opts.posCorrectionDate, e.g. ''2026.07.19'' or ''Jul19''.');
    end
    dateLabel=sprintf('%s.%s.%s',token{1},token{2},token{3});
end
end


function trialRows = localAccumulateStatePupil( ...
        trialRows, pupil, state, trialNo, T, fs)
names = ["nonTracking", "tracking", "closer", "farther"];
codes = {0, [1 2], 1, 2};
for i = 1:numel(names)
    selected = isfinite(pupil) & ismember(state, codes{i});
    if ~any(selected)
        continue
    end
    localValues = double(pupil(selected));
    row = localEmptyStateTrialRow();
    row.trial = trialNo;
    row.state = names(i);
    row.meanPupilZ = mean(localValues, 'omitnan');
    row.sdPupilZ = std(localValues, 0, 'omitnan');
    row.nSamples = numel(localValues);
    row.durationSec = numel(localValues) / fs;
    row.backgroundNoiseLvl = localTrialScalar(T, ...
        {'backgroundNoiseLvl','background','bg'});
    row.targetVisibility = localTrialScalar(T, ...
        {'targetVisibility','visibility','vis'});
    trialRows(end+1, 1) = row; %#ok<AGROW>
end
end


function output = localStatePupilOutput(trialRows, pairedOnly)
names = ["nonTracking", "tracking", "closer", "farther"];
if isempty(trialRows)
    trialMeans = struct2table(localEmptyStateTrialRow());
    trialMeans(1, :) = [];
else
    trialMeans = struct2table(trialRows);
end
pairedTrials = zeros(0, 1);
if ~isempty(trialMeans)
    trackingTrials = trialMeans.trial(trialMeans.state == "tracking");
    nonTrackingTrials = trialMeans.trial(trialMeans.state == "nonTracking");
    pairedTrials = intersect(trackingTrials, nonTrackingTrials);
    if logical(pairedOnly)
        trialMeans = trialMeans(ismember(trialMeans.trial, pairedTrials), :);
    end
end
rows = repmat(struct( ...
    'state', "", 'nSamples', 0, 'nTrials', 0, ...
    'sampleWeightedMeanPupilZ', NaN, 'sampleWeightedSdPupilZ', NaN, ...
    'trialWeightedMeanPupilZ', NaN, 'trialWeightedSdPupilZ', NaN), ...
    numel(names), 1);
for i = 1:numel(names)
    selected = ~isempty(trialMeans) & trialMeans.state == names(i);
    rows(i).state = names(i);
    rows(i).nSamples = sum(trialMeans.nSamples(selected));
    rows(i).nTrials = sum(selected);
    if any(selected)
        [rows(i).sampleWeightedMeanPupilZ, ...
            rows(i).sampleWeightedSdPupilZ] = localPooledSampleMoments( ...
            trialMeans.meanPupilZ(selected), ...
            trialMeans.sdPupilZ(selected), trialMeans.nSamples(selected));
        rows(i).trialWeightedMeanPupilZ = mean( ...
            trialMeans.meanPupilZ(selected), 'omitnan');
        rows(i).trialWeightedSdPupilZ = std( ...
            trialMeans.meanPupilZ(selected), 0, 'omitnan');
    end
end
summary = struct2table(rows);

comparison = table(NaN, NaN, NaN, 0, NaN, NaN, NaN, NaN, NaN, false, ...
    'VariableNames', {'sampleWeightedTrackingMinusNonTrackingZ', ...
    'trialWeightedTrackingMinusNonTrackingZ', ...
    'pairedTrialTrackingMinusNonTrackingZ', 'nPairedTrials', ...
    'pairedTStatistic', 'pairedTDegreesFreedom', 'pairedTPValue', ...
    'pairedTCILower', 'pairedTCIUpper', 'pairedTReject05'});
nontracking = summary.state == "nonTracking";
tracking = summary.state == "tracking";
comparison.sampleWeightedTrackingMinusNonTrackingZ = ...
    summary.sampleWeightedMeanPupilZ(tracking) - ...
    summary.sampleWeightedMeanPupilZ(nontracking);
comparison.trialWeightedTrackingMinusNonTrackingZ = ...
    summary.trialWeightedMeanPupilZ(tracking) - ...
    summary.trialWeightedMeanPupilZ(nontracking);
if ~isempty(trialMeans)
    wide = unstack(trialMeans(:, {'trial','state','meanPupilZ'}), ...
        'meanPupilZ', 'state');
    if all(ismember({'tracking','nonTracking'}, wide.Properties.VariableNames))
        valid = isfinite(wide.tracking) & isfinite(wide.nonTracking);
        trackingValues = wide.tracking(valid);
        nonTrackingValues = wide.nonTracking(valid);
        paired = trackingValues - nonTrackingValues;
        comparison.pairedTrialTrackingMinusNonTrackingZ = ...
            mean(paired, 'omitnan');
        comparison.nPairedTrials = numel(paired);
        if numel(paired) >= 2
            [tStatistic, degreesFreedom, pValue, confidenceInterval] = ...
                localPairedTTest(trackingValues, nonTrackingValues);
            comparison.pairedTStatistic = tStatistic;
            comparison.pairedTDegreesFreedom = degreesFreedom;
            comparison.pairedTPValue = pValue;
            comparison.pairedTCILower = confidenceInterval(1);
            comparison.pairedTCIUpper = confidenceInterval(2);
            comparison.pairedTReject05 = isfinite(pValue) && pValue < 0.05;
        end
    end
end
output = struct('summary', summary, 'trialMeans', trialMeans, ...
    'comparison', comparison, 'pairedOnly', logical(pairedOnly), ...
    'pairedTrials', pairedTrials(:));
end


function [average, standardDeviation] = localPooledSampleMoments( ...
        groupMeans, groupSds, groupCounts)
groupMeans = double(groupMeans(:));
groupSds = double(groupSds(:));
groupCounts = double(groupCounts(:));
valid = isfinite(groupMeans) & isfinite(groupCounts) & groupCounts > 0;
groupMeans = groupMeans(valid); groupSds = groupSds(valid);
groupCounts = groupCounts(valid);
total = sum(groupCounts);
if total == 0
    average = NaN; standardDeviation = NaN; return
end
average = sum(groupCounts .* groupMeans) / total;
if total < 2
    standardDeviation = NaN; return
end
groupSds(~isfinite(groupSds)) = 0;
sumSquares = sum((groupCounts - 1) .* groupSds.^2 + ...
    groupCounts .* (groupMeans - average).^2);
standardDeviation = sqrt(max(0, sumSquares / (total - 1)));
end


function [tStatistic, degreesFreedom, pValue, confidenceInterval] = ...
        localPairedTTest(first, second)
% Two-sided paired Student t-test implemented without Statistics Toolbox.
difference = double(first(:) - second(:));
difference = difference(isfinite(difference));
n = numel(difference);
degreesFreedom = n - 1;
average = mean(difference);
standardError = std(difference, 0) / sqrt(n);
if n < 2
    tStatistic = NaN; pValue = NaN;
    confidenceInterval = [NaN NaN];
    return
elseif standardError == 0
    if average == 0
        tStatistic = 0; pValue = 1;
    else
        tStatistic = sign(average) * Inf; pValue = 0;
    end
    confidenceInterval = [average average];
    return
end
tStatistic = average / standardError;
% For Student's t, the two-sided tail probability is expressed directly
% through the regularized incomplete beta function.
x = degreesFreedom / (degreesFreedom + tStatistic^2);
pValue = betainc(x, degreesFreedom / 2, 0.5);
xCritical = betaincinv(0.05, degreesFreedom / 2, 0.5);
tCritical = sqrt(degreesFreedom * (1 - xCritical) / xCritical);
confidenceInterval = average + [-1 1] * tCritical * standardError;
end


function opts = localFillDefaults(opts, defaults)
names = fieldnames(defaults);
for i = 1:numel(names)
    allowEmpty = strcmp(names{i}, 'baselineWindowSec');
    if ~isfield(opts, names{i}) || ...
            (isempty(opts.(names{i})) && ~allowEmpty)
        opts.(names{i}) = defaults.(names{i});
    end
end
end


function localValidateWindows(opts)
if opts.preSec <= 0 || opts.postSec <= 0
    error('pupilHmmTransitions:BadEpoch', 'preSec and postSec must be positive.');
end
if ~(isscalar(opts.excludeOutsideScreen) && ...
        (islogical(opts.excludeOutsideScreen) || isnumeric(opts.excludeOutsideScreen)) && ...
        isfinite(double(opts.excludeOutsideScreen)) && ...
        ismember(double(opts.excludeOutsideScreen), [0 1]))
    error('pupilHmmTransitions:BadScreenOption', ...
        'excludeOutsideScreen must be logical or 0/1.');
end
if ~(isscalar(opts.screenPaddingPx) && isnumeric(opts.screenPaddingPx) && ...
        isfinite(opts.screenPaddingPx) && opts.screenPaddingPx >= 0)
    error('pupilHmmTransitions:BadScreenPadding', ...
        'screenPaddingPx must be a finite nonnegative scalar.');
end
for name = {'baselineWindowSec','anticipatoryWindowSec', ...
        'earlyWindowSec','lateWindowSec','blinkWindowSec'}
    value = opts.(name{1});
    if strcmp(name{1}, 'baselineWindowSec') && isempty(value)
        continue
    end
    if numel(value) ~= 2 || value(2) <= value(1) || ...
            value(1) < -opts.preSec || value(2) > opts.postSec
        error('pupilHmmTransitions:BadWindow', ...
            '%s must be an increasing pair inside the event epoch.', name{1});
    end
end
if ~(isscalar(opts.deconvBinSec)&&isfinite(opts.deconvBinSec)&&opts.deconvBinSec>0)
    error('pupilHmmTransitions:BadDeconvolutionBin', ...
        'deconvBinSec must be a positive finite scalar.');
end
for name={'deconvSaccadeWindowSec','deconvBlinkWindowSec', ...
        'deconvRewardWindowSec'}
    value=opts.(name{1});
    if numel(value)~=2||any(~isfinite(value))||value(2)<=value(1)
        error('pupilHmmTransitions:BadDeconvolutionWindow', ...
            '%s must be a finite increasing pair.',name{1});
    end
end
if ~(isscalar(opts.deconvDriftOrder)&&isfinite(opts.deconvDriftOrder)&& ...
        opts.deconvDriftOrder>=0&&opts.deconvDriftOrder==round(opts.deconvDriftOrder))
    error('pupilHmmTransitions:BadDeconvolutionDrift', ...
        'deconvDriftOrder must be a nonnegative integer.');
end
if ~(isscalar(opts.deconvRidge)&&isfinite(opts.deconvRidge)&&opts.deconvRidge>=0)
    error('pupilHmmTransitions:BadDeconvolutionRidge', ...
        'deconvRidge must be a finite nonnegative scalar.');
end
end


function blink = localBilateralBlinkMask( ...
        leftRaw, rightRaw, leftValid, rightValid, center, scale, outlierMad)
leftInvalid = ~logical(leftValid(:)) | ~isfinite(leftRaw(:));
rightInvalid = ~logical(rightValid(:)) | ~isfinite(rightRaw(:));
if isfinite(center.left) && isfinite(scale.left) && scale.left > 0
    leftInvalid = leftInvalid | ...
        abs(double(leftRaw(:))-center.left) > outlierMad*scale.left;
end
if isfinite(center.right) && isfinite(scale.right) && scale.right > 0
    rightInvalid = rightInvalid | ...
        abs(double(rightRaw(:))-center.right) > outlierMad*scale.right;
end
blink = leftInvalid & rightInvalid;
end


function trials = localTrialList(requested, nTrials)
if isempty(requested)
    trials = 1:nTrials;
else
    trials = unique(double(requested(:)'));
    if any(~isfinite(trials) | trials ~= round(trials) | ...
            trials < 1 | trials > nTrials)
        error('pupilHmmTransitions:BadTrialList', ...
            'trialList must contain valid integer trial numbers.');
    end
end
end


function tf = localHasHmmMethod(T, method)
tf = isfield(T, 'hmm') && isstruct(T.hmm) && ...
    isfield(T.hmm, method) && isstruct(T.hmm.(method)) && ...
    isfield(T.hmm.(method), 'hardCloser') && ...
    ~isempty(T.hmm.(method).hardCloser);
end


function tf = localHasNonTrackingProbability(methodHmm)
tf = isfield(methodHmm, 'pNonTracking') && ...
    any(isfinite(double(methodHmm.pNonTracking(:))));
end


function [center, scale] = localSessionPupilScale( ...
        ex, trialList, opts, screenRect)
leftAll = zeros(0, 1); rightAll = zeros(0, 1);
for trialNo = trialList(:)'
    T = ex.Trials(trialNo);
    [left, right, leftValid, rightValid] = localRawPupil(T);
    if opts.excludeOutsideScreen
        [xPx, yPx, ~, ~, gazeValid] = reconstructEyePx( ...
            ex, T, opts.useEyeTime, opts);
        n = min([numel(left), numel(right), numel(xPx), numel(yPx)]);
        left = left(1:n); right = right(1:n);
        leftValid = leftValid(1:n); rightValid = rightValid(1:n);
        insideScreen = localInsideScreen(xPx(1:n), yPx(1:n), ...
            gazeValid(1:n), screenRect, opts.screenPaddingPx);
        leftValid = leftValid & insideScreen;
        rightValid = rightValid & insideScreen;
    end
    leftAll = [leftAll; left(leftValid)]; %#ok<AGROW>
    rightAll = [rightAll; right(rightValid)]; %#ok<AGROW>
end
[center.left, scale.left] = localRobustLocationScale(leftAll, opts.outlierMad);
[center.right, scale.right] = localRobustLocationScale(rightAll, opts.outlierMad);
end


function [center, scale] = localRobustLocationScale(values, outlierMad)
values = double(values(:));
% Datapixx pupil channels are analog voltages and may legitimately be
% negative; invalidity is determined from nonfinite samples, gaze loss, and
% robust pupil outliers rather than the sign of the raw value.
values = values(isfinite(values));
if isempty(values)
    center = NaN; scale = NaN; return
end
center = median(values);
scale = 1.4826 * median(abs(values - center));
if ~isfinite(scale) || scale <= 0
    scale = std(values, 'omitnan');
end
if ~isfinite(scale) || scale <= 0
    scale = 1;
end
keep = abs(values - center) <= outlierMad * scale;
if any(keep)
    center = median(values(keep));
    scale2 = 1.4826 * median(abs(values(keep) - center));
    if isfinite(scale2) && scale2 > 0
        scale = scale2;
    end
end
end


function [left, right, leftValid, rightValid] = localRawPupil(T)
left = zeros(0, 1); right = zeros(0, 1);
leftValid = false(0, 1); rightValid = false(0, 1);
if ~isfield(T, 'Eye') || ~isfield(T.Eye, 'v') || isempty(T.Eye.v)
    return
end
V = double(T.Eye.v);
n = size(V, 2);
if isfield(T.Eye, 'n') && isfinite(T.Eye.n) && ...
        T.Eye.n > 0 && T.Eye.n <= n
    n = double(T.Eye.n);
end
V = V(:, 1:n);
right = nan(n, 1); left = nan(n, 1);
rightValid = false(n, 1); leftValid = false(n, 1);
if size(V, 1) >= 3
    right = V(3, :)';
    rightValid = isfinite(right);
    if size(V, 1) >= 2
        rightValid = rightValid & isfinite(V(1, :)') & isfinite(V(2, :)');
    end
end
if size(V, 1) >= 6
    left = V(6, :)';
    leftValid = isfinite(left) & ...
        isfinite(V(4, :)') & isfinite(V(5, :)');
end
end


function pupil = localPreprocessPupil( ...
        raw, valid, center, scale, fs, opts, hardExclude)
raw = double(raw(:)); valid = logical(valid(:));
if nargin < 7 || isempty(hardExclude)
    hardExclude = false(size(raw));
else
    hardExclude = logical(hardExclude(:));
end
if numel(hardExclude) ~= numel(raw)
    error('pupilHmmTransitions:ScreenMaskSize', ...
        'The screen mask must match the pupil trace length.');
end
valid = valid & isfinite(raw);
if isfinite(center) && isfinite(scale) && scale > 0
    valid = valid & abs(raw - center) <= opts.outlierMad * scale;
else
    valid(:) = false;
end
padding = max(0, round(opts.blinkPaddingSec * fs));
if padding > 0
    invalidExpanded = conv(double(~valid), ones(2*padding+1, 1), 'same') > 0;
    valid(invalidExpanded) = false;
end
pupil = nan(size(raw));
pupil(valid) = (raw(valid) - center) ./ scale;
pupil = localInterpolateShortGaps(pupil, round(opts.maxInterpGapSec * fs));
pupil(hardExclude) = NaN;
pupil = localNanMovingAverage(pupil, max(1, round(opts.smoothWindowSec * fs)));
pupil(hardExclude) = NaN;
end


function raw = localRestoreRawUnits(pupilZ, center, scale)
raw = nan(size(pupilZ));
if isfinite(center) && isfinite(scale) && scale > 0
    valid = isfinite(pupilZ);
    raw(valid) = pupilZ(valid) .* scale + center;
end
end


function rect = localScreenRect(ex, required)
rect = [];
if isfield(ex, 'setup') && isfield(ex.setup, 'screenRect') && ...
        numel(ex.setup.screenRect) >= 4
    candidate = double(ex.setup.screenRect(1:4));
    if all(isfinite(candidate)) && candidate(3) > candidate(1) && ...
            candidate(4) > candidate(2)
        rect = candidate;
    end
end
if logical(required) && isempty(rect)
    error('pupilHmmTransitions:MissingScreenRect', ...
        ['opts.excludeOutsideScreen=true requires a valid ' ...
         'ex.setup.screenRect. Set the option false only for legacy data.']);
end
end


function inside = localInsideScreen(xPx, yPx, gazeValid, rect, paddingPx)
xPx = double(xPx(:)); yPx = double(yPx(:));
gazeValid = logical(gazeValid(:));
if isempty(rect)
    inside = gazeValid & isfinite(xPx) & isfinite(yPx);
    return
end
inside = gazeValid & isfinite(xPx) & isfinite(yPx) & ...
    xPx >= rect(1) - paddingPx & xPx <= rect(3) + paddingPx & ...
    yPx >= rect(2) - paddingPx & yPx <= rect(4) + paddingPx;
end


function values = localInterpolateShortGaps(values, maxGap)
if maxGap < 1 || numel(values) < 3
    return
end
missing = ~isfinite(values);
edges = diff([false; missing; false]);
starts = find(edges == 1); stops = find(edges == -1) - 1;
for i = 1:numel(starts)
    a = starts(i); b = stops(i);
    if b-a+1 <= maxGap && a > 1 && b < numel(values) && ...
            isfinite(values(a-1)) && isfinite(values(b+1))
        values(a:b) = interp1([a-1 b+1], ...
            [values(a-1) values(b+1)], a:b, 'linear');
    end
end
end


function output = localNanMovingAverage(values, window)
window = max(1, round(window));
kernel = ones(window, 1);
valid = isfinite(values);
filled = values; filled(~valid) = 0;
denominator = conv(double(valid), kernel, 'same');
output = conv(filled, kernel, 'same') ./ denominator;
output(denominator == 0) = NaN;
end


function output = localNanMeanPair(first, second)
validFirst = isfinite(first); validSecond = isfinite(second);
count = double(validFirst) + double(validSecond);
first(~validFirst) = 0; second(~validSecond) = 0;
output = (first + second) ./ count;
output(count == 0) = NaN;
end


function candidates = localTransitionCandidates(state, targetState, time, opts)
candidates = repmat(struct( ...
    'sample', NaN, 'timeSec', NaN, 'sourceState', NaN, ...
    'destinationState', NaN, 'destinationTrackedTarget', NaN, ...
    'sourceDwellSec', NaN, 'destinationDwellSec', NaN, ...
    'eventType', ""), 0, 1);
defined = isfinite(state);
boundary = [true; ~defined(2:end) | ~defined(1:end-1) | ...
    state(2:end) ~= state(1:end-1)];
runStarts = find(boundary & defined);
if isempty(runStarts)
    return
end
runStops = [runStarts(2:end)-1; numel(state)];
% A run must stop before an intervening undefined interval.
for r = 1:numel(runStarts)
    firstUndefined = find(~defined(runStarts(r):runStops(r)), 1, 'first');
    if ~isempty(firstUndefined)
        runStops(r) = runStarts(r) + firstUndefined - 2;
    end
end
for r = 2:numel(runStarts)
    if runStarts(r) ~= runStops(r-1) + 1
        continue
    end
    source = state(runStarts(r-1)); destination = state(runStarts(r));
    eventType = localEventType(source, destination);
    if strlength(eventType) == 0
        continue
    end
    sourceTarget = targetState(runStops(r-1));
    destinationTarget = targetState(runStarts(r));
    isCloserFartherTransition = ismember(source, [1 2]) && ...
        ismember(destination, [1 2]);
    % A change in reward-relative rank is a target-switch event only when
    % the inferred physical target identity changes at the same boundary.
    % This rejects apparent closer/farther transitions caused solely by the
    % moving targets exchanging their distance rank relative to reward.
    if isCloserFartherTransition && ...
            (~ismember(sourceTarget, [1 2]) || ...
             ~ismember(destinationTarget, [1 2]) || ...
             sourceTarget == destinationTarget)
        continue
    end
    sourceDwell = localRunDuration(time, runStarts(r-1), runStops(r-1));
    destinationDwell = localRunDuration(time, runStarts(r), runStops(r));
    if sourceDwell < opts.minStateDwellSec || ...
            destinationDwell < opts.minStateDwellSec
        continue
    end
    destinationTrackedTarget = destinationTarget;
    if destination == 0 || ~ismember(destinationTarget, [1 2])
        destinationTrackedTarget = NaN;
    end
    candidates(end+1, 1) = struct( ... %#ok<AGROW>
        'sample', runStarts(r), 'timeSec', time(runStarts(r)), ...
        'sourceState', source, 'destinationState', destination, ...
        'destinationTrackedTarget', destinationTrackedTarget, ...
        'sourceDwellSec', sourceDwell, ...
        'destinationDwellSec', destinationDwell, ...
        'eventType', eventType);
end
end


function duration = localRunDuration(time, first, last)
if last < first || ~isfinite(time(first)) || ~isfinite(time(last))
    duration = 0; return
end
localDt = median(diff(time(max(1, first-2):min(numel(time), last+2))), 'omitnan');
if ~isfinite(localDt) || localDt < 0
    localDt = 0;
end
duration = max(0, time(last) - time(first) + localDt);
end


function name = localEventType(source, destination)
name = "";
if source == 1 && destination == 2
    name = "closer_to_farther";
elseif source == 2 && destination == 1
    name = "farther_to_closer";
elseif source == 0 && destination == 1
    name = "nonTracking_to_closer";
elseif source == 0 && destination == 2
    name = "nonTracking_to_farther";
elseif source == 1 && destination == 0
    name = "closer_to_nonTracking";
elseif source == 2 && destination == 0
    name = "farther_to_nonTracking";
end
end


function category = localEventCategory(source, destination)
if source == 0 && ismember(destination, [1 2])
    category = "nonTracking_to_tracking";
elseif ismember(source, [1 2]) && destination == 0
    category = "tracking_to_nonTracking";
else
    category = localEventType(source, destination);
end
end


function [pCloser, pFarther, pNonTracking] = localStateProbabilities(method, step)
pCloser = NaN; pFarther = NaN; pNonTracking = NaN;
if ~isfinite(step) || step < 1
    return
end
if isfield(method, 'pCloser') && step <= numel(method.pCloser)
    pCloser = double(method.pCloser(step));
end
if isfield(method, 'pNonTracking') && step <= numel(method.pNonTracking)
    pNonTracking = double(method.pNonTracking(step));
end
if isfinite(pCloser) && isfinite(pNonTracking)
    pFarther = max(0, min(1, 1 - pCloser - pNonTracking));
elseif isfinite(pCloser)
    pFarther = 1 - pCloser;
end
end


function [latency, amplitudeDeg] = localNearestSaccade( ...
        eventSample, time, x, y, starts, stops, setup)
latency = NaN; amplitudeDeg = NaN;
if isempty(starts) || ~isfinite(time(eventSample))
    return
end
[~, index] = min(abs(time(starts) - time(eventSample)));
latency = time(starts(index)) - time(eventSample);
if stops(index) <= numel(x) && starts(index) <= numel(x)
    amplitudePx = hypot( ...
        x(stops(index)) - x(starts(index)), ...
        y(stops(index)) - y(starts(index)));
    amplitudeDeg = px2deg(amplitudePx, setup);
end
end


function value = localTrialScalar(T, names)
value = NaN;
for i = 1:numel(names)
    if isfield(T, names{i}) && isnumeric(T.(names{i})) && ...
            isscalar(T.(names{i})) && isfinite(T.(names{i}))
        value = double(T.(names{i})); return
    end
end
if isfield(T, 'params') && isstruct(T.params)
    for i = 1:numel(names)
        if isfield(T.params, names{i}) && isnumeric(T.params.(names{i})) && ...
                isscalar(T.params.(names{i})) && isfinite(T.params.(names{i}))
            value = double(T.params.(names{i})); return
        end
    end
end
end


function row = localEmptyEventRow()
row = struct( ...
    'trial', NaN, 'eventType', "", 'eventCategory', "", ...
    'eventTimeSec', NaN, ...
    'sourceState', NaN, 'destinationState', NaN, ...
    'destinationTrackedTarget', NaN, ...
    'sourceDwellSec', NaN, 'destinationDwellSec', NaN, ...
    'previousEventIntervalSec', NaN, 'nextEventIntervalSec', NaN, ...
    'step', NaN, 'pCloser', NaN, 'pFarther', NaN, ...
    'pNonTracking', NaN, 'backgroundNoiseLvl', NaN, ...
    'targetVisibility', NaN, 'baselinePupilZ', NaN, ...
    'anticipatoryPupilChangeZ', NaN, 'earlyPupilChangeZ', NaN, ...
    'latePupilChangeZ', NaN, 'peakPostPupilChangeZ', NaN, ...
    'validEpochFrac', NaN, 'nearestSaccadeLatencySec', NaN, ...
    'nearestSaccadeAmplitudeDeg', NaN, 'gazeValidAtTransition', false, ...
    'hasBlinkInWindow', false);
end


function row = localEmptyStateTrialRow()
row = struct( ...
    'trial', NaN, 'state', "", 'meanPupilZ', NaN, 'sdPupilZ', NaN, ...
    'nSamples', 0, 'durationSec', NaN, ...
    'backgroundNoiseLvl', NaN, 'targetVisibility', NaN);
end


function mask = localWindowMask(time, window)
mask = time >= window(1) & time <= window(2);
end


function value = localWindowMean(trace, time, window)
value = mean(trace(localWindowMask(time, window)), 'omitnan');
end

function times=localRewardTimesRelative(T,tRel)
times=[];
if ~isfield(T,'times')||~isfield(T.times,'reward')||isempty(T.times.reward)
    return
end

raw=double(T.times.reward(:));raw=raw(isfinite(raw));if isempty(raw),return;end
relative=raw;absolute=nan(size(raw));
if isfield(T,'TrialStart')&&isscalar(T.TrialStart)&&isfinite(T.TrialStart)
    absolute=raw-double(T.TrialStart);
end
lower=min(tRel,[],'omitnan');upper=max(tRel,[],'omitnan');
scoreRelative=sum(relative>=lower&relative<=upper);
scoreAbsolute=sum(absolute>=lower&absolute<=upper);
if scoreAbsolute>scoreRelative||(scoreAbsolute==scoreRelative&&scoreAbsolute>0&& ...
        median(abs(absolute),'omitnan')<median(abs(relative),'omitnan'))
    times=absolute;
else
    times=relative;
end
times=sort(times(isfinite(times)&times>=lower&times<=upper));
end

function group=localCorrectionGroup(groups,sessionNo)
group=sessionNo;
for k=1:height(groups)
    blocks=groups.sessionBlocks{k};
    if any(double(blocks)==sessionNo),group=groups.group(k);return;end
end
end

function traces=localKernelsForEvents(events,deconvolution,time)
traces=nan(height(events),numel(time));
for k=1:height(events)
    name=char(events.eventCategory(k));
    if ~isfield(deconvolution.kernels,name),continue;end
    kernel=deconvolution.kernels.(name);
    traces(k,:)=interp1(kernel.timeSec,kernel.value,time,'linear',NaN);
end
end

function summary=localSummarizeDeconvolution(events,deconvolution,opts)
summary=localSummarize(events);
for k=1:height(summary)
    name=char(summary.eventCategory(k));
    if ~isfield(deconvolution.kernels,name),continue;end
    kernel=deconvolution.kernels.(name);
    summary.anticipatoryPupilChangeZ(k)=localWindowMean( ...
        kernel.value,kernel.timeSec,opts.anticipatoryWindowSec);
    summary.earlyPupilChangeZ(k)=localWindowMean( ...
        kernel.value,kernel.timeSec,opts.earlyWindowSec);
    summary.latePupilChangeZ(k)=localWindowMean( ...
        kernel.value,kernel.timeSec,opts.lateWindowSec);
end
end


function summary = localSummarize(events)
if isempty(events)
    summary = table(string.empty(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), ...
        'VariableNames', {'eventCategory','nEvents', ...
        'anticipatoryPupilChangeZ','earlyPupilChangeZ','latePupilChangeZ'});
    return
end
types = unique(events.eventCategory, 'stable');
rows = repmat(struct('eventCategory', "", 'nEvents', 0, ...
    'anticipatoryPupilChangeZ', NaN, 'earlyPupilChangeZ', NaN, ...
    'latePupilChangeZ', NaN), numel(types), 1);
for i = 1:numel(types)
    selected = events.eventCategory == types(i);
    rows(i).eventCategory = types(i);
    rows(i).nEvents = sum(selected);
    rows(i).anticipatoryPupilChangeZ = mean( ...
        events.anticipatoryPupilChangeZ(selected), 'omitnan');
    rows(i).earlyPupilChangeZ = mean( ...
        events.earlyPupilChangeZ(selected), 'omitnan');
    rows(i).latePupilChangeZ = mean( ...
        events.latePupilChangeZ(selected), 'omitnan');
end
summary = struct2table(rows);
end


function figureHandle = localPlot(time, events, traces, opts)
figureHandle = figure('Color', 'w', 'Name', 'HMM transition pupil responses', ...
    'Position', [100 50 760 920]);
colors = lines(4);
tiled = tiledlayout(figureHandle, 2, 1, ...
    'TileSpacing', 'compact', 'Padding', 'compact');
axesHandles = gobjects(2, 1);
axesHandles(1) = nexttile(tiled);
[~, trackingLabels] = localPlotPanel( ...
    axesHandles(1), time, events, traces, ...
    ["nonTracking_to_tracking", "tracking_to_nonTracking"], ...
    ["non-tracking -> tracking", "tracking -> non-tracking"], ...
    colors([3 4], :), 'Tracking acquisition and loss', ...
    opts.baselineWindowSec);
axesHandles(2) = nexttile(tiled);
[~, switchLabels] = localPlotPanel( ...
    axesHandles(2), time, events, traces, ...
    ["closer_to_farther", "farther_to_closer"], ...
    ["closer -> farther", "farther -> closer"], ...
    colors([1 2], :), 'Switches between tracked targets', ...
    opts.baselineWindowSec);
linkaxes(axesHandles, 'x');
if strcmp(opts.corMethod,'deconvolution')
    overallTitle=sprintf('%s HMM states; joint FIR deconvolution',opts.hmmMethod);
    yLabel='Deconvolved pupil response (session-eye SD)';
elseif isempty(opts.baselineWindowSec)
    overallTitle = sprintf('%s HMM states; no event baseline', opts.hmmMethod);
    yLabel = 'Pupil size (session-eye SD)';
else
    overallTitle = sprintf('%s HMM states; baseline [%g, %g] s', ...
        opts.hmmMethod, opts.baselineWindowSec);
    yLabel = '\Delta pupil (session-eye SD)';
end
arrayfun(@(axisHandle) ylabel(axisHandle, yLabel), axesHandles);
title(tiled, overallTitle);
legendColors = colors([3 4 1 2], :);
legendHandles = gobjects(4, 1);
for i = 1:4
    legendHandles(i) = plot(axesHandles(1), NaN, NaN, ...
        'Color', legendColors(i,:), 'LineWidth', 2, ...
        'HandleVisibility', 'on');
end
legend(axesHandles(1), legendHandles, [trackingLabels; switchLabels], ...
    'Location', 'northoutside', 'Orientation', 'horizontal', ...
    'NumColumns', 2, 'Interpreter', 'none');
end


function [lineHandles, legendLabels] = localPlotPanel( ...
        axisHandle, time, events, traces, types, labels, colors, ...
        panelTitle, baselineWindow)
hold(axisHandle, 'on');
lineHandles = gobjects(numel(types), 1);
legendLabels = strings(numel(types), 1);
for i = 1:numel(types)
    selected = false(0, 1);
    if ~isempty(events)
        selected = events.eventCategory == types(i);
    end
    nSelected = sum(selected);
    legendLabels(i) = sprintf('%s (n=%d)', labels(i), nSelected);
    if nSelected > 0
        localTraces = traces(selected, :);
        average = mean(localTraces, 1, 'omitnan');
        count = sum(isfinite(localTraces), 1);
        sem = std(localTraces, 0, 1, 'omitnan') ./ sqrt(max(count, 1));
        fill(axisHandle, [time fliplr(time)], ...
            [average-sem fliplr(average+sem)], colors(i,:), ...
            'FaceAlpha', .15, 'EdgeColor', 'none', ...
            'HandleVisibility', 'off');
        lineHandles(i) = plot(axisHandle, time, average, ...
            'Color', colors(i,:), 'LineWidth', 2, ...
            'HandleVisibility', 'off');
    else
        lineHandles(i) = plot(axisHandle, NaN, NaN, ...
            'Color', colors(i,:), 'LineWidth', 2, ...
            'HandleVisibility', 'off');
    end
end
if ~isempty(baselineWindow)
    yLimits = ylim(axisHandle);
    baselinePatch = patch(axisHandle, ...
        baselineWindow([1 2 2 1]), yLimits([1 1 2 2]), [.75 .75 .75], ...
        'FaceAlpha', .22, 'EdgeColor', 'none', ...
        'HandleVisibility', 'off');
    uistack(baselinePatch, 'bottom');
end
xline(axisHandle, 0, 'k--', 'HMM transition', ...
    'HandleVisibility', 'off');
yline(axisHandle, 0, 'Color', [.5 .5 .5], ...
    'HandleVisibility', 'off');
xlabel(axisHandle, 'Time from transition (s)');
title(axisHandle, panelTitle); grid(axisHandle, 'on');
pbaspect(axisHandle, [1.45 1 1]);
end
