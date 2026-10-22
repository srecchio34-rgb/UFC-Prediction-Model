function [M, report] = ufc_upgrade_model(varargin)
%UFC_UPGRADE_MODEL Rebuild the updated model using chronological validation.
% The download already includes fitted parameters; retraining is optional.
%   ufc_upgrade_model
%   [M, report] = ufc_upgrade_model('Save',false);
% 2019-2021 selects half-life/prior/C. 2022-2024 earlier-year forecasts fit
% symmetric calibration. 2025 onward evaluates annual earlier-year fits.
% Base MATLAB R2021a+. No Statistics/Optimization toolboxes or Python needed.
    p = inputParser;
    root = fileparts(mfilename('fullpath'));
    addParameter(p,'DataDir',fullfile(root,'data'));
    addParameter(p,'Save',true,@islogical);
    addParameter(p,'Print',true,@islogical);
    parse(p,varargin{:}); o = p.Results;
    D = ufc_load_data(char(o.DataDir));
    C = ufc_v2_config();
    N = ufc_v2_prepare(D,C);
    n = height(D.Bouts); years = year(D.Bouts.Date);
    y = D.Bouts.Y;
    Xbase = baseline(D);
    candidates = zeros(0,4); bestLoss = Inf;
    for half = [1 2 3]
        for strength = [5 15 30]
            C.HalfLifeYears = half; C.PriorMinutes = strength;
            [F,~,info] = ufc_v2_core('build',N,C);
            X = F(1:n,:)-F(n+1:end,:);
            eligible = eligibility(info,n,years,y,C);
            train = eligible & years < 2019;
            validation = eligible & years >= 2019 & years <= 2021;
            assert(sum(train) >= 100 && sum(validation) >= 50,'ufc:TrainingPeriods', ...
                'The supplied data must cover the chronological training periods.');
            for ridge = [0.001 0.01 0.1 1]
                fit = ufc_v2_core('fit',X(train,:),y(train),ridge);
                pred = ufc_v2_core('sigmoid',ufc_v2_core('score',fit,X(validation,:)));
                metric = ufc_v2_core('metrics',y(validation),pred);
                candidates(end+1,:) = [half strength ridge metric.LogLoss]; %#ok<AGROW>
                if metric.LogLoss < bestLoss
                    bestLoss = metric.LogLoss; chosen = [half strength ridge];
                end
            end
            if o.Print, fprintf('Validated half-life %g years, prior %g minutes.\n',half,strength); end
        end
    end
    C.HalfLifeYears = chosen(1); C.PriorMinutes = chosen(2); C.C = chosen(3);
    [F,~,info] = ufc_v2_core('build',N,C);
    X = F(1:n,:)-F(n+1:end,:);
    eligible = eligibility(info,n,years,y,C);
    calibrationScore = NaN(n,1);
    for yr = 2022:2024
        train = eligible & years < yr; test = eligible & years == yr;
        fit = ufc_v2_core('fit',X(train,:),y(train),C.C);
        calibrationScore(test) = ufc_v2_core('score',fit,X(test,:));
    end
    calibrationRows = isfinite(calibrationScore);
    K = ufc_v2_core('calibrate',calibrationScore(calibrationRows),y(calibrationRows));
    pBase = NaN(n,1); pRaw = pBase; pUpdated = pBase; fitThrough = NaT(n,1);
    for yr = 2025:max(years)
        train = eligible & years < yr; test = eligible & years == yr;
        if ~any(test), continue; end
        fit = ufc_v2_core('fit',X(train,:),y(train),C.C);
        old = ufc_v2_core('fit',Xbase(train,:),y(train),0.01);
        z = ufc_v2_core('score',fit,X(test,:));
        pRaw(test) = ufc_v2_core('sigmoid',z);
        pUpdated(test) = ufc_v2_core('sigmoid',K.Slope*z);
        pBase(test) = ufc_v2_core('sigmoid',ufc_v2_core('score',old,Xbase(test,:)));
        fitThrough(test) = max(D.Bouts.Date(train));
    end
    scored = isfinite(pUpdated);
    assert(any(scored),'ufc:TestPeriod','The data must include fights from 2025 onward.');
    assert(all(fitThrough(scored) < D.Bouts.Date(scored)), 'ufc:FutureTraining', ...
        'Each evaluation fit must precede its tested bouts.');
    final = ufc_v2_core('fit',X(eligible,:),y(eligible),C.C);
    M = struct('Version','2.0','Config',C,'Fit',final,'Calibration',K, ...
        'FitThrough',char(string(max(D.Bouts.Date(eligible)),'yyyy-MM-dd')), ...
        'DataThrough',char(string(D.DataCutoff,'yyyy-MM-dd')), ...
        'SelectionThrough','2021-12-31','CalibrationThrough','2024-12-31', ...
        'EvaluationStarts','2025-01-01','TrainingFights',sum(eligible), ...
        'Description','Recency + Bayesian smoothing + prior opponent residuals + age + symmetric calibration');
    labels = {'Baseline (clean identities)';'Updated, uncalibrated';'Updated, calibrated'};
    probs = {pBase(scored),pRaw(scored),pUpdated(scored)};
    entries = cell(3,1);
    for k = 1:3, entries{k} = ufc_v2_core('metrics',y(scored),probs{k}); end
    values = vertcat(entries{:});
    summary = struct2table(values);
    summary.Model = string(labels);
    summary = movevars(summary,'Model','Before',1);
    P = D.Bouts(scored,{'BoutID','Date','Event','EventKey','Division','Red','Blue','Y'});
    P.FitThrough = fitThrough(scored);
    P.Date.Format = 'yyyy-MM-dd';
    P.FitThrough.Format = 'yyyy-MM-dd';
    P.BaselineProbabilityRed = pBase(scored);
    P.UpdatedRawProbabilityRed = pRaw(scored);
    P.UpdatedProbabilityRed = pUpdated(scored);
    P.AgeMissing = info.AgeMissing(find(scored)) | info.AgeMissing(n+find(scored));
    selection = array2table(candidates,'VariableNames', ...
        {'HalfLifeYears','PriorMinutes','C','ValidationLogLoss'});
    report = struct('Summary',summary,'Predictions',P,'Selection',selection, ...
        'Calibration',K,'AgeKnownAppearances',sum(~info.AgeMissing), ...
        'AgeTotalAppearances',numel(info.AgeMissing), ...
        'Caveat',['Retrospective time-ordered evaluation. Design work previously inspected ' ...
        'later results; this is not a prospectively untouched validation.']);
    if o.Save
        destination = char(o.DataDir);
        writeJSON(fullfile(destination,'model_v2.json'),M);
        out = fullfile(fileparts(destination),'results_v2');
        if ~isfolder(out), mkdir(out); end
        writetable(summary,fullfile(out,'validation_summary.csv'));
        writetable(P,fullfile(out,'historical_predictions.csv'));
        writetable(selection,fullfile(out,'hyperparameter_selection.csv'));
        writeJSON(fullfile(out,'training_report.json'),rmfield(report,{'Summary','Predictions','Selection'}));
        clear ufc_toolkit
    end
    if o.Print
        fprintf('\nSelected: half-life %.1f years; prior %.0f minutes; C=%g.\n', ...
            C.HalfLifeYears,C.PriorMinutes,C.C);
        fprintf('Calibration log-odds multiplier: %.4f.\n',K.Slope);
        fprintf('Evaluation: annual earlier-year fits, 2025 onward, identical bouts.\n');
        disp(summary);
        fprintf('%s\n',report.Caveat);
    end
end

function good = eligibility(info,n,years,y,C)
    good = isfinite(y) & years >= C.StartYear & ...
        info.PriorBouts(1:n) >= C.MinFights & info.PriorBouts(n+1:end) >= C.MinFights & ...
        info.PriorMinutes(1:n) >= C.MinMinutes & info.PriorMinutes(n+1:end) >= C.MinMinutes;
end

function X = baseline(D)
    n = height(D.Bouts); keys = cellstr(string(D.Model.features));
    F = zeros(2*n,numel(keys));
    for k = 1:numel(keys)
        if strcmp(keys{k},'experience')
            F(:,k) = log1p(D.PriorState(:,strcmp(D.Fields,'bouts')));
        else
            j = find(D.MetricKeys == string(keys{k}),1);
            F(:,k) = D.PriorMetrics(:,j);
        end
    end
    X = F(1:n,:)-F(n+1:end,:);
end

function writeJSON(path,value)
    file = fopen(path,'w');
    assert(file >= 0,'ufc:WriteFile','Cannot write %s.',path);
    cleanup = onCleanup(@() fclose(file)); %#ok<NASGU>
    fwrite(file,jsonencode(value),'char');
end
