#!/bin/bash

#dump env
ENV_DUMP=`env`
echo $ENV_DUMP

which podman
podman --version

# --------------------------------------------
# Export vars for helper scripts to use
# --------------------------------------------
package_json_path="${WORKSPACE:-.}${APP_DIR:-}/package.json"
export APP_NAME="$(jq -r '.insights.appname' < "$package_json_path")"

# Caller can set a duration for the image life in quay otherwise it is defaulted to 3 days
: ${QUAY_EXPIRE_TIME:="3d"}

# main IMAGE var is exported from the pr_check.sh parent file
if [[ ! -n "$IMAGE_TAG" ]]; then
    export IMAGE_TAG=$(git rev-parse --short=7 HEAD)
fi

export IS_PR=false
COMMON_BUILDER=https://raw.githubusercontent.com/RedHatInsights/insights-frontend-builder-common/master
EPOCH=$(date +%s)
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

function teardown_podman() {
  podman rm -f $CONTAINER_NAME || true
}

trap "teardown_podman" EXIT SIGINT SIGTERM

# Detect if the container is running
if podman ps | grep $CONTAINER_NAME > /dev/null; then
  # Delete it
  # We do this because an aborted run could leave the container around
  teardown_podman
fi

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

function verifyDependencies() {
  curl https://raw.githubusercontent.com/RedHatInsights/insights-frontend-builder-common/master/src/verify_frontend_dependencies.sh > verify_frontend_dependencies.sh
  chmod +x verify_frontend_dependencies.sh
  ./verify_frontend_dependencies.sh
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
  timestamp=$(date +%s)

  if [ ! -z "$ghprbPullId" ]; then
    export IMAGE_TAG="pr-${ghprbPullId}-${IMAGE_TAG}"
    CONTAINER_NAME="${APP_NAME}-pr-check-${ghprbPullId}-${timestamp}"
  fi

  if [ ! -z "$gitlabMergeRequestIid" ]; then
    export IMAGE_TAG="pr-${gitlabMergeRequestIid}-${IMAGE_TAG}"
    CONTAINER_NAME="${APP_NAME}-pr-check-${gitlabMergeRequestIid}-${timestamp}"
  fi

  IS_PR=true
fi

set -ex


function build() {
  # NOTE: Make sure this volume is mounted 'ro', otherwise Jenkins cannot clean up the
  # workspace due to file permission errors; the Z is used for SELinux workarounds
  # -e NODE_BUILD_VERSION can be used to specify a version other than 12
  podman run -i --name $CONTAINER_NAME \
    -v $PWD:/workspace:ro,Z \
    -e QUAY_USER=$QUAY_USER \
    -e QUAY_TOKEN=$QUAY_TOKEN \
    -e APP_DIR=$APP_DIR \
    -e IS_PR=$IS_PR \
    -e CI_ROOT=$CI_ROOT \
    -e NODE_BUILD_VERSION=$NODE_BUILD_VERSION \
    -e SERVER_NAME=$SERVER_NAME \
    -e DIST_FOLDER \
    -e INCLUDE_CHROME_CONFIG \
    -e CHROME_CONFIG_BRANCH \
    -e GIT_BRANCH \
    -e ROUTE_PATH \
    -e BETA_ROUTE_PATH \
    -e PREVIEW_ROUTE_PATH \
    -e BRANCH_NAME \
    -e NPM_BUILD_SCRIPT \
    -e YARN_BUILD_SCRIPT \
    --add-host stage.foo.redhat.com:127.0.0.1 \
    --add-host prod.foo.redhat.com:127.0.0.1 \
    quay.io/cloudservices/frontend-build-container:latest
  RESULT=$?

  if [ $RESULT -ne 0 ]; then
    echo "Test failure observed; aborting"
    teardown_podman
    exit 1
  fi

  # Extract files needed to build contianer
  mkdir -p $WORKSPACE/build
  podman cp $CONTAINER_NAME:/container_workspace/ $WORKSPACE/build

  teardown_podman
}

podman login -u="$QUAY_USER" --password-stdin quay.io <<< "$QUAY_TOKEN"
podman login -u="$RH_REGISTRY_USER" --password-stdin registry.redhat.io <<< "$RH_REGISTRY_TOKEN"

build  

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
  echo "LABEL quay.expires-after=${QUAY_EXPIRE_TIME}" >> $APP_ROOT/Dockerfile # tag expires in 3 days
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


#PRs shouldn't get the special treatment for history
if [ $IS_PR = true ]; then
  verifyDependencies

  podman  build -t "${IMAGE}:${IMAGE_TAG}" $APP_ROOT -f $APP_ROOT/Dockerfile
  podman  push "${IMAGE}:${IMAGE_TAG}"
  teardown_podman
else
  # Standard build and push
  podman build --label "image-type=single" -t "${IMAGE}:${IMAGE_TAG}-single" "$APP_ROOT" -f "$APP_ROOT/Dockerfile"
  podman push "${IMAGE}:${IMAGE_TAG}-single"
  getHistory
  podman build --label "image-type=aggregate" -t "${IMAGE}:${IMAGE_TAG}" "$APP_ROOT" -f "$APP_ROOT/Dockerfile"
  podman push "${IMAGE}:${IMAGE_TAG}"

  teardown_podman
fi
