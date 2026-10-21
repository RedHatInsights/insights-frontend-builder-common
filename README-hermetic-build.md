# Hermetic Build Setup Guide for Frontend Projects

## Overview

A hermetic build ensures your frontend application builds in a completely isolated environment without external network access, using only pre-fetched dependencies. This guide covers the shared `Dockerfile.hermetic` provided through `insights-frontend-builder-common`.

The shared Dockerfile supports **two build targets**:

| Target | Base Image | Use Case | Selection |
|--------|-----------|----------|-----------|
| `artifact` (default) | `ubi9/ubi-micro` | Security-compliance scanning images | No `--target` needed |
| `deploy` | `caddy-ubi` | Deployable frontend images with Caddy serving | `--target deploy` |

Existing consumers omitting target selection retain artifact-only behavior — **fully backward-compatible**.

---

## Prerequisites

- Access to Konflux
- Frontend project with `package.json` and `package-lock.json` (npm)
- `insights-frontend-builder-common` available as `build-tools/` submodule

---

## Step 1: Set Up Konflux Components

### Security-Compliance Component (artifact target)

1. **Component Name**: `your-project-name-sc`
2. **Dockerfile Path**: `build-tools/Dockerfile.hermetic`
3. **Build Type**: Hermetic Build
4. No `--target` needed — the default `artifact` stage produces a minimal ubi-micro image

### Deployable Component (deploy target)

1. **Component Name**: `your-project-name`
2. **Dockerfile Path**: `build-tools/Dockerfile.hermetic`
3. **Build Type**: Hermetic Build
4. Set target to `deploy` via pipeline parameters (see below)

---

## Step 2: Configure Pipeline Files

Konflux creates pipeline files in `.tekton/`. Add dependency prefetching and target selection.

### SC Pipeline (artifact target, default)

```yaml
spec:
  params:
  - name: git-url
    value: '{{source_url}}'
  - name: revision
    value: '{{revision}}'
  - name: output-image
    value: quay.io/your-registry/your-project-sc:{{revision}}
  - name: dockerfile
    value: build-tools/Dockerfile.hermetic
  - name: hermetic
    value: "true"
  - name: prefetch-input
    value: '{"type": "npm", "path": "."}'
```

### Regular Pipeline (deploy target)

The deploy target requires `--target deploy` to be forwarded to the Buildah task during the container build. This is a **cross-repository prerequisite** that involves:

1. **Buildah task**: The pinned Buildah task revision must accept a `TARGET` or equivalent parameter and pass `--target $(params.TARGET)` to `buildah build`.
2. **Shared/inline pipeline**: The Tekton Pipeline must expose this as a PipelineRun-level parameter (e.g. `target-stage`) and forward it to the Buildah task.
3. **Consumer PipelineRun**: Once the above are in place, set the parameter in `.tekton/`:

```yaml
spec:
  params:
  - name: git-url
    value: '{{source_url}}'
  - name: revision
    value: '{{revision}}'
  - name: output-image
    value: quay.io/your-registry/your-project:{{revision}}
  - name: dockerfile
    value: build-tools/Dockerfile.hermetic
  - name: hermetic
    value: "true"
  - name: prefetch-input
    value: '{"type": "npm", "path": "."}'
  - name: target-stage                          # Requires pipeline support (see above)
    value: deploy
```

> **Note**: Without the pipeline/task changes above, the build defaults to the `artifact` stage (backward-compatible, but no Caddy server). Check your `pipelineRef` revision for current parameter support.

---

## Step 3: Build Arguments

### Common Build Args

| ARG | Default | Description |
|-----|---------|-------------|
| `NODE_BUILD_VERSION` | `22` | Node.js major version |
| `NODE_IMAGE_TAG` | `9.8-1780375952` | UBI Node.js image tag |
| `NPM_CI_ARGS` | (empty) | Extra args for `npm ci` (e.g. `--legacy-peer-deps`) |
| `APP_BUILD_DIR` | `dist` | Build output directory |
| `PACKAGE_JSON_PATH` | `package.json` | Path to package.json |
| `APP_VERSION` | `unknown` | Application version string |
| `IOP` | `false` | IoP/Satellite build flag |
| `ENABLE_SENTRY` | `false` | Enable Sentry integration |

### Artifact-Only Build Args (labels)

| ARG | Default | Description |
|-----|---------|-------------|
| `LABEL_COMPONENT` | `frontend-app-hermetic` | `com.redhat.component` label |
| `LABEL_DESCRIPTION` | `HCC Frontend Application...` | Image description |
| `LABEL_URL` | `https://github.com/RedHatInsights` | Project URL |
| `LABEL_SUMMARY` | `HCC Frontend Application` | Image summary |

Override labels in your Tekton pipeline:

```yaml
  - name: build-args
    value: |
      LABEL_COMPONENT=my-app-hermetic
      LABEL_DESCRIPTION=My App - Hermetic Build
```

---

## Step 4: Caddyfile Generation (deploy target)

The deploy target automatically generates a Caddyfile using `caddyfile_gen_hermetic.js`:

- Reads `insights.appname` from `package.json` for the route path (`/apps/<appname>/*`)
- Generates the same Caddy config as `server_config_gen.sh`, but uses Node.js instead of `jq`
- **Skips generation** if a `Caddyfile` already exists in your repo (consumer override)

The generated Caddyfile provides:
- Port 8000 for application traffic
- Port 9000 for Prometheus metrics
- Route: `/apps/{APP_NAME}/*` serves from `/srv/dist`
- Environment-based route: `{$ENV_PUBLIC_PATH}/*`
- Root redirect: `/` → `/apps/chrome/index.html`

To use a custom Caddyfile, place it in your repo root. The generator will detect it and skip.

---

## Step 5: Verify and Test

### Check Build Process

Verify these steps in the build logs:

**Artifact target (default):**
- `npm ci --offline` succeeds with Cachi2 prefetched packages
- `npm run build` produces output in `dist/`
- Final image is ubi-micro based, minimal size (~50-100 MB)
- Files at `/srv/dist/`, `/srv/package.json`, `/srv/package-lock.json`

**Deploy target:**
- Same build steps as artifact
- Caddyfile generated (or consumer-provided)
- Final image is caddy-ubi based
- Files at `/srv/dist/`, Caddyfile at `/etc/caddy/Caddyfile`
- Container serves on port 8000

### Verify Image Contents

**Artifact image:**

```bash
podman build -f build-tools/Dockerfile.hermetic -t my-app-sc .
podman run --rm my-app-sc cat /srv/dist/index.html
podman run --rm my-app-sc id -u    # Should print 1001
```

**Deploy image:**

```bash
podman build -f build-tools/Dockerfile.hermetic --target deploy -t my-app .
podman run --rm -p 8000:8000 my-app
# Visit http://localhost:8000/apps/<appname>/
```

---

## Dependency Prefetch

Hermetic builds require all dependencies to be pre-fetched before the isolated build:

1. **npm prefetch**: Handled by Cachi2/Hermeto via `prefetch-input: '{"type": "npm", "path": "."}'`
2. **Git submodules**: Fetched during the network-enabled checkout step, before isolated RUN steps
3. **No networked installs**: All `RUN` commands execute with `--network=none`; `npm ci --offline` uses the prefetch cache

### Current Limitations

- **npm only**: Yarn and pnpm are not supported in hermetic mode (the builder image does not install them; `npm ci --offline` is hardcoded)
- **Sentry uploads**: Sourcemap uploads require network access. Pass Sentry build args to embed config; upload via a separate post-build pipeline task
- **app.info.json**: Generated via `build_app_info_hermetic.js` (Node.js, no `jq` dependency). Produces the same `app.info.json` and `app.info.deps.json` as the regular builder, with identical dependency serialization format
- **`jq` not available**: The hermetic builder image does not install `jq`. The Caddyfile generator uses Node.js instead. If your build scripts require `jq`, supply it via RPM generic prefetch or use an alternative

---

## Common Issues and Solutions

### Issue: npm ci fails with network errors
**Solution**: Ensure `prefetch-input` is correctly configured and `hermetic: "true"` is set.

### Issue: Cypress tries to download binaries
**Solution**: The Dockerfile sets `CYPRESS_INSTALL_BINARY=0` automatically.

### Issue: Build artifacts not found
**Solution**: Verify your build script outputs to `dist/` (or set `APP_BUILD_DIR` accordingly).

### Issue: Container fails Red Hat certification
**Solution**: The artifact target includes all required labels. Override `LABEL_*` build args for your application.

### Issue: Deploy target fails with "No Caddyfile found"
**Solution**: Update your `build-tools` submodule to a version containing `caddyfile_gen_hermetic.js`, or place a static `Caddyfile` in your repo root.

---

## Project Structure After Setup

```
your-project/
├── .tekton/
│   ├── your-project-pull-request.yaml          # (deploy target + hermetic)
│   ├── your-project-push.yaml                  # (deploy target + hermetic)
│   ├── your-project-sc-pull-request.yaml       # (artifact target, default)
│   └── your-project-sc-push.yaml               # (artifact target, default)
├── build-tools/                                 # git submodule
│   ├── Dockerfile.hermetic                      # shared multi-target Dockerfile
│   ├── caddyfile_gen_hermetic.js                # Caddyfile generator (Node.js)
│   ├── Dockerfile                               # regular (non-hermetic) build
│   └── ...
├── Caddyfile                                    # optional: consumer override
├── package.json
├── package-lock.json
└── src/
    └── ... (your source code)
```
