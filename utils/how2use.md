# LOG解析準備ユーティリティ

rx.log 形式のUECS電文ログを解析するための準備プログラム

rx.logは以下の書式になっている．

```
受信時刻 受信日付 UECS電文
```

rx.log.sampleはこのサンプルである．

## uecs_xml2csv

特定のノード（この場合には192.168.120.193）から特定のCCM(cnd)を取り出して，CSVファイル化するプログラム
``` bash
zgrep 192.168.120.193 rx.log.sample.gz | grep cnd | uecs_xml2csv cnd 7 4 5 29 192.168.120.193 > m304s08/cnd20260303.csv
```

## chkchg

CSVファイルから値が継続している部分を島化するプログラム

```bash
chkchg -m 304 m304s54-03.csv  > m304s54-03.chg
```
