function [phi, baseline, full] = ufc_probability_effects(contributions, intercept)
%UFC_PROBABILITY_EFFECTS Exact final-probability Shapley decomposition.
% Average each category's probability effect across all possible addition orders.
% Missing/absent categories have zero fighter difference. No model refit occurs.
    c = contributions(:);
    n = numel(c);
    assert(n >= 1 && n <= 20 && all(isfinite(c)), 'ufc:AttributionSize', ...
        'Exact attribution supports 1 to 20 finite model contributions (updated graph: 20 categories).');
    scores = intercept;
    sizes = 0;
    for j = 1:n
        scores = [scores; scores + c(j)]; %#ok<AGROW>
        sizes = [sizes; sizes + 1]; %#ok<AGROW>
    end
    values = logistic(scores);
    states = uint32((0:(2^n-1))');
    weights = zeros(n, 1);
    for k = 0:n-1
        weights(k+1) = 1 / (n * nchoosek(n-1, k));
    end
    phi = zeros(n, 1);
    for j = 1:n
        absent = bitget(states, j) == 0;
        indices = double(states(absent));
        gains = values(indices + 2^(j-1) + 1) - values(indices + 1);
        phi(j) = sum(weights(sizes(absent)+1) .* gains);
    end
    baseline = values(1);
    full = values(end);
    assert(abs(sum(phi) - (full-baseline)) < 1e-10, 'ufc:AttributionTotal', ...
        'Category effects must sum to the complete prediction minus baseline.');
end

function p = logistic(x)
    p = zeros(size(x));
    nonnegative = x >= 0;
    p(nonnegative) = 1 ./ (1 + exp(-x(nonnegative)));
    e = exp(x(~nonnegative));
    p(~nonnegative) = e ./ (1 + e);
end

