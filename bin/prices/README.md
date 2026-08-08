# `bin/prices/` — `ocw-meter` の価格表

`ocw-meter ingest` が起動時にこのディレクトリ配下の全 `*.json` を読み込み
（`load_price_tables()`、既定は `OCW_METER_SCRIPT_DIR/prices`。`OCW_METER_PRICE_DIR` で上書き可）、
各 `usage.message` イベントの**そのメッセージ自身のtimestampの日付**に対して
`effective_date <= その日付` のうち最も新しいテーブルを選んで適用する
（`ingest` を実行した日ではない）。詳細な費用計算式は
[docs/reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md](../../docs/reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md)
§4 を参照。

## 新しい価格表を追加する手順

1. 一次情報（プロバイダの公式価格ページ）から単価を確認し、URL を控える
2. `bin/prices/<provider>-<effective_date>.json` を作る（ファイル名は慣例。実際に読まれるのは
   中身の `price_table_version` / `effective_date` フィールドで、ファイル名そのものではない）
3. 必須フィールドを埋める（`load_price_tables()` がこの3つを持たないファイルを黙って
   スキップする）:
   - `price_table_version`: このテーブルを一意に識別する文字列。書き込み済みイベントに
     そのままコピーされ、あとから「どのテーブルで計算したか」を追跡する唯一の手がかりになる
   - `effective_date`: `YYYY-MM-DD`。このテーブルが有効になった日
   - `models`: `{ "<model名>": { "cache_hit_in": ..., "cache_miss_in": ..., "out": ... } }`
     （`unit: "per_1m_tokens"` 前提。100万トークンあたりの USD 単価）
4. **`source`（出典 URL）と `fetched_at`（確認日）を必ず埋めること。** 単価は一次情報であり、
   AI が記憶や推測で書くと静かに嘘の数字が入る。**このディレクトリに単価を書き込むのは
   人間の作業とし、AI に「過去の単価を調べて追加して」と依頼しない。**
5. コミットして `bin/tests/lint.sh` / 該当テストを流す

### 過去表を足しても、既に書き込まれたイベントの費用は直らない

`cost_estimate_usd` は `ingest` 時点で計算されて**イベントに焼き込まれる**。「過去は
再計算しない」が `ocw-meter` 全体の不変条件のため、**6〜7月に有効だった価格表をあとから
このディレクトリに足しても、その期間に既に書き込まれた `usage.message` の
`cost_estimate_usd` / `price_table_version` / `price_effective_date` は変わらない。**
（`test_ingest_new_price_table_does_not_touch_already_ingested_events` がこれを固定している。）

過去表を足す価値は「これから初めて ingest される、その期間の未取り込みメッセージ」に対して
正しい単価が適用されるようになることであり、過去に書き込み済みの数字を遡って直すことでは
ない。書き込み済みの数字を直したければイベントストアを作り直すしかなく、それは
`ocw-meter` の設計方針に反する。

### 該当する価格表が無い期間はどう扱われるか

対象日付以前に発効したテーブルが1枚も無いとき、`select_price_table()` は**クラッシュせず**
最も古いテーブル（`tables[0]`）にフォールバックする。この場合、そのイベントに焼き込まれる
`price_effective_date` は実際のメッセージの日付より**後**になる。`report` はこれを
（イベントを書き換えずに）メッセージ自身の日付と `price_effective_date` を突き合わせる
形で読み取り時に検出し、footer の `price_table:` 行の件数と、`report --month` の
`price_tables_applied` の各エントリの `is_fallback` に警告として出す。**判定は日単位**
（月の途中で発効したテーブルへのフォールバックも正しく検出される）。

## 時間帯課金の書き方

一部のプロバイダは時間帯によって単価が変わる（例: DeepSeek の
`Beijing 09:00-12:00, 14:00-18:00` 告知）。これを表現したい場合は、テーブルに
`time_of_day_pricing` を任意で追加する:

```jsonc
{
  "price_table_version": "example-2099-01-01",
  "effective_date": "2099-01-01",
  "source": "https://example.invalid/pricing (実在しないダミー)",
  "fetched_at": "2099-01-01",
  "currency": "USD",
  "unit": "per_1m_tokens",
  "models": {
    "example-model": { "cache_hit_in": 0.01, "cache_miss_in": 0.10, "out": 0.20 }
  },
  "time_of_day_pricing": {
    "tz_offset": "+08:00",
    "tz_label": "Beijing time (China Standard Time, UTC+8, no DST)",
    "boundary": "start_inclusive_end_exclusive",
    "windows": [
      {
        "start": "09:00", "end": "12:00",
        "models": { "example-model": { "cache_hit_in": 0.02, "cache_miss_in": 0.20, "out": 0.40 } }
      },
      {
        "start": "14:00", "end": "18:00",
        "models": { "example-model": { "cache_hit_in": 0.02, "cache_miss_in": 0.20, "out": 0.40 } }
      }
    ]
  }
}
```

（上の `example-model` / URL は実在しないプロバイダの明らかなダミー値。本物の単価表を
コピーして書き換えるときは、`price_table_version` / `source` / `fetched_at` / 単価を
すべて本物の一次情報に差し替えること。)

設計上の決まりごと（`bin/ocw-meter` の `compute_cost` 直前のコメント節に理由の詳細がある）:

- **`tz_offset` は固定オフセット文字列（`"+08:00"` 形式）のみ。** タイムゾーン名
  （`Asia/Shanghai` 等）は使えない。`zoneinfo` は Python 3.9+ かつ tzdata が必要で、
  実行環境に無い場合があるため。表示用に `tz_label` を添えてよいが、計算に使われるのは
  `tz_offset` のみ。時・分とも範囲外（`"+25:00"` 等）の値はテーブルごと無視され、
  クラッシュはしない（下記「壊れた `time_of_day_pricing` はどう扱われるか」参照）
- **境界は開始時刻を含み、終了時刻を含まない**（`start <= t < end`）。
  `"09:00"`-`"12:00"` と `"12:00"`-`"14:00"` のように窓を隙間なく並べても、
  境界ちょうどのタイムスタンプがどちらか片方だけに一意に決まる。**これはコード側に
  固定された唯一の境界規則であり、価格表側から変更する手段は無い。** `boundary` を
  書く場合は `"start_inclusive_end_exclusive"` の値のみが有効で、それ以外の値は
  「壊れた `time_of_day_pricing`」として扱われる（実装が読まずに無視する、ではなく、
  実装と食い違う値を書いたテーブルごと使用不可になる）
- **日を跨ぐ窓は表現できない。** `start >= end`（例 `"22:00"`-`"02:00"`）な窓は
  単に一致しない扱いになる（クラッシュはしないが、無いのと同じ）。日を跨ぐ課金が
  発効した場合はコード側の対応が必要になる
- **時間帯ごとに単価を直接書く（倍率ではない）。** 「2倍」のような倍率表記は
  「何に対しての2倍か」が曖昧になるため、`models` ブロックと同じ形で窓ごとの単価を
  そのまま書く。出典の単価表をそのまま転記できる
- **窓の `models` に載っていないモデルは、その窓の時間帯であっても常に基本の `models`
  の単価が適用される**（そのモデルは時間帯課金の対象外という意味）。同じテーブルの中で
  一部のモデルだけ時間帯課金にできる
- **スキーマに「どちらが高い時間帯か」という情報は無い。** 窓に一致したかどうかだけを
  表す `in_window` / `base_rate` という中立な名前を使う（`peak` / `off_peak` のような
  高低を暗示する名前は採用していない）。理由: 窓が「割高な時間帯」を表すのか「割引の
  時間帯」を表すのかはプロバイダごとに違い、しかも書き込まれたイベントの
  `time_of_day_basis` フィールドは「過去は再計算しない」不変条件のため後から意味を
  直せない。書き込まれたイベントの `time_of_day_basis`
  （`not_applicable` / `in_window` / `base_rate` / `unknown_timestamp`）で、実際に
  窓の単価が適用されたか基本単価が適用されたかを後から確認できる

### 壊れた `time_of_day_pricing` はどう扱われるか

`time_of_day_pricing` キー自体は書いたが、`tz_offset` が範囲外・`windows` が配列でない・
`boundary` が上記の値と食い違う、などで使用できない形になっている場合、そのテーブルは
**時間帯課金なしのテーブルと同じ扱い**（`time_of_day_basis: "not_applicable"`、基本単価を
適用）になる。ただし「最初から `time_of_day_pricing` を書いていない」場合と区別するため、
`ingest` はこの状態を検知すると `state/meter-errors.jsonl` に
`price_table_time_of_day_pricing_unusable` という診断を1件記録する（`report` の
footer の `meter.error diagnostics: N lines` に出る既存の自己診断経路と同じもので、
1日1件にまとめられる）。**単価計算自体はクラッシュしない**が、意図した時間帯課金が
黙って無視されている場合はこの診断で気づけるようにしてある。
