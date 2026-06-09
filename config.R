# ======================================================================
# config.R  — 環境設定ファイル
# analyze_switch_log_v10.R と同じディレクトリに置いてください．
# このファイルだけ編集すれば，Rコード本体は変更不要です．
#
# 複数環境での運用例:
#   config_温室A.R, config_温室B.R, config_宮崎.R … と複製して使う
#   Rscript analyze_switch_log_v10.R config_宮崎.R  ← 引数で指定
#   引数省略時は config.R が使われる
# ======================================================================

# --- 解析対象ノード ---
# node_settings の node_id（省略 or NA にすると起動時に対話選択）
NODE_ID <- 5

# --- Google スプレッドシート ---
# スプレッドシートURLの /d/XXXX/edit の XXXX 部分
SHEET_ID    <- "1vpljVcWE7tUuRqWkxL9AAr-ApEI19H2LKSxIqtgyl9M"

# 各シートの gid（シートタブのURLの ?gid= の数字）
GID_NODE    <- "0"            # node_settings シート
GID_CHANNEL <- "1209898986"  # channel_settings シート

# --- フォント ---
# 日本語フォント名（環境に合わせて変更）
# macOS  : "HiraginoSans-W3"
# Ubuntu : "Noto Sans CJK JP"
# Windows: "Yu Gothic"
MY_FONT <- "Noto Sans CJK JP"

# --- 表示するリレー番号 ---
# 描画対象のリレー番号（1〜8 の中から選択）
TARGET_RELAYS <- 1:5
