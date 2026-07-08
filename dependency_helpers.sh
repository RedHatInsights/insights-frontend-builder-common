#!/bin/bash
set -euo pipefail

has_supported_lock_file() {
  [[ -f package-lock.json ]] || [[ -f yarn.lock ]] || [[ -f pnpm-lock.yaml ]]
}

list_dependency_versions() {
  local dependency_scope="$1"
  local list_json

  if [[ -f pnpm-lock.yaml ]]; then
    if ! list_json=$(pnpm list --json --depth=0 --prod 2>/dev/null); then
      list_json="[]"
    fi
  else
    if ! list_json=$(npm list --silent --json --depth=0 --production 2>/dev/null); then
      list_json="{}"
    fi
  fi

  jq -r --arg scope "$dependency_scope" '
    ($scope | ascii_downcase) as $needle
    | (if type == "array" then .[0] else . end).dependencies // {}
    | to_entries
    | map(
        select(.key | ascii_downcase | contains($needle))
        | "\(.key)@\(.value.version // "unknown")"
      )
    | join("\",\"")
  ' <<< "$list_json" || echo ""
}

format_dependency_array() {
  local dependency_list="$1"

  if [[ -n "$dependency_list" ]]; then
    echo "[\"${dependency_list}\"]"
  else
    echo "[]"
  fi
}
