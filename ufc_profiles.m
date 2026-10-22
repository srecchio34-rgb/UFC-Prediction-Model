function P = ufc_profiles(D, asOf)
%UFC_PROFILES One cumulative profile per fighter, through an inclusive date.
    if nargin < 2 || isempty(asOf)
        asOf = D.DataCutoff;
    else
        asOf = datetime(asOf);
    end
    asOf = dateshift(asOf, 'start', 'day');
    assert(isscalar(asOf) && ~isnat(asOf), 'ufc:Date', 'AsOf must be one valid date.');
    selected = D.Rows.Date <= asOf;
    nF = numel(D.Names);
    ids = D.Rows.FighterID(selected);
    state = zeros(nF, numel(D.Fields));
    for j = 1:numel(D.Fields)
        state(:, j) = accumarray(ids, D.State(selected, j), [nF, 1], @sum, 0);
    end
    results = D.Rows.Result(selected);
    wins = accumarray(ids, double(results == "W"), [nF, 1], @sum, 0);
    losses = accumarray(ids, double(results == "L"), [nF, 1], @sum, 0);
    draws = accumarray(ids, double(results == "D"), [nF, 1], @sum, 0);
    nc = accumarray(ids, double(results == "NC"), [nF, 1], @sum, 0);
    bouts = state(:, strcmp(D.Fields, 'bouts'));
    minutes = state(:, strcmp(D.Fields, 'seconds')) / 60;
    winRate = wins ./ (wins + losses);
    winRate(wins + losses == 0) = NaN;
    lastDate = NaT(nF, 1);
    latestDivision = strings(nF, 1);
    for k = 1:nF
        ix = find(selected & D.Rows.FighterID == k);
        if isempty(ix), continue; end
        [~, order] = sortrows([datenum(D.Rows.Date(ix)), D.Rows.BoutID(ix)], [1, 2]); %#ok<DATNM>
        last = ix(order(end));
        lastDate(k) = D.Rows.Date(last);
        latestDivision(k) = D.Rows.Division(last);
    end
    P = struct();
    P.Summary = table(D.Names, bouts, wins, losses, draws, nc, winRate, minutes, ...
        lastDate, latestDivision, 'VariableNames', {'Fighter', 'Bouts', 'Wins', ...
        'Losses', 'Draws', 'NoContests', 'WinRate', 'Minutes', 'LastFight', 'LatestDivision'});
    P.State = state;
    P.Metrics = ufc_metrics(state, D.Fields, D.MetricKeys);
    P.AsOf = min(asOf, D.DataCutoff);
end
