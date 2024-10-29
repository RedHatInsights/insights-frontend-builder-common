#!/bin/bash

if [[ -z "$IMAGE" ]]; then
  echo "IMAGE not defined!"
  exit 1
fi

# Set to not empty to force using local path scripts (for testing in change request context)
FORCE_LOCAL_SCRIPT_PATHS="${FORCE_LOCAL_SCRIPT_PATHS:-}"

#dump env
ENV_DUMP=`env`
echo "$ENV_DUMP"

which docker
docker --version

WORKSPACE=${WORKSPACE:-$(pwd)}

# --------------------------------------------
# Export vars for helper scripts to use
# --------------------------------------------
package_json_path="${WORKSPACE:-.}${APP_DIR:-}/package.json"
export APP_NAME="$(jq -r '.insights.appname' < "$package_json_path")"

# Caller can set a duration for the image life in quay otherwise it is defaulted to 3 days
: "${QUAY_EXPIRE_TIME:="3d"}"

if [[ "$GIT_BRANCH" == *"security-compliance"* ]]; then
    # if we're coming from security-compliance, override the IMAGE_TAG. Ignoring anything from the parent
    export IMAGE_TAG="sc-$(date +%Y%m%d)-$(git rev-parse --short=7 HEAD)"
elif [[ -z "$IMAGE_TAG" ]]; then
    # otherwise, respect IMAGE_TAG coming from the parent pr_check.sh file
    export IMAGE_TAG=$(git rev-parse --short=7 HEAD)
fi

export IS_PR=false
COMMON_BUILDER_REPOSITORY_ORG="${COMMON_BUILDER_REPOSITORY_ORG:-RedHatInsights}"
COMMON_BUILDER_REPOSITORY_NAME="${COMMON_BUILDER_REPOSITORY_NAME:-insights-frontend-builder-common}"
COMMON_BUILDER_REPOSITORY_BRANCH="${COMMON_BUILDER_REPOSITORY_BRANCH:-master}"

running_in_ci() {
    [[ "$CI" == "true" ]]
}

if ! running_in_ci || [[ -n "$FORCE_LOCAL_SCRIPT_PATHS" ]]; then
  COMMON_BUILDER_BASE_URL="file://$(cd "$(dirname "$0")" && pwd)"
else
  COMMON_BUILDER_BASE_URL="https://raw.githubusercontent.com/${COMMON_BUILDER_REPOSITORY_ORG}/${COMMON_BUILDER_REPOSITORY_NAME}/${COMMON_BUILDER_REPOSITORY_BRANCH}/src"
fi

# Get current git branch
# The current branch is going to be the GIT_BRANCH env var but with origin/ stripped off
if [[ $GIT_BRANCH == origin/* ]]; then
    BRANCH_NAME=${GIT_BRANCH:7}
else
    BRANCH_NAME=$GIT_BRANCH
fi
# We want to be really, really, really sure we have a unique container name
export CONTAINER_NAME="$APP_NAME-$BRANCH_NAME-$IMAGE_TAG-$(date +%s)"

#The BUILD_SCRIPT env var is used in the frontend build container
#and is the script we run with NPM at build time
#the default is build, but we give apps the option to override
if [ -z "$NPM_BUILD_SCRIPT" ]; then
  export NPM_BUILD_SCRIPT="build"
fi
if [ -z "$YARN_BUILD_SCRIPT" ]; then
  export YARN_BUILD_SCRIPT="build:prod"
fi

teardown_docker() {
  if _container_exists "$CONTAINER_NAME"; then
    docker rm -f "$CONTAINER_NAME"
  fi
}

_container_exists() {
    local name="$1"
    docker ps -a --format "{{.Names}}" |  grep "$name" -q
}

_get_fbc_script() {
  local name="$1"

  if ! curl -sLOf "${COMMON_BUILDER_BASE_URL}/${name}"; then
    echo "couldn't download the script: '${name}'"
    return 1
  fi
  if ! chmod +x "$name"; then
    echo "could not set execution permissions for '${name}'"
    return 1
  fi
}

trap "teardown_docker" EXIT

function verifyDependencies() {
  if ! _get_fbc_script 'verify_frontend_dependencies.sh'; then
    return 1
  fi
  ./verify_frontend_dependencies.sh
}

function getHistory() {
  if ! _get_fbc_script 'frontend-build-history.sh'; then
    return 1
  fi

  mkdir aggregated_history
  ./frontend-build-history.sh -q "$IMAGE" -o aggregated_history -c dist -p true -t "$QUAY_TOKEN" -u "$QUAY_USER"
}

#FIXME this is not actually true in all cases
# Job name will contain pr-check or build-master. $GIT_BRANCH is not populated on a
# manually triggered build
if grep -wq 'pr-check' <<< "$JOB_NAME"; then
  timestamp=$(date +%s)


#FIXME Refactor
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

##TODO check which env variables are required here ...
build() {
  # NOTE: Make sure this volume is mounted 'ro', otherwise Jenkins cannot clean up the
  # workspace due to file permission errors; the Z is used for SELinux workarounds
  # -e NODE_BUILD_VERSION can be used to specify a version other than 12
  docker run -i --name $CONTAINER_NAME \
    --pull=always \
    -v $PWD:/workspace:ro,Z \
    -e QUAY_USER=$QUAY_USER \
    -e QUAY_TOKEN=$QUAY_TOKEN \
    -e GLITCHTIP_TOKEN=$GLITCHTIP_TOKEN \
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
    quay.io/cloudservices/frontend-build-container:948c169
  RESULT=$?

  if [ $RESULT -ne 0 ]; then
    echo "Test failure observed; aborting"
    exit 1
  fi


  if [[ -d "$WORKSPACE/build/container_workspace" ]]; then
    rm -rf "$WORKSPACE/build/container_workspace"
  fi

  # Extract files needed to build container
  mkdir -p $WORKSPACE/build
  docker cp $CONTAINER_NAME:/container_workspace/ $WORKSPACE/build
}

setup_docker_login() {

    DOCKER_CONFIG=$(mktemp -d -p "$HOME" docker_config_XXXXX)
    export DOCKER_CONFIG

    if [[ -z "$QUAY_USER" || -z "$QUAY_TOKEN" ]]; then
        echo "QUAY_USER and QUAY_TOKEN must be set"
        return 1
    fi

    if [[ -z "$RH_REGISTRY_USER" || -z "$RH_REGISTRY_TOKEN" ]]; then
        echo "RH_REGISTRY_USER and RH_REGISTRY_TOKEN must be set"
        return 1
    fi

    docker login -u="$QUAY_USER" --password-stdin quay.io <<< "$QUAY_TOKEN"
    docker login -u="$RH_REGISTRY_USER" --password-stdin registry.redhat.io <<< "$RH_REGISTRY_TOKEN"

}

if running_in_ci && ! setup_docker_login; then
    echo "Error configuring Docker login"
    exit 1
fi

build

# Set the APP_ROOT
#cd $WORKSPACE/build/container_workspace && export APP_ROOT="$WORKSPACE/build/container_workspace"
export APP_ROOT="$WORKSPACE/build/container_workspace"
#FIXME avoid jumping around
cd "$APP_ROOT"

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
  #FIXME this should not modify a project's Dockerfile, and be handled like a label when building
  echo "LABEL quay.expires-after=${QUAY_EXPIRE_TIME}" >> $APP_ROOT/Dockerfile # tag expires in 3 days
else
  echo "Publishing to Quay without expiration"
fi

# IMAGE, IMAGE_TAG, and Tokens are exported from upstream pr_check.sh
export LC_ALL=en_US.utf-8
export LANG=en_US.utf-8
export APP_ROOT=${APP_ROOT:-pwd}
export WORKSPACE=${WORKSPACE:-$APP_ROOT}  # if running in jenkins, use the build's workspace
export GIT_COMMIT=$(git rev-parse HEAD)

#PRs shouldn't get the special treatment for history
if [ $IS_PR = true ]; then
  verifyDependencies

  docker  build -t "${IMAGE}:${IMAGE_TAG}" $APP_ROOT -f $APP_ROOT/Dockerfile
  if running_in_ci; then
    docker push "${IMAGE}:${IMAGE_TAG}"
  fi
else
  # Standard build and push
  docker build --label "image-type=single" -t "${IMAGE}:${IMAGE_TAG}-single" "$APP_ROOT" -f "$APP_ROOT/Dockerfile"
  if running_in_ci; then
    docker push "${IMAGE}:${IMAGE_TAG}-single"
  fi
  getHistory
  docker build --label "image-type=aggregate" -t "${IMAGE}:${IMAGE_TAG}" "$APP_ROOT" -f "$APP_ROOT/Dockerfile"
  if running_in_ci; then
    docker push "${IMAGE}:${IMAGE_TAG}"
  fi
fi
