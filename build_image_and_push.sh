#!/bin/bash

set -exv

export WORKSPACE=${WORKSPACE:-$(pwd)} # if running in jenkins, use the build's workspace
export CICD_IMAGE_BUILDER_IMAGE_NAME='quay.io/cloudservices/releaser'
export CICD_IMAGE_BUILDER_CONTAINERFILE_PATH="${WORKSPACE}/src/releaser.Dockerfile"

generate_junit_report_stub() {

    mkdir -p "${WORKSPACE}/artifacts"

    cat <<- EOF > "${WORKSPACE}/artifacts/junit-dummy.xml"
	<testsuite tests="1">
	    <testcase classname="dummy" name="dummytest"/>
	</testsuite>
	EOF
}

CICD_TOOLS_URL="https://raw.githubusercontent.com/RedHatInsights/cicd-tools/main/src/bootstrap.sh"
# shellcheck source=/dev/null
source <(curl -sSL "$CICD_TOOLS_URL") image_builder

cicd::image_builder::build_and_push

generate_junit_report_stub
