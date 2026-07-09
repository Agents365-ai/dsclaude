#!/usr/bin/env bash
# install.sh — one-command installer for dsclaude launchers.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Agents365-ai/dsclaude/main/install.sh | bash
#
#   # Or, if you already have the repo:
#   ./install.sh
#
#   # Install to ~/.local/bin instead of /usr/local/bin:
#   curl ... | bash -s -- --user
#
#   # Custom install directory:
#   ./install.sh --prefix /opt/bin
#
set -euo pipefail

PREFIX=""
REPO_URL="https://github.com/Agents365-ai/dsclaude.git"
TMP_DIR=""

cleanup() { [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# ---- Parse args ------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --user)  PREFIX="$HOME/.local/bin" ;;
    --prefix) PREFIX="$2"; shift ;;
    *)       echo "install.sh: unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# ---- Resolve install directory ---------------------------------------------
if [ -z "$PREFIX" ]; then
  if [ -w /usr/local/bin ]; then
    PREFIX="/usr/local/bin"
  elif [ "$(id -u)" = "0" ]; then
    PREFIX="/usr/local/bin"
  else
    echo "install.sh: /usr/local/bin is not writable. Options:"
    echo "  • Run with sudo:  curl ... | sudo bash"
    echo "  • User install:   curl ... | bash -s -- --user"
    exit 1
  fi
fi

mkdir -p "$PREFIX"

echo "install.sh: installing to $PREFIX"

# ---- Get the scripts -------------------------------------------------------
REPO_DIR=""
# If we're already inside a repo clone, use it directly.
self_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
if [ -n "${self_dir:-}" ] && [ -f "$self_dir/dsclaude" ] && [ -d "$self_dir/.git" ]; then
  REPO_DIR="$self_dir"
  echo "install.sh: using local repo at $REPO_DIR"
else
  TMP_DIR="$(mktemp -d -t dsclaude-install.XXXXXX)"
  echo "install.sh: cloning $REPO_URL ..."
  git clone --depth 1 "$REPO_URL" "$TMP_DIR" >/dev/null 2>&1 || {
    echo "install.sh: git clone failed. Check your network or install git." >&2
    exit 1
  }
  REPO_DIR="$TMP_DIR"
fi

# ---- Install shared library --------------------------------------------------
echo "install.sh: installing shared library..."
mkdir -p "$PREFIX/lib"
cp "$REPO_DIR/lib/common.sh" "$PREFIX/lib/common.sh"
chmod +x "$PREFIX/lib/common.sh"

# ---- Install CLI launchers (no extension) ----------------------------------
count=0
echo "install.sh: installing CLI launchers..."
for script in "$REPO_DIR"/*claude; do
  name="$(basename "$script")"
  # Skip .ps1 files and desktop configurators.
  case "$name" in
    *.ps1|*-desktop) continue ;;
  esac
  # Skip non-files.
  [ ! -f "$script" ] && continue
  cp "$script" "$PREFIX/$name"
  chmod +x "$PREFIX/$name"
  echo "  $name"
  count=$((count + 1))
done

# ---- Install desktop configurators -----------------------------------------
echo "install.sh: installing desktop configurators..."
for script in "$REPO_DIR"/*-desktop; do
  name="$(basename "$script")"
  [ ! -f "$script" ] && continue
  cp "$script" "$PREFIX/$name"
  chmod +x "$PREFIX/$name"
  echo "  $name"
  count=$((count + 1))
done

echo ""
echo "✓ Installed $count scripts to $PREFIX"

# ---- PATH reminder ----------------------------------------------------------
if [ "$PREFIX" = "$HOME/.local/bin" ]; then
  if ! echo "$PATH" | tr ':' '\n' | grep -qFx "$PREFIX"; then
    echo ""
    echo "⚠️  $PREFIX is not in your PATH. Add this to your ~/.zshrc or ~/.bashrc:"
    echo "     export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
fi

echo ""
echo "Now set an API key and run xclaude (auto-detect) or any launcher directly:"
echo "  export DEEPSEEK_API_KEY=sk-..."
echo "  xclaude"
