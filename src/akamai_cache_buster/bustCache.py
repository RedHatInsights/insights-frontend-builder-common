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
        

    paths = getYMLFromUrl("https://cloud.redhat.com/config/main.yml").get(appName).get("frontend").get("paths")
    for path in paths:
        print(path.split('/'))
    #print(paths)

    #  old way
    # urls = []
    # for paths in getYMLFromUrl("https://cloud.redhat.com/config/main.yml").get(appName).get("frontend").get("paths"):
    #     urls.append("https://cloud.redhat.com" + paths)
    #     for subApps in getYMLFromUrl("https://cloud.redhat.com/config/main.yml").get(appName).get("frontend").get("sub_apps"):
    #         urls.append("https://cloud.redhat.com" + paths + "/" + subApps.get("id"))
    
    # for url in urls:
    #     print(url)

    # body = {
    #     "objects" : urls
    # }

    #generate metadata xml
   
    #create a request for each path
    for path in paths:

        #create the basic metadata message
        metadata = '<?xml version=\"1.0\"?>\n'
        metadata += '<!-- Submitted by bustCache.py script automatically -->'
        metadata += '<eccu>\n'

        #generate the path XML
        splitPath = path.split('/')
        for i in range(1, len(splitPath)):
            metadata += '   ' * i + ('<match:recursive-dirs value=\"%s\">\n'%(splitPath[i]))
        metadata += '   ' * len(splitPath) + '<revalidate>now</revalidate>\n'
        for i in range(1, len(splitPath)):
            metadata += '   ' * (len(splitPath) - i) + '</match:recursive-dirs>\n'
        metadata += '</eccu>'

        print(metadata + '\n')

        body = {
            "propertyName": "cloud.redhat.com",
            "propertyNameExactMatch": 'true',
            "propertyType": "HOST_HEADER",
            "metadata": metadata,
            "notes": "purging cache for new deployment",
            "requestName": "Invalidate cache for some frontend",
            "statusUpdateEmails": [
                "rfelton@redhat.com"
            ]
        }

        print(body)
        print(base_url + "/eccu/v1/requests")
        #print(akamaiPost("/ccu/v3/invalidate/url/staging", body))
        #print(akamaiPost("/eccu-api/v1/requests", body))

if __name__ == "__main__":
    main()