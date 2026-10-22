function varargout = ufc_v2_core(action, varargin)
%UFC_V2_CORE Numerical feature, fitting and calibration engine. No toolboxes.
% Numeric dates are MATLAB serial days. Counts never contain future bouts.
    switch lower(action)
        case 'build'
            [varargout{1:nargout}] = build(varargin{:});
        case 'profiles'
            [varargout{1:nargout}] = profiles(varargin{:});
        case 'fit'
            varargout{1} = fit(varargin{:});
        case 'score'
            varargout{1} = score(varargin{:});
        case 'calibrate'
            varargout{1} = calibrate(varargin{:});
        case 'metrics'
            varargout{1} = metrics(varargin{:});
        case 'sigmoid'
            varargout{1} = sigmoid(varargin{:});
        otherwise
            error('ufc:CoreAction', 'Unknown numerical engine action: %s', action);
    end
end

function [F, S, info] = build(N, C)
% Build all profiles before updating any fighter or population on that date.
    n = numel(N.Day);
    assert(size(N.Raw,1) == n && size(N.Raw,2) == 19);
    assert(all(isfinite(N.Raw(:))) && all(N.Raw(:) >= 0));
    assert(isfinite(C.HalfLifeYears) && C.HalfLifeYears > 0 && C.PriorMinutes > 0);
    S = struct('Counts',zeros(N.FighterCount,19), ...
        'Adjusted',zeros(N.FighterCount,5), ...
        'Bouts',zeros(N.FighterCount,1),'Minutes',zeros(N.FighterCount,1), ...
        'Division',zeros(N.DivisionCount,19),'Global',zeros(1,19), ...
        'Day',min(N.Day));
    F = NaN(n,21);
    info = struct('PriorBouts',zeros(n,1),'PriorMinutes',zeros(n,1), ...
        'RecentMinutes',zeros(n,1),'AgeMissing',false(n,1));
    [~, order] = sortrows([N.Day(:), N.BoutID(:), N.Side(:)], [1 2 3]);
    orderedDays = N.Day(order);
    starts = find([true; diff(orderedDays) ~= 0]);
    stops = [starts(2:end)-1; n];
    for g = 1:numel(starts)
        ix = order(starts(g):stops(g));
        day = N.Day(ix(1));
        S = advance(S, day, C);
        [F(ix,:), detail] = profiles(S, N.Fighter(ix), N.Division(ix), day, N.DOB, C);
        info.PriorBouts(ix) = detail.Bouts;
        info.PriorMinutes(ix) = detail.Minutes;
        info.RecentMinutes(ix) = detail.RecentMinutes;
        info.AgeMissing(ix) = detail.AgeMissing;
        % Every opponent profile below was calculated before this whole date.
        for k = 1:numel(ix)
            r = ix(k); f = N.Fighter(r); d = N.Division(r);
            x = N.Raw(r,:); opp = F(N.OpponentRow(r),:);
            assert(all(isfinite(opp(1:15))), 'ufc:OpponentHistory', ...
                'The opponent must have a same-date prior profile.');
            minutes = x(16)/60;
            exposure = min(x(13),x(15));
            a = [x(1)-x(3)-(opp(2)-opp(1))*minutes, ...
                x(5)-x(7)-(oppRate(S,N.Opponent(r),d,C,7)-opp(5))*minutes/15, ...
                x(10)-x(11)-(opp(9)-opp(8))*minutes/15, ...
                0, exposure];
            if exposure > 0
                a(4) = x(12)-x(14)-(opp(11)-opp(10))*exposure;
            end
            % Delay all state updates until every residual on the date exists.
            % Store the residual; the update loop follows below.
            if k == 1, adjusted = zeros(numel(ix),5); end
            adjusted(k,:) = a;
        end
        for k = 1:numel(ix)
            r = ix(k); f = N.Fighter(r); d = N.Division(r); x = N.Raw(r,:);
            S.Counts(f,:) = S.Counts(f,:) + x;
            S.Adjusted(f,:) = S.Adjusted(f,:) + adjusted(k,:);
            S.Bouts(f) = S.Bouts(f)+1;
            S.Minutes(f) = S.Minutes(f)+x(16)/60;
            S.Division(d,:) = S.Division(d,:)+x;
            S.Global = S.Global+x;
        end
    end
end

function value = oppRate(S, fighter, division, C, index)
% Smoothed opponent takedowns allowed per 15 minutes, using earlier dates.
    p = posterior(S, fighter, division, C);
    value = 900*p(index)/p(16);
end

function S = advance(S, day, C)
    assert(isscalar(day) && isfinite(day) && day >= S.Day, ...
        'ufc:HistoryDate', 'A forecast date cannot precede its stored history.');
    factor = 2^(-(day-S.Day)/(365.25*C.HalfLifeYears));
    S.Counts = S.Counts*factor;
    S.Adjusted = S.Adjusted*factor;
    S.Division = S.Division*factor;
    S.Global = S.Global*factor;
    S.Day = day;
end

function p = posterior(S, ids, divisions, C)
    ids = ids(:); divisions = divisions(:);
    seed = C.Seed(:)'*(C.GlobalSeedMinutes/15);
    globalRate = (S.Global+seed)/(S.Global(16)+60*C.GlobalSeedMinutes);
    p = S.Counts(ids,:);
    for d = unique(divisions)'
        rows = divisions == d;
        baseline = (S.Division(d,:)+globalRate*(60*C.DivisionBackoffMinutes)) / ...
            (S.Division(d,16)+60*C.DivisionBackoffMinutes);
        p(rows,:) = p(rows,:) + repmat(baseline*(60*C.PriorMinutes),sum(rows),1);
    end
end

function [F, detail] = profiles(S, ids, divisions, day, dob, C)
% Predictive profiles use all records strictly before the supplied day.
    S = advance(S,day,C);
    ids = ids(:); divisions = divisions(:);
    p = posterior(S,ids,divisions,C);
    t = p(:,16); sig = p(:,1);
    F = [60*sig./t, 60*p(:,3)./t, sig./p(:,2), 1-p(:,3)./p(:,4), ...
        900*p(:,5)./t, 1-p(:,7)./p(:,8), 900*p(:,9)./t, ...
        900*p(:,10)./t, 900*p(:,11)./t, p(:,12)./p(:,13), ...
        p(:,14)./p(:,15), p(:,17)./sig, p(:,18)./sig, p(:,19)./sig, ...
        log1p(S.Bouts(ids)), zeros(numel(ids),6)];
    recentMinutes = S.Counts(ids,16)/60;
    a = S.Adjusted(ids,:);
    if C.OpponentAdjustment
        F(:,16:19) = [a(:,1)./(recentMinutes+C.PriorMinutes), ...
            a(:,2)./(recentMinutes/15+C.PriorMinutes/15), ...
            a(:,3)./(recentMinutes/15+C.PriorMinutes/15), ...
            a(:,4)./(a(:,5)+60*C.PriorMinutes)];
    end
    ages = (day-dob(ids))/365.25;
    ageMissing = ~isfinite(ages) | ages < 14 | ages > 65;
    if C.UseAge
        z = (ages-C.AgeCenter)/C.AgeScale;
        z(ageMissing) = NaN;
        F(:,20:21) = [z,z.^2];
    end
    detail = struct('Bouts',S.Bouts(ids),'Minutes',S.Minutes(ids), ...
        'RecentMinutes',recentMinutes,'AgeYears',ages,'AgeMissing',ageMissing);
end

function M = fit(X, y, ridgeC)
% Mirrored logistic objective: sum(loss) + ||beta||^2/(4*C).
    X(~isfinite(X)) = 0;
    y = y(:);
    assert(size(X,1) == numel(y) && all(y == 0 | y == 1));
    assert(numel(unique(y)) == 2 && ridgeC > 0, 'ufc:TrainingData', ...
        'Training needs both outcomes and positive regularization C.');
    scale = sqrt(mean(X.^2,1)); scale(scale < 1e-12) = 1;
    Z = bsxfun(@rdivide,X,scale);
    beta = zeros(size(X,2),1); lambda = 1/(2*ridgeC);
    converged = false;
    for iteration = 1:100
        z = Z*beta; p = sigmoid(z);
        gradient = Z'*(p-y)+lambda*beta;
        if norm(gradient,Inf) < 1e-8*max(1,size(X,1))
            converged = true; break
        end
        w = p.*(1-p);
        hessian = Z'*bsxfun(@times,Z,w)+lambda*eye(numel(beta));
        step = hessian\gradient;
        old = objective(Z,y,beta,lambda);
        rate = 1;
        while rate > 1e-8
            candidate = beta-rate*step;
            if objective(Z,y,candidate,lambda) <= old-1e-4*rate*(gradient'*step)
                break
            end
            rate = rate/2;
        end
        beta = candidate;
    end
    assert(converged, 'ufc:FitConvergence', 'Logistic fitting did not converge.');
    M = struct('Coefficient',beta,'Scale',scale(:),'C',ridgeC, ...
        'Iterations',iteration,'Converged',converged,'Intercept',0);
end

function loss = objective(X,y,beta,lambda)
    z = X*beta;
    loss = sum(max(z,0)+log1p(exp(-abs(z)))-y.*z)+0.5*lambda*sum(beta.^2);
end

function z = score(M,X)
    X(~isfinite(X)) = 0;
    z = bsxfun(@rdivide,X,M.Scale(:)')*M.Coefficient(:);
end

function K = calibrate(z,y)
% Positive scalar on log odds preserves A/B symmetry and the 50/50 baseline.
% Calibration data must consist of earlier out-of-time forecasts.
    z = z(:); y = y(:);
    assert(numel(z) >= 50 && numel(z) == numel(y) && all(isfinite(z)));
    left = log(0.05); right = log(5); ratio = (sqrt(5)-1)/2;
    a = right-ratio*(right-left); b = left+ratio*(right-left);
    for k = 1:70
        if calibrationLoss(a,z,y) < calibrationLoss(b,z,y)
            right = b; b = a; a = right-ratio*(right-left);
        else
            left = a; a = b; b = left+ratio*(right-left);
        end
    end
    slope = exp((left+right)/2);
    K = struct('Slope',slope,'Method','Symmetric temperature scaling', ...
        'Samples',numel(y),'RawLogLoss',calibrationLoss(0,z,y), ...
        'CalibratedLogLoss',calibrationLoss(log(slope),z,y));
end

function loss = calibrationLoss(logSlope,z,y)
    score = exp(logSlope)*z;
    loss = mean(max(score,0)+log1p(exp(-abs(score)))-y.*score);
end

function M = metrics(y,p)
    y = y(:); p = p(:);
    assert(numel(y) == numel(p) && all(isfinite(p)));
    clipped = max(1e-12,min(1-1e-12,p));
    M = struct('Fights',numel(y),'Correct',sum((p >= 0.5) == y), ...
        'Accuracy',mean((p >= 0.5) == y), ...
        'LogLoss',-mean(y.*log(clipped)+(1-y).*log(1-clipped)), ...
        'Brier',mean((p-y).^2),'AUC',NaN);
    positive = sum(y == 1); negative = sum(y == 0);
    if positive > 0 && negative > 0
        [ordered,order] = sort(p); ranks = zeros(size(p));
        first = 1;
        while first <= numel(p)
            last = first;
            while last < numel(p) && ordered(last+1) == ordered(first), last = last+1; end
            ranks(order(first:last)) = (first+last)/2;
            first = last+1;
        end
        M.AUC = (sum(ranks(y == 1))-positive*(positive+1)/2)/(positive*negative);
    end
end

function p = sigmoid(z)
    p = zeros(size(z)); good = z >= 0;
    p(good) = 1./(1+exp(-z(good)));
    e = exp(z(~good)); p(~good) = e./(1+e);
end
