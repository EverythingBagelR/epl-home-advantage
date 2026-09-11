# Data

The raw match results come from the [English Premier League dataset on Datahub](https://datahub.io/football/english-premier-league), which republishes season-level Football-Data files.

## Required seasons

Download the five season CSV files and place them in `data/raw/` using these exact names:

| File | Season |
|---|---|
| `season-1718.csv` | 2017/18 |
| `season-1819.csv` | 2018/19 |
| `season-1920.csv` | 2019/20 |
| `season-2021.csv` | 2020/21 |
| `season-2122.csv` | 2021/22 |

Each file must contain the following columns:

- `Date`: match date; both `dd/mm/yyyy` and ISO `yyyy-mm-dd` are accepted
- `HomeTeam`: home club
- `AwayTeam`: away club
- `FTHG`: full-time home goals
- `FTAG`: full-time away goals
- `FTR`: full-time result (`H`, `D`, or `A`)

The pipeline keeps only these six source fields, adds the season and analysis variables, and writes `data/processed/pl_final.csv`. The supplementary ghost-game analysis also writes `data/processed/ghost_dynamic.csv`, including the fixed early/later phase and standardized ghost-game progress variables. Both raw and processed data are excluded from version control so that the provenance and transformation remain explicit.
