function [name, id] = ufc_resolve_name(D, query)
%UFC_RESOLVE_NAME Exact names or unambiguous partial names; never guess ties.
    query = string(query);
    assert(isscalar(query) && ~ismissing(query) && strlength(strtrim(query)) > 0, ...
        'ufc:Name', 'Enter a fighter name.');
    normalized = normalize(D.Names);
    q = normalize(query);
    assert(strlength(q) > 0, 'ufc:Name', 'Enter letters or numbers from a fighter name.');
    candidates = find(normalized == q);
    if isempty(candidates), candidates = find(contains(normalized, q)); end
    if numel(candidates) == 1
        id = candidates;
        name = D.Names(id);
    elseif isempty(candidates)
        error('ufc:NameNotFound', 'No fighter matches "%s". Use ufc_toolkit(''search'', ''part of name'').', query);
    else
        text = strjoin(D.Names(candidates(1:min(15, numel(candidates)))), ', ');
        error('ufc:AmbiguousName', 'More than one fighter matches "%s": %s. Enter a fuller name.', query, text);
    end
end

function out = normalize(value)
    out = regexprep(upper(strtrim(string(value))), '[^A-Z0-9]', '');
end
