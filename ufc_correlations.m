function [T, fig] = ufc_correlations(D, varargin)
%UFC_CORRELATIONS Paired correlation bars centered on a vertical zero line.
% Mode: prefight, within, physical (snapshots), or weights (joint coefficients).
    p = inputParser;
    addParameter(p, 'Mode', 'prefight');
    addParameter(p, 'Division', 'All');
    addParameter(p, 'From', []);
    addParameter(p, 'To', []);
    addParameter(p, 'MinPriorFights', 2, @(x) isscalar(x) && x >= 0);
    addParameter(p, 'MinPriorMinutes', 10, @(x) isscalar(x) && x >= 0);
    addParameter(p, 'Bootstrap', 500, @(x) isscalar(x) && x >= 0 && x == fix(x));
    addParameter(p, 'TopN', Inf, @(x) isscalar(x) && x >= 1);
    addParameter(p, 'XLimit', 1, @(x) isscalar(x) && x > 0);
    addParameter(p, 'Plot', true, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'Visible', 'on');
    parse(p, varargin{:});
    opt = p.Results;
    mode = lower(string(opt.Mode));
    fig = [];
    if mode == "weights"
        assert(strcmpi(opt.Division, 'All') && isempty(opt.From) && isempty(opt.To), ...
            'ufc:WeightsFilter', 'Bundled model weights are pooled; division/date filters apply to correlations only.');
        C = ufc_read_csv(fullfile(D.DataDir, 'adjusted_coefficients.csv'));
        T = table(C.metric, C.label, str2double(C.coefficient_per_sd_advantage), ...
            log(str2double(C.odds_ratio_ci_low)), log(str2double(C.odds_ratio_ci_high)), ...
            'VariableNames', {'Key', 'Metric', 'Coefficient', 'CILow', 'CIHigh'});
        heading = sprintf('Joint historical-stat weights | model fit through %s', D.Model.fit_end_date);
        axisLabel = 'Standardized log-odds coefficient (not a correlation coefficient)';
    else
        assert(any(mode == ["prefight", "within", "physical"]), 'ufc:Mode', ...
            'Mode must be prefight, within, physical, or weights.');
        n = height(D.Bouts);
        good = isfinite(D.Bouts.Y);
        metricKeys = D.MetricKeys;
        metricLabels = D.MetricLabels;
        if mode == "prefight"
            M = D.PriorMetrics;
            bouts = D.PriorState(:, strcmp(D.Fields, 'bouts'));
            minutes = D.PriorState(:, strcmp(D.Fields, 'seconds')) / 60;
            good = good & bouts(1:n) >= opt.MinPriorFights & bouts(n+1:end) >= opt.MinPriorFights & ...
                minutes(1:n) >= opt.MinPriorMinutes & minutes(n+1:end) >= opt.MinPriorMinutes;
            from = datetime(2000, 1, 1);
        elseif mode == "within"
            M = D.CurrentMetrics;
            from = min(D.Bouts.Date);
        else
            assert(~isempty(D.Bio), 'ufc:Bio', 'Processed bio snapshot file is required for physical correlations.');
            [known, loc] = ismember(D.Rows.Fighter, D.Bio.Fighter);
            M = NaN(2*n, 5);
            M(known, 1) = D.Bio.HeightCM(loc(known));
            M(known, 2) = D.Bio.ReachCM(loc(known));
            stance = strings(2*n, 1);
            stance(known) = D.Bio.Stance(loc(known));
            knownStance = known & ~ismissing(stance) & strlength(strtrim(stance)) > 0;
            categories = ["Southpaw", "Orthodox", "Switch"];
            for c = 1:3, M(knownStance, c+2) = double(stance(knownStance) == categories(c)); end
            metricKeys = ["height_cm"; "reach_cm"; "southpaw"; "orthodox"; "switch"];
            metricLabels = ["Height (cm; snapshot)"; "Reach (cm; snapshot)"; ...
                "Southpaw stance (snapshot)"; "Orthodox stance (snapshot)"; "Switch stance (snapshot)"];
            from = min(D.Bouts.Date);
        end
        if ~isempty(opt.From), from = datetime(opt.From); end
        to = D.DataCutoff;
        if ~isempty(opt.To), to = datetime(opt.To); end
        good = good & D.Bouts.Date >= from & D.Bouts.Date <= to;
        if ~strcmpi(opt.Division, 'All')
            good = good & strcmpi(D.Bouts.Division, string(opt.Division));
        end
        assert(any(good), 'ufc:NoBouts', 'No eligible bouts match these filters.');
        delta = M(1:n, :) - M(n+1:end, :);
        delta = delta(good, :);
        outcome = D.Bouts.Y(good);
        [~, ~, event] = unique(D.Bouts.EventKey(good));
        G = max(event);
        K = numel(metricKeys);
        num = zeros(G, K); sq = num; counts = num;
        correlation = NaN(K, 1); sample = zeros(K, 1); ties = sample;
        nonTied = sample; higherWins = sample; higherWinRate = NaN(K, 1);
        for k = 1:K
            valid = isfinite(delta(:, k));
            d = delta(valid, k); yy = outcome(valid); eg = event(valid);
            signed = d .* (2*yy-1);
            num(:, k) = accumarray(eg, signed, [G, 1], @sum, 0);
            sq(:, k) = accumarray(eg, d.^2, [G, 1], @sum, 0);
            counts(:, k) = accumarray(eg, ones(size(eg)), [G, 1], @sum, 0);
            denom = sqrt(sum(sq(:, k)) * sum(counts(:, k)));
            if denom > 0, correlation(k) = sum(signed)/denom; end
            tied = abs(d) <= 1e-10;
            sample(k) = numel(d); ties(k) = sum(tied); nonTied(k) = sum(~tied);
            higherWins(k) = sum(((d > 0) == yy) & ~tied);
            if nonTied(k) > 0, higherWinRate(k) = higherWins(k)/nonTied(k); end
        end
        lo = NaN(K, 1); hi = lo;
        if opt.Bootstrap > 0
            oldRng = rng;
            cleaner = onCleanup(@() rng(oldRng)); %#ok<NASGU>
            rng(20261021, 'twister');
            boot = NaN(opt.Bootstrap, K);
            for b = 1:opt.Bootstrap
                weight = accumarray(randi(G, G, 1), ones(G, 1), [G, 1]);
                denom = sqrt((weight'*sq) .* (weight'*counts));
                value = (weight'*num) ./ denom;
                value(denom == 0) = NaN;
                boot(b, :) = value;
            end
            for k = 1:K
                lo(k) = percentile(boot(:, k), 0.025);
                hi(k) = percentile(boot(:, k), 0.975);
            end
        end
        T = table(metricKeys, metricLabels, correlation, lo, hi, sample, ...
            ties, nonTied, higherWins, higherWinRate, 'VariableNames', {'Key', ...
            'Metric', 'Correlation', 'CILow', 'CIHigh', 'ComparableFights', 'Ties', ...
            'NonTiedFights', 'HigherStatWins', 'HigherStatWinRate'});
        heading = sprintf('%s stat correlations | %d bouts | %s', mode, sum(good), string(opt.Division));
        axisLabel = 'Paired correlation with winning (r): negative left, positive right';
    end
    if mode == "weights", plotValue = T.Coefficient; else, plotValue = T.Correlation; end
    strength = abs(plotValue);
    strength(~isfinite(strength)) = -Inf;
    [~, order] = sort(strength, 'descend');
    T = T(order, :);
    T = T(1:min(height(T), opt.TopN), :);
    plotValue = plotValue(order);
    plotValue = plotValue(1:height(T));
    if ~opt.Plot, return; end
    fig = figure('Name', 'UFC stat correlations', 'Color', 'w', ...
        'Visible', char(opt.Visible), 'Position', [70 50 1250 960]);
    ax = axes(fig);
    k = height(T);
    bars = barh(ax, 1:k, plotValue, 0.68, 'FaceColor', 'flat');
    colors = repmat([0.06 0.43 0.57], k, 1);
    colors(plotValue < 0, :) = repmat([0.80 0.24 0.22], sum(plotValue < 0), 1);
    bars.CData = colors;
    hold(ax, 'on');
    for j = 1:k
        if isfinite(T.CILow(j)) && isfinite(T.CIHigh(j))
            plot(ax, [T.CILow(j), T.CIHigh(j)], [j j], 'k-', 'LineWidth', 1);
        end
    end
    xline(ax, 0, 'k-', 'LineWidth', 1.3);
    xlim(ax, [-opt.XLimit opt.XLimit]);
    ylim(ax, [0.3 k+0.7]);
    set(ax, 'YTick', 1:k, 'YTickLabel', cellstr(T.Metric), 'YDir', 'reverse', ...
        'TickLabelInterpreter', 'none', 'FontSize', 9);
    xlabel(ax, axisLabel); title(ax, heading, 'Interpreter', 'none');
    grid(ax, 'on'); box(ax, 'off');
    ax.Position = [0.40 0.10 0.56 0.82];
    if mode == "weights"
        note = 'Lines: approximate 95% event-bootstrap intervals of the fitted coefficients.';
    else
        note = sprintf('Lines: approximate 95%% event-bootstrap intervals (%d replicates). Each fight contributes once.', opt.Bootstrap);
    end
    annotation(fig, 'textbox', [0.02 0.015 0.96 0.045], 'String', note, ...
        'EdgeColor', 'none', 'FontSize', 9);
end

function v = percentile(values, p)
    values = sort(values(isfinite(values)));
    if isempty(values), v = NaN; return; end
    at = 1 + (numel(values)-1)*p;
    low = floor(at); high = ceil(at);
    v = values(low) + (at-low)*(values(high)-values(low));
end
