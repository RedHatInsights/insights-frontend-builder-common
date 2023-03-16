#!/bin/bash

# Show timestamps, don't exit on error
set -x

# Globals
SINGLETAG="-single"       # used for looking up single build images
Color_Off='\033[0m'       # Text Reset
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White
HISTORY_CONTAINER_NAME="frontend-build-history"
SINGLE_IMAGE_FOUND=false
OUTPUT_DIR=false
CURRENT_BUILD_DIR=false
BRANCH=false
QUAYREPO=false

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
  echo -e "   ${Blue}HISTORY: ${Green}$1${Color_Off} - $2"
}

function printError() {
   echo -e "  ${Blue}HISTORY: ${Red}$1${Color_Off} - $2"
}

function getArgs() {
  while getopts ":b:q:o:c" opt; do
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
      \? )
        echo "Invalid option -$OPTARGV" >&2
        ;;
    esac
  done
}

function makeHistoryDirectories() {
  rm -ef .history
  mkdir .history
  # Make the history level directories
  for i in {1..6}
  do
    mkdir .history/$i
  done
}

function getGitHistory() {
  # Get the git history
  git log --first-parent --oneline --format='format:%h' --abbrev=7 > .history/git_history
}



function getBuildImages() {
  # We count the number of images found to make sure we don't go over 6
  local HISTORY_FOUND_IMAGES=0
  # We track the history found backwards, from 6 down, because we need to build
  # history cumulative from the oldest to the newest
  local HISTORY_DEPTH=6
  local SINGLE_IMAGE=""
  local USE_SINGLE_TAG=true
  local ITERATIONS=0
  if [ ! -z "$1" ]; then
    USE_SINGLE_TAG=false
  fi
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
    SINGLE_IMAGE=$QUAYREPO:$REF$SINGLETAG
    if [ $USE_SINGLE_TAG == false ]; then
      SINGLE_IMAGE=$QUAYREPO:$REF
    fi
    printSuccess "Pulling single-build image" $SINGLE_IMAGE
    # Pull the image
    docker pull $SINGLE_IMAGE
    # if the image is not found skip to the next loop
    if [ $? -ne 0 ]; then
      printError "Image not found" $SINGLE_IMAGE
      continue
    fi
    SINGLE_IMAGE_FOUND=true
    printSuccess "Single-build image found" $SINGLE_IMAGE
    # Increment FOUND_IMAGES
    HISTORY_FOUND_IMAGES=$((HISTORY_FOUND_IMAGES+1))
    # Run the image
    docker run -d --name $HISTORY_CONTAINER_NAME $SINGLE_IMAGE
    # Copy the files out of the docker container into the history level directory
    docker cp $HISTORY_CONTAINER_NAME:/opt/app-root/src/build .history/$HISTORY_DEPTH
    # Stop the image
    docker stop $HISTORY_CONTAINER_NAME
    # delete the container
    docker rm $HISTORY_CONTAINER_NAME
    # if we've found 6 images we're done
    if [ $HISTORY_FOUND_IMAGES -eq 6 ]; then
      printSuccess "Found 6 single-build images, stopping history search" $SINGLE_IMAGE
      break
    fi
    #Decrement history depth
    HISTORY_DEPTH=$((HISTORY_DEPTH-1))
  done
}

function copyHistoryIntoOutputDir() {
  # Clear out the output doirectory
  rm -rf $OUTPUT_DIR/*

  # Copy the files from the history level directories into the build directory
  for i in {6..1}
  do
    if [ -d .history/$i ]; then
      cp -r .history/$i/* $OUTPUT_DIR
    fi
  done

  # Copy the original build into the output directory
  cp -r $CURRENT_BUILD_DIR/* $OUTPUT_DIR
}

function main() {
  getArgs $@
  validateArgs
  makeHistoryDirectories
  getGitHistory
  GET_SINGLE_IMAGES=true
  getBuildImages $GET_SINGLE_IMAGES
  if [ $SINGLE_IMAGE_FOUND == false ]; then
    # If we are in this block then no images were found with the single tag
    # this means we are probably building history for the first time
    # if we didn't have this block then we would never initiate the history build
    # process
    printError "No single-tagged images found." "Using non-single-tagged images instead."
    GET_SINGLE_IMAGES=false
    getBuildImages $GET_SINGLE_IMAGES
  fi
  copyHistoryIntoOutputDir
}

main $@