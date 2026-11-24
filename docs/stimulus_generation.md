# Generate CoPs texture banks

The repository includes the laboratory `genDailyStimCorey` generator, its
modified textureSynth functions, and the required matlabPyrTools source.
Add the repository root to MATLAB's path. No separate synthesis checkout,
Psychtoolbox display, compiled MEX files, or extra MATLAB toolbox is needed
for offline generation.

Run these examples from the repository root. If an older generator is still
on your path or in the current directory, `which genDailyStimCorey -all`
shows which entry point MATLAB will use. `copsstim.generateCorey` is the
unambiguous package entry point and accepts the same arguments.

## Generate and use a local bank

The source PNGs are included in this repo. To use them and save the generated
banks in the repo's untracked output folder:

```matlab
out = genDailyStimCorey('local');
```

This selects five face IDs and uses the usual synthesis defaults: three
banks, 100 frames per image, and 50 iterations per frame. The `local` keyword
chooses the repo's `stimulus_sources` folder even if an old
`COPS_STIM_SOURCE_ROOT` environment variable points to a network drive.

For a custom selection and one bank:

```matlab
opts = struct();
opts.sessions = 1;
opts.rng_seed = 42; % omit for a shuffled seed
out = genDailyStimCorey('local', 'both', 5, opts);

bank = out.sessions(1).daily_dir;
ex = runEx('mouse_mini', stimulusDir=bank, testTrials=3);
% Or record a presentation movie:
ex = recEx(stimulusDir=bank, length=5, background=1);
```

`stimulusDir` is available in all `runEx` modes, including `runEx('h')` and
the no-eye solo mode `runEx('t')`, and in `recEx`. Pass the
**session directory containing image subdirectories**,
rather than a `noise1`, `full`, or `scramble` directory. It overrides the
configured bank, including the bundled bank normally used by mouse modes.
The existing `graph.imgs` image-name filter still applies. An empty
`stimulusDir` retains the usual bank selection.

The default output root is this repository's `stimuli` directory. Set
`opts.output_root` to save elsewhere. Generated files under `stimuli` are
ignored by Git; the input PNGs under `stimulus_sources` are versioned.
Explicit `opts.source_root` and `opts.output_root` still override the
defaults, including in local mode.

## Source images

The repo contains 490 face and 820 object PNGs (69.6 MiB total) in this layout:

```text
stimulus_sources/
  faces_scrambled_raw/
    fn_0001_sample_01.png
    fn_0001_sample_02.png
    ...
  objects_scrambled_raw/
    fn_0001_sample_01.png
    ...
```

Only the folders needed by the selected stimulus type must exist. Filenames
may also omit the underscore immediately before the sample number, e.g.
`fn_0001_sample02.png`. Grayscale and RGB PNGs are accepted; RGB is converted
to grayscale and values are scaled to the generator's 0-255 range.

With the default `Nsc=4`, dimensions must be multiples of 64. The general
requirement is a multiple of `2^(Nsc+2)`, with each dimension at least
`2*mask_radius+1`. Use square source images for the CoPs task.

The source root resolves in this order: explicit `opts.source_root`, the
`COPS_STIM_SOURCE_ROOT` environment variable, then the repository's
`stimulus_sources` directory. Local mode skips the environment-variable step.
No network connection or separate dataset transfer is required when using
the bundled PNGs. The [source manifest](../stimulus_sources/manifest.json)
records the byte size and SHA-256 checksum of every bundled PNG.

## Calling convention and selection

The original interface is preserved:

```matlab
out = genDailyStimCorey(label, stimType, selection, opts);
```

- `label`: empty or two letters, used only in output directory names. The
  special keyword `'local'` enables the repo-local defaults and omits a label
  from the output directory name.
- `stimType`: `'face'`, `'object'`, or `'both'`.
- Scalar numeric `selection`: number of image-ID groups to sample, choosing
  one source sample per selected group.
- Numeric vector: requested IDs within the selected source type.
- Text selection: explicit templates, optionally prefixed with `face_` or
  `object_` to disambiguate mixed sources.

```matlab
out = genDailyStimCorey('ka', 'face', 5, opts);
out = genDailyStimCorey('', 'object', [3 4 5], opts);
out = genDailyStimCorey('', 'both', ...
    ["face_fn_0001_sample_02", "object_fn_0003_sample_01"], opts);
```

The legacy abbreviated calls also remain available: no arguments or only a
label selects five face IDs. Omitting a selection uses `opts.default_count`
(five by default). `genDailyStimCorey('local', opts)` also supports this
abbreviated form.

## Main options

| Field in `opts` | Default | Meaning |
| --- | --- | --- |
| `source_root` | Repo `stimulus_sources` in local mode; otherwise environment variable or repo | Parent of source folders |
| `face_folder` | `'faces_scrambled_raw'` | Face source subfolder |
| `object_folder` | `'objects_scrambled_raw'` | Object source subfolder |
| `output_root` | Repo `stimuli` | Parent for generated session folders |
| `sessions` | `3` | Independently seeded banks |
| `date_tag` | Tomorrow's date, e.g. `nov19` | Session-name component; specify explicitly for a fixed name |
| `rng_seed` | `[]` | Empty shuffles; numeric fixes the selection/session seed sequence |
| `Ntp` | `100` | Number of texture frames per image |
| `Niter` | `50` | Synthesis iterations per frame |
| `Nsc` | `4` | Pyramid scales |
| `Nor` | `4` | Orientations |
| `Na` | `9` | Spatial correlation neighborhood |
| `noise_scalar` | `1` | Noise added between generated frames; also determines `noise1`, etc. |
| `method` | `1` | Original generation method: `1`, `2`, or `3` |
| `coh_lvls` | `0.05:0.05:0.95` | Coherence levels generated by method `3` |
| `mask_radius` | `20` | Historical name for the sigma of the auxiliary offline masks |
| `save_bool` | `1` | Write the bank and manifest |
| `save_coh_lvl_only` | `0` | Original file-selection switch; keep `0` for complete task banks |
| `maxRetries` | `1` | Attempts per synthesized frame |
| `max_template_retries` | `10` | Replacement-template attempts for an incomplete image bank |

Method `3` writes `mixXX` directories in addition to `full` and `scramble`.
These mixtures serve the task's `ctl.coherence` manipulation. The task's
`graph.target_visibility`/`recEx(visibility=...)` controls the displayed patch
blend separately. Generate every positive background noise level requested
by the task. Background conditions `0` and `-1` reuse a real noise directory
and apply their fixed/gray display behavior during the task.

`Ntp` counts stored texture frames. The task cycles through the available
frames if a trial needs more stimulus steps. `Niter` controls synthesis work
and texture quality. For a quick code check, use a small `Ntp` and `Niter`.

The legacy `add_paths` and `plot` fields remain accepted. Synthesis helpers
are private and require no path edits; the generator retains its existing
non-plotting execution behavior.

## Files, reproducibility, and the shared mask

Output retains the task's existing format:

```text
<output_root>/<label_><date_tag>_stim1/
  generation_manifest.mat
  face_fn_0001_sample_01/
    params.mat
    full_gen.mat
    seed.mat
    full_as_target.mat
    scr_as_target.mat
    noise1/
      full/full_0001.mat          % full_tp
      scramble/scramble_0001.mat  % scramble_tp
      mix50/mix50_0001.mat        % mix_tpi; method 3
```

Each completed session's `generation_manifest.mat` stores `manifest.settings`,
the `localMode` flag, the selection seed, and `manifest.session` with its RNG seed and selected
source paths. The returned `out` also contains the resolved options and all
session/image paths. Existing matching parameter caches and the original
retry/replacement behavior are retained. For a reproducible fresh run, use
the same source PNGs/settings/seed and a new empty output directory, since
loading cached analysis parameters skips work that consumes random numbers.

Task rendering and generation now share **one Gaussian implementation** in
`copsstim.gaussMask`. The public `gauss_mask` function forwards to it for
compatibility. The task retains sigma = radius/3 times its configured mask
multiplier. The generator explicitly passes sigma = mask_radius and retains
its unit-peak normalization. This preserves both original mask conventions;
the auxiliary offline composites are not used to create the main sequences.

The synthesis libraries are isolated in the package's `private` folder,
including portable MATLAB versions of lookup-table operations. Original
licenses, READMEs, and source hashes are retained; see
[`+copsstim/README.md`](../+copsstim/README.md).

## Verification

```matlab
results = runtests({'testCoPsStimulusGenerationx.m','testRecEx.m', ...
    'testCoPsRunExOverlayx.m','testCoPsMiniStimulusBoundsx.m'});
assertSuccess(results);
```

Generation tests run against independent fixtures made with the original
generator/native MEX backend for methods 1-3. They compare full, scrambled,
mixed, and auxiliary images; check the real task loader; and exercise
conflicting helper names without external synthesis dependencies.
Local-mode tests use the bundled templates, verify that a stale network
environment setting is ignored, and validate every source PNG's checksum.
