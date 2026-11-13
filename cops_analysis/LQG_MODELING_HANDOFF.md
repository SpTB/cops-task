# CoPs LQG Modeling Handoff

This is a handoff note for continuing the single-target and two-target gaze modeling work without needing the original chat history.

## Current Goal

Build a modeling pipeline for CoPs gaze data that starts with a reliable single-target baseline, then branches toward two-target tracking models.

Current strategy:

1. Export CoPs MATLAB session data into Python-readable arrays.
2. Validate preprocessing and plotting against existing MATLAB functions such as `plotTraj`.
3. Fit simple single-target models first.
4. Compare those models formally before moving to two-target/HMM or LQG actor models.

## Important Files

- `cops_analysis/exportCoPsTwoTargetLqg.m`
  - MATLAB exporter for LQG-compatible data.
- `cops_analysis/helpers/reconstructEyePx.m`
  - Existing helper that informed gaze reconstruction/coordinate handling.
- `cops_analysis/plotTraj.m`
  - MATLAB plotting/preprocessing reference for gaze trajectories.
- `cops_analysis/lqg-main/notebooks/SingleTargetFit.ipynb`
  - Main single-target notebook. This is the best place to resume.
- `cops_analysis/lqg-main/notebooks/SingleTargetIndependentRecovery.ipynb`
  - Single-target recovery and residual-diagnostic notebook for the independent-output model and an AR(1) residual-likelihood variant.
- `cops_analysis/lqg-main/notebooks/TwoTargetIndependentFit.ipynb`
  - Two-target independent-output HMM notebook, including trial-CV and condition-wise difficulty checks.
- `cops_analysis/lqg-main/notebooks/BoundedActorFit.ipynb`
  - Separate notebook for trying the existing `lqg` bounded actor machinery.
- `cops_analysis/lqg-main/lqg/tracking/basic.py`
  - Existing LQG tracking primitives.
- `cops_analysis/lqg-main/lqg/tracking/two_target.py`
  - Existing two-target LQG model code.

Example exported data:

- `cops_analysis/example_data/experimental_ly_t1/lqg_export_t1.mat`
- `cops_analysis/example_data/lqg_export_t1.mat`
- `cops_analysis/example_data/experimental_ka/lqg_export.mat`

## Python Environment

A venv was created here:

```powershell
C:\Users\zajkowskiwk\Documents\vsg\cops_analysis\lqg-main\.venv
```

The useful Jupyter kernel is:

```text
Python (.venv vsg-lqg)
```

Known installed modeling dependencies include:

- `numpy`
- `scipy`
- `matplotlib`
- `jax`
- `numpyro`
- local `lqg-main` package on `sys.path`

To run the single-target notebook headlessly from PowerShell:

```powershell
cd C:\Users\zajkowskiwk\Documents\vsg\cops_analysis\lqg-main
$env:MPLBACKEND='Agg'
@'
import json
from pathlib import Path
p = Path('notebooks') / 'SingleTargetFit.ipynb'
nb = json.loads(p.read_text())
ns = {}
for i, cell in enumerate(nb['cells']):
    if cell.get('cell_type') != 'code':
        continue
    print(f'exec cell {i}: {cell.get("id")}')
    exec(compile(''.join(cell.get('source', [])), str(p), 'exec'), ns)
print('done')
'@ | .\.venv\Scripts\python.exe -
```

## MATLAB Export Structure

The exporter returns a MATLAB struct with fields such as:

- `out.x1`: target 1 trajectory, shape roughly `trials x time x 2`
- `out.x2`: target 2 trajectory, same shape, may be `NaN` for single-target trials
- `out.gaze`: gaze trajectory, same shape
- `out.mask`: valid gaze/timepoint mask, shape `trials x time`
- `out.targetPresent`: target-presence logicals
- `out.tRelSec`: relative time in seconds
- `out.step`: exported timestep indices
- `out.trialMeta`: trial labels and metadata
- `out.fit`: export/preprocessing options
- `out.geometry`: conversion metadata

The `2` in `trials x time x 2` is spatial dimension: x/y screen position.

The current exported example has:

```text
x shape:    (117, 540, 2)
gaze shape: (117, 540, 2)
mask shape: (117, 540)
```

## Units

The exporter stores display-pixel positions plus geometry metadata. The notebook converts to visual degrees after loading.

Current example geometry:

```text
deg_per_px = 0.019125862026423326
center_px = [960, 540]
```

Current notebook convention:

```text
position_unit = "visual deg"
variance_unit = "visual deg^2"
```

Most model outputs and fit summaries are now reported in visual degrees.

## Gaze Preprocessing Decision

For consistency with existing MATLAB visualization and analysis, gaze export now follows `plotTraj`-style preprocessing before time aggregation:

1. Mark invalid/out-of-texture samples.
2. Interpolate short true blink/missing gaps where appropriate.
3. Low-pass filter long clean gaze runs.
4. Aggregate/constrain to the modeling timestep.

This was important because an intermediate exporter version produced gaze traces that looked shifted or jumpy compared with `plotTraj`.

## Single-Target Notebook Models

`SingleTargetFit.ipynb` currently has three single-target baselines.

Bonnen fitting mode is controlled near the top of the notebook:

```python
BONNEN_FIT_MODE = "bridge"         # gap-aware default
# BONNEN_FIT_MODE = "segment_reset"  # older contiguous-valid-segment implementation
```

### 1. Independent-output target-filter model

Mean recursion:

```text
mu[t] = (1 - K) * mu[t-1] + K * target[t]
```

Likelihood:

```text
gaze[t] ~ Normal(mu[t], sigma_motor^2 I)
```

Fitted parameters:

- `R`: controls Kalman gain `K`, so it controls lag/smoothing.
- `sigma_motor`: isotropic output noise around the predicted mean.

Fixed/derived:

- `Q`: estimated from target step variance, then treated as fixed.

### 2. Bonnen-style ideal-observer model

This is closer to the Bonnen paper's Kalman observer transition likelihood. The current implementation is gap-aware.

For consecutive valid gaze samples, the likelihood is:

```text
gaze[t] ~ Normal((1 - K) * gaze[t-1] + K * target[t], K^2 * R)
```

If valid gaze samples are separated by a missing-data gap, the model predicts the next valid gaze sample from the previous valid gaze sample by recursively applying the same response update through all intervening target samples. The conditional variance grows across the gap:

```text
mu[k] = (1 - K) * mu[k-1] + K * target[k]
var[k] = (1 - K)^2 * var[k-1] + K^2 * R
```

The first valid gaze sample in each trial is conditioning data and is not scored. The model no longer restarts at every post-gap segment.

The older segment-reset implementation is still available with:

```python
BONNEN_FIT_MODE = "segment_reset"
```

That mode scores only within contiguous valid segments and treats the first valid sample of each segment as conditioning data.

Fitted parameters:

- `R`

Fixed/derived:

- `Q`: estimated from target step variance, then treated as fixed.

Plotting:

- The gap-aware conditional bridge mean used by the likelihood is kept as `bonnen_fit["bridge_mu"]`.
- The main plotted Bonnen prediction is `bonnen_fit["mu"]`, the target-conditioned expected response mean `E[gaze trajectory | target trajectory]`.
- The expected mean now carries through the full trial instead of restarting after missing-data gaps.

Reason for this plotting decision:

- The one-step conditional mean predicts only one sample ahead and reanchors to observed gaze.
- It can look artificially good or visually confusing.
- The expected response mean is more interpretable as a target-conditioned predicted trajectory.

### 3. Bonnen + output-noise model

This modified Bonnen baseline uses the same gap-aware bridge mean as the Bonnen likelihood, but adds an estimated isotropic output-noise term to the conditional variance.

Likelihood:

```text
gaze[next_valid] ~ Normal(mu_bridge[next_valid], bridge_var[next_valid] + sigma_motor^2)
```

Fitted parameters:

- `R`: controls the Bonnen/Kalman bridge mean and bridge uncertainty through `K`.
- `sigma_motor`: additional residual output noise around the bridge prediction.

Fixed/derived:

- `Q`: estimated from target step variance, then treated as fixed.

Interpretation:

- `R` controls lag/smoothing and gap-bridge uncertainty.
- `sigma_motor` absorbs residual scatter not explained by the bridge variance.
- This is now a conditional bridge model, not the same as the independent-output likelihood.

## Current Example Fit Results

Data:

```text
C:\Users\zajkowskiwk\Documents\vsg\cops_analysis\example_data\experimental_ly_t1\lqg_export_t1.mat
```

Independent-output:

```text
Q = 0.091 visual deg^2/step
R = 159.092 visual deg^2
sqrt(R) = 12.613 visual deg
sigma_motor = 2.910 visual deg
K = 0.024
observations = 61626
```

Original Bonnen-style:

```text
Q = 0.091 visual deg^2/step
R = 1709.701 visual deg^2
sqrt(R) = 41.349 visual deg
K = 0.007
one-step innovation sigma = 0.301 visual deg
mean bridge innovation sigma = 0.303 visual deg
valid trial sequences = 117
bridged transitions = 61509
mean / max bridge gap = 1.02 / 161 steps
mean NLL/transition = 1.412
```

Bonnen + output-noise:

```text
Q = 0.091 visual deg^2/step
R = 807.689 visual deg^2
sqrt(R) = 28.420 visual deg
sigma_motor = 0.295 visual deg
K = 0.011
mean bridge innovation sigma = 0.302 visual deg
valid trial sequences = 117
bridged transitions = 61509
mean / max bridge gap = 1.02 / 161 steps
mean NLL/bridged transition = 1.127
```

Matched mean-comparison results:

```text
Shared samples = 61626

independent_output:
  RMSE = 4.115 visual deg
  MAE = 2.718 visual deg
  matched sigma = 2.910 visual deg
  matched NLL/sample = 4.974
  matched AIC = 613086.8

bonnen_expected:
  RMSE = 4.266 visual deg
  MAE = 3.287 visual deg
  matched sigma = 3.017 visual deg
  matched NLL/sample = 5.046
  matched AIC = 621965.0

bonnen_output_noise:
  RMSE = 4.179 visual deg
  MAE = 3.069 visual deg
  matched sigma = 2.955 visual deg
  fitted model sigma_motor = 0.295 visual deg
  matched NLL/sample = 5.005
  matched AIC = 616875.2
```

Gap-aware Bonnen bridge likelihood results:

```text
bonnen_bridge:
  bridged transitions = 61509
  mean / max bridge gap = 1.02 / 161 steps
  model NLL/transition = 1.412
  model AIC = 173661.1

bonnen_bridge_output_noise:
  bridged transitions = 61509
  mean / max bridge gap = 1.02 / 161 steps
  model NLL/transition = 1.127
  model AIC = 138594.6
```

Old segment-reset comparison, available through `BONNEN_FIT_MODE = "segment_reset"`:

```text
segment_reset Bonnen:
  R = 1380.580 visual deg^2
  K = 0.0081
  segments = 158
  transitions = 61457
  NLL/transition = 1.370

segment_reset Bonnen + output noise:
  R = 117.962 visual deg^2
  K = 0.0274
  sigma_motor = 2.918 visual deg
  segments = 158
  scored samples = 61615
  NLL/sample = 4.980
```

Interpretation:

- The gap-aware bridge implementation removes the old segment-reset assumption.
- Bonnen + output-noise strongly improves the actual bridge likelihood relative to the no-output-noise bridge model.
- In target-conditioned mean comparison, independent-output still wins on this example.
- Independent-output and Bonnen + output-noise still have the same number of fitted parameters in this implementation: `R` and `sigma_motor`.
- The main visual-check trial scans compare `independent_fit["mu"]` against `bonnen_noise_fit["mu"]`.
- The old segment-reset implementation fits slightly better on some raw metrics, but it does so by restarting after gaps; keep it as a comparison mode rather than the default.

## Conceptual Notes

### Single-target recovery and AR residual diagnostics

`SingleTargetIndependentRecovery.ipynb` was added as a simpler starting point before two-target recovery.

It fits and recovers:

- current independent-output model with iid residuals
- independent-output mean plus AR(1) residual likelihood

The AR(1) variant keeps the same target-filter mean as the independent-output model:

```text
mu[t] = (1 - K) * mu[t-1] + K * target[t]
```

but changes the observation likelihood to score innovations:

```text
e[t] = gaze[t] - mu[t]
e[t] = rho * e[t-1] + innovation[t]
innovation[t] ~ Normal(0, sigma_innov^2 I)
```

Initial checks on the first 24 single-target trials showed:

```text
real iid fit:
  R = 54.551 deg^2
  sigma_motor = 2.207 deg
  K = 0.0403

real AR(1) fit:
  R = 121.609 deg^2
  sigma_innov = 0.408 deg
  rho = 0.981
  K = 0.0272
```

Recovery sanity checks behaved as expected:

- iid simulations recover with `rho` near 0 when fit by the AR model.
- AR simulations recover `R`, `sigma_innov`, and `rho` well when fit by the AR model.
- iid fits to AR simulations inflate the residual scale and shift `R/K`.

However, real-data AR innovations were still autocorrelated:

```text
real iid residual lag1 autocorr: x = 0.979, y = 0.984
real AR innovation lag1 autocorr: x = 0.735, y = 0.754
```

So a single AR(1) term is not enough to fully whiten the real residuals. This suggests additional structure remains, such as preprocessing effects, lag/gain mismatch, calibration drift, saccades/corrections, or model-mean misspecification.

The notebook also includes a synthetic preprocessing-only check. The MATLAB exporter order was verified as:

```text
invalid / bounds mask
-> short blink/missing-gap interpolation
-> zero-phase low-pass filtering on clean runs
-> final valid / bounds mask
-> step aggregation
```

The notebook mirrors this order in a synthetic high-rate approximation:

- step-rate model means are repeated to synthetic raw samples
- synthetic raw gaze is generated
- exporter-style preprocessing is applied
- samples are aggregated back to the model timestep

This is not a perfect raw-eye reconstruction, because the notebook starts from exported step-rate targets/means rather than true raw sample-rate target/gaze streams. In the default run, no synthetic blink gaps were inserted, so interpolation filled zero samples; the main preprocessing effects came from low-pass filtering and aggregation.

Initial preprocessing test results:

```text
real AR innovation lag1:       x = 0.735, y = 0.754
preprocessed iid AR innovation: x = 0.299, y = 0.345
preprocessed AR AR innovation:  x = 0.781, y = 0.782
```

Interpretation:

- Low-pass + aggregation alone can produce leftover autocorrelation after an AR(1) fit, even when the raw synthetic noise was iid.
- A strongly persistent raw AR residual process plus preprocessing can reproduce real-like leftover AR-innovation autocorrelation.
- This supports the idea that preprocessing may explain a substantial part of the remaining autocorrelation, but it does not uniquely prove preprocessing is the only cause.

A component ablation in the same notebook suggests low-pass filtering is the dominant contributor among the synthetic preprocessing pieces tested:

```text
iid raw noise, AR innovation lag1:
  aggregate only:  x = 0.009, y = -0.008
  low-pass only:   x = 0.251, y = 0.295

AR raw noise, AR innovation lag1:
  aggregate only:  x = 0.156, y = 0.172
  low-pass only:   x = 0.780, y = 0.781
```

In this ablation, interpolation filled zero samples because no synthetic blink gaps were injected, so it did not contribute. The bounds/mask step was only represented by the exported valid mask, not a true raw screen-bound reconstruction.

### Why can independent-output beat Bonnen + output-noise?

Both have output noise, but their mean trajectories differ.

Independent-output carries one filtered target trajectory through the trial.

Bonnen + output-noise now uses the gap-aware bridge likelihood. Its target-conditioned expected mean still differs from the independent-output mean because `R` is fitted under a conditional bridge objective rather than an independent output objective.

Output noise helps explain residual scatter but does not erase differences in the mean trajectory.

### What does fitted `Q` mean?

At the moment, `Q` is not fitted as a behavioral parameter. It is estimated from target movement statistics.

In Bonnen, `Q` corresponds to known target process variance. In the original paper, target jumps were generated with known variance, so `Q` was effectively fixed by the stimulus.

If `Q` were fitted, it would partly reflect the model's inferred target volatility. But fitting both `Q` and `R` can create identifiability issues because the gain depends strongly on their ratio.

### Is motor noise identifiable in Bonnen + output-noise?

Partly, but with caution.

In this model:

- `R` changes the mean trajectory by changing `K`.
- `sigma_motor` changes residual variance around the mean.

That gives some separation. But both can still trade off because a smoother/laggier mean can increase residuals, and `sigma_motor` can absorb that.

Motor noise is more structurally identifiable in a full LQG/actor model when actions, state dynamics, and observation noise make distinct predictions over time. But even there, it depends on data richness and model constraints.

## Relation To Bonnen And Rothkopf/LQG Papers

Bonnen:

- Closest to an ideal-observer Kalman filter.
- Uses target process variance `Q` and sensory variance `R`.
- The paper uses known target dynamics, so `Q` is not really a free behavioral fit.

Rothkopf/LQG hierarchy, as discussed:

1. Ideal observer/Kalman filter.
2. Ideal actor/LQG.
3. Bounded actor/LQG.
4. Subjective actor.

The local `lqg` code has actor models such as `OptimalActor` and `BoundedActor`, but the existing scripts do not expose a clean Bonnen-style ideal-observer likelihood directly. The bounded actor notebook is therefore a comparison path, not a drop-in replacement for the Bonnen single-target observer.

Important distinction:

- Some LQG code plots or evaluates one-step teacher-forced predictions.
- These can look very accurate because they condition on current observed state/gaze.
- For visual model comparison, target-conditioned expected-response trajectories are more interpretable.

## Trial And Segment Handling

The exporter can support:

- single-target trials
- two-target trials
- mixed sessions

The current single-target notebook uses single-target data and can map exported rows back to original trial numbers through `trial_idx`.

Useful helper concept:

```python
choose_trial(mask, rand=True, thresh=0.75)
```

Meaning:

- If `rand=True`, choose a random trial with at least `thresh` valid timepoints.
- If no candidate exists, or `rand=False`, choose the trial with the highest valid fraction.

Bonnen bridge likelihoods operate on trial-level sequences with at least:

```python
BONNEN_MIN_SEGMENT_LENGTH = 5
```

The name is historical; it now effectively means "minimum valid gaze samples in the trial." Missing-data gaps inside a trial are bridged rather than split into independent segments.

## Difficulty Condition Checks

The exporter already writes condition metadata in:

```text
out.trialMeta.backgroundNoiseLvl
out.trialMeta.targetVisibility
out.trialMeta.trialIdx
out.trialMeta.targetNum
```

The modeling arrays inside `fit.singleTarget` / `fit.twoTarget` do not always carry those labels directly, so the notebooks map condition metadata back by `trialIdx`.

`SingleTargetIndependentRecovery.ipynb` now has cells that:

- print all observed `backgroundNoiseLvl x targetVisibility` groups for the single-target export
- fit iid independent-output and AR(1) independent-output models separately within each condition
- report `Q`, `R`, output/innovation noise, `K`, NLL, and lag-1 residual/innovation autocorrelation

The current single-target export has the expected 2 x 3 condition layout:

```text
backgroundNoiseLvl: 0, 1
targetVisibility:  0.6, 0.8, 1.0
```

`TwoTargetIndependentFit.ipynb` now has matching condition cells for the independent-output HMM. These currently fit only `R` and `sigma_motor` on the existing coarse grid, with `p_switch` fixed at the notebook default. They also report the global-parameter reference NLL for each condition.

The current two-target export has six observed cells, but not a simple full 2 x 3 grid:

```text
bg=0: vis=0.2, 0.6, 1.0
bg=1: vis=0.6, 0.8, 1.0
```

So avoid hard-coding assumed difficulty levels; use the metadata grouping helper in the notebook.

## Immediate Next Steps

Good next steps for a future Codex session:

1. Open and run `cops_analysis/lqg-main/notebooks/SingleTargetFit.ipynb`.
2. Inspect the Bonnen + output-noise plotting cell and the gap-aware bridge likelihood summary.
3. Consider renaming `BONNEN_MIN_SEGMENT_LENGTH` to `BONNEN_MIN_VALID_SAMPLES` for clarity.
4. Consider adding a stricter apples-to-apples comparison between independent-output and bridge models on exactly the bridged transition samples.
5. Consider adding cross-validation by trial, since in-sample fit differences can be misleading.
6. After single-target behavior is trusted, branch toward a two-target model.

## Two-Target Branch Point And Hybrid Workflow

The two-target work now has two complementary baselines:

- The independent-output HMM is more descriptive and appears better at recovering which target is being tracked, because the emission is strongly location sensitive.
- Bonnen-style models are more mechanistic, because the expected gaze follows a recursive target-response/Kalman update.

This suggests a useful "best of both worlds" workflow:

1. Use the independent HMM to infer likely tracked-target states.
2. Use high-confidence independent-HMM states as provisional labels for visualization, diagnostics, and selecting clean target-tracking segments.
3. Fit or diagnose Bonnen-style dynamics conditional on those high-confidence segments.
4. Use what is learned to build a joint HMM with Bonnen-style emissions.
5. Compare the joint Bonnen-style model against the independent HMM on held-out trials.

This two-stage approach is not automatically circular if it is described honestly as initialization, diagnostic labeling, or a conditional analysis. It becomes circular only if independent-model labels are treated as ground truth and then the Bonnen model is presented as if it independently discovered those same latent states.

The cleaner eventual model is a joint latent-state model:

```text
z[t] = tracked target identity, with HMM switch dynamics

if z[t] = T1:
  gaze[t] ~ Bonnen-style emission based on target 1 history

if z[t] = T2:
  gaze[t] ~ Bonnen-style emission based on target 2 history
```

The joint model should integrate/sum over latent target states during fitting rather than hard-labeling them first. A correlated residual likelihood, such as AR(1), may also be worth adding because processed real-gaze residuals are strongly temporally autocorrelated.

The LQG bounded actor code is still useful as a comparison and eventual richer model, but it brings more machinery and assumptions.

## Caution For Future Work

- Do not overwrite user changes without checking `git status`.
- Current modeling files may be untracked in git.
- Keep terminology as "gaze", not "cursor".
- Prefer visual degrees for model distances and variance summaries.
- When changing gaze preprocessing, compare against MATLAB `plotTraj` on the same original trial number.
- Be careful comparing one-step conditional predictions to free or target-conditioned prediction trajectories; they answer different questions.
