"""
Tests for repository-level configuration files.

This test suite verifies that shared configuration files
(e.g. .dockerignore) exist at the repo root with the expected entries.
These tests run without Podman — they only inspect the local filesystem.
"""

import fnmatch
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
        """Test that .dockerignore does not accidentally exclude build-critical paths.

        Uses fnmatch to evaluate Docker-compatible pattern matching semantics,
        catching wildcard and directory-form rules (e.g. ``*``, ``test/``,
        ``**/*.sh``) that would exclude protected paths.
        """
        dockerignore_path = os.path.join(self.repo_root, ".dockerignore")
        with open(dockerignore_path) as f:
            entries = [line.strip() for line in f if line.strip() and not line.startswith("#")]

        # Representative files that must survive the ignore filter.
        # Each is a realistic path that could be matched by overly broad rules.
        critical_files = [
            "Dockerfile",
            "universal_build.sh",
            "src/frontend-build.sh",
            "test/conftest.py",
            "build_app_info.sh",
        ]

        for entry in entries:
            # Normalise directory-form rules: "test/" should match "test/conftest.py"
            pattern = entry.rstrip("/")
            for filepath in critical_files:
                # Direct match (e.g. pattern "src" matches path "src")
                matched = fnmatch.fnmatch(filepath, pattern)
                # Directory-prefix match (e.g. pattern "src" matches "src/frontend-build.sh")
                if not matched:
                    matched = filepath.startswith(pattern + "/")
                # Recursive-glob match (e.g. "**/*.sh" → "*.sh" applied to basename)
                if not matched and pattern.startswith("**/"):
                    matched = fnmatch.fnmatch(
                        os.path.basename(filepath), pattern[3:]
                    )
                assert not matched, (
                    f".dockerignore entry '{entry}' would exclude "
                    f"build-critical path: {filepath}"
                )


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
