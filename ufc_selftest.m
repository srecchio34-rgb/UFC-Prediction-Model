function passed = ufc_selftest(testFigures)
%UFC_SELFTEST Verify import, strict history, correlations and matchup symmetry.
% ufc_selftest          numerical checks against independent Python fixtures
% ufc_selftest(true)    also construct and close the four figure types
    if nargin < 1, testFigures = false; end
    root = fileparts(mfilename('fullpath'));
    if isfile(fullfile(root,'data','model_v2.json'))
        passed = ufc_v2_selftest(testFigures);
        return
    end
    D = ufc_load_data(fullfile(root, 'data'));
    F = jsondecode(fileread(fullfile(root, 'data', 'verification.json')));
    assert(height(D.Bouts) == F.source_bouts && numel(D.Names) == F.source_fighters);
    assert(sum(isfinite(D.Bouts.Y)) == F.decisive_bouts);
    T = ufc_correlations(D, 'Bootstrap', 0, 'Plot', false);
    assert(height(T) == 42);
    for k = 1:numel(F.correlations)
        ref = F.correlations(k);
        j = find(T.Key == string(ref.key), 1);
        assert(~isempty(j) && abs(T.Correlation(j)-ref.r) < 1e-10, ...
            'ufc:TestCorrelation', 'Correlation mismatch for %s.', ref.key);
        assert(T.NonTiedFights(j) == ref.non_tied_fights);
        assert(T.ComparableFights(j) == ref.comparable_fights);
    end
    for k = 1:numel(F.profiles)
        ref = F.profiles(k);
        P = ufc_profile(D, string(ref.name), 'Print', false);
        assert(P.Summary.Bouts == ref.bouts && P.Summary.Wins == ref.wins && P.Summary.Losses == ref.losses);
        expected = ref.metrics(:);
        actual = P.MetricValues(:);
        assert(isequal(isnan(expected), isnan(actual)));
        valid = isfinite(expected);
        assert(max(abs(actual(valid)-expected(valid))) < 1e-9, ...
            'ufc:TestProfile', 'Profile metric mismatch for %s.', ref.name);
    end
    n = height(D.Bouts);
    for k = 1:numel(F.histories)
        ref = F.histories(k);
        row = ref.bout_id_one_based;
        if string(ref.side) == "blue", row = row+n; end
        assert(D.Rows.Fighter(row) == string(ref.name));
        assert(D.PriorState(row, strcmp(D.Fields, 'bouts')) == ref.prior_bouts);
        j = find(D.MetricKeys == "slpm", 1);
        assert(abs(D.PriorMetrics(row, j)-ref.slpm) < 1e-9);
        j = find(D.MetricKeys == "sig_accuracy", 1);
        assert(abs(D.PriorMetrics(row, j)-ref.sig_accuracy) < 1e-9);
    end
    A = string(F.matchup.fighter_a); B = string(F.matchup.fighter_b);
    R = ufc_matchup(D, A, B, 'Plot', false, 'Print', false);
    reverse = ufc_matchup(D, B, A, 'Plot', false, 'Print', false);
    assert(abs(R.ProbabilityA-F.matchup.probability_a) < 1e-10);
    assert(abs(R.ProbabilityA+R.ProbabilityB-1) < 1e-14);
    assert(abs(R.ProbabilityA+reverse.ProbabilityA-1) < 1e-14);
    ambiguous = false;
    try
        ufc_resolve_name(D, 'Nurmagomedov');
    catch problem
        ambiguous = strcmp(problem.identifier, 'ufc:AmbiguousName');
    end
    assert(ambiguous, 'ufc:TestNames', 'Ambiguous name must not silently choose a fighter.');
    S = ufc_scatter(D, 'slpm', 'Plot', false);
    assert(height(S) == F.stat_scatter_fighters);
    Q = ufc_scatter(D, 'slpm', 'View', 'probability', 'Plot', false);
    assert(height(Q) == F.probability_scatter_fighters);
    assert(all(Q.ActualWinRate >= 0 & Q.ActualWinRate <= 1));
    assert(all(Q.ExpectedWinRate >= 0 & Q.ExpectedWinRate <= 1));
    if testFigures
        [~, fig] = ufc_correlations(D, 'Bootstrap', 20, 'TopN', 12, 'Visible', 'off'); close(fig);
        [~, fig] = ufc_matchup(D, A, B, 'Print', false, 'Visible', 'off'); close(fig);
        [~, fig] = ufc_scatter(D, 'slpm', 'Visible', 'off'); close(fig);
        [~, fig] = ufc_scatter(D, 'slpm', 'View', 'probability', 'Visible', 'off'); close(fig);
    end
    passed = true;
    fprintf('PASS: CSV import, 42 correlations, profiles, strict histories, name ambiguity, matchup symmetry and scatter data.\n');
end
