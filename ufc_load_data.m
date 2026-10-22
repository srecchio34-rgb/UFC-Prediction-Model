function D = ufc_load_data(dataDir)
%UFC_LOAD_DATA Import raw bouts and derive current and strictly prior metrics.
% Base MATLAB R2021a+. No Statistics and Machine Learning Toolbox required.
    if nargin < 1
        dataDir = fullfile(fileparts(mfilename('fullpath')), 'data');
    end
    raw = ufc_read_csv(fullfile(dataDir, 'ufc_raw_stats_recovered.csv'));
    n = height(raw);
    dates = datetime(raw.event_date, 'InputFormat', 'dd/MM/yyyy');
    seconds = elapsedTime(raw);
    assert(all(isfinite(seconds) & seconds > 0), 'ufc:Duration', 'Invalid fight duration.');
    divisions = strings(n, 1);
    for k = 1:n
        divisions(k) = weightClass(raw.bout_type(k));
    end
    % Two distinct UFC athletes share this exact source name. Split them
    % before deriving histories so a flyweight never inherits middleweight stats.
    for corner = {'red','blue'}
        key = [corner{1} '_fighter_name'];
        ambiguous = raw.(key) == "BRUNO SILVA";
        light = ismember(divisions,["Flyweight","Bantamweight"]);
        raw.(key)(ambiguous & light) = "BRUNO SILVA (FLYWEIGHT)";
        raw.(key)(ambiguous & ~light) = "BRUNO SILVA (MIDDLEWEIGHT)";
    end
    outcome = raw.fight_outcome;
    y = NaN(n, 1);
    y(outcome == "red_win") = 1;
    y(outcome == "blue_win") = 0;
    assert(all(ismember(outcome, ["red_win", "blue_win", "draw", "no_contest"])), ...
        'ufc:Outcome', 'Unsupported outcome in the raw file.');
    B = table((1:n)', dates, raw.event_name, divisions, raw.red_fighter_name, ...
        raw.blue_fighter_name, outcome, y, seconds, ...
        'VariableNames', {'BoutID', 'Date', 'Event', 'Division', 'Red', 'Blue', ...
        'Outcome', 'Y', 'Seconds'});
    B.EventKey = string(B.Date, 'yyyy-MM-dd') + "|" + B.Event;
    L = table([(1:n)'; (1:n)'], [dates; dates], [raw.event_name; raw.event_name], ...
        [divisions; divisions], [raw.red_fighter_name; raw.blue_fighter_name], ...
        [raw.blue_fighter_name; raw.red_fighter_name], ...
        [raw.red_fighter_result; raw.blue_fighter_result], [y; 1-y], ...
        [ones(n, 1); 2*ones(n, 1)], ...
        'VariableNames', {'BoutID', 'Date', 'Event', 'Division', 'Fighter', ...
        'Opponent', 'Result', 'Win', 'Side'});
    [names, ~, fighterID] = unique(L.Fighter);
    L.FighterID = fighterID;
    fields = {};
    bases = {'sig_str', 'total_str', 'TD', 'sig_str_head', 'sig_str_body', ...
        'sig_str_leg', 'sig_str_distance', 'sig_str_clinch', 'sig_str_ground'};
    for j = 1:numel(bases)
        fields(end+1:end+2) = {[bases{j} '_landed'], [bases{j} '_attempted']}; %#ok<AGROW>
    end
    own = fields;
    for j = 1:numel(own)
        fields{end+1} = ['opp_' own{j}]; %#ok<AGROW>
    end
    fields = [fields, {'kd', 'sub', 'rev', 'opp_kd', 'opp_sub', 'opp_rev', ...
        'seconds', 'ctrl', 'ctrl_seconds', 'opp_ctrl', 'opp_ctrl_seconds', 'bouts'}];
    S = zeros(2*n, numel(fields));
    fieldIndex = @(key) find(strcmp(fields, key), 1);
    for side = 1:2
        if side == 1
            corner = 'red'; other = 'blue'; ix = (1:n)';
        else
            corner = 'blue'; other = 'red'; ix = (n+1:2*n)';
        end
        corners = {corner, other};
        prefixes = {'', 'opp_'};
        for which = 1:2
            for j = 1:numel(bases)
                values = raw.([corners{which} '_fighter_' bases{j}]);
                pairs = parsePairs(values);
                S(ix, fieldIndex([prefixes{which} bases{j} '_landed'])) = pairs(:, 1);
                S(ix, fieldIndex([prefixes{which} bases{j} '_attempted'])) = pairs(:, 2);
            end
            shorts = {'kd', 'sub', 'rev'};
            originals = {'KD', 'sub_att', 'rev'};
            for j = 1:3
                values = str2double(raw.([corners{which} '_fighter_' originals{j}]));
                assert(all(isfinite(values) & values >= 0), 'ufc:Count', 'Invalid count.');
                S(ix, fieldIndex([prefixes{which} shorts{j}])) = values;
            end
            control = parseTime(raw.([corners{which} '_fighter_ctrl']));
            known = isfinite(control);
            assert(all(control(known) <= seconds(known)), 'ufc:ControlTime', ...
                'Control time exceeds fight duration.');
            control(~known) = 0;
            S(ix, fieldIndex([prefixes{which} 'ctrl'])) = control;
            S(ix, fieldIndex([prefixes{which} 'ctrl_seconds'])) = seconds .* known;
        end
        S(ix, fieldIndex('seconds')) = seconds;
        S(ix, fieldIndex('bouts')) = 1;
    end
    partitions = {{'head', 'body', 'leg'}, {'distance', 'clinch', 'ground'}};
    for prefix = {'', 'opp_'}
        for part = 1:numel(partitions)
            for ending = {'landed', 'attempted'}
                total = zeros(2*n, 1);
                for target = partitions{part}
                    total = total + S(:, fieldIndex([prefix{1} 'sig_str_' target{1} '_' ending{1}]));
                end
                expected = S(:, fieldIndex([prefix{1} 'sig_str_' ending{1}]));
                assert(all(total == expected), 'ufc:StrikeSubtotal', 'Striking subtotals do not match.');
            end
        end
    end
    % The first row of each fighter/date group receives the same prior state.
    % Subtracting the whole current date protects same-night tournaments.
    P = zeros(size(S));
    for f = 1:numel(names)
        ix = find(fighterID == f);
        [~, order] = sortrows([datenum(L.Date(ix)), L.BoutID(ix)], [1, 2]); %#ok<DATNM>
        ix = ix(order);
        prior = [zeros(1, size(S, 2)); cumsum(S(ix(1:end-1), :), 1)];
        firstOfDate = [true; diff(L.Date(ix)) ~= days(0)];
        starts = find(firstOfDate);
        stops = [starts(2:end)-1; numel(ix)];
        for g = 1:numel(starts)
            P(ix(starts(g):stops(g)), :) = repmat(prior(starts(g), :), ...
                stops(g)-starts(g)+1, 1);
        end
    end
    definitions = ufc_read_csv(fullfile(dataDir, 'metric_definitions.csv'));
    D = struct('Raw', raw, 'Bouts', B, 'Rows', L, 'State', S, 'PriorState', P, ...
        'Fields', {fields}, 'Names', names, 'MetricKeys', definitions.key, ...
        'MetricLabels', definitions.label, 'MetricUnits', definitions.unit, ...
        'DataDir', string(dataDir), 'DataCutoff', max(dates));
    D.CurrentMetrics = ufc_metrics(S, fields, D.MetricKeys);
    D.PriorMetrics = ufc_metrics(P, fields, D.MetricKeys);
    D.Model = jsondecode(fileread(fullfile(dataDir, 'model_parameters.json')));
    assert(numel(D.Model.features) == numel(D.Model.coefficient) && ...
        numel(D.Model.scale) == numel(D.Model.coefficient) && all(D.Model.scale > 0), ...
        'ufc:Model', 'Model features, coefficients, or scales are invalid.');
    bioFile = fullfile(dataDir, 'ufc_bouts_recovered.csv');
    D.Bio = table();
    if isfile(bioFile)
        bio = ufc_read_csv(bioFile);
        namesAll = [bio.red_fighter_name; bio.blue_fighter_name];
        heights = [str2double(bio.red_fighter_height); str2double(bio.blue_fighter_height)];
        reaches = [str2double(bio.red_fighter_reach); str2double(bio.blue_fighter_reach)];
        stances = [bio.red_fighter_stance; bio.blue_fighter_stance];
        [uniqueNames, first] = unique(namesAll);
        D.Bio = table(uniqueNames, heights(first), reaches(first), stances(first), ...
            'VariableNames', {'Fighter', 'HeightCM', 'ReachCM', 'Stance'});
    end
    predFile = fullfile(dataDir, 'heldout_predictions.csv');
    D.Heldout = table();
    if isfile(predFile)
        D.Heldout = ufc_read_csv(predFile);
    end
    D.Profiles = ufc_profiles(D, D.DataCutoff);
    D.IdentityVersion = 2;
    modelFile = fullfile(dataDir,'model_v2.json');
    D.Updated = [];
    if isfile(modelFile)
        M = jsondecode(fileread(modelFile));
        C = M.Config;
        N = ufc_v2_prepare(D,C);
        [F,S,info] = ufc_v2_core('build',N,C);
        D.Updated = struct('Model',M,'Inputs',N,'Features',F,'State',S,'Info',info);
    end
end

function pairs = parsePairs(values)
    tokens = regexp(cellstr(values), '^\s*(\d+)\s+of\s+(\d+)\s*$', 'tokens', 'once');
    pairs = zeros(numel(values), 2);
    for k = 1:numel(values)
        assert(~isempty(tokens{k}), 'ufc:CountPair', 'Malformed count: %s', values(k));
        pairs(k, :) = str2double(tokens{k});
    end
    assert(all(pairs(:, 1) <= pairs(:, 2)), 'ufc:CountPair', 'Landed count exceeds attempts.');
end

function sec = parseTime(values)
    sec = NaN(numel(values), 1);
    tokens = regexp(cellstr(values), '^(\d+):(\d{2})$', 'tokens', 'once');
    for k = 1:numel(values)
        if isempty(tokens{k}), continue; end
        v = str2double(tokens{k});
        if v(2) < 60, sec(k) = 60*v(1) + v(2); end
    end
end

function sec = elapsedTime(raw)
    sec = parseTime(raw.time);
    rounds = str2double(raw.round);
    for k = 1:height(raw)
        if rounds(k) == 1, continue; end
        token = regexp(char(raw.time_format(k)), '\(([^)]+)\)', 'tokens', 'once');
        assert(~isempty(token), 'ufc:RoundFormat', 'Unknown round schedule.');
        lengths = 60*str2double(strsplit(token{1}, '-'));
        assert(rounds(k) <= numel(lengths) && sec(k) <= lengths(rounds(k)), ...
            'ufc:RoundFormat', 'Invalid round/time combination.');
        sec(k) = sec(k) + sum(lengths(1:rounds(k)-1));
    end
end

function division = weightClass(text)
    classes = ["Light Heavyweight", "Women's Strawweight", "Women's Flyweight", ...
        "Women's Bantamweight", "Women's Featherweight", "Strawweight", ...
        "Flyweight", "Bantamweight", "Featherweight", "Lightweight", ...
        "Welterweight", "Middleweight", "Heavyweight", "Open Weight", "Catch Weight"];
    division = "Other";
    for k = 1:numel(classes)
        if contains(text, classes(k)), division = classes(k); return; end
    end
end
