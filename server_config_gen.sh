#!/bin/bash

export LC_ALL=en_US.utf-8
export LANG=en_US.utf-8
export GIT_COMMIT=$(git rev-parse HEAD)

NODE_ROOT=$APP_ROOT${APP_DIR:-}
APP_NAME=$(node -e "console.log(require(\"${NODE_ROOT}/package.json\").insights.appname)")
NPM_INFO="undefined"
PATTERNFLY_DEPS="undefined"
export USES_CADDY=true
SERVER_NAME=${SERVER_NAME:-$APP_NAME}

function generate_caddy_config() {

  local ROUTE_PATH=${ROUTE_PATH:-"/apps/${APP_NAME}"}

  # The spacing on the bash format here makes the closing bracket 
  # look odd, but it's fine.
  echo "{
    {\$CADDY_TLS_MODE}
    auto_https disable_redirects
    servers {
      metrics
    }
}

:9000 {
    metrics /metrics
  }
  
  :8000 {
    {\$CADDY_TLS_CERT}
    log

    # Handle main app route
    @app_match {
        path ${ROUTE_PATH}*
    }
    handle @app_match {
        uri strip_prefix ${ROUTE_PATH}
        file_server * {
            root /srv/${DIST_FOLDER}
            browse
        }
    }

    handle / {
        redir /apps/chrome/index.html permanent
    }
} 
    " > "$APP_ROOT/Caddyfile"
}

function generate_dockerfile() {
  cat << EOF > "$APP_ROOT/Dockerfile"
  FROM quay.io/redhat-services-prod/hcm-eng-prod-tenant/caddy-ubi:0d6954b

  COPY LICENSE /licenses/

  ENV CADDY_TLS_MODE http_port 8000

  COPY ./Caddyfile /etc/caddy/Caddyfile
  COPY dist /srv/dist/
  COPY ./package.json /srv
EOF

}

function generate_docker_ignore() {
  cat << EOF > "$APP_ROOT/.dockerignore"
  node_modules
  .git
EOF
}

function generate_app_info() {
  if [[ -f package-lock.json ]] || [[ -f yarn.lock ]];
  then
    LINES=$(npm list --silent --depth=0 --production | grep @patternfly -i | sed -E "s/^(.{0})(.{4})/\1/" | tr "\n" "," | sed -E "s/,/\",\"/g")
    PATTERNFLY_DEPS="[\"${LINES%???}\"]"
    LINES=$(npm list --silent --depth=0 --production | grep @redhat-cloud-services -i | sed -E "s/^(.{0})(.{4})/\1/" | tr "\n" "," | sed -E "s/,/\",\"/g")
    RH_CLOUD_SERVICES_DEPS="[\"${LINES%???}\"]"
  else
    PATTERNFLY_DEPS="[]"
    RH_CLOUD_SERVICES_DEPS="[]"
  fi
  
  echo "{
  \"app_name\": \"$APP_NAME\",
  \"src_hash\": \"$GIT_COMMIT\",
  \"patternfly_dependencies\": $PATTERNFLY_DEPS,
  \"rh_cloud_services_dependencies\": $RH_CLOUD_SERVICES_DEPS
  }" > ./app.info.json
}


# Now we check for a Caddyfile and if it's correct to generate
if [[ -f $APP_ROOT/Caddyfile ]]; then
    echo "Caddy config already exists, skipping generation"
else
    generate_caddy_config;
fi

# Generate Dockerfile based on config
if [[ -f $APP_ROOT/Dockerfile ]]; then
  echo "Dockerfile already exists, skipping generation"
else
  generate_dockerfile
fi

if [[ -f $APP_ROOT/.dockerignore ]]; then
  echo "Docker ignore already exists, skipping generation"
else
  generate_docker_ignore
fi

# Generate app info and app info deps
if [[ -n "${APP_BUILD_DIR:-}" &&  -d $APP_BUILD_DIR ]]
then
  cd "$APP_BUILD_DIR"
else
  cd "$NODE_ROOT/dist" || cd "$NODE_ROOT/build"
fi

if [[ -f ./app.info.deps.json ]]; then
  echo "app.info.deps.json already exists, skipping generation"
else
  echo $NPM_INFO > ./app.info.deps.json
fi

if [[ -f ./app.info.json ]]; then
  echo "app.info.json already exists, skipping generation"
else
  generate_app_info
fi
