# Synchronizing task timestamps to camera video via Datapixx ADC

This repo already records ADC samples and per-sample Datapixx timestamps into each trial:

- `ex.Trials(i).Eye.v` (channels × samples)
- `ex.Trials(i).Eye.t` (Datapixx time for each sample)
- `ex.Trials(i).TrialStartDatapixx` (Datapixx timestamp near trial start)

In `getDefaultSettingsx.m`, binocular mode currently schedules channels `0:5` plus one extra channel (stored as the 7th recorded row). If your camera sync is wired to that extra input, it will appear in the 7th row of `Eye.v` during analysis.

## Practical workflow

1. **Record the camera sync signal on every trial**
   - Keep the analog sync line connected to the extra ADC channel.
   - Run as usual; the existing `checkEyex` call continuously pulls new ADC frames from Datapixx.

2. **Extract sync pulse edges from ADC**
   - For each trial, read the sync row from `Eye.v` and detect threshold crossings.
   - Convert crossing sample indices to Datapixx times with `Eye.t`.

3. **Align task events to video timeline**
   - Task events in trial structs are in PTB/GetSecs (`ex.Trials(i).times.*`).
   - Use `TrialStartDatapixx` and/or `PsychDataPixx('BoxsecsToGetsecs', ...)` remapping from `runEx.m` to convert task event times into a common clock, then match to camera pulse times.

## Example usage

```matlab
% Suppose `ex` is loaded from a session .mat file.

scheduledChannels = ex.setup.adc.Channels;  % e.g. [0 1 2 3 4 5 6]
physicalSyncChannel = 7;                    % 0-based Datapixx channel index

for iT = 1:numel(ex.Trials)
    tr = ex.Trials(iT);

    sync = extractVideoSyncFromTrial(tr, scheduledChannels, ...
        'PhysicalChannel', physicalSyncChannel, ...
        'MinPulseWidthSec', 0.001);

    % Example: first sync pulse relative to trial start (Datapixx seconds)
    if ~isempty(sync.edgeTimeFromTrialStart)
        fprintf('Trial %d first pulse: %.6f s after trial start\n', ...
            iT, sync.edgeTimeFromTrialStart(1));
    end
end
```

## Notes

- If WM/e3 Vision outputs frame pulses, detected rising edges correspond to camera frames.
- If it outputs a trial marker pulse train, you can use first/last edge per trial for alignment anchors.
- If your sync channel appears inverted (high-to-low pulses), set polarity to `'falling'` in `extractVideoSyncFromTrial`.
