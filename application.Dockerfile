FROM quay.io/redhat-services-prod/hcm-eng-prod-tenant/frontend-builder:latest as builder

COPY --chown=default . .

RUN bash universal_build.sh

# Pin runtime content by digest; Renovate tracks updates to the latest tag.
FROM quay.io/redhat-services-prod/hcm-eng-prod-tenant/caddy-ubi:latest@sha256:e329ebe7a312870b6cb62e3613bb63aaaacc2a7f5fa17047b1dffafe70e5adf9

COPY LICENSE /licenses/

ENV CADDY_TLS_MODE http_port 8000

COPY --from=builder /opt/app-root/src/Caddyfile /etc/caddy/Caddyfile
COPY --from=builder /opt/app-root/src/dist dist
COPY package.json .
