function passed = ufc_v2_selftest(makeFigures)
%UFC_V2_SELFTEST Verify the MATLAB implementation against Python fixtures.
% Includes all-bout feature parity, future/same-day isolation, fitting,
% calibration, fighter identity, neutral unknown age, symmetry and graph sums.
    if nargin < 1, makeFigures = false; end
    root = fileparts(mfilename('fullpath'));
    D = ufc_toolkit('load','DataDir',fullfile(root,'data'));
    U = D.Updated; C = U.Model.Config; N = U.Inputs;
    V = load(fullfile(root,'validation','reference.mat'));
    assert(numel(D.Names) == 2694 && height(D.Bouts) == 8737);
    assert(isequal(N.Raw,V.N.Raw) && isequal(N.Fighter,double(V.N.Fighter)));
    assert(isequal(N.Division,double(V.N.Division)) && isequal(N.Day,V.N.Day));
    assert(isequal(isnan(N.DOB),isnan(V.N.DOB)));
    assert(max(abs(N.DOB(isfinite(N.DOB))-V.N.DOB(isfinite(N.DOB)))) < 1e-9);
    closeEnough(U.Features,V.Features,1e-8);
    closeEnough(U.Info.PriorBouts,V.PriorBouts,1e-10);
    closeEnough(U.Info.PriorMinutes,V.PriorMinutes,1e-8);
    [current,detail] = ufc_v2_core('profiles',U.State,(1:N.FighterCount)', ...
        double(V.CurrentDivision),V.CurrentDay,N.DOB,C);
    closeEnough(current,V.CurrentFeatures,1e-8);
    [~,later] = ufc_v2_core('profiles',U.State,(1:N.FighterCount)', ...
        double(V.CurrentDivision),V.CurrentDay+365.25*C.HalfLifeYears,N.DOB,C);
    closeEnough(later.RecentMinutes,0.5*detail.RecentMinutes,1e-8);
    % Changing this date and all future measurements cannot change predictions
    % on this date or any earlier date, including same-night tournaments.
    perturbed = N; boundary = datenum(2025,1,18); %#ok<DATNM>
    perturbed.Raw(N.Day >= boundary,:) = 1.25*perturbed.Raw(N.Day >= boundary,:);
    changed = ufc_v2_core('build',perturbed,C);
    closeEnough(changed(N.Day <= boundary,:),U.Features(N.Day <= boundary,:),1e-10);
    n = height(D.Bouts); X = U.Features(1:n,:)-U.Features(n+1:end,:);
    eligible = logical(V.Eligible);
    fitted = ufc_v2_core('fit',X(eligible,:),D.Bouts.Y(eligible),C.C);
    closeEnough(fitted.Coefficient,U.Model.Fit.Coefficient(:),2e-5);
    closeEnough(fitted.Scale,U.Model.Fit.Scale(:),1e-9);
    years = year(D.Bouts.Date); z = NaN(n,1);
    for yr = 2022:2024
        train = eligible & years < yr; test = eligible & years == yr;
        fit = ufc_v2_core('fit',X(train,:),D.Bouts.Y(train),C.C);
        z(test) = ufc_v2_core('score',fit,X(test,:));
    end
    use = isfinite(z);
    calibration = ufc_v2_core('calibrate',z(use),D.Bouts.Y(use));
    assert(abs(calibration.Slope-U.Model.Calibration.Slope) < 2e-4);
    a = ufc_resolve_name(D,'Alexander Volkanovski');
    b = ufc_resolve_name(D,'Movsar Evloev');
    forecast = D.DataCutoff+days(1);
    A = ufc_matchup_updated(D,a,b,'AsOf',forecast,'Print',false);
    B = ufc_matchup_updated(D,b,a,'AsOf',forecast,'Print',false);
    assert(abs(A.ProbabilityA+B.ProbabilityA-1) < 1e-12);
    [~,aid] = ufc_resolve_name(D,a);
    noAge = D; noAge.Updated.Inputs.DOB(aid) = NaN;
    missing = ufc_matchup_updated(noAge,a,b,'AsOf',forecast,'Print',false);
    assert(all(missing.Comparison.MissingComparison(20:21)));
    assert(all(missing.Comparison.LogOddsContribution(20:21) == 0));
    R = compare_ufc(a,b,'AsOf',forecast,'Plot',false,'Print',false);
    assert(height(R.Contributions) == 20 && height(R.FeatureComparison) == 21);
    assert(abs(50+sum(R.Contributions.FighterA_PercentagePoints)-R.PercentA) < 1e-8);
    assert(abs(50+sum(R.Contributions.FighterB_PercentagePoints)-R.PercentB) < 1e-8);
    ambiguous = false;
    try, ufc_resolve_name(D,'Bruno Silva');
    catch problem, ambiguous = strcmp(problem.identifier,'ufc:AmbiguousName'); end
    assert(ambiguous,'ufc:IdentityTest','Bruno Silva must resolve to two separate profiles.');
    [bets,total] = ufc_backtest_v2('LastN',50,'Print',false,'Plot',false);
    assert(height(bets) == 50 && abs(sum(bets.Profit)-total.NetProfit) < 1e-10);
    if makeFigures
        [~,fig] = compare_ufc(a,b,'AsOf',forecast,'Print',false,'Visible','off'); close(fig);
        [~,fig] = review_model_v2; close(fig);
    end
    passed = true;
    fprintf(['PASS: all chronological feature fixtures, decay, same-day/future isolation, ' ...
        'fitting, calibration, neutral missing age, identities, symmetry and graph totals.\n']);
end

function closeEnough(a,b,tolerance)
    assert(isequal(size(a),size(b)) && isequal(isnan(a),isnan(b)), ...
        'ufc:FixtureShape','Reference values have different shapes or missingness.');
    good = isfinite(a) & isfinite(b);
    assert(all(abs(a(good)-b(good)) < tolerance),'ufc:FixtureValue', ...
        'MATLAB and the independent reference disagree.');
end
