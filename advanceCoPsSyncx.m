function [cursor, bit, index, phase] = advanceCoPsSyncx(sync, cursor, active)
% Advance once per submitted GO frame, never from elapsed time or target step.
% phase: 0=idle black, 1=GO marker, 2=black gap, 3=binary payload.
bit = 0;
index = NaN;
phase = uint8(0);
if ~active, return; end
cursor = cursor + 1;
if cursor <= sync.preambleFrames
    bit = 1;
    phase = uint8(1);
elseif cursor <= sync.preambleFrames + sync.gapFrames
    phase = uint8(2);
else
    index = floor((cursor - sync.preambleFrames - sync.gapFrames - 1) / sync.framesPerBit) + 1;
    if index > numel(sync.sequence)
        error('advanceCoPsSyncx:SequenceExhausted', 'Photodiode sequence exhausted; provide more bits or increase framesPerBit. The sequence is never wrapped.');
    end
    bit = double(sync.sequence(index));
    phase = uint8(3);
end
end
