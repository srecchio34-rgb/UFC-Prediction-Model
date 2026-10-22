function [T,fig] = review_model_v2(varargin)
%REVIEW_MODEL_V2 Show the saved same-fight chronological comparison.
    p = inputParser;
    addParameter(p,'DataDir',fullfile(fileparts(mfilename('fullpath')),'data'));
    addParameter(p,'Plot',true,@islogical);
    parse(p,varargin{:});
    folder = fullfile(fileparts(char(p.Results.DataDir)),'results_v2');
    T = readtable(fullfile(folder,'validation_summary.csv'),'TextType','string');
    fprintf('\nSame-bout evaluation, annual earlier-year fits, January 2025 onward.\n');
    disp(T);
    fprintf('Calibration changes probabilities, while preserving the chosen winner.\n');
    fprintf('This is retrospective testing; later results were previously inspected during design.\n');
    fig = [];
    if p.Results.Plot
        fig = figure('Name','UFC updated model validation','Color','w');
        ax = axes(fig); bar(ax,100*T.Accuracy);
        xticks(ax,1:height(T)); xticklabels(ax,T.Model);
        ylabel(ax,'Correct winner predictions (%)'); ylim(ax,[0 100]); grid(ax,'on');
        title(ax,sprintf('Same %d fights: earlier-year models only',T.Fights(1)));
        for k = 1:height(T)
            text(ax,k,100*T.Accuracy(k)+2,sprintf('%.1f%%',100*T.Accuracy(k)), ...
                'HorizontalAlignment','center');
        end
    end
end
