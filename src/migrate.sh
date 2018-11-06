#!/bin/bash
set -e
APP_NAME=$1

if [[ ! -n "$APP_NAME" ]]
then
    echo "Error include the app name as a parameter (ex: migrate.sh advisor)";
    exit 1
fi

rm -rf .travis/*sh

git mv ./deploy_key.enc .travis/

sed -s 's|- .travis/after_success.sh|- curl -sSL https://raw.githubusercontent.com/RedHatInsights/insights-frontend-builder-common/master/src/bootstrap.sh \| bash -s|' -i .travis.yml

node -e "const pkg = require(\"./package.json\")
pkg.insights = { appname: \"$APP_NAME\" }
console.log(JSON.stringify(pkg, false, 2))
" > package.json.tmp

mv package.json.tmp package.json

