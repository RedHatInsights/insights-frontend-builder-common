#!/usr/bin/env bash
set -e
set -x

# Check if it is a pull request
# If it is not a pull request, generate the deploy key
if [ "${TRAVIS_PULL_REQUEST}" != "false" ]; then
    echo -e "Pull Request, not pushing a build"
    exit 0;
else
    set +x # Dont set -x here ... keys would be echo'ed to the logs
    openssl aes-256-cbc \
            -K `env | grep 'encrypted_.*_key' | cut -f2 -d '='` \
            -iv `env | grep 'encrypted_.*_iv' | cut -f2 -d '='` \
            -in .travis/deploy_key.enc -out .travis/deploy_key -d
    set -x

    chmod 600 .travis/deploy_key
    eval `ssh-agent -s`
    ssh-add .travis/deploy_key
fi

if [ -x .travis/custom_release.sh ]
then
    .travis/custom_release.sh
else
    # If current dev branch is master, push to build repo ci-beta
    if [[ "${TRAVIS_BRANCH}" = "master" ||  "${TRAVIS_BRANCH}" = "main" ]]; then
        .travis/release.sh "ci-beta"
    fi

    # If current dev branch is deployment branch, push to build repo
    if [[ "${TRAVIS_BRANCH}" = "ci-stable" || "${TRAVIS_BRANCH}" = "qa-beta" || "${TRAVIS_BRANCH}" = "qa-stable" || "${TRAVIS_BRANCH}" = "prod-beta" || "${TRAVIS_BRANCH}" = "prod-stable" || "${TRAVIS_BRANCH}" = "qaprodauth-stable" || "${TRAVIS_BRANCH}" = "qaprodauth-beta" || "${TRAVIS_BRANCH}" = "stage-beta" || "${TRAVIS_BRANCH}" = "stage-stable" ]]; then
        .travis/release.sh "${TRAVIS_BRANCH}"
    fi
fi

# Ignore custom release so we can build repo nightly
if [ "${TRAVIS_BRANCH}" = "nightly" ]; then
    .travis/nightly.sh
    .travis/release.sh "nightly-stable"
fi
