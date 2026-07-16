#!/usr/bin/env bash
# install.sh — build and install Grok Build (multi-vendor fork)
#
# Usage (from a cloned or unzipped source tree):
#   ./install.sh
#   ./install.sh --prefix ~/.local
#   ./install.sh --name grok-local
#   ./install.sh --with-together-config
#   ./install.sh --skip-build   # only install if target/release/xai-grok-pager exists
#
# After install:
#   grok-local --version
#   grok-local models
#
# Optional vendor key (Together.ai):
#   export TOGETHER_API_KEY=...
#   # or:  echo 'your-key' > ~/together_api_key.txt
#   # then point api_key_file in ~/.grok/config.toml (see config.example.toml)

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN_NAME="${BIN_NAME:-grok-local}"
WITH_TOGETHER_CONFIG=0
SKIP_BUILD=0
JOBS="${JOBS:-}"

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --name) BIN_NAME="$2"; shift 2 ;;
    --with-together-config) WITH_TOGETHER_CONFIG=1; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    -j|--jobs) JOBS="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

log()  { printf '==> %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ── requirements ──────────────────────────────────────────────────────────
need_build_tools() {
  have rustc && have cargo || die "Rust toolchain required (https://rustup.rs)"
  if ! have protoc; then
    if [[ -x "$HOME/.local/bin/protoc" ]]; then
      export PATH="$HOME/.local/bin:$PATH"
    else
      log "protoc not found — installing protobuf 29.3 to ~/.local/bin"
      install_protoc
    fi
  fi
  have protoc || die "protoc still not available"
  export PROTOC="$(command -v protoc)"
  # optional: cargo-dotslash for bin/protoc wrapper
  if ! have dotslash; then
    log "Installing cargo-dotslash (optional, for bin/protoc wrapper)"
    cargo install dotslash --locked 2>/dev/null || true
    export PATH="$HOME/.cargo/bin:$PATH"
  fi
}

install_protoc() {
  local os arch url tmp
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os-$arch" in
    Linux-x86_64)   url="https://github.com/protocolbuffers/protobuf/releases/download/v29.3/protoc-29.3-linux-x86_64.zip" ;;
    Linux-aarch64)  url="https://github.com/protocolbuffers/protobuf/releases/download/v29.3/protoc-29.3-linux-aarch_64.zip" ;;
    Darwin-x86_64)  url="https://github.com/protocolbuffers/protobuf/releases/download/v29.3/protoc-29.3-osx-x86_64.zip" ;;
    Darwin-arm64)   url="https://github.com/protocolbuffers/protobuf/releases/download/v29.3/protoc-29.3-osx-aarch_64.zip" ;;
    *) die "unsupported platform for auto-protoc: $os $arch (install protoc manually)" ;;
  esac
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fsSL -o "$tmp/protoc.zip" "$url"
  unzip -q -o "$tmp/protoc.zip" -d "$tmp/out"
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$tmp/out/bin/protoc" "$HOME/.local/bin/protoc"
  export PATH="$HOME/.local/bin:$PATH"
  log "protoc $(protoc --version)"
}

# ── build ─────────────────────────────────────────────────────────────────
BINARY_SRC="$ROOT/target/release/xai-grok-pager"

build_release() {
  need_build_tools
  log "Building release binary (this can take 10–20+ minutes)…"
  export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"
  export PROTOC="${PROTOC:-$(command -v protoc)}"
  local -a args=(build -p xai-grok-pager-bin --release)
  if [[ -n "$JOBS" ]]; then
    args+=(-j "$JOBS")
  fi
  cargo "${args[@]}"
  [[ -x "$BINARY_SRC" ]] || die "build finished but $BINARY_SRC missing"
}

# ── install binary ────────────────────────────────────────────────────────
install_binary() {
  [[ -x "$BINARY_SRC" ]] || die "no binary at $BINARY_SRC — run without --skip-build"
  mkdir -p "$PREFIX/bin"
  local dest="$PREFIX/bin/$BIN_NAME"
  install -m 755 "$BINARY_SRC" "$dest"
  log "Installed $dest"
  if ! echo ":$PATH:" | grep -q ":$PREFIX/bin:"; then
    log "NOTE: add to your shell profile:"
    echo "  export PATH=\"$PREFIX/bin:\$PATH\""
  fi
  "$dest" --version 2>/dev/null || true
}

# ── optional Together config snippet ──────────────────────────────────────
install_together_config() {
  local cfg="${GROK_HOME:-$HOME/.grok}/config.toml"
  local example="$ROOT/config.example.toml"
  mkdir -p "$(dirname "$cfg")"
  if [[ ! -f "$example" ]]; then
    log "config.example.toml missing — skip config merge"
    return
  fi
  if [[ ! -f "$cfg" ]]; then
    cp "$example" "$cfg"
    log "Wrote $cfg from example"
    return
  fi
  if grep -q 'api.together.ai' "$cfg" 2>/dev/null; then
    log "Together models already present in $cfg — leave unchanged"
    return
  fi
  {
    echo ""
    echo "# --- appended by install.sh (multi-vendor Together models) ---"
    # strip comments-only header from example if any, append model blocks
    sed -n '/^\[model\./,$p' "$example"
  } >> "$cfg"
  log "Appended Together model blocks to $cfg"
  log "Set api_key_file paths or TOGETHER_API_KEY / env_key as needed"
}

# ── main ──────────────────────────────────────────────────────────────────
main() {
  log "Grok Build multi-vendor installer"
  log "Source: $ROOT"
  if [[ "$SKIP_BUILD" -eq 1 ]]; then
    log "Skipping build (--skip-build)"
  elif [[ -x "$BINARY_SRC" ]] && [[ "${FORCE_REBUILD:-0}" != "1" ]]; then
    log "Existing release binary found — rebuild with FORCE_REBUILD=1 if needed"
  else
    build_release
  fi
  install_binary
  if [[ "$WITH_TOGETHER_CONFIG" -eq 1 ]]; then
    install_together_config
  else
    log "Tip: re-run with --with-together-config to append Together.ai models to ~/.grok/config.toml"
    log "     or copy config.example.toml manually"
  fi
  cat <<EOF

Done.

  Run:     $BIN_NAME
  Models:  $BIN_NAME models
  Vendor:  $BIN_NAME -m together-glm
  Account: $BIN_NAME -m grok-4.5   # or other Grok account models

Identity prompt: "You are Grok Build running the <model> model…"

EOF
}

main
