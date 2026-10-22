function N = ufc_v2_prepare(D,C)
%UFC_V2_PREPARE Convert imported tables into numeric chronological inputs.
    n = height(D.Bouts);
    [divisions,~,divisionID] = unique(D.Rows.Division);
    raw = zeros(2*n,numel(C.RawFields));
    for k = 1:numel(C.RawFields)
        j = find(strcmp(D.Fields,C.RawFields{k}),1);
        assert(~isempty(j),'ufc:RawField','Missing raw field: %s',C.RawFields{k});
        raw(:,k) = D.State(:,j);
    end
    dob = NaN(numel(D.Names),1);
    file = fullfile(D.DataDir,'fighter_birth_dates.csv');
    assert(isfile(file),'ufc:BirthDates', ...
        'Keep data/fighter_birth_dates.csv in the extracted toolkit folder.');
    bio = ufc_read_csv(file);
    [found,where] = ismember(D.Names,bio.Fighter);
    valid = found;
    valid(found) = strlength(bio.DOB(where(found))) > 0;
    if any(valid)
        dates = datetime(bio.DOB(where(valid)),'InputFormat','yyyy-MM-dd');
        dob(valid) = datenum(dates); %#ok<DATNM>
    end
    N = struct('Raw',raw,'Fighter',D.Rows.FighterID, ...
        'Opponent',D.Rows.FighterID([n+1:2*n,1:n]), ...
        'OpponentRow',[n+1:2*n,1:n]', ...
        'Day',datenum(D.Rows.Date),'Division',divisionID, ...
        'BoutID',D.Rows.BoutID,'Side',D.Rows.Side,'DOB',dob, ...
        'FighterCount',numel(D.Names),'DivisionCount',numel(divisions), ...
        'DivisionNames',divisions); %#ok<DATNM>
end
