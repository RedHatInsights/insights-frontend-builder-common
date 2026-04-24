# Testing Guidelines

Guide for writing and maintaining the pytest-based Dockerfile integration tests.

## Test Architecture

Tests verify the built Docker image by:

1. Copying build scripts from repo root to `test-fixtures/fake-app/build-tools/`
2. Building a container image using `podman build`
3. Starting a container and making HTTP requests or inspecting the filesystem
4. Cleaning up containers and images after each suite

Each test class is self-contained: it builds its own image, runs its own container, and tears down after completion.

## Test Organization

| File | Scope | Marker |
|------|-------|--------|
| `test_dockerfile_caddy.py` | Caddy server responses, routes, content types | `caddy` |
| `test_dockerfile_env_vars.py` | Build ARGs, runtime ENVs, default values | `envvars` |
| `test_dockerfile_filesystem.py` | File locations, directory structure, metadata | `filesystem` |
| `test_dockerfile_hermetic.py` | Hermetic Dockerfile build and output | `hermetic` |
| `conftest.py` | Pytest markers and automatic marker assignment | - |

## Test Class Pattern

All test classes follow this structure:

```python
class TestDockerfileSomething:
    """Description of what this suite tests."""

    IMAGE_NAME = "test-frontend-builder-something:test"
    CONTAINER_NAME = "test-something-container"

    @classmethod
    def setup_class(cls):
        """Build the image once for all tests in this class."""
        # Copy build scripts to test fixture
        # Run podman build
        # Start container (if needed)

    @classmethod
    def teardown_class(cls):
        """Clean up container and image."""
        # Stop and remove container
        # Remove image
        # Clean up copied files

    def test_specific_behavior(self):
        """Test one specific aspect."""
        # Make HTTP request or inspect container
        # Assert expected behavior
```

### Key Patterns

**Building the image:**

```python
subprocess.run(
    ["podman", "build", "-f", "build-tools/Dockerfile", "-t", cls.IMAGE_NAME, "."],
    cwd=str(fixture_dir),
    check=True,
    capture_output=True,
    text=True,
)
```

**Running the container:**

```python
subprocess.run(
    ["podman", "run", "-d", "--name", cls.CONTAINER_NAME,
     "-p", f"{HOST_PORT}:8000", cls.IMAGE_NAME],
    check=True,
)
```

**Waiting for Caddy to be ready:**

```python
def _wait_for_caddy(self, timeout=30):
    """Poll until Caddy responds on the health endpoint."""
    start = time.time()
    while time.time() - start < timeout:
        try:
            requests.get(f"http://localhost:{HOST_PORT}/", timeout=2)
            return
        except requests.ConnectionError:
            time.sleep(1)
    raise TimeoutError("Caddy did not start in time")
```

**Inspecting container filesystem:**

```python
result = subprocess.run(
    ["podman", "exec", cls.CONTAINER_NAME, "cat", "/srv/dist/app.info.json"],
    capture_output=True, text=True, check=True,
)
data = json.loads(result.stdout)
assert data["app_name"] == "test-app"
```

## Writing New Tests

### Adding a Test to an Existing Suite

1. Add a new method to the appropriate test class
2. Name it `test_<what_it_verifies>`
3. Use descriptive assertions with error messages:

```python
def test_new_env_var_default(self):
    """MY_VAR defaults to 'hello' when not specified."""
    result = subprocess.run(
        ["podman", "exec", self.CONTAINER_NAME, "printenv", "MY_VAR"],
        capture_output=True, text=True,
    )
    assert result.stdout.strip() == "hello", (
        f"Expected MY_VAR='hello', got '{result.stdout.strip()}'"
    )
```

### Adding a New Test Suite

1. Create `test/test_dockerfile_<domain>.py`
2. Add a pytest marker in `conftest.py`:

```python
config.addinivalue_line("markers", "newdomain: description")
```

3. Add automatic marker assignment in `pytest_collection_modifyitems`
4. Add a Makefile target:

```makefile
test-newdomain:
    pytest test_dockerfile_newdomain.py -v
```

5. Add a step in `.github/workflows/test-dockerfile.yml`

### Testing Build Arguments

To test a new `ARG`:

```python
def test_custom_arg(self):
    """Build with custom ARG value and verify behavior."""
    # Build with custom arg
    subprocess.run(
        ["podman", "build", "-f", "build-tools/Dockerfile",
         "--build-arg", "MY_ARG=custom_value",
         "-t", "test-custom:test", "."],
        cwd=str(self.FIXTURE_DIR),
        check=True,
    )
    # Run container and verify
    # ...
    # Clean up
    subprocess.run(["podman", "rmi", "-f", "test-custom:test"], check=False)
```

### Testing with Secrets

For tests that need Konflux-style secrets, create a temporary file and mount it:

```python
# Create temp secret file
with tempfile.NamedTemporaryFile(mode='w', suffix='.env', delete=False) as f:
    f.write("MY_SECRET=test-value\n")
    secret_path = f.name

# Build with secret mount
subprocess.run(
    ["podman", "build", "--secret",
     f"id=build-container-additional-secret/secrets,src={secret_path}",
     "-f", "build-tools/Dockerfile", "-t", "test-secrets:test", "."],
    cwd=str(self.FIXTURE_DIR),
    check=True,
)
```

## Running Tests

```bash
cd test

# All tests
make test

# Single suite
make test-caddy
make test-env
make test-fs

# Single test
pytest test_dockerfile_caddy.py::TestDockerfileCaddy::test_app_route_serves_index_html -v

# With output
pytest -v -s

# Lint
make lint
```

## CI Integration

Tests run via `.github/workflows/test-dockerfile.yml` on:
- PRs to `master`
- Push to `master` (after merge)
- Manual trigger (`workflow_dispatch`)

Each test suite runs as a separate step with a 15-minute timeout. Test artifacts are uploaded and retained for 7 days.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Port 8080 in use | Change `HOST_PORT` in test file or stop conflicting process |
| Container won't start | Check `podman logs <container-name>` for Caddy errors |
| Build timeout | Increase timeout in CI workflow or check network/registry access |
| Import errors | Ensure you're in `test/` directory with deps installed (`make install`) |
| Podman permission errors | Ensure rootless Podman is configured (`podman system migrate`) |

## Checklist for New Tests

- [ ] Test method named `test_<what_it_verifies>`
- [ ] Descriptive assertion messages
- [ ] Cleanup in `teardown_class` (containers, images, temp files)
- [ ] Timeout handling for HTTP requests
- [ ] Added to CI workflow if new suite
- [ ] Added to Makefile if new suite
- [ ] `ruff check` passes on new test code
