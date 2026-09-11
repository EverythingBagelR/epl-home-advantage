# Robustness benchmark: binary mixed-effects logistic model --------------

if (!exists("repo_path", mode = "function")) {
  source(file.path("R", "00_setup.R"))
}

suppressPackageStartupMessages({
  library(rstanarm)
  library(readr)
  library(dplyr)
})

data_path <- repo_path("data", "processed", "pl_final.csv")
if (!file.exists(data_path)) {
  stop(
    "Processed data not found. Run R/01_data_prep.R first.",
    call. = FALSE
  )
}

pl_data <- readr::read_csv(data_path, show_col_types = FALSE) |>
  dplyr::mutate(
    period_f = stats::relevel(
      factor(period, levels = c("pre", "during", "post")),
      ref = "during"
    )
  )

# This model is a robustness comparison, not the main analysis: collapsing
# draws and away wins into one category discards Davidson's explicit draw model.
fit_baseline <- rstanarm::stan_glmer(
  home_win ~ period_f + (1 | HomeTeam) + (1 | AwayTeam),
  family = stats::binomial(link = "logit"),
  data = pl_data,
  prior = rstanarm::normal(0, 1),
  chains = 4,
  iter = 2000,
  seed = 42,
  refresh = 100
)

saveRDS(fit_baseline, repo_path("outputs", "fit_baseline.rds"))

fixed_effect_names <- c(
  "(Intercept)",
  "period_fpre",
  "period_fpost"
)

baseline_summary <- summary(
  fit_baseline,
  pars = fixed_effect_names,
  probs = c(0.025, 0.5, 0.975)
) |>
  as.data.frame() |>
  tibble::rownames_to_column("parameter")

readr::write_csv(
  baseline_summary,
  repo_path("outputs", "baseline_parameter_summary.csv")
)

message("Saved robustness-model fit to outputs/fit_baseline.rds")
