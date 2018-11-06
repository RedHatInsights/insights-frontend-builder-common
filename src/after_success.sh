#!/usr/bin/env bash
set -e

# Dont set -x here ... keys would be echo'ed to the logs

# Check if it is a pull request
# If it is not a pull request, generate the deploy key
if [ "${TRAVIS_PULL_REQUEST}" != "false" ]; then
    echo -e "Pull Request, not pushing a build"
    exit 0;
else
    openssl aes-256-cbc \
            -K `env | grep 'encrypted_.*_key' | cut -f2 -d '='` \
            -iv `env | grep 'encrypted_.*_iv' | cut -f2 -d '='` \
            -in .travis/deploy_key.enc -out .travis/deploy_key -d

    chmod 600 starter
    eval `ssh-agent -s`
    ssh-add .travis/deploy_key
fi

# If current dev branch is master, push to build repo ci-beta
if [ "${TRAVIS_BRANCH}" = "master" ]; then
    .travis/release.sh "ci-beta"
fi

# If current dev branch is deployment branch, push to build repo
if [[ "${TRAVIS_BRANCH}" = "ci-stable"  || "${TRAVIS_BRANCH}" = "qa-beta" || "${TRAVIS_BRANCH}" = "qa-stable" || "${TRAVIS_BRANCH}" = "prod-beta" || "${TRAVIS_BRANCH}" = "prod-stable" ]]; then
    .travis/release.sh "${TRAVIS_BRANCH}"
fi
