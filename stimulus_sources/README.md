# Bundled stimulus source PNGs

These are the two raw template sets used by `genDailyStimCorey`, imported
unchanged from the supplied local copy of Corey's face_fMRI stimulus folder.
Original filenames and PNG bytes are preserved.

| Directory | PNGs | Bytes |
| --- | ---: | ---: |
| `faces_scrambled_raw` | 490 | 22,454,493 |
| `objects_scrambled_raw` | 820 | 50,480,900 |
| Total | 1,310 | 72,935,393 |

`manifest.json` records each source file's size and SHA-256 checksum.
These PNGs are tracked inputs. Additional local files in this folder are
ignored unless explicitly allowed in `.gitignore`.

From the repository root in MATLAB:

```matlab
out = genDailyStimCorey('local');
```

This uses these PNGs independently of any network-drive environment setting
and writes generated banks under the repository's Git-ignored `stimuli`
directory. The local keyword replaces the optional two-letter output label;
it is not included in session directory names. Explicit source/output options
can still override these defaults.

This directory contains source templates, separate from the generated
`full`, `scramble`, and `mixXX` sequences. See
[`docs/stimulus_generation.md`](../docs/stimulus_generation.md) for details.
