#!/usr/bin/env bash
# tools/*.py 用のPython環境を用意する（Homebrew等のPEP 668環境でも安全）。
#
#   bash tools/setup.sh
#
# 以後は次のように使う:
#   .venv/bin/python tools/preview_templates.py M2-C1
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d .venv ]; then
  echo "仮想環境 .venv を作成します..."
  python3 -m venv .venv
fi
.venv/bin/python -m pip install --quiet --upgrade pip
.venv/bin/python -m pip install --quiet -r requirements.txt

echo ""
echo "準備ができました。次のように実行してください:"
echo "  .venv/bin/python tools/preview_templates.py             # 全テンプレートの問題例"
echo "  .venv/bin/python tools/preview_templates.py M2-C1       # 単元を指定"
echo "  .venv/bin/python tools/validate_templates.py data/templates"
