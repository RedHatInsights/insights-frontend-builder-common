#!/bin/bash

# ----------------------------------------------------------------------------
# Script Name: build_app_info.sh
# Description: outputs to STDOUT a JSON containing various
#              pieces of information about a Node.js application and its
#              dependencies. The generated JSON includes the application
#              name, Node.js version, source hash, source tag, source branch,
#              PatternFly dependencies, and Red Hat Cloud Services
#              dependencies, gleaned from the git environment and package.json.
#
# Usage:       ./build_app_info.sh
#
# Parameters:  None
#
# Dependencies: The script requires `jq` and `node` to be installed, and expects
#               to be run in a git repository directory to extract certain
#               pieces of source information.
# ----------------------------------------------------------------------------

export PACKAGE_JSON_PATH=${PACKAGE_JSON_PATH:-package.json}

get_package_value() {
  local key="$1"

  jq ".${key} // \"unknown\" " --raw-output < $PACKAGE_JSON_PATH
}

# handle_npm_list
# Purpose: Retrieve a comma-separated list of dependency versions for a given scope.
# Parameters:
#   - dependency_scope: A string to grep for in the npm list, e.g. a scope or package name.
# Usage: handle_npm_list <dependency_scope>
# Example: handle_npm_list "@patternfly"
handle_npm_list() {
  local dependency_scope="$1"

  # Check if a lock file exists, suggesting that the node_modules directory is present.
  if [[ -f package-lock.json ]] || [[ -f yarn.lock ]]; then
    # Retrieve and format the dependency list. If unsuccessful, return an empty string.
    local dep_list
    dep_list=$(npm list --silent --depth=0 --production | grep "$dependency_scope" -i | sed -E "s/^(.{0})(.{4})/\1/" | tr "\n" "," | sed -E "s/,/\",\"/g" || echo "")

    # Check if the dependency list is empty and log an error message if so.
    if [[ -z "$dep_list" ]]; then
      echo "Error: No dependencies matching '$dependency_scope' found." >&2
      echo "" # Return an empty string as the function result.
    else
      echo "$dep_list"
    fi
  else
    # If no lock file is present, log an error message and return an empty string.
    echo "Error: No package-lock.json or yarn.lock file found. Cannot retrieve dependency list for '$dependency_scope'." >&2
    echo ""
  fi
}

get_git_branch() {
  local branch

  # 1. Direct branch name (works on regular checkouts)
  branch=$(git branch --show-current 2>/dev/null)
  if [[ -n "$branch" ]]; then
    echo "$branch"
    return
  fi

  # 2. Symbolic ref (fails in detached HEAD but worth trying)
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [[ -n "$branch" && "$branch" != "HEAD" ]]; then
    echo "$branch"
    return
  fi

  # 3. Find remote branch(es) pointing at HEAD (detached HEAD in CI)
  branch=$(git branch -r --points-at HEAD 2>/dev/null | head -1 | sed 's|.*/||' | xargs)
  if [[ -n "$branch" ]]; then
    echo "$branch"
    return
  fi

  # 4. CI environment variable fallbacks
  for var in SOURCE_GIT_BRANCH GITHUB_HEAD_REF GITHUB_REF_NAME GIT_BRANCH BRANCH_NAME; do
    if [[ -n "${!var:-}" ]]; then
      # Strip any refs/heads/ prefix
      echo "${!var##*/}"
      return
    fi
  done

  echo "unknown"
}

get_git_tag() {
  local tag

  # 1. Describe the current commit's nearest tag
  tag=$(git describe --tags --abbrev=0 2>/dev/null)
  if [[ -n "$tag" ]]; then
    echo "$tag"
    return
  fi

  # 2. Check for tags directly pointing at HEAD (shallow clones may lack history)
  tag=$(git tag --points-at HEAD 2>/dev/null | head -1)
  if [[ -n "$tag" ]]; then
    echo "$tag"
    return
  fi

  # 3. CI environment variable fallback (set via Dockerfile build arg)
  if [[ -n "${SOURCE_GIT_TAG:-}" ]]; then
    echo "$SOURCE_GIT_TAG"
    return
  fi

  echo "unknown"
}

get_git_hash() {
  local hash
  hash=$(git rev-parse --verify HEAD 2>/dev/null)
  if [[ -n "$hash" ]]; then
    echo "$hash"
    return
  fi

  echo "unknown"
}

SRC_HASH=$(get_git_hash)
APP_NAME=$(get_package_value "insights.appname")
NODE_VERSION=$(get_package_value "engines.node")
SRC_BRANCH=$(get_git_branch)
SRC_TAG=$(get_git_tag)
APP_VERSION=${APP_VERSION:-unknown}

PATTERNFLY_DEPS=$(handle_npm_list "@patternfly")
RH_CLOUD_SERVICES_DEPS=$(handle_npm_list "@redhat-cloud-services")
PATTERNFLY_DEPS="[\"${PATTERNFLY_DEPS%???}\"]"
RH_CLOUD_SERVICES_DEPS="[\"${RH_CLOUD_SERVICES_DEPS%???}\"]"

# JSON generation with `jq`
jq -n \
  --arg an "$APP_NAME" \
  --arg nv "$NODE_VERSION" \
  --arg sh "$SRC_HASH" \
  --arg st "$SRC_TAG" \
  --arg sb "$SRC_BRANCH" \
  --arg av "$APP_VERSION" \
  --arg pd "$PATTERNFLY_DEPS" \
  --arg rh "$RH_CLOUD_SERVICES_DEPS" \
  '{
    app_name: $an,
    node_version: $nv,
    src_hash: $sh,
    src_tag: $st,
    src_branch: $sb,
    app_version: $av,
    patternfly_dependencies: $pd,
    rh_cloud_services_dependencies: $rh
  }'
