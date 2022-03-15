#!/usr/bin/env bash
set -e
set -x

SRC_HASH=`git rev-parse --verify HEAD`
APP_NAME=$(node -e "console.log(require(\"${WORKSPACE:-.}/package.json\").insights.appname)")
NODE_VERSION=$(node -e "console.log(require(\"${WORKSPACE:-.}/package.json\")?.engines?.node || \"unknown\")")

major_version=0
# Get the major version of node
OLDIFS=$IFS
IFS='.'
read -a versionarr <<< "$NODE_VERSION"
major_version=${versionarr[0]/>=/}

if [[ $major_version == unknown ]]; then
    echo "No node version specified in package.json -> engines!"
else
    if [ $major_version -lt 16 ]; then
        echo "You are using outdated version of node! Please update to LTS. Current version: $NODE_VERSION"
    fi
fi
IFS=$OLDIFS


NPM_INFO="undefined"
# if [ -f package.json ]
# then
#     NPM_INFO=`npm ls --depth=0 --json || true`
# fi

# instead of using -v use -n to check for an empty strings
# -v is not working well on bash 3.2 on osx
PATTERNFLY_DEPS="undefined"
RH_CLOUD_SERVICES_DEPS="undefined"
if [[ -f package-lock.json ]] || [[ -f yarn.lock ]];
then
  LINES=`npm list --silent --depth=0 --production | grep @patternfly -i | sed -E "s/^(.{0})(.{4})/\1/" | tr "\n" "," | sed -E "s/,/\",\"/g"` 
  PATTERNFLY_DEPS="[\"${LINES%???}\"]"
  LINES=`npm list --silent --depth=0 --production | grep @redhat-cloud-services -i | sed -E "s/^(.{0})(.{4})/\1/" | tr "\n" "," | sed -E "s/,/\",\"/g"`
  RH_CLOUD_SERVICES_DEPS="[\"${LINES%???}\"]"
else
  PATTERNFLY_DEPS="[]"
  RH_CLOUD_SERVICES_DEPS="[]"
fi

if [[ -n "$APP_BUILD_DIR" &&  -d $APP_BUILD_DIR ]]
then
    cd $APP_BUILD_DIR
else
    cd dist || cd build
fi

echo $NPM_INFO > ./app.info.deps.json

echo "{
  \"app_name\": \"$APP_NAME\",
  \"node_version\": \"$NODE_VERSION\",
  \"src_hash\": \"$SRC_HASH\",
  \"src_tag\": \"$TRAVIS_TAG\",
  \"src_branch\": \"$TRAVIS_BRANCH\",
  \"patternfly_dependencies\": $PATTERNFLY_DEPS,
  \"rh_cloud_services_dependencies\": $RH_CLOUD_SERVICES_DEPS,
  \"travis\": {
    \"event_type\": \"$TRAVIS_EVENT_TYPE\",
    \"build_number\": \"$TRAVIS_BUILD_NUMBER\",
    \"build_web_url\": \"$TRAVIS_BUILD_WEB_URL\"
  }
}" > ./app.info.json

cp ../.travis/58231b16fdee45a03a4ee3cf94a9f2c3 ./58231b16fdee45a03a4ee3cf94a9f2c3
sed -s "s/__APP_NAME__/$APP_NAME/" -i ./58231b16fdee45a03a4ee3cf94a9f2c3

git config --global user.name $COMMIT_AUTHOR_USERNAME
git config --global user.email $COMMIT_AUTHOR_EMAIL

if git ls-remote --exit-code ${DEPLOY_REPO:-$REPO} $1 &>/dev/null; then
  # Handle where the target branch exists
  git clone --bare --branch $1 --depth 1 ${DEPLOY_REPO:-$REPO} .git
elif git ls-remote --exit-code ${DEPLOY_REPO:-$REPO} HEAD &>/dev/null; then
  # Handle where the target branch doesn't exist but there is a default branch
  git clone --bare --depth 1 ${DEPLOY_REPO:-$REPO} .git
  git update-ref refs/heads/$1 $(git symbolic-ref HEAD)
  git symbolic-ref HEAD refs/heads/$1
else
  # Handle where the repo does not have a default branch (i.e. an empty repo)
  git init
  git remote add origin ${DEPLOY_REPO:-$REPO}
  git commit --allow-empty -m "Initial commit"
  git push origin master
  git checkout -b $1
fi

git config core.bare false
git add -A
git commit -m "${TRAVIS_COMMIT_MESSAGE}"
git push origin $1
