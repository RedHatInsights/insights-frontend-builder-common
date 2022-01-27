#!/bin/bash

NODE_DEFAULT_VERSION=16
# Grab the Jenkins workspace
# /workspace is mounted by the container
# /container_workspace is created by the Dockerfile
cp -r /workspace/. /container_workspace
cd /container_workspace

# nvm is not a binary, but an alias that needs to be sourced.
source ~/.bash_profile
if [[ -z $NODE_BUILD_VERSION ]]; then
    echo "Using Node ${NODE_DEFAULT_VERSION} by default; use NODE_BUILD_VERSION to override."
    nvm install $NODE_DEFAULT_VERSION && nvm use $NODE_DEFAULT_VERSION
else 
    nvm install $NODE_BUILD_VERSION && nvm use $NODE_BUILD_VERSION
fi
export APP_NAME=`node -e 'console.log(require("./package.json").insights.appname)'`
export APP_ROOT=/container_workspace

set -exv

npm ci

if [ $IS_PR = true ]; then
    npm run verify
else
    npm run build
fi
source /container_workspace/nginx_conf_gen.sh
