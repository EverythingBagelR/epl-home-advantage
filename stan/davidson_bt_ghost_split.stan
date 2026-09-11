data {
  int<lower=1> N;
  int<lower=1> T;
  array[N] int<lower=1, upper=T> home;
  array[N] int<lower=1, upper=T> away;
  array[N] int<lower=0, upper=2> result;
  array[N] int<lower=1, upper=4> phase;
}

parameters {
  vector[T] beta_raw;
  real mu_beta;
  real<lower=0> sigma_beta;
  real alpha_pre;
  real alpha_early_ghost;
  real alpha_later_ghost;
  real alpha_post;
  real log_nu;
}

transformed parameters {
  vector[T] beta = mu_beta + sigma_beta * beta_raw;
  real nu = exp(log_nu);
  vector[4] alpha;
  alpha[1] = alpha_pre;
  alpha[2] = alpha_early_ghost;
  alpha[3] = alpha_later_ghost;
  alpha[4] = alpha_post;
}

model {
  beta_raw         ~ normal(0, 1);
  mu_beta          ~ normal(0, 1);
  sigma_beta       ~ normal(0, 1);
  alpha_pre        ~ normal(0.4, 0.3);
  alpha_early_ghost ~ normal(0.0, 0.3);
  alpha_later_ghost ~ normal(0.0, 0.3);
  alpha_post       ~ normal(0.3, 0.3);
  log_nu           ~ normal(0, 1);

  for (n in 1:N) {
    real bi = beta[home[n]] + alpha[phase[n]];
    real bj = beta[away[n]];
    real draw_term = log_nu + 0.5 * (bi + bj);
    real log_denom = log_sum_exp(log_sum_exp(bi, draw_term), bj);

    if (result[n] == 2)
      target += bi - log_denom;
    else if (result[n] == 1)
      target += draw_term - log_denom;
    else
      target += bj - log_denom;
  }
}

generated quantities {
  real delta_initial_shock = alpha_early_ghost - alpha_pre;
  real delta_adaptation = alpha_later_ghost - alpha_early_ghost;
  real delta_late_shock = alpha_later_ghost - alpha_pre;
  real delta_post_gap = alpha_post - alpha_pre;
}
