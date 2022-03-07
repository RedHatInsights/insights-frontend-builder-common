#!/bin/bash

# --------------------------------------------
# Export vars for helper scripts to use
# --------------------------------------------
export APP_NAME=$(node -e "console.log(require(\"${WORKSPACE:-.}${APP_DIR:-}/package.json\").insights.appname)")
export CONTAINER_NAME="$APP_NAME-pr-check-$ghprbPullId"
export IMAGE="quay.io/cloudservices/$COMPONENT-frontend"
export IMAGE_TAG=$(git rev-parse --short=7 HEAD)
export IS_PR=true
COMMON_BUILDER=https://raw.githubusercontent.com/RedHatInsights/insights-frontend-builder-common/master

function teardown_docker() {
  docker rm -f $CONTAINER_NAME || true
}

trap "teardown_docker" EXIT SIGINT SIGTERM

# Job name will container pr-check or build-master. $GIT_BRANCH is not populated on a
# manually triggered build
if echo $JOB_NAME | grep -w "build-master" > /dev/null; then
  CONTAINER_NAME="$APP_NAME-build-main"
  IS_PR=false
fi

set -ex
# NOTE: Make sure this volume is mounted 'ro', otherwise Jenkins cannot clean up the
# workspace due to file permission errors; the Z is used for SELinux workarounds
# -e NODE_BUILD_VERSION can be used to specify a version other than 12
docker run -i --name $CONTAINER_NAME \
  -v $PWD:/workspace:ro,Z \
  -e QUAY_USER=$QUAY_USER \
  -e QUAY_TOKEN=$QUAY_TOKEN \
  -e APP_DIR=$APP_DIR \
  -e IS_PR=$IS_PR \
  -e NODE_BUILD_VERSION=$NODE_BUILD_VERSION \
  quay.io/cloudservices/frontend-build-container:580aaa3
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

if [ $IS_PR = true ]; then
  echo "LABEL quay.expires-after=3d" >> $APP_ROOT/Dockerfile # tag expires in 3 days
else
  echo "Publishing to Quay without expiration"
fi

curl -sSL $COMMON_BUILDER/src/quay_push.sh | bash -s

teardown_docker
