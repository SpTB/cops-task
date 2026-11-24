Run from the MATLAB command window, with the animal ready and no experiment running:

```matlab
cd('/home/vpixx/Desktop/cops-task')
ex = runEx('t', calibrationTransitionCheck=true);
```

Complete the usual manual calibration. The check then displays a plain centre
target and eye markers using the **final fitted calibration**, with no recentering
or gain updates. Once the animal is fixating the centre, press **K**. At least
one second of fresh ADC data is required; release the key before pressing again.
The last 250 ms is selected for comparison, and the full observation is retained.

EyeLink then undergoes the same offline/close/open/start sequence normally used
before validation. The target stays visible. Once the animal fixates it again,
press **K** a second time. **Esc/F4** cancels either observation; a phase also
times out after 60 seconds. The check exits before validation and the experiment.
It does not issue rewards or overwrite the normal/desktop calibration files.

The command window prints the output folder under
`test_data/output/calibration_transition/`. `check.mat` contains the frozen
calibration, setup, resolved source paths, full eye traces (including pupil
channels), selected sample indices and restart timestamps. `Eye.v` has the same
horizontal sign convention as task recordings; `setup.horEyeSign` is retained.
`summary.csv` compares the selected windows. The post-restart EDF is transferred
to the same folder when available. Partial observations are saved on cancellation.

`beforeErrorPx` and `afterErrorPx` are each eye's estimated displacement from
the centre target. Positive X is right and positive Y is down. `changePx` is
after minus before. `beforeSDPx`/`afterSDPx` describe variation within each
selected window, not accuracy. The operator's selection is not automatic proof
that the animal was fixating; inspect the full traces and repeat if needed.

A bias already present before restart points toward the manual calibration.
A reproducible shift across restart, with comparable stable fixation, points
toward the recording transition. If both observations look accurate but normal
validation remains biased, investigate validation-specific presentation and
sampling. These comparisons identify where to investigate; they do not by
themselves prove a tracker fault. Normal `runEx` behaviour is unchanged.

To compare the centre checks with the actual validation trial routine, run:

```matlab
cd('/home/vpixx/Desktop/cops-task')
ex = runEx('t', calibrationValidationCheck=true);
```

Complete manual calibration and both **K** captures as above. Six automatic
validation trials then use the normal `runTrialFixTargx` display, fixation
criteria, timing and rewards: centre, the four outer corners of the first
validation grid (currently +/-8 degrees) in random order, and centre again.
Keep MATLAB focused; **F4** stops these trials. There is no second validation
pass or task afterward. Failed trials still count toward the six-trial limit.

Calibration updates and the Z+X recenter shortcut are disabled for these six
trials. Each trial is saved immediately in `validation.mat` beside `check.mat`,
with the frozen calibration and normal `ex.Trials` raw recordings.
`validation_summary.csv` gives each eye/axis error relative to its trial's
target. It uses normal validation's mean and time-window rules, including the
100 ms window before reward. Trials without enough suitable fixation samples
have NaN errors. Reward indicates the normal binocular fixation criterion;
it is not independent proof of accurate fixation for each eye.

Compare the centre trials against the preceding centre check to identify a
change introduced by normal validation. Compare corner errors against target
position to investigate gain or position-dependent errors. The repeated final
centre helps distinguish these from drift during the short run.
