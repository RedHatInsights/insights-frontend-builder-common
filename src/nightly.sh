#!/usr/bin/env bash
set -e
set -x

# show remotes
git remote -v

git pull origin master

# show branches
git branch -a

# Rest branch to master so cron job takes care of all the work
git reset --hard master

# install packages
npm install @patternfly/patternfly@latest
npm install @patternfly/react-core@prerelease
npm install @patternfly/react-tokens@prerelease
npm install @patternfly/react-icons@latest
npm install @patternfly/react-charts@prerelease

# Echo version numbers for deugging
echo "using @patternfly/patternfly version " npm show @patternfly/patternfly version
echo "using @patternfly/react-core version " npm show @patternfly/react-core version
echo "using @patternfly/react-tokens version " npm show @patternfly/react-tokens version
echo "using @patternfly/react-icons " npm show @patternfly/react-icons version
echo "using @patternfly/react-charts " npm show @patternfly/react-charts version

# Lint + Test
npm run lint
npm run test

# build it
NODE_ENV=production webpack --config config/prod.webpack.config.js
