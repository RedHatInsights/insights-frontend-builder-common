FROM quay.io/redhat-services-prod/hcm-eng-prod-tenant/frontend-builder:latest as builder

COPY --chown=default . .

RUN bash -x universal_build.sh

FROM quay.io/redhat-services-prod/hcm-eng-prod-tenant/caddy-ubi:5519eba

COPY LICENSE /licenses/

ENV CADDY_TLS_MODE http_port 8000

COPY --from=builder /opt/app-root/src/Caddyfile /etc/caddy/Caddyfile
COPY --from=builder /opt/app-root/src/dist dist
COPY package.json .
