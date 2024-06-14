verifyDependencies() {
  package_json=$(cat package.json)
  # Initialize an array to store error messages
  errors=()
  url="https://api.github.com/repos/${ghprbGhRepository}/issues/${ghprbPullId}/comments"

  delete_comments() {
    comments=$(curl  -s -L \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      $url)
      comment_ids=($(echo "$comments" | jq -r '.[] | select(.user.login=="InsightsDroid") | .id'))

    # Remove old bot comments
    for id in "${comment_ids[@]}"; do
      curl -s -L \
      -X DELETE \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      https://api.github.com/repos/${ghprbGhRepository}/issues/comments/${id} > /dev/null 2>&1
    done
  }

  post_comments() {
    local errors=("$@")

    # Prepare the comment body
    comment_body="## :exclamation: Outdated dependencies error\n"
    for error in "${errors[@]}"; do
      comment_body+="* $error\n"
    done

    # Post the errors as a single comment
    curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -X POST -d "{\"body\":\"$comment_body\"}" "$url" > /dev/null 2>&1
  }

  check_version() {
    package=$1
    required_version=$2

    # Get the installed version
    installed_version=$(echo "$package_json" | jq -r ".dependencies.\"$package\"")

    if [[ -z "$installed_version" || "$installed_version" == "null" ]]; then
      # check dev dependcies as well
      installed_version=$(echo "$package_json" | jq -r ".devDependencies.\"$package\"")
    fi

    # remove ranges and pre-release tags
    installed_version=$(echo "$installed_version" | awk -F'-' '{print $1}' | sed 's/^[^0-9]//')

    # Check if the installed version is not null
    if [[ -z "$installed_version" || "$installed_version" == "null" ]]; then
      # ignore packages that are not installed 
      return
    fi

    # Compare the versions
    if [[ $(printf '%s\n' "$required_version" "$installed_version" | sort -V | head -n 1) != "$required_version" ]]; then
      errors+=("Installed version of $package ($installed_version) is older than required version ($required_version)")
    fi
  }

  declare -A requirements=(
    ["react"]="18.0.0"
    ["react-dom"]="18.0.0"
    ["react-router-dom"]="6.0.0"
    ["@redhat-cloud-services/frontend-components-config"]="6.0.0"
    ["@patternfly/react-core"]="5.0.0"
    ["@patternfly/react-icons"]="5.0.0"
  )

  for package in "${!requirements[@]}"; do
    check_version "$package" "${requirements[$package]}"
  done

  delete_comments
  # If there are any errors, print them and send a GH comment
  if [[ ${#errors[@]} -ne 0 ]]; then
    printf '%s\n' "${errors[@]}"
    post_comments "${errors[@]}"
  fi
}

remote_url=$(git config --get remote.origin.url)

if [[ $remote_url == *github.com* ]]; then
  verifyDependencies
elif [[ $remote_url == *gitlab.com* ]]; then
  # TODO: Implement GitLab dependency verification
  echo "GitLab dependency verification is not implemented yet"
fi
