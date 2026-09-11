# Supplementary analysis: dynamics within the ghost-game period ---------

if (!exists("repo_path", mode = "function")) {
  source(file.path("R", "00_setup.R"))
}

suppressPackageStartupMessages({
  library(tidyverse)
  library(cmdstanr)
  library(posterior)
  library(bayesplot)
})

data_path <- repo_path("data", "processed", "pl_final.csv")
if (!file.exists(data_path)) {
  stop("Processed data not found. Run R/01_data_prep.R first.", call. = FALSE)
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

pl_data <- readr::read_csv(data_path, show_col_types = FALSE) |>
  dplyr::mutate(Date = as.Date(Date))

# The split is fixed from the competition calendar, not selected after seeing
# the outcomes. Early ghost games are the 2019/20 restart; later ghost games
# are the 2020/21 season, which contains the majority of restricted-attendance
# matches. March 2020 matches before the shutdown are excluded from this
# supplementary model, while the original three-period model remains unchanged.
dynamic_data <- pl_data |>
  dplyr::mutate(
    ghost_phase = dplyr::case_when(
      Date < as.Date("2020-03-09") ~ "pre",
      Date >= as.Date("2020-06-17") & Date <= as.Date("2020-07-26") ~
        "early_ghost",
      season == "2020/21" &
        Date >= as.Date("2020-09-12") & Date <= as.Date("2021-05-23") ~
        "later_ghost",
      Date >= as.Date("2021-08-13") ~ "post",
      TRUE ~ NA_character_
    )
  ) |>
  dplyr::filter(!is.na(ghost_phase)) |>
  dplyr::mutate(
    ghost_phase = factor(
      ghost_phase,
      levels = c("pre", "early_ghost", "later_ghost", "post")
    ),
    ghost_phase_id = as.integer(ghost_phase)
  ) |>
  dplyr::arrange(Date, home_id, away_id)

phase_counts <- dynamic_data |>
  dplyr::count(ghost_phase, name = "matches")

expected_ghost_counts <- c(early_ghost = 92L, later_ghost = 380L)
observed_ghost_counts <- stats::setNames(
  phase_counts$matches,
  as.character(phase_counts$ghost_phase)
)[names(expected_ghost_counts)]

if (anyNA(observed_ghost_counts) ||
    !all(observed_ghost_counts == expected_ghost_counts)) {
  warning(
    "Expected 92 early and 380 later ghost games, but found ",
    paste(observed_ghost_counts, collapse = " and "),
    ". Check the raw season files before interpreting the extension.",
    call. = FALSE
  )
}

# Progress runs from 0 to 1 over chronologically ordered ghost matches. Matches
# on the same date receive the same average rank, so arbitrary within-day order
# cannot affect the estimated trend.
ghost_rows <- dynamic_data$ghost_phase %in% c("early_ghost", "later_ghost")
ghost_rank <- rank(
  as.numeric(dynamic_data$Date[ghost_rows]),
  ties.method = "average"
)
ghost_progress <- (ghost_rank - min(ghost_rank)) /
  (max(ghost_rank) - min(ghost_rank))

dynamic_data$ghost_progress <- 0
dynamic_data$ghost_progress[ghost_rows] <- ghost_progress

readr::write_csv(
  dynamic_data,
  repo_path("data", "processed", "ghost_dynamic.csv")
)

shared_stan_data <- list(
  N = nrow(dynamic_data),
  T = max(c(dynamic_data$home_id, dynamic_data$away_id)),
  home = as.integer(dynamic_data$home_id),
  away = as.integer(dynamic_data$away_id),
  result = as.integer(dynamic_data$result3)
)

split_stan_data <- c(
  shared_stan_data,
  list(phase = as.integer(dynamic_data$ghost_phase_id))
)

trend_phase <- dplyr::case_when(
  dynamic_data$ghost_phase == "pre" ~ 1L,
  ghost_rows ~ 2L,
  dynamic_data$ghost_phase == "post" ~ 3L
)

trend_stan_data <- c(
  shared_stan_data,
  list(
    phase = as.integer(trend_phase),
    ghost_progress = as.numeric(dynamic_data$ghost_progress)
  )
)

if (anyNA(unlist(split_stan_data)) || anyNA(unlist(trend_stan_data))) {
  stop("A ghost-dynamics Stan input contains missing values.", call. = FALSE)
}

# Main extension: compare the early restart with the later ghost-game season.
ghost_split_model <- cmdstanr::cmdstan_model(
  repo_path("stan", "davidson_bt_ghost_split.stan")
)

fit_ghost_split <- ghost_split_model$sample(
  data = split_stan_data,
  iter_warmup = 1000,
  iter_sampling = 1000,
  chains = 4,
  seed = 43,
  parallel_chains = 4,
  refresh = 100
)

fit_ghost_split$save_object(
  file = repo_path("outputs", "fit_ghost_split.rds")
)

# Robustness extension: replace the cutoff with a linear trend over ghost-game
# progress. gamma_ghost is the change from the beginning to the end of the
# standardized 0-to-1 ghost period.
ghost_trend_model <- cmdstanr::cmdstan_model(
  repo_path("stan", "davidson_bt_ghost_trend.stan")
)

fit_ghost_trend <- ghost_trend_model$sample(
  data = trend_stan_data,
  iter_warmup = 1000,
  iter_sampling = 1000,
  chains = 4,
  seed = 44,
  parallel_chains = 4,
  refresh = 100
)

fit_ghost_trend$save_object(
  file = repo_path("outputs", "fit_ghost_trend.rds")
)

split_variables <- c(
  "alpha_pre", "alpha_early_ghost", "alpha_later_ghost", "alpha_post",
  "delta_initial_shock", "delta_adaptation", "delta_late_shock",
  "delta_post_gap", "log_nu", "sigma_beta"
)
trend_variables <- c(
  "alpha_pre", "alpha_ghost_start", "alpha_ghost_end", "alpha_post",
  "gamma_ghost", "delta_ghost_trend", "log_nu", "sigma_beta"
)

split_summary <- fit_ghost_split$summary(variables = split_variables)
trend_summary <- fit_ghost_trend$summary(variables = trend_variables)

readr::write_csv(
  split_summary,
  repo_path("outputs", "ghost_split_parameter_summary.csv")
)
readr::write_csv(
  trend_summary,
  repo_path("outputs", "ghost_trend_parameter_summary.csv")
)

split_draws <- fit_ghost_split$draws(
  variables = split_variables,
  format = "df"
) |>
  tibble::as_tibble()
trend_draws <- fit_ghost_trend$draws(
  variables = trend_variables,
  format = "df"
) |>
  tibble::as_tibble()

ghost_key_results <- tibble::tibble(
  quantity = c(
    "P(delta_adaptation < 0)",
    "median_delta_adaptation",
    "delta_adaptation_lo95",
    "delta_adaptation_hi95",
    "P(gamma_ghost < 0)",
    "median_gamma_ghost",
    "gamma_ghost_lo95",
    "gamma_ghost_hi95"
  ),
  value = c(
    mean(split_draws$delta_adaptation < 0),
    median(split_draws$delta_adaptation),
    quantile(split_draws$delta_adaptation, 0.025),
    quantile(split_draws$delta_adaptation, 0.975),
    mean(trend_draws$gamma_ghost < 0),
    median(trend_draws$gamma_ghost),
    quantile(trend_draws$gamma_ghost, 0.025),
    quantile(trend_draws$gamma_ghost, 0.975)
  )
)

readr::write_csv(
  ghost_key_results,
  repo_path("outputs", "ghost_dynamics_key_results.csv")
)

phase_summary <- split_draws |>
  dplyr::select(
    alpha_pre, alpha_early_ghost, alpha_later_ghost, alpha_post
  ) |>
  tidyr::pivot_longer(
    cols = dplyr::everything(),
    names_to = "parameter",
    values_to = "alpha"
  ) |>
  dplyr::group_by(parameter) |>
  dplyr::summarise(
    median = median(alpha),
    lo95 = quantile(alpha, 0.025),
    hi95 = quantile(alpha, 0.975),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    phase = dplyr::recode(
      parameter,
      alpha_pre = "Pre-COVID",
      alpha_early_ghost = "Early ghost\n2019/20 restart",
      alpha_later_ghost = "Later ghost\n2020/21",
      alpha_post = "Post-COVID"
    ),
    phase = factor(
      phase,
      levels = c(
        "Pre-COVID", "Early ghost\n2019/20 restart",
        "Later ghost\n2020/21", "Post-COVID"
      )
    )
  ) |>
  dplyr::arrange(phase)

ghost_phase_plot <- ggplot(
  phase_summary,
  aes(x = phase, y = median, group = 1)
) +
  geom_line(color = "#7C3AED", linewidth = 1.1) +
  geom_pointrange(
    aes(ymin = lo95, ymax = hi95),
    color = "#7C3AED",
    linewidth = 0.8,
    fatten = 2.8
  ) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey55") +
  labs(
    title = "Did home advantage fade as ghost games continued?",
    subtitle = paste(
      "Posterior medians and 95% credible intervals;",
      "the early/later split is fixed by season"
    ),
    x = NULL,
    y = expression("Home-advantage parameter " * alpha * " (log-strength scale)"),
    caption = "Early: 2019/20 restart (92 matches); later: 2020/21 (380 matches)"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold"),
    axis.text.x = element_text(face = "bold")
  )

ggsave(
  repo_path("figures", "ghost_home_advantage_by_phase.png"),
  ghost_phase_plot,
  width = 10,
  height = 6,
  dpi = 320,
  bg = "white"
)

progress_grid <- seq(0, 1, length.out = 101)
trend_matrix <- outer(
  trend_draws$gamma_ghost,
  progress_grid,
  `*`
) + trend_draws$alpha_ghost_start

trend_plot_data <- tibble::tibble(
  progress = progress_grid,
  median = apply(trend_matrix, 2, median),
  lo95 = apply(trend_matrix, 2, quantile, probs = 0.025),
  hi95 = apply(trend_matrix, 2, quantile, probs = 0.975)
)

ghost_trend_plot <- ggplot(
  trend_plot_data,
  aes(x = progress, y = median)
) +
  geom_ribbon(aes(ymin = lo95, ymax = hi95), fill = "#BFDBFE", alpha = 0.7) +
  geom_line(color = "#1D4ED8", linewidth = 1.1) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey55") +
  scale_x_continuous(
    labels = scales::label_percent(accuracy = 1),
    breaks = c(0, 0.25, 0.5, 0.75, 1)
  ) +
  labs(
    title = "Continuous trend in home advantage during ghost games",
    subtitle = "Posterior median and 95% credible band from the trend robustness model",
    x = "Progress through chronologically ordered ghost games",
    y = expression("Home-advantage parameter " * alpha * " (log-strength scale)")
  ) +
  theme_minimal(base_size = 12) +
  theme(
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold")
  )

ggsave(
  repo_path("figures", "ghost_home_advantage_over_time.png"),
  ghost_trend_plot,
  width = 10,
  height = 6,
  dpi = 320,
  bg = "white"
)

ghost_split_trace <- bayesplot::mcmc_trace(
  fit_ghost_split$draws(
    variables = c("alpha_early_ghost", "alpha_later_ghost", "delta_adaptation"),
    format = "draws_array"
  )
) +
  labs(title = "Trace plots — early/later ghost-game model")

ggsave(
  repo_path("figures", "ghost_dynamics_trace.png"),
  ghost_split_trace,
  width = 10,
  height = 7,
  dpi = 320,
  bg = "white"
)

ghost_diagnostics <- dplyr::bind_rows(
  split_summary |>
    dplyr::transmute(
      model = "early_later_split", variable, rhat, ess_bulk, ess_tail
    ),
  trend_summary |>
    dplyr::transmute(
      model = "continuous_trend", variable, rhat, ess_bulk, ess_tail
    )
)

readr::write_csv(
  ghost_diagnostics,
  repo_path("outputs", "ghost_dynamics_diagnostics.csv")
)

print(phase_counts)
print(ghost_key_results)
message("Saved ghost-game dynamics fits, diagnostics, figures, and summaries.")
