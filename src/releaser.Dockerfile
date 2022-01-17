FROM quay.io/fedora/fedora:35-x86_64

ENV GOPATH=/go

RUN dnf update -y && \
        dnf install nodejs openssh-clients golang -y && \
        npm i -g yarn && \
        dnf clean all

RUN mkdir -p /root/.ssh && \
        chmod 0777 -R /root/.ssh && \
        chmod 0777 -R /etc/ssh/ssh_config && \
        ssh-keyscan github.com >> /etc/ssh/ssh_known_hosts && \
        echo $'Host github.com\n\
  HostName github.com\n\
  User git\n\
  IdentitiesOnly yes\n\
  IdentityFile /root/.ssh/ssh_key' >> /etc/ssh/ssh_config && \
        mkdir -p /go/src
