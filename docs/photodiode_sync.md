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
