weighted_var <- function(data, value_col, count_col) {
  if (!is.data.frame(data)) {
    stop("data must be a data.frame", call. = FALSE)
  }

  if (!is.character(value_col) || length(value_col) != 1L) {
    stop("value_col must be a single column name string", call. = FALSE)
  }
  if (!is.character(count_col) || length(count_col) != 1L) {
    stop("count_col must be a single column name string", call. = FALSE)
  }
  if (!(value_col %in% names(data))) {
    stop(sprintf("Column '%s' not found in data", value_col), call. = FALSE)
  }
  if (!(count_col %in% names(data))) {
    stop(sprintf("Column '%s' not found in data", count_col), call. = FALSE)
  }

  out <- data
  out$.value <- as.numeric(out[[value_col]])
  out$.count <- as.numeric(out[[count_col]])
  out$.weighted_value <- out$.value * out$.count
  rownames(out) <- NULL
  out
}


bootstrap_func <- function(data, value_col, count_col, n_boot = 2000, seed = NULL) {
  weighted_data <- weighted_var(data, value_col, count_col)
  weighted_data <- weighted_data[
    is.finite(weighted_data$.value) &
      is.finite(weighted_data$.count) &
      weighted_data$.count > 0,
    ,
    drop = FALSE
  ]

  if (nrow(weighted_data) == 0L) {
    return(data.frame(
      n = 0L,
      mean = NA_real_,
      se = NA_real_
    ))
  }

  if (!is.null(seed)) {
    set.seed(seed)
  }

  weighted_mean_once <- function(df) {
    sum(df$.weighted_value, na.rm = TRUE) / sum(df$.count, na.rm = TRUE)
  }

  boot_vals <- replicate(n_boot, {
    idx <- sample.int(nrow(weighted_data), size = nrow(weighted_data), replace = TRUE)
    weighted_mean_once(weighted_data[idx, , drop = FALSE])
  })

  data.frame(
    n = nrow(weighted_data),
    mean = weighted_mean_once(weighted_data),
    se = stats::sd(boot_vals)
  )
}


bootstrap_family <- function(data, value_prefix, count_prefix = "nTrackedSamples",
                             n_boot = 2000, seed = NULL) {
  if (!is.data.frame(data)) {
    stop("data must be a data.frame", call. = FALSE)
  }
  if (!is.character(value_prefix) || length(value_prefix) != 1L) {
    stop("value_prefix must be a single string", call. = FALSE)
  }
  if (!is.character(count_prefix) || length(count_prefix) != 1L) {
    stop("count_prefix must be a single string", call. = FALSE)
  }

  value_cols <- names(data)[startsWith(names(data), value_prefix)]
  if (length(value_cols) == 0L) {
    stop(sprintf("No columns found starting with '%s'", value_prefix), call. = FALSE)
  }

  if (is.null(seed)) {
    seeds <- rep(list(NULL), length(value_cols))
  } else {
    seeds <- as.list(seed + seq_along(value_cols) - 1L)
  }

  pieces <- vector("list", length(value_cols))
  for (i in seq_along(value_cols)) {
    value_col <- value_cols[[i]]
    suffix <- sub(paste0("^", value_prefix), "", value_col)

    if (identical(suffix, "")) {
      count_col <- count_prefix
    } else {
      count_col <- paste0(count_prefix, suffix)
    }

    if (!(count_col %in% names(data))) {
      warning(sprintf("Skipping '%s': count column '%s' not found", value_col, count_col), call. = FALSE)
      next
    }

    stats_df <- bootstrap_func(
      data,
      value_col = value_col,
      count_col = count_col,
      n_boot = n_boot,
      seed = seeds[[i]]
    )
    stats_df$variable <- value_col
    stats_df$count_col <- count_col
    pieces[[i]] <- stats_df[, c("variable", "count_col", "n", "mean", "se")]
  }

  pieces <- Filter(Negate(is.null), pieces)
  if (length(pieces) == 0L) {
    return(data.frame(
      variable = character(),
      count_col = character(),
      n = integer(),
      mean = numeric(),
      se = numeric()
    ))
  }

  out <- do.call(rbind, pieces)
  rownames(out) <- NULL
  out
}


bootstrap_family_grouped <- function(data, value_prefix, group_cols,
                                     count_prefix = "nTrackedSamples",
                                     n_boot = 2000, seed = NULL) {
  if (!is.data.frame(data)) {
    stop("data must be a data.frame", call. = FALSE)
  }
  if (!is.character(group_cols) || length(group_cols) < 1L) {
    stop("group_cols must be a non-empty character vector", call. = FALSE)
  }
  missing_cols <- setdiff(group_cols, names(data))
  if (length(missing_cols) > 0L) {
    stop(sprintf(
      "Grouping columns not found in data: %s",
      paste(missing_cols, collapse = ", ")
    ), call. = FALSE)
  }

  group_df <- unique(data[group_cols])
  pieces <- vector("list", nrow(group_df))

  for (i in seq_len(nrow(group_df))) {
    mask <- rep(TRUE, nrow(data))
    for (col in group_cols) {
      mask <- mask & (data[[col]] == group_df[[col]][i])
    }
    subset_data <- data[mask, , drop = FALSE]
    stats_df <- bootstrap_family(
      subset_data,
      value_prefix = value_prefix,
      count_prefix = count_prefix,
      n_boot = n_boot,
      seed = if (is.null(seed)) NULL else seed + i - 1L
    )
    for (col in group_cols) {
      stats_df[[col]] <- group_df[[col]][i]
    }
    pieces[[i]] <- stats_df[, c(group_cols, "variable", "count_col", "n", "mean", "se")]
  }

  out <- do.call(rbind, pieces)
  rownames(out) <- NULL
  out
}


bootstrap_grouped <- function(data, value_col, count_col, group_cols,
                              n_boot = 2000, seed = NULL) {
  if (!is.data.frame(data)) {
    stop("data must be a data.frame", call. = FALSE)
  }
  if (!is.character(value_col) || length(value_col) != 1L) {
    stop("value_col must be a single string", call. = FALSE)
  }
  if (!is.character(count_col) || length(count_col) != 1L) {
    stop("count_col must be a single string", call. = FALSE)
  }
  if (!is.character(group_cols) || length(group_cols) < 1L) {
    stop("group_cols must be a non-empty character vector", call. = FALSE)
  }

  needed <- c(value_col, count_col, group_cols)
  missing_cols <- setdiff(needed, names(data))
  if (length(missing_cols) > 0L) {
    stop(sprintf(
      "Columns not found in data: %s",
      paste(missing_cols, collapse = ", ")
    ), call. = FALSE)
  }

  group_df <- unique(data[group_cols])
  pieces <- vector("list", nrow(group_df))

  for (i in seq_len(nrow(group_df))) {
    mask <- rep(TRUE, nrow(data))
    for (col in group_cols) {
      mask <- mask & (data[[col]] == group_df[[col]][i])
    }
    subset_data <- data[mask, , drop = FALSE]
    stats_df <- bootstrap_func(
      subset_data,
      value_col = value_col,
      count_col = count_col,
      n_boot = n_boot,
      seed = if (is.null(seed)) NULL else seed + i - 1L
    )
    stats_df$variable <- value_col
    stats_df$count_col <- count_col
    for (col in group_cols) {
      stats_df[[col]] <- group_df[[col]][i]
    }
    pieces[[i]] <- stats_df[, c(group_cols, "variable", "count_col", "n", "mean", "se")]
  }

  out <- do.call(rbind, pieces)
  rownames(out) <- NULL
  out
}


pivot_dist_bootstrap <- function(data, base_var, group_cols,
                                 count_base = "nTrackedSamples",
                                 n_boot = 2000, seed = NULL) {
  base_name <- rlang::as_name(rlang::enquo(base_var))

  long_data <- dplyr::bind_rows(
    data %>%
      dplyr::mutate(
        tracked_dist_name = "far",
        !!base_name := .data[[paste0(base_name, "Far")]],
        !!count_base := .data[[paste0(count_base, "Far")]]
      ),
    data %>%
      dplyr::mutate(
        tracked_dist_name = "mid",
        !!base_name := .data[[paste0(base_name, "Mid")]],
        !!count_base := .data[[paste0(count_base, "Mid")]]
      ),
    data %>%
      dplyr::mutate(
        tracked_dist_name = "near",
        !!base_name := .data[[paste0(base_name, "Near")]],
        !!count_base := .data[[paste0(count_base, "Near")]]
      )
  )

  bootstrap_grouped(
    long_data,
    value_col = base_name,
    count_col = count_base,
    group_cols = c(group_cols, "tracked_dist_name"),
    n_boot = n_boot,
    seed = seed
  )
}


pool_plot <- function(summary_data, var, group, group2 = NULL) {
  group_quo <- rlang::enquo(group)
  group2_quo <- rlang::enquo(group2)
  var_name <- rlang::as_name(rlang::enquo(var))

  tab0 <- dplyr::filter(summary_data, .data$variable == var_name)

  if (rlang::quo_is_null(group2_quo)) {
    tab <- tab0 %>%
      dplyr::mutate(label = paste0(as.character(!!group_quo), " (n=", .data$n, ")"))

    ggplot2::ggplot(tab, ggplot2::aes(x = !!group_quo, y = .data$mean)) +
      ggplot2::geom_pointrange(
        ggplot2::aes(
          ymin = .data$mean - 2 * .data$se,
          ymax = .data$mean + 2 * .data$se
        ),
        size = prs, linewidth = lw
      ) +
      ggplot2::scale_x_discrete(labels = stats::setNames(tab$label, tab[[rlang::as_name(group_quo)]])) +
      ggplot2::theme_classic() +
      ggplot2::theme(
        axis.text = ggplot2::element_text(size = txt_ax),
        axis.title = ggplot2::element_text(size = txt_axtit),
        legend.text = ggplot2::element_text(size = txt_leg)
      ) +
      ggplot2::labs(
        x = rlang::as_label(group_quo),
        y = var_name
      )
  } else {
    g1_name <- rlang::as_name(group_quo)
    g2_name <- rlang::as_name(group2_quo)

    tab <- tab0 %>%
      dplyr::mutate(cell = interaction(!!group_quo, !!group2_quo, sep = " × ", drop = TRUE))

    lab_df <- tab %>%
      dplyr::mutate(
        cell = interaction(!!group_quo, !!group2_quo, sep = " × ", drop = TRUE),
        label = paste0(.data[[g1_name]], " × ", .data[[g2_name]], " (n=", .data$n, ")")
      )

    g1_levels <- sort(unique(as.character(lab_df[[g1_name]])))
    g2_levels <- sort(unique(as.character(lab_df[[g2_name]])))

    pal <- stats::setNames(scales::hue_pal()(length(g2_levels)), g2_levels)

    cell_order <- unlist(lapply(g1_levels, function(g1) {
      paste(g1, g2_levels, sep = " × ")
    }))

    values <- stats::setNames(
      unlist(lapply(g1_levels, function(g1) pal[g2_levels])),
      cell_order
    )

    labels_vec <- stats::setNames(lab_df$label, as.character(lab_df$cell))
    cell_breaks <- cell_order[cell_order %in% unique(as.character(tab$cell))]
    labels_vec <- labels_vec[cell_breaks]

    ggplot2::ggplot(tab, ggplot2::aes(x = !!group_quo, y = .data$mean, color = .data$cell, group = .data$cell)) +
      ggplot2::geom_pointrange(
        ggplot2::aes(
          ymin = .data$mean - 2 * .data$se,
          ymax = .data$mean + 2 * .data$se
        ),
        position = ggplot2::position_dodge(width = 0.3),
        size = prs, linewidth = lw
      ) +
      ggplot2::scale_color_manual(
        values = values,
        breaks = cell_breaks,
        labels = labels_vec
      ) +
      ggplot2::theme_classic() +
      ggplot2::theme(
        axis.text = ggplot2::element_text(size = txt_ax),
        axis.title = ggplot2::element_text(size = txt_axtit),
        legend.text = ggplot2::element_text(size = txt_leg)
      ) +
      ggplot2::labs(
        x = rlang::as_label(group_quo),
        y = var_name,
        color = paste(rlang::as_label(group_quo), "×", rlang::as_label(group2_quo))
      )
  }
}
