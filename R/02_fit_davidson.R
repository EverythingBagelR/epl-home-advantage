# Primary model: Bayesian Bradley-Terry-Davidson -------------------------

if (!exists("repo_path", mode = "function")) {
  source(file.path("R", "00_setup.R"))
}

suppressPackageStartupMessages({
  library(cmdstanr)
  library(readr)
})

data_path <- repo_path("data", "processed", "pl_final.csv")
if (!file.exists(data_path)) {
  stop(
    "Processed data not found. Run R/01_data_prep.R first.",
    call. = FALSE
  )
}

cmdstan_version <- tryCatch(
  cmdstanr::cmdstan_version(error_on_NA = FALSE),
  error = function(error) NULL
)
if (is.null(cmdstan_version) || anyNA(cmdstan_version)) {
  stop(
    "CmdStan is not installed. Run cmdstanr::install_cmdstan() once, then rerun.",
    call. = FALSE
  )
}

pl_data <- readr::read_csv(data_path, show_col_types = FALSE)

stan_data <- list(
  N = nrow(pl_data),
  T = length(unique(c(pl_data$HomeTeam, pl_data$AwayTeam))),
  home = as.integer(pl_data$home_id),
  away = as.integer(pl_data$away_id),
  result = as.integer(pl_data$result3),
  period = as.integer(pl_data$period_id)
)

if (anyNA(unlist(stan_data))) {
  stop("Stan input contains missing values.", call. = FALSE)
}

if (!all(stan_data$result %in% 0:2) || !all(stan_data$period %in% 1:3)) {
  stop("Stan result or period indices are outside their expected ranges.", call. = FALSE)
}

# This is the primary causal model. It retains draws as a three-outcome process,
# unlike the binary robustness model in R/03_baseline.R.
davidson_model <- cmdstanr::cmdstan_model(
  repo_path("stan", "davidson_bt.stan")
)

fit_davidson <- davidson_model$sample(
  data = stan_data,
  iter_warmup = 1000,
  iter_sampling = 1000,
  chains = 4,
  seed = 42,
  parallel_chains = 4,
  refresh = 100
)

fit_path <- repo_path("outputs", "fit_davidson.rds")
fit_davidson$save_object(file = fit_path)

fit_davidson$summary(
  variables = c(
    "alpha_pre", "alpha_during", "alpha_post",
    "delta_crowd", "delta_recovery", "delta_gap",
    "log_nu", "sigma_beta"
  )
) |>
  readr::write_csv(repo_path("outputs", "davidson_parameter_summary.csv"))

message("Saved primary Davidson fit to outputs/fit_davidson.rds")
