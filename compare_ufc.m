function [R, fig] = compare_ufc(fighterA, fighterB, varargin)
%COMPARE_UFC Print win probabilities and graph every model category's effect.
% Put this file beside ufc_toolkit.m in your existing UFC_MATLAB_Toolkit folder.
%
%   compare_ufc                         prompt for two fighter names
%   R = compare_ufc('Alexander Volkanovski', 'Movsar Evloev');
%   [R, fig] = compare_ufc('Max Holloway', 'Alexander Volkanovski');
%   compare_ufc('Alexander Volkanovski', 'Movsar Evloev', ...
%       'SaveFile', 'volk_vs_evloev.png');
%
% Options: SaveFile (PNG/PDF), DataDir, AsOf, AllowLimitedHistory, Plot,
% Print, Visible. Base MATLAB R2021a+; no extra toolboxes.
% R.ProbabilityA/B are fractions; R.PercentA/B are percentages.
% R.Contributions contains each fighter's percentage-point contribution.
% Uses updated v2 by default. Select 'Model','baseline' for the original fit.
    if nargin == 0
        fighterA = strtrim(input('Fighter A: ', 's'));
        fighterB = strtrim(input('Fighter B: ', 's'));
    elseif nargin < 2
        error('ufc:Arguments', 'Supply two names, or call compare_ufc with no arguments.');
    end
    assert(exist('ufc_toolkit', 'file') == 2, 'ufc:ToolkitMissing', ...
        'Put compare_ufc.m in your UFC_MATLAB_Toolkit folder and open that folder in MATLAB.');
    p = inputParser;
    addParameter(p, 'DataDir', '', @(x) ischar(x) || (isstring(x) && isscalar(x)));
    addParameter(p, 'AsOf', []);
    addParameter(p, 'Model', 'updated');
    addParameter(p, 'Division', '');
    addParameter(p, 'AllowLimitedHistory', false, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'Plot', true, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'Print', true, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'Visible', 'on');
    addParameter(p, 'SaveFile', '', @(x) ischar(x) || (isstring(x) && isscalar(x)));
    parse(p, varargin{:});
    opts = p.Results;
    assert(opts.Plot || strlength(string(opts.SaveFile)) == 0, 'ufc:SavePlot', ...
        'SaveFile requires Plot=true. Use Visible=off to save without showing the figure.');
    args = {'AsOf', opts.AsOf, 'AllowLimitedHistory', opts.AllowLimitedHistory, ...
            'Plot', false, 'Print', false,'Model',opts.Model,'Division',opts.Division};
    if strlength(string(opts.DataDir)) > 0
        args = [args, {'DataDir', char(string(opts.DataDir))}];
    end
    R = ufc_toolkit('matchup', fighterA, fighterB, args{:});
    T = R.Comparison;
    R.FeatureComparison = T;
    if isfield(R,'GroupIndex')
        T = groupFeatures(T,R);
    end
    % The original model intercept is zero, so its neutral baseline is 50/50.
    intercept = R.Score - sum(T.LogOddsContribution);
    assert(abs(intercept) < 1e-10, 'ufc:ModelChanged', ...
        'This graph requires a zero-intercept symmetric UFC model.');
    intercept = 0;
    [phi, base, probability] = ufc_probability_effects(T.LogOddsContribution, intercept);
    assert(abs(probability - R.ProbabilityA) < 1e-10, 'ufc:AttributionProbability', ...
        'Attribution calculation must reproduce the matchup probability.');
    T.FighterA_PercentagePoints = 100 * phi;
    T.FighterB_PercentagePoints = -100 * phi;
    T.GraphLabel = graphLabels(T.Key, T.Metric);
    [~, order] = sort(abs(phi), 'descend');
    T = T(order, :);
    R.PercentA = 100 * R.ProbabilityA;
    R.PercentB = 100 * R.ProbabilityB;
    R.Contributions = T;
    R.BaselinePercentA = 100 * base;
    R.BaselinePercentB = 100 * (1-base);
    R.ContributionMethod = "Exact Shapley effects relative to equal fighter values";
    R.ProbabilitySummary = table([R.FighterA; R.FighterB], [R.PercentA; R.PercentB], ...
        'VariableNames', {'Fighter', 'WinChancePercent'});
    assert(abs(R.BaselinePercentA + sum(T.FighterA_PercentagePoints) - R.PercentA) < 1e-8);
    assert(abs(R.BaselinePercentB + sum(T.FighterB_PercentagePoints) - R.PercentB) < 1e-8);
    if opts.Print
        fprintf('\n%s: %.1f%% | %s: %.1f%%\n', R.FighterA, R.PercentA, R.FighterB, R.PercentB);
        fprintf('Profiles through %s; model fit through %s.\n', ...
            string(R.ProfileThroughDate, 'yyyy-MM-dd'), R.ModelFitThrough);
        fprintf('Model: %s.\n',R.ModelName);
        if isfield(R,'CalibrationSlope')
            fprintf('Recency half-life %.1f years; smoothing %.0f minutes; calibration %.3f.\n', ...
                R.HalfLifeYears,R.PriorMinutes,R.CalibrationSlope);
            fprintf('Fighter ages: %.1f and %.1f years; fight data through %s.\n', ...
                R.AgeYears(1),R.AgeYears(2),string(R.DataCutoff,'yyyy-MM-dd'));
        end
        if ~R.MeetsHistoryRule
            fprintf('Exploratory estimate: one or both fighters have limited recorded history.\n');
        end
        disp(R.ProbabilitySummary);
        disp(T(:, {'Metric', 'FighterA', 'FighterB', 'FighterA_PercentagePoints', ...
            'FighterB_PercentagePoints', 'MissingComparison'}));
        fprintf('Percentage-point columns show each category''s contribution from a 50/50 baseline.\n');
        fprintf('%s: 50%% %+.2f points = %.2f%%\n', R.FighterA, sum(T.FighterA_PercentagePoints), R.PercentA);
        fprintf('%s: 50%% %+.2f points = %.2f%%\n', R.FighterB, sum(T.FighterB_PercentagePoints), R.PercentB);
        fprintf('Accuracies/shares are fractions; experience is log(1 + bouts); the age row shows years.\n');
        fprintf('Effects describe the fitted model. Overlapping stats can have counterintuitive signs.\n');
    end
    fig = [];
    if opts.Plot
        fig = drawGraph(R, opts.Visible);
    end
    R.SavedGraph = "";
    if strlength(string(opts.SaveFile)) > 0
        path = char(string(opts.SaveFile));
        [parent, ~, ext] = fileparts(path);
        assert(ismember(lower(string(ext)), [".png", ".pdf"]), 'ufc:SaveExtension', ...
            'SaveFile must end in .png or .pdf.');
        assert(isempty(parent) || isfolder(parent), 'ufc:SaveFolder', ...
            'The output folder does not exist: %s', parent);
        if strcmpi(ext, '.pdf')
            exportgraphics(fig, path, 'ContentType', 'vector', 'BackgroundColor', 'white');
        else
            exportgraphics(fig, path, 'Resolution', 200, 'BackgroundColor', 'white');
        end
        R.SavedGraph = string(path);
        if opts.Print, fprintf('Saved graph: %s\n', path); end
    end
end

function G = groupFeatures(T,R)
% Treat both age terms as one category while retaining all 21 feature rows.
    groups = R.GroupIndex(:);
    first = zeros(max(groups),1);
    for k = 1:max(groups), first(k) = find(groups == k,1); end
    G = T(first,:);
    for k = 1:max(groups)
        ix = groups == k;
        G.LogOddsContribution(k) = sum(T.LogOddsContribution(ix));
        G.RawLogOddsContribution(k) = sum(T.RawLogOddsContribution(ix));
        G.MissingComparison(k) = any(T.MissingComparison(ix));
        G.Metric(k) = R.GroupLabels(k);
        if sum(ix) > 1
            G.Key(k) = "age_curve";
            G.FighterA(k) = R.AgeYears(1); G.FighterB(k) = R.AgeYears(2);
            G.DifferenceUsed(k) = R.AgeYears(1)-R.AgeYears(2);
            G.StandardizedAdvantage(k) = NaN; G.Coefficient(k) = NaN;
        end
    end
end

function labels = graphLabels(keys, fallback)
    labels = string(fallback);
    for j = 1:numel(keys)
        switch keys(j)
            case "slpm", labels(j) = "Significant strikes landed / min";
            case "sapm", labels(j) = "Significant strikes absorbed / min";
            case "sig_accuracy", labels(j) = "Significant-strike accuracy";
            case "sig_defense", labels(j) = "Significant-strike defense";
            case "td_per15", labels(j) = "Takedowns landed / 15 min";
            case "td_defense", labels(j) = "Takedown defense";
            case "sub_per15", labels(j) = "Submission attempts / 15 min";
            case "kd_per15", labels(j) = "Knockdowns scored / 15 min";
            case "kd_abs_per15", labels(j) = "Knockdowns suffered / 15 min";
            case "control_share", labels(j) = "Own control time share*";
            case "opp_control_share", labels(j) = "Opponent control time share";
            case "body_share", labels(j) = "Body share of strikes landed*";
            case "leg_share", labels(j) = "Leg share of strikes landed*";
            case "ground_share", labels(j) = "Ground share of strikes landed*";
            case "experience", labels(j) = "Recorded fight experience*";
        end
    end
end

function fig = drawGraph(R, visibility)
    T = R.Contributions;
    n = height(T);
    blue = [0.09 0.41 0.61]; orange = [0.78 0.42 0.13];
    fig = figure('Name', 'UFC matchup - win probabilities and category effects', ...
        'Color', 'w', 'Visible', char(visibility), 'Position', [70 60 1200 920]);
    header = sprintf('%s  vs  %s\n%s: %.1f%%     |     %s: %.1f%%', ...
        R.FighterA, R.FighterB, R.FighterA, R.PercentA, R.FighterB, R.PercentB);
    annotation(fig, 'textbox', [0.03 0.875 0.94 0.105], 'String', header, ...
        'EdgeColor', 'none', 'FontSize', 16, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'Interpreter', 'none');
    subtitle = sprintf('%s | profiles through %s | fitted through %s', ...
        R.ModelName,string(R.ProfileThroughDate, 'yyyy-MM-dd'), R.ModelFitThrough);
    if isfield(R,'DataCutoff')
        subtitle = [subtitle sprintf(' | source fights through %s',string(R.DataCutoff,'yyyy-MM-dd'))];
    end
    if ~R.MeetsHistoryRule, subtitle = [subtitle ' | LIMITED HISTORY']; end
    annotation(fig, 'textbox', [0.03 0.835 0.94 0.04], 'String', subtitle, ...
        'EdgeColor', 'none', 'FontSize', 10, 'HorizontalAlignment', 'center', 'Interpreter', 'none');
    ax = axes('Parent', fig, 'Position', [0.32 0.235 0.64 0.55]);
    hold(ax, 'on');
    y = (1:n)';
    ba = barh(ax, y-0.17, T.FighterA_PercentagePoints, 0.30, ...
        'FaceColor', blue, 'EdgeColor', 'none');
    bb = barh(ax, y+0.17, T.FighterB_PercentagePoints, 0.30, ...
        'FaceColor', orange, 'EdgeColor', 'none');
    maximum = max(abs(T.FighterA_PercentagePoints));
    limit = max(1, maximum * 1.24 + 0.25);
    xlim(ax, [-limit limit]); ylim(ax, [0.45 n+0.55]);
    xline(ax, 0, '-', 'Color', [0.2 0.24 0.3], 'LineWidth', 1.1, 'HandleVisibility', 'off');
    set(ax, 'YTick', y, 'YTickLabel', cellstr(T.GraphLabel), 'YDir', 'reverse', ...
        'FontSize', 10, 'TickLabelInterpreter', 'none', 'TickLength', [0 0]);
    ax.XGrid = 'on'; ax.YGrid = 'off'; ax.GridAlpha = 0.15; box(ax, 'off');
    xlabel(ax, {'Change in estimated win probability (percentage points)', ...
        'Left decreases that fighter''s chance; right increases it'}, 'FontSize', 11);
    legend(ax, [ba bb], cellstr([R.FighterA; R.FighterB]), ...
        'Location', 'northoutside', 'Orientation', 'horizontal', 'Box', 'off', 'Interpreter', 'none');
    gap = 0.018 * limit;
    for j = 1:n
        addLabel(ax, T.FighterA_PercentagePoints(j), y(j)-0.17, blue, gap);
        addLabel(ax, T.FighterB_PercentagePoints(j), y(j)+0.17, orange, gap);
    end
    note = sprintf(['Starting point: 50%% each. Category bars total %+.2f points for %s and %+.2f for %s.\n' ...
        'Effects average across every possible order of adding the categories (exact Shapley calculation).\n' ...
        'A category absent from the calculation has equal fighter values. Effects explain this fitted model.\n' ...
        '*Overlapping stats can have counterintuitive signs; style shares are not inherently advantages.'], ...
        sum(T.FighterA_PercentagePoints), R.FighterA, sum(T.FighterB_PercentagePoints), R.FighterB);
    if any(T.MissingComparison)
        note = [note newline 'Undefined comparisons receive a neutral zero difference.'];
    end
    annotation(fig, 'textbox', [0.035 0.035 0.93 0.135], 'String', note, ...
        'EdgeColor', 'none', 'FontSize', 9, 'Interpreter', 'none', ...
        'VerticalAlignment', 'top', 'Color', [0.32 0.37 0.43]);
end

function addLabel(ax, value, y, color, gap)
    alignment = 'left'; direction = 1;
    if value < 0, alignment = 'right'; direction = -1; end
    text(ax, value + direction*gap, y, sprintf('%+.2f', value), ...
        'HorizontalAlignment', alignment, 'VerticalAlignment', 'middle', ...
        'Color', color, 'FontSize', 9, 'Interpreter', 'none');
end
