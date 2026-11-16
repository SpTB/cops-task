function stopCoPsAnalogx
% Best-effort cleanup, including an interrupted session or initialization error.
try
    Datapixx('StopAdcSchedule');
    Datapixx('RegWr');
catch err
    warning('stopCoPsAnalogx:CleanupFailed', 'Could not stop ADC acquisition: %s', err.message);
end
end
