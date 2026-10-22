function [T, fig] = ufc_scatter(D, metric, varargin)
%UFC_SCATTER Actual win rate versus a stat, probability, pick rate or accuracy.
% View='accuracy': y is correct win OR loss predictions / scored predictions.
    if nargin < 2 || isempty(metric), metric = 'slpm'; end
    p = inputParser;
    addParameter(p, 'View', 'stat');
    addParameter(p, 'Model', 'updated');
    addParameter(p, 'MinFights', 5, @(x) isscalar(x) && x >= 1);
    addParameter(p, 'Division', 'All');
    addParameter(p, 'AsOf', []);
    addParameter(p, 'Highlight', strings(0, 1));
    addParameter(p, 'ShowLabels', false, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'Plot', true, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'Visible', 'on');
    parse(p, varargin{:});
    opt = p.Results;
    view = lower(string(opt.View));
    assert(any(view == ["stat", "probability", "pickrate", "accuracy"]), 'ufc:View', ...
        'View must be stat, probability, pickrate, or accuracy.');
    if isempty(opt.AsOf), P = D.Profiles; else, P = ufc_profiles(D, opt.AsOf); end
    if view == "stat"
        j = find(strcmpi(D.MetricKeys, string(metric)) | strcmpi(D.MetricLabels, string(metric)), 1);
        assert(~isempty(j), 'ufc:Metric', 'Unknown metric. Run ufc_toolkit(''metrics'') for the available keys.');
        S = P.Summary;
        T = table(S.Fighter, S.Wins + S.Losses, S.WinRate, P.Metrics(:, j), ...
            S.LatestDivision, 'VariableNames', {'Fighter', 'DecisiveFights', ...
            'ActualWinRate', 'StatValue', 'LatestDivision'});
        T = T(T.DecisiveFights >= opt.MinFights & isfinite(T.ActualWinRate) & isfinite(T.StatValue), :);
        ylabelText = char(D.MetricLabels(j));
        units = D.MetricUnits(j);
        y = T.StatValue;
        if units == "fraction", y = 100*y; ylabelText = [ylabelText ' (%)']; end
        heading = sprintf('Career stat versus decisive win rate | through %s', string(P.AsOf, 'yyyy-MM-dd'));
        note = 'One point per fighter. Career stats include all measured bouts; win rate excludes draws and no contests.';
    else
        selectedModel = lower(string(opt.Model));
        assert(ismember(selectedModel,["updated","baseline"]),'ufc:ModelChoice', ...
            'Model must be updated or baseline.');
        if selectedModel == "updated"
            file = fullfile(fileparts(char(D.DataDir)),'results_v2','historical_predictions.csv');
            H = ufc_read_csv(file);
            H.date = H.Date; H.red_fighter = H.Red; H.blue_fighter = H.Blue;
            H.y = H.Y; H.stats_probability_red_wins = H.UpdatedProbabilityRed;
            probabilityNote = 'Updated v2: annual earlier-year predictions from 2025 onward; calibration uses earlier years.';
        else
            assert(~isempty(D.Heldout), 'ufc:Predictions', 'heldout_predictions.csv is required for the probability view.');
            H = D.Heldout;
            probabilityNote = 'Original baseline: held-out 2023-2026 predictions. Minimum test-bout filter applies.';
        end
        dates = datetime(H.date, 'InputFormat', 'yyyy-MM-dd');
        use = dates <= P.AsOf;
        H = H(use, :);
        assert(~isempty(H), 'ufc:NoPredictions', 'No held-out predictions on or before this date.');
        yOutcome = str2double(H.y);
        pRed = str2double(H.stats_probability_red_wins);
        valid = isfinite(yOutcome) & ismember(yOutcome, [0 1]) & ...
            isfinite(pRed) & pRed >= 0 & pRed <= 1;
        H = H(valid, :); yOutcome = yOutcome(valid); pRed = pRed(valid);
        assert(~isempty(H), 'ufc:NoPredictions', 'No valid decisive-fight forecasts match this view.');
        names = [H.red_fighter; H.blue_fighter];
        actual = [yOutcome; 1-yOutcome]; expected = [pRed; 1-pRed];
        [uniqueNames, ~, id] = unique(names);
        n = accumarray(id, ones(size(id)));
        actualMean = accumarray(id, actual, [], @mean);
        expectedMean = accumarray(id, expected, [], @mean);
        % Pick rate counts forecasts above 50%, independently of confidence.
        % An exact 50/50 forecast counts as no winner pick for either fighter.
        predictedWins = accumarray(id, double(expected > 0.5), [], @sum);
        predictedWinRate = predictedWins ./ n;
        % Score each forecast against the result from that fighter's side.
        % Exact 50/50 forecasts are unpicked and excluded from accuracy only.
        pickedWin = expected > 0.5;
        pickedLoss = expected < 0.5;
        actualWins = accumarray(id, double(actual == 1), [], @sum);
        correctWins = accumarray(id, double(pickedWin & actual == 1), [], @sum);
        correctLosses = accumarray(id, double(pickedLoss & actual == 0), [], @sum);
        scoredPredictions = accumarray(id, double(pickedWin | pickedLoss), [], @sum);
        correctPredictions = correctWins + correctLosses;
        latestDivision = strings(numel(uniqueNames), 1);
        [known, loc] = ismember(uniqueNames, P.Summary.Fighter);
        latestDivision(known) = P.Summary.LatestDivision(loc(known));
        T = table(uniqueNames, n, actualMean, expectedMean, latestDivision, ...
            'VariableNames', {'Fighter', 'DecisiveFights', 'ActualWinRate', ...
            'ExpectedWinRate', 'LatestDivision'});
        T.WinRateMinusExpected = T.ActualWinRate - T.ExpectedWinRate;
        T.PredictedWins = predictedWins;
        T.PredictedWinRate = predictedWinRate;
        T.WinRateMinusPickRate = T.ActualWinRate - T.PredictedWinRate;
        T.ActualWins = actualWins;
        T.CorrectlyIdentifiedWins = correctWins;
        T.WinRecall = safeFraction(correctWins, actualWins);
        T.HitRate = safeFraction(correctWins, predictedWins);
        T.CorrectlyIdentifiedLosses = correctLosses;
        T.CorrectPredictions = correctPredictions;
        T.ScoredPredictions = scoredPredictions;
        T.UnpickedFights = n - scoredPredictions;
        T.PredictionAccuracy = safeFraction(correctPredictions, scoredPredictions);
        T = T(T.DecisiveFights >= opt.MinFights, :);
        if view == "accuracy"
            T = T(isfinite(T.PredictionAccuracy), :);
            y = 100*T.PredictionAccuracy;
            ylabelText = 'Overall prediction accuracy: correct win or loss picks (%)';
            heading = sprintf('%s: actual fighter win rate versus model accuracy',selectedModel);
        elseif view == "pickrate"
            y = 100*T.PredictedWinRate;
            ylabelText = 'Fights the model picked the fighter to win (%)';
            heading = sprintf('%s: actual win rate versus model pick rate',selectedModel);
        else
            y = 100*T.ExpectedWinRate;
            ylabelText = 'Average predicted win probability against recorded opponents (%)';
            heading = sprintf('%s: actual win rate versus average model probability',selectedModel);
        end
        note = probabilityNote;
    end
    if ~strcmpi(opt.Division, 'All')
        keep = strcmpi(T.LatestDivision, string(opt.Division));
        T = T(keep, :); y = y(keep);
        heading = [heading ' | latest division: ' char(string(opt.Division))];
    end
    assert(height(T) >= 2, 'ufc:ScatterSample', 'At least two fighters must match the scatter filters.');
    x = 100*T.ActualWinRate;
    fig = [];
    if ~opt.Plot, return; end
    fig = figure('Name', 'UFC fighter scatter', 'Color', 'w', ...
        'Visible', char(opt.Visible), 'Position', [100 100 1120 760]);
    ax = axes(fig);
    points = scatter(ax, x, y, 22 + 4*sqrt(T.DecisiveFights), T.DecisiveFights, ...
        'filled', 'MarkerFaceAlpha', 0.62);
    hold(ax, 'on');
    if numel(unique(x)) >= 2
        trend = polyfit(x, y, 1);
        xx = linspace(min(x), max(x), 150);
        plot(ax, xx, polyval(trend, xx), 'k-', 'LineWidth', 1.4, 'HandleVisibility', 'off', ...
            'HitTest', 'off', 'PickableParts', 'none');
    end
    if view == "probability" || view == "pickrate"
        plot(ax, [0 100], [0 100], '--', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off', ...
            'HitTest', 'off', 'PickableParts', 'none');
        ylim(ax, [0 100]);
    elseif view == "accuracy"
        % Accuracy and fighter win rate are different measurements, so there
        % is no equal-actual/predicted diagonal in this view.
        ylim(ax, [0 100]);
    end
    highlights = string(opt.Highlight(:));
    for k = 1:numel(highlights)
        name = ufc_resolve_name(D, highlights(k));
        selected = find(T.Fighter == name);
        if isempty(selected)
            fprintf('%s does not meet the current scatter filters.\n', name);
            continue;
        end
        scatter(ax, x(selected), y(selected), 120, [0.85 0.23 0.16], ...
            'LineWidth', 1.8, 'HandleVisibility', 'off', 'HitTest', 'off', 'PickableParts', 'none');
        text(ax, x(selected), y(selected), "  " + name, 'Interpreter', 'none', ...
            'FontSize', 10, 'FontWeight', 'bold');
    end
    if opt.ShowLabels
        text(ax, x, y, " " + T.Fighter, 'Interpreter', 'none', 'FontSize', 8);
    end
    xlabel(ax, 'Actual decisive win rate (%)'); ylabel(ax, ylabelText, 'Interpreter', 'none');
    title(ax, heading, 'Interpreter', 'none'); xlim(ax, [0 100]);
    grid(ax, 'on'); box(ax, 'off');
    color = colorbar(ax); color.Label.String = 'Number of decisive fights in this view';
    annotation(fig, 'textbox', [0.04 0.005 0.92 0.045], 'String', note, ...
        'EdgeColor', 'none', 'FontSize', 9);
    % Link point tips to fighter names rather than displaying anonymous x/y.
    points.UserData = T;
    cursor = datacursormode(fig);
    cursor.UpdateFcn = @fighterTip;
end

function lines = fighterTip(~, event)
    T = event.Target.UserData;
    k = event.DataIndex;
    if ~istable(T) || k < 1 || k > height(T)
        lines = {sprintf('X: %.3f', event.Position(1)), sprintf('Y: %.3f', event.Position(2))};
        return;
    end
    lines = {char(T.Fighter(k)), sprintf('Actual win rate: %.1f%%', 100*T.ActualWinRate(k)), ...
        sprintf('Decisive fights: %d', T.DecisiveFights(k))};
    if ismember('StatValue', T.Properties.VariableNames)
        lines{end+1} = sprintf('Stat (stored units): %.4f', T.StatValue(k));
    else
        lines{end+1} = sprintf('Picked to win: %d/%d (%.1f%%)', ...
            T.PredictedWins(k), T.DecisiveFights(k), 100*T.PredictedWinRate(k));
        lines{end+1} = sprintf('Average predicted probability: %.1f%%', 100*T.ExpectedWinRate(k));
        lines{end+1} = fractionTip('Correctly identified wins', ...
            T.CorrectlyIdentifiedWins(k), T.ActualWins(k));
        lines{end+1} = fractionTip('Hit rate when picking fighter', ...
            T.CorrectlyIdentifiedWins(k), T.PredictedWins(k));
        lines{end+1} = fractionTip('Overall prediction accuracy', ...
            T.CorrectPredictions(k), T.ScoredPredictions(k));
        if T.UnpickedFights(k) > 0
            lines{end+1} = sprintf('50/50 forecasts excluded from accuracy: %d', T.UnpickedFights(k));
        end
    end
end

function value = safeFraction(numerator, denominator)
    value = NaN(size(numerator));
    known = denominator > 0;
    value(known) = numerator(known) ./ denominator(known);
end

function line = fractionTip(label, numerator, denominator)
    if denominator > 0
        line = sprintf('%s: %d/%d (%.1f%%)', label, numerator, ...
            denominator, 100*numerator/denominator);
    else
        line = sprintf('%s: N/A (no qualifying fights)', label);
    end
end
