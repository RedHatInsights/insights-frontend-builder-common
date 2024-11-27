FROM registry.access.redhat.com/ubi9/nodejs-22:9.5-1731603585 as builder

USER root

RUN dnf install jq -y

USER default

RUN npm i -g yarn

COPY universal_build.sh build_app_info.sh server_config_gen.sh /opt/app-root/bin/
