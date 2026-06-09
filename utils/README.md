# LOG解析準備ユーティリティ

UECS電文受信ログ（`rx.log`）から、スイッチログ統合解析ツール（`analyze_switch_log_v10.R`）が読み込めるファイルを生成するためのユーティリティ群です。

## 全体の流れ

```
rx.log（UECS電文ログ）
    │
    │ zgrep でノード・CCMを絞り込む
    ▼
uecs_xml2csv   ──→  *.csv（日時,値 形式）
    │
    │ chkchg で変化点を抽出・圧縮
    ▼
cnd.nmc / *.chg（スイッチログ統合解析ツールへ）
```

---

## rx.log の形式

UECS電文受信ログです。1行1電文で、以下の形式になっています。

```
受信時刻 受信日付 UECS電文(XML)
```

実際の例：

```
00:00:00 2026-06-09 <?xml version="1.0"?><UECS ver="1.00-E10"><DATA type="cnd" room="7" region="1" order="1" priority="29">0</DATA><IP>192.168.120.177</IP></UECS>
```

| フィールド | 例 | 内容 |
|---|---|---|
| 受信時刻 | `00:00:00` | HH:MM:SS |
| 受信日付 | `2026-06-09` | YYYY-MM-DD |
| type | `cnd` | CCM種別（cnd=制御ノード出力, PPFD=光量子束密度 など） |
| room/region/order | `7/1/1` | ノードの識別子 |
| priority | `29` | 優先度 |
| 値 | `0` | センサ値またはリレー状態 |
| IP | `192.168.120.177` | 送信元IPアドレス |

通常 gzip 圧縮（`rx.log.gz`）で蓄積されます。`rx_log.sample` はサンプルファイルです。

---

## uecs_xml2csv

UECS電文ログから特定ノードの特定CCMを抽出し、CSV形式に変換するシェルスクリプトです。

### 書式

```bash
uecs_xml2csv <type> <room> <region> <order> <priority> <IP>
```

| 引数 | 内容 | 例 |
|---|---|---|
| type | CCM種別 | `cnd`, `PPFD`, `InRadiation` など |
| room | room番号 | `7` |
| region | region番号 | `4` |
| order | order番号 | `5` |
| priority | priority番号 | `29` |
| IP | 送信元IPアドレス | `192.168.120.193` |

### 出力形式

```
2026-06-09 00:00:00,0
2026-06-09 00:00:01,4
2026-06-09 00:00:02,0
```

`日時,値` の2列CSVです。

### 使用例

```bash
# 圧縮ログから特定ノード・CCMを抽出してCSV化
zgrep 192.168.120.193 rx.log.gz | grep cnd | \
    uecs_xml2csv cnd 7 4 5 29 192.168.120.193 > m304s08/cnd20260524.csv

# 非圧縮の場合
grep 192.168.120.193 rx.log | grep cnd | \
    uecs_xml2csv cnd 7 4 5 29 192.168.120.193 > m304s08/cnd20260524.csv
```

### 環境センサの場合

```bash
# 日射量（InRadiation）の取り出し
zgrep 192.168.120.50 rx.log.gz | grep InRadiation | \
    uecs_xml2csv InRadiation 3 1 1 15 192.168.120.50 > m304s08/m302n10.csv
```

---

## chkchg

CSVファイルから値が変化した点の前後だけを抽出し、安定区間を圧縮するシェルスクリプトです。

大量のCSVデータを `analyze_switch_log_v10.R` が読めるコンパクトな形式（`cnd.nmc`）に変換します。

### 書式

```bash
chkchg [-a min_val] [-b max_val] [-m 304] <filename>
```

| オプション | 内容 | 例 |
|---|---|---|
| `-a min_val` | 指定値**以上**のデータのみ出力（Above） | `-a 1` |
| `-b max_val` | 指定値**以下**のデータのみ出力（Below） | `-b 100` |
| `-m 304` | M304固有の特殊値をラベルに変換 | `-m 304` |

### 出力形式

変化区間をブロックとして出力します。

```
:::(skipped 4543 stable rows):::   # 安定区間（省略）
2026-05-24 08:55:58,0x4            # 変化点（前）
2026-05-24 08:56:01,0x0            # 変化点（後）
---                                # ブロック区切り
:::(skipped 120 stable rows):::
2026-05-24 09:10:00,0x5
...
```

整数値（256未満）は `0x` 形式の16進数に変換されます。小数点を含む値（温度など）はそのまま出力されます。

`-m 304` オプションを付けると、M304固有の特殊値が読みやすいラベルに変換されます。

| 値 | ラベル |
|---|---|
| `2064` | `IGNORE DHCP` |
| `131074` | `CHG PARAM FROM WEB` |
| `395264` | `COLD REBOOT` |

### 使用例

```bash
# 制御ノード出力（cnd）を島化 → cnd.nmc として保存
chkchg -m 304 m304s08/cnd20260524.csv > m304s08/cnd20260524.nmc

# 複数日分を結合して cnd.nmc にまとめる
cat cnd20260521.nmc cnd20260524.nmc cnd20260525.nmc > m304s08/cnd.nmc

# 閾値フィルタの例（1以上のデータのみ：OFFを除く）
chkchg -a 1 -m 304 m304s08/cnd20260524.csv > m304s08/cnd20260524.nmc

# 環境センサ（温度など小数点あり）の島化
chkchg m304s08/temp_in.csv > m304s08/temp_in.chg
```

---

## 典型的なワークフロー

M304S08（灌水制御ノード, IP: 192.168.120.193）のデータを準備する例です。

```bash
# 1. データディレクトリを作成
mkdir -p m304s08

# 2. リレー状態ログを日付ごとに抽出・CSV化
zgrep 192.168.120.193 rx.log.20260524.gz | grep ' cnd ' | \
    uecs_xml2csv cnd 7 4 5 29 192.168.120.193 > m304s08/cnd20260524.csv

zgrep 192.168.120.193 rx.log.20260525.gz | grep ' cnd ' | \
    uecs_xml2csv cnd 7 4 5 29 192.168.120.193 > m304s08/cnd20260525.csv

# 3. 各日のCSVを島化
chkchg -m 304 m304s08/cnd20260524.csv > m304s08/cnd20260524.nmc
chkchg -m 304 m304s08/cnd20260525.csv > m304s08/cnd20260525.nmc

# 4. 複数日をまとめて cnd.nmc を作成
cat m304s08/cnd20260524.nmc m304s08/cnd20260525.nmc > m304s08/cnd.nmc

# 5. 環境センサCSVを用意（analyze_switch_log_v10.R の channel_settings に合わせて）
zgrep 192.168.120.50 rx.log.20260524.gz | grep InRadiation | \
    uecs_xml2csv InRadiation 3 1 1 15 192.168.120.50 >> m304s08/m302n10.csv

# 6. 解析実行
Rscript analyze_switch_log_v10.R config_m304s08.R "2026-05-24 07:00:00" "2026-05-24 18:00:00"
```

---

## インストール

`uecs_xml2csv` と `chkchg` はシェルスクリプトです。実行権限を付けて PATH の通った場所に置いてください。

```bash
chmod +x uecs_xml2csv chkchg
cp uecs_xml2csv chkchg /usr/local/bin/
```

または作業ディレクトリに置いて `./uecs_xml2csv` として実行することもできます。

### 動作要件

- `bash`（chkchg）
- `sh`, `sed`, `awk`（uecs_xml2csv）
- `zgrep`（gzip圧縮ログを直接処理する場合）

いずれも標準的な Linux 環境であれば追加インストール不要です。
