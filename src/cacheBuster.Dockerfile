# This was inspired by https://github.com/akamai/akamai-docker/blob/master/dockerfiles/purge.Dockerfile
# but modified to run in a Red Hat environment 
#
# Example usage:
# $ podman build -f cacheBuster.Dockerfile -t akamai-purge .
# $ podman run -it -v ~/.edgerc:/opt/app-root/edgerc:z -it akamai-purge invalidate https://somewhere.com/some/cached/file https://somewhere.com/some/other/cached/file
#
# Notes: 
#   * you have to have your akamai creds in a file that you mount to /opt/app-root/edgerc
#   * I added the -z in the mount to prevent selinux weirdness but YMMV
#   * The akamai creds file format is SUPER finicky and needs to be exactly like this but with the hash marks removed:
#
#[default]
#client_secret = FOOFOOFOOFOOFOOFOOFOOFOOFOOFOOF
#host = asomecrazyhostname.com
#access_token = BARBARBARBARBARBARBARBARBARB
#client_token = DEADBEEFDEADBEEFDEADBEEF
#[ccu]
#client_secret = FOOFOOFOOFOOFOOFOOFOOFOOFOOFOOF
#host = asomecrazyhostname.com
#access_token = BARBARBARBARBARBARBARBARBARB
#client_token = DEADBEEFDEADBEEFDEADBEEF
#
# You can set up creds via directions in this article https://techdocs.akamai.com/developer/docs/set-up-authentication-credentials
FROM registry.access.redhat.com/ubi8/go-toolset:1.25.5-1770654314 as builder

USER 0

RUN dnf install -y git \
    && git clone --depth=1 https://github.com/akamai/cli-purge \
    && cd cli-purge \
    && go mod init github.com/akamai/cli-purge \
    && go get github.com/akamai/cli-purge \
    && go mod vendor \
    && mkdir -p /cli/.akamai-cli/src/cli-purge/bin \
    && go build -o /cli/.akamai-cli/src/cli-purge/bin/akamai-purge -ldflags="-s -w" \
    && cp cli.json /cli/.akamai-cli/src/cli-purge/bin/cli.json

ENTRYPOINT ["/cli/.akamai-cli/src/cli-purge/bin/akamai-purge", "--edgerc", "/opt/app-root/edgerc"]
