#!/usr/bin/env bash
# build.sh — Export Smush for Windows, Linux, and macOS via Godot headless CLI.
# Usage: ./tools/build.sh [windows|linux|macos|all]
# Requires: Godot 4.x on PATH (or set GODOT_BIN env var).

set -euo pipefail

GODOT="${GODOT_BIN:-godot}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$PROJECT_DIR/builds/windows"
mkdir -p "$PROJECT_DIR/builds/linux"
mkdir -p "$PROJECT_DIR/builds/macos"

build_windows() {
  echo "==> Exporting Windows..."
  "$GODOT" --headless --path "$PROJECT_DIR" --export-release "Windows Desktop" "builds/windows/Smush.exe"
  echo "    Done: builds/windows/Smush.exe"
}

build_linux() {
  echo "==> Exporting Linux..."
  "$GODOT" --headless --path "$PROJECT_DIR" --export-release "Linux" "builds/linux/Smush.x86_64"
  echo "    Done: builds/linux/Smush.x86_64"
}

build_macos() {
  echo "==> Exporting macOS..."
  "$GODOT" --headless --path "$PROJECT_DIR" --export-release "macOS" "builds/macos/Smush.zip"
  echo "    Done: builds/macos/Smush.zip"
}

TARGET="${1:-all}"

case "$TARGET" in
  windows) build_windows ;;
  linux)   build_linux ;;
  macos)   build_macos ;;
  all)
    build_windows
    build_linux
    build_macos
    echo "==> All platforms exported."
    ;;
  *)
    echo "Usage: $0 [windows|linux|macos|all]"
    exit 1
    ;;
esac
