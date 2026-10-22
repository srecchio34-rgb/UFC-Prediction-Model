function R = ufc_matchup_updated(D,fighterA,fighterB,varargin)
%UFC_MATCHUP_UPDATED Apply recency, smoothing, opponent context, age/calibration.
% AsOf is the forecast date: only strictly earlier bouts enter profiles.
    p = inputParser;
    addParameter(p,'AsOf',[]);
    addParameter(p,'Division','');
    addParameter(p,'AllowLimitedHistory',false,@islogical);
    addParameter(p,'Print',true,@islogical);
    parse(p,varargin{:}); o = p.Results;
    assert(~isempty(D.Updated),'ufc:UpdatedModelMissing', ...
        'Extract the complete updated toolkit, including data/model_v2.json.');
    U = D.Updated; M = U.Model; C = M.Config; N = U.Inputs;
    [nameA,idA] = ufc_resolve_name(D,fighterA);
    [nameB,idB] = ufc_resolve_name(D,fighterB);
    assert(idA ~= idB,'ufc:SameFighter','Select two different fighters.');
    if isempty(o.AsOf), forecast = datetime('today'); else, forecast = datetime(o.AsOf); end
    forecast = dateshift(forecast,'start','day');
    assert(isscalar(forecast) && ~isnat(forecast),'ufc:Date','AsOf must be one date.');
    fitted = datetime(M.FitThrough,'InputFormat','yyyy-MM-dd');
    assert(forecast > fitted,'ufc:HistoricalModel', ...
        ['The updated fitted model includes results through %s. Use a later AsOf date ' ...
         'for a new prediction, or use ufc_backtest_v2 for historical evaluation.'],M.FitThrough);
    day = datenum(forecast); %#ok<DATNM>
    ids = [idA;idB]; divs = zeros(2,1); last = NaT(2,1);
    for k = 1:2
        rows = find(N.Fighter == ids(k) & N.Day < day);
        assert(~isempty(rows),'ufc:NoHistory','No earlier recorded fights for %s.',D.Names(ids(k)));
        [~,order] = sortrows([N.Day(rows),N.BoutID(rows)],[1 2]);
        row = rows(order(end)); divs(k) = N.Division(row); last(k) = D.Rows.Date(row);
    end
    if strlength(string(o.Division)) > 0
        chosen = find(strcmpi(N.DivisionNames,string(o.Division)),1);
        assert(~isempty(chosen),'ufc:WeightClass','Unknown division: %s',string(o.Division));
        divs(:) = chosen;
    else
        assert(divs(1) == divs(2),'ufc:WeightClass', ...
            ['Latest recorded divisions differ. Specify the booked division, ' ...
             'for example ''Division'',''Lightweight''.']);
    end
    [values,detail] = ufc_v2_core('profiles',U.State,ids,divs,day,N.DOB,C);
    enough = all(detail.Bouts >= C.MinFights & detail.Minutes >= C.MinMinutes);
    assert(enough || o.AllowLimitedHistory,'ufc:LimitedHistory', ...
        ['The model requires two recorded fights and ten minutes per fighter. ' ...
         'Use AllowLimitedHistory=true only for an exploratory estimate.']);
    difference = values(1,:)'-values(2,:)'; missing = ~isfinite(difference);
    difference(missing) = 0;
    scaled = difference./M.Fit.Scale(:);
    raw = scaled.*M.Fit.Coefficient(:);
    calibrated = M.Calibration.Slope*raw;
    probability = ufc_v2_core('sigmoid',sum(calibrated));
    T = table(string(C.Keys(:)),string(C.Labels(:)),values(1,:)',values(2,:)', ...
        difference,scaled,M.Fit.Coefficient(:),raw,calibrated,missing, ...
        'VariableNames',{'Key','Metric','FighterA','FighterB','DifferenceUsed', ...
        'StandardizedAdvantage','Coefficient','RawLogOddsContribution', ...
        'LogOddsContribution','MissingComparison'});
    R = struct('FighterA',nameA,'FighterB',nameB,'ProbabilityA',probability, ...
        'ProbabilityB',1-probability,'Score',sum(calibrated),'Comparison',T, ...
        'ProfileThroughDate',forecast-days(1),'ForecastDate',forecast, ...
        'ModelFitThrough',string(M.FitThrough),'MeetsHistoryRule',enough, ...
        'ModelName','Updated v2','CalibrationSlope',M.Calibration.Slope, ...
        'HalfLifeYears',C.HalfLifeYears,'PriorMinutes',C.PriorMinutes, ...
        'GroupIndex',C.GroupIndex(:),'GroupLabels',string(C.GroupLabels(:)), ...
        'AgeYears',detail.AgeYears,'AgeMissing',detail.AgeMissing, ...
        'RecentMinutes',detail.RecentMinutes,'LastRecordedFight',last, ...
        'DataCutoff',D.DataCutoff);
    if o.Print
        fprintf('\nUpdated v2 | %s: %.1f%% | %s: %.1f%%\n',nameA,100*probability,nameB,100*(1-probability));
        fprintf('Forecast date %s; fight data through %s; model fitted through %s.\n', ...
            string(forecast,'yyyy-MM-dd'),string(D.DataCutoff,'yyyy-MM-dd'),M.FitThrough);
        fprintf('Recency half-life: %.1f years. Smoothing: %.0f equivalent minutes.\n', ...
            C.HalfLifeYears,C.PriorMinutes);
        if any(detail.AgeMissing), fprintf('Unknown birth date: age comparison is neutral.\n'); end
        disp(T);
    end
end
