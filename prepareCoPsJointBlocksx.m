function ex = prepareCoPsJointBlocksx(ex)
% Prepare random lengths and reward centers for the joint-block CoPs task.
% This must run after display geometry has been initialized.

if ~isfield(ex, 'exp') || ~isfield(ex.exp, 'CoPs') || ...
        ~isfield(ex.exp.CoPs, 'ctl')
    return
end

ctl = ex.exp.CoPs.ctl;
if ~localLogicalScalar(ctl, 'jointBlocks', false)
    return
end

numBlocks = localPositiveInteger(ctl, 'numBlocks');
meanTrials = localPositiveInteger(ctl, 'blockMeanTrials');
transRange = localNonnegativeInteger(ctl, 'blockTransRange');
minCenterDistanceDeg = localNonnegativeScalar(ctl, 'rewPeakDistFromPrev');
if meanTrials - transRange < 1
    error('prepareCoPsJointBlocksx:BadBlockLengthRange', ...
        'ctl.blockMeanTrials - ctl.blockTransRange must be at least 1 trial.');
end

blockLengths = randi([meanTrials - transRange, meanTrials + transRange], 1, numBlocks);
blockEnds = cumsum(blockLengths);
blockStarts = [1, blockEnds(1:end-1) + 1];

blockCenters = nan(numBlocks, 2);
[blockCenters(1, :), drawInfo] = drawRewPeak(ex);
degPerNorm = (drawInfo.gauss_dim - 1) / drawInfo.ppd;
for blockIdx = 2:numBlocks
    found = false;
    for attempt = 1:10000
        candidate = drawRewPeak(ex);
        distanceDeg = norm(candidate - blockCenters(blockIdx - 1, :)) * degPerNorm;
        if distanceDeg >= minCenterDistanceDeg
            blockCenters(blockIdx, :) = candidate;
            found = true;
            break
        end
    end
    if ~found
        error('prepareCoPsJointBlocksx:NoFeasibleCenter', ...
            ['Could not draw a reward center at least %.3g deg from the previous center. ' ...
             'Reduce ctl.rewPeakDistFromPrev or increase ctr.max_peak_dist_deg.'], ...
            minCenterDistanceDeg);
    end
end

ctl.jointBlockLengths = blockLengths;
ctl.jointBlockStartMainTrials = blockStarts;
ctl.jointBlockEndMainTrials = blockEnds;
ctl.jointBlockCenters = blockCenters;
ex.exp.CoPs.ctl = ctl;

% Joint blocks define the complete main-task length and use free centers.
ex.exp.nreps = sum(blockLengths);
ex.exp.CoPs.rew.gauss_center_free = true;
ex.exp.CoPs.rew.gauss_center_coords = blockCenters(1, :);
end


function value = localPositiveInteger(s, fieldName)
value = localNumericScalar(s, fieldName);
if value < 1 || value ~= round(value)
    error('prepareCoPsJointBlocksx:BadPositiveInteger', ...
        'ctl.%s must be a positive integer.', fieldName);
end
value = round(value);
end


function value = localNonnegativeInteger(s, fieldName)
value = localNumericScalar(s, fieldName);
if value < 0 || value ~= round(value)
    error('prepareCoPsJointBlocksx:BadNonnegativeInteger', ...
        'ctl.%s must be a nonnegative integer.', fieldName);
end
value = round(value);
end


function value = localNonnegativeScalar(s, fieldName)
value = localNumericScalar(s, fieldName);
if value < 0
    error('prepareCoPsJointBlocksx:BadNonnegativeScalar', ...
        'ctl.%s must be nonnegative.', fieldName);
end
end


function value = localNumericScalar(s, fieldName)
if ~isfield(s, fieldName) || isempty(s.(fieldName)) || ...
        ~(isnumeric(s.(fieldName)) || islogical(s.(fieldName))) || ...
        ~isscalar(s.(fieldName)) || ~isfinite(double(s.(fieldName)))
    error('prepareCoPsJointBlocksx:BadSetting', ...
        'ctl.%s must be a finite numeric scalar.', fieldName);
end
value = double(s.(fieldName));
end


function value = localLogicalScalar(s, fieldName, defaultValue)
value = defaultValue;
if ~isfield(s, fieldName) || isempty(s.(fieldName))
    return
end
candidate = s.(fieldName);
if islogical(candidate) || isnumeric(candidate)
    value = logical(candidate(1));
elseif ischar(candidate) || isstring(candidate)
    value = any(strcmpi(strtrim(char(string(candidate))), {'true', '1', 'yes', 'on'}));
end
end
