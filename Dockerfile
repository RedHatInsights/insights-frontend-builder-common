FROM registry.access.redhat.com/ubi9/nodejs-22:9.7-1770021428 as builder

USER root

RUN dnf install jq -y

USER default

RUN npm i -g yarn

# ────────── SENTRY BUILD ARGS ──────────
# NOTE:
# Tekton/Konflux passes values like --build-arg ENABLE_SENTRY=true and
# --build-arg SENTRY_RELEASE=<commit SHA> during the build.
# ARG makes them available only at build-time.
# The ENV line copies them into the final container so they persist at runtime,
# letting Node (process.env.ENABLE_SENTRY, process.env.SENTRY_RELEASE, etc.)
# and other tools read them.
ARG ENABLE_SENTRY=false
ARG SENTRY_AUTH_TOKEN
ARG SENTRY_RELEASE
ENV ENABLE_SENTRY=${ENABLE_SENTRY} \
  SENTRY_AUTH_TOKEN=${SENTRY_AUTH_TOKEN} \
  SENTRY_RELEASE=${SENTRY_RELEASE}
ARG NPM_BUILD_SCRIPT=""

# Persist yarn build script at runtime.
ARG YARN_BUILD_SCRIPT=""
ARG USES_YARN=false
ENV YARN_BUILD_SCRIPT=${YARN_BUILD_SCRIPT} \
  USES_YARN=${USES_YARN}
ARG APP_BUILD_DIR=dist
ARG PACKAGE_JSON_PATH=package.json
ENV PACKAGE_JSON_PATH=${PACKAGE_JSON_PATH}

COPY build-tools/universal_build.sh build-tools/build_app_info.sh build-tools/server_config_gen.sh /opt/app-root/bin/
COPY --chown=default . .

RUN chmod +x build-tools/parse-secrets.sh

# 👉 Mount one secret with many keys; universal_build.sh handles the rest
USER root
RUN --mount=type=secret,id=build-container-additional-secret/secrets,required=false \
  universal_build.sh
USER default


FROM quay.io/redhat-services-prod/hcm-eng-prod-tenant/caddy-ubi:latest

COPY LICENSE /licenses/

ENV CADDY_TLS_MODE http_port 8000
# fallback value to the env public path env variable
# Caddy must have a default value for the public path or it will not start
ENV ENV_PUBLIC_PATH "/default"

ARG APP_BUILD_DIR=dist
ARG PACKAGE_JSON_PATH=package.json

# Copy the valpop binary from the valpop image
COPY --from=quay.io/redhat-services-prod/hcc-platex-services-tenant/valpop:latest /usr/local/bin/valpop /usr/local/bin/valpop

COPY --from=builder /opt/app-root/src/Caddyfile /etc/caddy/Caddyfile
COPY --from=builder /opt/app-root/src/${APP_BUILD_DIR} dist
COPY ${PACKAGE_JSON_PATH} .
