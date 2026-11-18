# Stimulus-generation compatibility fixture

`template.png` is a synthetic 64x64 grayscale image generated with MATLAB
`rng(42); uint8(min(240,max(15,128+35*randn(64))))`. It contains no source
face/object dataset content.

`reference.mat` stores two full and scrambled frames from each of methods
1, 2, and 3, plus method 3's mix50 frames and the two auxiliary masked
composites. They were generated independently using the original laboratory
`genDailyStimCorey.m`, its original sigma-based mask, the local `_wz` synthesis
code, and the original Windows pointOp/range2 MEX implementations. Only the
stray backtick preventing the original generator from parsing was removed
in that temporary reference copy.

The MAT file includes the exact settings. All methods used seed 42, one
session, Ntp=2, Niter=1, Nsc=2, Nor=4, Na=5, and coherence=0.5. Source/output
paths were temporary and are excluded from the fixture settings.

Tests compare the imported portable implementation against these arrays
with a small floating-point tolerance. This catches changes in synthesis,
RNG ordering, shared-mask width/normalization, and saved variable formats.
