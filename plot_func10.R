# ======================================================================
# plot_func10.R  — 汎用グラフ描画関数
# チャンネル設定（ch_bottom）をループして描画するため，
# ノード種別に関わらずこのファイルは変更不要．
# License: MIT License (https://opensource.org/licenses/MIT)
# Copyright (c) 2025 Masafumi Horimoto
# ======================================================================

draw_combined_plot <- function(all_times_num, all_vals,
                               range_from_num, range_to_num,
                               start_input, end_input,
                               selected_node, relay_names,
                               target_dir, my_font,
                               ch_bottom,
                               display_relays = 1:8) {

  # --- 時間軸の計算 ---
  start_dt     <- as.POSIXct(range_from_num, origin = "1970-01-01")
  end_dt       <- as.POSIXct(range_to_num,   origin = "1970-01-01")
  duration_hrs <- (range_to_num - range_from_num) / 3600
  by_val       <- if (duration_hrs <= 12) 3600 else if (duration_hrs <= 48) 3600 * 3 else 3600 * 12
  start_tick_num   <- as.numeric(trunc(start_dt, "hours"))
  time_ticks_num   <- seq(start_tick_num, range_to_num, by = by_val)
  time_ticks_posix <- as.POSIXct(time_ticks_num, origin = "1970-01-01")
  tick_labels <- if (duration_hrs > 24) format(time_ticks_posix, "%m/%d\n%H:%M") else format(time_ticks_posix, "%H:%M")

  # --- 出力パス ---
  safe_start   <- gsub("[: ]", "_", start_input)
  base_name    <- paste0("combined_analysis_", selected_node$node_name, "_", safe_start)
  output_pdf   <- file.path(target_dir, paste0(base_name, ".pdf"))
  output_png   <- file.path(target_dir, paste0(base_name, ".png"))

  # --- 描画本体を関数化（PDF・PNG共用）---
  do_plot <- function() {
    layout(matrix(c(1, 2), nrow = 2), heights = c(3, 7))

    common_mar_top <- c(0.2, 12, 3, 5)
    common_mar_btm <- c(5,   12, 0.2, 5)

  # ======================================================
  # 上段：リレー開閉状態
  # ======================================================
  par(mar = common_mar_top)
  if (length(all_times_num) > 0) {
    ord          <- order(all_times_num)
    all_times_num <- all_times_num[ord]
    all_vals     <- all_vals[ord]
    dup          <- duplicated(all_times_num)
    all_times_num <- all_times_num[!dup]
    all_vals     <- all_vals[!dup]

    n_relays      <- length(display_relays)
    status_matrix <- matrix(0, nrow = n_relays, ncol = length(all_times_num))
    for (i in seq_len(n_relays)) {
      relay_id <- display_relays[i]
      status_matrix[i, ] <- ifelse(bitwAnd(all_vals, 2^(relay_id - 1)) > 0, 1, 0)
    }
    image(x = all_times_num, y = 1:n_relays,
          z = t(status_matrix[n_relays:1, ]),
          col = c("#F0F0F0", "#0041FF"), axes = FALSE, xlab = "", ylab = "",
          xlim = c(range_from_num, range_to_num), xaxs = "i",
          main = paste0("統合解析: ", selected_node$node_name,
                        "\n", start_input, " 〜 ", end_input),
          cex.main = 1.5)
  } else {
    plot(1, type = "n", axes = FALSE, xlab = "", ylab = "",
         xlim = c(range_from_num, range_to_num),
         ylim = c(0.5, length(display_relays) + 0.5), xaxs = "i")
  }
  axis(2, at = length(display_relays):1,
       labels = relay_names[display_relays], las = 1, cex.axis = 1.4)
  box()
  abline(h = seq(0.5, length(display_relays) + 0.5, 1), col = "white", lwd = 1.5)
  abline(v = time_ticks_num, col = "gray90", lty = "dotted")

  # ======================================================
  # 下段：環境データ（ch_bottom をループ）
  # ======================================================
  par(mar = common_mar_btm)

  # --- 左右軸のスケールを ch_bottom から取得 ---
  left_chs  <- ch_bottom[ch_bottom$axis == "left",  ]
  right_chs <- ch_bottom[ch_bottom$axis == "right", ]

  ylim_left  <- if (nrow(left_chs)  > 0) c(left_chs$ymin[1],  left_chs$ymax[1])  else c(0, 1)
  ylim_right <- if (nrow(right_chs) > 0) c(right_chs$ymin[1], right_chs$ymax[1]) else c(0, 1)

  # ベースプロット（左軸スケールで初期化）
  plot(NULL, type = "n", xlab = "", ylab = "", xaxt = "n", yaxt = "n",
       xlim = c(start_dt, end_dt), ylim = ylim_left, xaxs = "i")

  axis(1, at = time_ticks_posix, labels = tick_labels, cex.axis = 1.4)
  mtext("日時", side = 1, line = 3.5, cex = 1.5)
  abline(v = time_ticks_posix, col = "gray90", lty = "dotted")

  # --- 凡例用ベクタ ---
  leg_labels <- c()
  leg_colors <- c()
  leg_ltys   <- c()

  right_axis_drawn <- FALSE  # 右軸は最初の右チャンネルだけ描画

  # --- チャンネルループ ---
  for (i in seq_len(nrow(ch_bottom))) {
    ch <- ch_bottom[i, ]

    file_path <- file.path(target_dir, ch$file)
    if (!file.exists(file_path)) {
      cat(paste0("  [skip] ファイルなし: ", file_path, "\n"))
      next
    }

    df <- tryCatch(
      read.csv(file_path, stringsAsFactors = FALSE),
      error = function(e) { cat(paste0("  [error] 読込失敗: ", file_path, "\n")); NULL }
    )
    if (is.null(df)) next
    if (!ch$col %in% names(df)) {
      cat(paste0("  [skip] 列 '", ch$col, "' が見つかりません: ", file_path, "\n"))
      next
    }

    df$TOD_p <- as.POSIXct(df$TOD, format = "%Y-%m-%d %H:%M:%S")
    df_sub   <- df[!is.na(df$TOD_p) & df$TOD_p >= start_dt & df$TOD_p <= end_dt, ]
    if (nrow(df_sub) == 0) next

    if (ch$axis == "left") {
      # 左軸：ベースプロットと同じスケールなのでそのまま lines
      lines(df_sub$TOD_p, df_sub[[ch$col]],
            col = ch$color, lwd = 1.5, lty = ch$lty)

      # 左軸ラベル（左チャンネルが複数あっても軸は1本だけ）
      if (i == min(which(ch_bottom$axis == "left"))) {
        axis(2, at  = pretty(ylim_left, n = 6),
             col.axis = ch$color, col = ch$color, las = 1, cex.axis = 1.4)
        mtext(ch$label, side = 2, line = 3, col = ch$color, cex = 1.4)
      }

    } else {
      # 右軸：par(new=TRUE) で重ね描き
      par(new = TRUE)
      plot(df_sub$TOD_p, df_sub[[ch$col]],
           type = "l", col = ch$color, lwd = 1.5, lty = ch$lty,
           axes = FALSE, xlab = "", ylab = "",
           xlim = c(start_dt, end_dt),
           ylim = ylim_right, xaxs = "i")

      if (!right_axis_drawn) {
        axis(4, at  = pretty(ylim_right, n = 6),
             col.axis = ch$color, col = ch$color, las = 1, cex.axis = 1.4)
        mtext(ch$label, side = 4, line = 3, col = ch$color, cex = 1.3)
        right_axis_drawn <- TRUE
      }
    }

    leg_labels <- c(leg_labels, ch$label)
    leg_colors <- c(leg_colors, ch$color)
    leg_ltys   <- c(leg_ltys,   ch$lty)
  }

  # --- 凡例 ---
  if (length(leg_labels) > 0) {
    legend("topleft",
           legend = leg_labels,
           col    = leg_colors,
           lty    = leg_ltys,
           lwd    = 2, bty = "n", cex = 1.4)
  }
  }  # do_plot() end

  # --- PDF 出力 ---
  cairo_pdf(output_pdf, width = 14, height = 7, family = my_font)
  do_plot()
  if (dev.cur() > 1) dev.off()
  cat(paste0("PDF: ", output_pdf, "\n"))

  # --- PNG 出力 ---
  png(output_png, width = 1400, height = 700, res = 100, type = "cairo",
      family = my_font)
  do_plot()
  if (dev.cur() > 1) dev.off()
  cat(paste0("PNG: ", output_png, "\n"))

  cat("完了\n")
}
