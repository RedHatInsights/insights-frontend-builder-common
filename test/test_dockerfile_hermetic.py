"""
Tests for Dockerfile.hermetic multi-target build.

This test suite verifies both build targets:

Artifact target (default, no --target needed):
1. Files are copied to the correct locations (/srv/dist, /srv/package.json)
2. Build artifacts are in the expected directories
3. Required files (package.json, LICENSE) are properly placed
4. Image metadata and labels are correct
5. Container runs as non-root user (1001)
6. Offline build process works correctly
7. Minimal image contains only necessary components (no Caddy)

Deploy target (--target deploy):
1. Caddyfile is generated and placed at /etc/caddy/Caddyfile
2. Build artifacts are at expected locations (dist/)
3. Package.json is present
4. LICENSE is present
5. Caddy environment variables are set
"""

import json
import os
import shutil
import subprocess
import tempfile
import uuid

import pytest


class TestDockerfileHermetic:
    """Test suite for Dockerfile.hermetic artifact target (default)."""

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
        print("✓ Removed copied test files")

    @classmethod
    def _prepare_test_env(cls, test_dir, repo_root):
        """Prepare test environment by copying Dockerfile.hermetic and helpers."""
        # Copy Dockerfile.hermetic to test directory
        dockerfile_src = os.path.join(repo_root, "Dockerfile.hermetic")
        dockerfile_dest = os.path.join(test_dir, "Dockerfile.hermetic")
        shutil.copy(dockerfile_src, dockerfile_dest)

        # Create build-tools directory and copy hermetic build scripts
        build_tools_dir = os.path.join(test_dir, "build-tools")
        os.makedirs(build_tools_dir, exist_ok=True)
        caddyfile_gen_src = os.path.join(repo_root, "caddyfile_gen_hermetic.js")
        caddyfile_gen_dest = os.path.join(build_tools_dir, "caddyfile_gen_hermetic.js")
        shutil.copy(caddyfile_gen_src, caddyfile_gen_dest)
        app_info_gen_src = os.path.join(repo_root, "build_app_info_hermetic.js")
        app_info_gen_dest = os.path.join(build_tools_dir, "build_app_info_hermetic.js")
        shutil.copy(app_info_gen_src, app_info_gen_dest)

        # Initialize git repository if it doesn't exist (required by npm build)
        # Note: GPG signing is disabled for this test fixture commit because
        # the test uses a fake identity that has no GPG key
        git_dir = os.path.join(test_dir, ".git")
        if not os.path.exists(git_dir):
            subprocess.run(["git", "init"], cwd=test_dir, check=True)
            subprocess.run(["git", "config", "user.email", "test@test.com"], cwd=test_dir, check=True)
            subprocess.run(["git", "config", "user.name", "Test User"], cwd=test_dir, check=True)
            subprocess.run(["git", "config", "commit.gpgsign", "false"], cwd=test_dir, check=True)
            subprocess.run(["git", "add", "."], cwd=test_dir, check=True)
            subprocess.run(["git", "commit", "-m", "Initial commit"], cwd=test_dir, check=True)

    @classmethod
    def _cleanup_test_env(cls, test_dir):
        """Clean up test environment."""
        dockerfile_dest = os.path.join(test_dir, "Dockerfile.hermetic")
        if os.path.exists(dockerfile_dest):
            os.remove(dockerfile_dest)

        build_tools_dir = os.path.join(test_dir, "build-tools")
        if os.path.exists(build_tools_dir):
            shutil.rmtree(build_tools_dir)

    @classmethod
    def _build_image(cls, test_dir, build_args=None, image_name=None, target=None):
        """Build Docker image with optional build args and target.

        Enforces offline/hermetic build by disabling network access during build.

        Args:
            test_dir: Directory containing the Dockerfile
            build_args: Optional dict of build arguments
            image_name: Optional custom image name (defaults to cls.IMAGE_NAME)
            target: Optional build target (e.g. "deploy", "artifact")
        """
        target_image_name = image_name or cls.IMAGE_NAME

        build_cmd = [
            "podman", "build",
            "-t", target_image_name,
            "-f", "Dockerfile.hermetic",
            "--network=none"  # Enforce offline/hermetic build
        ]

        # Add target if specified
        if target:
            build_cmd.extend(["--target", target])

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
        # Use podman create + podman cp instead of running commands in minimal image
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

    def _get_image_env(self, image_name=None):
        """Get environment variables from the image.

        Args:
            image_name: Optional custom image name (defaults to self.IMAGE_NAME)

        Returns:
            dict: Environment variables as key-value pairs
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
            if data and len(data) > 0:
                config = data[0].get("Config", {})
                env_list = config.get("Env", [])
                env_dict = {}
                for item in env_list:
                    if "=" in item:
                        key, value = item.split("=", 1)
                        env_dict[key] = value
                return env_dict
        except (json.JSONDecodeError, KeyError, IndexError):
            return {}
        return {}

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

    def test_app_info_json_exists(self):
        """Test that app.info.json is generated in hermetic builds.

        build_app_info_hermetic.js generates metadata equivalent to
        build_app_info.sh but without jq dependency.
        """
        print("\n=== Testing app.info.json in hermetic image ===")

        app_info_path = "/srv/dist/app.info.json"
        content = self._read_file_from_image(app_info_path)
        assert content is not None, \
            "app.info.json not found at /srv/dist/app.info.json"

        data = json.loads(content)
        assert data.get("app_name") == self.APP_NAME, \
            f"Expected app_name '{self.APP_NAME}', got '{data.get('app_name')}'"
        assert "src_hash" in data, "app.info.json missing src_hash"
        assert "src_branch" in data, "app.info.json missing src_branch"
        assert "app_version" in data, "app.info.json missing app_version"
        assert "node_version" in data, "app.info.json missing node_version"
        assert "patternfly_dependencies" in data, "app.info.json missing patternfly_dependencies"
        assert "rh_cloud_services_dependencies" in data, "app.info.json missing rh_cloud_services_dependencies"

        print(f"  ✓ app_name: {data['app_name']}")
        print(f"  ✓ src_hash: {data['src_hash'][:12]}...")
        print(f"  ✓ node_version: {data['node_version']}")
        print("✓ app.info.json exists with correct metadata")

    def test_app_info_deps_json_exists(self):
        """Test that app.info.deps.json is generated in hermetic builds."""
        print("\n=== Testing app.info.deps.json in hermetic image ===")

        app_info_deps_path = "/srv/dist/app.info.deps.json"
        content = self._read_file_from_image(app_info_deps_path)
        assert content is not None, \
            "app.info.deps.json not found at /srv/dist/app.info.deps.json"

        data = json.loads(content)
        assert data.get("app_name") == self.APP_NAME, \
            f"Expected app_name '{self.APP_NAME}', got '{data.get('app_name')}'"
        assert "patternfly_dependencies" in data, "app.info.deps.json missing patternfly_dependencies"
        assert "rh_cloud_services_dependencies" in data, "app.info.deps.json missing rh_cloud_services_dependencies"

        print(f"  ✓ app_name: {data['app_name']}")
        print("✓ app.info.deps.json exists with correct metadata")

    # ============= Negative Tests (Things that should NOT exist) =============

    def test_no_caddy_files(self):
        """Test that Caddy-related files do NOT exist in hermetic artifact image."""
        print("\n=== Testing that Caddy files are absent ===")

        # Caddyfile should not exist in the artifact target
        caddyfile_exists = self._file_exists_in_image("/etc/caddy/Caddyfile")
        assert not caddyfile_exists, "Caddyfile should not exist in hermetic artifact image"

        print("✓ Caddyfile correctly absent from hermetic artifact image")


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

    def test_labels_are_generic(self):
        """Test that labels use generic defaults, not hardcoded app-specific values."""
        print("\n=== Testing labels are not hardcoded to specific app ===")

        labels = self._get_image_labels()
        assert labels, "No labels found in image"

        # Should NOT contain landing-page-frontend (old hardcoded value)
        component = labels.get("com.redhat.component", "")
        assert "landing-page" not in component, \
            f"Label com.redhat.component still contains hardcoded 'landing-page': {component}"

        print(f"  ✓ com.redhat.component: {component} (no hardcoded app name)")
        print("✓ Labels use generic defaults")

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


class TestDockerfileHermeticDeploy:
    """Test suite for Dockerfile.hermetic deploy target (Caddy runtime).

    Builds with --target deploy to produce a Caddy-based serving image.
    Verifies Caddyfile generation, file placement, and environment config.
    """

    IMAGE_NAME = "test-frontend-builder-hermetic-deploy:test"
    APP_NAME = "test-app"

    @classmethod
    def setup_class(cls):
        """Build the Docker image with --target deploy."""
        print("\n=== Building Hermetic Deploy Docker image for tests ===")

        test_script_dir = os.path.dirname(__file__)
        repo_root = os.path.abspath(os.path.join(test_script_dir, ".."))
        cls.test_dir = os.path.join(test_script_dir, "test-fixtures", "fake-app")

        # Reuse same prepare method (Dockerfile.hermetic + build-tools/)
        TestDockerfileHermetic._prepare_test_env(cls.test_dir, repo_root)

        # Build with --target deploy
        print("Building hermetic deploy image (offline build, deploy target)")
        TestDockerfileHermetic._build_image(
            cls.test_dir,
            image_name=cls.IMAGE_NAME,
            target="deploy"
        )

        print(f"✓ Deploy image {cls.IMAGE_NAME} built successfully")

    @classmethod
    def teardown_class(cls):
        """Clean up: remove the Docker image."""
        print("\n=== Cleaning up hermetic deploy tests ===")

        subprocess.run(
            ["podman", "rmi", "-f", cls.IMAGE_NAME],
            capture_output=True
        )
        print(f"✓ Image {cls.IMAGE_NAME} removed")

        TestDockerfileHermetic._cleanup_test_env(cls.test_dir)
        print("✓ Removed copied test files")

    def _file_exists_in_image(self, file_path):
        """Check if a file exists in the deploy image."""
        return TestDockerfileHermeticDeploy._file_exists_in_image_static(file_path, self.IMAGE_NAME)

    def _read_file_from_image(self, file_path):
        """Read a file from the deploy image."""
        return TestDockerfileHermeticDeploy._read_file_from_image_static(file_path, self.IMAGE_NAME)

    @staticmethod
    def _file_exists_in_image_static(file_path, image_name):
        """Static helper to check file existence in an image."""
        container_name = f"temp-check-{uuid.uuid4().hex[:8]}"
        create_result = subprocess.run(
            ["podman", "create", "--name", container_name, image_name],
            capture_output=True,
            text=True
        )
        if create_result.returncode != 0:
            return False

        try:
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
                if os.path.exists(tmp_path):
                    os.remove(tmp_path)
        finally:
            subprocess.run(
                ["podman", "rm", "-f", container_name],
                capture_output=True,
                text=True
            )

    @staticmethod
    def _read_file_from_image_static(file_path, image_name):
        """Static helper to read a file from an image."""
        container_name = f"temp-read-{uuid.uuid4().hex[:8]}"
        create_result = subprocess.run(
            ["podman", "create", "--name", container_name, image_name],
            capture_output=True,
            text=True
        )
        if create_result.returncode != 0:
            return None

        try:
            with tempfile.NamedTemporaryFile(mode='r', delete=False) as tmp_file:
                tmp_path = tmp_file.name
            try:
                cp_result = subprocess.run(
                    ["podman", "cp", f"{container_name}:{file_path}", tmp_path],
                    capture_output=True,
                    text=True
                )
                if cp_result.returncode != 0:
                    return None
                with open(tmp_path) as f:
                    return f.read()
            finally:
                if os.path.exists(tmp_path):
                    os.remove(tmp_path)
        finally:
            subprocess.run(
                ["podman", "rm", "-f", container_name],
                capture_output=True,
                text=True
            )

    # ============= Deploy Target Tests =============

    def test_caddyfile_exists(self):
        """Test that Caddyfile is generated and placed at /etc/caddy/Caddyfile."""
        print("\n=== Testing Caddyfile in deploy image ===")

        caddyfile_exists = self._file_exists_in_image("/etc/caddy/Caddyfile")
        assert caddyfile_exists, "Caddyfile not found at /etc/caddy/Caddyfile"

        print("✓ Caddyfile exists at /etc/caddy/Caddyfile")

    def test_caddyfile_contains_app_route(self):
        """Test that generated Caddyfile contains correct app-specific route."""
        print("\n=== Testing Caddyfile content ===")

        content = self._read_file_from_image("/etc/caddy/Caddyfile")
        assert content is not None, "Could not read Caddyfile"

        # Should contain route for test-app (from fake-app package.json)
        assert f"/apps/{self.APP_NAME}" in content, \
            f"Caddyfile does not contain route for /apps/{self.APP_NAME}"

        # Should contain port 8000 listener
        assert ":8000" in content, "Caddyfile does not contain :8000 listener"

        # Should contain metrics port 9000
        assert ":9000" in content, "Caddyfile does not contain :9000 metrics port"

        # Should NOT contain hardcoded landing-page-frontend
        assert "landing-page" not in content, \
            "Caddyfile contains hardcoded landing-page reference"

        print(f"  ✓ Route /apps/{self.APP_NAME} present")
        print("  ✓ Port :8000 configured")
        print("  ✓ Metrics port :9000 configured")
        print("  ✓ No hardcoded app names")
        print("✓ Caddyfile content is correct")

    def test_deploy_dist_files_exist(self):
        """Test that build artifacts are present in deploy image."""
        print("\n=== Testing dist files in deploy image ===")

        # In deploy target, dist is at /srv/dist (Caddy working dir)
        index_exists = self._file_exists_in_image("/srv/dist/index.html")
        assert index_exists, "index.html not found in deploy image"

        js_exists = self._file_exists_in_image("/srv/dist/js/app.js")
        assert js_exists, "js/app.js not found in deploy image"

        css_exists = self._file_exists_in_image("/srv/dist/css/app.css")
        assert css_exists, "css/app.css not found in deploy image"

        print("  ✓ index.html exists")
        print("  ✓ js/app.js exists")
        print("  ✓ css/app.css exists")
        print("✓ Build artifacts present in deploy image")

    def test_deploy_package_json_exists(self):
        """Test that package.json is present in deploy image."""
        print("\n=== Testing package.json in deploy image ===")

        content = self._read_file_from_image("/srv/package.json")
        assert content is not None, "package.json not found in deploy image"

        data = json.loads(content)
        assert data.get("insights", {}).get("appname") == self.APP_NAME, \
            "package.json doesn't contain expected appname"

        print(f"✓ package.json found with appname: {self.APP_NAME}")

    def test_deploy_license_exists(self):
        """Test that LICENSE is present in deploy image."""
        print("\n=== Testing LICENSE in deploy image ===")

        license_exists = self._file_exists_in_image("/licenses/LICENSE")
        assert license_exists, "LICENSE not found at /licenses/LICENSE"

        print("✓ LICENSE file present in deploy image")

    def test_deploy_caddy_env_vars(self):
        """Test that Caddy environment variables are set in deploy image."""
        print("\n=== Testing Caddy environment variables ===")

        result = subprocess.run(
            ["podman", "inspect", self.IMAGE_NAME],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, "Failed to inspect deploy image"

        data = json.loads(result.stdout)
        config = data[0].get("Config", {})
        env_list = config.get("Env", [])
        env_dict = {}
        for item in env_list:
            if "=" in item:
                key, value = item.split("=", 1)
                env_dict[key] = value

        assert "CADDY_TLS_MODE" in env_dict, "CADDY_TLS_MODE not set"
        assert "ENV_PUBLIC_PATH" in env_dict, "ENV_PUBLIC_PATH not set"

        print(f"  ✓ CADDY_TLS_MODE={env_dict.get('CADDY_TLS_MODE')}")
        print(f"  ✓ ENV_PUBLIC_PATH={env_dict.get('ENV_PUBLIC_PATH')}")
        print("✓ Caddy environment variables configured")

    def test_deploy_build_succeeds_offline(self):
        """Test that the deploy target builds successfully with --network=none."""
        print("\n=== Testing deploy target offline build ===")

        result = subprocess.run(
            ["podman", "image", "exists", self.IMAGE_NAME],
            capture_output=True
        )
        assert result.returncode == 0, "Deploy image does not exist"

        print("✓ Deploy image built successfully with offline build")

    def test_deploy_app_info_json_exists(self):
        """Test that app.info.json is present in deploy image."""
        print("\n=== Testing app.info.json in deploy image ===")

        content = self._read_file_from_image("/srv/dist/app.info.json")
        assert content is not None, "app.info.json not found in deploy image"

        data = json.loads(content)
        assert data.get("app_name") == self.APP_NAME, \
            f"Expected app_name '{self.APP_NAME}', got '{data.get('app_name')}'"
        assert "src_hash" in data, "app.info.json missing src_hash"
        assert "app_version" in data, "app.info.json missing app_version"
        assert "node_version" in data, "app.info.json missing node_version"

        print(f"  ✓ app_name: {data['app_name']}")
        print(f"  ✓ node_version: {data['node_version']}")
        print("✓ app.info.json present in deploy image")

    def test_deploy_app_info_deps_json_exists(self):
        """Test that app.info.deps.json is present in deploy image."""
        print("\n=== Testing app.info.deps.json in deploy image ===")

        content = self._read_file_from_image("/srv/dist/app.info.deps.json")
        assert content is not None, "app.info.deps.json not found in deploy image"

        data = json.loads(content)
        assert data.get("app_name") == self.APP_NAME, \
            f"Expected app_name '{self.APP_NAME}', got '{data.get('app_name')}'"

        print(f"  ✓ app_name: {data['app_name']}")
        print("✓ app.info.deps.json present in deploy image")

    def test_caddyfile_root_uses_srv_dist(self):
        """Test that Caddyfile file_server roots use /srv/dist.

        The deploy stage always copies ${APP_BUILD_DIR} into /srv/dist,
        so the Caddyfile must reference /srv/dist regardless of APP_BUILD_DIR.
        """
        print("\n=== Testing Caddyfile root paths ===")

        content = self._read_file_from_image("/etc/caddy/Caddyfile")
        assert content is not None, "Could not read Caddyfile"

        # All file_server roots should use /srv/dist
        assert "/srv/dist" in content, \
            "Caddyfile does not reference /srv/dist — runtime path mismatch"

        # Should NOT reference a variable-based root that could differ from /srv/dist
        import re
        roots = re.findall(r'root\s+(\S+)', content)
        for root_path in roots:
            assert root_path == "/srv/dist", \
                f"Caddyfile root '{root_path}' does not match runtime destination /srv/dist"

        print("  ✓ All file_server roots use /srv/dist")
        print("✓ Caddyfile root paths match runtime destination")


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
