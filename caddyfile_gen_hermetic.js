#!/usr/bin/env node
// caddyfile_gen_hermetic.js — Generate Caddyfile for hermetic frontend builds
//
// Equivalent to the generate_caddy_config() function in server_config_gen.sh,
// but uses Node.js instead of jq for package.json parsing so it works in
// hermetic build environments where jq is not available.
//
// Environment variables:
//   PACKAGE_JSON_PATH  Path to package.json (default: "package.json")
//   APP_BUILD_DIR      Build output directory name (default: "dist")
//
// Skips generation if a Caddyfile already exists (consumer override).

'use strict';

const fs = require('fs');

const CADDYFILE_PATH = 'Caddyfile';

// Skip if consumer provides their own Caddyfile
if (fs.existsSync(CADDYFILE_PATH)) {
  console.log('Caddyfile already exists, skipping generation');
  process.exit(0);
}

// Read app name from package.json insights.appname field
const pkgPath = process.env.PACKAGE_JSON_PATH || 'package.json';
let appName = 'app';
try {
  const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
  appName = (pkg.insights && pkg.insights.appname) || 'app';
} catch (err) {
  console.error(`Warning: Could not read ${pkgPath}: ${err.message}`);
  console.error('Using default app name: app');
}

// Caddy config template — matches server_config_gen.sh generate_caddy_config()
// {$VAR} is Caddy's runtime environment variable syntax (not shell expansion)
//
// NOTE: The deploy stage always copies ${APP_BUILD_DIR} to /srv/dist regardless
// of the source directory name, so file_server roots must use /srv/dist (not
// /srv/${APP_BUILD_DIR}). This matches the regular Dockerfile behavior where
// OUTPUT_DIR defaults to "dist" at Caddyfile generation time.
const caddyfile = `{
\t{$CADDY_TLS_MODE}
\tauto_https disable_redirects
\tservers {
\t\tmetrics
\t}
}

:9000 {
\tmetrics /metrics
}

:8000 {
\t{$CADDY_TLS_CERT}
\tlog

\t# Handle main app route
\t@app_match {
\t\tpath /apps/${appName}*
\t}
\thandle @app_match {
\t\turi strip_prefix /apps/${appName}
\t\tfile_server * {
\t\t\troot /srv/dist
\t\t\tbrowse
\t\t}
\t}

\t# Handle env based main route
\t@env_match {
\t\tpath {$ENV_PUBLIC_PATH}*
\t}

\thandle @env_match {
\t\turi strip_prefix {$ENV_PUBLIC_PATH}
\t\tfile_server * {
\t\t\troot /srv/dist
\t\t\tbrowse
\t\t}
\t}

\thandle / {
\t\tredir /apps/chrome/index.html permanent
\t}
}
`;

fs.writeFileSync(CADDYFILE_PATH, caddyfile);
console.log(`Generated Caddyfile for app: ${appName}`);
