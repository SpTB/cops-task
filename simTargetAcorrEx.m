function ex = simTargetAcorrEx(opts)
% simTargetAcorrEx  Build a lightweight ex struct with simulated CoPs target walks.
%
% Example:
%   exSim = simTargetAcorrEx;
%   plotTargetAcorr(exSim, 1:numel(exSim.Trials), 'all', ...
%       struct('signalMode', 'velocity', 'source', 'targetPositions'));

if nargin < 1 || isempty(opts)
    opts = struct();
end

base = struct();
try
    evalc('base = setDefaultsCoPs(base);');
catch
    base = localFallbackDefaults();
end

cfg = base.exp.CoPs;
graph = cfg.graph;
ctl = cfg.ctl;
pos = cfg.pos;
timing = cfg.timing;

nTrials = localOpt(opts, 'nTrials', 200);
nsteps = localOpt(opts, 'nsteps', ctl.nsteps);
fsHz = localOpt(opts, 'fsHz', 500);
screenRect = localOpt(opts, 'screenRect', [0 0 1920 1080]);

if isfield(opts, 'waitHz') && ~isempty(opts.waitHz)
    timing.waitHz = opts.waitHz;
    timing.wait_secs = 1 / double(opts.waitHz);
elseif isfield(opts, 'waitSecs') && ~isempty(opts.waitSecs)
    timing.wait_secs = opts.waitSecs;
    timing.waitHz = 1 / double(opts.waitSecs);
end
[waitSecs, waitHz] = resolveCoPsWaitSecs(struct('timing', timing), 0.1);

ctl.nsteps = nsteps;
ctl.step_size_mult = localOpt(opts, 'stepSizeMult', ctl.step_size_mult);
ctl.stepNoiseSigma = localOpt(opts, 'stepNoiseSigma', ctl.stepNoiseSigma);
ctl.stepNoiseCapSigma = localOpt(opts, 'stepNoiseCapSigma', ctl.stepNoiseCapSigma);
ctl.stepNoiseType = localOpt(opts, 'stepNoiseType', ctl.stepNoiseType);
ctl.boundaryMode = localOpt(opts, 'boundaryMode', localField(ctl, 'boundaryMode', 'clip'));
ctl.boundaryRejectMaxAttempts = localOpt(opts, 'boundaryRejectMaxAttempts', localField(ctl, 'boundaryRejectMaxAttempts', 50));
ctl.targetHiddenBoundsFrac = localOpt(opts, 'targetHiddenBoundsFrac', localField(ctl, 'targetHiddenBoundsFrac', 0));
ctl.target_num = localOpt(opts, 'targetNum', localFirstScalar(ctl.target_num));

if isfield(opts, 'seed') && ~isempty(opts.seed)
    localSetSeed(opts.seed);
end

ex = struct();
ex.exp.CoPs = cfg;
ex.exp.CoPs.graph = graph;
ex.exp.CoPs.ctl = ctl;
ex.exp.CoPs.timing = timing;
ex.exp.CoPs.timing.waitHz = waitHz;
ex.exp.CoPs.timing.wait_secs = waitSecs;
ex.exp.CoPs.analysis.firstGoStep = 1;
ex.setup.screenRect = screenRect;
ex.setup.adc.Rate = fsHz;
ex.setup.horEyeSign = 1;
ex.fix.PCtr = [mean(screenRect([1 3])), mean(screenRect([2 4]))];
ex.eyeCal = localDummyEyeCal();

nTrials = max(1, round(double(nTrials)));
nsteps = max(2, round(double(nsteps)));
fsHz = max(1, double(fsHz));
nSamples = max(2, ceil(nsteps * waitSecs * fsHz));
sampleT = (0:(nSamples - 1)) ./ fsHz;
targetPositionBound = localTargetPositionBound(graph, ctl.targetHiddenBoundsFrac);

ex.Trials = repmat(localEmptyTrial(), 1, nTrials);
for iTrial = 1:nTrials
    stepSizeMult = localDrawLevel(ctl.step_size_mult);
    stepNoiseSigma = stepSizeMult * localFirstScalar(ctl.stepNoiseSigma);
    targetNum = round(localDrawLevel(ctl.target_num));

    posTrial = pos;
    if localField(ctl, 'randomize_start_pos', 0)
        [posTrial.initx1, posTrial.inity1, posTrial.initx2, posTrial.inity2] = ...
            localRandomizedStarts(posTrial.initx1, posTrial.inity1, targetNum);
    end

    dx1 = stepSizeMult * [posTrial.dxmin1, posTrial.dxmax1];
    dy1 = stepSizeMult * [posTrial.dymin1, posTrial.dymax1];
    posT.x1 = sim_targ_pos(nsteps, posTrial.initx1, dx1(1), dx1(2), ...
        ctl.stepNoiseType, stepNoiseSigma, ctl.stepNoiseCapSigma, ...
        ctl.boundaryMode, ctl.boundaryRejectMaxAttempts, targetPositionBound);
    posT.y1 = sim_targ_pos(nsteps, posTrial.inity1, dy1(1), dy1(2), ...
        ctl.stepNoiseType, stepNoiseSigma, ctl.stepNoiseCapSigma, ...
        ctl.boundaryMode, ctl.boundaryRejectMaxAttempts, targetPositionBound);

    if targetNum == 2
        dx2 = stepSizeMult * [posTrial.dxmin2, posTrial.dxmax2];
        dy2 = stepSizeMult * [posTrial.dymin2, posTrial.dymax2];
        posT.x2 = sim_targ_pos(nsteps, posTrial.initx2, dx2(1), dx2(2), ...
            ctl.stepNoiseType, stepNoiseSigma, ctl.stepNoiseCapSigma, ...
            ctl.boundaryMode, ctl.boundaryRejectMaxAttempts, targetPositionBound);
        posT.y2 = sim_targ_pos(nsteps, posTrial.inity2, dy2(1), dy2(2), ...
            ctl.stepNoiseType, stepNoiseSigma, ctl.stepNoiseCapSigma, ...
            ctl.boundaryMode, ctl.boundaryRejectMaxAttempts, targetPositionBound);
    end

    T = localEmptyTrial();
    T.nsteps = nsteps;
    T.target_num = targetNum;
    T.step_size_mult = stepSizeMult;
    T.waitSecs = waitSecs;
    T.waitHz = waitHz;
    T.targetHiddenBoundsFrac = ctl.targetHiddenBoundsFrac;
    T.targetPositionBound = targetPositionBound;
    T.boundaryMode = char(ctl.boundaryMode);
    T.boundaryRejectMaxAttempts = ctl.boundaryRejectMaxAttempts;
    T.posT = posT;
    T.targetPositions = localTargetPositions(posT, graph, screenRect, targetNum, ctl.targetHiddenBoundsFrac);
    T.TrialStart = 0;
    T.TrialStartDatapixx = 0;
    T.TrialEnd = sampleT(end);
    T.times.stimOn = 0;
    T.Eye.v = zeros(2, nSamples);
    T.Eye.n = nSamples;
    T.Eye.t = sampleT;
    ex.Trials(iTrial) = T;
end
end


function T = localEmptyTrial()
T = struct( ...
    'nsteps', NaN, ...
    'target_num', NaN, ...
    'step_size_mult', NaN, ...
    'waitSecs', NaN, ...
    'waitHz', NaN, ...
    'targetHiddenBoundsFrac', NaN, ...
    'targetPositionBound', NaN, ...
    'boundaryMode', '', ...
    'boundaryRejectMaxAttempts', NaN, ...
    'posT', struct(), ...
    'targetPositions', struct([]), ...
    'TrialStart', NaN, ...
    'TrialStartDatapixx', NaN, ...
    'TrialEnd', NaN, ...
    'times', struct('stimOn', NaN), ...
    'Eye', struct('v', [], 'n', 0, 't', []));
end


function targetPositions = localTargetPositions(posT, graph, screenRect, targetNum, hiddenFrac)
sizeMult = double(graph.size_mult);
radius = double(graph.radius);
texDims = double(graph.texture_dims(:)');
imgWidth = texDims(1);
imgHeight = texDims(min(2, numel(texDims)));
texW = imgWidth * sizeMult;
texH = imgHeight * sizeMult;
xshift = (screenRect(3) - texW) / 2;
yshift = (screenRect(4) - texH) / 2;

nsteps = numel(posT.x1);
targetPositions = repmat(struct(), 1, nsteps);
for s = 1:nsteps
    [px1, py1] = pix_norm(posT.x1(s), posT.y1(s), imgWidth, imgHeight, radius, hiddenFrac);
    targetPositions(s).targ1.pos_abs = [screenRect(1) + xshift + px1 * sizeMult, ...
        screenRect(2) + yshift + py1 * sizeMult];
    targetPositions(s).targ1.norm_pos = [posT.x1(s), posT.y1(s)];
    targetPositions(s).step = s;
    targetPositions(s).image_idx = NaN;
    targetPositions(s).cx = posT.x1(s);
    targetPositions(s).cy = posT.y1(s);

    if targetNum == 2
        [px2, py2] = pix_norm(posT.x2(s), posT.y2(s), imgWidth, imgHeight, radius, hiddenFrac);
        targetPositions(s).targ2.pos_abs = [screenRect(1) + xshift + px2 * sizeMult, ...
            screenRect(2) + yshift + py2 * sizeMult];
        targetPositions(s).targ2.norm_pos = [posT.x2(s), posT.y2(s)];
        targetPositions(s).cx2 = posT.x2(s);
        targetPositions(s).cy2 = posT.y2(s);
    end
end
end


function [x1, y1, x2, y2] = localRandomizedStarts(baseX, baseY, targetNum)
r = hypot(baseX, baseY);
theta = rand * 2 * pi;
x1 = r * cos(theta);
y1 = r * sin(theta);
if targetNum == 2
    x2 = -x1;
    y2 = -y1;
else
    x2 = NaN;
    y2 = NaN;
end
end


function bound = localTargetPositionBound(graph, hiddenFrac)
bound = 1;
hiddenFrac = max(0, localFirstScalar(hiddenFrac));
if ~isfinite(hiddenFrac) || hiddenFrac <= 0
    return
end
texDims = double(graph.texture_dims(:)');
if numel(texDims) < 2
    texDims = [texDims(1), texDims(1)];
end
visibleRange = min((texDims(1:2) / 2) - double(graph.radius));
if isfinite(visibleRange) && visibleRange > 0
    bound = 1 + (2 * double(graph.radius) * hiddenFrac) / visibleRange;
end
end


function ex = localFallbackDefaults()
ex.exp.CoPs.graph = struct('size_mult', 1080/192, 'texture_dims', [192 192], 'radius', 15);
ex.exp.CoPs.ctl = struct( ...
    'nsteps', 180, ...
    'step_size_mult', 1, ...
    'stepNoiseType', 'gaussian', ...
    'stepNoiseSigma', 0.07, ...
    'stepNoiseCapSigma', 3.5, ...
    'boundaryMode', 'reject', ...
    'boundaryRejectMaxAttempts', 50, ...
    'targetHiddenBoundsFrac', 0.2, ...
    'target_num', 2, ...
    'randomize_start_pos', 1);
ex.exp.CoPs.pos = struct( ...
    'initx1', -0.5, 'inity1', 0, ...
    'initx2', 0.5, 'inity2', 0, ...
    'dxmin1', -0.1, 'dxmax1', 0.1, ...
    'dymin1', -0.1, 'dymax1', 0.1, ...
    'dxmin2', -0.1, 'dxmax2', 0.1, ...
    'dymin2', -0.1, 'dymax2', 0.1);
ex.exp.CoPs.timing = struct('waitHz', 10, 'wait_secs', 0.1);
end


function eyeCal = localDummyEyeCal()
eyeCal = struct();
eyeCal.RX0 = 0;
eyeCal.RY0 = 0;
eyeCal.RXGain = 1;
eyeCal.RYGain = 1;
eyeCal.LXPos = [];
eyeCal.Delta = struct('cnt', 1, 'RX0', 0, 'RY0', 0, 'LX0', 0, 'LY0', 0);
end


function value = localOpt(opts, fieldName, fallback)
if isstruct(opts) && isfield(opts, fieldName) && ~isempty(opts.(fieldName))
    value = opts.(fieldName);
else
    value = fallback;
end
end


function value = localField(s, fieldName, fallback)
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);
else
    value = fallback;
end
end


function value = localDrawLevel(x)
x = double(x(:)');
if isempty(x)
    value = NaN;
elseif numel(x) == 1
    value = x;
else
    value = x(randi(numel(x)));
end
end


function value = localFirstScalar(x)
if isempty(x)
    value = NaN;
else
    value = double(x(1));
end
end


function localSetSeed(seed)
seed = double(seed(1));
if exist('rng', 'file') == 2 || exist('rng', 'builtin') == 5
    rng(seed);
else
    rand('seed', seed); %#ok<RAND>
    randn('seed', seed); %#ok<RAND>
end
end
