function Results = MNL(INPUT,Results_old,EstimOpt,OptimOpt)


% save tmp_MNL
% return

global B_backup

tic 

Results.bhat = [];
Results.R = [];
Results.R_out = {};
Results.stats = [];


%% Check data and inputs


if nargin < 3
    error('Too few input arguments for MNL(INPUT,EstimOpt,OptimOpt)')
end

warning off MATLAB:mir_warning_maybe_uninitialized_temporary

format shortG;
format compact;

if isfield(EstimOpt, 'Display') == 0
    EstimOpt.Display = 0;
end

if EstimOpt.Display ~= 0
    disp(' ');
    disp('__________________________________________________________________________________________________________________');
    disp(' ');
    disp('Estimating MNL model ...')
end

if isfield(EstimOpt, 'WTP_space') == 0
    EstimOpt.WTP_space = 0;
    EstimOpt.WTP_matrix = [];
elseif EstimOpt.WTP_space == 0;
	EstimOpt.WTP_matrix = [];
end

if EstimOpt.Display ~= 0
    if EstimOpt.WTP_space > 0
        disp('in WTP-space ...')
    else
        disp('in preference-space ...') 
    end
    if isfield(EstimOpt, 'NLTVariables') && ~isempty(EstimOpt.NLTVariables)
        disp('with non-linear transformation(s) ... ')
    end
end

if isfield(EstimOpt, 'NLTVariables') 
    EstimOpt.NLTVariables = EstimOpt.NLTVariables(:);
    EstimOpt.NVarNLT = length(unique(EstimOpt.NLTVariables));
    if ~ismember(unique(EstimOpt.NLTVariables),1:EstimOpt.NVarA)
        error('Incorrect non-linear variable(s) specification')
    end
    if isfield(EstimOpt, 'NLTType') == 0
        cprintf(rgb('DarkOrange'), 'WARNING: Assuming Box-Cox transformation \n')
        EstimOpt.NLTType = 1;
    elseif EstimOpt.NLTType == 1
        disp('using Box-Cox transformation(s)')
    elseif EstimOpt.NLTType == 2
        disp('using Yeo-Johnson transformation(s)')
    else 
        error('Incorrect transformation type')
    end
    if EstimOpt.NLTType == 1
        if any(INPUT.Xa(:, EstimOpt.NLTVariables) < 0)
            cprintf(rgb('DarkOrange'), 'WARNING: Values of Box-Cox transformed variables < 0 \n')
        elseif any(INPUT.Xa(:, EstimOpt.NLTVariables) == 0) % not sure if this is stil necessary
            cprintf(rgb('DarkOrange'), 'WARNING: Values of Box-Cox transformed variables including zeros shifted by 0.00001 \n')
            for i = 1:EstimOpt.NVarNLT
                if any(INPUT.Xa(:, EstimOpt.NLTVariables(i)) == 0)
                    INPUT.Xa(:, EstimOpt.NLTVariables(i)) = INPUT.Xa(:, EstimOpt.NLTVariables(i)) + 0.00001;
                end
            end
        end
    end
else
    EstimOpt.NVarNLT = 0;
end

if isfield(INPUT, 'Xs') == 0
    INPUT.Xs = zeros(size(INPUT.Y,1),0);
end 
if isfield(EstimOpt,'SCEXP')==0
     EstimOpt.SCEXP = 1;
end
EstimOpt.NVarS = size(INPUT.Xs,2); % Number of covariates of scale

if EstimOpt.WTP_space > 0 
	if isfield(EstimOpt, 'WTP_matrix') == 0
        WTP_att = (EstimOpt.NVarA-EstimOpt.WTP_space)/EstimOpt.WTP_space;
        if rem(WTP_att,1) ~= 0
        	error('EstimOpt.WTP_matrix associating attributes with cost parameters not provided')
        else
            if EstimOpt.WTP_space > 1
	        	disp(['EstimOpt.WTP_matrix associating attributes with cost parameters not provided - assuming equal shares for each of the ',num2str(EstimOpt.WTP_space),' monetary attributes'])
            end
        EstimOpt.WTP_matrix = EstimOpt.NVarA - EstimOpt.WTP_space + kron(1:EstimOpt.WTP_space,ones(1,WTP_att));
%         tic; EstimOpt.WTP_matrix = 1:EstimOpt.WTP_space;...
%         EstimOpt.WTP_matrix = EstimOpt.WTP_matrix(floor((0:size(EstimOpt.WTP_matrix,2)*WTP_att-1)/WTP_att)+1); toc
        end
%     elseif ~isequal(size(EstimOpt.WTP_matrix),[EstimOpt.NVarA-EstimOpt.WTP_space,EstimOpt.WTP_space])
	elseif size(EstimOpt.WTP_matrix,2) ~= EstimOpt.NVarA - EstimOpt.WTP_space
        error('Dimensions of EstimOpt.WTP_matrix not correct - for each non-monetary attribute provide no. of attribute to multiply it with')
	end
end

if isfield(EstimOpt,'NamesA') == 0 || isempty(EstimOpt.NamesA) || length(EstimOpt.NamesA) ~= EstimOpt.NVarA
    EstimOpt.NamesA = (1:EstimOpt.NVarA)';
    EstimOpt.NamesA = cellstr(num2str(EstimOpt.NamesA));
elseif size(EstimOpt.NamesA,1) ~= EstimOpt.NVarA
    EstimOpt.NamesA = EstimOpt.NamesA';
end

if EstimOpt.NVarS > 0
    if isfield(EstimOpt,'NamesS') == 0 || isempty(EstimOpt.NamesS) || length(EstimOpt.NamesS) ~= EstimOpt.NVarS
        EstimOpt.NamesS = (1:EstimOpt.NVarS)';
        EstimOpt.NamesS = cellstr(num2str(EstimOpt.NamesS));
    elseif size(EstimOpt.NamesS,1) ~= EstimOpt.NVarS
        EstimOpt.NamesS = EstimOpt.NamesS';
    end
end


%% Starting values


if exist('B_backup','var') && ~isempty(B_backup) && size(B_backup,1) == EstimOpt.NVarA + EstimOpt.NVarS + EstimOpt.NVarNLT
    b0 = B_backup(:);
    if EstimOpt.Display ~= 0
        disp('Using the starting values from Backup')
    end
elseif isfield(Results_old,'MNL') && isfield(Results_old.MNL,'b0') && (length(Results_old.MNL.b0) == EstimOpt.NVarA + EstimOpt.NVarS + EstimOpt.NVarNLT) % MNL starting values provided
%     disp('Using MNL results as starting values')
    Results_old.MNL.b0_old = Results_old.MNL.b0;
    Results_old.MNL = rmfield(Results_old.MNL,'b0');
    if length(Results_old.MNL.b0_old) ~= EstimOpt.NVarA + EstimOpt.NVarS + EstimOpt.NVarNLT
        if EstimOpt.Display ~= 0
            cprintf(rgb('DarkOrange'), 'WARNING: Incorrect no. of starting values or model specification \n')
        end
        Results_old.MNL = rmfield(Results_old.MNL,'b0_old');        
    else
        b0 = Results_old.MNL.b0_old(:);
    end
end
if  ~exist('b0','var')
    if EstimOpt.Display ~= 0
        disp('Using linear regression estimates as starting values')
    end
    if EstimOpt.NVarS > 0
        b00 = zeros(EstimOpt.NVarS,1); ...
        Y = INPUT.Y(INPUT.MissingInd == 0);
        Xa = INPUT.Xa(INPUT.MissingInd == 0,:);
        b0 = [regress(Y,Xa);b00;ones(EstimOpt.NVarNLT,1)];
%         if EstimOpt.WTP_space > 0
%             b0(1:EstimOpt.NVarA-EstimOpt.WTP_space) = b0(1:EstimOpt.NVarA-EstimOpt.WTP_space) .* b0(EstimOpt.WTP_matrix,:);
%         end
    else
        b0 = [regress(INPUT.Y,INPUT.Xa); ones(EstimOpt.NVarNLT,1)];                   
%         if EstimOpt.WTP_space > 0
%             b0(1:EstimOpt.NVarA-EstimOpt.WTP_space) = b0(1:EstimOpt.NVarA-EstimOpt.WTP_space) .* b0(EstimOpt.WTP_matrix,:);
%         end
    end
end


%% Optimization Options


if any(EstimOpt.MissingAlt(:) == 1) && EstimOpt.NumGrad == 0
	EstimOpt.NumGrad = 1;
    OptimOpt.GradObj = 'off';
    if EstimOpt.Display ~= 0
        cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied gradient to numerical - missing alternatives not supported by analytical gradient \n')
    end
end

if  isfield(EstimOpt,'BActive')
	EstimOpt.BActive = EstimOpt.BActive(:)';
end

if EstimOpt.ConstVarActive == 1
    if ~isfield(EstimOpt,'BActive') || isempty(EstimOpt.BActive) || sum(EstimOpt.BActive == 0) == 0
        error ('Are there any constraints on model parameters (EstimOpt.ConstVarActive)? Constraints not provided (EstimOpt.BActive).')
    elseif length(b0) ~= length(EstimOpt.BActive)
        error('Check no. of constraints')
    end
    if EstimOpt.Display ~= 0
        disp(['Initial values: ' mat2str(b0',2)])
        disp(['Parameters with zeros are constrained to their initial values: ' mat2str(EstimOpt.BActive')]) 
    end
else    
    if ~isfield(EstimOpt,'BActive') || isempty(EstimOpt.BActive) || sum(EstimOpt.BActive == 0) == 0
        EstimOpt.BActive = ones(1,length(b0));
        if EstimOpt.Display ~= 0
            disp(['Initial values: ' mat2str(b0',2)])
        end
    else        
        if length(b0) ~= length(EstimOpt.BActive)
            error('Check no. of constraints')
        else
            if EstimOpt.Display ~= 0
                disp(['Initial values: ' mat2str(b0',2)])
                disp(['Parameters with zeros are constrained to their initial values: ' mat2str(EstimOpt.BActive')])
            end
        end
    end
end

if ((isfield(EstimOpt, 'ConstVarActive') == 1 && EstimOpt.ConstVarActive == 1) || sum(EstimOpt.BActive == 0) > 0) && ~isequal(OptimOpt.GradObj,'on')
    if EstimOpt.Display ~= 0
        cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied gradient on - otherwise parameters'' constraints will be ignored - switch to constrained optimization instead (EstimOpt.ConstVarActive = 1) \n')
    end
    OptimOpt.GradObj = 'on';
end

if EstimOpt.NVarS > 0 && EstimOpt.NumGrad == 0
	EstimOpt.NumGrad = 1;
	if EstimOpt.Display ~= 0
        cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied gradient to numerical - covariates of scale not supported by analytical gradient \n')
	end
end

% if EstimOpt.NVarNLT > 0 && EstimOpt.NLTType == 2 && EstimOpt.NumGrad == 0
% 	EstimOpt.NumGrad = 1;
% 	if EstimOpt.Display ~= 0
%         cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied gradient to numerical - Yeo-Johnston transformation not supported by analytical gradient \n')
% 	end
% end

if (isfield(EstimOpt, 'ConstVarActive') == 0 || EstimOpt.ConstVarActive == 0) && isequal(OptimOpt.Algorithm,'quasi-newton') && isequal(OptimOpt.Hessian,'user-supplied')
    if EstimOpt.Display ~= 0
        cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied Hessian off - quasi-newton algorithm does not use it anyway \n')
    end
    OptimOpt.Hessian = 'off';
end

if EstimOpt.Display ~= 0
    
    cprintf('Opmization algorithm: '); cprintf('*Black',[OptimOpt.Algorithm '\n'])

    if strcmp(OptimOpt.GradObj,'on')
        if EstimOpt.NumGrad == 0
            cprintf('Gradient: '); cprintf('*Black','user-supplied, analytical \n')
        else
            cprintf('Gradient: '); cprintf('*Black',['user-supplied, numerical, ' OptimOpt.FinDiffType '\n'])
        end
    else
        cprintf('Gradient: '); cprintf('*Black',['built-in, ' OptimOpt.FinDiffType '\n'])
    end

    if isequal(OptimOpt.Algorithm,'quasi-newton')
        cprintf('Hessian: '); cprintf('*Black','off, ')    
        switch EstimOpt.HessEstFix
            case 0
                cprintf('*Black','retained from optimization \n')
            case 1
                cprintf('*Black','ex-post calculated using BHHH \n')
            case 2
                cprintf('*Black','ex-post calculated using high-precision BHHH \n')
            case 3
                cprintf('*Black','ex-post calculated numerically \n')
            case 4
                cprintf('*Black','ex-post calculated analytically \n')
        end
    else
        if strcmp(OptimOpt.Hessian,'user-supplied')
            if EstimOpt.ApproxHess == 1
                cprintf('Hessian: '); cprintf('*Black','user-supplied, BHHH, ')
            else
                cprintf('Hessian: '); cprintf('*Black','user-supplied, analytical, ')
            end
        else
            cprintf('Hessian: '); cprintf('*Black',['built-in, ' OptimOpt.HessUpdate ', '])
        end
        switch EstimOpt.HessEstFix
            case 0
                cprintf('*Black','retained from optimization \n')
            case 1
                cprintf('*Black','ex-post calculated using BHHH \n')
            case 2
                cprintf('*Black','ex-post calculated using high-precision BHHH \n')
            case 3
                cprintf('*Black','ex-post calculated numerically \n')
            case 4
                cprintf('*Black','ex-post calculated analytically \n')
        end
    end
    
end



%% Restucturing Data - get rids of not completed choice tasks, but leaves missing alternatives


idx = sum(reshape(INPUT.MissingInd,EstimOpt.NAlt,EstimOpt.NCT*EstimOpt.NP)) == EstimOpt.NAlt; ...
idx = reshape(idx(ones(EstimOpt.NAlt,1),:), EstimOpt.NAlt*EstimOpt.NCT*EstimOpt.NP,1);
INPUT.Y = INPUT.Y(idx == 0);

INPUT.Xa(INPUT.MissingInd == 1,:) = NaN;
INPUT.Xs(INPUT.MissingInd == 1,:) = NaN;
%Xa and Xs has NaNs where there is missing alternative
INPUT.Xa = INPUT.Xa(idx == 0,:);
if EstimOpt.NVarS > 0
    INPUT.Xs = INPUT.Xs(idx == 0,:);
end


%% Estimation


LLfun = @(B) LL_mnl_MATlike(INPUT.Y, INPUT.Xa, INPUT.Xs, EstimOpt,OptimOpt,B);

if EstimOpt.ConstVarActive == 0  
    
    if EstimOpt.HessEstFix == 0
        [Results.bhat, LL, Results.exitf, Results.output, Results.g, Results.hess] = fminunc(LLfun, b0, OptimOpt);
    else
        [Results.bhat, LL, Results.exitf, Results.output, Results.g] = fminunc(LLfun, b0, OptimOpt);
    end  
    
elseif EstimOpt.ConstVarActive == 1 % equality constraints
        
    EstimOpt.CONS1 = diag(1 - EstimOpt.BActive);
    EstimOpt.CONS1(sum(EstimOpt.CONS1,1)==0,:)=[];
    EstimOpt.CONS2 = zeros(size(EstimOpt.CONS1,1),1);
%     EstimOpt.CONS1 = sparse(EstimOpt.CONS1);
%     EstimOpt.CONS2 = sparse(EstimOpt.CONS2);
    if EstimOpt.HessEstFix == 0
        [Results.bhat, LL, Results.exitf, Results.output, Results.lambda, Results.g, Results.hess] = fmincon(LLfun,b0,[],[],EstimOpt.CONS1,EstimOpt.CONS2,[],[],[],OptimOpt);
    else
        [Results.bhat, LL, Results.exitf, Results.output, Results.lambda, Results.g] = fmincon(LLfun,b0,[],[],EstimOpt.CONS1,EstimOpt.CONS2,[],[],[],OptimOpt);
    end

end


%% Output

% save tmp_MNL_output

Results.LL = -LL;
Results.b0_old = b0;

if isfield(EstimOpt,'R2type') == 0
   EstimOpt.R2type = 0; 
end
    
Results.LLdetailed = LL_mnl(INPUT.Y,INPUT.Xa,INPUT.Xs,EstimOpt,Results.bhat);
if any(INPUT.MissingInd == 1) % In case of some missing data
   idx = sum(reshape(INPUT.MissingInd,EstimOpt.NAlt,EstimOpt.NCT*EstimOpt.NP)) == EstimOpt.NAlt; ...
   idx = sum(reshape(idx, EstimOpt.NCT, EstimOpt.NP),1)'; % no. of missing NCT for every respondent
   R2 = zeros(EstimOpt.NP,1);
   idx = EstimOpt.NCT - idx;
   l = 1;
   for i = 1:EstimOpt.NP
       R2(i) = prod(exp(Results.LLdetailed(l:l-1+idx(i)))).^(1/idx(i));
       l = l+idx(i);
   end
   R2 = mean(R2);
else
    R2 = mean(prod(reshape(exp(Results.LLdetailed), EstimOpt.NCT, EstimOpt.NP),1).^(1/EstimOpt.NCT),2); 
end

if EstimOpt.HessEstFix == 1
	f = LL_mnl(INPUT.Y,INPUT.Xa,INPUT.Xs,EstimOpt,Results.bhat);
    Results.jacobian = numdiff(@(B) LL_mnl(INPUT.Y,INPUT.Xa,INPUT.Xs,EstimOpt,B),f,Results.bhat,isequal(OptimOpt.FinDiffType, 'central'),EstimOpt.BActive);
elseif EstimOpt.HessEstFix == 2
    Results.jacobian = jacobianest(@(B) LL_mnl(INPUT.Y,INPUT.Xa,INPUT.Xs,EstimOpt,B),Results.bhat);
elseif EstimOpt.HessEstFix == 3
    Results.hess = hessian(@(B) sum(LL_mnl(INPUT.Y,INPUT.Xa,INPUT.Xs,EstimOpt,B),1), Results.bhat);
elseif EstimOpt.HessEstFix == 4 %missing
    Results.hess = hessian(@(B) sum(LL_mnl(INPUT.Y,INPUT.Xa,INPUT.Xs,EstimOpt,B),1), Results.bhat);
%     EstimOpt_tmp = EstimOpt;
%     EstimOpt_tmp.NumGrad = 0;
%     EstimOpt_tmp.ApproxHess = 0;
%     [~,~,Results.hess] = LL_mnl(INPUT.Y,INPUT.Xa,INPUT.Xs,EstimOpt_tmp,Results.bhat);
end

if sum(EstimOpt.BActive == 0) > 0
    if EstimOpt.HessEstFix == 1 || EstimOpt.HessEstFix == 2
        Results.jacobian = Results.jacobian(:, EstimOpt.BActive == 1);
        Results.hess = Results.jacobian'*Results.jacobian;
    elseif EstimOpt.HessEstFix == 0 || EstimOpt.HessEstFix == 3
        Results.hess = Results.hess(EstimOpt.BActive == 1,EstimOpt.BActive == 1);
    end
    Results.ihess = inv(Results.hess);
    Results.ihess = direcXpnd(Results.ihess,EstimOpt.BActive);
    Results.ihess = direcXpnd(Results.ihess',EstimOpt.BActive);
    Results.std = sqrt(diag(Results.ihess));
	Results.std(EstimOpt.BActive == 0) = NaN;
else
	if EstimOpt.HessEstFix == 1 || EstimOpt.HessEstFix == 2
        Results.hess = Results.jacobian'*Results.jacobian;
	end
    Results.ihess = inv(Results.hess);
    Results.std = sqrt(diag(Results.ihess)); 
end

Results.std(imag(Results.std) ~= 0) = NaN;
Results.R = [Results.bhat , Results.std , pv(Results.bhat , Results.std)];

EstimOpt.Params = length(b0);
if isfield(EstimOpt,'BActive')
	EstimOpt.Params = EstimOpt.Params - sum(EstimOpt.BActive == 0);
end

if isfield(Results_old,'MNL0') && isfield(Results_old.MNL0,'LL')
    Results.stats = [Results_old.MNL0.LL; Results.LL; 1-Results.LL/Results_old.MNL0.LL;R2; ((2*EstimOpt.Params-2*Results.LL) + 2*EstimOpt.Params*(EstimOpt.Params+1)/(EstimOpt.NObs-EstimOpt.Params-1))/EstimOpt.NObs; EstimOpt.NObs; EstimOpt.Params];
end

if EstimOpt.WTP_space == 0
   % Results.WTP = IP_MNL_delta(Results.bhat(1:EstimOpt.NVarA) , Results.ihess(1:EstimOpt.NVarA,1:EstimOpt.NVarA),EstimOpt)';
else 
    Results.WTP = [Results.bhat(1:end-EstimOpt.WTP_space) Results.std(1:end-EstimOpt.WTP_space) Results.bhat(1:end-EstimOpt.WTP_space)-norminv(0.975,0,1)*Results.std(1:end-EstimOpt.WTP_space) Results.bhat(1:end-EstimOpt.WTP_space)+norminv(0.975,0,1)*Results.std(1:end-EstimOpt.WTP_space)];
end

Results.INPUT = INPUT;
Results.EstimOpt = EstimOpt;
Results.OptimOpt = OptimOpt;

clocknote = clock;
tocnote = toc;
[~,DayName] = weekday(now,'long');

if EstimOpt.Display ~= 0
    disp(' ');
    disp(['var.', blanks(size(char(EstimOpt.NamesA),2)-2) ,'coef.      st.err.  p-value'])
    disp([char(EstimOpt.NamesA), blanks(EstimOpt.NVarA)', num2str(Results.R(1:EstimOpt.NVarA,1),'%8.4f'), star_sig(Results.R(1:EstimOpt.NVarA,3)), num2str(Results.R(1:EstimOpt.NVarA,2:3),'%8.4f %8.4f')])
    disp(' ')
    
    if EstimOpt.NVarNLT > 0
        if EstimOpt.NLTType == 1
            disp('Box-Cox transformation parameters')
        elseif EstimOpt.NLTType == 2
            disp('Yeo-Johnson transformation parameters')
        end
        disp(['var.', blanks(size(char(EstimOpt.NamesA(EstimOpt.NLTVariables)),2)-2) ,'coef.      st.err.  p-value'])
        disp([char(EstimOpt.NamesA(EstimOpt.NLTVariables)), blanks(EstimOpt.NVarNLT)', num2str(Results.bhat(EstimOpt.NVarA+EstimOpt.NVarS+1:end),'%8.4f') star_sig(pv(Results.bhat(EstimOpt.NVarA+EstimOpt.NVarS+1:end) , Results.std(EstimOpt.NVarA+EstimOpt.NVarS+1:end))) num2str([Results.std(EstimOpt.NVarA+EstimOpt.NVarS+1:end) pv(Results.bhat(EstimOpt.NVarA+EstimOpt.NVarS+1:end) , Results.std(EstimOpt.NVarA+EstimOpt.NVarS+1:end))],'%8.4f %8.4f')])
        disp(' ')
    end
    
    if EstimOpt.NVarS > 0
        disp('Covariates of scale')
        disp(['var.',blanks(size(char(EstimOpt.NamesS),2)-2) ,'coef.      st.err.  p-value'])
        disp([char(EstimOpt.NamesS) ,blanks(EstimOpt.NVarS)', num2str(Results.bhat(EstimOpt.NVarA+1:end),'%8.4f') star_sig(pv(Results.bhat(EstimOpt.NVarA+1:end) , Results.std(EstimOpt.NVarA+1:end))) num2str([Results.std(EstimOpt.NVarA+1:end) pv(Results.bhat(EstimOpt.NVarA+1:end) , Results.std(EstimOpt.NVarA+1:end))],'%8.4f %8.4f')])
        disp(' ')
    end
    
    disp(['LL at convergence: ',num2str(Results.LL,'%8.4f')])
	disp(' ')
    disp(['Estimation completed on ' DayName ', ' num2str(clocknote(1)) '-' sprintf('%02.0f',clocknote(2)) '-' sprintf('%02.0f',clocknote(3)) ' at ' sprintf('%02.0f',clocknote(4)) ':' sprintf('%02.0f',clocknote(5)) ':' sprintf('%02.0f',clocknote(6))])
    disp(['Estimation took ' num2str(tocnote) ' seconds ('  num2str(floor(tocnote/(60*60))) ' hours ' num2str(floor(rem(tocnote,60*60)/60)) ' minutes ' num2str(rem(tocnote,60)) ' seconds).']);
    disp(' ');
end

Results.R_out = cell(12 + EstimOpt.NVarA + EstimOpt.NVarS + (EstimOpt.NVarS>0)*2, 4 + (EstimOpt.NVarNLT>0)*3); 

Results.R_out(1,1) = {'MNL'};

head = {'var.' , 'coef.', 'st.err.' , 'p-value'};
headx = [head, repmat(head(1,2:4),1,(EstimOpt.NVarNLT>0))];
Results.R_out(3,:) = headx;

Results.R_out(4:3+EstimOpt.NVarA,1:4) = [EstimOpt.NamesA,num2cell([Results.bhat(1:EstimOpt.NVarA),Results.std(1:EstimOpt.NVarA), pv(Results.bhat(1:EstimOpt.NVarA),Results.std(1:EstimOpt.NVarA))])];

if EstimOpt.NVarNLT > 0
	Results.DetailsNLT = [Results.bhat(EstimOpt.NVarA+EstimOpt.NVarS+1:end),Results.std(EstimOpt.NVarA+EstimOpt.NVarS+1:end),pv(Results.bhat(EstimOpt.NVarA+EstimOpt.NVarS+1:end),Results.std(EstimOpt.NVarA+EstimOpt.NVarS+1:end))];
	Results.DetailsNLT0 = NaN(EstimOpt.NVarA,3);
	Results.DetailsNLT0(EstimOpt.NLTVariables,:) = Results.DetailsNLT;
	if EstimOpt.NLTType == 1
        Results.R_out(2,5) = {'Box-Cox transformation parameters'};
	elseif EstimOpt.NLTType == 2
        Results.R_out(2,5) = {'Yeo-Johnson transformation parameters'};
	end   
    Results.R_out(4:(EstimOpt.NVarA+3),5:7) = num2cell(Results.DetailsNLT0);
end

if EstimOpt.NVarS > 0
    Results.R_out(EstimOpt.NVarA + 4,1) = {'Covariates of Scale'};
    Results.R_out(EstimOpt.NVarA + 5,1:4) = {'var.' , 'coef.', 'st.err.' , 'p-value'};
    Results.R_out(EstimOpt.NVarA + 6:EstimOpt.NVarA+EstimOpt.NVarS+5,:) = [EstimOpt.NamesS, num2cell([Results.bhat(EstimOpt.NVarA+EstimOpt.NVarNLT+1:end),Results.std(EstimOpt.NVarA+EstimOpt.NVarNLT+1:end), pv(Results.bhat(EstimOpt.NVarA+EstimOpt.NVarNLT+1:end),Results.std(EstimOpt.NVarA+EstimOpt.NVarNLT+1:end))])];
end

Results.R_out(EstimOpt.NVarA + EstimOpt.NVarS + (EstimOpt.NVarS>0)*2 + 5,1) = {'Model characteristics'};
Results.R_out(EstimOpt.NVarA + EstimOpt.NVarS + (EstimOpt.NVarS>0)*2 + 6:end,1) = {'LL0'; 'LL' ; 'McFadden R2';'Ben-Akiva R2' ;'AIC/n' ; 'n'; 'k'};
if isfield(Results_old,'MNL0') && isfield(Results_old.MNL0,'LL')
	Results.R_out(EstimOpt.NVarA + EstimOpt.NVarS + (EstimOpt.NVarS>0)*2 + 6:end,2) = num2cell(Results.stats);
end

Results.clocknote = clocknote;
Results.tocnote = clocknote;

% save(EstimOpt.fnameout, 'Results')
    
end
