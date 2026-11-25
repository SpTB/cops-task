function sync = prepareCoPsSyncx(sync, refreshIntervalSec)
% Resolve the photodiode protocol once, before trial execution (no toolboxes).
if nargin < 1, sync = struct(); end
defaults = struct('mode', 'goPulse', 'framesPerBit', 1, 'seed', 1, ...
    'sequence', [], 'preambleSec', 0.1, 'gapSec', 0.05, 'physicalChannel', 0, ...
    'captureTailSecs', 0.1);
names = fieldnames(defaults);
for k = 1:numel(names)
    if ~isfield(sync, names{k}), sync.(names{k}) = defaults.(names{k}); end
end
sync.mode = validatestring(sync.mode, {'goPulse','binary','off'});
validateattributes(refreshIntervalSec, {'numeric'}, {'scalar','real','finite','positive'});
validateattributes(sync.framesPerBit, {'numeric'}, {'scalar','integer','positive','finite'});
validateattributes(sync.seed, {'numeric'}, {'scalar','integer','>=',1,'<=',32767});
validateattributes(sync.preambleSec, {'numeric'}, {'scalar','real','finite','positive'});
validateattributes(sync.gapSec, {'numeric'}, {'scalar','real','finite','positive'});
validateattributes(sync.physicalChannel, {'numeric'}, {'scalar','integer','nonnegative','finite'});
validateattributes(sync.captureTailSecs, {'numeric'}, {'scalar','real','nonnegative','finite'});
sync.refreshIntervalSec = double(refreshIntervalSec);
sync.bitRateHz = 1 / (refreshIntervalSec * sync.framesPerBit);
sync.preambleFrames = max(1, round(sync.preambleSec / refreshIntervalSec));
sync.gapFrames = max(1, round(sync.gapSec / refreshIntervalSec));
sync.protocolVersion = 1;
sync.sequencePolicy = 'reuse from bit 1 each trial';
if strcmp(sync.mode, 'binary')
    if isempty(sync.sequence)
        % x^15 + x^14 + 1; one full period, without changing MATLAB's RNG.
        bits = false(1, 32767);
        bits(1:15) = logical(bitget(uint16(sync.seed), 15:-1:1));
        for k = 16:numel(bits)
            bits(k) = xor(bits(k-1), bits(k-15));
        end
        sync.sequence = bits;
        sync.generator = 'LFSR15: b(k)=xor(b(k-1),b(k-15)); initial bits MSB first';
    else
        validateattributes(sync.sequence, {'numeric','logical'}, {'vector','nonempty','real','finite'});
        if any(sync.sequence ~= 0 & sync.sequence ~= 1) || numel(unique(sync.sequence)) < 2
            error('prepareCoPsSyncx:InvalidSequence', 'The sync sequence must contain both 0 and 1, and no other values.');
        end
        sync.sequence = logical(sync.sequence(:)');
        sync.generator = 'supplied binary vector';
    end
end
end
