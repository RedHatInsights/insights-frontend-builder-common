FROM docker.io/openshift/jenkins-slave-base-centos7:v3.11

RUN yum install -y centos-release-scl && \
    yum-config-manager --enable centos-sclo-rh-testing && \
    yum install -y rh-python36 && \
    yum clean all

ENV PATH=/opt/bin/:/opt/rh/rh-python36/root/usr/bin${PATH:+:${PATH}} \
    LD_LIBRARY_PATH=/opt/rh/rh-python36/root/usr/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}} \
    PKG_CONFIG_PATH=/opt/rh/rh-python36/root/usr/lib64/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}} \
    XDG_DATA_DIRS="/opt/rh/rh-python36/root/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

RUN mkdir -p /opt/bin/ /home/jenkins/.akamai-cli/src/cli-purge/bin/ && \
    curl -L https://github.com/akamai/cli/releases/download/1.3.0/akamai-1.3.0-linuxamd64 \
         -o /opt/bin/akamai && \
    curl -L https://github.com/akamai/cli-purge/releases/download/1.0.1/akamai-purge-1.0.1-linuxamd64 \
         -o /home/jenkins/.akamai-cli/src/cli-purge/bin/akamai-purge && \
    curl -L https://raw.githubusercontent.com/akamai/cli-purge/1.0.1/cli.json \
         -o /home/jenkins/.akamai-cli/src/cli-purge/cli.json && \
    chmod +x /opt/bin/akamai /home/jenkins/.akamai-cli/src/cli-purge/bin/akamai-purge
    
COPY config /home/jenkins/.akamai-cli/

RUN python3.6 -m venv /insights_venv

ENV PATH=/insights_venv/bin/:${PATH}

RUN pip install --no-cache-dir -U pip setuptools wheel && \
    chgrp -R 0 /insights_venv/ && \
    chmod -R g+rwX /insights_venv/

