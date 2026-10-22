% RUN_MATCHUP_GRAPH Edit the two names below, then press Run.
% Put this script and compare_ufc.m beside your existing ufc_toolkit.m.

fighterA = 'Alexander Volkanovski';
fighterB = 'Movsar Evloev';

% Win percentages print in the Command Window and appear on the graph.
% Category bars show percentage points added/subtracted for each fighter.
[result, matchupFigure] = compare_ufc(fighterA, fighterB);

% Convenient numerical outputs in your Workspace:
winProbabilities = result.ProbabilitySummary;
statContributions = result.Contributions;

% To save the entire graph including both total probabilities, uncomment:
% exportgraphics(matchupFigure, 'my_matchup.png', 'Resolution', 200);

% Alternative: prompt for names directly in the Command Window:
% compare_ufc
