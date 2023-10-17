#!/bin/bash

# -------------------------------------------
# Script Name: frontend-build.sh
# Description:
#   This script automates the process of building frontend containers
#   for the ConsoleDot platform. It includes functions to handle builds for 
#   both regular merges and Pull Requests (PRs). Furthermore ensures required environment 
#   variables are set, logs into registries, builds and pushes the appropriate image tags, 
#   and manages containers.
#
# Usage:
#   Execute this script directly, or source it and call its functions individually
#   for granular control.
#
# Dependencies:
#   - Node.js: Used to fetch the application name from the package.json.
#   - Docker or Podman: Required for building and pushing container images.
#   - External CICD tools: Abstracts the container engine away
#   - Git: Used for various operations, like fetching the latest commit.
#
# Environment Variables:
#   The script uses a variety of environment variables, some mandatory. These can
#   include QUAY_USER, QUAY_TOKEN, RH_REGISTRY_USER, RH_REGISTRY_TOKEN, GIT_BRANCH,
#   WORKSPACE, APP_DIR, and others. These are set by Jenkins in the CI/CD pipeline.
#
# -------------------------------------------

set -ex

export APP_NAME=$(node -p "require('${WORKSPACE:-.}${APP_DIR:-}/package.json').insights.appname")
export IMAGE_TAG=$(cicd::image_builder::get_image_tag)
export CONTAINER_NAME="$APP_NAME-$BRANCH_NAME-$IMAGE_TAG-$(date +%s)"
export NPM_BUILD_SCRIPT="${NPM_BUILD_SCRIPT:-build}"
export YARN_BUILD_SCRIPT="${YARN_BUILD_SCRIPT:-build:prod}"
export LC_ALL=en_US.utf-8
export LANG=en_US.utf-8

BUILD_IMAGE_TAG=c026352
BRANCH_NAME=${GIT_BRANCH#origin/}


build_and_push_aggregated_image() {
  # Guard clause to ensure this function is NOT for PR builds
  if ! cicd::image_builder::is_change_request_context; then
      return
  fi

  # Build and push the -single tagged image
  # This image contains only the current build
  export BUILD_CONTEXT="${APP_ROOT}"
  export LABELS=("image-type=single")
  export ADDITIONAL_TAGS=("${default_tag}-single")
  export CONTAINERFILE_PATH="${APP_ROOT}/Dockerfile"
  export IMAGE_NAME="$IMAGE"
  cicd::image_builder::build_and_push

  # Get the last 6 builds
  get_history

  # Build and push the aggregated image
  # This image is tagged with just the SHA for the current build
  # as this is the one we want deployed
  
  export BUILD_CONTEXT="${APP_ROOT}"
  export LABELS=("image-type=aggregate")
  export CONTAINERFILE_PATH="${APP_ROOT}/Dockerfile"
  export IMAGE_NAME="$IMAGE"
  cicd::image_builder::build_and_push
}

build_and_push_pr_image() {
  # Guard clause to ensure this function is for PR builds
  if cicd::image_builder::is_change_request_context; then
      return
  fi

  export BUILD_CONTEXT="${APP_ROOT}"
  export CONTAINERFILE_PATH="${APP_ROOT}/Dockerfile"
  export IMAGE_NAME="$IMAGE"
  cicd::image_builder::build_and_push
  delete_running_container
}

build_and_setup() {
  # Constants
  local STAGE_HOST="stage.foo.redhat.com"
  local PROD_HOST="prod.foo.redhat.com"

  # NOTE: Make sure this volume is mounted 'ro', otherwise Jenkins cannot clean up the
  # workspace due to file permission errors; the Z is used for SELinux workarounds
  # -e NODE_BUILD_VERSION can be used to specify a version other than 12
  cicd::container::cmd run -i --name "$CONTAINER_NAME" \
    -v "$PWD:/workspace:ro,Z" \
    -e QUAY_USER="$QUAY_USER" \
    -e QUAY_TOKEN="$QUAY_TOKEN" \
    -e APP_DIR="$APP_DIR" \
    -e IS_PR="$IS_PR" \
    -e CI_ROOT="$CI_ROOT" \
    -e NODE_BUILD_VERSION="$NODE_BUILD_VERSION" \
    -e SERVER_NAME="$SERVER_NAME" \
    -e DIST_FOLDER="$DIST_FOLDER" \
    -e INCLUDE_CHROME_CONFIG="$INCLUDE_CHROME_CONFIG" \
    -e CHROME_CONFIG_BRANCH="$CHROME_CONFIG_BRANCH" \
    -e GIT_BRANCH="$GIT_BRANCH" \
    -e BRANCH_NAME="$BRANCH_NAME" \
    -e NPM_BUILD_SCRIPT="$NPM_BUILD_SCRIPT" \
    -e YARN_BUILD_SCRIPT="$YARN_BUILD_SCRIPT" \
    --add-host "$STAGE_HOST":127.0.0.1 \
    --add-host "$PROD_HOST":127.0.0.1 \
    quay.io/cloudservices/frontend-build-container:"$BUILD_IMAGE_TAG"
    
  local RESULT=$?

  if [ $RESULT -ne 0 ]; then
    echo "Build failure observed; aborting"
    delete_running_container
    exit 1
  fi

  # Extract files needed to build container
  mkdir -p "$WORKSPACE/build"
  cicd::container::cmd cp "$CONTAINER_NAME:/container_workspace/" "$WORKSPACE/build"

  delete_running_container
}

delete_running_container() {
  if cicd::container::cmd  ps | grep $CONTAINER_NAME > /dev/null; then
    cicd::container::cmd  rm -f $CONTAINER_NAME || true
  fi
}

get_history() {
  mkdir -p aggregated_history
  
  if [ ! -f frontend-build-history.sh ]; then
    curl https://raw.githubusercontent.com/RedHatInsights/insights-frontend-builder-common/master/src/frontend-build-history.sh > frontend-build-history.sh
    chmod +x frontend-build-history.sh
  fi

  ./frontend-build-history.sh -q $IMAGE -o aggregated_history -c dist -p true -t $QUAY_TOKEN -u $QUAY_USER
}

initialize_environment() {
    # Set default values for directories
    export APP_ROOT="${APP_ROOT:-$(pwd)}"
    export WORKSPACE="${WORKSPACE:-$APP_ROOT}"

    # Change to the desired directory and set APP_ROOT
    mkdir -p "$WORKSPACE/build/container_workspace/"
    cd "$WORKSPACE/build/container_workspace/"
    export APP_ROOT="$WORKSPACE/build/container_workspace/"
}

load_cicd_helper_functions() {
    local LIBRARY_TO_LOAD="$1"
    local cicd_REPO_BRANCH='main'
    local cicd_REPO_ORG='RedHatInsights'
    local cicd_URL="https://raw.githubusercontent.com/${cicd_REPO_ORG}/cicd-tools/${cicd_REPO_BRANCH}/src/bootstrap.sh"
    source <(curl -sSL "$cicd_URL") "$LIBRARY_TO_LOAD"
}

main() {
  # Load the CICD helper scripts
  load_cicd_helper_functions image_builder
  # Ensure we teardown docker on exit
  trap "delete_running_container" EXIT SIGINT SIGTERM
  # Delete any running containers with the same name
  delete_running_container
  # Build the container and copy the files we need
  build_and_setup
  # Set directory paths, update Dockerfile for PR builds, and retrieve the latest git commit hash.
  initialize_environment
  # Build and push the PR image if this is a PR build
  build_and_push_pr_image
  # Build and push the aggregated image if this is NOT a PR build
  build_and_push_aggregated_image
  # clean up
  delete_running_container
}

main
