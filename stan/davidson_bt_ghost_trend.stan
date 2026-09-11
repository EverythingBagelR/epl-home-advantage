data {
  int<lower=1> N;
  int<lower=1> T;
  array[N] int<lower=1, upper=T> home;
  array[N] int<lower=1, upper=T> away;
  array[N] int<lower=0, upper=2> result;
  array[N] int<lower=1, upper=3> phase;
  vector<lower=0, upper=1>[N] ghost_progress;
}

parameters {
  vector[T] beta_raw;
  real mu_beta;
  real<lower=0> sigma_beta;
  real alpha_pre;
  real alpha_ghost_start;
  real gamma_ghost;
  real alpha_post;
  real log_nu;
}

transformed parameters {
  vector[T] beta = mu_beta + sigma_beta * beta_raw;
  real nu = exp(log_nu);
}

model {
  beta_raw         ~ normal(0, 1);
  mu_beta          ~ normal(0, 1);
  sigma_beta       ~ normal(0, 1);
  alpha_pre        ~ normal(0.4, 0.3);
  alpha_ghost_start ~ normal(0.0, 0.3);
  gamma_ghost      ~ normal(0.0, 0.3);
  alpha_post       ~ normal(0.3, 0.3);
  log_nu           ~ normal(0, 1);

  for (n in 1:N) {
    real alpha_n;

    if (phase[n] == 1)
      alpha_n = alpha_pre;
    else if (phase[n] == 2)
      alpha_n = alpha_ghost_start + gamma_ghost * ghost_progress[n];
    else
      alpha_n = alpha_post;

    {
      real bi = beta[home[n]] + alpha_n;
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
}

generated quantities {
  real alpha_ghost_end = alpha_ghost_start + gamma_ghost;
  real delta_ghost_trend = gamma_ghost;
}
