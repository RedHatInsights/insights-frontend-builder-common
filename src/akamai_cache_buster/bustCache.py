import yaml
import sys
import subprocess
import requests
from urllib.parse import urljoin

# Set up connectivity. Global var because it's a session that's used in multiple functions.
s = requests.Session()

#get that YAML from a URL
def getYMLFromUrl(url):
    return yaml.safe_load(s.get(url).content.decode('utf-8'))

#main
def main():
    print(f'Cache purge started with: {sys.argv}')
    edgeRcPath = sys.argv[1]
    appName = sys.argv[2]
    branch = sys.argv[3]
    domain = 'https://console.stage.redhat.com'
    if 'prod' in branch:
        domain = 'https://console.redhat.com'
    entryBase = f'/apps/{appName}'
    fedModsBase = f'{entryBase}/fed-mods.json'
    #get the data to use for cache busting
    paths = []
    try:
        paths = getYMLFromUrl("https://console.redhat.com/config/main.yml").get(appName).get("frontend").get("paths")
    except:
        print("WARNING: this app has no path, if that's okay ignore this :)")
        paths = []
    
    releases = getYMLFromUrl("https://console.redhat.com/config/releases.yml")

    print(paths)
    purgeSuffixes = []
    purgeUrls = []
    for key in releases:
        prefix = releases[key].get("content_path_prefix")
        if (prefix == None):
            prefix = ''
        purgeSuffixes.append(f'{prefix}{fedModsBase}')
        for path in paths:
            purgeSuffixes.append(f'{prefix}{path}')
    
    for suffix in purgeSuffixes:
        purgeUrls.append(f'{domain}{suffix}')

    for endpoint in purgeUrls:
        print(f'Purging endpoint cache: {endpoint}')
        try:
            subprocess.check_output(['akamai', 'purge', '--edgerc', edgeRcPath , 'invalidate', endpoint])
        except subprocess.CalledProcessError as e:
            print(e.output)
            sys.exit(1)



if __name__ == "__main__":
    main()