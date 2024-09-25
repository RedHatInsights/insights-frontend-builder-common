#!/usr/bin/env bash

# shellcheck source=/dev/null
source <(curl -sSL https://raw.githubusercontent.com/RedHatInsights/cicd-tools/main/src/bootstrap.sh) image_builder

export CICD_IMAGE_BUILDER_IMAGE_NAME='quay.io/cloudservices/releaser'
export CICD_IMAGE_BUILDER_CONTAINERFILE_PATH='src/releaser.Dockerfile'

cicd::image_builder::build_and_push