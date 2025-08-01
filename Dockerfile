FROM registry.access.redhat.com/ubi9/nodejs-22:9.5-1746535891 as builder

USER root

RUN dnf install jq -y

USER default

RUN npm i -g yarn

# ────────── SENTRY BUILD ARGS ──────────
ARG ENABLE_SENTRY=false
ARG SENTRY_AUTH_TOKEN
ARG SENTRY_RELEASE
ENV ENABLE_SENTRY=${ENABLE_SENTRY} \
    SENTRY_AUTH_TOKEN=${SENTRY_AUTH_TOKEN} \
    SENTRY_RELEASE=${SENTRY_RELEASE}

COPY build-tools/universal_build.sh build-tools/build_app_info.sh build-tools/server_config_gen.sh /opt/app-root/bin/
COPY --chown=default . .

ARG NPM_BUILD_SCRIPT=""
RUN universal_build.sh

FROM quay.io/redhat-services-prod/hcm-eng-prod-tenant/caddy-ubi:latest

COPY LICENSE /licenses/

ENV CADDY_TLS_MODE http_port 8000
# fallback value to the env public path env variable
# Caddy must have a default value for the public path or it will not start
ENV ENV_PUBLIC_PATH "/default"

# Copy the valpop binary from the valpop image
COPY --from=quay.io/redhat-services-prod/hcc-platex-services-tenant/valpop:latest /usr/local/bin/valpop /usr/local/bin/valpop

COPY --from=builder /opt/app-root/src/Caddyfile /etc/caddy/Caddyfile
COPY --from=builder /opt/app-root/src/dist dist
COPY package.json .
