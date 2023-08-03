#!/bin/bash


CONTAINER_ENGINE_CMD=''
PREFER_CONTAINER_ENGINE="${PREFER_CONTAINER_ENGINE:-}"

container_engine_cmd() {

    if [ -z "$(get_container_engine_cmd)" ]; then
        if ! set_container_engine_cmd; then
            return 1
        fi
    fi

    if [ "$(get_container_engine_cmd)" = "podman" ]; then
        podman "$@"
    else
        docker "--config=${DOCKER_CONF}" "$@"
    fi
}

get_container_engine_cmd() {
    echo -n "$CONTAINER_ENGINE_CMD"
}

set_container_engine_cmd() {

    if _configured_container_engine_available; then
        CONTAINER_ENGINE_CMD="$PREFER_CONTAINER_ENGINE"
    else
        if container_engine_available 'podman'; then
            CONTAINER_ENGINE_CMD='podman'
        elif container_engine_available 'docker'; then
            CONTAINER_ENGINE_CMD='docker'
        else
            echo "ERROR, no container engine found, please install either podman or docker first"
            return 1
        fi
    fi

    echo "Container engine selected: $CONTAINER_ENGINE_CMD"
}

_configured_container_engine_available() {

    local CONTAINER_ENGINE_AVAILABLE=1

    if [ -n "$PREFER_CONTAINER_ENGINE" ]; then
        if container_engine_available "$PREFER_CONTAINER_ENGINE"; then
            CONTAINER_ENGINE_AVAILABLE=0
        else
            echo "WARNING!: specified container engine '${PREFER_CONTAINER_ENGINE}' not present, finding alternative..."
        fi
    fi

    return "$CONTAINER_ENGINE_AVAILABLE"
}

container_engine_available() {

    local CONTAINER_ENGINE_TO_CHECK="$1"
    local CONTAINER_ENGINE_AVAILABLE=1

    if _command_is_present "$CONTAINER_ENGINE_TO_CHECK"; then
        if [[ "$CONTAINER_ENGINE_TO_CHECK" != "docker" ]] || ! _docker_seems_emulated; then
            CONTAINER_ENGINE_AVAILABLE=0
        fi
    fi
    return "$CONTAINER_ENGINE_AVAILABLE"
}

_command_is_present() {
    command -v "$1" > /dev/null 2>&1
}

_docker_seems_emulated() {

    local DOCKER_COMMAND_PATH
    DOCKER_COMMAND_PATH=$(command -v docker)

    if [[ $(file "$DOCKER_COMMAND_PATH") == *"ASCII text"* ]]; then
        return 0
    fi
    return 1
}

#dump env
ENV_DUMP=`env`
echo $ENV_DUMP

container_engine_cmd --version

exit 99
# --------------------------------------------
# Export vars for helper scripts to use
# --------------------------------------------
export APP_NAME=$(node -e "console.log(require(\"${WORKSPACE:-.}${APP_DIR:-}/package.json\").insights.appname)")


# main IMAGE var is exported from the pr_check.sh parent file
export IMAGE_TAG=$(git rev-parse --short=7 HEAD)
export IS_PR=false
COMMON_BUILDER=https://raw.githubusercontent.com/RedHatInsights/insights-frontend-builder-common/master
EPOCH=$(date +%s)
BUILD_IMAGE_TAG=353f5b8
# Get current git branch
# The current branch is going to be the GIT_BRANCH env var but with origin/ stripped off
if [[ $GIT_BRANCH == origin/* ]]; then
    BRANCH_NAME=${GIT_BRANCH:7}
else
    BRANCH_NAME=$GIT_BRANCH
fi
# We want to be really, really, really sure we have a unique container name
export CONTAINER_NAME="$APP_NAME-$BRANCH_NAME-$IMAGE_TAG-$EPOCH"

#The BUILD_SCRIPT env var is used in the frontend build container
#and is the script we run with NPM at build time
#the default is build, but we give apps the option to override
if [ -z "$NPM_BUILD_SCRIPT" ]; then
  export NPM_BUILD_SCRIPT="build"
fi
if [ -z "$YARN_BUILD_SCRIPT" ]; then
  export YARN_BUILD_SCRIPT="build:prod"
fi

export BETA=false

# If branch name is one of these:
# 'master', 'qa-beta', 'ci-beta', 'prod-beta', 'main', 'devel', 'stage-beta'
# then we need to set BETA to true
# this list is taken from https://github.com/RedHatInsights/frontend-components/blob/master/packages/config/index.js#L8
if [[ $BRANCH_NAME =~ ^(master|qa-beta|ci-beta|prod-beta|main|devel|stage-beta)$ ]]; then
    export BETA=true
fi

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


function getHistory() {
  mkdir aggregated_history
  curl https://raw.githubusercontent.com/RedHatInsights/insights-frontend-builder-common/master/src/frontend-build-history.sh > frontend-build-history.sh
  chmod +x frontend-build-history.sh
  ./frontend-build-history.sh -q $IMAGE -o aggregated_history -c dist -p true -t $QUAY_TOKEN -u $QUAY_USER
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


function build() {
  local OUTPUT_DIR=$1
  local IS_PREVIEW=$2
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
    -e BETA=$IS_PREVIEW \
    -e NPM_BUILD_SCRIPT \
    -e YARN_BUILD_SCRIPT \
    --add-host stage.foo.redhat.com:127.0.0.1 \
    --add-host prod.foo.redhat.com:127.0.0.1 \
    quay.io/cloudservices/frontend-build-container:$BUILD_IMAGE_TAG 
  RESULT=$?

  if [ $RESULT -ne 0 ]; then
    echo "Test failure observed; aborting"
    teardown_docker
    exit 1
  fi

  # Extract files needed to build contianer
  mkdir -p $OUTPUT_DIR
  docker cp $CONTAINER_NAME:/container_workspace/ $OUTPUT_DIR

  teardown_docker
}



# Run a stable build
# this will result in a $WORKSPACE/build/container_workspace directory that has build, dist, and the Dcokerfile and what not
# dist and the Caddyfile and stuff will be copied from here into the container
build $WORKSPACE/build false

# Run a preview build
build $WORKSPACE/build/preview true

# Copy the preview build output so its gets picked up in the copy from the stable dist
cp -r $WORKSPACE/build/preview/container_workspace/dist $WORKSPACE/build/container_workspace/dist/preview

# Set the APP_ROOT
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

# Chrome isn't currently using our config, don't need this complexity for now
# Not deleting, as we may need to re-enable later
#if [ $APP_NAME == "chrome" ] ; then
  # get_chrome_config;
#fi

DOCKER_CONFIG="$PWD/.docker"
mkdir -p "$DOCKER_CONFIG"
echo $QUAY_TOKEN | docker  login -u="$QUAY_USER" --password-stdin quay.io
echo $RH_REGISTRY_TOKEN | docker  login -u="$RH_REGISTRY_USER" --password-stdin registry.redhat.io

#PRs shouldn't get the special treatment for history
if [ $IS_PR = true ]; then
  docker  build -t "${IMAGE}:${IMAGE_TAG}" $APP_ROOT -f $APP_ROOT/Dockerfile
  docker  push "${IMAGE}:${IMAGE_TAG}"
  teardown_docker
else
  # Build and push the -single tagged image
  # This image contains only the current build
  docker  build --label "image-type=single" -t "${IMAGE}:${IMAGE_TAG}-single" $APP_ROOT -f $APP_ROOT/Dockerfile
  docker  push "${IMAGE}:${IMAGE_TAG}-single"

  # Get the the last 6 builds
  getHistory

  # Build and push the aggregated image
  # This image is tagged with just the SHA for the current build
  # as this is the one we want deployed
  docker  build --label "image-type=aggregate" -t "${IMAGE}:${IMAGE_TAG}" $APP_ROOT -f $APP_ROOT/Dockerfile
  docker  push "${IMAGE}:${IMAGE_TAG}"

  teardown_docker
fi
