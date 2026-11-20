# CoPs stimulus generation

`genDailyStimCorey.m` in the repository root is the public entry point.
`generateCorey.m` preserves the laboratory generator's selection, synthesis,
retry, and file-format behavior. See `docs/stimulus_generation.md` for usage.

The required textureSynth and matlabPyrTools functions are vendored in
`private/`, so they cannot shadow task functions or pick up a different
installation's synthesis helpers. No path changes or compiled MEX binaries
are required. The private lookup-table implementation follows the original
pointOp C interpolation expression, including extrapolation and constant
tables, rather than relying on a platform-specific binary.

Both task rendering and offline generation call `copsstim.gaussMask`, the
single implementation moved from the task's original `gauss_mask.m`.
The root `gauss_mask.m` retains its historical API as a forwarding wrapper.
The generator explicitly supplies sigma = mask_radius and retains its
unit-peak normalization; the task supplies its configured sigma, normally
radius/3. The two pipelines therefore retain their original widths.

## Provenance and licenses

Imported from the laboratory's local snapshots of:

- [textureSynth](https://github.com/LabForComputationalVision/textureSynth),
  including local `_wz` synthesis changes and generation helpers.
- [matlabPyrTools](https://github.com/LabForComputationalVision/matlabPyrTools).

The original licenses and READMEs are retained in `private/`. Source-file
SHA-256 hashes before integration are recorded in `source_manifest.json`.
No upstream example images, toolbox archives, or native binaries are included
in this package. The task's source templates are bundled separately in the
repo's `stimulus_sources` directory; `genDailyStimCorey('local')` selects them.

Integration changes: remove an invalid backtick in the generator, replace
host-specific paths with explicit/repository defaults, use the shared mask,
save generation settings/seeds, and resolve helpers privately. In the
vendored pyramid helpers, pointOp is vectorized to match the C implementation
and repeated compile-MEX notices are removed from MATLAB fallbacks. Other
synthesis mathematics are unchanged.

Research using the synthesis algorithm should cite the Portilla and
Simoncelli paper listed in the retained textureSynth README.
