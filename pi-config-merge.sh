#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# pi-config-merge.sh
# Merge/split pi settings.json from layered config files.
#
# Concept:
#   settings.base.json    → shared config (synced via dotfiles)
#   settings.local.json   → machine-specific overrides (NOT synced)
#   settings.json         → generated merge result (NOT synced, read by pi)
#
# Usage:
#   pi-config-merge.sh merge           # merge base + local -> settings.json
#   pi-config-merge.sh split           # split settings.json -> base + local
#   pi-config-merge.sh init-local      # create settings.local.json template
#   pi-config-merge.sh validate        # check configs are consistent
#   pi-config-merge.sh watch           # watch base/local and auto-merge
#
# Environment variables:
#   PI_DIR           Override pi agent directory (default: ~/.pi/agent)
#   LOCAL_KEYS       Comma-separated keys treated as local (see below)
# ============================================================================

PI_DIR="${PI_DIR:-$HOME/.pi/agent}"
BASE_FILE="$PI_DIR/settings.base.json"
LOCAL_FILE="$PI_DIR/settings.local.json"
OUTPUT_FILE="$PI_DIR/settings.json"

# Default keys considered machine-specific. Override via LOCAL_KEYS env var.
DEFAULT_LOCAL_KEYS="shellPath,shellCommandPrefix,editor,npmCommand"
LOCAL_KEYS="${LOCAL_KEYS:-$DEFAULT_LOCAL_KEYS}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()   { echo -e "${RED}[ERR]${NC}  $*"; }
log_dim()   { echo -e "${DIM}$*${NC}"; }

print_help() {
  cat << 'EOF'
Usage: pi-config-merge.sh <command>

Commands:
  merge       Merge settings.base.json + settings.local.json -> settings.json
  split       Split existing settings.json -> settings.base.json + settings.local.json
              (smart: auto-detects local keys by path patterns)
  init-local  Create a fresh settings.local.json template for this machine
  validate    Check that settings.json equals merge(base, local)
  diff        Show differences between current settings.json and merged result
  watch       Watch base/local files and auto-merge on changes (requires fswatch or inotifywait)
  env         Print detected environment info (OS, shell, paths)
  help        Show this help

Environment variables:
  PI_DIR       Path to pi agent directory (default: ~/.pi/agent)
  LOCAL_KEYS   Comma-separated keys considered machine-local
               Default: shellPath,shellCommandPrefix,editor,npmCommand

Examples:
  # One-time merge after pulling dotfiles
  ./pi-config-merge.sh merge

  # Migrate existing monolithic settings.json to layered
  ./pi-config-merge.sh split

  # Create local overrides on a new machine
  ./pi-config-merge.sh init-local

  # Auto-merge during development
  ./pi-config-merge.sh watch

  # Use custom local keys
  LOCAL_KEYS="shellPath,theme,editor" ./pi-config-merge.sh split
EOF
}

# ============================================================================
# Utils
# ============================================================================

check_deps() {
  if ! command -v jq &> /dev/null; then
    log_err "jq is required but not installed."
    log_info "Install: https://jqlang.github.io/jq/download/"
    exit 1
  fi
}

ensure_pi_dir() {
  if [[ ! -d "$PI_DIR" ]]; then
    log_err "Pi agent directory not found: $PI_DIR"
    exit 1
  fi
}

backup_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    local bak="${file}.bak.$(date +%s)"
    cp "$file" "$bak"
    log_dim "  Backed up: $bak"
  fi
}

# Detect likely local keys by checking if their values contain absolute paths
# or known platform-specific patterns
detect_local_keys() {
  local file="$1"
  local detected=""

  # Keys explicitly known to be local
  local known="$LOCAL_KEYS"

  # Auto-detect: values that look like absolute Windows paths
  local win_paths
  win_paths=$(jq -r '
    keys[] as $k |
    select(.[$k] | type == "string" and test("^[A-Za-z]:\\\\")) |
    $k
  ' "$file" 2>/dev/null || true)

  # Auto-detect: values that look like Unix absolute paths (excluding standard ones)
  local unix_paths
  unix_paths=$(jq -r '
    keys[] as $k |
    select(.[$k] | type == "string" and test("^/[^/]") and (. | test("^/tmp/|^/dev/|^/proc/") | not)) |
    $k
  ' "$file" 2>/dev/null || true)

  # Combine
  detected="$known"
  for k in $win_paths $unix_paths; do
    if [[ ",${detected}," != *",${k},"* ]]; then
      detected="${detected},${k}"
    fi
  done

  echo "$detected"
}

# Convert comma-separated keys to jq filter
keys_to_jq_filter() {
  local keys="$1"
  local filter=""
  IFS=',' read -ra KEY_ARRAY <<< "$keys"
  for k in "${KEY_ARRAY[@]}"; do
    k=$(echo "$k" | xargs) # trim
    [[ -z "$k" ]] && continue
    if [[ -n "$filter" ]]; then
      filter="$filter, \"$k\""
    else
      filter="\"$k\""
    fi
  done
  echo "[$filter]"
}

# ============================================================================
# Commands
# ============================================================================

cmd_merge() {
  ensure_pi_dir

  if [[ ! -f "$BASE_FILE" ]]; then
    log_err "Base config not found: $BASE_FILE"
    log_info "Run 'split' to extract from existing settings.json, or create it manually."
    exit 1
  fi

  # Validate base is valid JSON
  if ! jq empty "$BASE_FILE" 2>/dev/null; then
    log_err "$BASE_FILE is not valid JSON"
    exit 1
  fi

  # Merge
  if [[ -f "$LOCAL_FILE" ]]; then
    if ! jq empty "$LOCAL_FILE" 2>/dev/null; then
      log_err "$LOCAL_FILE is not valid JSON"
      exit 1
    fi
    jq -s '.[0] * .[1]' "$BASE_FILE" "$LOCAL_FILE" > "$OUTPUT_FILE.tmp"
    log_ok "Merged: base ($(jq 'keys | length' "$BASE_FILE") keys) + local ($(jq 'keys | length' "$LOCAL_FILE") keys)"
  else
    cp "$BASE_FILE" "$OUTPUT_FILE.tmp"
    log_warn "No local config found. Using base only."
    log_info "Run 'init-local' to create local overrides."
  fi

  backup_file "$OUTPUT_FILE"
  mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
  log_ok "Generated: $OUTPUT_FILE ($(jq 'keys | length' "$OUTPUT_FILE") keys)"
}

cmd_split() {
  ensure_pi_dir

  if [[ ! -f "$OUTPUT_FILE" ]]; then
    log_err "No settings.json found to split: $OUTPUT_FILE"
    exit 1
  fi

  # Validate
  if ! jq empty "$OUTPUT_FILE" 2>/dev/null; then
    log_err "$OUTPUT_FILE is not valid JSON"
    exit 1
  fi

  log_info "Analyzing settings.json for local keys..."
  local detected_keys
  detected_keys=$(detect_local_keys "$OUTPUT_FILE")
  log_info "Detected local keys: $detected_keys"

  local jq_keys
  jq_keys=$(keys_to_jq_filter "$detected_keys")
  log_dim "  JQ filter: $jq_keys"

  # Extract local keys
  jq "with_entries(select(.key as \$k | $jq_keys | index(\$k)))" "$OUTPUT_FILE" > "$LOCAL_FILE.tmp"

  # Extract base keys (everything else)
  jq "with_entries(select(.key as \$k | $jq_keys | index(\$k) | not))" "$OUTPUT_FILE" > "$BASE_FILE.tmp"

  backup_file "$LOCAL_FILE"
  backup_file "$BASE_FILE"

  mv "$LOCAL_FILE.tmp" "$LOCAL_FILE"
  mv "$BASE_FILE.tmp" "$BASE_FILE"

  log_ok "Split complete:"
  echo ""
  echo "  Base config:    $BASE_FILE"
  echo "    Keys:         $(jq 'keys | length' "$BASE_FILE")"
  echo ""
  echo "  Local config:   $LOCAL_FILE"
  echo "    Keys:         $(jq 'keys | length' "$LOCAL_FILE")"
  echo ""

  # Validate round-trip
  log_info "Validating round-trip merge..."
  local merged_tmp="$PI_DIR/.settings.validate.tmp"
  jq -s '.[0] * .[1]' "$BASE_FILE" "$LOCAL_FILE" > "$merged_tmp"

  if diff -q "$OUTPUT_FILE" "$merged_tmp" > /dev/null 2>&1; then
    log_ok "Round-trip validation passed!"
    rm "$merged_tmp"
    log_info "You can now:"
    echo "  1. Add $BASE_FILE to your dotfiles repo"
    echo "  2. Keep $LOCAL_FILE device-local (DO NOT git add)"
    echo "  3. settings.json is now auto-generated — edit base or local instead"
  else
    log_warn "Round-trip mismatch! Manual review needed."
    log_info "Diff saved to: $merged_tmp"
  fi
}

cmd_init_local() {
  ensure_pi_dir

  if [[ -f "$LOCAL_FILE" ]]; then
    log_warn "Local config already exists: $LOCAL_FILE"
    read -rp "Overwrite? [y/N] " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { log_info "Aborted."; exit 0; }
  fi

  # Detect OS and suggest appropriate local config
  local os="unknown"
  case "$(uname -s)" in
    Linux*)     os="linux" ;;
    Darwin*)    os="macos" ;;
    CYGWIN*|MINGW*|MSYS*) os="windows" ;;
  esac

  log_info "Detected OS: $os"

  local local_json
  case "$os" in
    windows)
      local_json='{
  "_comment": "Windows-specific pi configuration",
  "shellPath": "D:\\Programs\\msys2\\usr\\bin\\bash.exe",
  "shellCommandPrefix": "source ~/.bashrc && "
}'
      ;;
    macos)
      local_json='{
  "_comment": "macOS-specific pi configuration",
  "shellPath": "/bin/zsh",
  "shellCommandPrefix": ""
}'
      ;;
    linux)
      local_json='{
  "_comment": "Linux-specific pi configuration",
  "shellPath": "/bin/bash",
  "shellCommandPrefix": "source ~/.bashrc && "
}'
      ;;
    *)
      local_json='{
  "_comment": "Machine-specific pi configuration — edit for your platform",
  "shellPath": "/bin/bash",
  "shellCommandPrefix": ""
}'
      ;;
  esac

  echo "$local_json" > "$LOCAL_FILE"
  log_ok "Created: $LOCAL_FILE"
  cat "$LOCAL_FILE"

  echo ""
  log_info "Next: run './pi-config-merge.sh merge' to generate settings.json"
}

cmd_validate() {
  ensure_pi_dir

  if [[ ! -f "$BASE_FILE" ]] || [[ ! -f "$LOCAL_FILE" ]]; then
    log_err "Missing base or local config"
    exit 1
  fi

  if [[ ! -f "$OUTPUT_FILE" ]]; then
    log_err "No settings.json to validate against"
    exit 1
  fi

  local merged_tmp="$PI_DIR/.settings.validate.tmp"
  jq -s '.[0] * .[1]' "$BASE_FILE" "$LOCAL_FILE" > "$merged_tmp"

  if diff -q "$OUTPUT_FILE" "$merged_tmp" > /dev/null 2>&1; then
    log_ok "settings.json is consistent with base + local"
    rm "$merged_tmp"
  else
    log_err "settings.json is OUT OF SYNC with base + local!"
    log_info "Run 'merge' to regenerate, or 'diff' to see changes."
    rm "$merged_tmp"
    exit 1
  fi
}

cmd_diff() {
  ensure_pi_dir

  if [[ ! -f "$BASE_FILE" ]]; then
    log_err "No base config found"
    exit 1
  fi

  local merged_tmp="$PI_DIR/.settings.diff.tmp"
  if [[ -f "$LOCAL_FILE" ]]; then
    jq -s '.[0] * .[1]' "$BASE_FILE" "$LOCAL_FILE" > "$merged_tmp"
  else
    cp "$BASE_FILE" "$merged_tmp"
  fi

  if [[ ! -f "$OUTPUT_FILE" ]]; then
    log_warn "No settings.json exists yet. Merged result would be:"
    cat "$merged_tmp"
    rm "$merged_tmp"
    return
  fi

  log_info "Diff: current settings.json vs merged(base + local)"
  diff -u "$OUTPUT_FILE" "$merged_tmp" || true
  rm "$merged_tmp"
}

cmd_watch() {
  ensure_pi_dir

  if ! command -v fswatch &> /dev/null && ! command -v inotifywait &> /dev/null; then
    log_err "No file watcher found. Install fswatch (macOS) or inotify-tools (Linux)."
    log_info "  macOS:   brew install fswatch"
    log_info "  Linux:   sudo apt-get install inotify-tools"
    exit 1
  fi

  log_info "Watching for changes in:"
  log_dim "  $BASE_FILE"
  log_dim "  $LOCAL_FILE"
  echo ""

  cmd_merge

  if command -v fswatch &> /dev/null; then
    fswatch -o "$BASE_FILE" "$LOCAL_FILE" | while read -r; do
      echo ""
      log_info "Change detected, re-merging..."
      cmd_merge
    done
  else
    while inotifywait -e modify,move,create,delete "$BASE_FILE" "$LOCAL_FILE" 2>/dev/null; do
      echo ""
      log_info "Change detected, re-merging..."
      cmd_merge
    done
  fi
}

cmd_env() {
  echo "Detected environment:"
  echo "  OS:            $(uname -s)"
  echo "  Home:          $HOME"
  echo "  Pi dir:        $PI_DIR"
  echo "  Base config:   $BASE_FILE"
  echo "  Local config:  $LOCAL_FILE"
  echo "  Output config: $OUTPUT_FILE"
  echo ""
  echo "Local keys filter: $LOCAL_KEYS"
  echo ""

  if [[ -f "$BASE_FILE" ]]; then
    echo "Base config exists: yes ($(jq 'keys | length' "$BASE_FILE") keys)"
  else
    echo "Base config exists: no"
  fi

  if [[ -f "$LOCAL_FILE" ]]; then
    echo "Local config exists: yes ($(jq 'keys | length' "$LOCAL_FILE") keys)"
  else
    echo "Local config exists: no"
  fi

  if [[ -f "$OUTPUT_FILE" ]]; then
    echo "Output config exists: yes ($(jq 'keys | length' "$OUTPUT_FILE") keys)"
  else
    echo "Output config exists: no"
  fi
}

# ============================================================================
# Main
# ============================================================================

check_deps

case "${1:-help}" in
  merge)
    cmd_merge
    ;;
  split)
    cmd_split
    ;;
  init-local)
    cmd_init_local
    ;;
  validate)
    cmd_validate
    ;;
  diff)
    cmd_diff
    ;;
  watch)
    cmd_watch
    ;;
  env)
    cmd_env
    ;;
  help|--help|-h)
    print_help
    ;;
  *)
    log_err "Unknown command: $1"
    print_help
    exit 1
    ;;
esac
