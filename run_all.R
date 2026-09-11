# One-command reproduction from the repository root ----------------------

command_args <- commandArgs(trailingOnly = FALSE)
file_argument <- grep("^--file=", command_args, value = TRUE)

if (length(file_argument) == 1L) {
  script_path <- sub("^--file=", "", file_argument)
  repository_root <- normalizePath(dirname(script_path), mustWork = TRUE)
} else {
  repository_root <- normalizePath(".", mustWork = TRUE)
}

setwd(repository_root)

scripts <- file.path(
  "R",
  c(
    "00_setup.R",
    "01_data_prep.R",
    "02_fit_davidson.R",
    "03_baseline.R",
    "04_diagnostics.R",
    "05_figures.R",
    "06_ghost_dynamics.R"
  )
)

for (script in scripts) {
  message("\nRunning ", script, " ...")
  source(script, local = globalenv(), chdir = FALSE)
}

message("\nReproduction complete. See figures/ and outputs/.")
