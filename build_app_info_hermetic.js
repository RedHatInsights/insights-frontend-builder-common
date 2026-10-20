#!/usr/bin/env node
// build_app_info_hermetic.js — Generate app.info.json and app.info.deps.json
//
// Hermetic equivalent of build_app_info.sh + server_config_gen.sh metadata
// generation. Uses Node.js instead of jq/bash so it works in hermetic build
// environments where jq is not available.
//
// Generates:
//   ${APP_BUILD_DIR}/app.info.json      — Application metadata
//   ${APP_BUILD_DIR}/app.info.deps.json — Dependency metadata
//
// Environment variables:
//   PACKAGE_JSON_PATH  Path to package.json (default: "package.json")
//   APP_BUILD_DIR      Build output directory name (default: "dist")
//   APP_VERSION        Application version string (default: "unknown")
//   SOURCE_GIT_BRANCH  Git branch override for detached HEAD in CI
//   SOURCE_GIT_TAG     Git tag override for detached HEAD in CI
//
// Skips generation if output files already exist (consumer override).

'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const pkgPath = process.env.PACKAGE_JSON_PATH || 'package.json';
const buildDir = process.env.APP_BUILD_DIR || 'dist';
const appVersion = process.env.APP_VERSION || 'unknown';

// Read package.json
let pkg = {};
try {
  pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
} catch (err) {
  console.error(`Warning: Could not read ${pkgPath}: ${err.message}`);
}

const appName = (pkg.insights && pkg.insights.appname) || 'unknown';
const nodeVersion = (pkg.engines && pkg.engines.node) || 'unknown';

// Git helpers — match build_app_info.sh fallback chain
function execGit(cmd) {
  try {
    return execSync(cmd, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();
  } catch {
    return '';
  }
}

function getGitHash() {
  return execGit('git rev-parse --verify HEAD') || 'unknown';
}

function getGitBranch() {
  // 1. Direct branch name (works on regular checkouts)
  let branch = execGit('git branch --show-current');
  if (branch) return branch;

  // 2. Symbolic ref (fails in detached HEAD but worth trying)
  branch = execGit('git rev-parse --abbrev-ref HEAD');
  if (branch && branch !== 'HEAD') return branch;

  // 3. Find remote branch(es) pointing at HEAD (detached HEAD in CI)
  const remoteBranch = execGit('git branch -r --points-at HEAD');
  if (remoteBranch) {
    const first = remoteBranch.split('\n')[0].trim();
    const parts = first.split('/');
    return parts[parts.length - 1];
  }

  // 4. CI environment variable fallbacks
  const envVars = [
    'SOURCE_GIT_BRANCH', 'GITHUB_HEAD_REF', 'GITHUB_REF_NAME',
    'GIT_BRANCH', 'BRANCH_NAME'
  ];
  for (const envVar of envVars) {
    const val = process.env[envVar];
    if (val) return val.replace(/^.*\//, '');
  }

  return 'unknown';
}

function getGitTag() {
  // 1. Nearest tag from current commit
  let tag = execGit('git describe --tags --abbrev=0');
  if (tag) return tag;

  // 2. Tags directly pointing at HEAD (shallow clones)
  tag = execGit('git tag --points-at HEAD');
  if (tag) return tag.split('\n')[0].trim();

  // 3. CI environment variable fallback
  if (process.env.SOURCE_GIT_TAG) return process.env.SOURCE_GIT_TAG;

  return 'unknown';
}

// Dependency listing — reads installed versions from node_modules
function listScopedDeps(scope) {
  const allDeps = Object.assign({}, pkg.dependencies || {});
  const matched = [];

  for (const name of Object.keys(allDeps).sort()) {
    if (name.toLowerCase().includes(scope.toLowerCase())) {
      let version = 'unknown';
      try {
        const depPkg = JSON.parse(
          fs.readFileSync(path.join('node_modules', name, 'package.json'), 'utf8')
        );
        version = depPkg.version || version;
      } catch {
        // Fall back to specified version from package.json
        version = allDeps[name] || version;
      }
      matched.push(`${name}@${version}`);
    }
  }

  return matched;
}

// Gather metadata
const srcHash = getGitHash();
const srcBranch = getGitBranch();
const srcTag = getGitTag();
const patternflyDeps = listScopedDeps('@patternfly');
const rhCloudServicesDeps = listScopedDeps('@redhat-cloud-services');

// Format dependency arrays as strings — matches build_app_info.sh output format
// (jq --arg treats the formatted array as a string value)
function formatDepsString(deps) {
  if (deps.length === 0) return '';
  return deps.join('","');
}

// Generate app.info.json — matches build_app_info.sh output format
const appInfo = {
  app_name: appName,
  node_version: nodeVersion,
  src_hash: srcHash,
  src_tag: srcTag,
  src_branch: srcBranch,
  app_version: appVersion,
  patternfly_dependencies: formatDepsString(patternflyDeps),
  rh_cloud_services_dependencies: formatDepsString(rhCloudServicesDeps)
};

// Generate app.info.deps.json — structured dependency metadata
const appInfoDeps = {
  app_name: appName,
  patternfly_dependencies: patternflyDeps,
  rh_cloud_services_dependencies: rhCloudServicesDeps
};

// Ensure build directory exists
if (!fs.existsSync(buildDir)) {
  console.error(`Warning: Build directory ${buildDir} does not exist. Skipping metadata generation.`);
  process.exit(0);
}

// Write files (skip if already exist — consumer may generate their own)
const appInfoPath = path.join(buildDir, 'app.info.json');
const appInfoDepsPath = path.join(buildDir, 'app.info.deps.json');

if (fs.existsSync(appInfoPath)) {
  console.log('app.info.json already exists, skipping generation');
} else {
  fs.writeFileSync(appInfoPath, JSON.stringify(appInfo, null, 2) + '\n');
  console.log(`Generated ${appInfoPath}`);
}

if (fs.existsSync(appInfoDepsPath)) {
  console.log('app.info.deps.json already exists, skipping generation');
} else {
  fs.writeFileSync(appInfoDepsPath, JSON.stringify(appInfoDeps, null, 2) + '\n');
  console.log(`Generated ${appInfoDepsPath}`);
}
