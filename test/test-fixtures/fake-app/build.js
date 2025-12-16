#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// Get build directory from env or default to 'dist'
const buildDir = process.env.APP_BUILD_DIR || 'dist';

// Create dist directory
if (!fs.existsSync(buildDir)) {
  fs.mkdirSync(buildDir, { recursive: true });
}

// Create subdirectories
const cssDir = path.join(buildDir, 'css');
const jsDir = path.join(buildDir, 'js');
fs.mkdirSync(cssDir, { recursive: true });
fs.mkdirSync(jsDir, { recursive: true });

// Create test files
fs.writeFileSync(
  path.join(buildDir, 'index.html'),
  '<!DOCTYPE html><html><head><title>Test App</title></head><body><h1>Test App</h1></body></html>'
);

fs.writeFileSync(
  path.join(cssDir, 'app.css'),
  'body { margin: 0; padding: 0; }'
);

fs.writeFileSync(
  path.join(jsDir, 'app.js'),
  'console.log("Test app loaded");'
);

fs.writeFileSync(
  path.join(buildDir, 'manifest.json'),
  JSON.stringify({ name: 'test-app', version: '1.0.0' }, null, 2)
);

console.log(`Build complete! Files created in ${buildDir}/`);
