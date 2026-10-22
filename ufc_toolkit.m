function varargout = ufc_toolkit(action, varargin)
%UFC_TOOLKIT UFC correlations, fighter profiles, matchups, and scatter plots.
%   ufc_toolkit                                      interactive menu
%   ufc_toolkit('correlation')                       first correlation graph
%   p = ufc_toolkit('fighter', 'Max Holloway')        individual profile
%   r = ufc_toolkit('matchup', 'Max Holloway', 'Alexander Volkanovski')
%   ufc_toolkit('scatter', 'slpm')                    stat vs win rate
%   ufc_toolkit('scatter', 'slpm', 'View', 'probability')
%   ufc_toolkit('search', 'Nurmagomedov')             matching names
%   data = ufc_toolkit('load')                       imported MATLAB data
%   ufc_toolkit('reload')                            reimport changed data
%   ufc_toolkit('metrics')                           list metric keys/units
% All actions accept 'DataDir', path. Other options are documented in README.
    if nargin < 1 || isempty(action), action = 'menu'; end
    action = lower(string(action));
    assert(isscalar(action), 'ufc:Action', 'Action must be one string.');
    root = fileparts(mfilename('fullpath'));
    [args, dataDir] = takeDataDir(varargin, fullfile(root, 'data'));
    persistent cachedData cachedSignature
    signature = dataSignature(dataDir);
    if isempty(cachedData) || ~isequal(signature, cachedSignature) || action == "reload"
        fprintf('Importing UFC data and calculating strictly prior fight histories...\n');
        cachedData = ufc_load_data(dataDir);
        cachedSignature = signature;
        fprintf('Loaded %d bouts, %d fighters; latest date %s.\n', ...
            height(cachedData.Bouts), numel(cachedData.Names), ...
            string(cachedData.DataCutoff, 'yyyy-MM-dd'));
    end
    D = cachedData;
    out = []; fig = [];
    switch action
        case "menu"
            runMenu(D);
        case {"load", "reload"}
            out = D;
        case {"correlation", "correlations"}
            [out, fig] = ufc_correlations(D, args{:});
            if nargout == 0, disp(out); end
        case {"fighter", "profile"}
            assert(~isempty(args), 'ufc:Arguments', 'Supply a fighter name.');
            out = ufc_profile(D, args{1}, args{2:end});
        case {"matchup", "predict"}
            assert(numel(args) >= 2, 'ufc:Arguments', 'Supply two fighter names.');
            [out, fig] = ufc_matchup(D, args{1}, args{2}, args{3:end});
        case "scatter"
            if isempty(args), args = {'slpm'}; end
            [out, fig] = ufc_scatter(D, args{1}, args{2:end});
        case {"validation","validate"}
            [out,fig] = review_model_v2('DataDir',dataDir,args{:});
        case "backtest"
            [out,~,fig] = ufc_backtest_v2('DataDir',dataDir,args{:});
        case "search"
            assert(~isempty(args), 'ufc:Arguments', 'Supply part of a fighter name.');
            q = regexprep(upper(string(args{1})), '[^A-Z0-9]', '');
            assert(strlength(q) > 0, 'ufc:Name', 'Enter part of a fighter name.');
            normalized = regexprep(upper(D.Names), '[^A-Z0-9]', '');
            out = D.Profiles.Summary(contains(normalized, q), :);
            if nargout == 0, disp(out); end
        case "metrics"
            out = table(D.MetricKeys, D.MetricLabels, D.MetricUnits, ...
                'VariableNames', {'Key', 'Metric', 'Unit'});
            if nargout == 0, disp(out); end
        otherwise
            error('ufc:Action', 'Unknown action "%s". Type help ufc_toolkit.', action);
    end
    if nargout > 0, varargout{1} = out; end
    if nargout > 1, varargout{2} = fig; end
end

function runMenu(D)
    while true
        fprintf('\nUFC Stats Toolkit\n');
        fprintf('1  Correlation graph\n2  Fighter lookup\n3  Two-fighter probabilities\n');
        fprintf('4  Stat versus fighter win-rate scatter\n5  Predicted versus actual win-rate scatter\n');
        fprintf('6  Search fighter names\n0  Exit\n');
        fprintf('7  Updated-model validation\n8  Latest 50 historical $10 bets\n');
        choice = strtrim(input('Choose: ', 's'));
        if strcmp(choice, '0') || isempty(choice), return; end
        try
            switch choice
                case '1'
                    mode = strtrim(input('Mode [prefight / within / weights; default prefight]: ', 's'));
                    if isempty(mode), mode = 'prefight'; end
                    [T, ~] = ufc_correlations(D, 'Mode', mode);
                    disp(T);
                case '2'
                    ufc_profile(D, input('Fighter name: ', 's'));
                case '3'
                    a = input('Fighter A: ', 's'); b = input('Fighter B: ', 's');
                    ufc_matchup(D, a, b);
                case '4'
                    disp(table(D.MetricKeys, D.MetricLabels, 'VariableNames', {'Key', 'Metric'}));
                    metric = strtrim(input('Metric key [default slpm]: ', 's'));
                    if isempty(metric), metric = 'slpm'; end
                    ufc_scatter(D, metric);
                case '5'
                    ufc_scatter(D, 'slpm', 'View', 'probability');
                case '6'
                    query = regexprep(upper(string(input('Part of name: ', 's'))), '[^A-Z0-9]', '');
                    assert(strlength(query) > 0, 'ufc:Name', 'Enter part of a name.');
                    normalized = regexprep(upper(D.Names), '[^A-Z0-9]', '');
                    disp(D.Profiles.Summary(contains(normalized, query), :));
                case '7'
                    review_model_v2('DataDir',D.DataDir);
                case '8'
                    ufc_backtest_v2('DataDir',D.DataDir,'LastN',50,'Stake',10);
                otherwise
                    fprintf('Choose one of the listed numbers.\n');
            end
        catch problem
            fprintf(2, '%s\n', problem.message);
        end
    end
end

function [args, dataDir] = takeDataDir(args, fallback)
    dataDir = fallback;
    for k = 1:numel(args)-1
        if (ischar(args{k}) || isstring(args{k})) && strcmpi(string(args{k}), 'DataDir')
            dataDir = char(string(args{k+1}));
            args(k:k+1) = [];
            return;
        end
    end
end

function signature = dataSignature(dataDir)
    files = {'ufc_raw_stats_recovered.csv', 'metric_definitions.csv', 'model_parameters.json', ...
        'ufc_bouts_recovered.csv', 'heldout_predictions.csv', 'adjusted_coefficients.csv', ...
        'fighter_birth_dates.csv','model_v2.json'};
    signature = string(dataDir);
    for k = 1:numel(files)
        info = dir(fullfile(dataDir, files{k}));
        if isempty(info)
            signature = signature + "|" + files{k} + ":missing";
        else
            signature = signature + "|" + files{k} + ":" + ...
                string(info.bytes) + ":" + string(sprintf('%.12f', info.datenum));
        end
    end
end
