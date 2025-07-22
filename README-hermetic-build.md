# **Hermetic Build Setup Guide for Frontend Projects**

Based on our experience setting up hermetic builds for the landing-page-frontend, here's a complete guide for teams to implement hermetic builds in Konflux using the shared Dockerfile from `insights-frontend-builder-common`.

## **Overview**

A hermetic build ensures your frontend application builds in a completely isolated environment without external network access, using only pre-fetched dependencies. This guide uses a shared Dockerfile provided through the `insights-frontend-builder-common` repository. The resulting container will include the build artifacts, package.json, and package-lock.json files organized under a `/srv` directory.

## **Prerequisites**

- ✅ Access to Konflux
- ✅ Frontend project with `package.json` and `package-lock.json`
- ✅ `insights-frontend-builder-common` already available in your project

---

## **Step 1: Set Up Konflux Component**

1. **Navigate to Konflux Console**
2. **Create New Component:**
   - **Component Name**: `your-project-name-hermetic`
   - **Git Repository**: Your frontend project repo
   - **Dockerfile Path**: `/build-tools/Dockerfile.hermetic`
   - **Build Type**: Select "Hermetic Build"

---

## **Step 2: Configure Pipeline Files**

Konflux will automatically create pipeline files in `.tekton/`. You'll need to modify them to add dependency prefetching.

### **2.1: Update Push Pipeline**

Edit `.tekton/your-project-hermetic-push.yaml`:

```yaml
# Find the spec.params section and add/modify:
spec:
  params:
  - name: git-url
    value: '{{source_url}}'
  - name: revision
    value: '{{revision}}'
  - name: output-image
    value: quay.io/your-registry/your-project-hermetic:{{revision}}
  - name: dockerfile
    value: /build-tools/Dockerfile.hermetic
  - name: prefetch-input                    # ADD THIS
    value: '{"type": "npm", "path": "."}'   # ADD THIS
```

### **2.2: Update Pull Request Pipeline**

Edit `.tekton/your-project-hermetic-pull-request.yaml`:

```yaml
# Find the spec.params section and add/modify:
spec:
  params:
  - name: git-url
    value: '{{source_url}}'
  - name: revision
    value: '{{revision}}'
  - name: output-image
    value: quay.io/your-registry/your-project-hermetic:on-pr-{{revision}}
  - name: dockerfile
    value: /build-tools/Dockerfile.hermetic
  - name: prefetch-input                    # ADD THIS
    value: '{"type": "npm", "path": "."}'   # ADD THIS
```

---

## **Step 3: Verify and Test**

### **3.1: Create Pull Request**

1. **Create PR** with your pipeline changes
2. **Konflux will automatically trigger** the hermetic build
3. **Monitor the build** in Konflux console

### **3.2: Check Build Process**

Verify these steps succeed in the build logs:
- ✅ **Offline npm ci**: Should use `--offline` flag
- ✅ **Dependency prefetch**: Should use Cachi2 prefetched packages
- ✅ **Build process**: Should generate files in `/hermetic-build/dist`
- ✅ **Tests and linting**: Should pass all checks

### **3.3: Verify Image**

Check the final container image:
- ✅ **Size**: Should be minimal (~50-100MB total)
- ✅ **Contents**: Should contain built static files in `/hermetic-build/dist`, with `package.json` and `package-lock.json` in `/hermetic-build/`
- ✅ **Labels**: Should pass Red Hat compliance checks

---

## **Common Issues and Solutions**

### **Issue: npm ci fails with network errors**
**Solution**: Ensure `prefetch-input` is correctly configured in pipeline files

### **Issue: Cypress tries to download binaries**
**Solution**: The Dockerfile automatically sets `CYPRESS_INSTALL_BINARY=0` in airgapped environments

### **Issue: Build artifacts not found**
**Solution**: Verify your build script produces files in `/dist` directory during the build process. The shared Dockerfile expects this standard location and copies the files to `/hermetic-build/dist` in the final container.

### **Issue: Container fails certification**
**Solution**: The shared Dockerfile includes all required labels and UBI-minimal base image for compliance

---

## **FAQ**

### **Q: Can I optimize build performance?**
**A:** Yes, you can add a `.dockerignore` file to exclude unnecessary files like `node_modules/`, cache directories, and development files from the build context. This can speed up builds and reduce context size.

### **Q: How do I update the shared Dockerfile?**
**A:** The Dockerfile is maintained in `insights-frontend-builder-common`. Updates will be automatically available when the submodule is updated.

### **Q: What if my build output is not in `/dist`?**
**A:** The shared Dockerfile expects build output in `/dist` during the build process, which is then copied to `/hermetic-build/dist` in the final container. Ensure your `package.json` build script outputs to the `/dist` directory, or modify your build configuration accordingly.

### **Q: Why do I need to add prefetch-input manually?**
**A:** Konflux doesn't automatically detect npm dependencies for hermetic builds. The `prefetch-input` parameter tells Cachi2 to pre-download your npm dependencies for offline use.

---

## **Project Structure After Setup**

```
your-project/
├── .tekton/
│   ├── your-project-hermetic-push.yaml      # (modified with prefetch-input)
│   └── your-project-hermetic-pull-request.yaml  # (modified with prefetch-input)
├── build-tools/
│   └── Dockerfile.hermetic                   # (shared Dockerfile)
├── package.json
├── package-lock.json
└── src/
    └── ... (your source code)
```