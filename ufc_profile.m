function R = ufc_profile(D, query, varargin)
%UFC_PROFILE Look up one fighter and compare career metrics with division peers.
    p = inputParser;
    addParameter(p, 'AsOf', []);
    addParameter(p, 'PeerMinFights', 5, @(x) isscalar(x) && x >= 1);
    addParameter(p, 'Print', true, @(x) islogical(x) && isscalar(x));
    parse(p, varargin{:});
    [name, id] = ufc_resolve_name(D, query);
    if isempty(p.Results.AsOf)
        P = D.Profiles;
    else
        P = ufc_profiles(D, p.Results.AsOf);
    end
    summary = P.Summary(id, :);
    assert(summary.Bouts > 0, 'ufc:NoHistory', 'No recorded bouts for %s on or before this date.', name);
    peerMask = P.Summary.Bouts >= p.Results.PeerMinFights & ...
        P.Summary.LatestDivision == summary.LatestDivision;
    divisionMean = NaN(numel(D.MetricKeys), 1);
    percentile = divisionMean;
    for k = 1:numel(D.MetricKeys)
        peer = P.Metrics(peerMask, k);
        peer = peer(isfinite(peer));
        value = P.Metrics(id, k);
        if ~isempty(peer)
            divisionMean(k) = mean(peer);
            if isfinite(value)
                percentile(k) = 100 * (sum(peer < value) + 0.5*sum(peer == value)) / numel(peer);
            end
        end
    end
    values = P.Metrics(id, :)';
    formatted = strings(numel(values), 1);
    formattedMean = formatted;
    for k = 1:numel(values)
        formatted(k) = formatMetric(values(k), D.MetricUnits(k));
        formattedMean(k) = formatMetric(divisionMean(k), D.MetricUnits(k));
    end
    stats = table(D.MetricKeys, D.MetricLabels, values, D.MetricUnits, formatted, ...
        divisionMean, formattedMean, percentile, 'VariableNames', ...
        {'Key', 'Metric', 'Value', 'Unit', 'DisplayValue', 'DivisionMean', ...
        'DisplayDivisionMean', 'RawValuePercentile'});
    history = D.Rows(D.Rows.FighterID == id & D.Rows.Date <= P.AsOf, ...
        {'Date', 'Event', 'Division', 'Opponent', 'Result', 'BoutID'});
    history = sortrows(history, {'Date', 'BoutID'}, {'descend', 'descend'});
    bio = table();
    if ~isempty(D.Bio), bio = D.Bio(D.Bio.Fighter == name, :); end
    R = struct('Name', name, 'ID', id, 'Summary', summary, 'Stats', stats, ...
        'History', history, 'BioSnapshot', bio, 'AsOf', P.AsOf, ...
        'State', P.State(id, :), 'MetricValues', P.Metrics(id, :));
    if p.Results.Print
        fprintf('\n%s | through %s\n', name, string(P.AsOf, 'yyyy-MM-dd'));
        fprintf('%d W, %d L, %d D, %d NC | %.1f%% decisive win rate | %.1f minutes\n', ...
            summary.Wins, summary.Losses, summary.Draws, summary.NoContests, ...
            100*summary.WinRate, summary.Minutes);
        fprintf('Latest recorded division: %s | last fight: %s\n', ...
            summary.LatestDivision, string(summary.LastFight, 'yyyy-MM-dd'));
        if ~isempty(bio), disp(bio); end
        disp(stats(:, {'Key', 'Metric', 'DisplayValue', 'DisplayDivisionMean', 'RawValuePercentile'}));
        fprintf('Peer mean: one equally weighted career profile per fighter in the latest division, with at least %d bouts.\n', p.Results.PeerMinFights);
        fprintf('Percentile ranks the raw value; a high percentile in absorbed strikes is not a favorable rating.\n');
        if ~isempty(D.Updated)
            fprintf('These are career statistics. compare_ufc returns the updated model inputs in FeatureComparison.\n');
        end
        disp(history);
    end
end

function text = formatMetric(value, unit)
    if ~isfinite(value), text = "n/a"; return; end
    if unit == "fraction"
        text = string(sprintf('%.1f%%', 100*value));
    else
        text = string(sprintf('%.2f', value));
    end
end
