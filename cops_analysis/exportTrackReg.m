function [trackTable, csvPath] = exportTrackReg(ex, csvPath, opts)
% exportTrackReg  Export one row per HMM tracking chunk for tracking models.
%
%   T = exportTrackReg(ex)
%   T = exportTrackReg(ex, 'tracking_chunks.csv')
%   [T, csvPath] = exportTrackReg(ex, csvPath, opts)
%
% Chunk definitions, identifiers, timing, conditions, and reward-distance
% predictors are identical to exportSelReg. Selection outcomes are replaced
% by tracking bias, error, and variability outcomes in visual degrees by
% default (or pixels when opts.distanceUnits='px').

if nargin < 2
    csvPath = [];
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
opts.outputType = 'tracking';
opts.compactOutput = true;
[trackTable, csvPath] = exportSelReg(ex, csvPath, opts);
end
