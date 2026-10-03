da_zr_out <- as.matrix(zCompositions::cmultRepl(
  as.data.frame(da_zr_x), label = 0, method = "CZM", output = "prop",
  frac = da_zr_delta, threshold = da_zr_threshold, adjust = TRUE,
  z.warning = 1, z.delete = FALSE, suppress.print = TRUE))
