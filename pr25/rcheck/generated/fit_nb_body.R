da_g <- factor(da_group, levels = da_levels)
da_term <- paste0("da_g", da_levels[2])
da_n <- ncol(da_counts)
da_result <- data.frame(status = rep("ok", da_n), note = rep("", da_n),
                        estimate = rep(NA_real_, da_n), se = rep(NA_real_, da_n),
                        statistic = rep(NA_real_, da_n), pvalue = rep(NA_real_, da_n),
                        theta = rep(NA_real_, da_n), stringsAsFactors = FALSE)
for (da_j in seq_len(da_n)) {
  da_y <- da_counts[, da_j]
  if (length(unique(da_y)) < 2L) {
    da_result[da_j, "status"] <- "failed"
    da_result[da_j, "note"] <- "the counts are constant across samples: there is nothing to estimate"
    next
  }
  da_warns <- character(0)
  da_fit <- tryCatch(
    withCallingHandlers(
      MASS::glm.nb(da_y ~ da_g + offset(da_offset), control = glm.control(maxit = 100)),
      warning = function(w) {
        da_warns <<- c(da_warns, conditionMessage(w))
        invokeRestart("muffleWarning")
      }),
    error = function(e) e)
  if (inherits(da_fit, "error")) {
    da_result[da_j, "status"] <- "failed"
    da_result[da_j, "note"] <- paste("glm.nb stopped with an error:", conditionMessage(da_fit))
    next
  }
  da_warns <- unique(da_warns)
  if (!isTRUE(da_fit[["converged"]]) || !is.null(da_fit[["th.warn"]]) ||
      any(grepl("iteration limit|alternation limit|did not converge|NaNs produced", da_warns))) {
    da_result[da_j, "status"] <- "failed"
    da_result[da_j, "note"] <- paste("the fit did not converge:",
                                     paste(c(da_fit[["th.warn"]], da_warns), collapse = "; "))
    next
  }
  da_co <- summary(da_fit)[["coefficients"]]
  if (!(da_term %in% rownames(da_co))) {
    da_result[da_j, "status"] <- "failed"
    da_result[da_j, "note"] <- "the group coefficient is not estimable (aliased)"
    next
  }
  da_row <- da_co[da_term, ]
  if (!all(is.finite(da_row)) || da_row[[4]] < 0 || da_row[[4]] > 1) {
    da_result[da_j, "status"] <- "failed"
    da_result[da_j, "note"] <- "the fit returned a non-finite estimate, standard error or p-value"
    next
  }
  da_theta <- da_fit[["theta"]]
  da_result[da_j, c("estimate", "se", "statistic", "pvalue")] <- unname(da_row[1:4])
  da_result[da_j, "theta"] <- da_theta
  if (!is.finite(da_theta) || da_theta >= da_theta_upper) {
    da_result[da_j, "status"] <- "boundary"
    da_result[da_j, "note"] <- "the dispersion parameter theta reached its upper bound: these counts show no overdispersion, so the fit is effectively Poisson"
  } else if (da_theta <= da_theta_lower) {
    da_result[da_j, "status"] <- "boundary"
    da_result[da_j, "note"] <- "the dispersion parameter theta reached its lower bound: the variance is extreme relative to the mean"
  } else if (length(da_warns) > 0L) {
    da_result[da_j, "note"] <- paste("R warned:", paste(da_warns, collapse = "; "))
  }
}
