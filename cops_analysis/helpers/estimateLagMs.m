function [c, lags] = estimateLagMs(tx, x, fs, maxLagSec)
%returns cross-correlation vector
% tx: target position (x or y)
% x: eye position (x or y)
lagMs = NaN;
rhoAtLag = NaN;

if nargin < 4 || ~isfinite(maxLagSec) || maxLagSec <= 0
    maxLagSec = 0.5;
end

good = isfinite(x) & isfinite(tx);
if nnz(good) < 5
    return
end

x = x(good);
tx = tx(good);

x = x - mean(x, 'omitnan');
tx = tx - mean(tx, 'omitnan');

maxLag = max(1, round(maxLagSec * fs));
[c, lags] = xcorr(tx, x, maxLag, 'coeff');
%[~, idx] = max(c);
%lagSamp = lags(idx);
%lagMs = 1000 * lagSamp / fs;
%rhoAtLag = c(idx);
end
