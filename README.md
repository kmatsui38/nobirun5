# nobirun5（のびるん5）

学力を伸ばしたい中学生が、毎日コツコツと既習内容を復習することで苦手を克服し、学力アップにつなげる学習サービス。

## 現在のステータス

**企画フェーズ**

- 企画書: [docs/planning/01_企画書.md](docs/planning/01_企画書.md)
- 数学 単元マスタ: [docs/curriculum/01_数学単元マスタ.md](docs/curriculum/01_数学単元マスタ.md)
- MVP機能要件: [docs/requirements/01_MVP機能要件.md](docs/requirements/01_MVP機能要件.md)
- 問題テンプレート設計: [docs/requirements/02_問題テンプレート設計.md](docs/requirements/02_問題テンプレート設計.md)

## ドキュメント構成

```
data/
├── curriculum/
│   └── math-units.yaml            # 数学 単元マスタ（機械可読・指導要領準拠）
└── templates/
    └── samples/                   # 問題テンプレートのサンプル（4本）
docs/
├── planning/
│   └── 01_企画書.md               # サービスコンセプト・企画書
├── curriculum/
│   └── 01_数学単元マスタ.md        # 単元マスタの解説・一覧
├── requirements/
│   ├── 01_MVP機能要件.md          # MVPの画面・学習ロジック・データ設計
│   └── 02_問題テンプレート設計.md   # テンプレート形式・検品フロー・必要本数
└── reference/
    └── mext/
        └── shidoyoryo_sugaku_h29_honbun.md  # 指導要領（数学）原文抽出テキスト
tools/
└── validate_templates.py          # テンプレートの機械検証（検品フロー②）
```
