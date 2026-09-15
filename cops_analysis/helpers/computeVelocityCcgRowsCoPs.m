function [rowX, rowY] = computeVelocityCcgRowsCoPs(xPx, yPx, targetX, targetY, stepIdx, tRelSec, analysisMask, dtSec, ccgWindowSec)
% computeVelocityCcgRowsCoPs  Stepwise, chunked velocity CCGs for x and y.
%
% Inputs are assumed to already be preprocessed for gaze gaps / filtering
% if desired. Non-usable gaze samples should be represented as NaN.

if nargin < 7 || isempty(analysisMask)
    analysisMask = true(size(stepIdx));
end
if nargin < 8 || ~isfinite(dtSec) || dtSec <= 0
    rowX = [];
    rowY = [];
    return
end
if nargin < 9 || isempty(ccgWindowSec)
    ccgWindowSec = [-0.5 2];
end

ccgWindowSec = double(ccgWindowSec(:)');
if numel(ccgWindowSec) ~= 2 || any(~isfinite(ccgWindowSec)) || ccgWindowSec(1) > ccgWindowSec(2)
    error('computeVelocityCcgRowsCoPs:BadCcgWindow', ...
        'ccgWindowSec must be a finite 1x2 vector [minLagSec maxLagSec].');
end

stepTable = localAggregateToSteps( ...
    double(xPx(:)), double(yPx(:)), double(targetX(:)), double(targetY(:)), ...
    double(stepIdx(:)), double(tRelSec(:)), logical(analysisMask(:)));

rowX = localComputeVelocityCcg1d(stepTable.xPx, stepTable.targetX, stepTable.tRelSec, dtSec, ccgWindowSec);
rowY = localComputeVelocityCcg1d(stepTable.yPx, stepTable.targetY, stepTable.tRelSec, dtSec, ccgWindowSec);
end


function stepTable = localAggregateToSteps(xPx, yPx, targetX, targetY, stepIdx, tRelSec, analysisMask)
valid = analysisMask & isfinite(stepIdx) & isfinite(targetX) & isfinite(targetY);
if ~any(valid)
    stepTable = table();
    return
end

T = table(stepIdx(valid), tRelSec(valid), xPx(valid), yPx(valid), targetX(valid), targetY(valid), ...
    'VariableNames', {'step','tRelSec','xPx','yPx','targetX','targetY'});
[stepGroups, ~] = findgroups(T.step);

stepTable = table();
stepTable.step = splitapply(@(x) x(1), T.step, stepGroups);
stepTable.tRelSec = splitapply(@mean, T.tRelSec, stepGroups);
stepTable.xPx = splitapply(@(x) mean(x, 'omitnan'), T.xPx, stepGroups);
stepTable.yPx = splitapply(@(x) mean(x, 'omitnan'), T.yPx, stepGroups);
stepTable.targetX = splitapply(@(x) mean(x, 'omitnan'), T.targetX, stepGroups);
stepTable.targetY = splitapply(@(x) mean(x, 'omitnan'), T.targetY, stepGroups);
stepTable = sortrows(stepTable, 'step');
end


function out = localComputeVelocityCcg1d(gazePos, targetPos, tRelSec, fallbackDtSec, ccgWindowSec)
out = struct('lagSamples', NaN(0,1), 'lagSec', NaN(0,1), 'corr', NaN(0,1), ...
    'chunkAccum', NaN(0,1), 'chunkWeightSum', 0);
if isempty(gazePos) || isempty(targetPos) || numel(gazePos) < 3 || numel(targetPos) < 3
    return
end

dtStep = localResolveStepDt(tRelSec, fallbackDtSec);
if ~isfinite(dtStep) || dtStep <= 0
    return
end

validMask = isfinite(gazePos) & isfinite(targetPos);
if nnz(validMask) < 3
    return
end

maxLagSamples = max(1, round(max(abs(ccgWindowSec)) / dtStep));
chunkInfo = localChunkedVelocityCorr(gazePos, targetPos, validMask, maxLagSamples, dtStep, ccgWindowSec);
lagsAll = (-maxLagSamples:maxLagSamples)';
lagSecAll = lagsAll .* dtStep;
keep = lagSecAll >= min(ccgWindowSec) & lagSecAll <= max(ccgWindowSec);

out.lagSamples = lagsAll(keep);
out.lagSec = lagSecAll(keep);
out.corr = chunkInfo.corr;
out.chunkAccum = chunkInfo.accum;
out.chunkWeightSum = chunkInfo.weightSum;
end


function dtStep = localResolveStepDt(tRelSec, fallbackDtSec)
dtStep = NaN;
if numel(tRelSec) >= 2
    dtCandidates = diff(tRelSec(:));
    dtCandidates = dtCandidates(isfinite(dtCandidates) & dtCandidates > 0);
    if ~isempty(dtCandidates)
        dtStep = median(dtCandidates, 'omitnan');
        return
    end
end
dtStep = fallbackDtSec;
end


function out = localChunkedVelocityCorr(gazePos, targetPos, validMask, maxLagSamples, dtStep, ccgWindowSec)
lagsAll = (-maxLagSamples:maxLagSamples)';
lagSecAll = lagsAll .* dtStep;
keep = lagSecAll >= min(ccgWindowSec) & lagSecAll <= max(ccgWindowSec);
out = struct('corr', NaN(sum(keep), 1), 'accum', zeros(sum(keep), 1), 'weightSum', 0);

idx = find(validMask);
if isempty(idx)
    return
end

runBreak = [true; diff(idx) > 1];
runStarts = find(runBreak);
runEnds = [runStarts(2:end) - 1; numel(idx)];
for i = 1:numel(runStarts)
    ii = idx(runStarts(i):runEnds(i));
    if numel(ii) < 4
        continue
    end

    gazeVel = diff(gazePos(ii)) ./ dtStep;
    targetVel = diff(targetPos(ii)) ./ dtStep;
    goodVel = isfinite(gazeVel) & isfinite(targetVel);
    gazeVel = gazeVel(goodVel);
    targetVel = targetVel(goodVel);
    if numel(gazeVel) < 3
        continue
    end

    gazeVel = gazeVel - mean(gazeVel, 'omitnan');
    targetVel = targetVel - mean(targetVel, 'omitnan');
    xc = xcorr(gazeVel, targetVel, maxLagSamples, 'coeff');

    w = numel(gazeVel);
    out.accum = out.accum + w .* xc(keep);
    out.weightSum = out.weightSum + w;
end

if out.weightSum > 0
    out.corr = out.accum ./ out.weightSum;
end
end
