import yaml
import json
import sys
import os
import configparser
import requests
from urllib.parse import urljoin
from akamai.edgegrid import EdgeGridAuth, EdgeRc

# Set up connectivity. Global var because it's a session that's used in multiple functions.
s = requests.Session()

#get that YAML from a URL
def getYMLFromUrl(url):
    return yaml.safe_load(s.get(url).content.decode('utf-8'))

# Initializes the EdgeGrid auth using the .edgerc file (or some passed-in config).
def initEdgeGridAuth(path="~/.edgerc"):
    # If the config file was passed in, use that.
    if len(sys.argv) > 1:
        path = sys.argv[1]
    config = configparser.RawConfigParser()
    config.read(os.path.expanduser(path))

    # TODO: We might actually be able to authenticate without EdgeGridAuth,
    # which would reduce the number of dependencies.
    s.auth = EdgeGridAuth(
        client_token=config.get("default", "client_token"),
        client_secret=config.get("default", "client_secret"),
        access_token=config.get("default", "access_token")
)

def akamaiPost(url, body):
    return s.post(urljoin(base_url, url), json=body).content

# Gets the hostname from the .edgerc file (or some passed-in config).
def getHostFromConfig(path="~/.edgerc"):
    # If the config file was passed in, use that.
    if len(sys.argv) > 1:
        path = sys.argv[1]
    config = configparser.RawConfigParser()
    config.read(os.path.expanduser(path))
    return config.get("default", "host")

# Get the base url using the provided config
base_url = "https://" + getHostFromConfig()


#main
def main():
    appName = sys.argv[2]

    #sys.argv[2] should be name of app to bust
    print(appName)
    
    #connect to akamai and validate
    initEdgeGridAuth()

    print(getYMLFromUrl("https://cloud.redhat.com/config/main.yml").get(appName).get("frontend").get("paths"))

    urls = []
    for paths in getYMLFromUrl("https://cloud.redhat.com/config/main.yml").get(appName).get("frontend").get("paths"):
        urls.append("https://cloud.redhat.com" + paths)
    
    for url in urls:
        print(url)

    body = {
        "objects" : urls
    }

    print(base_url + "/ccu/v3/invalidate/url/staging")
    print(akamaiPost("/ccu/v3/invalidate/url/staging", body))

if __name__ == "__main__":
    main()