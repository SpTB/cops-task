# Photodiode synchronization on `main`

`main` supports three display protocols. The raw settings structure defaults
to the legacy GO marker; `runEx` on this rig currently selects `binary` by
default. An explicit `syncMode` argument overrides that choice.

| Mode | Patch behavior |
| --- | --- |
| `goPulse` | White for approximately 100 ms at GO onset. |
| `binary` | White GO marker, black gap, then a saved sequence of black/white bits. |
| `off` | No GO marker or binary code. |

Both active modes use main's existing **top-right** patch (60 × 60 pixels by default), so switching
protocols does not require moving the sensor. Binary levels use `ex.idx.black`
and `ex.idx.white`; the patch rectangle and levels are saved in `trial.sync`.

```matlab
ex = runEx('t', syncMode='binary');
ex = runEx('t', syncMode='binary', syncFramesPerBit=2);
ex = runEx('t', syncMode='binary', syncSequence=myBits); % precomputed 0/1 vector
ex = runEx('t', syncMode='off');
```

The corresponding defaults are in `ex.exp.CoPs.sync` in `setDefaultsCoPs.m`.
Binary mode uses a 100 ms marker and 50 ms gap, rounded to whole display
refreshes. The payload starts at bit 1 each trial. `framesPerBit=N` holds each
bit for N submitted GO frames; its intended rate is `refreshRate/N` bits/s.
The default sequence has 32,767 bits. A supplied `sync.sequence` must contain
both 0 and 1 and be long enough for the trial; it is never silently wrapped.

The patch is drawn with the stimulus before the same asynchronous flip.
Playback keeps the existing asynchronous display pipeline, so gaze, reward,
and keyboard polling can continue while a flip is pending. The code advances
once per submitted GO frame, independently of target steps or eye samples.
A missed refresh holds the previous patch level longer; payload indices do
not jump forward to catch up. Changing the mode does not eliminate overload
or guarantee a new frame at every refresh.

## Recording and saved fields

Changing `syncMode` changes the displayed patch. It does **not** enable ADC
acquisition, change its sampling rate, or add a separate capture session.
Use the existing main-branch eye/ADC configuration to record the diode.
The hardware-free `test1` profile does not acquire photodiode voltage merely
because binary display is selected.

For binary trials with eye/ADC input enabled, the final black flip is followed
by a 100 ms capture tail (`sync.captureTailSecs`), then the ADC buffer is
drained. Reward is switched off before this wait; it adds no stimulus frames.
The trial also saves a bracketed PTB/DataPixx clock reference for decoding.

The configured diode input is zero-based physical DataPixx channel **6**.
Existing `getDefaultSettingsx.m` records channels `[0:5 6 7]` for binocular
runs and `[0:2 6]` for monocular runs, at 500 Hz by default. Match the physical
wiring and `sync.physicalChannel`; channel numbers differ from MATLAB row
numbers. The usual main acquisition path stores ADC values and timestamps
in `trial.Eye.v`, `trial.Eye.t`, and `trial.Eye.n`.

| Trial field | Meaning |
| --- | --- |
| `sync` | Resolved protocol, sequence, refresh interval, frames/bit, and physical diode channel. |
| `flip_info` | Actual PTB VBL, onset, completion, and missed-deadline values for each completed flip. |
| `frameState`, `frameStep` | Task state and stimulus step for each logged flip. |
| `frameSyncBit` | Submitted black/white level, 0 or 1. |
| `frameSyncIndex` | Payload bit index; NaN outside the payload. Repeats when frames/bit exceeds 1. |
| `frameSyncPhase` | 0=idle, 1=GO marker, 2=black gap, 3=payload. |
| `frameSyncPulse` | Legacy GO-marker mask. |
| `adcChannels` | Physical ADC channel corresponding to each acquired row. |
| `syncOffTime` | PTB timestamp of the final black-patch flip. |
| `syncClock` | PTB/DataPixx clock reference and measured timing uncertainty. |

The bit/index/phase fields describe binary playback. In `goPulse` and `off`
mode, bit/index remain NaN and phase remains zero; `frameSyncPulse` retains
the existing GO-flash mask in `goPulse` mode.

The mode and logs describe submitted frames and completed flips. Keep them
with the recorded optical trace when checking physical stimulus timing.

## Offline decoding

For a binary trial containing its acquired trace and clock metadata:

```matlab
out = decodeCoPsSyncx(ex.Trials(1), plot=true);
out.alignmentReliable
out.waveform
out.matchFraction
out.lagSec
out.clockDriftPpm
out.estimatedMissedRefreshes
out.longFlipIntervalFrameIndices
out.mismatchedFrameIndices
```

The decoder selects the configured physical channel using `adcChannels` and `sync.physicalChannel`,
using `Analog` if present or the main `Eye` ADC record. It needs a DataPixx/PTB
clock reference (`syncClock`, or `TrialStartDatapixx` with `TrialStart`), at
least 20 finite increasing sample timestamps, and at least 10 logged payload
frames. A display-only trial has no trace to decode.

For an externally acquired trace, first align its timestamps to PTB seconds
using an independent clock reference:

```matlab
out = decodeCoPsSyncx(ex.Trials(1), diodeTimesPtb, diodeVolts, sameClock=true);
```

Use `sameClock=true` only for timestamps already expressed in PTB's clock.
Options include `thresholdV`, `invert`, `maxLagSec`, `maxDriftPpm`, and
`minStableSamples`. `waveform="auto"` first tries the original continuous
light-level decoder. If that alignment is unreliable, it averages measured
voltage over a centred one-refresh window and decodes the resulting light
envelope. This handles DLP projectors whose white frames contain short light
bursts separated by darkness. The envelope threshold is learned from the GO
marker and black gap when those intervals provide usable contrast; payload
bits are not used to choose that threshold. Both paths retain the code
ambiguity, clock-drift, coverage and mismatch checks.

Use `waveform="continuous"` or `waveform="pulsed"` to force one path.
`out.waveform` reports the selected path and `out.envelopeWindowSec` reports
the averaging window (zero for continuous decoding). An explicit `thresholdV`
and `minStableSamples` apply to the selected raw/envelope waveform.

For continuous decoding, fitted lag includes display/sensor latency and
remaining clock-reference error. **For pulsed decoding, `lagSec` aligns the
averaged light envelope; it is not a direct measurement of the first optical
pulse.** See `out.lagInterpretation`. Use high-rate raw recordings to inspect
individual pulse onset times.

A reliable alignment can still contain mismatches. At 500 Hz, narrow DLP
flashes can fall entirely between samples; smoothing cannot reconstruct an
unobserved flash. `mismatchedFrameIndices` lists disagreements at logged frame
hold midpoints and does not by itself distinguish undersampling from actual
display errors. `alignmentReliable` describes identification of the code's
alignment, not confirmation of every individual displayed frame.
Repeated identical bits have no optical edge, so a single diode cannot
uniquely identify every missed refresh or verify every stimulus pixel.

Run `runtests('testCoPsSyncx')` for the hardware-free protocol/decoder tests;
validate the complete display, wiring, and recording path on the rig.

## Independent optical estimate of held refreshes

`estimateCoPsOpticalHoldsx` estimates extra refreshes from the pulsed diode
record and the saved code order. Unlike `decodeCoPsSyncx`'s
`estimatedMissedRefreshes`, it accepts **no individual flip timestamps**.
Supply the active marker/gap/payload bits, ADC timestamps and volts, nominal
refresh interval, and two increasing code indices that start white runs.
Choose anchors surrounded by a distinctive pattern, with recorded context
on both sides. The count applies only between those anchors.

The function fits the refresh frequency and phase from the measured light
pulses, then aligns the code while allowing both repeated display frames
and white flashes missed by ADC sampling. It assumes that the submitted code
order is preserved, as in the current task runner. `holdCount` is the median
count across sampled alignment paths; `viterbiHoldCount` counts the holds on
the single most likely complete path. These need not be equal.

Check `posteriorRange95`, `countResolvedUnderModel`, and sensitivity to
`holdProbability` and `missedLightProbability`. The range conditions on this
model and its probabilities; it does not cover model errors. A good alignment
score alone does not guarantee a unique count. At 500 Hz, use this as an
independent physical cross-check of VBL interval counts and flag ambiguous
windows. Do not count every unobserved white flash as a dropped frame.
Leading/trailing constant levels may prevent whole-trial optical counting;
compare optical and VBL results over the same anchor span.

Run `runtests('testCoPsOpticalHoldsx')` for known-count simulated recordings,
including held frames, unrelated preparation flashes, 500 Hz downsampling,
and wrong-code controls. This function does not access hardware or change
acquisition settings.

## Automatic audit when a session ends

`runEx` now runs the VBL/optical comparison automatically at the common final
save, after normal completion or F4. This adds no work to the trial loop.
`saveCoPsSessionx` saves the raw session first, computes the audit, writes an
enriched temporary MAT file, and replaces the raw file only after that write
succeeds. Individual optical failures leave timestamp results and a reason;
they do not prevent other trials from being audited. Unexpected audit or
audit-save failures leave the saved raw session available.

The returned `ex` and final session MAT contain:

```matlab
ex.frameAudit.summary                   % session counts and coverage
ex.Header.sessionEndReason              % 'completed', 'F4', or 'error'
a = ex.Trials(1).frameAudit;
find(a.missed)
find(a.missVBL)
find(a.missPhot)
find(a.flagged)
a.windows                              % comparisons over longer code sections
```

Every per-frame array has one row per `flip_info` row. **Row i describes the
interval after that frame, ending at flip i+1.** For example, a 25 ms interval
at 120 Hz records two extra holds of frame i. The last row and the final
active-to-blank interval are unassessed. Counts in the session summary refer
to GO intervals; `vblExtraRefreshes` counts extra refreshes, whereas
`missedFrames`, `missVBLFrames`, and `missPhotFrames` count affected intervals.

| Field | Meaning |
| --- | --- |
| `vblMissCount` | Extra refreshes calculated from actual VBL intervals. NaN when unavailable. |
| `photMedianCount` | Baseline optical model's median extra-refresh count. |
| `photLowerCount`, `photUpperCount` | Union of conditional 95% ranges from the three saved optical model settings. |
| `missed` | VBL count and optical lower bound are both positive at this interval. |
| `missVBL` | VBL count is positive and the optical upper bound is zero. |
| `missPhot` | VBL count is zero and the optical lower bound is positive. |
| `photCompared` | This interval has accepted independent optical evidence. |
| `photUncertain` | Exact optical count is unresolved or unavailable. |
| `flagged` | An uncertain possible hold, disagreement, or VBL miss without usable optical evidence requires review. This flag can accompany a `missed` label if the counts remain uncertain. |
| `classification` | Readable label: `missed`, `missVBL`, `missPhot`, `flagged`, `ok`, `unassessed`, or `outsideGO`. |
| `windowSupportedMissed` | A VBL-positive interval in a longer window whose count agrees exactly across methods/models; the optical evidence does not necessarily identify that particular interval. |

The optical fit uses only code order, raw ADC times/volts and nominal refresh
interval, never individual flip timestamps. Code windows are approximately
64 submitted frames long, with distinctive patterns around their boundaries.
Each `a.windows` row covers interval indices `startFrame:endFrame-1`, saves
VBL/optical counts and bounds, and records `exactCountAgreement`. Frame-level
labels require frame-level optical evidence; matching aggregate counts alone
do not assign an exact repeated frame within a run of identical bits.

The audit checks three hold/missed-light probability pairs:
`[.03 .15; .005 .30; .15 .05]`, with 100 sampled alignments each. Uncertainty
includes variation across those fits, not every possible model error. A
missing/unusable diode recording is **not** a `missVBL` disagreement: VBL
misses are flagged and the trial's `reason` explains why comparison failed.
Trials ending before 128 payload frames retain VBL results but skip optical
classification. The normal 500 Hz recording and saved stimulus/task data
are unchanged.

To audit an already loaded session without writing a file:

```matlab
ex = auditCoPsFrameTimingx(ex);
```

Use `runtests('testCoPsFrameAuditx')` for agreement, disagreements, repeated-bit
ambiguity, absent recordings, and normal/F4 final-save checks. Recovered
sessions can be audited using the same offline function.

## Short high-rate optical check

With the experiment stopped and the display and photodiode connected:

```matlab
results = runCoPsSyncHardwareCheckx();
out = decodeCoPsSyncx(results.trials{1}, plot=true);
```

This captures two five-second binary-patch sequences at 10 kHz on physical
ADC channel 6, using one and two display frames per bit. It uses the normal
60-pixel corner patch, RB3D display mode, saved frame timestamps and production
binary sequence generator. ESC/F4 cancels. It does not connect to EyeLink,
run behavioural trials or deliver rewards. Raw recordings and ADC status are
saved in `test_data/output/sync_hardware/`. The temporary higher sampling rate
does not change the experiment's normal ADC settings. This marker-only check
does not measure the rendering load of a full experiment trial.

The separate hardware benchmark draws its own optical marker in generated
trial copies and disables the normal patch protocol there. It continues to
compare its legacy and VBL runners independently of this option.
