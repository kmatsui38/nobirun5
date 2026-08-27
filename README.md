# nobirun5（のびるん5）

学力を伸ばしたい中学生が、毎日コツコツと既習内容を復習することで苦手を克服し、学力アップにつなげる学習サービス。

## 現在のステータス

**開発フェーズ（MVP実装中）**

- 企画書: [docs/planning/01_企画書.md](docs/planning/01_企画書.md)
- 数学 単元マスタ: [docs/curriculum/01_数学単元マスタ.md](docs/curriculum/01_数学単元マスタ.md)
- MVP機能要件: [docs/requirements/01_MVP機能要件.md](docs/requirements/01_MVP機能要件.md)
- 問題テンプレート設計: [docs/requirements/02_問題テンプレート設計.md](docs/requirements/02_問題テンプレート設計.md)
- 技術スタック選定: [docs/requirements/03_技術スタック選定.md](docs/requirements/03_技術スタック選定.md)

## ツールの実行準備

`tools/*.py` は PyYAML を使います。初回のみ次を実行してください（`.venv` に隔離してインストールするので、
Homebrew の Python でも `externally-managed-environment` エラーになりません）。

```bash
bash tools/setup.sh
```

以後は `.venv/bin/python tools/xxx.py` の形で実行します。

問題テンプレートの検品だけなら、インストール不要の[検品ページ](https://claude.ai/code/artifact/8acfe114-7971-4c21-a617-0cac36fb8c65)が使えます。

## ドキュメント構成

```
data/
├── curriculum/
│   └── math-units.yaml            # 数学 単元マスタ（機械可読・指導要領準拠）
└── templates/
    ├── samples/                   # 問題テンプレートのサンプル（4本）
    └── math/<単元ID>/             # 数学の問題テンプレート（99本）
docs/
├── planning/
│   └── 01_企画書.md               # サービスコンセプト・企画書
├── curriculum/
│   └── 01_数学単元マスタ.md        # 単元マスタの解説・一覧
├── requirements/
│   ├── 01_MVP機能要件.md          # MVPの画面・学習ロジック・データ設計
│   ├── 02_問題テンプレート設計.md   # テンプレート形式・検品フロー・必要本数
│   └── 03_技術スタック選定.md      # スタック比較と推奨構成
└── reference/
    └── mext/
        └── shidoyoryo_sugaku_h29_honbun.md  # 指導要領（数学）原文抽出テキスト
supabase/
├── migrations/                    # DBスキーマ（0001〜0004）
├── seed.sql                       # 単元マスタ・テンプレートのシード（自動生成）
└── ops.sql                        # 運用クエリ集（セットアップ・進捗確認・検証用の抽出）
tools/
├── validate_templates.py          # テンプレートの機械検証（検品フロー②）
├── preview_templates.py           # 問題例の出力（人の検品用）
├── gen_seed_sql.py                # YAML → シードSQL生成
web/                               # フロントエンド（Next.js 静的SPA → web/README.md）
├── setup.sh                       # ツール用のPython環境を用意（初回のみ）
requirements.txt                   # ツール用のPython依存
```

## テンプレート検品

ブラウザで確認する場合は[検品ページ](https://claude.ai/code/artifact/8acfe114-7971-4c21-a617-0cac36fb8c65)（各テンプレートの問題例・正解・解説を表示し、確認済みチェックと承認SQLの生成ができる）。

コマンドラインの場合:

```bash
bash tools/setup.sh                                              # 初回のみ
.venv/bin/python tools/preview_templates.py                      # 全テンプレートの問題例
.venv/bin/python tools/preview_templates.py M2-C1 --samples 3    # 単元を指定
```
