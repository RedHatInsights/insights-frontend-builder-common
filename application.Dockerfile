FROM quay.io/redhat-services-prod/hcm-eng-prod-tenant/frontend-builder:latest as builder

COPY --chown=default . .

RUN bash universal_build.sh

# Pin runtime content by digest; Renovate tracks updates to the latest tag.
FROM quay.io/redhat-services-prod/hcm-eng-prod-tenant/caddy-ubi:latest@sha256:52813ccd11b29dde78d2a87e7a5bceb05e9164329af91db8434ed1d9d8a57dcc

COPY LICENSE /licenses/

ENV CADDY_TLS_MODE http_port 8000

COPY --from=builder /opt/app-root/src/Caddyfile /etc/caddy/Caddyfile
COPY --from=builder /opt/app-root/src/dist dist
COPY package.json .
