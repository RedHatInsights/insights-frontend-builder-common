#!/usr/bin/env bash
set -e
set -x

# Update the remote, travis only pulls one branch
git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
git remote update

# Rest branch to master so cron job takes care of all the work
git reset --hard remotes/origin/master

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
