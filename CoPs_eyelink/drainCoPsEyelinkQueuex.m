function nDiscarded = drainCoPsEyelinkQueuex()
% Discard pretrial link data without allocating GetQueuedData matrices.
% GetNextDataType advances the queue even when GetFloatData is not called.
% EDF recording is independent of these discarded online samples/events.
nDiscarded = 0;
for item = 1:100000
    if Eyelink('GetNextDataType') == 0
        return
    end
    nDiscarded = nDiscarded + 1;
end
error('drainCoPsEyelinkQueuex:NotDrained', ...
    'EyeLink pretrial queue did not empty after discarding %d items.', nDiscarded);
end
