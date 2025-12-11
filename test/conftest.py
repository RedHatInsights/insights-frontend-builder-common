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


def pytest_collection_modifyitems(config, items):
    """Add markers to tests automatically."""
    for item in items:
        # Mark all tests in TestDockerfileCaddy as caddy tests
        if "TestDockerfileCaddy" in item.nodeid:
            item.add_marker(pytest.mark.caddy)
