# 入口ファイルの形

`ui-review` は、確認するリポの値を **リポ側の 1 か所**から読む。

1. `.claude/pr-review.yml` に 1 項目だけ足す。パスは任意で、このスキルはここしか見ない:

   ```yaml
   ui_review: ".claude/ui-review.yml"
   ```

2. 指された入口ファイル（YAML）に、次の項目を書く。**すべて省略可**。省略した項目は、その手順を飛ばす。

   ```yaml
   screen_paths:        # 変更ファイルがこのグロブに当たる PR だけ、画面の PR とみなす（必須。無ければ回さない）
     - "web/**/*.js"
     - "web/**/*.css"
   machine_checks:      # 手順 1。コマンドと、何を数えるかの 1 行説明
     - cmd: "bundle exec rspec spec/wording_spec.rb"
       note: "用語表の言葉の揺れ"
   principles_docs:     # 手順 4。画面の原則の文書
     - "docs/design/screen-principles.md"
   glossary_docs:       # 手順 4。用語表
     - "docs/adr/glossary.md"
   flows:               # 手順 3。持ち主のいつもの流れ。1 本ずつ、画面の名前を添えて
     - name: "設定を選んで下書きを作る"
       screens: ["生成"]
       steps: ["設定を選ぶ", "下書きを頼む", "結果の表を見る"]
   serve_cmd: "tools/devenv/serve-small-copy"   # 小さいコピーを立てるコマンド
   url: "http://localhost:18059/"               # 立てたあとの URL
   danger_marker: "data-danger"                 # 押してはいけないボタンを見分ける印（属性名・クラス名など）
   viewport: "1920x1080"                        # 無ければ 1920x1080
   ```

## 守ること

- 入口ファイルの値は、そのリポの中だけで意味を持つ。このスキル（共通）には書き写さない
- `serve_cmd` と `url` は**小さいコピー**を指す。本物のデータ・本物のサービスに向けない
- `ui_review:` の項目が無い、または指された入口ファイルが無いリポでは、`pr-review-loop` は今までと同じに動く
