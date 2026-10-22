function [T,summary,fig] = ufc_backtest_v2(varargin)
%UFC_BACKTEST_V2 Flat-stake historical bets from genuinely earlier-year fits.
%   ufc_backtest_v2('LastN',50,'Stake',10)
%   ufc_backtest_v2('LastN',30,'OnlyUnderdogs',true)
%   ufc_backtest_v2('LastN',50,'Model','baseline')
% Updated evaluation starts in 2025; older years selected/calibrated the model.
    p = inputParser;
    root = fileparts(mfilename('fullpath'));
    addParameter(p,'DataDir',fullfile(root,'data'));
    addParameter(p,'LastN',50,@(x) isscalar(x) && x >= 1 && x == floor(x));
    addParameter(p,'Stake',10,@(x) isscalar(x) && isfinite(x) && x > 0);
    addParameter(p,'Model','updated');
    addParameter(p,'OnlyUnderdogs',false,@islogical);
    addParameter(p,'From',[]); addParameter(p,'To',[]);
    addParameter(p,'Print',true,@islogical); addParameter(p,'Plot',true,@islogical);
    parse(p,varargin{:}); o = p.Results;
    folder = fullfile(fileparts(char(o.DataDir)),'results_v2');
    H = ufc_read_csv(fullfile(folder,'historical_predictions.csv'));
    Q = ufc_read_csv(fullfile(o.DataDir,'historical_odds.csv'));
    model = lower(string(o.Model));
    assert(ismember(model,["updated","baseline"]),'ufc:ModelChoice','Choose updated or baseline.');
    [found,loc] = ismember(str2double(H.BoutID),str2double(Q.BoutID));
    H = H(found,:); Q = Q(loc(found),:);
    date = datetime(H.Date,'InputFormat','yyyy-MM-dd');
    assert(all(date == datetime(Q.Date,'InputFormat','yyyy-MM-dd')),'ufc:OddsMatch', ...
        'Odds and forecast bout IDs must refer to the same dates.');
    assert(all(H.Red == Q.Red & H.Blue == Q.Blue),'ufc:OddsFighters', ...
        'Odds must match both exact fighter identities and corner orientation.');
    if model == "updated", probability = str2double(H.UpdatedProbabilityRed);
    else, probability = str2double(H.BaselineProbabilityRed); end
    red = probability > 0.5;
    chance = max(probability,1-probability);
    pick = H.Red; opponent = H.Blue;
    pick(~red) = H.Blue(~red); opponent(~red) = H.Red(~red);
    decimal = str2double(Q.RedDecimal); blue = str2double(Q.BlueDecimal);
    decimal(~red) = blue(~red);
    won = double(red) == str2double(H.Y);
    american = 100*(decimal-1);
    favorite = decimal < 2;
    american(favorite) = -100./(decimal(favorite)-1);
    keep = isfinite(decimal) & decimal > 1 & abs(probability-0.5) > 1e-12;
    if o.OnlyUnderdogs, keep = keep & american > 0; end
    if ~isempty(o.From), keep = keep & date >= datetime(o.From); end
    if ~isempty(o.To), keep = keep & date <= datetime(o.To); end
    profit = -o.Stake*ones(height(H),1);
    profit(won) = o.Stake*(decimal(won)-1);
    T = table(str2double(H.BoutID),date,pick,opponent,100*chance,american,decimal, ...
        won,profit,Q.Source,Q.OddsTiming, ...
        'VariableNames',{'BoutID','Date','ModelPick','Opponent','ModelChancePercent', ...
        'AmericanOdds','DecimalOdds','Won','Profit','OddsSource','OddsTiming'});
    T = sortrows(T(keep,:),{'Date','BoutID'},{'descend','ascend'});
    T = T(1:min(height(T),o.LastN),:);
    assert(~isempty(T),'ufc:NoBets','No evaluated fights with odds match these filters.');
    risk = o.Stake*height(T); net = sum(T.Profit);
    summary = table(string(model),height(T),sum(T.Won),sum(~T.Won),risk,risk+net,net, ...
        100*net/risk,'VariableNames',{'Model','Bets','Wins','Losses','TotalWagered', ...
        'TotalReturned','NetProfit','ROIPercent'});
    if o.Print
        fprintf('\n$%.2f per pick | %s model | %s through %s\n',o.Stake,model, ...
            string(min(T.Date),'yyyy-MM-dd'),string(max(T.Date),'yyyy-MM-dd'));
        disp(summary); disp(T);
        fprintf('Uses stored earlier-year forecasts, not today''s fit applied to old fights.\n');
        fprintf('Returns use the archived quotes; odds-source timing limitations still apply.\n');
    end
    fig = [];
    if o.Plot
        chronological = sortrows(T,{'Date','BoutID'},{'ascend','descend'});
        fig = figure('Name','UFC updated historical bets','Color','w'); ax = axes(fig);
        plot(ax,0:height(T),[0;cumsum(chronological.Profit)],'LineWidth',1.8);
        yline(ax,0,'--'); grid(ax,'on'); box(ax,'off');
        xlabel(ax,'Bet number, oldest to newest'); ylabel(ax,'Cumulative net profit ($)');
        title(ax,sprintf('%s | %d bets at $%.2f | net $%+.2f',model,height(T),o.Stake,net));
    end
end
