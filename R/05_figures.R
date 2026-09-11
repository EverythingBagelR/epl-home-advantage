# Portfolio figures and result summaries ---------------------------------

if (!exists("repo_path", mode = "function")) {
  source(file.path("R", "00_setup.R"))
}

suppressPackageStartupMessages({
  library(tidyverse)
  library(posterior)
  library(bayesplot)
})

fit_path <- repo_path("outputs", "fit_davidson.rds")
if (!file.exists(fit_path)) {
  stop("Primary model fit not found. Run R/02_fit_davidson.R first.", call. = FALSE)
}

fit_davidson <- readRDS(fit_path)

draws <- fit_davidson$draws(
  variables = c(
    "alpha_pre", "alpha_during", "alpha_post",
    "delta_crowd", "delta_recovery", "delta_gap", "log_nu"
  ),
  format = "df"
) |>
  tibble::as_tibble()

period_summary <- draws |>
  dplyr::select(alpha_pre, alpha_during, alpha_post) |>
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
    period = dplyr::recode(
      parameter,
      alpha_pre = "Pre-COVID",
      alpha_during = "Behind closed doors",
      alpha_post = "Post-COVID"
    ),
    period = factor(
      period,
      levels = c("Pre-COVID", "Behind closed doors", "Post-COVID")
    )
  ) |>
  dplyr::arrange(period)

home_advantage_plot <- ggplot(
  period_summary,
  aes(x = period, y = median, group = 1)
) +
  geom_line(color = "#1D4ED8", linewidth = 1.1) +
  geom_pointrange(
    aes(ymin = lo95, ymax = hi95),
    color = "#1D4ED8",
    linewidth = 0.8,
    fatten = 2.8
  ) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey55") +
  labs(
    title = "Home advantage fell behind closed doors—and then partially recovered",
    subtitle = "Posterior median and 95% credible interval from the Davidson model",
    x = NULL,
    y = expression("Home-advantage parameter " * alpha * " (log-strength scale)"),
    caption = "Premier League, 2017/18–2021/22"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold"),
    axis.text.x = element_text(face = "bold")
  )

ggsave(
  repo_path("figures", "home_advantage_by_period.png"),
  home_advantage_plot,
  width = 10,
  height = 6,
  dpi = 320,
  bg = "white"
)

contrast_draws <- draws |>
  dplyr::select(delta_crowd, delta_recovery, delta_gap)

contrast_plot <- bayesplot::mcmc_areas(
  posterior::as_draws_matrix(contrast_draws),
  prob = 0.95
) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "#DC2626") +
  scale_y_discrete(labels = c(
    delta_crowd = "Crowd shock: during − pre",
    delta_recovery = "Recovery: post − during",
    delta_gap = "Long-run gap: post − pre"
  )) +
  labs(
    title = "Posterior distributions of the period contrasts",
    subtitle = "Shaded intervals contain 95% posterior probability",
    x = "Difference in home-advantage parameter",
    y = NULL
  ) +
  theme_minimal(base_size = 11)

ggsave(
  repo_path("figures", "period_contrasts.png"),
  contrast_plot,
  width = 10,
  height = 5.5,
  dpi = 320,
  bg = "white"
)

posterior_summary <- draws |>
  dplyr::select(
    alpha_pre, alpha_during, alpha_post,
    delta_crowd, delta_recovery, delta_gap
  ) |>
  tidyr::pivot_longer(dplyr::everything(), names_to = "parameter") |>
  dplyr::group_by(parameter) |>
  dplyr::summarise(
    median = median(value),
    lo95 = quantile(value, 0.025),
    hi95 = quantile(value, 0.975),
    .groups = "drop"
  )

bayesian_evidence <- tibble::tibble(
  quantity = c(
    "P(delta_crowd < 0)",
    "P(delta_recovery > 0)",
    "P(delta_gap < 0)",
    "median_nu"
  ),
  value = c(
    mean(draws$delta_crowd < 0),
    mean(draws$delta_recovery > 0),
    mean(draws$delta_gap < 0),
    median(exp(draws$log_nu))
  )
)

readr::write_csv(period_summary, repo_path("outputs", "period_summary.csv"))
readr::write_csv(posterior_summary, repo_path("outputs", "posterior_summary.csv"))
readr::write_csv(bayesian_evidence, repo_path("outputs", "key_results.csv"))

print(period_summary)
print(bayesian_evidence)
message("Saved the portfolio figures and result tables.")
