% Run all four requested features with editable example inputs.
toolkitFolder = fileparts(mfilename('fullpath'));
addpath(toolkitFolder);
fighterA = 'Max Holloway';
fighterB = 'Alexander Volkanovski';
selectedMetric = 'slpm';

% 1. Correlations centered on a vertical zero line.
correlations = ufc_toolkit('correlation', 'XLimit', 0.25);

% 2. One fighter's complete profile and bout history.
fighterProfile = ufc_toolkit('fighter', fighterA);

% 3. Matchup probabilities and each feature's contribution.
matchup = ufc_toolkit('matchup', fighterA, fighterB);

% 4. Stat versus actual win rate, with the selected fighter highlighted.
statScatter = ufc_toolkit('scatter', selectedMetric, 'Highlight', fighterA);

% Companion view: actual held-out win rate versus average predicted probability.
probabilityScatter = ufc_toolkit('scatter', selectedMetric, 'View', 'probability');
