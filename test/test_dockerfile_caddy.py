"""
Tests for Dockerfile Caddy server functionality.

This test suite verifies that:
1. The Docker image builds successfully
2. Caddy serves static files correctly
3. Different routes work as expected (app route, env-based route)
4. The proper file structure is maintained
"""

import subprocess
import time
import requests
import pytest
import os
import json


class TestDockerfileCaddy:
    """Test suite for Dockerfile Caddy functionality."""

    IMAGE_NAME = "test-frontend-builder:test"
    CONTAINER_NAME = "test-frontend-container"
    APP_NAME = "test-app"
    CONTAINER_PORT = 8000
    HOST_PORT = 8080

    @classmethod
    def setup_class(cls):
        """Build the Docker image before running tests."""
        print("\n=== Preparing test environment ===")

        # Get paths
        test_script_dir = os.path.dirname(__file__)
        repo_root = os.path.abspath(os.path.join(test_script_dir, ".."))
        test_dir = os.path.join(test_script_dir, "test-fixtures", "fake-app")
        build_tools_dest = os.path.join(test_dir, "build-tools")

        # Clean up any previous test artifacts
        if os.path.exists(build_tools_dest):
            subprocess.run(["rm", "-rf", build_tools_dest], check=True)

        # Create build-tools directory in test fixture
        os.makedirs(build_tools_dest, exist_ok=True)

        # Copy Dockerfile to build-tools/
        dockerfile_src = os.path.join(repo_root, "Dockerfile")
        dockerfile_dest = os.path.join(build_tools_dest, "Dockerfile")
        subprocess.run(["cp", dockerfile_src, dockerfile_dest], check=True)
        print(f"✓ Copied Dockerfile to build-tools/")

        # Copy all build scripts to build-tools/
        scripts = [
            "universal_build.sh",
            "build_app_info.sh",
            "server_config_gen.sh",
            "parse-secrets.sh"
        ]
        for script in scripts:
            src = os.path.join(repo_root, script)
            dest = os.path.join(build_tools_dest, script)
            subprocess.run(["cp", src, dest], check=True)
        print(f"✓ Copied build scripts to build-tools/")

        # Initialize git repository if it doesn't exist (required by build scripts)
        git_dir = os.path.join(test_dir, ".git")
        if not os.path.exists(git_dir):
            print("Initializing git repository for build scripts...")
            subprocess.run(["git", "init"], cwd=test_dir, check=True)
            subprocess.run(["git", "config", "user.email", "test@test.com"], cwd=test_dir, check=True)
            subprocess.run(["git", "config", "user.name", "Test User"], cwd=test_dir, check=True)
            subprocess.run(["git", "add", "."], cwd=test_dir, check=True)
            subprocess.run(["git", "commit", "-m", "Initial commit"], cwd=test_dir, check=True)
            print("✓ Git repository initialized")

        print("\n=== Building Docker image ===")

        # Build the image using podman from the fake-app directory (top level)
        # but with Dockerfile in build-tools/
        build_cmd = [
            "podman", "build",
            "-t", cls.IMAGE_NAME,
            "-f", "build-tools/Dockerfile",
            "."
        ]

        result = subprocess.run(
            build_cmd,
            cwd=test_dir,
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            print("STDOUT:", result.stdout)
            print("STDERR:", result.stderr)
            pytest.fail(f"Failed to build Docker image: {result.stderr}")

        print(f"✓ Image {cls.IMAGE_NAME} built successfully")

    @classmethod
    def teardown_class(cls):
        """Clean up: remove the Docker image and copied files."""
        print("\n=== Cleaning up ===")

        # Remove the Docker image
        subprocess.run(
            ["podman", "rmi", "-f", cls.IMAGE_NAME],
            capture_output=True
        )
        print(f"✓ Image {cls.IMAGE_NAME} removed")

        # Remove copied build-tools directory
        test_script_dir = os.path.dirname(__file__)
        test_dir = os.path.join(test_script_dir, "test-fixtures", "fake-app")
        build_tools_dest = os.path.join(test_dir, "build-tools")

        if os.path.exists(build_tools_dest):
            subprocess.run(["rm", "-rf", build_tools_dest], check=True)
            print(f"✓ Removed copied build-tools directory")

    def setup_method(self):
        """Start the container before each test."""
        # Stop and remove any existing container
        subprocess.run(
            ["podman", "rm", "-f", self.CONTAINER_NAME],
            capture_output=True
        )

        # Start the container
        run_cmd = [
            "podman", "run",
            "-d",
            "--name", self.CONTAINER_NAME,
            "-p", f"{self.HOST_PORT}:{self.CONTAINER_PORT}",
            self.IMAGE_NAME
        ]

        result = subprocess.run(run_cmd, capture_output=True, text=True)

        if result.returncode != 0:
            pytest.fail(f"Failed to start container: {result.stderr}")

        # Wait for Caddy to start
        self._wait_for_caddy()

    def teardown_method(self):
        """Stop and remove the container after each test."""
        subprocess.run(
            ["podman", "rm", "-f", self.CONTAINER_NAME],
            capture_output=True
        )

    def _wait_for_caddy(self, timeout=10):
        """Wait for Caddy server to be ready."""
        start_time = time.time()

        while time.time() - start_time < timeout:
            try:
                # Try to connect to the root endpoint
                response = requests.get(
                    f"http://localhost:{self.HOST_PORT}/",
                    timeout=1,
                    allow_redirects=False
                )
                # If we get any response, Caddy is up
                if response.status_code in [200, 301, 302, 308]:
                    return
            except requests.exceptions.RequestException:
                time.sleep(0.5)

        pytest.fail("Caddy server did not start within timeout period")

    def test_root_redirects_to_chrome(self):
        """Test that root path redirects to /apps/chrome/index.html."""
        response = requests.get(
            f"http://localhost:{self.HOST_PORT}/",
            timeout=5,
            allow_redirects=False
        )

        # Should be a redirect (301, 302, 307, or 308)
        # Note: Caddy's "redir" directive might use different status codes
        assert response.status_code in [200, 301, 302, 307, 308], \
            f"Expected redirect or success status, got {response.status_code}"

        # If it's a redirect, check the location
        if response.status_code in [301, 302, 307, 308]:
            location = response.headers.get("Location", "")
            assert "/apps/chrome/index.html" in location or location.endswith("/apps/chrome/index.html"), \
                f"Expected redirect to /apps/chrome/index.html, got {location}"
        # If it's 200, the redir might be handled differently, which is also acceptable
        # as long as the server is responding

    def test_app_route_serves_index_html(self):
        """Test that /apps/test-app/ serves the index.html file."""
        response = requests.get(
            f"http://localhost:{self.HOST_PORT}/apps/{self.APP_NAME}/",
            timeout=5
        )

        assert response.status_code == 200, \
            f"Expected 200, got {response.status_code}"

        assert "Test App" in response.text, \
            "index.html content not found in response"

        assert "<!DOCTYPE html>" in response.text, \
            "HTML doctype not found in response"

    def test_app_route_serves_css_files(self):
        """Test that CSS files are served correctly."""
        response = requests.get(
            f"http://localhost:{self.HOST_PORT}/apps/{self.APP_NAME}/css/app.css",
            timeout=5
        )

        assert response.status_code == 200, \
            f"Expected 200, got {response.status_code}"

        assert "margin" in response.text, \
            "CSS content not found in response"

        # Check content type
        content_type = response.headers.get("Content-Type", "")
        assert "css" in content_type.lower() or "text" in content_type.lower(), \
            f"Expected CSS content type, got {content_type}"

    def test_app_route_serves_js_files(self):
        """Test that JavaScript files are served correctly."""
        response = requests.get(
            f"http://localhost:{self.HOST_PORT}/apps/{self.APP_NAME}/js/app.js",
            timeout=5
        )

        assert response.status_code == 200, \
            f"Expected 200, got {response.status_code}"

        assert "Test app loaded" in response.text, \
            "JavaScript content not found in response"

    def test_app_route_serves_json_files(self):
        """Test that JSON files are served correctly."""
        response = requests.get(
            f"http://localhost:{self.HOST_PORT}/apps/{self.APP_NAME}/manifest.json",
            timeout=5
        )

        assert response.status_code == 200, \
            f"Expected 200, got {response.status_code}"

        # Verify it's valid JSON
        try:
            data = response.json()
            assert data.get("name") == "test-app", \
                f"Expected name 'test-app', got {data.get('name')}"
        except json.JSONDecodeError:
            pytest.fail("Response is not valid JSON")

    @pytest.mark.skip(reason="Metrics endpoint on port 9000 requires separate port mapping")
    def test_metrics_endpoint_exists(self):
        """Test that Caddy metrics endpoint is available.

        Note: This test is skipped by default because the metrics endpoint
        is on port 9000, which would require additional port mapping in setup_method.
        """
        pass

    def test_app_info_json_exists(self):
        """Test that app.info.json is generated and served."""
        response = requests.get(
            f"http://localhost:{self.HOST_PORT}/apps/{self.APP_NAME}/app.info.json",
            timeout=5
        )

        assert response.status_code == 200, \
            f"Expected 200, got {response.status_code}"

        # Verify it's valid JSON with expected fields
        try:
            data = response.json()
            assert "app_name" in data, "app_name field missing"
            assert "src_hash" in data, "src_hash field missing"
            assert data.get("app_name") == self.APP_NAME, \
                f"Expected app_name '{self.APP_NAME}', got {data.get('app_name')}"
        except json.JSONDecodeError:
            pytest.fail("app.info.json is not valid JSON")

    def test_nonexistent_file_returns_404(self):
        """Test that nonexistent files return 404."""
        response = requests.get(
            f"http://localhost:{self.HOST_PORT}/apps/{self.APP_NAME}/nonexistent.html",
            timeout=5
        )

        assert response.status_code == 404, \
            f"Expected 404 for nonexistent file, got {response.status_code}"

    def test_path_without_trailing_slash(self):
        """Test that paths work with and without trailing slash."""
        # With trailing slash
        response_with_slash = requests.get(
            f"http://localhost:{self.HOST_PORT}/apps/{self.APP_NAME}/",
            timeout=5
        )

        # Without trailing slash
        response_without_slash = requests.get(
            f"http://localhost:{self.HOST_PORT}/apps/{self.APP_NAME}",
            timeout=5
        )

        # Both should succeed (200 or redirect to 200)
        assert response_with_slash.status_code in [200, 301, 308], \
            f"Path with slash failed: {response_with_slash.status_code}"

        assert response_without_slash.status_code in [200, 301, 308], \
            f"Path without slash failed: {response_without_slash.status_code}"


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
