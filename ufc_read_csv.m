function T = ufc_read_csv(path)
%UFC_READ_CSV Import original CSV columns as strings without inferred dates.
    assert(isfile(path), 'ufc:MissingFile', 'Required file not found: %s', path);
    opts = detectImportOptions(path, 'Delimiter', ',', 'VariableNamingRule', 'preserve');
    opts = setvartype(opts, opts.VariableNames, 'string');
    T = readtable(path, opts, 'Encoding', 'UTF-8');
end
