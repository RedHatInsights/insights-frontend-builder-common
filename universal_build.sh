#!/bin/bash
set -euo pipefail

set -exv

# ────────── SENTRY & SECRETS SETUP ──────────
# Source secrets if the parse-secrets script exists
if [[ -f ./build-tools/parse-secrets.sh ]]; then
  source ./build-tools/parse-secrets.sh
fi

# Get the app name in uppercase format for secret lookup
# Note: Uses PACKAGE_JSON_PATH env var (defaults to package.json)
APP_NAME_FOR_SECRET="$(jq -r '.insights.appname' < "${PACKAGE_JSON_PATH:-package.json}" | tr '[:lower:]-' '[:upper:]_')"
SECRET_VAR_NAME="${APP_NAME_FOR_SECRET}_SECRET"
USES_NPM=false
USES_YARN=false
USES_PNPM=false

# Disable verbose output to hide Sentry token from logs
{ old_opts=$(set +o); set +x; } 2>/dev/null

if [[ -n "${!SECRET_VAR_NAME:-}" ]]; then
  export ENABLE_SENTRY=true
  export SENTRY_AUTH_TOKEN="${!SECRET_VAR_NAME}"
  echo "Sentry: token found for ${APP_NAME_FOR_SECRET} – enabling sourcemap upload."
else
  echo "Sentry: no token for ${APP_NAME_FOR_SECRET} – using any pre-set token (if provided) or skipping upload."
fi
# Restore previous shell options (re-enables verbose output)
{ eval "$old_opts"; } 2>/dev/null

# Configure git to trust this directory
git config --global --add safe.directory /opt/app-root/src

# ────────── END SENTRY & SECRETS SETUP ──────────

export APP_BUILD_DIR=${APP_BUILD_DIR:-dist}
export OUTPUT_DIR=${OUTPUT_DIR:-dist}

function install() {
  if [[ "$USES_NPM" == true ]]; then
    npm ci
  elif [[ "$USES_YARN" == true ]]; then
    yarn install --immutable
  elif [[ "$USES_PNPM" == true ]]; then
    pnpm install --frozen-lockfile
  else
    # Normally we would not use exit in a source'd file, but this should fail the job
    echo "Exiting; no supported installation packages"
    exit 1
  fi
}

function verify() {
  if [[ "$USES_NPM" == true ]]; then
    npm run verify
  elif [[ "$USES_YARN" == true ]]; then
    yarn verify
  elif [[ "$USES_PNPM" == true ]]; then
    pnpm run verify
  else
    # Normally we would not use exit in a source'd file, but this should fail the job
    echo "Exiting; no supported verification tool or target"
    exit 1
  fi
}

function build() {
  if [[ "$USES_NPM" == true ]]; then
    # If NPM_BUILD_SCRIPT env var is set use that
    # Otherwise just build
    if [[ -n "$NPM_BUILD_SCRIPT" ]]; then
      npm run "$NPM_BUILD_SCRIPT"
    else
      npm run build
    fi
  elif [[ "$USES_YARN" == true ]]; then
    # If YARN_BUILD_SCRIPT env var is set use that
    # Otherwise just build
    if [[ -n "$YARN_BUILD_SCRIPT" ]]; then
      yarn "$YARN_BUILD_SCRIPT"
    else
      yarn build:prod
    fi
  elif [[ "$USES_PNPM" == true ]]; then
    # Prefer the pnpm-specific build arg, but keep NPM_BUILD_SCRIPT working for
    # existing Tekton/Konflux configs that use that build arg name.
    if [[ -n "$PNPM_BUILD_SCRIPT" ]]; then
      pnpm run "$PNPM_BUILD_SCRIPT"
    elif [[ -n "$NPM_BUILD_SCRIPT" ]]; then
      pnpm run "$NPM_BUILD_SCRIPT"
    else
      pnpm run build
    fi
  else
    # Normally we would not use exit in a source'd file, but this should fail the job
    echo "Exiting; no supported build or target"
    exit 1
  fi
}

function delete_node_modules() {
  if [[ -d "node_modules" ]]; then
    rm -rf node_modules
  else
    echo "node_modules directory not found."
  fi
}

function setPackageManager() {
  # We can't assume npm, yarn, or pnpm, so we turn on the toggle depending on
  # lock files in the root.
  local lock_files=()

  [[ -f package-lock.json ]] && lock_files+=("package-lock.json")
  [[ -f yarn.lock ]] && lock_files+=("yarn.lock")
  [[ -f pnpm-lock.yaml ]] && lock_files+=("pnpm-lock.yaml")

  if (( ${#lock_files[@]} > 1 )); then
    echo "Exiting; multiple supported package lock files found: ${lock_files[*]}. Keep only one of package-lock.json, yarn.lock, or pnpm-lock.yaml in your project root" >&2
    exit 1
  fi

  if (( ${#lock_files[@]} == 0 )); then
    # Normally we would not use exit in a source'd file, but this should fail the job
    echo "Exiting; no supported package lock files found. Add package-lock.json, yarn.lock, or pnpm-lock.yaml to your project root" >&2
    exit 1
  fi

  USES_NPM=false
  USES_YARN=false
  USES_PNPM=false

  case "${lock_files[0]}" in
    package-lock.json)
      USES_NPM=true
      ;;
    yarn.lock)
      USES_YARN=true
      ;;
    pnpm-lock.yaml)
      USES_PNPM=true
      ;;
  esac
}

get_appname_from_package() {
  jq --raw-output '.insights.appname' < "${PACKAGE_JSON_PATH}"
}

if ! APP_NAME=$(get_appname_from_package); then
  echo "could not read application name from package.json"
  exit 1
fi

export APP_NAME

setPackageManager

if [[ "$USES_YARN" == true ]]; then
  # Work around large package timeout; up default from 30s to 5m
  yarn config set network-timeout 300000
fi

install

export BETA=false
build
build_app_info.sh > "${APP_BUILD_DIR}/app.info.json"
server_config_gen.sh
