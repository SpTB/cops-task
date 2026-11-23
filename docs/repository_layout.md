# Task and analysis repositories

`cops-task` contains acquisition, live calibration, participant instructions,
stimulus generation, recording and hardware validation. Offline fitting,
recorded-data analysis, posthoc plotting and simulation utilities live in the
separate `cops-analysis` repository. Existing data repositories are independent.

The human and main task branches keep their own acquisition implementations.
This human branch retains its native EyeLink, per-trial calibration, instruction,
movie, photodiode and stimulus-generation behavior.

The F9 live gaze display uses nine local functions in `helpers/`. `runEx` adds
that directory to the MATLAB path; the trial handler also loads it when F9 needs
the display. Calling an individual helper directly requires adding `helpers/`.
Live acquisition and calibration do not require `cops-analysis` on the path.
`plotCalibFunc` remains here because live analog calibration calls it.

Former standalone utilities such as `subsetEx`, `simTargetAcorrEx`,
`PlotEyeCalibData`, `plotCalib`, `plotTex`, `stimTimingTable`, `checkSynch` and
`extractVideoSyncFromTrial` belong to recorded-data analysis. Their original
versions and the removed analysis tree are preserved in the separate analysis
repository's migration archive. Generated `validation_reports/` are local
calibration outputs and are excluded from Git; calibration can continue to
write them.

For helper regression checks, run `runtests('testCoPsTaskHelpersx.m')`,
`runtests('testCoPsTrialCalibrationx.m')` and the tests under `CoPs_eyelink/`.
The helper tests exercise the real gaze display without task hardware, and the
native-eye tests verify calibration and timestamp handling. Other acquisition
tests remain specific to this branch.

The live stimulus renderer also calls clip.m. Its existing matlabPyrTools
implementation is provided explicitly in helpers/ with its original license
and provenance (helpers/THIRD_PARTY.txt). Stimulus equations and trial settings
are unchanged; the private generator dependency directory is not exposed.
