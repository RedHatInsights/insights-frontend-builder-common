.PHONY: help install test test-caddy test-env test-fs test-verbose lint clean

help:
	@echo "Available targets:"
	@echo "  install       - Install Python dependencies using uv"
	@echo "  test          - Run all tests"
	@echo "  test-caddy    - Run only Caddy server tests"
	@echo "  test-env      - Run only environment variable tests"
	@echo "  test-fs       - Run only filesystem structure tests"
	@echo "  test-verbose  - Run tests with verbose output"
	@echo "  lint          - Run ruff check on test code"
	@echo "  clean         - Remove test artifacts and containers"

install:
	uv pip install --system -r requirements.txt

test:
	pytest -v

test-caddy:
	pytest test_dockerfile_caddy.py -v

test-env:
	pytest test_dockerfile_env_vars.py -v

test-fs:
	pytest test_dockerfile_filesystem.py -v

test-verbose:
	pytest -v -s

lint:
	ruff check .

clean:
	-podman rm -f test-frontend-container test-envs-container test-fs-container
	-podman rmi -f test-frontend-builder:test test-frontend-builder-envs:test test-frontend-builder-fs:test
	-rm -rf test-fixtures/fake-app/build-tools
	-rm -rf test-fixtures/fake-app/dist
	-find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	-find . -type d -name .pytest_cache -exec rm -rf {} + 2>/dev/null || true
