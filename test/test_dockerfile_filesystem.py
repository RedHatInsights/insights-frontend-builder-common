"""
Tests for Dockerfile filesystem structure.

This test suite verifies that:
1. Files are copied to the correct locations in the final image
2. Build artifacts are in the expected directories
3. Configuration files (Caddyfile, package.json) are properly placed
4. Required binaries and licenses are present
5. Directory structure matches expectations
"""

import subprocess
import pytest
import os
import json


class TestDockerfileFilesystem:
    """Test suite for Dockerfile filesystem structure."""

    IMAGE_NAME = "test-frontend-builder-fs:test"
    CONTAINER_NAME = "test-fs-container"
    APP_NAME = "test-app"

    @classmethod
    def _prepare_test_env(cls, test_dir, repo_root):
        """Prepare test environment by copying build tools."""
        build_tools_dest = os.path.join(test_dir, "build-tools")

        # Clean up any previous test artifacts
        if os.path.exists(build_tools_dest):
            subprocess.run(["rm", "-rf", build_tools_dest], check=True)

        # Create build-tools directory
        os.makedirs(build_tools_dest, exist_ok=True)

        # Copy Dockerfile
        dockerfile_src = os.path.join(repo_root, "Dockerfile")
        dockerfile_dest = os.path.join(build_tools_dest, "Dockerfile")
        subprocess.run(["cp", dockerfile_src, dockerfile_dest], check=True)

        # Copy build scripts
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

    @classmethod
    def _cleanup_test_env(cls, test_dir):
        """Clean up test environment."""
        build_tools_dest = os.path.join(test_dir, "build-tools")
        if os.path.exists(build_tools_dest):
            subprocess.run(["rm", "-rf", build_tools_dest], check=True)

    @classmethod
    def _build_image(cls, test_dir, build_args=None):
        """Build Docker image with optional build args."""
        build_cmd = [
            "podman", "build",
            "-t", cls.IMAGE_NAME,
            "-f", "build-tools/Dockerfile"
        ]

        # Add build args if provided
        if build_args:
            for key, value in build_args.items():
                build_cmd.extend(["--build-arg", f"{key}={value}"])

        build_cmd.append(".")

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

        return result

    def _cleanup_container_and_image(self):
        """Clean up container and image."""
        subprocess.run(
            ["podman", "rm", "-f", self.CONTAINER_NAME],
            capture_output=True
        )
        subprocess.run(
            ["podman", "rmi", "-f", self.IMAGE_NAME],
            capture_output=True
        )

    def _create_container(self):
        """Create container without starting it (for filesystem inspection)."""
        # Remove any existing container
        subprocess.run(
            ["podman", "rm", "-f", self.CONTAINER_NAME],
            capture_output=True
        )

        # Create container without starting
        run_cmd = [
            "podman", "create",
            "--name", self.CONTAINER_NAME,
            self.IMAGE_NAME
        ]

        result = subprocess.run(run_cmd, capture_output=True, text=True)

        if result.returncode != 0:
            pytest.fail(f"Failed to create container: {result.stderr}")

    def _file_exists_in_container(self, file_path):
        """Check if a file exists in the container."""
        result = subprocess.run(
            ["podman", "exec", self.CONTAINER_NAME, "test", "-e", file_path],
            capture_output=True
        )
        return result.returncode == 0

    def _file_exists_in_image(self, file_path):
        """Check if a file exists in the container (using create instead of run)."""
        result = subprocess.run(
            ["podman", "run", "--rm", self.IMAGE_NAME, "test", "-e", file_path],
            capture_output=True
        )
        return result.returncode == 0

    def _read_file_from_image(self, file_path):
        """Read a file from the image."""
        result = subprocess.run(
            ["podman", "run", "--rm", self.IMAGE_NAME, "cat", file_path],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            return None
        return result.stdout

    def _list_directory_in_image(self, dir_path):
        """List files in a directory in the image."""
        result = subprocess.run(
            ["podman", "run", "--rm", self.IMAGE_NAME, "ls", "-la", dir_path],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            return None
        return result.stdout

    def test_license_file_exists(self):
        """Test that LICENSE file is copied to /licenses/."""
        print("\n=== Testing LICENSE file location ===")

        test_script_dir = os.path.dirname(__file__)
        repo_root = os.path.abspath(os.path.join(test_script_dir, ".."))
        test_dir = os.path.join(test_script_dir, "test-fixtures", "fake-app")

        try:
            self._prepare_test_env(test_dir, repo_root)
            self._build_image(test_dir)

            # Check if LICENSE exists at /licenses/LICENSE
            license_exists = self._file_exists_in_image("/licenses/LICENSE")
            assert license_exists, "LICENSE file not found at /licenses/LICENSE"

            # Verify it has content
            license_content = self._read_file_from_image("/licenses/LICENSE")
            assert license_content is not None, "LICENSE file is empty"
            assert "MIT License" in license_content or "LICENSE" in license_content.upper(), \
                "LICENSE file doesn't contain expected content"

            print("✓ LICENSE file exists at /licenses/LICENSE with content")

        finally:
            self._cleanup_container_and_image()
            self._cleanup_test_env(test_dir)

    def test_caddyfile_exists(self):
        """Test that Caddyfile is copied to /etc/caddy/Caddyfile."""
        print("\n=== Testing Caddyfile location ===")

        test_script_dir = os.path.dirname(__file__)
        repo_root = os.path.abspath(os.path.join(test_script_dir, ".."))
        test_dir = os.path.join(test_script_dir, "test-fixtures", "fake-app")

        try:
            self._prepare_test_env(test_dir, repo_root)
            self._build_image(test_dir)

            # Check if Caddyfile exists
            caddyfile_exists = self._file_exists_in_image("/etc/caddy/Caddyfile")
            assert caddyfile_exists, "Caddyfile not found at /etc/caddy/Caddyfile"

            # Verify it has content
            caddyfile_content = self._read_file_from_image("/etc/caddy/Caddyfile")
            assert caddyfile_content is not None, "Caddyfile is empty"
            assert ":8000" in caddyfile_content, "Caddyfile doesn't contain port 8000"
            assert "/apps/" in caddyfile_content or "test-app" in caddyfile_content, \
                "Caddyfile doesn't contain app route configuration"

            print("✓ Caddyfile exists at /etc/caddy/Caddyfile with valid configuration")

        finally:
            self._cleanup_container_and_image()
            self._cleanup_test_env(test_dir)

    def test_package_json_exists(self):
        """Test that package.json is copied to the working directory."""
        print("\n=== Testing package.json location ===")

        test_script_dir = os.path.dirname(__file__)
        repo_root = os.path.abspath(os.path.join(test_script_dir, ".."))
        test_dir = os.path.join(test_script_dir, "test-fixtures", "fake-app")

        try:
            self._prepare_test_env(test_dir, repo_root)
            self._build_image(test_dir)

            # Check if package.json exists in working directory
            # Try both /srv/package.json and ./package.json
            package_json_paths = ["/srv/package.json", "./package.json", "package.json"]

            package_json_found = False
            for path in package_json_paths:
                if self._file_exists_in_image(path):
                    package_json_content = self._read_file_from_image(path)
                    if package_json_content:
                        try:
                            data = json.loads(package_json_content)
                            assert data.get("insights", {}).get("appname") == "test-app", \
                                f"package.json doesn't contain expected appname"
                            print(f"✓ package.json found at {path} with correct content")
                            package_json_found = True
                            break
                        except json.JSONDecodeError:
                            pass

            assert package_json_found, f"package.json not found at any of: {package_json_paths}"

        finally:
            self._cleanup_container_and_image()
            self._cleanup_test_env(test_dir)

    def test_dist_directory_structure(self):
        """Test that dist directory contains expected build artifacts."""
        print("\n=== Testing dist directory structure ===")

        test_script_dir = os.path.dirname(__file__)
        repo_root = os.path.abspath(os.path.join(test_script_dir, ".."))
        test_dir = os.path.join(test_script_dir, "test-fixtures", "fake-app")

        try:
            self._prepare_test_env(test_dir, repo_root)
            self._build_image(test_dir)

            # Try different possible locations for dist
            dist_paths = ["/srv/dist", "./dist", "dist"]

            dist_found = False
            for dist_path in dist_paths:
                dist_listing = self._list_directory_in_image(dist_path)
                if dist_listing:
                    print(f"Found dist directory at {dist_path}")
                    print(f"Contents:\n{dist_listing}")

                    # Check for expected files
                    expected_files = ["index.html", "app.info.json", "manifest.json"]
                    for expected_file in expected_files:
                        file_path = f"{dist_path}/{expected_file}"
                        file_exists = self._file_exists_in_image(file_path)
                        assert file_exists, f"{expected_file} not found at {file_path}"
                        print(f"  ✓ {expected_file} exists")

                    # Check subdirectories
                    css_exists = self._file_exists_in_image(f"{dist_path}/css/app.css")
                    js_exists = self._file_exists_in_image(f"{dist_path}/js/app.js")

                    assert css_exists, f"css/app.css not found in {dist_path}"
                    assert js_exists, f"js/app.js not found in {dist_path}"

                    print(f"  ✓ css/app.css exists")
                    print(f"  ✓ js/app.js exists")

                    dist_found = True
                    break

            assert dist_found, f"dist directory not found at any of: {dist_paths}"
            print(f"✓ dist directory contains all expected build artifacts")

        finally:
            self._cleanup_container_and_image()
            self._cleanup_test_env(test_dir)

    def test_app_info_json_content(self):
        """Test that app.info.json is generated with correct content."""
        print("\n=== Testing app.info.json content ===")

        test_script_dir = os.path.dirname(__file__)
        repo_root = os.path.abspath(os.path.join(test_script_dir, ".."))
        test_dir = os.path.join(test_script_dir, "test-fixtures", "fake-app")

        try:
            self._prepare_test_env(test_dir, repo_root)
            self._build_image(test_dir)

            # Try different possible locations
            app_info_paths = [
                "/srv/dist/app.info.json",
                "dist/app.info.json",
                "./dist/app.info.json"
            ]

            app_info_found = False
            for path in app_info_paths:
                content = self._read_file_from_image(path)
                if content:
                    try:
                        data = json.loads(content)

                        # Check required fields
                        assert "app_name" in data, "app.info.json missing app_name field"
                        assert "src_hash" in data, "app.info.json missing src_hash field"
                        assert "src_branch" in data, "app.info.json missing src_branch field"

                        # Verify app_name is correct
                        assert data["app_name"] == "test-app", \
                            f"Expected app_name 'test-app', got '{data['app_name']}'"

                        print(f"✓ app.info.json found at {path}")
                        print(f"  app_name: {data['app_name']}")
                        print(f"  src_hash: {data['src_hash']}")
                        print(f"  src_branch: {data['src_branch']}")

                        app_info_found = True
                        break
                    except json.JSONDecodeError as e:
                        pytest.fail(f"app.info.json at {path} is not valid JSON: {e}")

            assert app_info_found, f"app.info.json not found at any of: {app_info_paths}"

        finally:
            self._cleanup_container_and_image()
            self._cleanup_test_env(test_dir)

    def test_valpop_binary_exists(self):
        """Test that valpop binary is copied to /usr/local/bin/valpop."""
        print("\n=== Testing valpop binary location ===")

        test_script_dir = os.path.dirname(__file__)
        repo_root = os.path.abspath(os.path.join(test_script_dir, ".."))
        test_dir = os.path.join(test_script_dir, "test-fixtures", "fake-app")

        try:
            self._prepare_test_env(test_dir, repo_root)
            self._build_image(test_dir)

            # Check if valpop exists
            valpop_exists = self._file_exists_in_image("/usr/local/bin/valpop")
            assert valpop_exists, "valpop binary not found at /usr/local/bin/valpop"

            # Check if it's executable
            result = subprocess.run(
                ["podman", "run", "--rm", self.IMAGE_NAME, "test", "-x", "/usr/local/bin/valpop"],
                capture_output=True
            )
            assert result.returncode == 0, "valpop binary is not executable"

            print("✓ valpop binary exists at /usr/local/bin/valpop and is executable")

        finally:
            self._cleanup_container_and_image()
            self._cleanup_test_env(test_dir)

    def test_custom_build_dir_location(self):
        """Test that custom APP_BUILD_DIR is respected in final image."""
        print("\n=== Testing custom APP_BUILD_DIR location ===")

        test_script_dir = os.path.dirname(__file__)
        repo_root = os.path.abspath(os.path.join(test_script_dir, ".."))
        test_dir = os.path.join(test_script_dir, "test-fixtures", "fake-app")

        try:
            self._prepare_test_env(test_dir, repo_root)

            # Build with custom build directory
            custom_dir = "custom-output"
            build_args = {"APP_BUILD_DIR": custom_dir}
            self._build_image(test_dir, build_args)

            # The Dockerfile copies ${APP_BUILD_DIR} to "dist" in the final image
            # So regardless of APP_BUILD_DIR name, it should end up as "dist" in final image
            # Let's verify the files are there
            dist_paths = ["/srv/dist", "dist", "./dist"]

            files_found = False
            for dist_path in dist_paths:
                if self._file_exists_in_image(f"{dist_path}/index.html"):
                    print(f"✓ Build artifacts from custom build dir found at {dist_path}")
                    files_found = True
                    break

            assert files_found, \
                "Build artifacts not found - custom APP_BUILD_DIR may not have been processed correctly"

        finally:
            self._cleanup_container_and_image()
            self._cleanup_test_env(test_dir)


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
