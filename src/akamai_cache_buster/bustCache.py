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

def createMetadata(path):
    #create the basic metadata message
    metadata = '<?xml version=\"1.0\"?>\n<!-- Submitted by bustCache.py script automatically -->\n<eccu>\n'

    #generate the path XML
    splitPath = path.split('/')
    metadataClosingTags = ''
    pathLength = len(splitPath)
    #create opening and closing tags
    for i in range(1, pathLength):
        metadata += '   ' * i + f'<match:recursive-dirs value=\"{splitPath[i]}\">\n'
        metadataClosingTags += '   ' * (pathLength - i) + '</match:recursive-dirs>\n'
    metadata += '   ' * pathLength + '<revalidate>now</revalidate>\n'
    metadata += metadataClosingTags
    metadata += '</eccu>'

    return metadata

def createRequest(path):
    body = {
        "propertyName": "cloud.redhat.com",
        "propertyNameExactMatch": 'true',
        "propertyType": "HOST_HEADER",
        "metadata": createMetadata(path),
        "notes": "purging cache for new deployment",
        "requestName": "Invalidate cache for some frontend",
        "statusUpdateEmails": [
            "rfelton@redhat.com"
        ]
    }

    return body

#main
def main():
    appName = sys.argv[2]
    
    #connect to akamai and validate
    initEdgeGridAuth()

    #create a request for each path
    paths = getYMLFromUrl("https://cloud.redhat.com/config/main.yml").get(appName).get("frontend").get("paths")
    for path in paths:
        akamaiPost("/eccu-api/v1/requests", createRequest(path))

if __name__ == "__main__":
    main()