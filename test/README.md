# Dockerfile Tests

This directory contains tests for the frontend builder Dockerfile, specifically testing the Caddy server functionality.

## Overview

The test suite verifies that:
- The Docker/Podman image builds successfully with the build scripts
- Caddy web server serves static files correctly
- Application routes work as expected (`/apps/{app-name}/`)
- Environment-based routes are configured
- Build-generated files (app.info.json) are present and valid
- Proper HTTP redirects and status codes are returned

## How It Works

This test suite mirrors the real-world usage where `insights-frontend-builder-common` is typically used as a git submodule named `build-tools`. The test setup:

1. **Dynamically copies** the Dockerfile and build scripts from the repo root to `test-fixtures/fake-app/build-tools/` before each test run
2. **Builds the image** from the fake-app directory (simulating a real frontend app) with `-f build-tools/Dockerfile`
3. **Cleans up** the copied files after tests complete

This ensures tests always use the current version of your Dockerfile and build scripts without maintaining duplicate copies.

## Test Structure

```
test/
├── test_dockerfile_caddy.py       # Caddy server functionality tests
├── test_dockerfile_env_vars.py    # Environment variable tests
├── test_dockerfile_filesystem.py  # Filesystem structure tests
├── conftest.py                    # Pytest configuration
├── requirements.txt               # Python dependencies
├── Makefile                       # Convenient test commands
├── README.md                      # This file
└── test-fixtures/
    └── fake-app/                  # Minimal test application
        ├── package.json           # With insights.appname field
        ├── package-lock.json      # NPM lock file
        ├── build.js               # Simple build script that creates dist/
        ├── LICENSE                # Required by Dockerfile
        ├── .gitignore             # Ignores build-tools/ and dist/
        └── build-tools/           # (Created dynamically during tests)
            ├── Dockerfile         # (Copied from repo root)
            └── *.sh               # (Build scripts copied from repo root)
```

## Prerequisites

1. **Podman** (or Docker) installed and running
2. **Python 3.8+**
3. **Node.js** (for the build process inside the container)

## Installation

Install Python test dependencies:

```bash
cd test
pip install -r requirements.txt
```

Or using a virtual environment (recommended):

```bash
cd test
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

## Running Tests

### Run all tests

```bash
# Run all tests
pytest -v

# Or run specific test files
pytest test_dockerfile_caddy.py -v
pytest test_dockerfile_env_vars.py -v
pytest test_dockerfile_filesystem.py -v
```

### Run a specific test

```bash
# Caddy tests
pytest test_dockerfile_caddy.py::TestDockerfileCaddy::test_app_route_serves_index_html -v

# Environment variable tests
pytest test_dockerfile_env_vars.py::TestDockerfileEnvVars::test_custom_app_build_dir -v

# Filesystem tests
pytest test_dockerfile_filesystem.py::TestDockerfileFilesystem::test_dist_directory_structure -v
```

### Run with detailed output

```bash
pytest test_dockerfile_caddy.py -v -s
pytest test_dockerfile_env_vars.py -v -s
```

### Run with coverage (if pytest-cov is installed)

```bash
pip install pytest-cov
pytest test_dockerfile_caddy.py --cov --cov-report=html
```

## What the Tests Do

### Setup Phase
1. Copies `Dockerfile` from repo root to `test-fixtures/fake-app/build-tools/`
2. Copies all build scripts (`*.sh`) from repo root to `test-fixtures/fake-app/build-tools/`
3. Prints confirmation of file copies

### Build Phase
1. Changes to `test-fixtures/fake-app` directory
2. Runs `podman build -f build-tools/Dockerfile .` (mimicking real-world usage)
3. The build process inside the container:
   - Installs npm dependencies
   - Runs `npm run build` (which executes `build.js`)
   - Creates `dist/` directory with test assets (HTML, CSS, JS, JSON)
   - Runs build scripts to generate Caddyfile and app.info.json
   - Copies files to final Caddy-based image

### Test Phase
Each test:
1. Starts a container from the built image
2. Waits for Caddy server to be ready
3. Makes HTTP requests to verify functionality
4. Asserts expected responses and content
5. Cleans up the container

### Cleanup Phase
After all tests complete:
1. Docker/Podman image is removed
2. Copied `build-tools/` directory is deleted from the test fixture

## Test Coverage

### Caddy Server Tests (`test_dockerfile_caddy.py`)

- ✓ Root redirect to `/apps/chrome/index.html`
- ✓ Main app route (`/apps/test-app/`) serves files
- ✓ CSS files are served with correct content type
- ✓ JavaScript files are served correctly
- ✓ JSON files are served and parseable
- ✓ Generated `app.info.json` contains expected fields
- ✓ 404 responses for nonexistent files
- ✓ Paths work with and without trailing slashes
- ✓ Metrics endpoint configuration

### Environment Variable Tests (`test_dockerfile_env_vars.py`)

**Build-time ARG variables:**
- ✓ `APP_BUILD_DIR` - Custom output directory for build artifacts
- ✓ `ENABLE_SENTRY` - Sentry configuration during build
- ✓ `SENTRY_RELEASE` - Sentry release version
- ✓ `USES_YARN` - Build system selection (npm vs yarn)

**Runtime ENV variables:**
- ✓ `ENV_PUBLIC_PATH` - Custom Caddy route for serving app
- ✓ `CADDY_TLS_MODE` - TLS configuration for Caddy
- ✓ Runtime variable override of defaults
- ✓ Default values are correctly set

**Note:** Due to the multi-stage Docker build, variables set in the builder stage (like `ENABLE_SENTRY`, `USES_YARN`, `YARN_BUILD_SCRIPT`) are only available during build and not at runtime in the final Caddy container. Only variables set in the final stage (`ENV_PUBLIC_PATH`, `CADDY_TLS_MODE`) are available at runtime.

### Filesystem Structure Tests (`test_dockerfile_filesystem.py`)

**File Locations:**
- ✓ `/licenses/LICENSE` - License file is copied correctly
- ✓ `/etc/caddy/Caddyfile` - Caddy configuration file with correct port and routes
- ✓ `/srv/dist/` - Build artifacts directory
- ✓ `/srv/dist/index.html` - Main HTML file
- ✓ `/srv/dist/css/app.css` - CSS files in subdirectory
- ✓ `/srv/dist/js/app.js` - JavaScript files in subdirectory
- ✓ `/srv/dist/manifest.json` - Application manifest
- ✓ `/srv/dist/app.info.json` - Generated build metadata with correct fields
- ✓ `/srv/package.json` - Package.json copied to working directory
- ✓ `/usr/local/bin/valpop` - Valpop binary is executable

**Build Artifact Tests:**
- ✓ Custom `APP_BUILD_DIR` is respected
- ✓ Complete directory structure with subdirectories
- ✓ app.info.json contains required fields (app_name, src_hash, src_branch)

## Customization

### Testing Local Changes

Since the Dockerfile and build scripts are copied dynamically before each test run, any changes you make to the files in the repo root will be automatically reflected in the next test run. No manual copying needed!

### Using a Different Port

The tests use port 8080 by default. To change this, modify the `HOST_PORT` variable in `test_dockerfile_caddy.py`:

```python
HOST_PORT = 8080  # Change to your desired port
```

### Testing Different App Builds

To test with a different application structure:

1. Create a new directory under `test-fixtures/`
2. Ensure it has the required files:
   - `package.json` with `insights.appname`
   - `package-lock.json` or `yarn.lock`
   - Build script that creates a `dist/` directory
   - `LICENSE` file
   - Git repository initialized (required by build scripts)
3. Update the test class to point to your new fixture
4. The `build-tools/` directory and `Dockerfile` will be copied automatically

### Using Docker Instead of Podman

The tests use `podman` by default. To use Docker instead, you can either:

1. Create a symlink: `ln -s $(which docker) /usr/local/bin/podman`
2. Or modify the test file to replace "podman" with "docker"

## Troubleshooting

### Container fails to start
- Check if port 8080 is already in use: `lsof -i :8080`
- Verify Podman/Docker is running: `podman ps`
- Check container logs: `podman logs test-frontend-container`

### Build fails
- Ensure all build scripts are executable: `chmod +x build-tools/*.sh`
- Check that git is initialized in the test fixture directory
- Verify Node.js is available in the builder image

### Tests fail with connection errors
- Increase the timeout in `_wait_for_caddy()` method
- Check if Caddy is actually running: `podman exec test-frontend-container ps aux`
- Verify the port mapping: `podman port test-frontend-container`

### Import errors
- Make sure you're in the `test/` directory
- Verify requirements are installed: `pip list | grep pytest`

## CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Test Dockerfile

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: |
          cd test
          pip install -r requirements.txt
      - name: Run tests
        run: |
          cd test
          pytest test_dockerfile_caddy.py -v
```

## Contributing

When adding new tests:
1. Follow the existing test pattern (setup_method/teardown_method)
2. Use descriptive test names that explain what's being tested
3. Include assertions with helpful error messages
4. Clean up resources in teardown methods
5. Document any new fixtures or dependencies

## License

These tests are part of the insights-frontend-builder-common repository.
