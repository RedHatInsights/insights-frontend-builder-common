#!/bin/bash

# -------------------------------------------
# Script Name: Frontend Build History Aggregator
# Description:
#   This script is designed to retrieve and aggregate the build history of frontend containers
#   for applications deployed on the ConsoleDot platform. The main goal is to gather
#   historical builds (typically the last 6 builds) and compile them into a current directory.
#
#   Features:
#   - Supports both 'single-build' and 'fallback' tagged images from Quay.
#   - Provides colorful terminal output for clear status tracking.
#   - Employs error handling and logging to streamline debugging and traceability.
#   - Uses an external CICD helper script to manage container interactions.
#
# Usage:
#   Run this script with appropriate command-line arguments. Ensure you provide necessary
#   information like Quay repo, output directory, and current build directory.
#
# Dependencies:
#   - Docker: Required for pulling and interacting with container images.
#   - Git: Used for fetching historical commits.
#   - External CICD tools: Expects functions from a CICD script hosted on GitHub.
#   - Bash utilities: grep, mkdir, rm, cp, etc.
#
# Arguments:
#   This script expects command-line arguments to specify Quay repo, current build directory,
#   output directory, debug mode, etc. Use `-h` or refer to `get_args()` function for specifics.
#
# -------------------------------------------

# Don't exit on error
# we need to trap errors to handle cerain conditions
set +e

# Globals
SINGLETAG="single" # used for looking up single build images
Color_Off='\033[0m' # What? I like colors.
Black='\033[0;30m'
Red='\033[0;31m'
Green='\033[0;32m'
Yellow='\033[0;33m'
Blue='\033[0;34m'
Purple='\033[0;35m'
Cyan='\033[0;36m'
White='\033[0;37m'
# The name of the container we use to build history
HISTORY_CONTAINER_NAME="frontend-build-history-$(date +%s)"
# where we send our full aggregated history to
OUTPUT_DIR=false
# where the current build is located
CURRENT_BUILD_DIR=false
# the quay repo we need to interact with
QUAYREPO=false
# debug mode. turns on verbose output.
DEBUG_MODE=false
# We first check for images tagged -single. If we don't find any we use normal SHA tagged images
# if this is true we will then take those SHA tagged images, retag them SHA-single, and push those back
# up. This is so subsequent builds will find -single images
PUSH_SINGLE_IMAGES=false
# Our default mode is to get images tagged -single
GET_SINGLE_IMAGES=true

#Quay Stuff
DOCKER_CONF="$PWD/.docker"
QUAY_TOKEN=""
QUAY_USER=""

load_cicd_helper_functions() {
    local LIBRARY_TO_LOAD="$1"
    local CICD_TOOLS_REPO_BRANCH='main'
    local CICD_TOOLS_REPO_ORG='RedHatInsights'
    local CICD_TOOLS_URL="https://raw.githubusercontent.com/${CICD_TOOLS_REPO_ORG}/cicd-tools/${CICD_TOOLS_REPO_BRANCH}/src/bootstrap.sh"
    source <(curl -sSL "$CICD_TOOLS_URL") "$LIBRARY_TO_LOAD"
}

quay_login() {
  echo $QUAY_TOKEN | cicd::container::cmd --config="$DOCKER_CONF" login -u="$QUAY_USER" --password-stdin quay.io
}

debug_mode() {
  if [ $DEBUG_MODE == true ]; then
    set -x
  fi
}

validate_args() {
  if [ -z "$QUAYREPO" ]; then
    print_error "Error" "Quay repo is required"
    exit 1
  fi
  if [ -z "$OUTPUT_DIR" ]; then
    print_error "Error" "Output directory is required"
    exit 1
  fi
  if [ -z "$CURRENT_BUILD_DIR" ]; then
    print_error "Error" "Current build directory is required"
    exit 1
  fi
}

print_success() {
  echo -e "${Blue}HISTORY: ${Green}$1${Color_Off} - $2"
}

print_error() {
   echo -e "${Blue}HISTORY: ${Red}$1${Color_Off} - $2"
}

get_args() {
  while getopts ":b:q:o:c:d:p:t:u:" opt; do
    case $opt in
      # quay.io/cloudservices/api-frontend etc
      q )
        QUAYREPO="$OPTARG"
        ;;
      o )
        OUTPUT_DIR="$OPTARG"
        ;;
      c )
        CURRENT_BUILD_DIR="$OPTARG"
        ;;
      d )
        DEBUG_MODE=true
        ;;
      p )
        PUSH_SINGLE_IMAGES="$OPTARG"
        ;;
      t )
        QUAY_TOKEN="$OPTARG"
        ;;
      u )
        QUAY_USER="$OPTARG"
        ;;
      \? )
        echo "Invalid option -$OPTARGV" >&2
        ;;
    esac
  done
}

make_history_directories() {
  rm -rf .history
  mkdir .history
  # Make the history level directories
  for i in {1..6}
  do
    mkdir .history/$i
  done
}

get_git_history() {
  # Get the git history
  # tail is to omit the first line, which would correspond to the current commit
  git log --first-parent --oneline --format='format:%h' --abbrev=7  | tail -n +2 > .history/git_history
}

get_build_images() {
  # We count the number of images found to make sure we don't go over 6
  local HISTORY_FOUND_IMAGES=0
  # We track the history found backwards, from 6 down, because we need to build
  # history cumulative from the oldest to the newest
  local HISTORY_DEPTH=6
  local SINGLE_IMAGE=""
  local ITERATIONS=0
  local IMAGE_TEXT="Single-build"
  # Get the single build images
  for REF in $(cat .history/git_history)
  do
    # If we've gone 12 iterations then bail
    ITERATIONS=$((ITERATIONS+1))
    if [ $ITERATIONS -eq 12 ]; then
      print_error "Exiting image search after 12 iterations." ""
      break
    fi
    # A "single image" is an images with its tag postpended with "-single"
    # these images contain only a single build of the frontend
    # example: quay.io/cloudservices/api-frontend:7b1b1b1-single
    SINGLE_IMAGE=$QUAYREPO:$REF-$SINGLETAG
    IMAGE_TEXT="Single-build"

    print_success "Pulling single-build image" $SINGLE_IMAGE
    # Pull the image
    cicd::container::cmd pull $SINGLE_IMAGE >/dev/null 2>&1
    # if the image is not found trying falling back to a non-single tagged build
    if [ $? -ne 0 ]; then
      SINGLE_IMAGE=$QUAYREPO:$REF
      IMAGE_TEXT="Fallback build"
      print_error "Image not found. Trying build not tagged single." $SINGLE_IMAGE
      cicd::container::cmd pull $SINGLE_IMAGE >/dev/null 2>&1
      if [ $? -ne 0 ]; then
        print_error "Fallback build not found. Skipping." $SINGLE_IMAGE
        continue
      fi
    fi
    print_success "$IMAGE_TEXT image found" $SINGLE_IMAGE
    # Increment FOUND_IMAGES
    HISTORY_FOUND_IMAGES=$((HISTORY_FOUND_IMAGES+1))
    # Run the image
    cicd::container::cmd rm -f $HISTORY_CONTAINER_NAME >/dev/null 2>&1
    cicd::container::cmd run -d --name $HISTORY_CONTAINER_NAME $SINGLE_IMAGE >/dev/null 2>&1
    # If the run fails log out and move to next
    if [ $? -ne 0 ]; then
      print_error "Failed to run image" $SINGLE_IMAGE
      continue
    fi
    print_success "Running $IMAGE_TEXT image" $SINGLE_IMAGE
    # Copy the files out of the container into the history level directory
    cicd::container::cmd cp $HISTORY_CONTAINER_NAME:/opt/app-root/src/dist/. .history/$HISTORY_DEPTH >/dev/null 2>&1
    # if this fails try build
    # This block handles a corner case. Some apps (one app actually, just chrome)
    # may use the build directory instead of the dist directory.
    # we assume dist, because that's the standard, but if we don't find it we try build
    # if a build copy works then we change the output dir to build so thaat we end up with 
    # history in the finaly container
    if [ $? -ne 0 ]; then
      print_error "Couldn't find dist on image, trying build..." $SINGLE_IMAGE
      cicd::container::cmd cp $HISTORY_CONTAINER_NAME:/opt/app-root/src/build/. .history/$HISTORY_DEPTH >/dev/null 2>&1
      # If the copy fails log out and move to next
      if [ $? -ne 0 ]; then
        print_error "Failed to copy files from image" $SINGLE_IMAGE
        continue
      fi
      # Set the current build dir to build instead of dist
      CURRENT_BUILD_DIR="build"
    fi
    print_success "Copied files from $IMAGE_TEXT image" $SINGLE_IMAGE
    # Stop the image
    cicd::container::cmd stop $HISTORY_CONTAINER_NAME >/dev/null 2>&1
    # delete the container
    cicd::container::cmd rm -f $HISTORY_CONTAINER_NAME >/dev/null 2>&1
    # if we've found 6 images we're done
    if [ $HISTORY_FOUND_IMAGES -eq 6 ]; then
      print_success "Found 6 images, stopping history search" $SINGLE_IMAGE
      break
    fi
    #Decrement history depth
    HISTORY_DEPTH=$((HISTORY_DEPTH-1))
  done
}

copy_history_into_output_directory() {
  # Copy the files from the history level directories into the build directory
  for i in {6..1}
  do
    if [ -d .history/$i ]; then
      cp -rf .history/$i/* $OUTPUT_DIR
      # if copy failed log an error
      if [ $? -ne 0 ]; then
        print_error "Failed to copy files from history level: " $i
        return 1
      fi
      print_success "Copied files from history level: " $i
    fi
  done
}

copy_current_build_into_output_dir() {
  # Copy the original build into the output directory
  cp -rf $CURRENT_BUILD_DIR/* $OUTPUT_DIR
  if [ $? -ne 0 ]; then
    print_error "Failed to copy files from current build dir" $CURRENT_BUILD_DIR
    return
  fi
  print_success "Copied files from current build dir" $CURRENT_BUILD_DIR
}

copy_output_directory_into_current_build() {
  # Copy the output directory into the current build directory
  cp -rf $OUTPUT_DIR/* $CURRENT_BUILD_DIR
  if [ $? -ne 0 ]; then
    print_error "Failed to copy files from output dir" $OUTPUT_DIR
    return
  fi
  print_success "Copied files from output dir" $OUTPUT_DIR
}

delete_build_container() {
  # Delete the build container
  cicd::container::cmd rm -f $HISTORY_CONTAINER_NAME >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    print_error "Failed to delete build container" $HISTORY_CONTAINER_NAME
    return
  fi
  print_success "Deleted build container" $HISTORY_CONTAINER_NAME
}

main() {
  get_args $@
  validate_args
  load_cicd_helper_functions container
  load_cicd_helper_functions image_builder
  debug_mode
  delete_build_container
  make_history_directories
  get_git_history
  quay_login
  get_build_images
  copy_history_into_output_directory
  copy_current_build_into_output_dir
  copy_output_directory_into_current_build
  print_success "History build complete" "Files available at $CURRENT_BUILD_DIR"
  delete_build_container
}

main $@