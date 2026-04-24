@AGENTS.md

## Commands

```bash
# Run all tests (requires Podman)
cd test && make test

# Run specific test suites
cd test && make test-caddy       # Caddy server tests
cd test && make test-env         # Environment variable tests
cd test && make test-fs          # Filesystem structure tests

# Lint Python test code
cd test && make lint

# Clean up test containers and artifacts
cd test && make clean

# Install Python test dependencies
cd test && make install
```

## Git Conventions

- Branch format: `type/short-description`
- Commit format: `type(scope): description`
- Types: `fix`, `feat`, `chore`, `docs`, `test`, `ci`
- Scopes: `dockerfile`, `build`, `caddy`, `sentry`, `secrets`, `test`, `deps`, `hermetic`
- Default branch: `master`

## Key Files

- `Dockerfile` — primary multi-stage build (builder + Caddy runtime)
- `Dockerfile.hermetic` — airgapped Konflux build variant
- `universal_build.sh` — main build orchestrator (detects npm/yarn, installs, builds)
- `build_app_info.sh` — generates app.info.json with build metadata
- `server_config_gen.sh` — generates Caddyfile and .dockerignore
- `parse-secrets.sh` — parses Konflux .env secrets
- `test/conftest.py` — pytest markers (caddy, envvars, filesystem, hermetic)
- `.github/workflows/test-dockerfile.yml` — CI workflow
