#!/bin/bash
set -e
set -x

COMMON_URL="https://raw.githubusercontent.com/RedHatInsights/insights-frontend-builder-common/master"
CHROME_URL="https://raw.githubusercontent.com/RedHatInsights/insights-chrome/master"
curl $COMMON_URL/src/nightly.sh > .travis/nightly.sh
curl $COMMON_URL/src/after_success.sh > .travis/after_success.sh
curl $COMMON_URL/src/release.sh > .travis/release.sh
curl $COMMON_URL/src/Jenkinsfile > .travis/58231b16fdee45a03a4ee3cf94a9f2c3

chmod 755 .travis/*sh
.travis/after_success.sh
