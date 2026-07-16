#!/usr/bin/env bash
# add-vendor.sh — install vendor presets or append a custom [model.*] block
#
# Usage:
#   ./scripts/add-vendor.sh list
#   ./scripts/add-vendor.sh install together [openai ...]
#   ./scripts/add-vendor.sh keys together     # create empty key file only
#   ./scripts/add-vendor.sh add --vendor acme --id acme-x --model m --base-url URL [--context N]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDORS_DIR="${ROOT}/vendors"
GROK_HOME="${GROK_HOME:-$HOME/.grok}"
CFG="${GROK_CONFIG:-$GROK_HOME/config.toml}"
KEYS_DIR="${GROK_KEYS_DIR:-$GROK_HOME/keys}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
add-vendor.sh — multi-vendor helpers for Grok Build

  list                         Show built-in vendor presets
  install <vendor> [vendor…]   Append preset models + create key placeholder
  keys <vendor> [vendor…]      Create ~/VENDOR_api_key.txt and ~/.grok/keys/VENDOR.txt
  add [options]                Append one custom model block

Custom add options:
  --vendor NAME        Vendor slug for key file (required)
  --id ID              Config id → [model.ID] (default: VENDOR-model)
  --model SLUG         Model id sent to the API (required)
  --base-url URL       OpenAI-compatible base URL (required)
  --name TEXT          Display name
  --context N          context_window (default 128000)
  --backend NAME       chat_completions | responses | messages (default chat_completions)
  --env-key VAR        Also set env_key = "VAR"
  --no-key-file        Do not create key placeholders
  --config PATH        Config file (default ~/.grok/config.toml)

Key convention for vendor V:
  ~/V_api_key.txt
  ~/.grok/keys/V.txt
  api_key_file = "@V"   in config
EOF
  exit "${1:-0}"
}

ensure_dirs() {
  mkdir -p "$GROK_HOME" "$KEYS_DIR"
}

create_key_placeholders() {
  local vendor="$1"
  local home_key="$HOME/${vendor}_api_key.txt"
  local grok_key="$KEYS_DIR/${vendor}.txt"
  ensure_dirs
  if [[ ! -f "$home_key" ]]; then
    : > "$home_key"
    chmod 600 "$home_key"
    log "Created empty key file: $home_key  (paste your key, one line)"
  else
    log "Key file exists: $home_key"
  fi
  if [[ ! -f "$grok_key" ]]; then
    : > "$grok_key"
    chmod 600 "$grok_key"
    log "Created empty key file: $grok_key"
  else
    log "Key file exists: $grok_key"
  fi
}

append_if_missing() {
  local marker="$1"
  local file="$2"
  local content="$3"
  ensure_dirs
  if [[ -f "$CFG" ]] && grep -qF "$marker" "$CFG" 2>/dev/null; then
    log "Already present in $CFG (marker: $marker) — skip"
    return 0
  fi
  {
    echo ""
    echo "$content"
  } >> "$CFG"
  log "Appended to $CFG"
}

cmd_list() {
  log "Presets in $VENDORS_DIR:"
  if [[ ! -d "$VENDORS_DIR" ]]; then
    die "vendors/ directory missing"
  fi
  local f base
  for f in "$VENDORS_DIR"/*.toml; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f" .toml)"
    [[ "$base" == "README" ]] && continue
    printf '  %-14s  %s\n' "$base" "$f"
  done
  echo
  echo "Install:  ./scripts/add-vendor.sh install together"
  echo "Keys:     echo 'sk-…' > ~/together_api_key.txt && chmod 600 ~/together_api_key.txt"
}

cmd_install() {
  [[ $# -ge 1 ]] || die "usage: install <vendor> [vendor…]"
  local v preset
  for v in "$@"; do
    preset="$VENDORS_DIR/${v}.toml"
    [[ -f "$preset" ]] || die "unknown preset '$v' (try: list)"
    create_key_placeholders "$v"
    # Prefer first [model.X] as marker
    local first_model
    first_model="$(grep -m1 -E '^\[model\.' "$preset" | tr -d '[]' || true)"
    local body
    body="$(grep -v '^#' "$preset" | sed '/^$/N;/^\n$/d')"
    # Keep comments for readability
    body="$(cat "$preset")"
    append_if_missing "# vendor-preset:${v}" "$CFG" "$(cat <<EOF
# vendor-preset:${v}  (from vendors/${v}.toml)
# Key: ~/${v}_api_key.txt  or  ~/.grok/keys/${v}.txt  or  api_key_file = \"@${v}\"
${body}
EOF
)"
    log "Installed preset '$v'${first_model:+ (e.g. ${first_model#model.} )}"
  done
  log "Edit keys, then: grok-local models"
}

cmd_keys() {
  [[ $# -ge 1 ]] || die "usage: keys <vendor> [vendor…]"
  local v
  for v in "$@"; do
    create_key_placeholders "$v"
  done
}

cmd_add() {
  local vendor="" id="" model="" base_url="" name="" context="128000"
  local backend="chat_completions" env_key="" no_key=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --vendor) vendor="$2"; shift 2 ;;
      --id) id="$2"; shift 2 ;;
      --model) model="$2"; shift 2 ;;
      --base-url) base_url="$2"; shift 2 ;;
      --name) name="$2"; shift 2 ;;
      --context) context="$2"; shift 2 ;;
      --backend) backend="$2"; shift 2 ;;
      --env-key) env_key="$2"; shift 2 ;;
      --no-key-file) no_key=1; shift ;;
      --config) CFG="$2"; shift 2 ;;
      -h|--help) usage 0 ;;
      *) die "unknown option: $1" ;;
    esac
  done
  [[ -n "$vendor" && -n "$model" && -n "$base_url" ]] || \
    die "--vendor, --model, and --base-url are required"
  # normalize vendor slug
  vendor="$(echo "$vendor" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_-' '-')"
  vendor="${vendor#-}"
  vendor="${vendor%-}"
  [[ -n "$vendor" ]] || die "invalid vendor slug"
  id="${id:-${vendor}-model}"
  name="${name:-$model ($vendor)}"
  [[ "$no_key" -eq 0 ]] && create_key_placeholders "$vendor"

  local env_line=""
  [[ -n "$env_key" ]] && env_line=$'env_key = "'"$env_key"$'"\n'

  append_if_missing "[model.${id}]" "$CFG" "$(cat <<EOF
# vendor-custom:${vendor}
[model.${id}]
model = "${model}"
base_url = "${base_url}"
name = "${name}"
api_key_file = "@${vendor}"
${env_line}api_backend = "${backend}"
system_prompt_label = "${model} (${vendor})"
context_window = ${context}
EOF
)"
  log "Model id: ${id}  →  grok-local -m ${id}"
  log "Key file: ~/${vendor}_api_key.txt  (or ~/.grok/keys/${vendor}.txt)"
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    list|"") cmd_list ;;
    install) cmd_install "$@" ;;
    keys) cmd_keys "$@" ;;
    add) cmd_add "$@" ;;
    -h|--help|help) usage 0 ;;
    *) die "unknown command: $cmd (try: list | install | keys | add)" ;;
  esac
}

main "$@"
