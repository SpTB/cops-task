# Recording camera synchronization signals

The task records ADC samples and their Datapixx timestamps into each trial:

- `ex.Trials(i).Eye.v`: recorded channels by samples.
- `ex.Trials(i).Eye.t`: Datapixx timestamp for each sample.
- `ex.Trials(i).TrialStartDatapixx`: the trial-start Datapixx anchor.

Connect the camera synchronization line to the intended spare ADC input and
confirm that input is included in `ex.setup.adc.Channels`. The acquisition
settings are resolved by `getDefaultSettingsx.m`; `checkEyex` drains the
scheduled ADC samples during acquisition. Physical channel numbers and stored
row numbers differ, so retain the scheduled channel list with each recording.

Saved-session pulse extraction, clock alignment and video analysis belong in
the standalone `cops-analysis` repository. The former
`extractVideoSyncFromTrial.m` utility is preserved there under
`legacy/matlab/`, with the original task versions retained in its migration
archive. Run that processing from the analysis project after acquisition.

This recording path does not import analysis code or add an analysis
repository to the experiment's MATLAB path.
