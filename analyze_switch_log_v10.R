# ======================================================================
# analyze_switch_log_v10.R  — 汎用スイッチログ解析（Googleスプレッドシート対応版）
#
# 使い方（バッチ）:
#   Rscript analyze_switch_log_v10.R 5 "2026-03-01 07:00:00" "2026-03-01 18:00:00"
#
# 使い方（対話）:
#   Rscript analyze_switch_log_v10.R
#   → ノード番号・日時をその場で入力
#
# 設定はすべて Google スプレッドシート（公開CSV URL）から取得．
# Rコードを変えなくても，スプレッドシートを編集するだけで
# チャンネル構成を変更できる．
#
# 対応ログファイル（target_dir 内に置く）:
#   cnd.nmc  … 複数日をまとめたファイル（優先）
#   cnd.chg  … 旧形式（cnd.nmc がない場合に使用）
#   値の表記（0x形式・10進数混在）はどちらも自動判別して処理する．
#
# License: MIT License (https://opensource.org/licenses/MIT)
# Copyright (c) 2025 Masafumi Horimoto
# ======================================================================
source("plot_func10.R")

# config ファイルの決定（引数1番目が .R ファイルなら使う、なければ config.R）
args        <- commandArgs(trailingOnly = TRUE)
config_file <- if (length(args) >= 1 && grepl("\\.R$", args[1])) args[1] else "config.R"
cat(paste0("設定ファイル: ", config_file, "\n"))
source(config_file)

# 日時引数の抽出（configファイル指定がある場合は2番目以降、ない場合は1番目以降）
arg_offset   <- if (grepl("\\.R$", args[1] %||% "")) 1L else 0L
numeric_args <- args[seq_along(args) > arg_offset]

# ======================================================
# 0. 非対話実行用入力ヘルパ
# ======================================================
ask_input <- function(prompt) {
  cat(prompt)
  if (interactive()) {
    return(readline())
  } else {
    con <- file("stdin")
    on.exit(close(con))
    res <- readLines(con, n = 1)
    return(if (length(res) > 0) res else "")
  }
}

# NULL合体演算子（Rの古いバージョン向け）
`%||%` <- function(a, b) if (!is.null(a)) a else b

# 値が「未設定（NA または 空文字）」かどうか判定
is_unset <- function(x) is.null(x) || (length(x) == 1 && (is.na(x) || x == ""))

# ======================================================
# 1. Google スプレッドシートから設定を読み込む
#    ※ シートを「リンクを知っている全員が閲覧可」に設定しておくこと
# ======================================================
base_url <- paste0("https://docs.google.com/spreadsheets/d/", SHEET_ID, "/export?format=csv")

cat("設定をGoogleスプレッドシートから読み込んでいます...\n")

node_url <- paste0(base_url, "&gid=", GID_NODE)
ch_url   <- paste0(base_url, "&gid=", GID_CHANNEL)

config_data <- tryCatch(
  read.csv(url(node_url), stringsAsFactors = FALSE, fileEncoding = "UTF-8"),
  error = function(e) stop(paste0("node_settings の読み込みに失敗しました．\nURL: ", node_url, "\nエラー: ", e$message))
)

ch_all <- tryCatch(
  read.csv(url(ch_url), stringsAsFactors = FALSE, fileEncoding = "UTF-8"),
  error = function(e) stop(paste0("channel_settings の読み込みに失敗しました．\nURL: ", ch_url, "\nエラー: ", e$message))
)

cat(paste0("  ノード設定: ", nrow(config_data), " 件\n"))
cat(paste0("  チャンネル設定: ", nrow(ch_all), " 件\n"))

# ======================================================
# 2. ノード選択（config.R の NODE_ID を使用、NA なら対話選択）
# ======================================================
if (!is_unset(NODE_ID)) {
  node_idx <- as.numeric(NODE_ID)
} else {
  cat("\n--- 解析対象のノードを選択してください ---\n")
  for (i in seq_len(nrow(config_data))) {
    cat(paste0(i, ": ", config_data$node_name[i], "\n"))
  }
  node_idx <- as.numeric(ask_input("番号を入力してください: "))
}

if (is.na(node_idx) || node_idx < 1 || node_idx > nrow(config_data)) {
  stop("ノード番号が不正です．")
}

selected_node <- config_data[node_idx, ]
node_prefix   <- tolower(sub("-.*", "", selected_node$node_name))
target_dir    <- paste0("./", node_prefix)

cat(paste0("\n選択ノード: ", selected_node$node_name, "\n"))
cat(paste0("データディレクトリ: ", target_dir, "\n"))

# ======================================================
# 3. 日時入力（引数 → 対話入力）
#    Rscript analyze_switch_log_v10.R "2026-05-24 07:00:00" "2026-05-24 18:00:00"
#    Rscript analyze_switch_log_v10.R config_宮崎.R "2026-05-24 07:00:00" "2026-05-24 18:00:00"
# ======================================================
start_input <- if (length(numeric_args) >= 1) numeric_args[1] else ask_input("開始日時 (YYYY-MM-DD HH:MM:SS): ")
end_input   <- if (length(numeric_args) >= 2) numeric_args[2] else ask_input("終了日時 (YYYY-MM-DD HH:MM:SS): ")

# ======================================================
# 4. チャンネル設定を抽出
# ======================================================
ch_node <- ch_all[ch_all$node_id == selected_node$node_id, ]

# active 列があれば 1 の行だけ使う（列がない場合は全行を有効とみなす）
if ("active" %in% names(ch_node)) {
  ch_node <- ch_node[ch_node$active == 1, ]
}

ch_bottom <- ch_node[ch_node$panel == "bottom", ]
# ※ 将来 panel == "top" の重ね描き機能を追加する場合はここで ch_top も抽出

if (nrow(ch_bottom) == 0) {
  cat("警告: このノードの channel_settings が未設定です．環境データは描画されません．\n")
}

cat(paste0("チャンネル数（下段）: ", nrow(ch_bottom), "\n"))
for (i in seq_len(nrow(ch_bottom))) {
  act <- if ("active" %in% names(ch_bottom)) ch_bottom$active[i] else 1
  cat(paste0("  ch", i, ": ", ch_bottom$file[i],
             " / ", ch_bottom$col[i],
             " [", ch_bottom$label[i], "]",
             if (act == 0) "  ← スキップ（active=0）" else "",
             "\n"))
}

# ======================================================
# 5. リレー名の構築
# ======================================================
relay_names <- sapply(1:8, function(i) {
  col_name <- paste0("r", i)
  paste0("RLY", i, "(", selected_node[[col_name]], ")")
})

# ======================================================
# 6. ログ解析
# ======================================================

# --- 値パース関数（0x形式・10進数・混在すべてに対応）---
parse_relay_val <- function(x) {
  x <- trimws(x)
  if (grepl("^0x", x, ignore.case = TRUE)) {
    strtoi(x, 16L)       # 0x4, 0x1f など → 16進数として解釈
  } else if (grepl("^[0-9]+$", x)) {
    as.integer(x)        # 4, 5 など → 10進数としてそのまま
  } else {
    NA_integer_          # IGNORE DHCP 等 → スキップ
  }
}

range_from_num <- as.numeric(as.POSIXct(start_input, format = "%Y-%m-%d %H:%M:%S"))
range_to_num   <- as.numeric(as.POSIXct(end_input,   format = "%Y-%m-%d %H:%M:%S"))

if (is.na(range_from_num) || is.na(range_to_num)) {
  stop("日時の形式が不正です．YYYY-MM-DD HH:MM:SS で入力してください．")
}

# --- ログファイルの自動検出（cnd.nmc → cnd.chg の順で探す）---
log_path_nmc <- file.path(target_dir, "cnd.nmc")
log_path_chg <- file.path(target_dir, "cnd.chg")

if (file.exists(log_path_nmc)) {
  log_path <- log_path_nmc
  cat(paste0("ログファイル（nmc）: ", log_path, "\n"))
} else if (file.exists(log_path_chg)) {
  log_path <- log_path_chg
  cat(paste0("ログファイル（chg）: ", log_path, "\n"))
} else {
  stop(paste0("ログファイルが見つかりません（cnd.nmc または cnd.chg）: ", target_dir))
}

cat(paste0("\nログ解析中: ", log_path, "\n"))
lines         <- readLines(log_path, warn = FALSE)
all_times_num <- c()
all_vals      <- c()
current_hex   <- 0L
last_time_num <- NULL

for (line in lines) {
  if (line == "" || line == "---") next

  if (grepl("skipped", line)) {
    skip_match <- regmatches(line, regexec("skipped ([0-9]+) stable rows", line))
    if (length(skip_match[[1]]) > 1) {
      skip_count <- as.numeric(skip_match[[1]][2])
      if (!is.null(last_time_num)) {
        new_times <- last_time_num + (1:skip_count)
        mask <- (new_times >= range_from_num & new_times <= range_to_num)
        if (any(mask)) {
          all_times_num <- c(all_times_num, new_times[mask])
          all_vals      <- c(all_vals, rep(current_hex, sum(mask)))
        }
        last_time_num <- max(new_times)
      }
    }
    next
  }

  parts <- strsplit(line, ",")[[1]]
  if (length(parts) < 2) next
  dt_attempt <- as.POSIXct(parts[1], format = "%Y-%m-%d %H:%M:%S")
  if (is.na(dt_attempt)) next
  dt_num  <- as.numeric(dt_attempt)
  val_num <- parse_relay_val(parts[2])   # ← 0x形式・10進数・混在に対応

  if (!is.na(val_num)) {
    if (!is.null(last_time_num) && dt_num > last_time_num + 1) {
      fill_secs  <- dt_num - last_time_num - 1
      fill_times <- last_time_num + (1:fill_secs)
      mask <- (fill_times >= range_from_num & fill_times <= range_to_num)
      if (any(mask)) {
        all_times_num <- c(all_times_num, fill_times[mask])
        all_vals      <- c(all_vals, rep(current_hex, sum(mask)))
      }
    }
    current_hex   <- val_num
    last_time_num <- dt_num
    if (dt_num >= range_from_num && dt_num <= range_to_num) {
      all_times_num <- c(all_times_num, dt_num)
      all_vals      <- c(all_vals, val_num)
    }
  }
}

cat(paste0("ログデータ: ", length(all_times_num), " 点\n"))

# ======================================================
# 7. 描画
# ======================================================
if (length(all_times_num) > 0) {
  draw_combined_plot(
    all_times_num  = all_times_num,
    all_vals       = all_vals,
    range_from_num = range_from_num,
    range_to_num   = range_to_num,
    start_input    = start_input,
    end_input      = end_input,
    selected_node  = selected_node,
    relay_names    = relay_names,
    target_dir     = target_dir,
    my_font        = MY_FONT,
    ch_bottom      = ch_bottom,
    display_relays = TARGET_RELAYS
  )
} else {
  cat("\n指定範囲にデータがありません．\n")
}
