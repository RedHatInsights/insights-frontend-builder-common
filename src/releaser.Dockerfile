FROM quay.io/fedora/fedora:40-x86_64

ENV GOPATH=/go

RUN dnf update -y && \
        dnf install 'dnf-command(copr)' -y && \
        dnf copr enable @caddy/caddy -y && \
        dnf group install "C Development Tools and Libraries" -y && \
        dnf install nodejs caddy rsync unzip openssh-clients golang pandoc asciidoctor ruby-devel zlib-devel graphviz java-11-openjdk.x86_64 -y && \
        gem install asciidoctor-plantuml && \
        gem install asciidoctor-diagram && \
        npm i -g yarn && \
        dnf clean all

RUN mkdir -p /root/.ssh && \
        chmod 0777 -R /root/.ssh && \
        chmod 0777 -R /etc/ssh/ssh_config && \
        mkdir /.npm && \
        chmod 0777 -R /.npm && \
        git config --global --add safe.directory '*' && \
        ssh-keyscan github.com >> /etc/ssh/ssh_known_hosts && \
        echo $'Host github.com\n\
  HostName github.com\n\
  User git\n\
  IdentitiesOnly yes\n\
  IdentityFile /root/.ssh/ssh_key' >> /etc/ssh/ssh_config && \
        mkdir -p /go/src && \
        mkdir -p /opt/app-root/src
