#!/bin/bash

# Local build script for front ends
# This script is used to build the front end locally
# Use this to test the frontend build system locally when making changes

# Usage:
# 1. Clone a frontend like https://github.com/RedHatInsights/edge-frontend/
# 2. Copy this file into the root of the repo
# 3. Run the script
# 4. Run the container podman run -p 8000:8000 localhost/edge:5316bd7
# 5. Open the app in your browser at http://localhost:8000/apps/edge 
#
# Note: You can find the image name and tag by looking at the output of the script
# or by running `podman images`. Also, fill in the app name in the URL with the 
# app you are testing

# --------------------------------------------
# Export vars for helper scripts to use
# --------------------------------------------
export WORKSPACE=$(pwd)
export APP_NAME=$(node -e "console.log(require(\"${WORKSPACE:-.}${APP_DIR:-}/package.json\").insights.appname)")
export CONTAINER_NAME="$APP_NAME-build-main"
# main IMAGE var is exported from the pr_check.sh parent file
export IMAGE="$APP_NAME-build-main"
export IMAGE_TAG=$(git rev-parse --short=7 HEAD)
export IS_PR=false
COMMON_BUILDER=https://raw.githubusercontent.com/RedHatInsights/insights-frontend-builder-common/master

# Get the chrome config from cloud-services-config
function get_chrome_config() {
  # Create the directory we're gonna plop the config files in
  if [ -d $APP_ROOT/chrome_config ]; then
    rm -rf $APP_ROOT/chrome_config;
  fi
  mkdir -p $APP_ROOT/chrome_config;

  # If the env var is not set, we don't want to include the config
  if [ -z ${INCLUDE_CHROME_CONFIG+x} ] ; then
    return 0
  fi
  # If the env var is set to anything but true, we don't want to include the config
  if [[ "${INCLUDE_CHROME_CONFIG}" != "true" ]]; then
    return 0
  fi
  # If the branch isn't set in the env, we want to use the default
  if [ -z ${CHROME_CONFIG_BRANCH+x} ] ; then
    CHROME_CONFIG_BRANCH="ci-stable";
  fi
  # belt and braces mate, belt and braces
  if [ -d $APP_ROOT/cloud-services-config ]; then
    rm -rf $APP_ROOT/cloud-services-config;
  fi

  # Clone the config repo
  git clone --branch $CHROME_CONFIG_BRANCH https://github.com/RedHatInsights/cloud-services-config.git;
  # Copy the config files into the chrome_config dir
  cp -r cloud-services-config/chrome/* $APP_ROOT/chrome_config/;
  # clean up after ourselves? why not
  rm -rf cloud-services-config;
  # we're done here
  return 0
}

# This function looks back through the git history and attempts to find the last 6 build images
# on quay. We attempt to pull 6 images, files from the images are copied out inot subdirecotries of .history
function getHistory() {
  #Set a container name
  HISTORY_CONTAINER_NAME=$APP_NAME-history
  HISTORY_DEPTH=6
  HISTORY_FOUND_IMAGES=0
  mkdir .history
  for REF in $(git log $IMAGE_TAG --first-parent --oneline --format='format:%h' --abbrev=7 )
  do
    SINGLE_IMAGE=$IMAGE:$REF-single
    echo "Looking for $SINGLE_IMAGE"
    # Pull the image
    docker pull $SINGLE_IMAGE
    # if the image is not found skip to the next loop
    if [ $? -ne 0 ]; then
      echo "Image not found"
      continue
    fi
    # Increment FOUND_IMAGES
    HISTORY_FOUND_IMAGES=$((HISTORY_FOUND_IMAGES+1))

    #if thecontainer is running 
    if [ $(docker ps -q -f name=$HISTORY_CONTAINER_NAME) ]; then
      # Stop and delete the container
      docker stop $HISTORY_CONTAINER_NAME
      docker rm $HISTORY_CONTAINER_NAME
    fi

    # Make the history level directory
    mkdir .history/$HISTORY_DEPTH

    #Decrement history depth
    HISTORY_DEPTH=$((HISTORY_DEPTH-1))

    # Run the image
    docker run -d --name $HISTORY_CONTAINER_NAME $SINGLE_IMAGE

    # Copy the files out of the docker container into the history level directory
    docker cp $HISTORY_CONTAINER_NAME:/opt/app-root/src/build .history/$HISTORY_DEPTH

    # if we've found 6 images we're done
    if [ $HISTORY_FOUND_IMAGES -eq 6 ]; then
      echo "Processed 6 images for history"
      break
    fi
  done
}

function copyHistoryBackwardsIntoBuild() {
  #clear out workspace build
  rm -rf $WORKSPACE/build
  mkdir $WORKSPACE/build

  # Copy the files from the history level directories into the build directory
  for i in {6..1}
  do
    if [ -d .history/$i ]; then
      cp -r .history/$i/* $WORKSPACE/build
    fi
  done

  # Copy the files from the current build into the build directory
  cp -r $WORKSPACE/build_original/* $WORKSPACE/build
}


set -ex
# NOTE: Make sure this volume is mounted 'ro', otherwise Jenkins cannot clean up the
# workspace due to file permission errors; the Z is used for SELinux workarounds
# -e NODE_BUILD_VERSION can be used to specify a version other than 12
docker run -i --name $CONTAINER_NAME \
  -v $PWD:/workspace:ro,Z \
  -e APP_DIR=$APP_DIR \
  -e IS_PR=$IS_PR \
  -e CI_ROOT=$CI_ROOT \
  -e NODE_BUILD_VERSION=$NODE_BUILD_VERSION \
  -e SERVER_NAME=$SERVER_NAME \
  -e INCLUDE_CHROME_CONFIG \
  -e CHROME_CONFIG_BRANCH \
  quay.io/cloudservices/frontend-build-container:9c23443
TEST_RESULT=$?

if [ $TEST_RESULT -ne 0 ]; then
  echo "Test failure observed; aborting"
  exit 1
fi

# Extract files needed to build contianer
mkdir -p $WORKSPACE/build
docker cp $CONTAINER_NAME:/container_workspace/ $WORKSPACE/build
cd $WORKSPACE/build/container_workspace/ && export APP_ROOT="$WORKSPACE/build/container_workspace/"


if [ $APP_NAME == "chrome" ] ; then
  get_chrome_config;
fi

docker build -t "${APP_NAME}:${IMAGE_TAG}-single" $APP_ROOT -f $APP_ROOT/Dockerfile

getHistory
copyHistoryBackwardsIntoBuild

docker build -t "${IMAGE}:${IMAGE_TAG}" $APP_ROOT -f $APP_ROOT/Dockerfile
