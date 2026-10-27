FROM quay.io/redhat-services-prod/hcm-eng-prod-tenant/frontend-builder:latest as builder

COPY --chown=default . .

RUN bash universal_build.sh

# Pin runtime content by digest; Renovate tracks updates to the latest tag.
FROM quay.io/redhat-services-prod/hcm-eng-prod-tenant/caddy-ubi:latest@sha256:7468f808396cddf82a10f93d976a1629b3f24fcb47e2de8cf8e20444f26565d8

COPY LICENSE /licenses/

ENV CADDY_TLS_MODE http_port 8000

COPY --from=builder /opt/app-root/src/Caddyfile /etc/caddy/Caddyfile
COPY --from=builder /opt/app-root/src/dist dist
COPY package.json .
