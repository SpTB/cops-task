function analog = readCoPsAnalogx(analog)
% Drain the ADC independently of behavioral input; timestamps are DataPixx time.
Datapixx('RegWrRd');
status = Datapixx('GetAdcStatus');
if (isfield(status, 'numStreamOverflows') && status.numStreamOverflows > 0) || ...
        (isfield(status, 'numBufferFrames') && status.newBufferFrames > status.numBufferFrames)
    error('readCoPsAnalogx:Overflow', 'The DataPixx ADC buffer overflowed.');
end
count = status.newBufferFrames;
if count > 0
    idx = analog.n + (1:count);
    [v, t, underflow, overflow] = Datapixx('ReadAdcBuffer', count, -1);
    if overflow
        error('readCoPsAnalogx:Overflow', 'The DataPixx ADC buffer overflowed during streaming.');
    end
    if underflow
        error('readCoPsAnalogx:Underflow', 'DataPixx returned an incomplete ADC buffer.');
    end
    analog.v(:,idx) = v;
    analog.t(idx) = t;
    analog.n = analog.n + count;
end
end
