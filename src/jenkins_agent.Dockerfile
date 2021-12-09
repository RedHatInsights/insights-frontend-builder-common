FROM quay.io/openshift/origin-jenkins-agent-base:4.9

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

ENV PATH=/insights_venv/bin/:/opt/bin/:${PATH}

RUN pip install --no-cache-dir -U pip setuptools wheel && \
    chgrp -R 0 /insights_venv/ && \
    chmod -R g+rwX /insights_venv/
