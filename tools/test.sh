#!/usr/bin/env bash
# Запуск автотестов без окна. Использование: tools/test.sh [stage1 stage2 ...]
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s res://tests/run_tests.gd -- "$@"
