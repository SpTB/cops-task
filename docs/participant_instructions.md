# Participant instructions and practice

Enable the three instruction pages and two practice trials with:

```matlab
ex = runEx('mouse_mini', instrOn=true); % preview with mouse input
ex = runEx('t', instrOn=true);          % configured gaze-input rig
```

`instrOn` in `setDefaultsCoPs.m` controls whether this flow runs. An explicit
runEx argument overrides that setting. Instruction pages use regular body
text; only the final SPACE sentence is bold. SPACE requires a fresh press and
release, using the configured participant keyboard. Experimenter F4 remains
available. The layout wraps and scales for the logical task canvas and redraws
when the preview is resized.

The maximum bonus stated in the text is configured in `setDefaultsCoPs.m`:

```matlab
pay.max_bonus_dollar = 25;
instr.targetVisibility = 1;
```

The bonus cap is saved as `ex.exp.CoPs.pay.max_bonus_dollar` and is shared by
the welcome text and the payout calculation. All money settings are in `pay`;
see [Participant bonus](participant_bonus.md) for thresholds and curves.
The second setting is saved as `ex.exp.CoPs.instr.targetVisibility`,
must be between 0 and 1, and controls the second practice trial's visibility.
It is independent of the main-task visibility schedule.

After calibration the flow is:

1. Welcome page explaining tracking, points, beeps, and the maximum bonus.
2. Practice trial 1: two full-visibility targets on a constant gray background.
3. Practice feedback, explicitly excluding the points from winnings.
4. Instructions explaining changing backgrounds and clearer/more blurred targets.
5. Practice trial 2: two targets on a dynamic background, using
   `instr.targetVisibility` (default 1).
6. Separate practice feedback.
7. Ready page explaining automatic trials, configured self-paced breaks, and
   asking the participant to keep their head still and press Q if they have
   questions, now or during any break, before pressing SPACE to start the main task.
8. After the task, an outro showing earned points, average points per task
   trial, the cash bonus, and SPACE to finish.

Both practice trials use normal moving texture targets, full coherence,
spatially uniform reward weighting, the normal trial duration, and the soundOn
setting. Dynamic practice uses the first configured dynamic noise level; if
the main task has only fixed/null backgrounds, it uses noise level 1. The
required stimulus folder is checked by the normal preflight validation.

The two practice trials are additional to the existing tutorial/pursuit/pre/main
blocks. `testTrials` continues to specify main trials only. Practice does not
replace main-task conditions or select/save a reward-landscape center.

The exact copy, amount, screen timestamps, stage (`welcome`, `dynamic`, or
`ready`), and acknowledgement of every page are saved in
`ex.Instructions.pages`. The original top-level `ex.Instructions` fields still
describe the welcome page. Completed trial data are saved before showing the
next page, and page acknowledgements are checkpointed before the next trial.

Practice is logged in `ex.Trials` with `isInstructionTutorial=true`,
`isTutorialTrial=true`, `instructionTrialNumber` (1 or 2),
`runPhase='instructionPractice'`, and
`pointsCountTowardTotal=false`. Its earned points and reward/beep events are
retained, but excluded from `ex.totalPoints` and all displayed session totals.
Practice feedback explicitly says these points do not count toward winnings,
then asks for SPACE to continue to the next instruction page. This transition
is shown even if normal between-trial pauses are disabled. Regular pause cadence
starts after both practice trials.
The reward accumulator and reward-event count reset in each trial as usual.

The ready page reads `ctl.between_trial_pause_mean` and
`ctl.between_trial_pause_range`. For a mean of 5 and range of 1 it states an
average of 5 trials and a range of 4 to 6. A zero range uses "every 5 trials";
mean 1/range 0 says "after every trial." If `advance_trial_with_space=false`,
the page describes automatic trials without promising scheduled breaks.

## Questions without head movement

Every instruction page, practice feedback, and scheduled between-trial pause
offers Q for questions and reminds the participant to keep their head still.
Q remains available on the final outro, without a displayed question prompt.
Q is read from the participant keyboard; Q on a separate
experimenter keyboard does not trigger it. A held Q produces one request until
released and pressed again. Q does not advance the page; SPACE still requires
a fresh press and release. No question alerts are generated during trials.

Q opens a **new, separate GUI window** saying the participant has a question
and asking the experimenter to come over. With multiple displays, it opens
centered on `overlayScreen` if specified, otherwise on the first screen other
than the participant's (excluding Windows' spanning screen 0 during automatic
selection). This works with `overlayOn=false` as well. It does not
replace or draw into the existing experimenter overlay. One alert remains open
per pause; another Q replaces it, and continuing closes it.

For example, choose the experimenter monitor using Psychtoolbox screen IDs:

```matlab
Screen('Screens')
ex = runEx('t', overlayScreen=0); % Linux example: Q popup uses experimenter X-screen 0
```

If Psychtoolbox exposes no separate experimenter screen, a nonmodal MATLAB
message box provides the preview fallback. On Linux, separate X-screens are
needed for monitor-specific routing, as for the existing experimenter overlay.
When testing with one shared keyboard, refocus the task window after
closing any popup. With separate rig keyboards, pause controls work regardless of
desktop focus. If the dedicated popup cannot open, the code tries the desktop
message box; if neither can open, the console still reports the question.
Windows physical monitors use IDs 1 and above; see the
[Psychtoolbox screen mapping](https://psychtoolbox.org/docs/Screen-Screens).

Request times and notification targets are saved in
`ex.Instructions.pages(i).questionRequests`,
`ex.Trials(i).pauseQuestionRequests`, and `ex.Outro.questionRequests` as
applicable. Targets are `experimenterPopup`, `experimenterDesktop`, or `console`.

## Recalibration at a pause

On the experimenter keyboard, press and release **F6** during any instruction
page, practice feedback, or between-trial pause to repeat calibration **and
validation**, then continue. F6 also acknowledges that pause; no extra SPACE
is needed. Remaining instruction pages still appear in their normal order.
The final outro has no next trial and does not offer recalibration. Mouse
profiles ignore F6 at pauses because there is no gaze tracker to calibrate.
During a live trial, F6 retains its existing reward-center overlay shortcut.

With dedicated devices, participant F6 is ignored, as are experimenter
SPACE/Q. Shared-keyboard preview uses the same keyboard for both roles.
Calibration is deferred until `runTrialTaskCoPsx` returns, so completed trial
data are saved before entering hardware setup. The trial counter, point
totals, condition schedules, filename, and task data remain intact; successful
calibration resumes with the next trial, without repeating the completed one.

For native EyeLink input, the existing tracker setup UI runs offline, followed
by the configured custom validation grid. The session EDF stays open;
recording restarts into the same file for validation and subsequent trials.
`COPS_RECALIBRATION_BEGIN/END` messages delimit it. F6 explicitly requests both
steps even if initial `nativeValidation=false` or `calib.validate=false` was
used. Calibration feedback tones are disabled during this repeat setup to
avoid opening another audio device; task reward beeps remain enabled according
to `soundOn`. Native EyeCal snapshots reference the shared session EDF rather
than creating another EDF.

For legacy analog input (`eyeSource='analog'`), F6 runs `calibrateEye2vx` on a
copy of the session, with calibration-file loading disabled and validation
enabled. It saves its separate EyeCal/validation MAT and returns the new fit
without replacing task trials, session counters, or the open task EDF.
Calibration/validation aborts or errors end the session with data saved.

`ex.Recalibration.history` records request source, upcoming trial number,
on/off times, completion, old/new calibration, and any error. Pending requests
are checkpointed before calibration and results afterward. Calibration and
validation do not earn task points or change the payout denominator. Each new
task trial saves a compact `eyeCal` snapshot (without the validation traces);
`reconstructEyePx` uses it so later recalibrations cannot change earlier
trials' reconstructed gaze. Older data without that field use the session fit.

Automated checks:

```matlab
results = runtests({'testCoPsInstructionsx.m','testCoPsTrialFeedbackx.m', ...
    'testCoPsRunExOverlayx.m','testCoPsMiniStimulusBoundsx.m', ...
    'testCoPsBetweenTrialPausesx.m','testCoPsKeyboardRoutingx.m', ...
    'testCoPsRecalibrationx.m','testCoPsTrialCalibrationx.m'});
assertSuccess(results);
```

Display/keyboard/tracker tests use mocks and never open real popups or connect
to hardware. On the rig, verify:

1. Q on the participant keyboard opens a new window on the intended monitor
   on each pause type, including the outro, without replacing the overlay.
2. Held Q gives one request; SPACE closes it and advances. Participant F6/F4
   and experimenter Q/SPACE have no task action with separate keyboards.
3. Experimenter F6 at a pause opens tracker setup, then custom validation,
   and resumes the correct next trial with unchanged points and conditions.
4. Repeat calibration twice, and abort one validation; inspect the saved
   history, per-trial calibration, session EDF continuity, and error/abort save.
5. Check reward beeps after recalibration, ordinary trial frame timing,
   instruction readability, and practice/main transitions.
