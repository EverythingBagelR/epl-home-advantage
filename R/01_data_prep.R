# Build the analysis-ready Premier League dataset ------------------------

if (!exists("repo_path", mode = "function")) {
  source(file.path("R", "00_setup.R"))
}

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
})

season_files <- tibble::tribble(
  ~file_name,         ~season,
  "season-1718.csv", "2017/18",
  "season-1819.csv", "2018/19",
  "season-1920.csv", "2019/20",
  "season-2021.csv", "2020/21",
  "season-2122.csv", "2021/22"
)

required_columns <- c("Date", "HomeTeam", "AwayTeam", "FTHG", "FTAG", "FTR")

clean_season <- function(file_name, season_label) {
  file_path <- repo_path("data", "raw", file_name)

  if (!file.exists(file_path)) {
    stop(
      "Missing raw data file: ", file_path,
      ". See data/README.md for download and naming instructions.",
      call. = FALSE
    )
  }

  raw_data <- readr::read_csv(file_path, show_col_types = FALSE)
  missing_columns <- setdiff(required_columns, names(raw_data))

  if (length(missing_columns) > 0L) {
    stop(
      file_name, " is missing required columns: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  cleaned_data <- raw_data |>
    dplyr::select(dplyr::all_of(required_columns)) |>
    dplyr::mutate(
      season = season_label,
      Date = as.Date(lubridate::parse_date_time(
        Date,
        orders = c("dmy", "ymd"),
        tz = "UTC",
        quiet = TRUE
      )),
      HomeTeam = stringr::str_squish(HomeTeam),
      AwayTeam = stringr::str_squish(AwayTeam),
      FTHG = as.integer(FTHG),
      FTAG = as.integer(FTAG),
      FTR = stringr::str_to_upper(stringr::str_squish(FTR))
    )

  if (anyNA(cleaned_data$Date)) {
    bad_dates <- unique(raw_data$Date[is.na(cleaned_data$Date)])
    stop(
      "Could not parse date values in ", file_name, ": ",
      paste(utils::head(bad_dates, 5L), collapse = ", "),
      call. = FALSE
    )
  }

  invalid_results <- setdiff(unique(cleaned_data$FTR), c("H", "D", "A"))
  if (length(invalid_results) > 0L) {
    stop(
      "Unexpected FTR values in ", file_name, ": ",
      paste(invalid_results, collapse = ", "),
      call. = FALSE
    )
  }

  cleaned_data
}

pl_data <- purrr::map2_dfr(
  season_files$file_name,
  season_files$season,
  clean_season
)

if (nrow(pl_data) != 1900L) {
  warning(
    "Expected 1,900 matches across five complete seasons but found ",
    nrow(pl_data), ". Check the raw files before interpreting results.",
    call. = FALSE
  )
}

# These cutoffs reproduce the original analysis. Matches in the summer gap
# between 2021-05-24 and 2021-08-12 are intentionally outside all periods.
pl_data <- pl_data |>
  dplyr::mutate(
    period = dplyr::case_when(
      Date < as.Date("2020-03-09") ~ "pre",
      Date >= as.Date("2020-03-09") & Date <= as.Date("2021-05-23") ~ "during",
      Date >= as.Date("2021-08-13") ~ "post",
      TRUE ~ NA_character_
    )
  ) |>
  dplyr::filter(!is.na(period)) |>
  dplyr::mutate(
    period = factor(period, levels = c("pre", "during", "post")),
    period_id = as.integer(period),
    crowd = ifelse(period == "during", 0L, 1L),
    home_win = ifelse(FTR == "H", 1L, 0L),
    draw = ifelse(FTR == "D", 1L, 0L),
    away_win = ifelse(FTR == "A", 1L, 0L),
    result3 = dplyr::case_when(
      FTR == "H" ~ 2L,
      FTR == "D" ~ 1L,
      FTR == "A" ~ 0L
    )
  )

# Deterministic indices connect club names to the Stan team-strength vector.
teams <- sort(unique(c(pl_data$HomeTeam, pl_data$AwayTeam)))
team_index <- stats::setNames(seq_along(teams), teams)

pl_data <- pl_data |>
  dplyr::mutate(
    home_id = unname(team_index[HomeTeam]),
    away_id = unname(team_index[AwayTeam]),
    period_f = stats::relevel(period, ref = "during")
  )

if (anyNA(pl_data)) {
  stop("The processed dataset contains missing values.", call. = FALSE)
}

readr::write_csv(pl_data, repo_path("data", "processed", "pl_final.csv"))

data_summary <- pl_data |>
  dplyr::group_by(period) |>
  dplyr::summarise(
    matches = dplyr::n(),
    home_win_rate = mean(home_win),
    draw_rate = mean(draw),
    away_win_rate = mean(away_win),
    .groups = "drop"
  )

print(data_summary)
message("Saved analysis-ready data to data/processed/pl_final.csv")
