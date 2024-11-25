FROM registry.access.redhat.com/ubi9/nodejs-22:9.5-1731603585

USER root

RUN sudo dnf install jq

USER default

RUN npm i -g yarn

COPY universal_build.sh  /opt/app-root/bin/

