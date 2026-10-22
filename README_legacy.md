# UFC MATLAB Toolkit

Four functions in one local tool: stat correlations, fighter lookup, matchup
probabilities, and fighter scatter plots. The recovered data and fitted model
are included. You do not need to upload or download anything else to start.

## Start

1. Extract the ZIP.
2. Open the `UFC_MATLAB_Toolkit` folder as MATLAB's Current Folder.
3. Run:

```matlab
start_ufc
```

This opens a numbered menu. The first import calculates all fighter histories
from the raw CSV. Subsequent commands reuse that data in memory.

For an example that executes all four features, run `demo_ufc`. Edit its two
fighter names and selected metric at the top to change the examples.

Target: MATLAB R2021a or later, using base MATLAB functions. No Statistics and
Machine Learning Toolbox or Python installation is needed to use this toolkit.
An active MATLAB license is still needed to run MATLAB; the CSVs and JSON model
are portable to a later Python version.

## 1. Correlation graph

```matlab
C = ufc_toolkit('correlation');
```

Every stat is one horizontal bar. The vertical center line is zero. Right is
positive association with winning, left is negative, and bar length is the
magnitude of the paired correlation. Bars are sorted by absolute strength.
Lines show approximate 95% event-bootstrap intervals using 500 resamples.

The default shows historical statistics before the bout. Both fighters must
have two earlier recorded bouts and ten earlier minutes. Targets include
decisive bouts from 2000 onward. No result or statistic from the same calendar
date enters another fight's pre-fight history.

Useful options:

```matlab
% Show all 42 stats, but zoom the horizontal axis for the modest effects.
C = ufc_toolkit('correlation', 'XLimit', 0.25);

% Show just the 15 strongest associations in one division.
C = ufc_toolkit('correlation', 'Division', 'Lightweight', 'TopN', 15);

% Date filters affect the outcomes being compared, not the prior-history pool.
C = ufc_toolkit('correlation', 'From', '2015-01-01', 'To', '2025-12-31');

% Compare statistics recorded DURING the same fight instead of earlier history.
C = ufc_toolkit('correlation', 'Mode', 'within');

% Height, reach, and stance snapshots, kept separate from historical metrics.
C = ufc_toolkit('correlation', 'Mode', 'physical');

% Conditional weights from the fitted multi-stat model; these are not r values.
W = ufc_toolkit('correlation', 'Mode', 'weights', 'XLimit', 0.5);

% Skip bootstrap intervals for a quicker numerical query.
C = ufc_toolkit('correlation', 'Bootstrap', 0, 'Plot', false);
```

`C.Correlation` is the mirrored paired point-biserial correlation:

```
mean(winner - loser stat difference) / RMS(fighter stat difference)
```

Mirroring defines a neutral orientation; each fight is counted once for sample
sizes and bootstrap grouping. The table also includes valid comparisons, ties,
non-tied comparisons, and the higher-stat fighter's win rate. Ties count in the
correlation but are excluded from that higher-stat win rate.

Negative bars retain the original stat direction. For example, a negative bar
for strikes absorbed means higher absorption accompanies fewer wins. The app
does not flip unfavorable metrics into artificial positive correlations.

## 2. Fighter lookup

```matlab
P = ufc_toolkit('fighter', 'Max Holloway');
P.Summary         % record, win rate, exposure, latest division and last date
P.Stats           % all 42 metrics, peer means and raw-value percentiles
P.History         % individual bouts and results
P.BioSnapshot     % height/reach/stance if present in the processed export

% A historical profile, using bouts on or before this date.
P = ufc_toolkit('fighter', 'Max Holloway', 'AsOf', '2024-01-01');

% Find exact spellings. Ambiguous partial names are never silently selected.
ufc_toolkit('search', 'Nurmagomedov');
```

Names are case-insensitive and ignore punctuation. An unambiguous partial
name works. If more than one fighter matches, the tool lists candidates.

All numerical accuracy, defense and share values are stored as fractions from
0 to 1. `DisplayValue` and `DisplayDivisionMean` format them as percentages.
Striking rates are per minute; takedowns, submissions, knockdowns and reversals
are per 15 minutes.

Career rates use summed counts divided by summed exposure, not the mean of
bout percentages. Control shares omit bouts with unobserved control time from
the denominator. Zero-attempt accuracies remain NaN. All earlier measured
performances, including draws and no contests, contribute statistics.

Record win rate is wins / (wins + losses). Draws and no contests are displayed
separately and are excluded from the win-rate denominator.

Peer means equally weight fighters with at least five recorded bouts in the
fighter's latest division. Those are career profiles, including their history
in other divisions. `RawValuePercentile` ranks the numerical value; a high
percentile in absorbed strikes is not a favorable skill rating. The profile
itself is included in the peer set when eligible. Change the peer threshold
with `'PeerMinFights', 10`.

Physical snapshots are not historical measurements. They remain the export's
height/reach/stance values even when an earlier `AsOf` is requested.

## 3. Two-fighter matchup probabilities

```matlab
R = ufc_toolkit('matchup', 'Max Holloway', 'Alexander Volkanovski');
R.ProbabilityA
R.ProbabilityB
R.Comparison

% Data only, without a figure or printed tables.
R = ufc_toolkit('matchup', 'Max Holloway', 'Alexander Volkanovski', ...
    'Plot', false, 'Print', false);
```

The probabilities sum to 1. Swapping the names reverses them. The tool uses
each fighter's cumulative profile through the dataset cutoff unless an `AsOf`
date is supplied. Different divisions are displayed in the profiles; the model
does not enforce weight-class eligibility for a hypothetical comparison.

`R.Comparison` shows every model feature, both values, the standardized
advantage, and its contribution to the model score. Positive contributions
favor fighter A. Missing comparisons receive a neutral difference of zero,
matching the fitted model, and are explicitly flagged.

The bundled stats-only model has 15 terms, including logged experience:

```
score = sum(coefficient .* ((statsA - statsB) ./ scale))
pA = 1 / (1 + exp(-score))
pB = 1 - pA
```

The model was fitted only to fighters with at least two earlier recorded bouts
and ten minutes each. The same history rule applies by default to profile-based
matchups. If a fighter has at least one recorded bout but fails that rule, an
explicit exploratory override is available:

```matlab
R = ufc_toolkit('matchup', 'Fighter A', 'Fighter B', ...
    'AllowLimitedHistory', true);
```

Replace the placeholder names with actual names. A fighter with no recorded
bouts by the chosen date cannot receive a data-based estimate.

The fitted coefficients were refit on all eligible data through June 27, 2026.
They are separate from the earlier-trained coefficients used for the held-out
2023-2026 predictions. An old `AsOf` profile combined with the current fitted
model is a hypothetical estimate, not a leakage-free historical backtest.
The profile date and model-fit date are returned and printed separately.

## 4. Fighter scatter plots

```matlab
% Actual career win rate on x, selected career stat on y.
S = ufc_toolkit('scatter', 'slpm');

% Show division peers and mark one fighter.
S = ufc_toolkit('scatter', 'sig_accuracy', 'Division', 'Featherweight', ...
    'MinFights', 5, 'Highlight', 'Max Holloway');

% Show everyone with at least one decisive bout and an available stat.
S = ufc_toolkit('scatter', 'td_per15', 'MinFights', 1);

% Actual held-out win rate on x, average predicted probability on y.
Q = ufc_toolkit('scatter', 'slpm', 'View', 'probability');
```

The stat view uses one point per qualifying fighter and adds a linear trend
line. Point size and color show the number of decisive bouts. Click a point
with MATLAB's Data Tips tool to see the fighter's name. All-point labels can
be enabled with `'ShowLabels', true`.

The default minimum is five decisive bouts. The division filter selects a
fighter's latest recorded division; each point's statistics remain their full
recorded career history. An optional `AsOf` changes that history cutoff.

The probability view uses only the archived held-out predictions against the
recorded opponents from January 2023 through June 2026. It excludes fighters
with too few eligible test bouts. It does not invent one opponent-independent
win probability for every fighter. The diagonal line is actual = expected;
the solid line is the descriptive linear trend.

`S` and `Q` return the plotted data so you can label, filter or export it.

## Import and export

```matlab
D = ufc_toolkit('load');
D.Raw              % the original 60 raw CSV columns, imported as strings
D.Bouts            % bout dates, opponents, outcomes, divisions and exposure
D.Rows             % one fighter per bout, both corners retained
D.Fields           % column names for the numeric count/exposure states
D.State            % each fighter-bout's count/exposure contribution
D.PriorState       % summed contributions from strictly earlier dates
D.PriorMetrics     % calculated prior metrics, in D.MetricKeys order

ufc_toolkit('metrics');
writetable(C, 'my_correlations.csv');
exportgraphics(gcf, 'my_chart.png', 'Resolution', 300);
```

The raw CSV has properly quoted cells containing original descriptive PDF line
breaks. The importer handles those cells; do not split the file into records
using one text line per row. Original missing markers remain in the source.

Replace `data/ufc_raw_stats_recovered.csv` with a compatible CSV to add bouts,
then run `ufc_toolkit('reload')`. Correlations and profiles are recalculated.
The bundled coefficients and held-out predictions do not retrain themselves.
To use an externally refitted model, replace `data/model_parameters.json` and
the corresponding `adjusted_coefficients.csv`. Keep the same model schema.

Use another data folder with any action:

```matlab
D = ufc_toolkit('load', 'DataDir', 'C:/my_ufc_data');
```

Required files are the raw CSV, metric definitions, and model parameters.
The processed bio CSV, coefficient CSV, and held-out predictions are needed
only for their respective optional views. This package includes every file.

## Verification

```matlab
ufc_selftest         % import, numerical values, histories, names and symmetry
ufc_selftest(true)   % also construct and close the chart types
```

The tests compare MATLAB output with independent reference results from the
earlier Python analysis: all 42 pre-fight correlations, four fighter profiles,
twelve historical states, a matchup probability, and scatter cohort sizes.
They also check probability symmetry and ambiguous-name handling. Reference
fixtures describe the bundled dataset and must change if that dataset changes.

The source passed a MATLAB R2021a syntax parse using MISS_HIT. The data and
reference calculations were checked in Python. A MATLAB runtime was not
available in the authoring environment, so actual MATLAB execution and figure
rendering must be confirmed by running `ufc_selftest(true)` locally.

`correlation_preview.png` is a Python-rendered preview using the same paired
correlations, not a screenshot of MATLAB. MATLAB calculates its own plot from
the included raw data.

## Data and model scope

Bundled data: 8,737 bouts and 2,693 distinct fighter names, March 11, 1994 through
June 27, 2026. The default historical correlation cohort contains 4,636 decisive
bouts. These are recorded UFC bouts, not complete non-UFC MMA careers.

Intervals resample entire events. Repeat fighters across events are not fully
accounted for, so intervals are approximate. Correlations and conditional model
weights describe associations and are not fractions of wins caused by a stat.

Implementation documentation:
- https://www.mathworks.com/help/matlab/ref/readtable.html
- https://www.mathworks.com/help/matlab/ref/barh.html
- https://www.mathworks.com/help/matlab/ref/jsondecode.html
- https://www.mathworks.com/help/matlab/ref/datacursormanager.html
