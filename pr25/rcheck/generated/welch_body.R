da_g <- factor(da_group, levels = da_levels)
da_a <- da_g == da_levels[1]
da_b <- da_g == da_levels[2]
da_n <- ncol(da_values)
da_result <- data.frame(status = rep("ok", da_n), note = rep("", da_n),
                        estimate = rep(NA_real_, da_n), se = rep(NA_real_, da_n),
                        statistic = rep(NA_real_, da_n), pvalue = rep(NA_real_, da_n),
                        df = rep(NA_real_, da_n), stringsAsFactors = FALSE)
for (da_j in seq_len(da_n)) {
  da_y <- da_values[, da_j]
  if (length(unique(da_y)) < 2L) {
    da_result[da_j, "status"] <- "failed"
    da_result[da_j, "note"] <- "the values are constant across samples: there is nothing to estimate"
    next
  }
  if (length(unique(da_y[da_a])) < 2L && length(unique(da_y[da_b])) < 2L) {
    da_result[da_j, "status"] <- "failed"
    da_result[da_j, "note"] <- "each group has one distinct value, so no variance can be estimated"
    next
  }
  da_warns <- character(0)
  da_fit <- tryCatch(
    withCallingHandlers(
      stats::t.test(x = da_y[da_b], y = da_y[da_a], var.equal = FALSE),
      warning = function(w) {
        da_warns <<- c(da_warns, conditionMessage(w))
        invokeRestart("muffleWarning")
      }),
    error = function(e) e)
  if (inherits(da_fit, "error")) {
    da_result[da_j, "status"] <- "failed"
    da_result[da_j, "note"] <- paste("t.test stopped with an error:", conditionMessage(da_fit))
    next
  }
  da_est <- unname(da_fit$estimate[1] - da_fit$estimate[2])
  da_stat <- unname(da_fit$statistic)
  da_df <- unname(da_fit$parameter)
  da_p <- da_fit$p.value
  # t.test gives the confidence interval, not the standard error, but Welch's is
  # one line of arithmetic and the statistic has to be estimate over it.
  da_se <- sqrt(stats::var(da_y[da_b]) / sum(da_b) + stats::var(da_y[da_a]) / sum(da_a))
  if (!all(is.finite(c(da_est, da_se, da_stat, da_df, da_p))) || da_se <= 0 || da_p < 0 || da_p > 1) {
    da_result[da_j, "status"] <- "failed"
    da_result[da_j, "note"] <- paste(c("the test returned a non-finite statistic or a zero standard error, so there is nothing to report",
                                       unique(da_warns)), collapse = "; ")
    next
  }
  da_result[da_j, c("estimate", "se", "statistic", "pvalue", "df")] <-
    c(da_est, da_se, da_stat, da_p, da_df)
  if (length(da_warns) > 0L) {
    da_result[da_j, "note"] <- paste("R warned:", paste(unique(da_warns), collapse = "; "))
  }
}
