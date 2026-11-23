# Presentation movies with recEx

```matlab
ex = recEx();
ex.MovieFiles{1}              % absolute path to the first MP4
```

By default this previews and exports **one ten-second trial**, with two targets,
visibility 1, a static gray/null background (`-1`), a flat reward landscape,
and a visible mouse. It uses
the hardware-free, windowed `mouse_mini` task. No instruction/practice trials,
between-trial screens, final outro, experimenter overlay, or photodiode patch
are shown. Reward beeps and a green reward outline are enabled by default and
can be disabled independently.

```matlab
ex = recEx(length=5, targetNum=2, visibility=1, background=-1, mouseVisible=true);
ex = recEx(8, background=1, visibility=0.5, mouseVisible=false);
ex = recEx(nTrials=3, length=4, fps=60, outputDir="presentation_movies");
ex = recEx(displayReward=true, rewardMarker=true);
ex = recEx(rewardLandscape=1); % Gaussian peak in the top-left quadrant
```

The first numeric argument is an optional shortcut for `length`. All other
arguments use name-value syntax. Options:

| Argument | Default | Meaning |
| --- | --- | --- |
| `length` | `10` | Stimulus/movie length in seconds, rounded to a movie frame |
| `targetNum` | `2` | One or two targets |
| `visibility` | `1` | Target visibility from 0 to 1, including null/fixed backgrounds |
| `background` | `-1` | `-1`: static gray/null; `0`: fixed texture; positive integers: dynamic noise levels from the configured stimulus set |
| `rewardLandscape` | `0` | `0`: flat; `1`: top-left; `2`: top-right; `3`: bottom-left; `4`: bottom-right |
| `mouseVisible` | `true` | Show the mouse in the preview and include its recorded path as an arrow in the movie |
| `displayReward` | `true` | Embed a beep at each earned-point crossing in the MP4's audio track |
| `rewardMarker` | `true` | Flash a green outline around the stimulus square at each earned-point crossing, in the preview and MP4 |
| `rewardMarkerDuration` | `0.2` | Green-outline duration in seconds; nearby crossings extend the flash |
| `nTrials` | `1` | One separate movie per trial |
| `fps` | `30` | Movie frame rate (positive integer, up to 240) |
| `movieSizePx` | `[1280 720]` | Output `[width height]`, both even |
| `windowSizePx` | `[960 540]` | Requested preview window size |
| `outputDir` | `""` | Parent folder for movies; empty uses the session's `movies` folder |
| `stimulusDir` | `""` | Generated bank/session directory; empty uses the bundled test bank |
| `filePrefix` | `"demo"` | Prefix for the accompanying session data and movie subfolder |

The stimulus updates at the existing configured rate (normally 30 Hz). A 60 fps
movie repeats each stimulus step twice; it does not introduce extra motion.
The full logical scene is fitted into the output size without cropping, adding
black borders if the aspect ratios differ. Visibility and target count apply
to the null-background condition as well as fixed/dynamic backgrounds.

Use `recEx(stimulusDir=bank)` to record a bank produced by `genDailyStimCorey`.
See [stimulus generation](stimulus_generation.md) for the complete workflow.

Move the mouse during the preview if you want to demonstrate tracking. The
mouse starts centered in the preview. The movie renders a software arrow using
the recorded mouse path, because GPU frame export does not include the desktop
cursor. No arrow is drawn while the recorded mouse is outside the task area.

## Reward landscape

`rewardLandscape=0` sets the spatial multiplier to 1 everywhere. Points still
require accurate tracking. Options 1-4 select the task's configured corner
presets and retain the Gaussian strength (`ctl.gauss_scalar`) and width
(`rew.gauss_sigma`) from `setDefaultsCoPs`. The default peak coordinates in
normalized stimulus-square units are:

| Value | Peak position | `[x y]` |
| --- | --- | --- |
| `1` | Top-left quadrant | `[0.25 0.25]` |
| `2` | Top-right quadrant | `[0.75 0.25]` |
| `3` | Bottom-left quadrant | `[0.25 0.75]` |
| `4` | Bottom-right quadrant | `[0.75 0.75]` |

These are the existing quadrant centers, inset from the square's edges.
The selected peak stays fixed across the recorded trials, independently of
free/random center settings or the daily center cache. The requested option
is saved in `ex.setup.recording.rewardLandscape`; trial data retain the resolved
`gauss_scalar` and `gaussRewardCenterNorm`. Visual `background` is independent
of the reward landscape.

## Reward cues

Choose either cue or both:

```matlab
ex = recEx(displayReward=true, rewardMarker=false); % recorded beeps only
ex = recEx(rewardMarker=true, displayReward=false); % green outline only
ex = recEx(displayReward=true, rewardMarker=true); % both
```

Both use the actual reward-crossing timestamps saved in `Trials(i).times.reward`.
Fractional points do not create cues. The outline surrounds the stimulus square,
rather than the entire preview window, and lasts 0.2 seconds by default.

Each recorded beep uses the live reward cue's 800 Hz, 30 ms waveform, synthesized
into a stereo 48 kHz AAC track. This does not record a microphone or desktop audio,
and does not require a sound device. The preview remains silent; the beeps are
embedded during export. No crossings produces a silent track. Overlapping beeps
are mixed; a beep at the clip's end is trimmed to preserve the requested duration.
AAC encoding can add a small amount of container padding (about 21 ms), while
the video retains the requested frame count.

Reward events and the mouse path are mapped to the generated stimulus steps, so
they follow the movie's timeline even if the live preview runs slowly. Metadata in
`Trials(i).movie` includes `rewardTimes` (seconds from movie onset),
`rewardBeepCount`, `audioSampleRate`, and `rewardMarkerFrames`.

## Files and export process

The console prints the absolute movie directory and each completed file.
Default output is:

```text
test_data/output/demo/YYYY.MM.DD/movies/<session-name>/trial_001.mp4
```

The `demo` folder is the default subject ID; `filePrefix` selects another ID.
An explicit `outputDir` also gets a per-session subfolder. Session naming
follows the regular filename mechanism, using `filePrefix`. Existing movies
are preserved by adding a numeric suffix if a trial filename already exists.
Normal session/trial MAT data are saved too. The returned `ex.MovieFiles` lists
successful exports; `ex.Trials(i).movie` records frame count, duration, size,
source step indices, and the sampled mouse path.

Encoding happens **after** each live trial while its generated textures are
still available. The exporter redraws those same textures to an offscreen
canvas and encodes the requested frame sequence. This provides a clean,
fixed-duration presentation movie without readback/encoding inside the live
trial timing loop. It excludes pretrial fixation and all feedback screens.
It represents the generated sequence, rather than reproducing any display
frame drops or window resizing seen during the preview.

F4 stops the preview. If stimulus presentation had started, the reached steps
are exported as a shorter movie; exiting before stimulus onset creates no
movie. Encoder failures retain their error in the session MAT and are reported
by `recEx`. The encoder and offscreen canvas are released on errors or Ctrl+C.

MP4 export uses Psychtoolbox/GStreamer with the `x264enc` H.264 Main-profile encoder and
`mp4mux`. Both must be installed in the GStreamer runtime used by Psychtoolbox.
Enabling `displayReward` additionally requires the `avenc_aac` audio encoder.
The implementation uses the documented
[CreateMovie](https://psychtoolbox.org/docs/Screen-CreateMovie),
[AddFrameToMovie](https://psychtoolbox.org/docs/Screen-AddFrameToMovie),
[AddAudioBufferToMovie](https://psychtoolbox.org/docs/Screen-AddAudioBufferToMovie), and
[FinalizeMovie](https://psychtoolbox.org/docs/Screen-FinalizeMovie) interfaces.

`recEx` changes only the returned run's configuration. There is no need to edit
`setDefaultsCoPs.m` or restore experimental settings afterward. Ordinary
`runEx` calls retain their existing behavior.

Automated checks:

```matlab
results = runtests({'testRecEx.m','testCoPsTrialMoviex.m', ...
    'testCoPsMovieRewardAudiox.m','testCoPsRewardSoundx.m', ...
    'testCoPsRunExOverlayx.m','testCoPsTrialFeedbackx.m','testCoPsTestProfilex.m'});
assertSuccess(results);
```

Display/encoder unit tests use mocks. Check playback on the presentation
computer after exporting a clip.
