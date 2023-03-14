#!/bin/bash

# --------------------------------------------
# Export vars for helper scripts to use
# --------------------------------------------
export APP_NAME=$(node -e "console.log(require(\"${WORKSPACE:-.}${APP_DIR:-}/package.json\").insights.appname)")
export CONTAINER_NAME="$APP_NAME-build-main"
# main IMAGE var is exported from the pr_check.sh parent file
export IMAGE_TAG=$(git rev-parse --short=7 HEAD)
export IS_PR=false
COMMON_BUILDER=https://raw.githubusercontent.com/RedHatInsights/insights-frontend-builder-common/master

function teardown_docker() {
  docker rm -f $CONTAINER_NAME || true
}

trap "teardown_docker" EXIT SIGINT SIGTERM

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


#!/bin/bash

# This function looks back through the git history and attempts to find the last 6 build images
# on quay. We attempt to pull 6 images, files from the images are copied out inot subdirecotries of .history
function getHistory() {
  #Set a container name
  HISTORY_CONTAINER_NAME = $APP_NAME-history
  HISTORY_DEPTH = 6
  HISTORY_FOUND_IMAGES = 0
  mkdir .history
  for REF in $(git log $IMAGE_TAG --first-parent --oneline --format='format:%h' --abbrev=7 )
  do
    SINGLE_IMAGE = $IMAGE:$REF-single
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


# Job name will contain pr-check or build-master. $GIT_BRANCH is not populated on a
# manually triggered build
if echo $JOB_NAME | grep -w "pr-check" > /dev/null; then
  if [ ! -z "$ghprbPullId" ]; then
    export IMAGE_TAG="pr-${ghprbPullId}-${IMAGE_TAG}"
    CONTAINER_NAME="${APP_NAME}-pr-check-${ghprbPullId}"
  fi

  if [ ! -z "$gitlabMergeRequestIid" ]; then
    export IMAGE_TAG="pr-${gitlabMergeRequestIid}-${IMAGE_TAG}"
    CONTAINER_NAME="${APP_NAME}-pr-check-${gitlabMergeRequestIid}"
  fi

  IS_PR=true
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
  -e CI_ROOT=$CI_ROOT \
  -e NODE_BUILD_VERSION=$NODE_BUILD_VERSION \
  -e SERVER_NAME=$SERVER_NAME \
  -e INCLUDE_CHROME_CONFIG \
  -e CHROME_CONFIG_BRANCH \
  --add-host stage.foo.redhat.com:127.0.0.1 \
  --add-host prod.foo.redhat.com:127.0.0.1 \
  quay.io/cloudservices/frontend-build-container:2e1c8c0
TEST_RESULT=$?

if [ $TEST_RESULT -ne 0 ]; then
  echo "Test failure observed; aborting"
  teardown_docker
  exit 1
fi

# Extract files needed to build contianer
mkdir -p $WORKSPACE/build
mkdir -p $WORKSPACE/build_original
docker cp $CONTAINER_NAME:/container_workspace/ $WORKSPACE/build_original
docker cp $CONTAINER_NAME:/container_workspace/ $WORKSPACE/build
cd $WORKSPACE/build/container_workspace/ && export APP_ROOT="$WORKSPACE/build/container_workspace/"



# ---------------------------
# Build and Publish to Quay
# ---------------------------

if [ $IS_PR = true ]; then
  echo $'\n'>> $APP_ROOT/Dockerfile
  # downstream developers may remove newline at end of dockerfile
  # this will result in something like
  #   CMD npm run start:containerLABEL quay.expires-after=3d
  # instead of
  #   CMD npm run start:container
  #   LABEL quay.expires-after=3d
  echo "LABEL quay.expires-after=3d" >> $APP_ROOT/Dockerfile # tag expires in 3 days
else
  echo "Publishing to Quay without expiration"
fi

# source <(curl -sSL $COMMON_BUILDER/src/quay_push.sh | bash -s)

# IMAGE, IMAGE_TAG, and Tokens are exported from upstream pr_check.sh
export LC_ALL=en_US.utf-8
export LANG=en_US.utf-8
export APP_ROOT=${APP_ROOT:-pwd}
export WORKSPACE=${WORKSPACE:-$APP_ROOT}  # if running in jenkins, use the build's workspace
# export IMAGE_TAG=$(git rev-parse --short=7 HEAD)
export GIT_COMMIT=$(git rev-parse HEAD)


if [[ -z "$QUAY_USER" || -z "$QUAY_TOKEN" ]]; then
    echo "QUAY_USER and QUAY_TOKEN must be set"
    exit 1
fi

if [[ -z "$RH_REGISTRY_USER" || -z "$RH_REGISTRY_TOKEN" ]]; then
    echo "RH_REGISTRY_USER and RH_REGISTRY_TOKEN must be set"
    exit 1
fi

if [ $APP_NAME == "chrome" ] ; then
  get_chrome_config;
fi

# Build and push the single image
# single here means it contains only a single copy of the app
# the contents of single images are aggregated into history images
DOCKER_CONF="$PWD/.docker"
mkdir -p "$DOCKER_CONF"
echo $QUAY_TOKEN | docker --config="$DOCKER_CONF" login -u="$QUAY_USER" --password-stdin quay.io
echo $RH_REGISTRY_TOKEN | docker --config="$DOCKER_CONF" login -u="$RH_REGISTRY_USER" --password-stdin registry.redhat.io
docker --config="$DOCKER_CONF" build -t "${IMAGE}:${IMAGE_TAG}-single" $APP_ROOT -f $APP_ROOT/Dockerfile
docker --config="$DOCKER_CONF" push "${IMAGE}:${IMAGE_TAG}-single"

getHistory
copyHistoryBackwardsIntoBuild

docker --config="$DOCKER_CONF" build -t "${IMAGE}:${IMAGE_TAG}" $APP_ROOT -f $APP_ROOT/Dockerfile
docker --config="$DOCKER_CONF" push "${IMAGE}:${IMAGE_TAG}"

teardown_docker
