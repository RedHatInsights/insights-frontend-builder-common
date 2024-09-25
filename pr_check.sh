#!/bin/bash

# shellcheck source=/dev/null
source <(curl -sSL https://raw.githubusercontent.com/RedHatInsights/cicd-tools/main/src/bootstrap.sh) common

if ! ./build_deploy.sh; then
  echo "Error building image"
  exit 1
fi

if cicd::common::is_ci_context; then
  # Stubbed out for now
  mkdir 'artifacts'
  cat << EOF > 'artifacts/junit-dummy.xml'
  <testsuite tests="1">
      <testcase classname="dummy" name="dummytest"/>
  </testsuite>
EOF
fi