"""
Pytest configuration for Dockerfile tests.
"""

import pytest


def pytest_configure(config):
    """Configure pytest with custom markers."""
    config.addinivalue_line(
        "markers",
        "slow: marks tests as slow (deselect with '-m \"not slow\"')"
    )
    config.addinivalue_line(
        "markers",
        "caddy: marks tests related to Caddy functionality"
    )
    config.addinivalue_line(
        "markers",
        "envvars: marks tests related to environment variables"
    )
    config.addinivalue_line(
        "markers",
        "filesystem: marks tests related to filesystem structure"
    )
    config.addinivalue_line(
        "markers",
        "hermetic: marks tests related to hermetic Dockerfile"
    )


def pytest_collection_modifyitems(config, items):
    """Add markers to tests automatically."""
    for item in items:
        # Mark all tests in TestDockerfileCaddy as caddy tests
        if "TestDockerfileCaddy" in item.nodeid:
            item.add_marker(pytest.mark.caddy)
        # Mark all tests in TestDockerfileEnvVars as envvars tests
        elif "TestDockerfileEnvVars" in item.nodeid:
            item.add_marker(pytest.mark.envvars)
        # Mark all tests in TestDockerfileFilesystem as filesystem tests
        elif "TestDockerfileFilesystem" in item.nodeid:
            item.add_marker(pytest.mark.filesystem)
        # Mark all tests in TestDockerfileHermetic as hermetic tests
        elif "TestDockerfileHermetic" in item.nodeid:
            item.add_marker(pytest.mark.hermetic)
