#!/bin/bash

# Grab the Jenkins workspace
# /workspace is mounted by the container
# /container_workspace is created by the Dockerfile
cp -r /workspace/. /container_workspace
cd /container_workspace

# nvm is not a binary, but an alias that needs to be sourced.
source ~/.bash_profile
nvm install $NODE_BUILD_VERSION && nvm use $NODE_BUILD_VERSION

set -exv
npm ci
npm run verify
source /container_workspace/nginx_conf_gen.sh
