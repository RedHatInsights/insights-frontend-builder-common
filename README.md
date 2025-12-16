# Frontend Builder Common

The repo responsible for building all of the frontends on cloud.redhat.com.

## Build Secrets Management

This Dockerfile supports passing build secrets via Konflux as a `.env` file format. The secrets are parsed and made available during the build process, with special handling for Sentry authentication tokens.

### Passing Build Secret Variables

Build secrets can be passed to the container using Konflux's secret mounting mechanism. The secrets are expected to be in `.env` file format with the following structure:

```
KEY1=value1
KEY2=value2
# Comments are supported
INVENTORY_SECRET=your-secret-value
```

**Key features:**
- Secrets are mounted at `/run/secrets/build-container-additional-secret/secrets`
- You have to name your secret as `build-container-additional-secret` inside of it create a single key/value secret with key as `secrets` and value contents of your `.env` file
- The `parse-secrets.sh` script automatically parses the `.env` file format
- Comments (lines starting with `#`) and empty lines are ignored
- All key-value pairs are exported as environment variables during the build
- The script gracefully handles missing secret files (exits with code 0)

### Setting Sentry Auth Token

The build process includes automatic Sentry authentication token detection based on a naming convention. If a secret variable follows the pattern `{APP_NAME}_SECRET`, it will be automatically used as the `SENTRY_AUTH_TOKEN`.

**How it works:**
1. The build process extracts the application name from `package.json`
2. It constructs the expected secret variable name: `{APP_NAME}_SECRET`
3. If this variable exists in the parsed secrets, it automatically:
   - Sets `ENABLE_SENTRY=true`
   - Sets `SENTRY_AUTH_TOKEN` to the value of `{APP_NAME}_SECRET`
   - Enables Sentry sourcemap upload for the build

**Example:**
For an application named "inventory", if you provide a secret named `INVENTORY_SECRET=your-sentry-token`, the build will automatically:
- Enable Sentry integration
- Use the provided token for sourcemap uploads
- Display: `"Sentry: token found for inventory – enabling sourcemap upload."`

If no matching secret is found, the build continues with any pre-configured Sentry settings or skips Sentry upload entirely.

## Testing

This repository includes comprehensive automated tests for the Dockerfile and build scripts. Tests are automatically run on all pull requests and after merge to ensure reliability.

### Test Coverage

- **Caddy Server Tests** - Verify Caddy serves static files correctly, routes work, and HTTP responses are correct
- **Environment Variable Tests** - Test build-time ARGs and runtime ENVs are properly set and used
- **Filesystem Structure Tests** - Ensure files are copied to correct locations in the final image

### Running Tests Locally

```bash
cd test

# Install uv (if not already installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install dependencies
uv pip install --system -r requirements.txt

# Run all tests
make test

# Or run specific test suites
make test-caddy      # Caddy server tests
make test-env        # Environment variable tests
make test-fs         # Filesystem structure tests
```

**Requirements:**
- Python 3.8+
- uv (fast Python package installer)
- Podman (or Docker)

For detailed testing documentation, see [`test/README.md`](test/README.md).

### CI/CD

All tests run automatically via GitHub Actions on:
- Pull requests to `master`/`main`
- Push to `master`/`main` (after merge)

The workflow is defined in `.github/workflows/test-dockerfile.yml`.

## Akamai Cache Buster

This script is run automatically from Jenkins each time a frontend is deployed
to `Prod`. It clears out all of the old cached versions of the application to make
sure users are served up-to-date content.

### To Run

```bash
python bustCache.py /path/to/your/.edgerc appName
```

### Some Notes and Requirements

* Your edgerc needs read/write permission for the eccu API on akamai (not open CCU)
* The script only works on production akamai (no way to clear the cache on staging)
* Requests take about 30 minutes to finish
* Will not work on apps that don't have paths listed in the [source of truth](https://github.com/RedHatInsights/cloud-services-config/blob/ci-beta/main.yml)
