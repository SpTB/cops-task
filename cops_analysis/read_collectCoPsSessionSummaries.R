#!/usr/bin/env Rscript

stat_levels <- c("mean", "sd", "se")

get_script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0L) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[[1L]]))))
  }

  frames <- sys.frames()
  for (i in rev(seq_along(frames))) {
    if (!is.null(frames[[i]]$ofile)) {
      return(dirname(normalizePath(frames[[i]]$ofile)))
    }
  }

  normalizePath(getwd())
}

shell_quote_single <- function(x) {
  paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
}

normalize_for_matlab <- function(path, must_work = TRUE) {
  normalizePath(path, winslash = "/", mustWork = must_work)
}

read_collectCoPsSessionSummaries <- function(mat_path, matlab = "matlab") {
  mat_path <- normalize_for_matlab(mat_path, must_work = TRUE)
  helper_dir <- get_script_dir()
  helper_path <- file.path(helper_dir, "exportCollectCoPsSessionSummariesForR.m")
  helper_path <- normalize_for_matlab(helper_path, must_work = TRUE)

  tmp_dir <- tempfile("collectCoPsSessionSummaries_")
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  tmp_dir <- normalize_for_matlab(tmp_dir, must_work = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE, force = TRUE), add = TRUE)

  matlab_cmd <- sprintf(
    "addpath(%s); exportCollectCoPsSessionSummariesForR(%s, %s); exit",
    shell_quote_single(dirname(helper_path)),
    shell_quote_single(mat_path),
    shell_quote_single(tmp_dir)
  )

  result <- system2(
    matlab,
    args = c("-batch", matlab_cmd),
    stdout = TRUE,
    stderr = TRUE
  )
  status <- attr(result, "status")
  if (!is.null(status) && status != 0L) {
    stop(
      paste(
        "MATLAB export failed.",
        paste(result, collapse = "\n")
      ),
      call. = FALSE
    )
  }

  trial_path <- file.path(tmp_dir, "trialAgg.csv")
  pool_path <- file.path(tmp_dir, "poolSum.csv")
  if (!file.exists(trial_path) || !file.exists(pool_path)) {
    stop(
      paste(
        "MATLAB export did not produce the expected CSV files.",
        "MATLAB output:",
        paste(result, collapse = "\n")
      ),
      call. = FALSE
    )
  }

  trialAgg <- utils::read.csv(trial_path, stringsAsFactors = FALSE, check.names = FALSE)
  poolSum <- utils::read.csv(pool_path, stringsAsFactors = FALSE, check.names = FALSE)

  if ("stat" %in% names(trialAgg)) {
    trialAgg$stat <- factor(trialAgg$stat, levels = stat_levels)
  }
  if ("stat" %in% names(poolSum)) {
    poolSum$stat <- factor(poolSum$stat, levels = stat_levels)
  }

  list(trialAgg = trialAgg, poolSum = poolSum)
}

args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 0L) {
  imported <- read_collectCoPsSessionSummaries(args[[1L]])
  trialAgg <- imported$trialAgg
  poolSum <- imported$poolSum
}
