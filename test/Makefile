.PHONY: help install test test-caddy test-env test-verbose clean

help:
	@echo "Available targets:"
	@echo "  install       - Install Python dependencies"
	@echo "  test          - Run all tests"
	@echo "  test-caddy    - Run only Caddy server tests"
	@echo "  test-env      - Run only environment variable tests"
	@echo "  test-verbose  - Run tests with verbose output"
	@echo "  clean         - Remove test artifacts and containers"

install:
	pip install -r requirements.txt

test:
	pytest -v

test-caddy:
	pytest test_dockerfile_caddy.py -v

test-env:
	pytest test_dockerfile_env_vars.py -v

test-verbose:
	pytest -v -s

clean:
	-podman rm -f test-frontend-container test-envs-container
	-podman rmi -f test-frontend-builder:test test-frontend-builder-envs:test
	-rm -rf test-fixtures/fake-app/build-tools
	-rm -rf test-fixtures/fake-app/dist
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -type d -name .pytest_cache -exec rm -rf {} +
