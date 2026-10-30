FROM quay.io/redhat-services-prod/hcm-eng-prod-tenant/frontend-builder:latest as builder

COPY --chown=default . .

RUN bash universal_build.sh

# Pin runtime content by digest; Renovate tracks updates to the latest tag.
FROM quay.io/redhat-services-prod/hcm-eng-prod-tenant/caddy-ubi:latest@sha256:74771b6c63ce3db5b6774a2480e213d98a9c78afe707427cdca2f0af6756a84b

COPY LICENSE /licenses/

ENV CADDY_TLS_MODE http_port 8000

COPY --from=builder /opt/app-root/src/Caddyfile /etc/caddy/Caddyfile
COPY --from=builder /opt/app-root/src/dist dist
COPY package.json .
