function [History, Figures, Details] = ufc_fighter_history(fighter, varargin)
%UFC_FIGHTER_HISTORY Review saved forecasts and explain individual old fights.
% Save beside ufc_toolkit.m in the extracted V2 folder.
%   ufc_fighter_history('Merab Dvalishvili')
%   ufc_fighter_history('Merab Dvalishvili', 'Breakdowns', true)
%   [H,F,R] = ufc_fighter_history('Petr Yan', 'Breakdowns', true, 'LastN', 3)
%   ufc_fighter_history('Petr Yan', 'BoutID', 1234, 'Breakdowns', true)
% Only forecasts in results_v2/historical_predictions.csv are included.
% Category explanations refit the appropriate earlier-year model with frozen
% settings/calibration; neither current nor future bout outcomes train it.

    if nargin < 1 || strlength(strtrim(string(fighter))) == 0
        fighter = input('Fighter name: ', 's');
    end
    root = fileparts(mfilename('fullpath'));
    p = inputParser;
    addParameter(p, 'DataDir', fullfile(root, 'data'));
    addParameter(p, 'Breakdowns', false, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'LastN', Inf, @(x) isscalar(x) && x >= 1 && (isinf(x) || x == fix(x)));
    addParameter(p, 'BoutID', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
    addParameter(p, 'Plot', true, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'Print', true, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'Visible', 'on');
    parse(p, varargin{:}); o = p.Results;

    D = ufc_toolkit('load', 'DataDir', char(o.DataDir));
    name = ufc_resolve_name(D, fighter);
    file = fullfile(fileparts(char(o.DataDir)), 'results_v2', 'historical_predictions.csv');
    H = ufc_read_csv(file);
    red = H.Red == name; blue = H.Blue == name;
    H = H(red | blue, :); red = H.Red == name;
    assert(~isempty(H), 'ufc:NoHistoricalForecasts', ...
        ['No saved evaluation forecasts for %s. The bundled updated archive ' ...
         'starts in January 2025 and does not cover every career fight.'], name);

    boutID = str2double(H.BoutID);
    date = datetime(H.Date, 'InputFormat', 'yyyy-MM-dd');
    date.Format = 'yyyy-MM-dd';
    fitted = datetime(H.FitThrough, 'InputFormat', 'yyyy-MM-dd');
    fitted.Format = 'yyyy-MM-dd';
    probability = str2double(H.UpdatedProbabilityRed);
    actual = str2double(H.Y);
    opponent = H.Blue;
    opponent(~red) = H.Red(~red);
    probability(~red) = 1 - probability(~red);
    actual(~red) = 1 - actual(~red);
    assert(all(isfinite(probability) & probability >= 0 & probability <= 1) ...
        && all(ismember(actual, [0 1])) && all(fitted < date), ...
        'ufc:ForecastArchive', 'Saved forecasts contain invalid probabilities, results or fit dates.');

    result = repmat("Loss", height(H), 1); result(actual == 1) = "Win";
    prediction = repmat("Loss", height(H), 1);
    prediction(probability > 0.5) = "Win";
    prediction(probability == 0.5) = "No pick";
    pick = opponent; pick(probability > 0.5) = name;
    pick(probability == 0.5) = "No pick";
    scored = probability ~= 0.5;
    correct = scored & ((probability > 0.5) == (actual == 1));
    status = repmat("Incorrect", height(H), 1);
    status(correct) = "Correct"; status(~scored) = "Unscored";
    History = table(boutID, date, repmat(name, height(H), 1), opponent, ...
        100*probability, pick, prediction, result, status, correct, scored, fitted, ...
        'VariableNames', {'BoutID', 'Date', 'Fighter', 'Opponent', ...
        'WinChancePercent', 'ModelPick', 'PredictedResult', 'ActualResult', ...
        'PredictionStatus', 'Correct', 'Scored', 'FitThrough'});
    if ~isempty(o.BoutID)
        History = History(History.BoutID == o.BoutID, :);
        assert(~isempty(History), 'ufc:BoutNotFound', 'That BoutID is not a saved forecast for this fighter.');
    end
    History = sortrows(History, {'Date', 'BoutID'}, {'descend', 'descend'});
    History = History(1:min(height(History), o.LastN), :);
    History = sortrows(History, {'Date', 'BoutID'}, {'ascend', 'ascend'});
    if o.Print
        fprintf('\n%s | %d saved historical forecasts\n', name, height(History));
        fprintf('These are the recorded earlier-year forecasts, not today''s model applied to old fights.\n');
        disp(History(:, {'BoutID', 'Date', 'Opponent', 'WinChancePercent', ...
            'PredictedResult', 'ActualResult', 'PredictionStatus'}));
        count = sum(History.Scored);
        if count > 0
            fprintf('Overall accuracy in this selection: %d/%d = %.1f%%.\n', ...
                sum(History.Correct), count, 100*sum(History.Correct)/count);
        end
    end

    Figures = struct('Overview', [], 'Breakdowns', gobjects(0, 1));
    Details = struct('BoutID', {}, 'Date', {}, 'Opponent', {}, ...
        'ArchivedProbability', {}, 'ReconstructedProbability', {}, ...
        'FeatureComparison', {}, 'Contributions', {}, 'FitThrough', {});
    if o.Plot, Figures.Overview = overview(History, name, o.Visible); end
    if ~o.Breakdowns, return; end

    U = D.Updated;
    assert(~isempty(U), 'ufc:UpdatedModelMissing', 'The updated V2 model is required.');
    C = U.Model.Config; n = height(D.Bouts); F = U.Features;
    X = F(1:n, :) - F(n+1:end, :);
    years = year(D.Bouts.Date); info = U.Info;
    eligible = isfinite(D.Bouts.Y) & years >= C.StartYear & ...
        info.PriorBouts(1:n) >= C.MinFights & info.PriorBouts(n+1:end) >= C.MinFights & ...
        info.PriorMinutes(1:n) >= C.MinMinutes & info.PriorMinutes(n+1:end) >= C.MinMinutes;
    fittedYears = []; fits = {}; cutoffs = NaT(0, 1);
    for k = 1:height(History)
        yr = year(History.Date(k)); slot = find(fittedYears == yr, 1);
        if isempty(slot)
            train = eligible & years < yr;
            assert(any(train), 'ufc:HistoricalTraining', 'No earlier training fights for %d.', yr);
            if o.Print, fprintf('Reconstructing model fitted before %d (once per year)...\n', yr); end
            fits{end+1} = ufc_v2_core('fit', X(train, :), D.Bouts.Y(train), C.C); %#ok<AGROW>
            fittedYears(end+1) = yr; %#ok<AGROW>
            cutoffs(end+1, 1) = max(D.Bouts.Date(train)); %#ok<AGROW>
            slot = numel(fits);
        end
        row = find(D.Bouts.BoutID == History.BoutID(k), 1);
        assert(~isempty(row) && D.Bouts.Date(row) == History.Date(k), ...
            'ufc:HistoricalIdentity', 'Saved forecast does not match the raw bout date and ID.');
        if D.Bouts.Red(row) == name
            a = row; b = row+n; other = D.Bouts.Blue(row);
        else
            assert(D.Bouts.Blue(row) == name, 'ufc:HistoricalIdentity', 'Fighter does not match this bout.');
            a = row+n; b = row; other = D.Bouts.Red(row);
        end
        assert(other == History.Opponent(k) && cutoffs(slot) == History.FitThrough(k), ...
            'ufc:HistoricalIdentity', 'Opponent or historical training cutoff differs from the archive.');
        [features, contributions, reconstructed] = explainFight( ...
            F(a, :), F(b, :), fits{slot}, C, U.Model.Calibration.Slope);
        archived = History.WinChancePercent(k)/100;
        assert(abs(reconstructed-archived) < 2e-4, 'ufc:HistoricalParity', ...
            ['Reconstructed probability differs from the saved archive. Source data/settings ' ...
             'may have changed; regenerate the historical forecasts before explaining them.']);
        Details(k) = struct('BoutID', History.BoutID(k), 'Date', History.Date(k), ...
            'Opponent', other, 'ArchivedProbability', archived, ...
            'ReconstructedProbability', reconstructed, 'FeatureComparison', features, ...
            'Contributions', contributions, 'FitThrough', cutoffs(slot)); %#ok<AGROW>
        if o.Plot
            Figures.Breakdowns(end+1, 1) = breakdown(History(k, :), ...
                contributions, reconstructed, name, o.Visible); %#ok<AGROW>
        end
        if o.Print
            fprintf('%s versus %s: archived %.2f%%; reconstructed %.2f%%; actual %s.\n', ...
                string(History.Date(k), 'yyyy-MM-dd'), other, 100*archived, ...
                100*reconstructed, History.ActualResult(k));
        end
        drawnow;
    end
end

function [T, G, probability] = explainFight(a, b, fit, C, slope)
    difference = a(:)-b(:); missing = ~isfinite(difference);
    difference(missing) = 0;
    logOdds = slope*(difference./fit.Scale(:)).*fit.Coefficient(:);
    T = table(string(C.Keys(:)), string(C.Labels(:)), a(:), b(:), ...
        difference, logOdds, missing, 'VariableNames', ...
        {'Key', 'Metric', 'FighterValue', 'OpponentValue', 'DifferenceUsed', ...
        'LogOddsContribution', 'MissingComparison'});
    groups = C.GroupIndex(:);
    grouped = accumarray(groups, logOdds);
    [phi, baseline, probability] = ufc_probability_effects(grouped, 0);
    G = table(string(C.GroupLabels(:)), 100*phi, -100*phi, ...
        'VariableNames', {'Category', 'FighterPercentagePoints', 'OpponentPercentagePoints'});
    assert(abs(baseline+sum(phi)-probability) < 1e-9, ...
        'ufc:HistoricalAttribution', 'Contributions do not reproduce the prediction.');
    [~, order] = sort(abs(phi), 'descend'); G = G(order, :);
end

function fig = overview(T, name, visible)
    fig = figure('Name', char(name+" historical predictions"), 'Color', 'w', ...
        'Visible', char(visible), 'Position', [90 70 1200 max(420, 170+48*height(T))]);
    ax = axes(fig);
    bars = barh(ax, 1:height(T), T.WinChancePercent, 0.65, 'FaceColor', 'flat');
    colors = repmat([0.78 0.23 0.20], height(T), 1);
    colors(T.Correct, :) = repmat([0.12 0.57 0.35], sum(T.Correct), 1);
    colors(~T.Scored, :) = repmat([0.55 0.55 0.55], sum(~T.Scored), 1);
    bars.CData = colors;
    labels = string(T.Date, 'yyyy-MM-dd')+" | "+T.Opponent+ ...
        " | actual "+T.ActualResult+" | predicted "+T.PredictedResult;
    set(ax, 'YTick', 1:height(T), 'YTickLabel', cellstr(labels), ...
        'TickLabelInterpreter', 'none', 'YDir', 'reverse');
    xline(ax, 50, '--k', '50%'); xlim(ax, [0 105]); ylim(ax, [0.3 height(T)+0.7]);
    for k = 1:height(T)
        text(ax, T.WinChancePercent(k)+1, k, sprintf('%.1f%%', T.WinChancePercent(k)), 'FontSize', 9);
    end
    xlabel(ax, 'Archived predicted probability of this fighter winning (%)');
    title(ax, {char(name+" | historical model predictions"), ...
        'Green = correct winner pick; red = incorrect; gray = no pick'}, 'Interpreter', 'none');
    grid(ax, 'on'); box(ax, 'off');
    ax.Position = [0.47 0.13 0.48 0.73];
end

function fig = breakdown(H, G, probability, name, visible)
    fig = figure('Name', char(name+" vs "+H.Opponent+" historical breakdown"), ...
        'Color', 'w', 'Visible', char(visible), 'Position', [100 60 1250 850]);
    ax = axes(fig);
    barh(ax, [G.FighterPercentagePoints G.OpponentPercentagePoints], 'grouped');
    set(ax, 'YTick', 1:height(G), 'YTickLabel', cellstr(G.Category), ...
        'TickLabelInterpreter', 'none', 'YDir', 'reverse');
    xline(ax, 0, 'k-'); grid(ax, 'on'); box(ax, 'off');
    xlabel(ax, 'Contribution to win probability from a 50/50 baseline (percentage points)');
    legend(ax, {char(name), char(H.Opponent)}, 'Interpreter', 'none', 'Location', 'best');
    title(ax, {sprintf('%s | %s %.1f%% versus %s %.1f%%', ...
        string(H.Date, 'yyyy-MM-dd'), name, 100*probability, H.Opponent, 100*(1-probability)), ...
        sprintf('Actual result for %s: %s | model pick: %s | %s', ...
        name, H.ActualResult, H.ModelPick, H.PredictionStatus)}, 'Interpreter', 'none');
    ax.Position = [0.37 0.11 0.59 0.75];
end
