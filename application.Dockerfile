FROM quay.io/redhat-services-prod/hcm-eng-prod-tenant/frontend-builder:latest as builder

COPY --chown=default . .

RUN bash universal_build.sh

# Pin runtime content by digest; Renovate tracks updates to the latest tag.
FROM quay.io/redhat-services-prod/hcm-eng-prod-tenant/caddy-ubi:latest@sha256:8d202412dfd1538029cd9590253234f7ed45e15039c62e3d4a6be55f3cfa6d64

COPY LICENSE /licenses/

ENV CADDY_TLS_MODE http_port 8000

COPY --from=builder /opt/app-root/src/Caddyfile /etc/caddy/Caddyfile
COPY --from=builder /opt/app-root/src/dist dist
COPY package.json .
