function [x,fval,exitflag] = nested_timeiter_obj(state,param,coeff_lnmh,coeff_lnmf,epsi_nodes,weight_nodes,n_nodes,x0,options)
% Call fmincon
[x,fval,exitflag] = fsolve(@eulers,x0,options);

function [residual] = eulers(control)
% load parameters
bbeta = param(1); % 1
ggamma = param(2); % 2
kkappa = param(3); % 3
eeta = param(4); % 4
rrho = param(5); %5
ssigma = param(6); %6
min_lnA = param(7);  %7
max_lnA = param(8); %8
min_lnK = param(9); %9
max_lnK = param(10); %10
min_lnN = param(11); % 11
max_lnN = param(12); % 12
degree = param(13); % 13
x = param(14); % 14
aalpha = param(15);
ddelta = param(16);
xxi = param(17);
ttau = param(18);
z = param(19);

% Load variables
lna = state(1); lnk = state(2); lnn = state(3); tot_stuff = state(4); ustuff = state(5);
lnEMH = control(1);
lnEMF = control(2);
c = 1/(bbeta*exp(lnEMH));
if c <= 0
    error('negative consumption currently');
end
q = kkappa/c/(bbeta*exp(lnEMF));
if q <= 0
    error('negative vacancy currently');
end
v = (q/ustuff)^(1/(eeta-1));
kplus = tot_stuff - c - kkappa*v;
nplus = (1-x)*exp(lnn) + q*v;
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
	lnaplus = rrho*lna + ssigma*eps;
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

% Find violation in Euler equations
residual(1) = c - bbeta*exp(lnEMH_hat);
residual(2) = kkappa/c/q - bbeta*exp(lnEMF_hat);

end

end
