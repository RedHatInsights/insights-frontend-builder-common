"""
Tests for Dockerfile.hermetic filesystem structure and build process.

This test suite verifies that:
1. Files are copied to the correct locations in the hermetic image
2. Build artifacts are in the expected directories (/srv/dist)
3. Required files (package.json, LICENSE) are properly placed
4. Directory structure matches hermetic build expectations
5. Image metadata and labels are correct
6. Container runs as non-root user (1001)
7. Offline build process works correctly
8. Minimal image contains only necessary components (no Caddy)
"""

import json
import os
import shutil
import subprocess
import tempfile
import uuid

import pytest


class TestDockerfileHermetic:
    """Test suite for Dockerfile.hermetic structure and build."""

    IMAGE_NAME = "test-frontend-builder-hermetic:test"
    CONTAINER_NAME = "test-hermetic-container"
    APP_NAME = "test-app"

    @classmethod
    def setup_class(cls):
        """Build the Docker image once before running all tests."""
        print("\n=== Building Hermetic Docker image for tests ===")

        # Get paths
        test_script_dir = os.path.dirname(__file__)
        repo_root = os.path.abspath(os.path.join(test_script_dir, ".."))
        cls.test_dir = os.path.join(test_script_dir, "test-fixtures", "fake-app")

        # Prepare environment
        cls._prepare_test_env(cls.test_dir, repo_root)

        # Build hermetic image
        print("Building hermetic image (offline build)")
        cls._build_image(cls.test_dir)

        print(f"✓ Hermetic image {cls.IMAGE_NAME} built successfully and ready for tests")

    @classmethod
    def teardown_class(cls):
        """Clean up: remove the Docker image and copied files."""
        print("\n=== Cleaning up hermetic tests ===")

        # Remove the Docker image
        subprocess.run(
            ["podman", "rmi", "-f", cls.IMAGE_NAME],
            capture_output=True
        )
        print(f"✓ Image {cls.IMAGE_NAME} removed")

        # Remove copied Dockerfile
        cls._cleanup_test_env(cls.test_dir)
        print("✓ Removed copied Dockerfile.hermetic")

    @classmethod
    def _prepare_test_env(cls, test_dir, repo_root):
        """Prepare test environment by copying Dockerfile.hermetic."""
        # Copy Dockerfile.hermetic to test directory
        dockerfile_src = os.path.join(repo_root, "Dockerfile.hermetic")
        dockerfile_dest = os.path.join(test_dir, "Dockerfile.hermetic")
        shutil.copy(dockerfile_src, dockerfile_dest)

        # Initialize git repository if it doesn't exist (required by npm build)
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
        dockerfile_dest = os.path.join(test_dir, "Dockerfile.hermetic")
        if os.path.exists(dockerfile_dest):
            os.remove(dockerfile_dest)

    @classmethod
    def _build_image(cls, test_dir, build_args=None, image_name=None):
        """Build Docker image with optional build args.

        Enforces offline/hermetic build by disabling network access during build.

        Args:
            test_dir: Directory containing the Dockerfile
            build_args: Optional dict of build arguments
            image_name: Optional custom image name (defaults to cls.IMAGE_NAME)
        """
        target_image_name = image_name or cls.IMAGE_NAME

        build_cmd = [
            "podman", "build",
            "-t", target_image_name,
            "-f", "Dockerfile.hermetic",
            "--network=none"  # Enforce offline/hermetic build
        ]

        # Add build args if provided
        if build_args:
            for key, value in build_args.items():
                build_cmd.extend(["--build-arg", f"{key}={value}"])

        build_cmd.append(".")

        try:
            result = subprocess.run(
                build_cmd,
                cwd=test_dir,
                capture_output=True,
                text=True,
                timeout=300  # 5 minute timeout for build
            )
        except subprocess.TimeoutExpired as e:
            # Provide clear error message with available output
            # Since text=True, stdout/stderr are already strings, not bytes
            stdout = e.stdout if e.stdout else "No stdout"
            stderr = e.stderr if e.stderr else "No stderr"
            pytest.fail(
                "Hermetic Docker build exceeded 5 minute timeout.\n"
                "This may indicate the build is hanging or trying to access network.\n"
                f"STDOUT:\n{stdout}\n\n"
                f"STDERR:\n{stderr}"
            )

        if result.returncode != 0:
            print("STDOUT:", result.stdout)
            print("STDERR:", result.stderr)
            pytest.fail(f"Failed to build hermetic Docker image: {result.stderr}")

        return result

    def _file_exists_in_image(self, file_path, image_name=None):
        """Check if a file exists in the image.

        Args:
            file_path: Path to check in the image
            image_name: Optional custom image name (defaults to self.IMAGE_NAME)

        Returns:
            bool: True if file exists, False otherwise
        """
        target_image_name = image_name or self.IMAGE_NAME
        # Use podman create + podman cp instead of running commands in minimal image
        # Create a temporary container without starting it (use unique name to avoid conflicts)
        container_name = f"temp-check-{uuid.uuid4().hex[:8]}"
        create_result = subprocess.run(
            ["podman", "create", "--name", container_name, target_image_name],
            capture_output=True,
            text=True
        )
        if create_result.returncode != 0:
            return False

        try:
            # Try to copy the file to a temp location to check existence
            with tempfile.NamedTemporaryFile(delete=False) as tmp_file:
                tmp_path = tmp_file.name

            try:
                cp_result = subprocess.run(
                    ["podman", "cp", f"{container_name}:{file_path}", tmp_path],
                    capture_output=True,
                    text=True
                )
                return cp_result.returncode == 0
            finally:
                # Clean up temp file
                if os.path.exists(tmp_path):
                    os.remove(tmp_path)
        finally:
            # Clean up temporary container
            subprocess.run(
                ["podman", "rm", "-f", container_name],
                capture_output=True,
                text=True
            )

    def _read_file_from_image(self, file_path, image_name=None):
        """Read a file from the image.

        Args:
            file_path: Path to read in the image
            image_name: Optional custom image name (defaults to self.IMAGE_NAME)

        Returns:
            str: File content if successful, None otherwise
        """
        target_image_name = image_name or self.IMAGE_NAME
        # Use podman create + podman cp instead of running cat in minimal image
        # Create a temporary container without starting it (use unique name to avoid conflicts)
        container_name = f"temp-read-{uuid.uuid4().hex[:8]}"
        create_result = subprocess.run(
            ["podman", "create", "--name", container_name, target_image_name],
            capture_output=True,
            text=True
        )
        if create_result.returncode != 0:
            return None

        try:
            # Create a temporary file to copy content to
            with tempfile.NamedTemporaryFile(mode='r', delete=False) as tmp_file:
                tmp_path = tmp_file.name

            try:
                # Copy the file from container to host
                cp_result = subprocess.run(
                    ["podman", "cp", f"{container_name}:{file_path}", tmp_path],
                    capture_output=True,
                    text=True
                )
                if cp_result.returncode != 0:
                    return None

                # Read the file from host
                with open(tmp_path) as f:
                    return f.read()
            finally:
                # Clean up temporary file
                if os.path.exists(tmp_path):
                    os.remove(tmp_path)
        finally:
            # Clean up temporary container
            subprocess.run(
                ["podman", "rm", "-f", container_name],
                capture_output=True,
                text=True
            )

    def _list_directory_in_image(self, dir_path, image_name=None):
        """List files in a directory in the image.

        Args:
            dir_path: Directory path to list in the image
            image_name: Optional custom image name (defaults to self.IMAGE_NAME)

        Returns:
            list: List of filenames if successful, None otherwise
        """
        target_image_name = image_name or self.IMAGE_NAME
        # Use podman create + podman cp instead of running ls in minimal image
        # Create a temporary container without starting it (use unique name to avoid conflicts)
        container_name = f"temp-list-{uuid.uuid4().hex[:8]}"
        create_result = subprocess.run(
            ["podman", "create", "--name", container_name, target_image_name],
            capture_output=True,
            text=True
        )
        if create_result.returncode != 0:
            return None

        try:
            # Create a temporary directory to copy content to
            tmp_dir = tempfile.mkdtemp()

            try:
                # Copy the directory from container to host
                cp_result = subprocess.run(
                    ["podman", "cp", f"{container_name}:{dir_path}", tmp_dir],
                    capture_output=True,
                    text=True
                )
                if cp_result.returncode != 0:
                    return None

                # List files in the copied directory
                # The copied dir_path will be inside tmp_dir
                copied_path = os.path.join(tmp_dir, os.path.basename(dir_path))
                if os.path.isdir(copied_path):
                    return os.listdir(copied_path)
                else:
                    # If it's a file, return the parent directory listing
                    return os.listdir(tmp_dir)
            finally:
                # Clean up temporary directory
                if os.path.exists(tmp_dir):
                    shutil.rmtree(tmp_dir)
        finally:
            # Clean up temporary container
            subprocess.run(
                ["podman", "rm", "-f", container_name],
                capture_output=True,
                text=True
            )

    def _get_image_labels(self, image_name=None):
        """Get labels from the Docker image.

        Labels can be stored in different locations depending on Podman/Docker version
        and whether inspecting an image or container:
        - data[0]["Labels"] (older format or containers)
        - data[0]["Config"]["Labels"] (newer format for images)

        Args:
            image_name: Optional custom image name (defaults to self.IMAGE_NAME)
        """
        target_image_name = image_name or self.IMAGE_NAME
        result = subprocess.run(
            ["podman", "inspect", target_image_name],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            return {}

        try:
            data = json.loads(result.stdout)
            if not data or len(data) == 0:
                return {}

            # Try root-level Labels first (containers, older format)
            if "Labels" in data[0] and data[0]["Labels"]:
                return data[0]["Labels"]

            # Fall back to Config.Labels (images, newer format)
            return data[0].get("Config", {}).get("Labels", {})

        except (json.JSONDecodeError, KeyError, IndexError):
            return {}
        except Exception:
            # Catch any other unexpected errors
            return {}

    def _get_image_user(self, image_name=None):
        """Get the user the container runs as.

        Args:
            image_name: Optional custom image name (defaults to self.IMAGE_NAME)
        """
        target_image_name = image_name or self.IMAGE_NAME
        result = subprocess.run(
            ["podman", "inspect", target_image_name],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            return None

        try:
            data = json.loads(result.stdout)
            if data and len(data) > 0:
                config = data[0].get("Config", {})
                return config.get("User", "")
        except (json.JSONDecodeError, KeyError, IndexError):
            return None
        return None

    # ============= Filesystem Structure Tests =============

    def test_license_file_exists(self):
        """Test that LICENSE file is copied to /licenses/."""
        print("\n=== Testing LICENSE file location in hermetic image ===")

        # Check if LICENSE exists at /licenses/LICENSE
        license_exists = self._file_exists_in_image("/licenses/LICENSE")
        assert license_exists, "LICENSE file not found at /licenses/LICENSE"

        # Verify it has content
        license_content = self._read_file_from_image("/licenses/LICENSE")
        assert license_content is not None, "LICENSE file is empty"
        assert "MIT License" in license_content or "LICENSE" in license_content.upper(), \
            "LICENSE file doesn't contain expected content"

        print("✓ LICENSE file exists at /licenses/LICENSE with content")

    def test_srv_directory_exists(self):
        """Test that /srv directory exists and contains expected files."""
        print("\n=== Testing /srv directory structure ===")

        srv_listing = self._list_directory_in_image("/srv")
        assert srv_listing is not None, "/srv directory not found"

        print(f"Contents of /srv:\n{srv_listing}")
        print("✓ /srv directory exists")

    def test_dist_directory_structure(self):
        """Test that /srv/dist directory contains expected build artifacts."""
        print("\n=== Testing /srv/dist directory structure ===")

        dist_listing = self._list_directory_in_image("/srv/dist")
        assert dist_listing is not None, "/srv/dist directory not found"

        print(f"Contents of /srv/dist:\n{dist_listing}")

        # Check for expected files
        # Note: app.info.json is not generated in hermetic builds (only in normal builds with build_app_info.sh)
        expected_files = ["index.html", "manifest.json"]
        for expected_file in expected_files:
            file_path = f"/srv/dist/{expected_file}"
            file_exists = self._file_exists_in_image(file_path)
            assert file_exists, f"{expected_file} not found at {file_path}"
            print(f"  ✓ {expected_file} exists")

        # Check subdirectories
        css_exists = self._file_exists_in_image("/srv/dist/css/app.css")
        js_exists = self._file_exists_in_image("/srv/dist/js/app.js")

        assert css_exists, "css/app.css not found in /srv/dist"
        assert js_exists, "js/app.js not found in /srv/dist"

        print("  ✓ css/app.css exists")
        print("  ✓ js/app.js exists")
        print("✓ /srv/dist directory contains all expected build artifacts")

    def test_package_json_exists(self):
        """Test that package.json is copied to /srv."""
        print("\n=== Testing package.json location ===")

        package_json_path = "/srv/package.json"
        package_json_exists = self._file_exists_in_image(package_json_path)
        assert package_json_exists, f"package.json not found at {package_json_path}"

        # Verify content
        package_json_content = self._read_file_from_image(package_json_path)
        assert package_json_content is not None, "package.json is empty"

        try:
            data = json.loads(package_json_content)
            assert data.get("insights", {}).get("appname") == "test-app", \
                "package.json doesn't contain expected appname"
            print(f"✓ package.json found at {package_json_path} with correct content")
        except json.JSONDecodeError:
            pytest.fail("package.json is not valid JSON")

    def test_package_lock_json_exists(self):
        """Test that package-lock.json is copied to /srv."""
        print("\n=== Testing package-lock.json location ===")

        package_lock_path = "/srv/package-lock.json"
        package_lock_exists = self._file_exists_in_image(package_lock_path)
        assert package_lock_exists, f"package-lock.json not found at {package_lock_path}"

        # Verify it has content
        package_lock_content = self._read_file_from_image(package_lock_path)
        assert package_lock_content is not None, "package-lock.json is empty"

        print(f"✓ package-lock.json found at {package_lock_path}")

    def test_no_app_info_json(self):
        """Test that app.info.json is NOT generated in hermetic builds.

        Note: app.info.json is only generated by build_app_info.sh in the normal
        Dockerfile build. Hermetic builds just run 'npm run build' directly.
        """
        print("\n=== Testing that app.info.json is not generated ===")

        app_info_path = "/srv/dist/app.info.json"
        content = self._read_file_from_image(app_info_path)
        assert content is None, \
            "app.info.json should not exist in hermetic builds (it's only in normal builds)"

        print("✓ app.info.json correctly absent (hermetic builds don't use build_app_info.sh)")

    # ============= Negative Tests (Things that should NOT exist) =============

    def test_no_caddy_files(self):
        """Test that Caddy-related files do NOT exist in hermetic image."""
        print("\n=== Testing that Caddy files are absent ===")

        # Caddyfile should not exist
        caddyfile_exists = self._file_exists_in_image("/etc/caddy/Caddyfile")
        assert not caddyfile_exists, "Caddyfile should not exist in hermetic image"

        print("✓ Caddyfile correctly absent from hermetic image")


    def test_no_nodejs_in_final_image(self):
        """Test that Node.js is NOT present in final hermetic image."""
        print("\n=== Testing that Node.js is absent from final image ===")

        # Try to run node command directly - should fail if node is absent
        # Note: ubi-micro doesn't have 'which', so we try to execute node directly
        result = subprocess.run(
            ["podman", "run", "--rm", self.IMAGE_NAME, "node", "--version"],
            capture_output=True,
            text=True
        )
        assert result.returncode != 0, "Node.js should not be present in final hermetic image"

        print("✓ Node.js correctly absent from final hermetic image")

    # ============= Image Metadata Tests =============

    def test_red_hat_labels_present(self):
        """Test that required Red Hat labels are present in the image."""
        print("\n=== Testing Red Hat compliance labels ===")

        labels = self._get_image_labels()
        assert labels, "No labels found in image"

        # Required Red Hat labels
        required_labels = [
            "com.redhat.component",
            "description",
            "distribution-scope",
            "io.k8s.description",
            "name",
            "release",
            "url",
            "vendor",
            "version",
            "maintainer",
            "summary"
        ]

        for label in required_labels:
            assert label in labels, f"Required label '{label}' not found in image"
            assert labels[label], f"Label '{label}' is empty"
            print(f"  ✓ {label}: {labels[label][:50]}{'...' if len(labels[label]) > 50 else ''}")

        print("✓ All required Red Hat labels are present")

    def test_runs_as_non_root_user(self):
        """Test that container runs as non-root user (1001)."""
        print("\n=== Testing container user ===")

        user = self._get_image_user()
        assert user is not None, "Could not determine container user"
        assert user == "1001", f"Expected user 1001, got {user}"

        print(f"✓ Container runs as non-root user: {user}")

    def test_image_user_id_at_runtime(self):
        """Test that the container actually runs with UID 1001 at runtime."""
        print("\n=== Testing runtime user ID ===")

        result = subprocess.run(
            ["podman", "run", "--rm", self.IMAGE_NAME, "id", "-u"],
            capture_output=True,
            text=True
        )

        assert result.returncode == 0, "Failed to get user ID from container"
        uid = result.stdout.strip()
        assert uid == "1001", f"Expected UID 1001, got {uid}"

        print(f"✓ Container runs with UID: {uid}")

    # ============= Build Process Tests =============

    def test_offline_build_succeeds(self):
        """Test that the hermetic build uses --offline flag successfully.

        This is verified by the successful build in setup_class, which uses
        npm ci --offline. This test just confirms the image was built.
        """
        print("\n=== Testing offline build ===")

        # If we got here, the image was built successfully in setup_class
        # using npm ci --offline, so the test passes
        result = subprocess.run(
            ["podman", "image", "exists", self.IMAGE_NAME],
            capture_output=True
        )

        assert result.returncode == 0, "Hermetic image does not exist"
        print("✓ Hermetic image built successfully with offline build")

    def test_npm_ci_args_build_arg(self):
        """Test that NPM_CI_ARGS build argument can be used.

        NOTE: This test builds its own image with custom build args,
        separate from the shared image used by other tests.
        """
        print("\n=== Testing NPM_CI_ARGS build argument ===")
        print("Note: Building separate image with custom NPM_CI_ARGS...")

        custom_image_name = "test-frontend-builder-hermetic-custom:test"

        try:
            # Build with custom NPM_CI_ARGS
            build_args = {"NPM_CI_ARGS": "--legacy-peer-deps"}

            # Build with custom image name (no class mutation!)
            self._build_image(self.test_dir, build_args, image_name=custom_image_name)

            # Verify the image was built
            result = subprocess.run(
                ["podman", "image", "exists", custom_image_name],
                capture_output=True
            )
            assert result.returncode == 0, "Custom hermetic image was not built"

            print("✓ NPM_CI_ARGS build argument works correctly")

        finally:
            # Clean up the custom image
            subprocess.run(
                ["podman", "rmi", "-f", custom_image_name],
                capture_output=True
            )
            print(f"✓ Cleaned up custom image {custom_image_name}")

    # ============= Security Tests =============

    def test_minimal_image_size(self):
        """Test that hermetic image is reasonably small (using ubi-micro base)."""
        print("\n=== Testing image size ===")

        result = subprocess.run(
            ["podman", "image", "inspect", self.IMAGE_NAME, "--format", "{{.Size}}"],
            capture_output=True,
            text=True
        )

        assert result.returncode == 0, "Failed to get image size"

        # Size is in bytes
        size_bytes = int(result.stdout.strip())
        size_mb = size_bytes / (1024 * 1024)

        print(f"Image size: {size_mb:.2f} MB")

        # Hermetic images should be significantly smaller than the full Caddy image
        # ubi-micro is very minimal, so even with node_modules and build artifacts,
        # it should be under 500MB (this is a sanity check, not a hard limit)
        assert size_mb < 500, f"Hermetic image seems too large: {size_mb:.2f} MB"

        print(f"✓ Image size is reasonable: {size_mb:.2f} MB")

    def test_read_only_filesystem_compatible(self):
        """Test that the hermetic image can run with a read-only filesystem.

        Since it's just static files, it should work with --read-only flag.
        Tests that files are actually readable, not just listable.
        """
        print("\n=== Testing read-only filesystem compatibility ===")

        # Try to read a file with read-only filesystem (stronger test than just ls)
        result = subprocess.run(
            ["podman", "run", "--rm", "--read-only", self.IMAGE_NAME, "cat", "/srv/dist/index.html"],
            capture_output=True,
            text=True
        )

        assert result.returncode == 0, "Container failed to run with read-only filesystem"
        assert "<!DOCTYPE" in result.stdout or "<html" in result.stdout.lower(), \
            "Build artifacts not readable with read-only FS - expected HTML content"

        print("✓ Container can run with read-only filesystem")
        print("✓ Files are readable (not just listable) in read-only mode")


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
