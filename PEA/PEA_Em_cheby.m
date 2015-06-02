%% Housekeeping
clear
close all
clc
format long
addpath('../tools')

%% Set the stage
mypara;
min_lnA = log(0.5); max_lnA = log(1.5);
min_lnK = log(900); max_lnK = log(1900);
min_lnN = log(0.5); max_lnN = log(0.9999);
degree = 7;
nA = 9;
nK = 9;
nN = 9;
damp_factor = 0.9;
maxiter = 10000;
tol = 1e-6;
options = optimoptions(@fsolve,'Display','final-detailed','Jacobian','off');
[epsi_nodes,weight_nodes] = GH_nice(5,0,1);
n_nodes = length(epsi_nodes);

%% Grid creaton
lnAgrid = ChebyshevRoots(nA,'Tn',[log(0.85),log(1.15)]);
lnKgrid = ChebyshevRoots(nK,'Tn',[log(1200),log(1500)]);
lnNgrid = ChebyshevRoots(nN,'Tn',[log(0.9),log(0.98)]);
lnAchebygrid = ChebyshevRoots(nA,'Tn');
lnKchebygrid = ChebyshevRoots(nK,'Tn');
lnNchebygrid = ChebyshevRoots(nN,'Tn');
N = nA*nK*nN;

[fakebasis,order_table] = ChebyshevND(degree,[0,0,0]);
K = size(fakebasis,2);

%% Encapsulate all parameters
param = [... 
 bbeta; % 1
 ggamma; % 2
 kkappa; % 3
 eeta; % 4
 rrho; %5
 ssigma; %6
 min_lnA;  %7
 max_lnA; %8
 min_lnK; %9
 max_lnK; %10
 min_lnN; % 11
 max_lnN; % 12
 degree; % 13
 x; % 14
 aalpha; % 15
 ddelta; % 16
 xxi; % 17
 ttau; % 18
 z
 ];

%% Precomputation
X = zeros(N,K);
tot_stuff = zeros(N,1); ustuff = zeros(N,1);
parfor i = 1:N
    [i_a,i_k,i_n] = ind2sub([nA,nK,nN],i);
    a = exp(lnAgrid(i_a)); k  = exp(lnKgrid(i_k)); n = exp(lnNgrid(i_n)); %#ok<PFBNS>
    tot_stuff(i) = a*k^aalpha*n^(1-aalpha) + (1-ddelta)*k + z*(1-n);
    ustuff(i) = xxi*(1-n)^(1-eeta);
    X(i,:) = ChebyshevND(degree,[lnAchebygrid(i_a),lnKchebygrid(i_k),lnNchebygrid(i_n)])
end

%% Create a initial guess from a rough PEA solution
if (exist('PEA_Em.mat','file')==2)
    load('PEA_Em.mat','coeff_mh','coeff_mf')
else
    coeff_mh = [2.197278872016918; -0.030892629079668; -0.581445054648990; -0.004225383144729]; % one constant, each for state variable
    coeff_mf = [2.281980399764238; 1.729203578753512; -0.315489670998162; -0.115805845378316];
end
lnEmh_train = zeros(N,1); lnEmf_train = zeros(N,1);
parfor i = 1:N
    [i_a,i_k,i_n] = ind2sub([nA,nK,nN],i);
    lnEmh_train(i) = ([1 lnAgrid(i_a) lnKgrid(i_k) lnNgrid(i_n)]*coeff_mh);
    lnEmf_train(i) = ([1 lnAgrid(i_a) lnKgrid(i_k) lnNgrid(i_n)]*coeff_mf)
end
coeff_lnmh = (X'*X)\(X'*(lnEmh_train));
coeff_lnmf = (X'*X)\(X'*(lnEmf_train));
coeff_lnmh_old = coeff_lnmh;
coeff_lnmf_old = coeff_lnmf;

lnEM_new = zeros(N,2);

%% Solve for SS
kss = k_ss;
nss = n_ss;

%% Iteration
opts = statset('nlinfit');
%opts.RobustWgtFun = 'bisquare';
opts.Display = 'final';
opts.MaxIter = 10000;
diff = 10; iter = 0;
while (diff>tol && iter <= maxiter)
    %% Time iter step, find EMF EMH that solve euler exactly
    for i = 1:N
        [i_a,i_k,i_n] = ind2sub([nA,nK,nN],i);
        state = [lnAgrid(i_a),lnKgrid(i_k),lnNgrid(i_n),tot_stuff(i),ustuff(i)];
        lnEMH = ChebyshevND(degree,[lnAchebygrid(i_a),lnKchebygrid(i_k),lnNchebygrid(i_n)])*coeff_lnmh;
        lnEMF = ChebyshevND(degree,[lnAchebygrid(i_a),lnKchebygrid(i_k),lnNchebygrid(i_n)])*coeff_lnmf;
        c = 1/(bbeta*exp(lnEMH));
        q = kkappa/c/(bbeta*exp(lnEMF));
        v = (q/ustuff(i))^(1/(eeta-1));
        kplus = tot_stuff(i) - c - kkappa*v;
        nplus = (1-x)*exp(lnNgrid(i_n)) + q*v;
        lnkplus = log(kplus); lnnplus = log(nplus);
        lnkplus_cheby = -1 + 2*(lnkplus-min_lnK)/(max_lnK-min_lnK);
        lnnplus_cheby = -1 + 2*(lnnplus-min_lnN)/(max_lnN-min_lnN);
        if (lnkplus_cheby < -1 || lnkplus_cheby > 1)
            lnkplus
            error('kplus out of bound')
        end
        if (lnnplus_cheby < -1 || lnnplus_cheby > 1)
            lnnplus_cheby
            lnnplus
            error('nplus out of bound')
        end
        
        % Find expected mh, mf tomorrow if current coeff applies tomorrow
        lnEMH_hat = 0;
        lnEMF_hat = 0;
        for i_node = 1:n_nodes
            eps = epsi_nodes(i_node);
            lnaplus = rrho*lnAgrid(i_a) + ssigma*eps;
            lnaplus_cheby = -1 + 2*(lnaplus-min_lnA)/(max_lnA-min_lnA);
            if (lnaplus_cheby < -1 || lnaplus_cheby > 1)
                error('Aplus out of bound')
            end
            lnEMH_plus = ChebyshevND(degree,[lnaplus_cheby,lnkplus_cheby,lnnplus_cheby])*coeff_lnmh;
            lnEMF_plus = ChebyshevND(degree,[lnaplus_cheby,lnkplus_cheby,lnnplus_cheby])*coeff_lnmf;
            cplus = 1/(bbeta*exp(lnEMH_plus));
            qplus = kkappa/cplus/(bbeta*exp(lnEMF_plus));
            tthetaplus = (qplus/xxi)^(1/(eeta-1));
            lnEMH_hat = lnEMH_hat + weight_nodes(i_node)*((1-ddelta+aalpha*exp(lnaplus)*(kplus/nplus)^(aalpha-1))/cplus);
            lnEMF_hat = lnEMF_hat + weight_nodes(i_node)*(( (1-ttau)*((1-aalpha)*exp(lnaplus)*(kplus/nplus)^aalpha-z-ggamma*cplus) + (1-x)*kkappa/qplus - ttau*kkappa*tthetaplus )/cplus );
        end        
        lnEM_new(i,:) = [lnEMH_hat,lnEMF_hat];
    end
    coeff = (X'*X)\(X'*lnEM_new);
    coeff_lnmh_temp = coeff(:,1); coeff_lnmf_temp = coeff(:,2);
    
    %% Damped update
    coeff_lnmh_new = (1-damp_factor)*coeff_lnmh_temp+(damp_factor)*coeff_lnmh;
    coeff_lnmf_new = (1-damp_factor)*coeff_lnmf_temp+(damp_factor)*coeff_lnmf;
    
    %% Compute norm
    diff = norm([coeff_lnmh;coeff_lnmf]-[coeff_lnmh_new;coeff_lnmf_new],Inf);
    
    %% Update
    coeff_lnmh = coeff_lnmh_new;
    coeff_lnmf = coeff_lnmf_new;
    iter = iter+1;
    %% Display something
    iter
    diff
    coeff_lnmh;
    coeff_lnmf;

end;

%% Euler equation error
nk = 50; nA = 50; nnn = 50;
lnKgrid = linspace(0.8*kss,1.2*kss,nk);
lnAgrid = linspace(0.8,1.2,nA);
lnNgrid = linspace(0.7,0.999,nnn);
EEerror_c = 999999*ones(nA,nk,nnn);
EEerror_v = 999999*ones(nA,nk,nnn);

for i_A = 1:nA
    A = lnAgrid(i_A);
    for i_k = 1:nk
        k = lnKgrid(i_k);
        for i_n = 1:nnn
            n = lnNgrid(i_n);
            state(1) = A;
            state(2) = k;
            state(3) = n;
            EM = exp([1 log(state)]*[coeff_mh coeff_mf]);
            
            y = A*(k)^(aalpha)*(n)^(1-aalpha);
            c = (bbeta*EM(1))^(-1);
            ttheta = (kkappa/(c*xxi*bbeta*EM(2)))^(1/(eeta-1));
            v = ttheta*(1-n);
            kplus = y - c +(1-ddelta)*k - kkappa*v + z*(1-n);
            nplus = (1-x)*n + xxi*ttheta^(eeta)*(1-n);
            
            % Find expected mf and mh and implied consumption
            Emf = 0; Emh = 0;
            for i_node = 1:length(weight_nodes)
                Aplus = exp(rrho_A*log(A) + ssigma_A*epsi_nodes(i_node));
                state(1) = Aplus;
                state(2) = kplus;
                state(3) = nplus;
                EM = exp([1 log(state)]*[coeff_mh coeff_mf]);
                yplus = Aplus*(kplus)^(aalpha)*(nplus)^(1-aalpha);
                cplus = (bbeta*EM(1))^(-1);
                tthetaplus = (kkappa/(cplus*xxi*bbeta*EM(2)))^(1/(eeta-1));
                Emh = Emh + weight_nodes(i_node)*((1-ddelta+aalpha*yplus/kplus)/cplus);
                Emf = Emf + weight_nodes(i_node)*(( (1-ttau)*((1-aalpha)*yplus/nplus-z-ggamma*cplus) + (1-x)*kkappa/xxi*tthetaplus^(1-eeta) - ttau*kkappa*tthetaplus )/cplus );
            end
            c_imp = (bbeta*Emh)^(-1);
            q_imp = kkappa/(c_imp*bbeta*Emf);
            v_imp = (q_imp/(xxi*(1-n)^(1-eeta)))^(1/(eeta-1));
            EEerror_c(i_A,i_k,i_n) = abs((c-c_imp)/c_imp);   
            EEerror_v(i_A,i_k,i_n) = abs((v-v_imp)/v_imp);  
        end
    end
end
EEerror_c_inf = norm(EEerror_c(:),inf);
EEerror_v_inf = norm(EEerror_v(:),inf);

EEerror_c_mean = mean(EEerror_c(:));
EEerror_v_mean = mean(EEerror_v(:));

figure
plot(lnKgrid,EEerror_c(ceil(nA/2),:,ceil(nnn/2)))

%% Implied policy functions and find wages
lnAgrid = csvread('../CUDA_VFI/results/Agrid.csv');
lnKgrid = csvread('../CUDA_VFI/results/Kgrid.csv');
lnNgrid = csvread('../CUDA_VFI/results/Ngrid.csv');
nA = length(lnAgrid);
nk = length(lnKgrid);
nnn = length(lnNgrid);

kk = zeros(nA,nk,nnn);
cc = kk;
vv = kk;
nn = kk;
ttheta_export = kk;
wage_export = kk;
cc_dynare = kk;
kk_dynare = kk;
nn_dynare = kk;
vv_dynare = kk;

mmummu = kk;
for i_k = 1:nk
    for i_n = 1:nnn
        for i_A = 1:nA
            state(1) = lnAgrid(i_A); A = state(1);
            state(2) = lnKgrid(i_k); k = state(2);
            state(3) = lnNgrid(i_n); n = state(3);
            EM = exp([1 log(state)]*[coeff_mh coeff_mf]);
            
            y = A*(k)^(aalpha)*(n)^(1-aalpha);
            c = (bbeta*EM(1))^(-1);
            ttheta = (kkappa/(c*xxi*bbeta*EM(2)))^(1/(eeta-1));
            v = ttheta*(1-n);
            mh = (1-ddelta+aalpha*y/k)/c;
            mf = ( (1-ttau)*((1-aalpha)*y/n-z-ggamma*c) + (1-x)*kkappa/xxi*ttheta^(1-eeta) - ttau*kkappa*ttheta )/c;
            w = ttau*A*k^(aalpha)*(1-aalpha)*n^(-aalpha) + (1-ttau)*(z+ggamma*c) + ttau*kkappa*ttheta;
    
            kk(i_A,i_k,i_n) = y - c +(1-ddelta)*k - kkappa*v + z*(1-nn(i_A,i_k,i_n));
            nn(i_A,i_k,i_n) = (1-x)*n + xxi*ttheta^(eeta)*(1-n);
            cc(i_A,i_k,i_n) = c;
            vv(i_A,i_k,i_n) = v;
            
            cc_dynare(i_A,i_k,i_n) = exp(2.111091 + 0.042424/rrho*log(lnAgrid(i_A))/ssigma + 0.615500*(log(lnKgrid(i_k))-log(k_ss)) + 0.014023*(log(lnNgrid(i_n))-log(n_ss)) );
            kk_dynare(i_A,i_k,i_n) = exp(7.206845 + 0.006928/rrho*log(lnAgrid(i_A))/ssigma + 0.997216*(log(lnKgrid(i_k))-log(k_ss)) + 0.005742*(log(lnNgrid(i_n))-log(n_ss)) );
            nn_dynare(i_A,i_k,i_n) = exp(-0.056639 + 0.011057/rrho*log(lnAgrid(i_A))/ssigma + 0.001409*(log(lnKgrid(i_k))-log(k_ss)) + 0.850397*(log(lnNgrid(i_n))-log(n_ss)) );
            
            % Export prices
            wage_export(i_A,i_k,i_n) = w;
            ttheta_export(i_A,i_k,i_n) = ttheta;
        end
    end
end
save('PEA_Em.mat');


i_mid_n = ceil(nnn/2);
i_mid_A = ceil(nA/2);
linewitdh=1.5;
figure
plot(lnKgrid,squeeze(kk(i_mid_A,:,i_mid_n)),lnKgrid,squeeze(kk_dynare(i_mid_A,:,i_mid_n)),'LineWidth',linewitdh)
axis('tight')
xlabel('k(t)')
ylabel('k(t+1)')
legend('Nonlinear','Linear')

figure
plot(lnKgrid,squeeze(nn(i_mid_A,:,i_mid_n)),lnKgrid,squeeze(nn_dynare(i_mid_A,:,i_mid_n)),'LineWidth',linewitdh)
axis('tight')
xlabel('k(t)')
ylabel('n(t+1)')
legend('Nonlinear','Linear')

figure
plot(lnKgrid,squeeze(cc(i_mid_A,:,i_mid_n)),lnKgrid,squeeze(cc_dynare(i_mid_A,:,i_mid_n)),'LineWidth',linewitdh)
axis('tight')
xlabel('k(t)')
ylabel('c(t)')
legend('Nonlinear','Linear')

figure
plot(lnKgrid,squeeze(wage_export(i_mid_A,:,i_mid_n)),'LineWidth',linewitdh)
axis('tight')
xlabel('k(t)')
ylabel('wage')
legend('Nonlinear')

figure
plot(lnKgrid,squeeze(ttheta_export(i_mid_A,:,i_mid_n)),'LineWidth',linewitdh)
axis('tight')
xlabel('k(t)')
ylabel('Tightness')
legend('Nonlinear')

%% Ergodic set where art thou?
    figure
    scatter3(Asim,ksim,nsim)
    xlabel('Productivity')
    ylabel('Capital')
    zlabel('Employment')

%% Dynamics
Aindex = ceil(nA/2);
figure
[Kmesh,Nmesh] = meshgrid(lnKgrid,lnNgrid);
DK = squeeze(kk(Aindex,:,:))-Kmesh';
DN = squeeze(nn(Aindex,:,:))-Nmesh';
quiver(Kmesh',Nmesh',DK,DN,2);
axis tight

%% Paths 1
T = 5000; scale = 0;
A = 0.6;
k1 = zeros(1,T); n1 = zeros(1,T);
k1(1) = 1100; n1(1) = 0.90;
for t = 1:T
    state = [A k1(t) n1(t)];
    EM = exp([1 log(state)]*[coeff_mh coeff_mf]);
    y = A*(k1(t))^(aalpha)*(n1(t))^(1-aalpha);
    c = (bbeta*EM(1))^(-1);
    ttheta = (kkappa/(c*xxi*bbeta*EM(2)))^(1/(eeta-1));
    v = ttheta*(1-n1(t));
    
    if t < T
    k1(t+1) = y - c +(1-ddelta)*k1(t) - kkappa*v;
    n1(t+1) = (1-x)*n1(t) + xxi*ttheta^(eeta)*(1-n1(t));
    end
end
xx = k1; y = n1;
u = [k1(2:end)-k1(1:end-1) 0];
v = [n1(2:end)-n1(1:end-1) 0];

figure
quiver(xx,y,u,v,scale,'Linewidth',0.3);



wage_export = wage_export(:);
ttheta_export = ttheta_export(:);
cc = cc(:);
kk = kk(:);
nn = nn(:);
dlmwrite('../CUDA_VFI/wage_export.csv',wage_export,'precision',16);
dlmwrite('../CUDA_VFI/ttheta_export.csv',ttheta_export,'precision',16);
dlmwrite('../CUDA_VFI/cPEA_export.csv',cc,'precision',16);
dlmwrite('../CUDA_VFI/kPEA_export.csv',kk,'precision',16);
dlmwrite('../CUDA_VFI/nPEA_export.csv',nn,'precision',16);


save('PEA_Em.mat');