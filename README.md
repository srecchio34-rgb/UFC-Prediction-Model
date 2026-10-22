# UFC MATLAB Toolkit v2

This update adds calendar recency weighting, opponent-adjusted performance,
small-sample smoothing, age, and probability calibration. The original
fitted model remains available. Base MATLAB R2021a or newer; no extra
toolboxes, Python, or network access are required for normal use.

## Start

Extract the **whole ZIP**. In MATLAB, open `START_UFC_V2.m` from the extracted
`UFC_MATLAB_Toolkit_V2` folder and press **Run**. It selects the new folder,
clears cached functions and verifies that MATLAB resolves the new scripts.
The Command Window prints **UFC TOOLKIT V2 IS ACTIVE**, then asks for two
fighter names. The scripts, `data`, and `results_v2` must remain together.

You can keep the original ZIP and extracted toolkit. MATLAB uses extracted
`.m` files rather than ZIP files. Keep the V2 folder as Current Folder while
using it; run `START_UFC_V2.m` again to switch back after using the old copy.
Once V2 is active, direct calls work as before:

```matlab
compare_ufc('Alexander Volkanovski', 'Movsar Evloev')
```

Run `compare_ufc` without names for prompts. `start_ufc` opens the menu.
Fitted parameters are already included in `data/model_v2.json`.

## Matchups and graphs

```matlab
[R, fig] = compare_ufc('Alexander Volkanovski', 'Movsar Evloev');
R.ProbabilitySummary       % both final percentages
R.Contributions           % 20 displayed categories
R.FeatureComparison       % all 21 numerical model inputs

compare_ufc('Alexander Volkanovski', 'Movsar Evloev', ...
    'SaveFile', 'volk_evloev.png');

% Original fitted coefficients and original career-average features:
compare_ufc('Alexander Volkanovski', 'Movsar Evloev', 'Model', 'baseline');

% Age and recency on a booked date, using only strictly earlier bouts:
compare_ufc('Alexander Volkanovski', 'Movsar Evloev', 'AsOf', '2026-10-24');

% Specify the booked division if latest recorded divisions differ:
compare_ufc('Ilia Topuria', 'Justin Gaethje', 'Division', 'Lightweight');
```

Other options: `DataDir`, `Print`, `Plot`, `Visible`, `AllowLimitedHistory`.
The normal gate requires two earlier recorded fights and ten minutes per
fighter. Overriding it gives an exploratory estimate.

Each graph starts at 50/50. Exact Shapley contributions include calibration
and sum to the final probabilities. The two age terms form one category;
the other nineteen categories correspond to individual inputs. The opposing
fighter's effects have equal magnitude and opposite signs. These explain
the fitted model; they are not causal skill-improvement estimates.

## Five additions

**Recency.** Each appearance receives weight
`2^(-days_since_fight / (365.25 * half_life_years))`. Counts and exposure
receive the same weight; rates use weighted totals divided by weighted time.
Individual and population histories decay. Lifetime experience and the
minimum-history gate retain actual, unweighted counts. One-, two-, and
three-year half-lives were compared on 2019-2021 only. The supplied model
selected **one year**: two-year-old performances retain 25% weight.

**Smoothing.** Count/exposure statistics use equivalent-exposure pseudocounts;
proportions use corresponding success/denominator pseudocounts. This is
Gamma-Poisson-style smoothing for rates and Beta-binomial-style smoothing
for proportions. Pseudocounts come from strictly earlier divisional totals.
Divisions back off to the earlier global population using 150 equivalent
minutes. A weak, explicit 60-minute global cold-start seed is documented in
`ufc_v2_config.m`. Fighter prior strengths of 5, 15, and 30 minutes were
compared; validation selected **five minutes**.

**Opponent context.** Four extra features measure performance above what an
average fighter would have been expected to do against the opponent's
earlier offense and defense. They cover strike, takedown, knockdown, and
control differentials. For strikes, the residual count is:

`own_strikes - opponent_strikes - (opponent_prior_SAPM - opponent_prior_SLpM)*minutes`

Residuals are time-weighted and shrunk toward zero. Opponent baselines are
smoothed and calculated before that historical bout. Control residuals
require both control exposures to be known. This is an opponent-performance
adjustment, not Elo or a complete measure of opponent ability. Original
rates remain separate, allowing fitting to determine the added value.

**Age.** Birth dates determine age on the forecast date. Linear and quadratic
inputs, `(age-30)/10` and its square, allow the fitted age relationship to
curve. No peak age or decline penalty is hardcoded. This release uses one
common curve, not a separate age submodel for every division. Missing or
implausible ages give a neutral comparison in both age terms.

Birth dates are present for 2,606 of 2,694 identities, covering 99.3% of
fighter appearances. Source priority, conflicts and missing dates are in
`data/birth_date_audit.json`. Only birth dates were imported from profile
snapshots; their present-day career stats, rankings and results are excluded.

**Calibration.** A positive multiplier on log odds is learned from earlier
out-of-time forecasts: `P(A wins) = sigmoid(slope * raw_logistic_score)`.
The supplied slope is approximately **1.123**. It changes probability
strength while preserving winner picks, symmetry and the 50/50 baseline.
Calibration is not an arbitrary reduction in confidence.

The original fifteen measurements plus four opponent-context features and
two age terms give 21 fitted inputs. The model remains transparent logistic
regression with zero intercept and training-only standardization.

## Chronological training and evaluation

1. Train settings-selection models on eligible fights before 2019.
2. Choose half-life, smoothing and regularization using 2019-2021 only.
3. Fit annual earlier-year models to obtain 2022-2024 forecasts. Fit the
   symmetric calibration scalar on those forecasts, not their training fits.
4. Evaluate 2025 and 2026 with annual models fitted before the evaluated
   year and the frozen earlier calibration. Both algorithms score identical bouts.
5. Fit the deployable updated model on available eligible fights through
   June 27, 2026. Current matchups use that fit; historical tests use annual fits.

All fighter and population updates are delayed until the entire date is
processed. Same-night fights cannot leak into each other's prior histories.
Draws/no contests contribute observed history but are excluded from binary
training/evaluation targets. Eligibility requires two earlier fights and ten
minutes per fighter. The selected regularization is `C=0.01`.

The supplied comparison covers 502 fights from January 2025 onward:

| Version | Correct | Accuracy | Log loss | Brier |
| --- | ---: | ---: | ---: | ---: |
| Baseline algorithm, corrected identities | 314 | 62.55% | 0.65229 | 0.23021 |
| Updated, before calibration | 327 | 65.14% | 0.61264 | 0.21200 |
| Updated, calibrated | 327 | 65.14% | 0.60862 | 0.21047 |

Lower log loss/Brier is better. Calibration preserves winner accuracy.
This is retrospective time-ordered evaluation: later results were already
inspected in our broader design discussions. It is not a prospectively
untouched trial, and these results do not establish profitable betting.

The two athletes named Bruno Silva are separated by flyweight/bantamweight
versus middleweight histories before feature construction and training.
The baseline algorithm is refitted with the same corrected identities for
this comparison. Close picks can differ from the older archived baseline
run. No recorded outcomes were changed. Original fitted baseline parameters
are retained in `data/model_parameters.json`.

## Validation and archived-price bets

```matlab
review_model_v2
[bets, summary] = ufc_backtest_v2('LastN', 50, 'Stake', 10);
ufc_backtest_v2('LastN', 30, 'Stake', 10, 'OnlyUnderdogs', true);
ufc_backtest_v2('LastN', 50, 'Stake', 10, 'Model', 'baseline');
```

The upgraded independent evaluation period starts in 2025. Older periods
selected settings or calibrated the model. The betting reader uses saved
earlier-year predictions; it does not apply today's fitted coefficients to
old training fights. Positive American odds, including +100, define the
underdog option. Last-N ties on a date use ascending bundled bout ID; no
intraday timing is claimed.

Quotes match exact dates, both fighter identities, and corner orientation.
Source zero-based IDs are converted to MATLAB one-based IDs. Matching,
provenance and odds timing limits are retained in the `data/odds_*` files.
Returns are illustrative archived-price results, not proof those exact
quotes could have been executed. The separate original `review_ufc_odds`
archive still describes the old model; use `ufc_backtest_v2` for this update.

## Original tools

```matlab
ufc_toolkit('fighter', 'Alexander Volkanovski')
ufc_toolkit('search', 'Silva')
ufc_toolkit('correlation')
ufc_toolkit('correlation', 'Mode', 'within')
ufc_toolkit('scatter', 'slpm')
ufc_toolkit('scatter', 'slpm', 'View', 'probability', 'MinFights', 3)
```

Career profiles and descriptive correlation/stat-scatter views describe raw
observed statistics, not the smoothed predictive inputs. The probability
scatter defaults to updated historical forecasts. Select `Model`,
`baseline` for the original saved 2023-2026 archive. Correlation
`Mode='weights'` still displays baseline coefficients; updated coefficients
are in `R.FeatureComparison`. `README_legacy.md` documents the original views.

## Retraining and verification

The download is already fitted. Optional `ufc_upgrade_model` performs all
fitting, chronological calibration and validation in base MATLAB. To add or
correct a birth date, edit `data/fighter_birth_dates.csv` using its exact
Fighter identifier and an ISO `yyyy-MM-dd` DOB, then run:

```matlab
ufc_upgrade_model
clear functions
```

Append complete raw bouts before fitting newly available fight data. New
historical bets also need independently aligned odds. Updated `AsOf` is a
forecast date; a date on/before the fitted model's last training date is
refused to prevent future-trained historical predictions. Use the backtest
for earlier fights.

Run `ufc_selftest`, or `ufc_selftest(true)` to include figures. It checks the
packaged snapshot against independent Python fixtures: raw imports,
identities, all prior features, recency, same-day/future isolation, fitting,
calibration, missing-age neutrality, symmetry, graph totals and bet arithmetic.
The fixtures apply to the bundled data; changing the source snapshot needs
new reference fixtures for a full parity comparison.

`validation/build_reference.py` uses scikit-learn fitting and SciPy calibration
as an optional independent implementation and future Python starting point.
MATLAB never invokes it.

Stance matchup features, Elo, random forests, special head-to-head weighting,
injuries and a hardcoded inactivity penalty are outside these five additions.
Fight statistics still end **June 27, 2026**. A later forecast date advances
age and recency but cannot invent unrecorded performances.

## Implementation checks

The numerical MATLAB engine was executed in Octave 8.4 and matched an
independent Python reference for features, fitting, calibration and exact
probability contributions. MATLAB-specific table I/O and the graphical
interface could not be executed here. Run `ufc_selftest` after extraction;
`ufc_v2_selftest(true)` also checks figure creation. Numeric verification
errors are recorded in `results_v2/verification.json`.
