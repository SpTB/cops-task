# Binary photodiode synchronization

Implemented for the `human` branch. Software checks use simulated signals and
mocked Screen/DataPixx calls. Physical display, sensor, voltage, and acquisition
timing still require validation on the rig.

## Start here

Preview the top-right patch without acquisition hardware:

```matlab
ex = runEx('mouse_mini', syncMode='binary', testTrials=3);
```

Fullscreen preview, with each bit held for two display refreshes:

```matlab
ex = runEx('test1', syncMode='binary', syncFramesPerBit=2, testTrials=3);
```

Later, on the rig with DataPixx and the photodiode connected:

```matlab
ex = runEx('test1', syncMode='binary', photodiodeRecord=true, ...
    photodiodeSampleRate=2000, testTrials=3);

out = decodeCoPsSyncx(ex.Trials(1), plot=true);
```

`photodiodeRecord=true` is an explicit hardware opt-in, including in mouse test
profiles. It enables DataPixx ADC acquisition without enabling EyeLink, reward
hardware, or experiment strobes. Omitting it keeps mouse profiles hardware-free.
Existing rig runs that already enable the ADC continue recording it normally.
Acquisition is stopped on function exit, including errors and early returns.

The default display mode remains `goPulse`: the existing 100 ms white GO marker.
Use `syncMode='binary'` to enable this protocol, or `syncMode='off'` to disable
the patch. Default settings are near the top of `setDefaultsCoPs.m`.

## One sequence or a different sequence each trial?

One sequence reused from bit 1 on every trial is sufficient when the trial
boundaries are known. This is the implemented policy. The actual vector is
prepared once per run and saved in the session and each trial, so recovered
per-trial MAT files also contain everything needed for decoding.

By default the vector contains one full 32767-bit period of a 15-bit maximal
length sequence. The implemented recurrence is
`b(k) = xor(b(k-1), b(k-15))`, with 15 initial bits taken MSB-first from the
nonzero `sync.seed` (1 to 32767). Generation does not change MATLAB's global RNG
or the stimulus random sequence. No Communications Toolbox is needed.

The code never wraps during a trial. Each trial starts with a fresh playback
cursor at zero. Preflight checks require enough bits for the trial's allocated
duration, including its timing margin; exhaustion also raises a clear error.
At 60 bits/s the default vector lasts about 546 seconds, excluding the preamble.

To use a pregenerated code:

```matlab
loaded = load('my_sync_code.mat', 'bits');
ex = runEx('mouse_mini', syncMode='binary', syncSequence=double(loaded.bits(:)'));
```

Alternatively set `sync.sequence` in `setDefaultsCoPs.m`. A supplied vector must
contain both 0 and 1 and be long enough for the entire trial allocation. A short
alternating pattern such as `010101...` creates ambiguous alignments; the decoder
reports low alignment confidence for such a pattern. Different codes per trial
are useful if trial identity must be recovered from an otherwise unlabeled
continuous recording; they are not required for the current trial-indexed logs.

## Patch rate versus sampling rate

These are separate clocks:

* **Display/bit rate:** at most one new bit per physical screen refresh.
  `syncFramesPerBit=N` holds each bit for N submitted display frames, making the
  intended bit rate `refreshRate/N`. This is independent of target-step rate.
* **Photodiode ADC rate:** the frequency at which voltage is measured.
  `photodiodeSampleRate` defaults to 500 samples/s when acquisition is explicitly
  enabled. It can be changed independently of the 500 Hz behavioral input
  polling. The rate option applies to the ADC schedule, including other channels
  acquired in that schedule; it does not change the EyeLink's configured rate.

| Display refresh | Refreshes per bit | Intended bits/s | ADC samples/bit at 500 Hz |
| --- | --- | --- | --- |
| 60 Hz | 1 | 60 | 8.33 |
| 60 Hz | 2 | 30 | 16.67 |
| 120 Hz | 1 | 120 | 4.17 |
| 144 Hz | 1 | 144 | 3.47 |

Thus a 60 Hz monitor cannot display 500 independent bits/s, even if the ADC or
eye tracker samples at 500 Hz. Adjacent bits can be identical, so bit rate is
also different from the number of observed light transitions per second.

For initial validation, 60 bits/s and 500 Hz ADC sampling are reasonable. A
2 kHz ADC schedule gives more samples per bit and a 0.5 ms sampling grid,
compared with 2 ms at 500 Hz. This does not guarantee that level of physical
timing accuracy: monitor response, sensor bandwidth, scanout position, and
clock synchronization must be measured. Validate supported ADC rate, channel
count, input range, and buffer capacity on the actual acquisition hardware.
Hosts without an ADC buffer-size setting use the existing rig default of
900000 buffer frames; include that setting in the hardware capacity check.

## What is displayed and recorded

In binary mode the existing square at the top-right of the participant display
is explicitly black or white, drawn after all stimulus/overlay content and
presented by the same flip as the stimulus. Its default size is the existing
`ex.synch.PSz` (120 logical pixels). Windowed preview scales the whole canvas;
physical patch size must be checked in fullscreen on the rig.

Playback covers the GO period:

1. White GO marker: approximately 100 ms, rounded to a whole number of refreshes.
2. Black gap: approximately 50 ms, rounded to whole refreshes.
3. Binary payload, beginning at bit 1.

The marker occupies the first GO frames; it does not add time before the task
or extend the trial. The patch is black during other trial phases and on the
between-trial/final feedback screens. The same initial GO marker remains
available to existing onset-alignment analysis. Binary phase information is
stored separately from the legacy `frameSyncPulse` mask.

The cursor advances once per submitted GO frame. It does not advance from wall
clock time, reward events, eye samples, or target steps. A late flip holds the
previous bit for longer; it does not silently skip forward in the code. Binary
flips request the next refresh relative to the preceding VBL timestamp. The
existing task's input loop and target-step logic remain in place.

Each `ex.Trials(i)` records:

| Field | Meaning |
| --- | --- |
| `sync` | Resolved protocol, full sequence, generator/seed, intended rate, frames/bit, patch rectangle, ADC channel |
| `flip_info` | PTB VBL, stimulus-onset, flip-completion timestamps and Missed value |
| `frameStep`, `frameState` | Stimulus step and state corresponding to each flip |
| `frameSyncBit` | Submitted patch level, 0 or 1; one entry per logged flip |
| `frameSyncIndex` | Payload bit index; NaN outside the payload; repeats when frames/bit > 1 |
| `frameSyncPhase` | uint8: 0=idle, 1=GO marker, 2=black gap, 3=payload |
| `frameSyncPulse` | Legacy GO marker mask; true only during the marker |
| `syncOffTime` | PTB timestamp of the black patch on the final blanking flip |
| `syncClock` | Paired PTB/DataPixx clock reference and its measured half-roundtrip uncertainty |
| `Analog.v`, `Analog.t`, `Analog.n` | ADC voltages, DataPixx sample timestamps, sample count |
| `adcChannels` | Physical zero-based channel associated with each ADC row |

The default photodiode input is physical DataPixx channel 6. Change
`sync.physicalChannel` in `setDefaultsCoPs.m` to match the rig. The decoder uses
the channel metadata, rather than assuming a particular row of `Analog.v`.
Native EyeLink data remain in `Eye` on the tracker clock. Legacy analog-eye
runs retain `Eye` and also expose the ADC trace as `Analog`; the diode channel
does not receive eye gain/position calibration.

The existing `checkSynch` examines the GO marker only. Use `decodeCoPsSyncx` for
the full binary protocol; its frame-rate edges should not be fed through the
old 20 ms edge-separation rule.

## Offline decoding and interpretation

```matlab
out = decodeCoPsSyncx(ex.Trials(1), plot=true);
out.alignmentReliable
out.matchFraction
out.lagSec
out.clockDriftPpm
out.longFlipIntervalFrameIndices
out.estimatedMissedRefreshes
out.mismatchedFrameIndices
```

The decoder maps recorded ADC timestamps to PTB time using `syncClock`, detects
both edge polarities using a Schmitt threshold and stable-sample rule, searches
for code alignment within +/-0.25 s and +/-2000 ppm drift, then refines the fit
using matched edges. It also detects ambiguous code alignments. Threshold,
polarity, search ranges, and stable-sample count can be overridden:

```matlab
out = decodeCoPsSyncx(ex.Trials(1), thresholdV=0.3, invert=false, ...
    maxLagSec=0.5, maxDriftPpm=2000, minStableSamples=2, plot=true);
```

Edge times are estimated at the midpoint of the two bracketing ADC samples,
avoiding a systematic half-sample delay from using the first sample after a
crossing. They remain estimates limited by the sampling interval and sensor
response.

For an externally recorded trace, first convert its timestamps to PTB seconds
using an independent shared-clock reference, then pass the trace explicitly:

```matlab
out = decodeCoPsSyncx(ex.Trials(1), diodeTimesPtb, diodeVolts, sameClock=true);
```

Do not set `sameClock=true` for unrelated clocks. The fitted lag includes
physical display/sensor delay and any remaining clock-reference error. Drift
is fitted over the trial; the reference is not a substitute for validating the
acquisition clock relationship. `alignmentReliable` means that code alignment
is sufficiently confident; inspect mismatches separately even when it is true.

`estimatedMissedRefreshes` comes from logged flip gaps relative to the measured
refresh interval. `mismatchedFrameIndices` compares the measured light level
with the expected level at the midpoint of each actual frame hold. It does not
prove every stimulus pixel was correct. Repeated equal bits have no transition,
so a single binary photodiode cannot uniquely localize every missed refresh.
Keep the software flip logs and optical trace together.

## Hardware validation checklist

1. Use fullscreen on the intended rig, at the intended fixed refresh rate.
   Attach the sensor over the entire patch and shield it from surrounding light.
2. Record black and white levels. Check input range, saturation, polarity,
   response time, and the physical ADC channel. Confirm the patch fits under
   the sensor and does not overlap the stimulus area used for analysis.
3. Start at two refreshes/bit, then test one refresh/bit. Record several trials
   at 500 Hz and, if supported, 2 kHz. Check that no ADC buffer overflow occurs.
4. Check the GO marker, code restart at bit 1, and black between trials.
5. Run the decoder and inspect its plot, match fraction, edge residuals,
   alignment confidence, longest flip gap, and mismatch locations.
6. In a dedicated timing test, introduce a known one-refresh hold and verify
   that logs and optical recording detect it. Do not inject delays into a
   participant session. Repeat with the experimenter overlay and audio enabled.
7. Measure repeatability across trials and the lag between patch illumination
   and the stimulus region of interest. A top-right sensor measures that scanout
   location, not automatically the center or bottom of the display.

## Automated verification

```matlab
results = runtests({'testCoPsSyncx.m','testCoPsSyncHardwarex.m', ...
    'testCoPsRunExOverlayx.m','testCoPsTrialFeedbackx.m','testCoPsTestProfilex.m'});
assertSuccess(results);
```

Tests cover the full LFSR period, RNG isolation, repeatable trial resets, marker
and gap frames, bit holding, code exhaustion, hardware-independent options,
black/white drawing and flip order, ADC draining and overflow, and decoding
simulated noise, latency, clock drift, a late refresh, inverted signals, channel
mapping, physical bit mismatches, missing data, and ambiguous alternating codes.
These tests validate software behavior; they do not validate real hardware.

References: [PTB Screen Flip](https://psychtoolbox.org/docs/Screen-Flip),
[PTB ADC scheduling](https://psychtoolbox.org/docs/Datapixx-SetAdcSchedule),
[PTB timing limitations](https://psychtoolbox.org/docs/SyncTrouble),
[maximum-length PN sequences](https://www.mathworks.com/help/comm/ref/comm.pnsequence-system-object.html).
