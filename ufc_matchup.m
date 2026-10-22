function [R, fig] = ufc_matchup(D, fighterA, fighterB, varargin)
%UFC_MATCHUP Apply the updated model, or select Model='baseline'.
    p = inputParser;
    addParameter(p, 'AsOf', []);
    addParameter(p, 'Model', 'updated');
    addParameter(p, 'Division', '');
    addParameter(p, 'AllowLimitedHistory', false, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'Plot', true, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'Print', true, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'Visible', 'on');
    parse(p, varargin{:});
    selectedModel = lower(string(p.Results.Model));
    assert(ismember(selectedModel,["updated","baseline"]),'ufc:ModelChoice', ...
        'Model must be updated or baseline.');
    if selectedModel == "updated"
        if p.Results.Plot
            [R,fig] = compare_ufc(fighterA,fighterB,'DataDir',D.DataDir, ...
                'Model','updated','AsOf',p.Results.AsOf,'Division',p.Results.Division, ...
                'AllowLimitedHistory',p.Results.AllowLimitedHistory, ...
                'Print',p.Results.Print,'Visible',p.Results.Visible);
        else
            R = ufc_matchup_updated(D,fighterA,fighterB,'AsOf',p.Results.AsOf, ...
                'Division',p.Results.Division,'AllowLimitedHistory',p.Results.AllowLimitedHistory, ...
                'Print',p.Results.Print);
            fig = [];
        end
        return
    end
    A = ufc_profile(D, fighterA, 'AsOf', p.Results.AsOf, 'Print', false);
    B = ufc_profile(D, fighterB, 'AsOf', p.Results.AsOf, 'Print', false);
    assert(A.ID ~= B.ID, 'ufc:SameFighter', 'Select two different fighters.');
    enough = A.Summary.Bouts >= 2 && B.Summary.Bouts >= 2 && ...
        A.Summary.Minutes >= 10 && B.Summary.Minutes >= 10;
    assert(enough || p.Results.AllowLimitedHistory, 'ufc:LimitedHistory', ...
        ['The fitted model requires two recorded bouts and ten minutes per fighter. ' ...
        '%s: %d bouts, %.1f min; %s: %d bouts, %.1f min. ' ...
        'Use AllowLimitedHistory=true only for an exploratory estimate.'], ...
        A.Name, A.Summary.Bouts, A.Summary.Minutes, B.Name, B.Summary.Bouts, B.Summary.Minutes);
    keys = string(D.Model.features(:));
    av = NaN(numel(keys), 1); bv = av;
    labels = strings(numel(keys), 1);
    for k = 1:numel(keys)
        if keys(k) == "experience"
            av(k) = log1p(A.Summary.Bouts);
            bv(k) = log1p(B.Summary.Bouts);
            labels(k) = "Prior recorded fights (log scale)";
        else
            j = find(D.MetricKeys == keys(k), 1);
            assert(~isempty(j), 'ufc:ModelMetric', 'Model metric not present: %s', keys(k));
            av(k) = A.MetricValues(j);
            bv(k) = B.MetricValues(j);
            labels(k) = D.MetricLabels(j);
        end
    end
    difference = av - bv;
    missing = ~isfinite(difference);
    difference(missing) = D.Model.impute_missing_difference;
    scaled = difference ./ D.Model.scale(:);
    coefficients = D.Model.coefficient(:);
    contribution = scaled .* coefficients;
    score = sum(contribution) + D.Model.intercept;
    if score >= 0
        pa = 1 / (1 + exp(-score));
    else
        e = exp(score); pa = e / (1 + e);
    end
    comparison = table(keys, labels, av, bv, difference, scaled, coefficients, ...
        contribution, missing, 'VariableNames', {'Key', 'Metric', 'FighterA', ...
        'FighterB', 'DifferenceUsed', 'StandardizedAdvantage', 'Coefficient', ...
        'LogOddsContribution', 'MissingComparison'});
    [~, order] = sort(abs(contribution), 'descend');
    comparison = comparison(order, :);
    R = struct('FighterA', A.Name, 'FighterB', B.Name, 'ProbabilityA', pa, ...
        'ProbabilityB', 1-pa, 'Score', score, 'Comparison', comparison, ...
        'ProfileA', A, 'ProfileB', B, 'ProfileThroughDate', A.AsOf, ...
        'ModelFitThrough', string(D.Model.fit_end_date), 'MeetsHistoryRule', enough);
    R.ModelName = 'Original baseline';
    fig = [];
    if p.Results.Print
        fprintf('\n%s: %.1f%% | %s: %.1f%%\n', A.Name, 100*pa, B.Name, 100*(1-pa));
        fprintf('Profiles through %s; model fit through %s.\n', ...
            string(A.AsOf, 'yyyy-MM-dd'), string(D.Model.fit_end_date));
        if ~enough, fprintf('Limited-history exploratory estimate.\n'); end
        disp(comparison);
        fprintf('Positive log-odds contributions favor %s. Their sum is the model score.\n', A.Name);
    end
    if p.Results.Plot
        fig = figure('Name', 'UFC matchup probability', 'Color', 'w', ...
            'Visible', char(p.Results.Visible), 'Position', [100 100 1050 430]);
        ax = axes(fig);
        b = barh(ax, [100*pa, 100*(1-pa)], 0.55, 'FaceColor', 'flat');
        b.CData = [0.05 0.42 0.57; 0.82 0.25 0.22];
        set(ax, 'YTick', [1 2], 'YTickLabel', cellstr([A.Name; B.Name]), ...
            'YDir', 'reverse', 'TickLabelInterpreter', 'none', 'FontSize', 12);
        xlim(ax, [0 100]); grid(ax, 'on'); box(ax, 'off');
        xlabel(ax, 'Estimated win probability (%)');
        title(ax, sprintf('Stat-based matchup | profiles through %s', string(A.AsOf, 'yyyy-MM-dd')));
        for k = 1:2
            value = [100*pa, 100*(1-pa)];
            text(ax, max(2, value(k)-2), k, sprintf('%.1f%%', value(k)), ...
                'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle', ...
                'Color', 'k', 'FontWeight', 'bold');
        end
        ax.Position(1) = 0.29; ax.Position(3) = 0.65;
    end
end
