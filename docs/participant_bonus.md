# Participant bonus and outro

All bonus settings live in `pay` near the top of `setDefaultsCoPs.m`, saved as
`ex.exp.CoPs.pay`. This replaces the former `ins.max_bonus_dollar` setting.

```matlab
pay.minPointsPerTrial = 3;
pay.maxPointsPerTrial = 25;
pay.max_bonus_dollar = 25;
pay.transform = 'linear'; % 'linear' or 'logit'
pay.logitSlope = 10;      % used only by the S-shaped option
```

The welcome-page maximum and the final bonus use the same cap. Settings are
validated before opening the task display. The maximum average must exceed the
minimum; the cap must be nonnegative and specify whole cents; slope must be
positive. Main-task payouts work whether `instrOn` is on or off.

## Eligible trials and earned points

The calculation uses whole reward-crossing events from `Trials(i).times.reward`.
It does not use fractional `pointsEarned`, `pointTrace`, or `ex.totalPoints`.
Those continuous analysis scores remain saved separately.

Both instruction practice trials are excluded from the points and trial count.
Any trial with `pointsCountTowardTotal=false` is also excluded. Other recorded
task trials count, including zero-point trials; dropping zero-point trials
would inflate the average. If legacy special blocks are enabled, their trials
count unless explicitly marked as excluded. The exact mask is saved for audit.

Let `A = eligible earned points / eligible trial count`. No eligible trials
produces a zero bonus. The normalized performance is:

```text
x = clamp((A - pay.minPointsPerTrial) /
          (pay.maxPointsPerTrial - pay.minPointsPerTrial), 0, 1)
```

At or below the minimum average, the bonus is zero. Exactly the minimum also
maps to zero; positive bonuses begin above it. At or above the maximum average,
the participant earns the full cap. Values outside the range are clamped.

## Linear and S-shaped transforms

For `pay.transform='linear'`, the bonus fraction is `x`.

For `pay.transform='logit'`, the implementation uses the **inverse logit**
(logistic sigmoid), normalized to reach both endpoints exactly:

```text
S(z) = 1 / (1 + exp(-z))
k = pay.logitSlope
fraction = [S(k*(x - 0.5)) - S(-k/2)] / [S(k/2) - S(-k/2)]
```

The code evaluates an algebraically equivalent `tanh` expression to avoid
exponential overflow. Very small slopes approach the linear mapping. The
default slope 10 produces a visible S shape centered on the midpoint average
(14 points/trial with the default thresholds). Increasing slope makes the
middle transition steeper. The option is named `logit` as requested; it does
not apply the divergent log-odds function `log(x/(1-x))` to the score.

The bonus before currency rounding is `pay.max_bonus_dollar * fraction`.
It is rounded **down** to whole cents, with floating-point tolerance at exact
cents. A below-maximum average cannot receive the full cap through rounding
or numerical sigmoid saturation.

| Average earned points/trial | Linear bonus | S-shaped bonus (slope 10) |
| --- | --- | --- |
| 3 or below | $0.00 | $0.00 |
| 8.5 | $6.25 | $1.75 |
| 14 | $12.50 | $12.50 |
| 19.5 | $18.75 | $23.24 |
| 25 or above | $25.00 | $25.00 |

![Linear and normalized sigmoid bonus curves](participant_bonus_curves.png)

## Screen, data, and experimenter output

The final gray outro replaces the former points-only end screen. It shows:

```text
The session is complete.

Total: 42 points
Average: 14.00 points per trial
Bonus earned: $12.50

Press SPACE to finish.

Please inform the experimenter.
```

The displayed average is rounded down to two decimal places. Payment uses the
unrounded average. The outro appears on normal completion even if instruction
pages, regular pauses, or between-trial point feedback are disabled.

`ex.Payout` records the resolved config, eligible trial mask, per-trial whole
points, total, eligible trial count, exact average, normalized performance,
bonus fraction, unrounded dollars, integer cents, and final dollars.
The last trial's `payout` field contains the same summary. `ex.Outro` records
the rendered text, on/off timestamps, and participant acknowledgement.
Existing `endScreen*` trial fields remain available. After the final data save,
the console prints the bonus, point total, trial count, and average.

To calculate a summary explicitly without changing saved data:

```matlab
payout = calculateCoPsPayoutx(ex.Trials, ex.exp.CoPs.pay);
```

`testCoPsPayoutx.m` checks endpoints, capping, midpoint, S shape, monotonicity,
practice exclusion, zero-point trials, fractional-evidence exclusion, empty
runs, extreme slopes, near-maximum rounding, and invalid settings. Feedback
tests verify the actual outro text and stored summary with mocked display and
keyboard calls. Check final text layout and question popups on the rig.
