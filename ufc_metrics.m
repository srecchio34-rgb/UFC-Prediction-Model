function M = ufc_metrics(S, fields, keys)
%UFC_METRICS Calculate rates from summed raw counts and exposure.
% Missing denominators produce NaN. Accuracy/defense/shares are fractions.
    get = @(name) S(:, find(strcmp(fields, name), 1));
    t = get('seconds');
    sig = get('sig_str_landed');
    V = struct();
    V.slpm = 60 * divide(sig, t);
    V.sapm = 60 * divide(get('opp_sig_str_landed'), t);
    V.sig_accuracy = divide(sig, get('sig_str_attempted'));
    V.sig_defense = 1 - divide(get('opp_sig_str_landed'), get('opp_sig_str_attempted'));
    V.total_slpm = 60 * divide(get('total_str_landed'), t);
    V.total_accuracy = divide(get('total_str_landed'), get('total_str_attempted'));
    V.td_per15 = 900 * divide(get('TD_landed'), t);
    V.td_accuracy = divide(get('TD_landed'), get('TD_attempted'));
    V.td_defense = 1 - divide(get('opp_TD_landed'), get('opp_TD_attempted'));
    V.sub_per15 = 900 * divide(get('sub'), t);
    V.kd_per15 = 900 * divide(get('kd'), t);
    V.kd_abs_per15 = 900 * divide(get('opp_kd'), t);
    V.rev_per15 = 900 * divide(get('rev'), t);
    V.control_share = divide(get('ctrl'), get('ctrl_seconds'));
    V.opp_control_share = divide(get('opp_ctrl'), get('opp_ctrl_seconds'));
    V.sig_attempts_per_min = 60 * divide(get('sig_str_attempted'), t);
    V.total_attempts_per_min = 60 * divide(get('total_str_attempted'), t);
    V.td_attempts_per15 = 900 * divide(get('TD_attempted'), t);
    targets = {'head', 'body', 'leg', 'distance', 'clinch', 'ground'};
    for j = 1:numel(targets)
        target = targets{j};
        base = ['sig_str_' target];
        landed = get([base '_landed']);
        attempted = get([base '_attempted']);
        V.([target '_share']) = divide(landed, sig);
        V.([target '_accuracy']) = divide(landed, attempted);
        V.([target '_landed_per_min']) = 60 * divide(landed, t);
        V.([target '_attempted_per_min']) = 60 * divide(attempted, t);
    end
    M = NaN(size(S, 1), numel(keys));
    for j = 1:numel(keys)
        key = char(keys(j));
        assert(isfield(V, key), 'ufc:UnknownMetric', 'Unknown metric: %s', key);
        M(:, j) = V.(key);
    end
end

function z = divide(a, b)
    z = NaN(size(a));
    valid = isfinite(a) & isfinite(b) & b > 0;
    z(valid) = a(valid) ./ b(valid);
end
