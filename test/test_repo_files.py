"""
Tests for repository-level configuration files.

This test suite verifies that shared configuration files
(e.g. .dockerignore) exist at the repo root with the expected entries.
These tests run without Podman — they only inspect the local filesystem.
"""

import os

import pytest


class TestRepoFiles:
    """Test suite for repository-level configuration files."""

    @classmethod
    def setup_class(cls):
        """Resolve paths once before all tests."""
        test_script_dir = os.path.dirname(__file__)
        cls.repo_root = os.path.abspath(os.path.join(test_script_dir, ".."))

    def test_dockerignore_exists(self):
        """Test that .dockerignore exists at the repository root."""
        dockerignore_path = os.path.join(self.repo_root, ".dockerignore")
        assert os.path.isfile(dockerignore_path), (
            ".dockerignore not found at repository root"
        )

    def test_dockerignore_entries(self):
        """Test that .dockerignore contains the required exclusion entries."""
        dockerignore_path = os.path.join(self.repo_root, ".dockerignore")
        with open(dockerignore_path) as f:
            entries = [line.strip() for line in f if line.strip() and not line.startswith("#")]

        required_entries = [".vscode", ".claude", "node_modules", ".git"]
        for entry in required_entries:
            assert entry in entries, (
                f".dockerignore is missing required entry: {entry}"
            )

    def test_dockerignore_no_sensitive_paths_included(self):
        """Test that .dockerignore does not accidentally exclude build-critical paths."""
        dockerignore_path = os.path.join(self.repo_root, ".dockerignore")
        with open(dockerignore_path) as f:
            entries = [line.strip() for line in f if line.strip() and not line.startswith("#")]

        # These paths must NOT be excluded — they are needed during Docker builds
        critical_paths = ["Dockerfile", "*.sh", "src", "test"]
        for path in critical_paths:
            assert path not in entries, (
                f".dockerignore must not exclude build-critical path: {path}"
            )


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
