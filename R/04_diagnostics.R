# Diagnostics for the primary Davidson model -----------------------------

if (!exists("repo_path", mode = "function")) {
  source(file.path("R", "00_setup.R"))
}

suppressPackageStartupMessages({
  library(tidyverse)
  library(posterior)
  library(bayesplot)
})

fit_path <- repo_path("outputs", "fit_davidson.rds")
data_path <- repo_path("data", "processed", "pl_final.csv")

if (!file.exists(fit_path)) {
  stop("Primary model fit not found. Run R/02_fit_davidson.R first.", call. = FALSE)
}
if (!file.exists(data_path)) {
  stop("Processed data not found. Run R/01_data_prep.R first.", call. = FALSE)
}

fit_davidson <- readRDS(fit_path)
pl_data <- readr::read_csv(data_path, show_col_types = FALSE)

key_parameters <- c(
  "alpha_pre", "alpha_during", "alpha_post",
  "delta_crowd", "delta_recovery", "delta_gap",
  "log_nu", "sigma_beta"
)

diagnostic_summary <- fit_davidson$summary(
  variables = key_parameters
) |>
  as.data.frame() |>
  dplyr::select(
    variable,
    rhat,
    ess_bulk,
    ess_tail
  )

readr::write_csv(
  diagnostic_summary,
  repo_path("outputs", "diagnostics_summary.csv")
)

diagnostic_plot_data <- diagnostic_summary |>
  tidyr::pivot_longer(
    cols = c(rhat, ess_bulk, ess_tail),
    names_to = "metric",
    values_to = "value"
  ) |>
  dplyr::mutate(
    metric = dplyr::recode(
      metric,
      rhat = "R-hat",
      ess_bulk = "Bulk ESS",
      ess_tail = "Tail ESS"
    )
  )

rhat_ess_plot <- ggplot(diagnostic_plot_data, aes(x = value, y = variable)) +
  geom_point(color = "#2563EB", size = 2.4) +
  facet_wrap(~metric, scales = "free_x", ncol = 1) +
  labs(
    title = "Davidson model convergence diagnostics",
    x = NULL,
    y = NULL
  ) +
  theme_minimal(base_size = 11)

ggsave(
  repo_path("figures", "rhat_ess.png"),
  rhat_ess_plot,
  width = 8,
  height = 8,
  dpi = 320,
  bg = "white"
)

trace_draws_raw <- fit_davidson$draws(
  variables = c(
    "alpha_pre",
    "alpha_during",
    "alpha_post",
    "log_nu"
  ),
  format = "draws_array"
)

trace_draws <- array(
  as.numeric(trace_draws_raw),
  dim = dim(trace_draws_raw),
  dimnames = dimnames(trace_draws_raw)
)

trace_plot <- bayesplot::mcmc_trace(trace_draws) +
  labs(
    title = "MCMC trace plots — Davidson BT model",
    subtitle = "Well-mixed chains should form stationary, overlapping bands"
  )

ggsave(
  repo_path("figures", "trace_plot.png"),
  trace_plot,
  width = 10,
  height = 7,
  dpi = 320,
  bg = "white"
)

# Posterior predictive check: compare observed period-level result rates with
# replicated rates from y_rep in the Stan generated-quantities block.
y_rep_raw <- fit_davidson$draws(
  variables = "y_rep",
  format = "matrix"
)

y_rep <- matrix(
  as.numeric(y_rep_raw),
  nrow = nrow(y_rep_raw),
  ncol = ncol(y_rep_raw),
  dimnames = dimnames(y_rep_raw)
)
y_rep_columns <- paste0("y_rep[", seq_len(nrow(pl_data)), "]")
if (!all(y_rep_columns %in% colnames(y_rep))) {
  stop("Posterior draws do not contain a complete y_rep vector.", call. = FALSE)
}
y_rep <- y_rep[, y_rep_columns, drop = FALSE]
set.seed(42)
kept_draws <- sample(seq_len(nrow(y_rep)), min(500L, nrow(y_rep)))
y_rep <- y_rep[kept_draws, , drop = FALSE]

period_levels <- c("pre", "during", "post")
outcome_codes <- c("Home win" = 2L, "Draw" = 1L, "Away win" = 0L)

replicated_rates <- purrr::map_dfr(period_levels, function(period_name) {
  match_indices <- which(pl_data$period == period_name)
  period_replications <- y_rep[, match_indices, drop = FALSE]

  purrr::imap_dfr(outcome_codes, function(outcome_code, outcome_name) {
    tibble(
      period = period_name,
      outcome = outcome_name,
      rate = rowMeans(period_replications == outcome_code)
    )
  })
})

replicated_intervals <- replicated_rates |>
  dplyr::group_by(period, outcome) |>
  dplyr::summarise(
    median = median(rate),
    lo95 = quantile(rate, 0.025),
    hi95 = quantile(rate, 0.975),
    .groups = "drop"
  )

observed_rates <- pl_data |>
  dplyr::mutate(
    outcome = dplyr::case_when(
      result3 == 2L ~ "Home win",
      result3 == 1L ~ "Draw",
      result3 == 0L ~ "Away win"
    )
  ) |>
  dplyr::count(period, outcome, name = "matches") |>
  dplyr::group_by(period) |>
  dplyr::mutate(observed = matches / sum(matches)) |>
  dplyr::ungroup()

pp_check_plot <- replicated_intervals |>
  dplyr::mutate(period = factor(period, levels = period_levels)) |>
  ggplot(aes(x = period, y = median, color = outcome)) +
  geom_pointrange(aes(ymin = lo95, ymax = hi95), position = position_dodge(0.5)) +
  geom_point(
    data = observed_rates |>
      dplyr::mutate(period = factor(period, levels = period_levels)),
    aes(y = observed, shape = outcome),
    position = position_dodge(0.5),
    color = "black",
    size = 2.2
  ) +
  scale_y_continuous(labels = scales::label_percent(accuracy = 1)) +
  labs(
    title = "Posterior predictive check by period",
    subtitle = "Intervals: replicated 95% ranges; black points: observed rates",
    x = NULL,
    y = "Outcome rate",
    color = "Replicated outcome",
    shape = "Observed outcome"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(
  repo_path("figures", "posterior_predictive_check.png"),
  pp_check_plot,
  width = 10,
  height = 6,
  dpi = 320,
  bg = "white"
)

print(diagnostic_summary)
message("Saved R-hat/ESS, trace, and posterior predictive diagnostics.")
