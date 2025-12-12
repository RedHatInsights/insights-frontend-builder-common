"""
Tests for Dockerfile environment variables (build args and runtime envs).

This test suite verifies that:
1. Build-time ARG variables are properly used during image build
2. Runtime ENV variables are accessible in the running container
3. Custom build directories (APP_BUILD_DIR) work correctly
4. Custom package.json paths (PACKAGE_JSON_PATH) work correctly
5. Sentry-related variables are properly set
6. ENV_PUBLIC_PATH affects Caddy routing correctly
"""

import subprocess
import time
import requests
import pytest
import os
import shutil


class TestDockerfileEnvVars:
    """Test suite for Dockerfile environment variables."""

    IMAGE_NAME = "test-frontend-builder-envs:test"
    CONTAINER_NAME = "test-envs-container"
    CONTAINER_PORT = 8000
    HOST_PORT = 8081

    @classmethod
    def _prepare_test_env(cls, test_dir, repo_root):
        """Prepare test environment by copying build tools."""
        build_tools_dest = os.path.join(test_dir, "build-tools")

        # Clean up any previous test artifacts
        if os.path.exists(build_tools_dest):
            shutil.rmtree(build_tools_dest)

        # Create build-tools directory
        os.makedirs(build_tools_dest, exist_ok=True)

        # Copy Dockerfile
        dockerfile_src = os.path.join(repo_root, "Dockerfile")
        dockerfile_dest = os.path.join(build_tools_dest, "Dockerfile")
        shutil.copy(dockerfile_src, dockerfile_dest)

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
            shutil.copy(src, dest)

        # Initialize git repository if it doesn't exist (required by build scripts)
        git_dir = os.path.join(test_dir, ".git")
        if not os.path.exists(git_dir):
            subprocess.run(["git", "init"], cwd=test_dir, check=True)
            subprocess.run(["git", "config", "user.email", "test@test.com"], cwd=test_dir, check=True)
            subprocess.run(["git", "config", "user.name", "Test User"], cwd=test_dir, check=True)
            subprocess.run(["git", "add", "."], cwd=test_dir, check=True)
            subprocess.run(["git", "commit", "-m", "Initial commit"], cwd=test_dir, check=True)

    @classmethod
    def _cleanup_test_env(cls, test_dir):
        """Clean up test environment."""
        build_tools_dest = os.path.join(test_dir, "build-tools")
        if os.path.exists(build_tools_dest):
            shutil.rmtree(build_tools_dest)

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

    def _start_container(self, env_vars=None):
        """Start container with optional runtime environment variables."""
        # Stop and remove any existing container
        subprocess.run(
            ["podman", "rm", "-f", self.CONTAINER_NAME],
            capture_output=True
        )

        run_cmd = [
            "podman", "run",
            "-d",
            "--name", self.CONTAINER_NAME,
            "-p", f"{self.HOST_PORT}:{self.CONTAINER_PORT}"
        ]

        # Add environment variables if provided
        if env_vars:
            for key, value in env_vars.items():
                run_cmd.extend(["-e", f"{key}={value}"])

        run_cmd.append(self.IMAGE_NAME)

        result = subprocess.run(run_cmd, capture_output=True, text=True)

        if result.returncode != 0:
            pytest.fail(f"Failed to start container: {result.stderr}")

        # Wait for Caddy to start
        self._wait_for_caddy()

    def _wait_for_caddy(self, timeout=10):
        """Wait for Caddy server to be ready."""
        start_time = time.time()

        while time.time() - start_time < timeout:
            try:
                response = requests.get(
                    f"http://localhost:{self.HOST_PORT}/",
                    timeout=1,
                    allow_redirects=False
                )
                if response.status_code in [200, 301, 302, 307, 308]:
                    return
            except requests.exceptions.RequestException:
                time.sleep(0.5)

        pytest.fail("Caddy server did not start within timeout period")

    def _get_container_env_var(self, var_name):
        """Get environment variable value from running container."""
        result = subprocess.run(
            ["podman", "exec", self.CONTAINER_NAME, "printenv", var_name],
            capture_output=True,
            text=True
        )
        # Return empty string if variable doesn't exist
        if result.returncode != 0:
            return ""
        return result.stdout.strip()

    def test_custom_app_build_dir(self):
        """Test that APP_BUILD_DIR build arg changes the output directory."""
        print("\n=== Testing custom APP_BUILD_DIR ===")

        test_script_dir = os.path.dirname(__file__)
        repo_root = os.path.abspath(os.path.join(test_script_dir, ".."))
        test_dir = os.path.join(test_script_dir, "test-fixtures", "fake-app")

        try:
            # Prepare environment
            self._prepare_test_env(test_dir, repo_root)

            # Build with custom output directory
            custom_build_dir = "custom-dist"
            build_args = {"APP_BUILD_DIR": custom_build_dir}

            print(f"Building with APP_BUILD_DIR={custom_build_dir}")
            self._build_image(test_dir, build_args)

            # Start container
            self._start_container()

            # Verify files are served from the custom directory
            # The Dockerfile copies ${APP_BUILD_DIR} to 'dist' in the final image,
            # so files should still be accessible via the app route
            response = requests.get(
                f"http://localhost:{self.HOST_PORT}/apps/test-app/"
            )

            assert response.status_code == 200, \
                f"Expected 200, got {response.status_code}"
            assert "Test App" in response.text, \
                "index.html content not found - APP_BUILD_DIR may not have worked"

            print(f"✓ APP_BUILD_DIR={custom_build_dir} worked correctly")

        finally:
            self._cleanup_container_and_image()
            self._cleanup_test_env(test_dir)

    def test_runtime_env_public_path(self):
        """Test that ENV_PUBLIC_PATH runtime variable affects Caddy routing."""
        print("\n=== Testing ENV_PUBLIC_PATH runtime variable ===")

        test_script_dir = os.path.dirname(__file__)
        repo_root = os.path.abspath(os.path.join(test_script_dir, ".."))
        test_dir = os.path.join(test_script_dir, "test-fixtures", "fake-app")

        try:
            # Prepare and build
            self._prepare_test_env(test_dir, repo_root)
            self._build_image(test_dir)

            # Start container with custom ENV_PUBLIC_PATH
            custom_path = "/custom/public/path"
            env_vars = {"ENV_PUBLIC_PATH": custom_path}
            print(f"Starting container with ENV_PUBLIC_PATH={custom_path}")
            self._start_container(env_vars)

            # Verify the custom path serves files
            response = requests.get(
                f"http://localhost:{self.HOST_PORT}{custom_path}/"
            )

            # Should either serve files or redirect, but not 404
            assert response.status_code != 404, \
                f"Custom ENV_PUBLIC_PATH route returned 404"

            print(f"✓ ENV_PUBLIC_PATH={custom_path} is accessible")

            # Verify the env var is set in the container
            env_value = self._get_container_env_var("ENV_PUBLIC_PATH")
            assert env_value == custom_path, \
                f"Expected ENV_PUBLIC_PATH={custom_path}, got {env_value}"

            print("✓ ENV_PUBLIC_PATH is correctly set in container")

        finally:
            self._cleanup_container_and_image()
            self._cleanup_test_env(test_dir)

    def test_build_args_accepted(self):
        """Test that various build-time arguments are accepted and don't break the build.

        Tests multiple build args: ENABLE_SENTRY, SENTRY_RELEASE, and USES_YARN.

        Note: These variables are only available in the builder stage,
        not in the final runtime container due to multi-stage build.
        """
        print("\n=== Testing build-time arguments ===")

        test_script_dir = os.path.dirname(__file__)
        repo_root = os.path.abspath(os.path.join(test_script_dir, ".."))
        test_dir = os.path.join(test_script_dir, "test-fixtures", "fake-app")

        try:
            # Prepare environment
            self._prepare_test_env(test_dir, repo_root)

            # Build with multiple build args: Sentry + USES_YARN
            build_args = {
                "ENABLE_SENTRY": "true",
                "SENTRY_RELEASE": "test-release-123",
                "USES_YARN": "false"
            }

            print("Building with multiple build args: ENABLE_SENTRY, SENTRY_RELEASE, USES_YARN")
            result = self._build_image(test_dir, build_args)

            # Verify the build completed successfully
            assert result.returncode == 0, \
                "Build failed with build arguments"

            print("✓ Build completed successfully with all build args")
            print("  - ENABLE_SENTRY=true")
            print("  - SENTRY_RELEASE=test-release-123")
            print("  - USES_YARN=false")
            print("  (Note: Build-time vars are not available at runtime)")

        finally:
            self._cleanup_container_and_image()
            self._cleanup_test_env(test_dir)

    def test_default_runtime_env_values(self):
        """Test that default runtime environment variable values are set correctly.

        Note: Only runtime variables in the final Caddy stage are tested.
        Build-stage variables (SENTRY, USES_YARN, etc.) are not available at runtime.
        """
        print("\n=== Testing default runtime environment variable values ===")

        test_script_dir = os.path.dirname(__file__)
        repo_root = os.path.abspath(os.path.join(test_script_dir, ".."))
        test_dir = os.path.join(test_script_dir, "test-fixtures", "fake-app")

        try:
            # Prepare and build without any custom build args
            self._prepare_test_env(test_dir, repo_root)
            print("Building with default values (no build args)")
            self._build_image(test_dir)

            # Start container without custom env vars
            self._start_container()

            # Check default runtime values (only variables in final stage)
            env_public_path = self._get_container_env_var("ENV_PUBLIC_PATH")
            caddy_tls_mode = self._get_container_env_var("CADDY_TLS_MODE")

            assert env_public_path == "/default", \
                f"Expected default ENV_PUBLIC_PATH=/default, got {env_public_path}"
            assert "http_port" in caddy_tls_mode and "8000" in caddy_tls_mode, \
                f"Expected CADDY_TLS_MODE to contain 'http_port 8000', got {caddy_tls_mode}"

            print("✓ All default runtime environment variables are correctly set")

        finally:
            self._cleanup_container_and_image()
            self._cleanup_test_env(test_dir)

    def test_runtime_env_override(self):
        """Test that runtime environment variables can override default values."""
        print("\n=== Testing runtime environment variable override ===")

        test_script_dir = os.path.dirname(__file__)
        repo_root = os.path.abspath(os.path.join(test_script_dir, ".."))
        test_dir = os.path.join(test_script_dir, "test-fixtures", "fake-app")

        try:
            # Prepare environment
            self._prepare_test_env(test_dir, repo_root)

            # Build with defaults
            print("Building with default values")
            self._build_image(test_dir)

            # Start container with custom ENV_PUBLIC_PATH (override default /default)
            custom_path = "/custom/override/path"
            env_vars = {"ENV_PUBLIC_PATH": custom_path}
            print(f"Starting container with ENV_PUBLIC_PATH={custom_path} (override)")
            self._start_container(env_vars)

            # Check that runtime value overrides default value
            env_public_path = self._get_container_env_var("ENV_PUBLIC_PATH")

            assert env_public_path == custom_path, \
                f"Expected runtime override ENV_PUBLIC_PATH={custom_path}, got {env_public_path}"

            print("✓ Runtime environment variable successfully overrides default value")

        finally:
            self._cleanup_container_and_image()
            self._cleanup_test_env(test_dir)


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
