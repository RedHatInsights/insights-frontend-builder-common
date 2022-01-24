#!/bin/bash

# --------------------------------------------
# Export vars for helper scripts to use
# --------------------------------------------
export APP_NAME=$(node -e 'console.log(require("./package.json").insights.appname)')
export CONTAINER_NAME="$APP_NAME-pr-check-$ghprbPullId"
export IMAGE="quay.io/cloudservices/$COMPONENT-frontend"
export IMAGE_TAG=$(git rev-parse --short=7 HEAD)
COMMON_BUILDER=https://raw.githubusercontent.com/RedHatInsights/insights-frontend-builder-common/master

function teardown_docker() {
  docker rm -f $CONTAINER_NAME || true
}

trap "teardown_docker" EXIT SIGINT SIGTERM

set -ex
# NOTE: Make sure this volume is mounted 'ro', otherwise Jenkins cannot clean up the
# workspace due to file permission errors; the Z is used for SELinux workarounds
# -e NODE_BUILD_VERSION can be used to specify a version other than 12
docker run -i --name $CONTAINER_NAME \
  -v $PWD:/workspace:ro,Z \
  -e QUAY_USER=$QUAY_USER \
  -e QUAY_TOKEN=$QUAY_TOKEN \
  -e NODE_BUILD_VERSION=$NODE_BUILD_VERSION \
  quay.io/bholifie/frontend-builder:v0.0.19
TEST_RESULT=$?

if [ $TEST_RESULT -ne 0 ]; then
  echo "Test failure observed; aborting"
  teardown_docker
  exit 1
fi

# Extract files needed to build contianer
mkdir -p $WORKSPACE/build
docker cp $CONTAINER_NAME:/container_workspace/ $WORKSPACE/build
cd $WORKSPACE/build/container_workspace/ && export APP_ROOT="$WORKSPACE/build/container_workspace/"

# ---------------------------
# Build and Publish to Quay
# ---------------------------

# Set expiry for PR images
if [[ $ghprbPullId -ne "master" ]] || [[ $ghprbPullId -ne "main" ]]; then
  echo "LABEL quay.expires-after=3d" >> $APP_ROOT/Dockerfile # tag expires in 3 days
fi

curl -sSL $COMMON_BUILDER/src/quay_push.sh | bash -s

teardown_docker
