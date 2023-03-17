#!/bin/bash

# Don't exit on error
# we need to trap errors to handle cerain conditions
set +e
# show comamnds being run
set -x

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
# we use the same name each time we spin up a container to copy stuff out of
# makes it easier
HISTORY_CONTAINER_NAME="frontend-build-history"
# If no -single images are found we set this to true
# allows us to move into a special mode where we use non-single tagged images
# only used for first time hisotry builds
#SINGLE_IMAGE_FOUND=false
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

function quayLogin() {
  echo $QUAY_TOKEN | docker --config="$DOCKER_CONF" login -u="$QUAY_USER" --password-stdin quay.io
}

function debugMode() {
  if [ $DEBUG_MODE == true ]; then
    set -x
  fi
}

function validateArgs() {
  if [ -z "$QUAYREPO" ]; then
    printError "Error" "Quay repo is required"
    exit 1
  fi
  if [ -z "$OUTPUT_DIR" ]; then
    printError "Error" "Output directory is required"
    exit 1
  fi
  if [ -z "$CURRENT_BUILD_DIR" ]; then
    printError "Error" "Current build directory is required"
    exit 1
  fi
}

function printSuccess() {
  echo -e "${Blue}HISTORY: ${Green}$1${Color_Off} - $2"
}

function printError() {
   echo -e "${Blue}HISTORY: ${Red}$1${Color_Off} - $2"
}

function getArgs() {
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

function makeHistoryDirectories() {
  rm -rf .history
  mkdir .history
  # Make the history level directories
  for i in {1..6}
  do
    mkdir .history/$i
  done
}

function getGitHistory() {
  # Get the git history
  # tail is to omit the first line, which would correspond to the current commit
  git log --first-parent --oneline --format='format:%h' --abbrev=7  | tail -n +2 > .history/git_history
}



function getBuildImages() {
  # We count the number of images found to make sure we don't go over 6
  local HISTORY_FOUND_IMAGES=0
  # We track the history found backwards, from 6 down, because we need to build
  # history cumulative from the oldest to the newest
  local HISTORY_DEPTH=6
  local SINGLE_IMAGE=""
  #local USE_SINGLE_TAG=$1
  local ITERATIONS=0
  local IMAGE_TEXT="Single-build"
  # Get the single build images
  for REF in $(cat .history/git_history)
  do
    # If we've gone 12 iterations then bail
    ITERATIONS=$((ITERATIONS+1))
    if [ $ITERATIONS -eq 12 ]; then
      printError "Exiting image search after 12 iterations." ""
      break
    fi
    # A "single image" is an images with its tag postpended with "-single"
    # these images contain only a single build of the frontend
    # example: quay.io/cloudservices/api-frontend:7b1b1b1-single
    SINGLE_IMAGE=$QUAYREPO:$REF-$SINGLETAG
    IMAGE_TEXT="Single-build"

    #if [ $USE_SINGLE_TAG == false ]; then
    #  SINGLE_IMAGE=$QUAYREPO:$REF
    #  IMAGE_TEXT="Fallback build"
    #fi
    printSuccess "Pulling single-build image" $SINGLE_IMAGE
    # Pull the image
    docker pull $SINGLE_IMAGE >/dev/null 2>&1
    # if the image is not found trying falling back to a non-single tagged build
    if [ $? -ne 0 ]; then
      SINGLE_IMAGE=$QUAYREPO:$REF
      IMAGE_TEXT="Fallback build"
      printError "Image not found. Trying build not tagged single." $SINGLE_IMAGE
      docker pull $SINGLE_IMAGE >/dev/null 2>&1
      if [ $? -ne 0 ]; then
        printError "Fallback build not found. Skipping." $SINGLE_IMAGE
        continue
      fi
    fi
    #SINGLE_IMAGE_FOUND=true
    printSuccess "$IMAGE_TEXT image found" $SINGLE_IMAGE
    # Increment FOUND_IMAGES
    HISTORY_FOUND_IMAGES=$((HISTORY_FOUND_IMAGES+1))
    # Run the image
    docker rm -f $HISTORY_CONTAINER_NAME #>/dev/null 2>&1
    docker run -d --name $HISTORY_CONTAINER_NAME $SINGLE_IMAGE #>/dev/null 2>&1
    # If the run fails log out and move to next
    if [ $? -ne 0 ]; then
      printError "Failed to run image" $SINGLE_IMAGE
      continue
    fi
    printSuccess "Running $IMAGE_TEXT image" $SINGLE_IMAGE
    # Copy the files out of the docker container into the history level directory
    docker cp $HISTORY_CONTAINER_NAME:/opt/app-root/src/dist/. .history/$HISTORY_DEPTH #>/dev/null 2>&1
    # if this fails try build
    # This block handles a corner case. Some apps (one app actually, just chrome)
    # may use the build directory instead of the dist directory.
    # we assume dist, because that's the standard, but if we don't find it we try build
    # if a build copy works then we change the output dir to build so thaat we end up with 
    # history in the finaly container
    if [ $? -ne 0 ]; then
      printError "Couldn't find dist on image, trying build..." $SINGLE_IMAGE
      docker cp $HISTORY_CONTAINER_NAME:/opt/app-root/src/build/. .history/$HISTORY_DEPTH #>/dev/null 2>&1
      # If the copy fails log out and move to next
      if [ $? -ne 0 ]; then
        printError "Failed to copy files from image" $SINGLE_IMAGE
        continue
      fi
      # Set the current build dir to build instead of dist
      CURRENT_BUILD_DIR="build"
    fi
    printSuccess "Copied files from $IMAGE_TEXT image" $SINGLE_IMAGE
    #if [ $GET_SINGLE_IMAGES == false ]; then
    #  tagAndPushSingleImage $SINGLE_IMAGE
    #fi
    # Stop the image
    docker stop $HISTORY_CONTAINER_NAME >/dev/null 2>&1
    # delete the container
    docker rm -f $HISTORY_CONTAINER_NAME >/dev/null 2>&1
    # if we've found 6 images we're done
    if [ $HISTORY_FOUND_IMAGES -eq 6 ]; then
      printSuccess "Found 6 images, stopping history search" $SINGLE_IMAGE
      break
    fi
    #Decrement history depth
    HISTORY_DEPTH=$((HISTORY_DEPTH-1))
  done
}

function tagAndPushSingleImage() {
  # Guard on PUSH_SINGLE_IMAGES
  # If the PUSH_SINGLE_IMAGES flag is false then we never engage this
  # feature
  if [ $PUSH_SINGLE_IMAGES == false ]; then
    return 0
  fi
  local SINGLE_IMAGE=$1
  # Tag HISTORY_CONTAINER_NAME with SHA-single
  docker tag $SINGLE_IMAGE "${SINGLE_IMAGE}-single"
  # Push the image
  docker push "${SINGLE_IMAGE}-single"
  # if the push fails log out and move to next
  if [ $? -ne 0 ]; then
    printError "Failed to push image" $SINGLE_IMAGE
    return 1
  fi
  # Log out success
  printSuccess "Pushed single image" $SINGLE_IMAGE
  return 0
}

function copyHistoryIntoOutputDir() {
  # Copy the files from the history level directories into the build directory
  for i in {6..1}
  do
    if [ -d .history/$i ]; then
      cp -rf .history/$i/* $OUTPUT_DIR
      # if copy failed log an error
      if [ $? -ne 0 ]; then
        printError "Failed to copy files from history level: " $i
        return 1
      fi
      printSuccess "Copied files from history level: " $i
    fi
  done
}

function copyCurrentBuildIntoOutputDir() {
  # Copy the original build into the output directory
  cp -rf $CURRENT_BUILD_DIR/* $OUTPUT_DIR
  if [ $? -ne 0 ]; then
    printError "Failed to copy files from current build dir" $CURRENT_BUILD_DIR
    return
  fi
  printSuccess "Copied files from current build dir" $CURRENT_BUILD_DIR
}

function copyOutputDirectoryIntoCurrentBuild() {
  # Copy the output directory into the current build directory
  cp -rf $OUTPUT_DIR/* $CURRENT_BUILD_DIR
  if [ $? -ne 0 ]; then
    printError "Failed to copy files from output dir" $OUTPUT_DIR
    return
  fi
  printSuccess "Copied files from output dir" $OUTPUT_DIR
}

function deleteBuildContainer() {
  # Delete the build container
  docker rm -f $HISTORY_CONTAINER_NAME #>/dev/null 2>&1
  if [ $? -ne 0 ]; then
    printError "Failed to delete build container" $HISTORY_CONTAINER_NAME
    return
  fi
  printSuccess "Deleted build container" $HISTORY_CONTAINER_NAME
}

function main() {
  getArgs $@
  validateArgs
  debugMode
  deleteBuildContainer
  makeHistoryDirectories
  getGitHistory
  quayLogin
  getBuildImages
  #if [ $SINGLE_IMAGE_FOUND == false ]; then
  #  # If we are in this block then no images were found with the single tag
  #  # this means we are probably building history for the first time
  #  # if we didn't have this block then we would never initiate the history build
  #  # process
  #  printError "No single-tagged images found." "Using non-single-tagged images instead."
  #  GET_SINGLE_IMAGES=false
  #  getBuildImages $GET_SINGLE_IMAGES
  #fi
  copyHistoryIntoOutputDir
  copyCurrentBuildIntoOutputDir
  copyOutputDirectoryIntoCurrentBuild
  printSuccess "History build complete" "Files available at $CURRENT_BUILD_DIR"
  deleteBuildContainer
}

main $@