FROM registry.access.redhat.com/ubi9/nodejs-22:9.5-1741637231 as builder

USER root

RUN dnf install jq -y

USER default

RUN npm i -g yarn

COPY ./universal_build.sh ./build_app_info.sh ./server_config_gen.sh /opt/app-root/bin/
COPY --chown=default . .

RUN universal_build.sh

FROM quay.io/redhat-services-prod/hcm-eng-prod-tenant/caddy-ubi:0d6954b

COPY LICENSE /licenses/

ENV CADDY_TLS_MODE http_port 8000

COPY --from=builder /opt/app-root/src/Caddyfile /etc/caddy/Caddyfile
COPY --from=builder /opt/app-root/src/dist dist
COPY package.json .
