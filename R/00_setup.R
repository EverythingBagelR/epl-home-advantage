# Project setup -----------------------------------------------------------

required_packages <- c(
  "tidyverse",
  "cmdstanr",
  "posterior",
  "bayesplot",
  "rstanarm",
  "lubridate",
  "here"
)

install_missing_packages <- function(packages) {
  missing_packages <- packages[
    !vapply(packages, requireNamespace, logical(1), quietly = TRUE)
  ]

  if (length(missing_packages) == 0L) {
    return(invisible(NULL))
  }

  message("Installing missing R packages: ", paste(missing_packages, collapse = ", "))
  options(repos = c(
    stan = "https://stan-dev.r-universe.dev",
    CRAN = "https://cloud.r-project.org"
  ))
  install.packages(missing_packages)
}

install_missing_packages(required_packages)

still_missing <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(still_missing) > 0L) {
  stop(
    "These packages could not be loaded: ",
    paste(still_missing, collapse = ", "),
    ". Install them and rerun the script.",
    call. = FALSE
  )
}

# here::here() anchors paths at the repository root instead of a machine-specific
# working directory. The .here file in the repository provides the anchor.
repo_path <- function(...) here::here(...)

dir.create(repo_path("data", "raw"), recursive = TRUE, showWarnings = FALSE)
dir.create(repo_path("data", "processed"), recursive = TRUE, showWarnings = FALSE)
dir.create(repo_path("figures"), recursive = TRUE, showWarnings = FALSE)
dir.create(repo_path("outputs"), recursive = TRUE, showWarnings = FALSE)

cmdstan_version <- tryCatch(
  cmdstanr::cmdstan_version(error_on_NA = FALSE),
  error = function(error) NULL
)
if (is.null(cmdstan_version) || anyNA(cmdstan_version)) {
  message(
    "CmdStan is not installed. Run cmdstanr::install_cmdstan() once before ",
    "fitting the Davidson model."
  )
} else {
  message("CmdStan version: ", cmdstan_version)
}

print(sessionInfo())
