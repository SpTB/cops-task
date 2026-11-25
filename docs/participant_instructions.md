# Participant instructions and practice

## Subject ID and output files

Every `runEx` profile captures the subject ID before calibration. Supply it as
`runEx('h', filePrefix="P001")`, or enter it in the subject dialog. A subject ID
already supplied by the initial questionnaire is reused. A trailing number is
automatically padded to at least three digits: `4` / `04` / `004` all become
`004`, and `t4` / `t04` / `t004` all become `t004`. Letter prefixes and their
case are preserved, as are numbers already three or more digits wide. IDs
without a trailing number, such as `demo`, are kept as entered.

The normalized ID is saved as `ex.Header.subjectID` and used for folders and
filenames. `ex.Header.subjectIDEntered` retains the original trimmed entry.
Unsafe path characters are replaced with underscores. Existing output folders
are not renamed or merged when this rule is applied.

Participant output is grouped as `<data root>/<subject ID>/YYYY.MM.DD/`,
including calibration MAT/EDF files, session data in `experimental/`, task EDF
files in `edf/`, daily logs, and temporary trial checkpoints. Repeated sessions
retain the existing timestamp and collision suffixes. Existing data are not moved.

The human rig's normal data root is `/home/nei-op4/Desktop/CoPs`. Explicit
`test1` and `mouse_mini` runs use `<repo>/test_data/output`, which is ignored by
Git. `recEx` uses that test root too, with movies under the participant's date
folder unless `outputDir` is supplied. Ordinary `runEx` reads the selected
stimulus bank; it does not generate or rewrite that bank. Whether the normal
data root is itself inside a repository depends on where the repository was
cloned.

The Command Window prints the resolved session MAT path as `CoPs output:`.
After `ex = runEx(...)`, it can also be obtained with
`fullfile(ex.Header.onlineExperimentalDirName, ex.Header.onlineFileName)`.

## Keyboard selection

On `nei-op4-Precision-3280-Compact`, ordinary `runEx()`, `runEx('h')`, and
`runEx('t')` runs default to two physical keyboards:

* **Participant:** Dell KB216 Wired Keyboard — SPACE advances instruction,
  break, and outro pages; Q requests help at pauses; ENTER requests extra
  practice when offered. The final comment screen accepts normal typing,
  Backspace, ENTER to submit, and ESC to skip.
* **Experimenter:** Mitsumi Electric Apple Extended USB Keyboard — F4 quits
  or skips final comments; F6 recalibrates at eligible pauses; trial shortcuts
  retain their existing functions. Experimenter SPACE does not advance pages.

The rig configuration is `ex.setup.keyboardDefaults` in `getDefaultSettingsx.m`.
Full device names are resolved at startup rather than storing PTB indices,
which may change when devices reconnect. Missing or duplicate name matches
stop startup with an explicit error rather than silently changing roles.
Startup prints the selected names and current indices, which are also saved
in `ex.setup.keyboards`.

```matlab
ex = runEx('h', 0); % rig defaults: two physical keyboards, overlay off
ex = runEx('t', 0, keyboardMode="shared"); % explicitly accept both roles from any keyboard
ex = runEx('h', participantKeyboard=participantID, experimenterKeyboard=operatorID);
```

Explicit indices override the named defaults. `keyboardMode="shared"` requires
omitting both indices. `keyboardMode="separate"` explicitly selects two-device
routing and uses the configured names when no indices are supplied. Portable
`test1` and `mouse_mini` previews default to shared controls in `auto` mode.
Hosts without configured keyboard defaults also retain shared controls.

Both modes keep polling keyboard state normally. During trials, focus
validation is requested only while an operator shortcut is down; idle frames
and participant SPACE do not query desktop focus. Pause controls and final
comment entry keep their existing polling/event-queue behavior.

Separate mode polls only the two chosen devices and bypasses the MATLAB
window-focus check. It temporarily floats the participant device from the X11
master keyboard so participant shortcuts cannot affect MATLAB or the desktop;
the experimenter device stays attached. This uses `xinput`, found on PATH or
in `~/.local/bin` (the op4 rig uses a user-local installation). Its resolved
command is retained for cleanup, even when MATLAB does not include that
directory on PATH. The participant keyboard is restored on normal exit and
handled errors. Final comment text is read from the
participant device through its dedicated event queue.

## Instructions and practice

Enable the three instruction pages and two practice trials with:

```matlab
ex = runEx('mouse_mini', instrOn=true); % preview with mouse input
ex = runEx('h', instrOn=true);          % human run with configured eye tracker
ex = runEx('t', instrOn=true);          % full task for solo testing without eyes
```

Only the explicit `mouse_mini` and `test1` simulation profiles use the mouse
as gaze. Ordinary `runEx()` / `runEx('h')` runs use the configured eye signal;
disabling eye input supplies no behavioral signal and earns no points.
Missing, invalid, stale, or off-screen gaze does not add reward evidence.

`'h'` (human) is the default. `'t'` runs the normal stimulus bank, task length,
reward blocks, instructions, practice (including voluntary repeats), feedback,
and task trials with eye tracking forced off. It skips all calibration and
validation, including for `eyeSource='analog'`. Trials advance by time without
gaze, `inputSource` is `'none'`, and `Eye.v`, `Eye.t`, and `mousePositions`
remain empty. Gaze-dependent points stay zero. On the op4 rig, normal `h` and `t` runs default to the two physical keyboards
described below. Use `keyboardMode="shared"` for shared-keyboard solo testing.
F6 calibration is unavailable in `t` mode.
The saved `ex.setup.runProfile` records the selected mode.

`'t'` keeps the normal DataPixx/strobe and reward switches. Use
`runEx('t', 1, 0)` to disable DataPixx strobes too (reward output is off by
default). An explicit `photodiodeRecord=true` still enables independent ADC
recording without eye data. The `test1` and `mouse_mini` profiles retain their
short mouse-driven preview behavior.

`instrOn` in `setDefaultsCoPs.m` controls whether this flow runs. An explicit
runEx argument overrides that setting. Instruction pages use regular body
text; only the final SPACE sentence is bold. SPACE requires a fresh press and
release, using the configured participant keyboard. Experimenter F4 remains
available. The layout wraps and scales for the logical task canvas and redraws
when the preview is resized.

The maximum bonus stated in the text is configured in `setDefaultsCoPs.m`:

```matlab
pay.max_bonus_dollar = 25; % maximum per trials_per_hour paid trials
pay.trials_per_hour = 180;
instr.targetVisibility = 1;
```

The hourly bonus amount is saved as `ex.exp.CoPs.pay.max_bonus_dollar`.
The welcome text quotes that amount scaled by planned paid trials divided by
`pay.trials_per_hour`: $12.50 for 90 paid trials or $50 for 360 with the
defaults. Both instruction practices are excluded. The final payout uses the
same scaling based on eligible trials actually recorded. All money settings are in `pay`;
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
6. Separate practice feedback. ENTER requests another dynamic-background
   practice trial; SPACE continues. Up to three extra trials are allowed.
7. Ready page explaining automatic trials, configured self-paced breaks, and
   asking the participant to keep their head still before pressing SPACE to
   start the main task.
8. After the task, an outro showing earned points, average points per task
   trial, the cash bonus, and SPACE to continue.
9. An optional participant feedback text box asking what worked well, what was
   confusing/difficult/uncomfortable, and "Did you notice anything about the task
   that wasn't explicitly explained?" Type a comment and press ENTER
   to submit, or press ESC to skip. Backspace edits the response; long comments
   wrap and scroll within the box. The configured participant keyboard supplies
   text; experimenter F4 skips this page. Q and SPACE are ordinary text here.

Feedback is saved as `ex.ParticipantFeedback.text`, with `submitted`, `skipped`,
screen `on`/`off` timestamps, and the prompt. A skipped draft is retained.
The feedback page follows an acknowledged normal or early bonus outro, and is
checkpointed to the session MAT before shutdown. Set `ex.exp.CoPs.fbOn = false`
in `setDefaultsCoPs.m` to disable it (`true` enables it). The optional
`runEx('mouse_mini', participantFeedback=false)` argument overrides that default.
Unattended
`showEndScreen=false` runs, movie recordings, and handled errors do not open it.
On Linux/X11, shared-keyboard feedback uses a temporary X11 keyboard grab so
typing and the submit key cannot spill into MATLAB's command window. A small
Python 3 helper forwards characters to the feedback box and releases the grab
when the screen exits or its parent process closes. Already isolated participant
keyboards continue to use the PTB queue directly.

Experimenter F4 also shows the outro when at least one paid trial has completed;
an unfinished trial is excluded from payment. `ex.Payout` is calculated and
saved even when the run stops early or only practice has run (a zero payout).
See [Early termination and recovery](participant_bonus.md#f4-and-early-termination).

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
`ex.Instructions.pages`. `max_bonus_dollar` in each page is the quoted session
cap; `hourly_max_bonus_dollar`, `trials_per_hour`, and `planned_paid_trials`
record how it was scaled. The original top-level `ex.Instructions` fields still
describe the welcome page. Completed trial data are saved before showing the
next page, and page acknowledgements are checkpointed before the next trial.

Practice is saved separately in `ex.Instructions.Trials` (two required trials,
plus up to three voluntary dynamic repeats) with
`trialNumber` (1 through 5), `instructionTrialNumber` (1 for gray, 2 for dynamic),
`instructionRepeatNumber` (0 for required trials, 1 through 3 for repeats),
`trialType='instructionPractice'`, `isInstructionTutorial=true`,
`isTutorialTrial=true`,
`runPhase='instructionPractice'`, and
`pointsCountTowardTotal=false`. Its earned points and reward/beep events are
retained, but excluded from `ex.totalPoints` and all displayed session totals.
The first actual task trial is `ex.Trials(1)`, with `trialNumber=1` and
`trialType='task'`. `ex.j`, `ex.finish`, condition schedules, reward blocks,
and regular pause schedules refer only to task trials. Practice has separate
loop counters in `ex.Instructions.loopcnt`. Individual practice checkpoints are
`instruction_practice/practice1.mat`, `practice2.mat`, and optional
`practice3.mat` through `practice5.mat` under the session's
trial directory, each containing a `Trials` variable. The directory is recorded
in `ex.Header.onlineInstructionDirName`. Task checkpoints start at `tr1.mat`.
After the final session MAT is saved, temporary task checkpoints are removed;
the `instruction_practice` folder and its files are retained.
The session MAT contains both collections, including their gaze, calibration,
timing, points and reward records. Raw trial-number strobes use the ordinal
within each phase, restarting at 1 for the task; use the saved timestamps to
distinguish practice from task in continuous recordings. Earlier saved sessions
keep their original combined `ex.Trials` layout.

Practice feedback explicitly says these points do not count toward winnings,
then asks for SPACE to continue to the next instruction page. After each
dynamic practice, ENTER instead requests another freshly generated dynamic
trial, with the remaining repeat count displayed. There can be at most four
dynamic attempts (one required plus three extra); the ENTER option disappears
after the third repeat. Holding ENTER does not request another trial: each
feedback screen requires a fresh press and release from the participant
keyboard. `practiceRepeatRequested` logs the choice in each practice record.
The ready page appears once the participant continues or uses all repeats.
This feedback is shown even if normal between-trial pauses are disabled.
Regular pause cadence starts with the first task trial after practice.
The reward accumulator and reward-event count reset in each trial as usual.

The ready page reads `ctl.between_trial_pause_mean` and
`ctl.between_trial_pause_range`. For a mean of 5 and range of 1 it states an
average of 5 trials and a range of 4 to 6. A zero range uses "every 5 trials";
mean 1/range 0 says "after every trial." If `advance_trial_with_space=false`,
the page describes automatic trials without promising scheduled breaks.

## Questions without head movement

Q remains available on every instruction page, practice feedback, scheduled
between-trial pause, and final outro. Participant screens do not display
instructions to press Q for questions. The ready page retains its reminder
to keep the head still throughout the task.
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
per pause; another Q replaces it, and continuing closes it. The experimenter
can also click the **X** inside the popup's upper-right corner to dismiss just
the alert. This does not advance the participant's page or resume the task.

For example, choose the experimenter monitor using Psychtoolbox screen IDs:

```matlab
Screen('Screens')
ex = runEx('h', overlayScreen=0); % Linux example: Q popup uses experimenter X-screen 0
```

If Psychtoolbox exposes no separate experimenter screen, a nonmodal MATLAB
message box provides the preview fallback. On Linux, separate X-screens are
needed for monitor-specific routing, as for the existing experimenter overlay.
Shared-keyboard testing accepts SPACE, Q, and experimenter controls from any
connected keyboard. Pause controls work regardless of desktop window focus,
including after a question popup. SPACE still requires a fresh press and release.
Separate rig keyboards retain their configured participant and experimenter roles.
If the dedicated popup cannot open, the code tries the desktop
message box; if neither can open, the console still reports the question.
Windows physical monitors use IDs 1 and above; see the
[Psychtoolbox screen mapping](https://psychtoolbox.org/docs/Screen-Screens).

Request times and notification targets are saved in
`ex.Instructions.pages(i).questionRequests`,
`ex.Trials(i).pauseQuestionRequests`, and `ex.Outro.questionRequests` as
applicable. Targets are `experimenterPopup`, `experimenterDesktop`, or `console`.

## Recalibration at a pause

On the experimenter keyboard, press and release **F6** during any instruction
page, practice feedback, or between-trial pause to repeat calibration, then
continue without the custom `setDefaultsValid` validation procedure.
F6 also acknowledges that pause; no extra SPACE is needed. Remaining
instruction pages still appear in their normal order.
The final outro has no next trial and does not offer recalibration. Mouse
profiles ignore F6 at pauses because there is no gaze tracker to calibrate.
During a live trial, F6 retains its existing reward-center overlay shortcut.

With dedicated devices, participant F6 is ignored, as are experimenter
SPACE/Q. Shared-keyboard preview uses the same keyboard for both roles.
Calibration is deferred until `runTrialTaskCoPsx` returns, so completed trial
data are saved before entering hardware setup. The trial counter, point
totals, condition schedules, filename, and task data remain intact; successful
calibration resumes with the next trial, without repeating the completed one.

For native EyeLink input, the existing tracker setup UI runs offline, then
the task resumes without launching the custom validation grid. EyeLink's own
validation remains available within tracker setup. The session EDF stays open;
recording restarts into the same file for subsequent trials.
`COPS_RECALIBRATION_BEGIN/END` messages delimit it. Initial validation settings
are unchanged. Any previous custom CoPs pixel correction is discarded because
it belongs to the old tracker calibration. Calibration feedback tones are
disabled during this repeat setup to avoid opening another audio device;
task reward beeps remain enabled according to `soundOn`. Native EyeCal
snapshots reference the shared session EDF rather than creating another EDF.

For legacy analog input (`eyeSource='analog'`), F6 runs `calibrateEye2vx` on a
copy of the session, with calibration-file loading and custom validation
disabled. It saves its separate EyeCal MAT and returns the new fit
without replacing task trials, session counters, or the open task EDF.
Calibration aborts or errors end the session with data saved.

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
3. Experimenter F6 at a pause opens tracker setup, skips custom validation,
   and resumes the correct next trial with unchanged points and conditions.
4. Repeat calibration twice, and fail one setup; inspect the saved
   history, per-trial calibration, session EDF continuity, and error/abort save.
5. Check reward beeps after recalibration, ordinary trial frame timing,
   instruction readability, and practice/main transitions.
