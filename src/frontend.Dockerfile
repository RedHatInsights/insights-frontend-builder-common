FROM registry.access.redhat.com/ubi8/ubi:8.5-214
USER 0
RUN dnf install -y openssh-clients git docker jq curl tar 
RUN useradd -ms /bin/bash builder
RUN mkdir -p /container_workspace
RUN chown -R builder:builder /container_workspace
USER builder
RUN touch ~/.bash_profile && chmod +x ~/.bash_profile && mkdir -p /home/builder/.nvm

# Setup https://github.com/nvm-sh/ [node version manager] and install 12 as the base
# so we don't have to create a build pipeline for every different version
# since ubi only has official images for node 14 and 16. Here be dragons.
ENV NVM_DIR="/home/builder/.nvm"
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash \
    && . $NVM_DIR/nvm.sh \
    && nvm install 12 \ 
    && nvm use 12

# Setup cache dir for jest
# ENV TMPDIR='/home/builder'
COPY --chown=builder:builder ./nginx_conf_gen.sh /container_workspace
COPY --chown=builder:builder ./quay_push.sh /container_workspace
COPY --chown=builder:builder ./universal_build.sh /container_workspace
# RUN chmod 775 /container_workspace/universal_build.sh
WORKDIR /container_workspace
ENTRYPOINT ["/container_workspace/universal_build.sh"]
