# Build Script Guidelines

Guide for modifying the shell scripts that orchestrate HCC frontend builds.

## Script Responsibilities

| Script | Role |
|--------|------|
| `universal_build.sh` | Entry point. Detects package manager, installs deps, builds, generates metadata. |
| `build_app_info.sh` | Outputs JSON with app name, git hash/branch/tag, Node version, PF/RHCS deps. |
| `server_config_gen.sh` | Generates Caddyfile, `.dockerignore`, and `app.info.json` (legacy path). |
| `parse-secrets.sh` | Reads `.env` secrets from Konflux mount and exports as env vars. |

## Script Standards

### Shell Header

Every script must start with:

```bash
#!/bin/bash
set -euo pipefail
```

- `set -e`: Exit on any command failure
- `set -u`: Treat unset variables as errors
- `set -o pipefail`: Pipe failures propagate

Use `set -exv` only in `universal_build.sh` for build-time debug output.

### Package Manager Detection

The build system supports both npm and yarn. Detection is based on lock file presence:

```bash
if [[ -f package-lock.json ]]; then
    USES_NPM=true
elif [[ -f yarn.lock ]]; then
    USES_YARN=true
else
    echo "No lock file found"
    exit 1
fi
```

When adding new functionality that invokes npm or yarn commands, always branch on `USES_NPM` and `USES_YARN`. Never hardcode one package manager.

### Environment Variable Conventions

- Use `${VAR:-default}` for variables with sensible defaults
- Use `${VAR:?error message}` for required variables
- Document every new ARG in the Dockerfile with a comment block
- Keep ARG and ENV declarations together by logical group (Sentry, version, git metadata)

### Adding New Build Arguments

When adding a new build-time argument:

1. Add `ARG` declaration in the Dockerfile builder stage with a default value
2. Add corresponding `ENV` if the value needs to persist to runtime
3. Document with a comment block explaining purpose
4. Add to the "Key Build Arguments" table in `AGENTS.md`
5. Add a test case in `test/test_dockerfile_env_vars.py`

Example pattern from existing code:

```dockerfile
# ────────── NEW FEATURE ──────────
# NOTE: explanation of what this does and why
ARG NEW_FEATURE=default
ENV NEW_FEATURE=${NEW_FEATURE}
```

### Git Metadata Extraction

`build_app_info.sh` uses a multi-step fallback for git information because Konflux/Tekton uses detached HEAD checkouts:

1. `git branch --show-current` (regular checkout)
2. `git rev-parse --abbrev-ref HEAD` (if not "HEAD")
3. `git branch -r --points-at HEAD` (detached HEAD, find remote branch)
4. CI environment variables: `SOURCE_GIT_BRANCH`, `GITHUB_HEAD_REF`, `GITHUB_REF_NAME`, `GIT_BRANCH`, `BRANCH_NAME`

Follow this same fallback pattern when adding new git-derived metadata.

### Secret Handling

The `parse-secrets.sh` script reads from a fixed path (`/run/secrets/build-container-additional-secret/secrets`). Rules:

- Never echo secret values to stdout
- Handle missing secret files gracefully (exit 0, not 1)
- Handle permission errors with warnings
- Use `.env` format: `KEY=VALUE`, one per line, `#` for comments
- The Sentry auto-detection pattern: `{APP_NAME_UPPERCASE}_SECRET`

### Error Handling

- Use `echo "message" >&2` for error messages (stderr)
- Return empty strings from functions on failure, not error codes
- The `|| echo ""` pattern prevents `set -e` from killing the script on expected failures:

```bash
dep_list=$(npm list --silent 2>/dev/null | grep "$scope" || echo "")
```

## Modifying the Dockerfile

### Multi-Stage Structure

```text
Stage 1: builder (Node.js UBI9)
  ├── Install system deps (jq)
  ├── Install npm/yarn
  ├── Copy build scripts + source
  ├── Mount secrets
  └── Run universal_build.sh

Stage 2: runtime (Caddy UBI)
  ├── Copy LICENSE
  ├── Copy Caddyfile from builder
  ├── Copy dist/ from builder
  └── Copy package.json
```

Key rules:
- ARGs from stage 1 do NOT carry to stage 2
- Minimize layers in stage 2 (it's the final image)
- Always use `--from=builder` to copy artifacts
- The `APP_BUILD_DIR` ARG must be declared in both stages

### Adding a New Build Step

1. Add the step to `universal_build.sh` (not directly in Dockerfile RUN)
2. Keep the Dockerfile's RUN minimal: just call the orchestrator script
3. If the step needs a new tool, install it in the builder stage
4. If the step produces output needed at runtime, ensure it's copied in stage 2

## Checklist for Changes

- [ ] Script has `set -euo pipefail` header
- [ ] Both npm and yarn paths handled (if applicable)
- [ ] New ARGs documented with comment blocks
- [ ] New env vars tested in `test/test_dockerfile_env_vars.py`
- [ ] Secret values never logged
- [ ] Error messages go to stderr
- [ ] Detached HEAD scenario considered for git operations
- [ ] AGENTS.md updated if new ARGs or scripts added
