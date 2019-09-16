
# Frontend Builder Common

The repo responsible for building all of the frontends on cloud.redhat.com

## Akamai Cache Buster

This script is run automatically from Jenkins each time a frontend is deployed
to `Prod`. It clears out all of the old cached versions of the application to make
sure users are served up to date content

### To Run

```bash
python bustCache.py /path/to/your/.edgerc nameOfApp
```

### Some Notes and Requirements

* your edgerc needs read/write permission for the eccu API on akamai (not open CCU)
* the script only works on production akamai (no way to clear the cache on staging)
* requests take about 30 minutes to finish
* will not work on apps that don't have paths listed in the [source of truth](https://github.com/RedHatInsights/cloud-services-config/blob/ci-beta/main.yml)
