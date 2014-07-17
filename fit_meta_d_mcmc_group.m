function fit = fit_meta_d_mcmc_group(nR_S1, nR_S2, mcmc_params, s, fncdf, fninv)
% fit = fit_meta_d_mcmc_group(nR_S1, nR_S2, mcmc_params, s, fncdf, fninv)
%
% Given data from an experiment where observers discriminate between two
% stimulus alternatives on every trial and provides confidence ratings,
% fits Maniscalco & Lau's meta-d' model to the data using MCMC implemented in
% JAGS. Requires matjags and JAGS to be installed
% (see http://psiexp.ss.uci.edu/research/programs_data/jags/)
%
% Use fit_meta_d_mcmc if you are estimating single-subject data. This
% function will estimate group-level parameter distributions over meta-d' from the set of
% all subjects' choices, having taken into account uncertainty in model
% fits at the single-subject level.
%
% For more information on the model please see:
%
% Maniscalco B, Lau H (2012) A signal detection theoretic approach for
% estimating metacognitive sensitivity from confidence ratings.
% Consciousness and Cognition
%
% Also allows fitting of response-conditional meta-d' via setting in mcmc_params
% (see below). This model fits meta-d' SEPARATELY for S1 and S2 responses.
% For more details on this model variant please see:

% Maniscalco & Lau (2014) Signal detection theory analysis of Type 1 and
% Type 2 data: meta-d', response-specific meta-d' and the unequal variance
% SDT model. In SM Fleming & CD Frith (eds) The Cognitive Neuroscience of
% Metacognition. Springer.
%
% INPUTS
%
% * nR_S1, nR_S2
% these are cell arrays containing the total number of responses in
% each response category, conditional on presentation of S1 and S2, for
% each subject. Each subject's data must contain the same number of
% response categories.
%
% e.g. if nR_S1{i} = [100 50 20 10 5 1], then when stimulus S1 was
% presented, subject "i" had the following response counts:
% responded S1, rating=3 : 100 times
% responded S1, rating=2 : 50 times
% responded S1, rating=1 : 20 times
% responded S2, rating=1 : 10 times
% responded S2, rating=2 : 5 times
% responded S2, rating=3 : 1 time
%
% * s
% this is the ratio of standard deviations for type 1 distributions, i.e.
%
% s = sd(S1) / sd(S2)
%
% if not specified, s is set to a default value of 1.
% the function SDT_MLE_fit available at
% http://www.columbia.edu/~bsm2105/type2sdt/
% can be used to get an MLE estimate of s using Matlab's optimization
% toolbox. This is somewhat deprecated in the hierarchical fit as it is not
% obvious whether s should be specified for each subject individually.
% Doing so would be a simple modification of this function to allow s to
% be a vector of length N subjects.
%
% * fncdf
% a function handle for the CDF of the type 1 distribution.
% if not specified, fncdf defaults to @normcdf (i.e. CDF for normal
% distribution)
%
% * fninv
% a function handle for the inverse CDF of the type 1 distribution.
% if not specified, fninv defaults to @norminv
%
% * mcmc_params
% a structure specifying parameters for running the MCMC chains in JAGS.
% Type "help matjags" for more details. If empty defaults to the following
% parameters:
%
%     mcmc_params.response_conditional = 0; % Do we want to fit response-conditional meta-d'?
%     mcmc_params.nchains = 3; % How Many Chains?
%     mcmc_params.nburnin = 1000; % How Many Burn-in Samples?
%     mcmc_params.nsamples = 10000;  %How Many Recorded Samples?
%     mcmc_params.nthin = 1; % How Often is a Sample Recorded?
%     mcmc_params.doparallel = 0; % Parallel Option
%     mcmc_params.dic = 1;  % Save DIC
%     mcmc_params.init0(1:nchains).meta_d = d1/2
%     mcmc_params.init0(1:nchains).cS1_raw = linspace(-1,0.2,nRatings)
%     mcmc_params.init0(1:nchains).cS2_raw = linspace(0.2,1,nRatings)
%
% To get meaningful Rhat estimates mcmc_params.init0 should be set at
% different locations for each chain (see XX for more details)
%
% OUTPUT
%
% Output is packaged in the struct "fit". All parameter values are taken
% from the means of the posterior MCMC distributions, with full
% posteriors stored in fit.mcmc
%
% In the following, let S1 and S2 represent the distributions of evidence
% generated by stimulus classes S1 and S2.
% Then the fields of "fit" are as follows:
%
% fit.da        = mean(S2) - mean(S1), in room-mean-square(sd(S1),sd(S2)) units
% fit.s         = sd(S1) / sd(S2)
% fit.meta_da   = meta-d' in RMS units
% fit.M_diff    = meta_da - da
% fit.M_ratio   = meta_da / da
% fit.t1ca      = type 1 criterion for meta-d' fit, RMS units
% fit.t2ca      = type 2 criteria for meta-d' fit, RMS units
%
% fit.mcmc.dic          = deviance information criterion (DIC) for model
% fit.mcmc.Rhat    = Gelman & Rubin's Rhat statistic for each parameter
% fit.mcmc.
%
% fit.obs_HR2_rS1  = actual type 2 hit rates for S1 responses
% fit.est_HR2_rS1  = estimated type 2 hit rates for S1 responses
% fit.obs_FAR2_rS1 = actual type 2 false alarm rates for S1 responses
% fit.est_FAR2_rS1 = estimated type 2 false alarm rates for S1 responses
%
% fit.obs_HR2_rS2  = actual type 2 hit rates for S2 responses
% fit.est_HR2_rS2  = estimated type 2 hit rates for S2 responses
% fit.obs_FAR2_rS2 = actual type 2 false alarm rates for S2 responses
% fit.est_FAR2_rS2 = estimated type 2 false alarm rates for S2 responses
%
% If there are N ratings, then there will be N-1 type 2 hit rates and false
% alarm rates. If meta-d' is fit using the response-conditional model,
% these parameters will be replicated separately for S1 and S2 responses.
%
% 6/5/2014 Steve Fleming www.stevefleming.org
% Parts of this code are adapted from Brian Maniscalco's meta-d' toolbox
% which can be found at http://www.columbia.edu/~bsm2105/type2sdt/

% toy data
% nR_S1{1} = [1552  933  954  720  448  220   78   27];
% nR_S2{1} = [33   77  213  469  729 1013  975 1559];
% nR_S1{2} = [1540  933  953  724  455  219   79   25];
% nR_S2{2} = [35   76  220  469  713 1020  973 1560];

if ~exist('s','var') || isempty(s)
    s = 1;
end

if ~exist('fncdf','var') || isempty(fncdf)
    fncdf = @normcdf;
end

if ~exist('fninv','var') || isempty(fninv)
    fninv = @norminv;
end

Nsubj = length(nR_S1);
nRatings = length(nR_S1{1})/2;
c1_index = nRatings;
padFactor = 1/(2*nRatings);

for n = 1:Nsubj
    
    if length(nR_S1{n}) ~= nRatings*2 || length(nR_S2{n}) ~= nRatings*2
        error('Subjects do not have equal numbers of response categories');
    end
    % Get type 1 SDT parameter values
    counts(n,:) = [nR_S1{n} nR_S2{n}];
    nTot(n) = sum(counts(n,:));
    pad_nR_S1 = nR_S1{n} + padFactor;
    pad_nR_S2 = nR_S2{n} + padFactor;
    
    j=1;
    for c = 2:nRatings*2
        ratingHR(j) = sum(pad_nR_S2(c:(nRatings*2)))/sum(pad_nR_S2);
        ratingFAR(j) = sum(pad_nR_S1(c:(nRatings*2)))/sum(pad_nR_S1);
        j=j+1;
    end
    
    % Get type 1 estimate (from pair of middle HR/FAR ratings)
    d1(n) = norminv(ratingHR(c1_index))-norminv(ratingFAR(c1_index));
    c1(n) = -0.5 * (norminv(ratingHR(c1_index)) + norminv(ratingFAR(c1_index)));
end

%% Sampling
if ~exist('mcmc_params','var') || isempty(mcmc_params)
    % MCMC Parameters
    mcmc_params.response_conditional = 0;
    mcmc_params.nchains = 3; % How Many Chains?
    mcmc_params.nburnin = 1000; % How Many Burn-in Samples?
    mcmc_params.nsamples = 10000;  %How Many Recorded Samples?
    mcmc_params.nthin = 1; % How Often is a Sample Recorded?
    mcmc_params.doparallel = 0; % Parallel Option
    mcmc_params.dic = 1;
    % Initialize Unobserved Variables
    for i=1:mcmc_params.nchains
        if mcmc_params.response_conditional
            S.mu_Mratio_rS1 = 1;
            S.lambda_Mratio_rS1 = 0.5;
            S.mu_Mratio_rS2 = 1;
            S.lambda_Mratio_rS2 = 0.5;
        else
            S.mu_Mratio = 1;
            S.lambda_Mratio = 0.5;
        end
        S.cS1_raw = linspace(-1,0.2,nRatings);
        S.cS2_raw = linspace(0.2,1,nRatings);
        mcmc_params.init0(i) = S;
    end
end
% Assign variables to the observed nodes
datastruct = struct('nsubj',Nsubj,'counts', counts, 'd1', d1, 'c', c1, 'nratings', nRatings, 'nTot', nTot, 'Tol', 1e-05);

% Select model file and parameters to monitor

switch mcmc_params.response_conditional
    case 0
        model_file = 'Bayes_metad_group.txt';
        monitorparams = {'mu_Mratio','lambda_Mratio','Mratio','cS1','cS2'};
        
    case 1
        model_file = 'Bayes_metad_rc_group.txt';
        monitorparams = {'mu_Mratio_rS1','mu_Mratio_rS2','lambda_Mratio_rS1','lambda_Mratio_rS2','Mratio_rS1','Mratio_rS2','cS1','cS2'};
end

% Use JAGS to Sample
tic
fprintf( 'Running JAGS ...\n' );
[samples, stats] = matjags( ...
    datastruct, ...
    fullfile(pwd, model_file), ...
    mcmc_params.init0, ...
    'doparallel' , mcmc_params.doparallel, ...
    'nchains', mcmc_params.nchains,...
    'nburnin', mcmc_params.nburnin,...
    'nsamples', mcmc_params.nsamples, ...
    'thin', mcmc_params.nthin, ...
    'dic', mcmc_params.dic,...
    'monitorparams', monitorparams, ...
    'savejagsoutput' , 0 , ...
    'verbosity' , 1 , ...
    'cleanup' , 1 , ...
    'workingdir' , 'tmpjags' );
toc

% Package group-level output

if ~mcmc_params.response_conditional
    
    fit.mu_Mratio = stats.mean.mu_Mratio;
    fit.lambda_Mratio = stats.mean.lambda_Mratio;
    fit.Mratio = stats.mean.Mratio;
    fit.meta_d   = fit.Mratio.*d1;
    fit.meta_da = sqrt(2/(1+s^2)) * s * fit.meta_d;

else
    
    fit.mu_Mratio_rS1 = stats.mean.mu_Mratio_rS1;
    fit.mu_Mratio_rS2 = stats.mean.mu_Mratio_rS2;
    fit.lambda_Mratio_rS1 = stats.mean.lambda_Mratio_rS1;
    fit.lambda_Mratio_rS2 = stats.mean.lambda_Mratio_rS2;
    fit.Mratio_rS1 = stats.mean.Mratio_rS1;
    fit.Mratio_rS2 = stats.mean.Mratio_rS2;
    fit.meta_d_rS1   = fit.Mratio_rS1.*d1;
    fit.meta_d_rS2   = fit.Mratio_rS2.*d1;
    fit.meta_da_rS1 = sqrt(2/(1+s^2)) * s * fit.meta_d_rS1;
    fit.meta_da_rS2 = sqrt(2/(1+s^2)) * s * fit.meta_d_rS2;

end
fit.da        = sqrt(2/(1+s^2)) .* s .* d1;
fit.s         = s;
fit.meta_ca   = ( sqrt(2).*s ./ sqrt(1+s.^2) ) .* c1;
fit.t2ca_rS1  = ( sqrt(2).*s ./ sqrt(1+s.^2) ) .* stats.mean.cS1;
fit.t2ca_rS2  = ( sqrt(2).*s ./ sqrt(1+s.^2) ) .* stats.mean.cS2;

fit.mcmc.dic = stats.dic;
fit.mcmc.Rhat = stats.Rhat;
fit.mcmc.samples = samples;
fit.mcmc.params = mcmc_params;

for n = 1:Nsubj
    
    
    %% Data is fit, now package output
    I_nR_rS2 = nR_S1{n}(nRatings+1:end);
    I_nR_rS1 = nR_S2{n}(nRatings:-1:1);
    
    C_nR_rS2 = nR_S2{n}(nRatings+1:end);
    C_nR_rS1 = nR_S1{n}(nRatings:-1:1);
    
    for i = 2:nRatings
        obs_FAR2_rS2(i-1) = sum( I_nR_rS2(i:end) ) / sum(I_nR_rS2);
        obs_HR2_rS2(i-1)  = sum( C_nR_rS2(i:end) ) / sum(C_nR_rS2);
        
        obs_FAR2_rS1(i-1) = sum( I_nR_rS1(i:end) ) / sum(I_nR_rS1);
        obs_HR2_rS1(i-1)  = sum( C_nR_rS1(i:end) ) / sum(C_nR_rS1);
    end
    
    
    % Calculate fits based on either vanilla or response-conditional model
    switch mcmc_params.response_conditional
        
        case 0
            
            %% find estimated t2FAR and t2HR
            meta_d = fit.meta_d(n);
            S1mu = -meta_d/2; S1sd = 1;
            S2mu =  meta_d/2; S2sd = S1sd/s;
            
            C_area_rS2 = 1-fncdf(c1(n),S2mu,S2sd);
            I_area_rS2 = 1-fncdf(c1(n),S1mu,S1sd);
            
            C_area_rS1 = fncdf(c1(n),S1mu,S1sd);
            I_area_rS1 = fncdf(c1(n),S2mu,S2sd);
            
            t2c1 = [fit.t2ca_rS1(n,:) fit.t2ca_rS2(n,:)];
            
            for i=1:nRatings-1
                
                t2c1_lower = t2c1(nRatings-i);
                t2c1_upper = t2c1(nRatings-1+i);
                
                I_FAR_area_rS2 = 1-fncdf(t2c1_upper,S1mu,S1sd);
                C_HR_area_rS2  = 1-fncdf(t2c1_upper,S2mu,S2sd);
                
                I_FAR_area_rS1 = fncdf(t2c1_lower,S2mu,S2sd);
                C_HR_area_rS1  = fncdf(t2c1_lower,S1mu,S1sd);
                
                
                est_FAR2_rS2(i) = I_FAR_area_rS2 / I_area_rS2;
                est_HR2_rS2(i)  = C_HR_area_rS2 / C_area_rS2;
                
                est_FAR2_rS1(i) = I_FAR_area_rS1 / I_area_rS1;
                est_HR2_rS1(i)  = C_HR_area_rS1 / C_area_rS1;
                
            end
            
        case 1
            
            %% find estimated t2FAR and t2HR
            S1mu_rS1 = -fit.meta_d_rS1(n)/2; S1sd = 1;
            S2mu_rS1 =  fit.meta_d_rS1(n)/2; S2sd = S1sd/s;
            S1mu_rS2 = -fit.meta_d_rS2(n)/2/2;
            S2mu_rS2 =  fit.meta_d_rS2(n)/2;
            
            C_area_rS2 = 1-fncdf(c1(n),S2mu_rS2,S2sd);
            I_area_rS2 = 1-fncdf(c1(n),S1mu_rS2,S1sd);
            
            C_area_rS1 = fncdf(c1(n),S1mu_rS1,S1sd);
            I_area_rS1 = fncdf(c1(n),S2mu_rS1,S2sd);
            
            t2c1 = [fit.t2ca_rS1(n,:) fit.t2ca_rS2(n,:)];
            
            for i=1:nRatings-1
                
                t2c1_lower = t2c1(nRatings-i);
                t2c1_upper = t2c1(nRatings-1+i);
                
                I_FAR_area_rS2 = 1-fncdf(t2c1_upper,S1mu_rS2,S1sd);
                C_HR_area_rS2  = 1-fncdf(t2c1_upper,S2mu_rS2,S2sd);
                
                I_FAR_area_rS1 = fncdf(t2c1_lower,S2mu_rS1,S2sd);
                C_HR_area_rS1  = fncdf(t2c1_lower,S1mu_rS1,S1sd);
                
                
                est_FAR2_rS2(i) = I_FAR_area_rS2 / I_area_rS2;
                est_HR2_rS2(i)  = C_HR_area_rS2 / C_area_rS2;
                
                est_FAR2_rS1(i) = I_FAR_area_rS1 / I_area_rS1;
                est_HR2_rS1(i)  = C_HR_area_rS1 / C_area_rS1;
                
            end
            
    end
    fit.est_HR2_rS1(n,:)  = est_HR2_rS1;
    fit.obs_HR2_rS1(n,:)  = obs_HR2_rS1;
    
    fit.est_FAR2_rS1(n,:) = est_FAR2_rS1;
    fit.obs_FAR2_rS1(n,:) = obs_FAR2_rS1;
    
    fit.est_HR2_rS2(n,:)  = est_HR2_rS2;
    fit.obs_HR2_rS2(n,:)  = obs_HR2_rS2;
    
    fit.est_FAR2_rS2(n,:) = est_FAR2_rS2;
    fit.obs_FAR2_rS2(n,:) = obs_FAR2_rS2;
end
