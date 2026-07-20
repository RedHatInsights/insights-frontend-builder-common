#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const buildDir = process.env.APP_BUILD_DIR || 'dist';

fs.mkdirSync(path.join(buildDir, 'css'), { recursive: true });
fs.mkdirSync(path.join(buildDir, 'js'), { recursive: true });

fs.writeFileSync(
  path.join(buildDir, 'index.html'),
  '<!DOCTYPE html><html><head><title>Test PNPM App</title></head><body><h1>Test PNPM App</h1></body></html>'
);
fs.writeFileSync(path.join(buildDir, 'css', 'app.css'), 'body { margin: 0; padding: 0; }');
fs.writeFileSync(path.join(buildDir, 'js', 'app.js'), 'console.log("Test pnpm app loaded");');
fs.writeFileSync(
  path.join(buildDir, 'manifest.json'),
  JSON.stringify({ name: 'test-pnpm-app', version: '1.0.0' }, null, 2)
);

if (process.env.BUILD_VARIANT === 'plugin') {
  fs.writeFileSync(path.join(buildDir, 'plugin-build.txt'), 'plugin build');
}

console.log(`Build complete! Files created in ${buildDir}/`);
