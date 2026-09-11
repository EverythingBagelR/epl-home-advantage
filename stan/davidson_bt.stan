data {
  int<lower=1> N;
  int<lower=1> T;
  array[N] int home;
  array[N] int away;
  array[N] int result;
  array[N] int period;
}

parameters {
  vector[T] beta_raw;
  real mu_beta;
  real<lower=0> sigma_beta;
  real alpha_pre;
  real alpha_during;
  real alpha_post;
  real log_nu;
}

transformed parameters {
  vector[T] beta = mu_beta + sigma_beta * beta_raw;
  real nu = exp(log_nu);
  vector[3] alpha;
  alpha[1] = alpha_pre;
  alpha[2] = alpha_during;
  alpha[3] = alpha_post;
}

model {
  beta_raw     ~ normal(0, 1);
  mu_beta      ~ normal(0, 1);
  sigma_beta   ~ normal(0, 1);
  alpha_pre    ~ normal(0.4, 0.3);
  alpha_during ~ normal(0.0, 0.3);
  alpha_post   ~ normal(0.3, 0.3);
  log_nu       ~ normal(0, 1);

  for (n in 1:N) {
    real bi   = beta[home[n]] + alpha[period[n]];
    real bj   = beta[away[n]];
    real draw_term = log_nu + 0.5 * (bi + bj);

    real log_denom = log_sum_exp(
      log_sum_exp(bi, draw_term), bj
    );

    if (result[n] == 2)
      target += bi - log_denom;
    else if (result[n] == 1)
      target += draw_term - log_denom;
    else
      target += bj - log_denom;
  }
}

generated quantities {
  real delta_crowd    = alpha_during - alpha_pre;
  real delta_recovery = alpha_post - alpha_during;
  real delta_gap      = alpha_post - alpha_pre;

  array[N] int y_rep;
  for (n in 1:N) {
    real bi        = beta[home[n]] + alpha[period[n]];
    real bj        = beta[away[n]];
    real draw_term = log_nu + 0.5 * (bi + bj);
    real denom     = exp(bi) + exp(draw_term) + exp(bj);

    vector[3] probs;
    probs[1] = exp(bj) / denom;
    probs[2] = exp(draw_term) / denom;
    probs[3] = exp(bi) / denom;

    y_rep[n] = categorical_rng(probs) - 1;
  }
}
