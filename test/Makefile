.PHONY: help install test test-verbose clean

help:
	@echo "Available targets:"
	@echo "  install       - Install Python dependencies"
	@echo "  test          - Run all tests"
	@echo "  test-verbose  - Run tests with verbose output"
	@echo "  clean         - Remove test artifacts and containers"

install:
	pip install -r requirements.txt

test:
	pytest test_dockerfile_caddy.py

test-verbose:
	pytest test_dockerfile_caddy.py -v -s

clean:
	-podman rm -f test-frontend-container
	-podman rmi -f test-frontend-builder:test
	-rm -rf test-fixtures/fake-app/build-tools
	-rm -rf test-fixtures/fake-app/dist
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -type d -name .pytest_cache -exec rm -rf {} +
