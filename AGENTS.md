# insights-frontend-builder-common

Shared Docker build infrastructure for all HCC (Hybrid Cloud Console) frontend applications. Consumed as a git submodule named `build-tools` in each frontend repo.

## Tech Stack

| Technology | Version/Details | Purpose |
|-----------|----------------|---------|
| Docker/Podman | Multi-stage builds | Container image builds |
| Bash | Shell scripts | Build orchestration, config generation |
| Caddy | UBI-based (`caddy-ubi:latest`) | Static file serving in production |
| Node.js | UBI9 nodejs-22 | Frontend build stage |
| Python | 3.8+ with pytest | Dockerfile integration tests |
| Podman | Container runtime | Test execution (builds + runs containers) |
| uv | Package installer | Python dependency management |
| ruff | Linter | Python code quality |
| Renovate | Bot | Automated dependency updates (Docker + Python) |
| GitHub Actions | CI | Automated test runs on PRs and merges |

## Project Structure

```text
insights-frontend-builder-common/
├── Dockerfile                    # Primary multi-stage build (Node.js builder → Caddy runtime)
├── Dockerfile.hermetic           # Hermetic/airgapped build variant (Node.js → ubi-micro)
├── application.Dockerfile        # Legacy Dockerfile using pre-built builder image
├── universal_build.sh            # Main build orchestrator (npm/yarn detect, install, build)
├── build_app_info.sh             # Generates app.info.json with build metadata
├── server_config_gen.sh          # Generates Caddyfile, .dockerignore, app.info.json
├── parse-secrets.sh              # Parses .env secrets from Konflux secret mounts
├── README.md                     # Main documentation
├── README-hermetic-build.md      # Hermetic build setup guide
├── renovate.json                 # Renovate bot configuration
├── .github/
│   └── workflows/
│       └── test-dockerfile.yml   # CI: builds image + runs pytest suites
├── src/                          # Legacy Jenkins/CI scripts (mostly historical)
│   ├── bootstrap.sh              # Legacy Jenkins bootstrap
│   ├── frontend-build.sh         # Legacy build script
│   ├── release.sh                # Legacy release script
│   ├── after_success.sh          # Legacy post-build
│   ├── nightly.sh                # Legacy nightly builds
│   ├── quay_push.sh              # Legacy Quay push
│   ├── migrate.sh                # Legacy migration
│   ├── verify_frontend_dependencies.sh  # Dependency verification
│   ├── frontend-build-history.sh # Build history tracking
│   ├── akamai_cache_buster/      # Akamai cache purge (Python)
│   ├── Jenkinsfile               # Legacy Jenkins pipeline
│   └── *.Dockerfile              # Legacy specialized Dockerfiles
└── test/                         # Pytest integration tests
    ├── conftest.py               # Pytest markers (caddy, envvars, filesystem, hermetic)
    ├── test_dockerfile_caddy.py  # Caddy server functionality tests
    ├── test_dockerfile_env_vars.py    # Build ARG and runtime ENV tests
    ├── test_dockerfile_filesystem.py  # File structure verification tests
    ├── test_dockerfile_hermetic.py    # Hermetic Dockerfile tests
    ├── Makefile                  # Test runner shortcuts
    ├── requirements.txt          # Python test dependencies
    ├── pyproject.toml            # Python project config
    ├── README.md                 # Detailed testing documentation
    └── test-fixtures/
        └── fake-app/             # Minimal test application
            ├── package.json      # With insights.appname field
            ├── package-lock.json
            ├── build.js          # Creates dist/ with test assets
            └── LICENSE
```

## How It Works

### Build Flow

Consumer apps include this repo as a git submodule at `build-tools/`:

```text
frontend-app/
├── build-tools/          ← git submodule (this repo)
│   ├── Dockerfile
│   ├── universal_build.sh
│   └── ...
├── package.json
├── src/
└── dist/                 ← build output
```

The build is triggered by `podman build -f build-tools/Dockerfile .` and follows this flow:

1. **Builder stage** (Node.js UBI9):
   - Copies build scripts to `/opt/app-root/bin/`
   - Copies application source
   - Runs `parse-secrets.sh` to load Konflux secrets
   - Runs `universal_build.sh` which:
     - Detects npm vs yarn (via lock file presence)
     - Runs `npm ci` or `yarn install --immutable`
     - Runs the build command (`npm run build` or custom script)
     - Generates `app.info.json` via `build_app_info.sh`
     - Generates Caddyfile via `server_config_gen.sh`

2. **Runtime stage** (Caddy UBI):
   - Copies Caddyfile to `/etc/caddy/Caddyfile`
   - Copies build output to `/srv/dist`
   - Copies `package.json` to `/srv/`
   - Serves static files on port 8000

### Hermetic Build Flow

`Dockerfile.hermetic` is used for airgapped Konflux builds:
- Uses Cachi2 prefetched dependencies (`npm ci --offline`)
- Final stage uses `ubi-micro` (minimal image, no Caddy)
- Output goes to `/srv/dist`, `/srv/package.json`, `/srv/package-lock.json`
- Requires `prefetch-input` in Tekton pipeline config

### Key Build Arguments

| ARG | Default | Purpose |
|-----|---------|---------|
| `APP_BUILD_DIR` | `dist` | Build output directory name |
| `ENABLE_SENTRY` | `false` | Enable Sentry sourcemap upload |
| `SENTRY_AUTH_TOKEN` | (none) | Sentry authentication token |
| `SENTRY_RELEASE` | (none) | Sentry release identifier |
| `APP_VERSION` | `unknown` | Application version for app.info.json |
| `NPM_BUILD_SCRIPT` | (empty) | Custom npm build script name |
| `YARN_BUILD_SCRIPT` | (empty) | Custom yarn build script name |
| `USES_YARN` | `false` | Force yarn build system |
| `SOURCE_GIT_BRANCH` | (empty) | Git branch for detached HEAD CI |
| `SOURCE_GIT_TAG` | (empty) | Git tag for detached HEAD CI |
| `PACKAGE_JSON_PATH` | `package.json` | Path to package.json |
| `NPM_CI_ARGS` | (empty) | Extra args for npm ci (hermetic only) |

### Caddy Configuration

Generated by `server_config_gen.sh`:
- Port 8000 for application traffic
- Port 9000 for Prometheus metrics
- Route: `/apps/{APP_NAME}/*` serves from `/srv/dist`
- Route: `{ENV_PUBLIC_PATH}/*` for env-based routing
- Root redirect: `/` redirects to `/apps/chrome/index.html`
- TLS mode configurable via `CADDY_TLS_MODE`

## Development Commands

```bash
# Run all tests (requires Podman)
cd test && make test

# Run specific test suites
cd test && make test-caddy       # Caddy server tests
cd test && make test-env         # Environment variable tests
cd test && make test-fs          # Filesystem structure tests

# Run with verbose output
cd test && make test-verbose

# Lint Python test code
cd test && make lint

# Clean up containers and artifacts
cd test && make clean

# Install test dependencies
cd test && make install
```

## Coding Conventions

1. **Shell scripts**: Use `set -euo pipefail` at the top. Use `set -exv` for verbose debug output during builds.
2. **Conventional commits**: Follow `type(scope): description` format. Types: `fix`, `feat`, `chore`, `docs`, `test`, `ci`. Renovate uses `chore(deps):` for dependency updates.
3. **Build system detection**: Always detect npm vs yarn by checking for `package-lock.json` or `yarn.lock`. Never hardcode one.
4. **Environment variables**: Use `ARG` for build-time, `ENV` to persist to runtime. Document every ARG in the Dockerfile with comments.
5. **Secrets handling**: Never log secret values. Use the `parse-secrets.sh` pattern for `.env` format secrets from Konflux mounts.
6. **Python tests**: Use pytest classes (e.g., `TestDockerfileCaddy`). Each test class builds its own container image and cleans up.
7. **Container references**: Use Quay registry paths. The Caddy base image is `quay.io/redhat-services-prod/hcm-eng-prod-tenant/caddy-ubi:latest`.
8. **Submodule convention**: Consumer apps clone this as `build-tools/`. Scripts reference paths relative to this (e.g., `build-tools/Dockerfile`).

## Common Pitfalls

1. **Detached HEAD in CI**: Konflux/Tekton checks out a detached HEAD, so `git branch --show-current` returns empty. `build_app_info.sh` has a 4-step fallback: current branch, abbrev-ref, remote branch, CI env vars (`SOURCE_GIT_BRANCH`, `GITHUB_HEAD_REF`, etc.).
2. **npm vs yarn detection**: `universal_build.sh` checks for lock files. If neither `package-lock.json` nor `yarn.lock` exists, the build fails. Both cannot be present.
3. **Secret naming convention**: Sentry tokens use `{APP_NAME}_SECRET` where `APP_NAME` comes from `package.json` `insights.appname`, uppercased with dashes replaced by underscores.
4. **Multi-stage build variables**: `ARG` values set in the builder stage do NOT persist to the runtime (Caddy) stage. Only `ENV` values set in the final stage are available at runtime.
5. **Test fixture setup**: Tests dynamically copy the Dockerfile and scripts from repo root to `test-fixtures/fake-app/build-tools/` before each run. Don't manually place files there.
6. **Caddyfile generation**: `server_config_gen.sh` only generates a Caddyfile if one doesn't already exist. If a consumer app has its own Caddyfile, it takes precedence.
7. **Git safe.directory**: The build script runs `git config --global --add safe.directory /opt/app-root/src` because the container user differs from the repo owner.

## Documentation Index

| Document | Description |
|----------|-------------|
| [README.md](README.md) | Main documentation: secrets, testing, cache busting |
| [README-hermetic-build.md](README-hermetic-build.md) | Step-by-step hermetic build setup with Konflux |
| [test/README.md](test/README.md) | Comprehensive testing guide |
| [docs/build-script-guidelines.md](docs/build-script-guidelines.md) | Guide for modifying build scripts |
| [docs/testing-guidelines.md](docs/testing-guidelines.md) | Python/pytest testing patterns |
| [docs/architecture-guidelines.md](docs/architecture-guidelines.md) | Multi-stage Docker build architecture |
