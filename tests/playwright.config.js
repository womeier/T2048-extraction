// Playwright end-to-end configuration for the T2048 web build.
//
// The application under test is the final `t2048-web` bundle from the
// flake: index.html, index.js and t2048.wasm (the whole verified game
// compiled to a single Wasm module by CertiRocq).
//
// The app fetches its Wasm module, so it needs a real HTTP origin; a
// python http.server of the bundle is started and torn down per run.
//
// Point T2048_APP_DIR at a bundle; the default picks the flake's
// ./result symlink, so `cd tests && playwright test` works right
// after `nix build`. The nix targets set it to the store path.
//
// Projects: the three browser engines as desktop profiles, plus touch
// devices from Playwright's device descriptors (Pixel 7 for
// Android/Chromium, iPhone 14 for iOS/WebKit) — the on-screen controls
// are the touch interface, and every project runs the whole spec. On
// Windows there is one more, `msedge`; see below.
const { defineConfig, devices } = require('@playwright/test');
const path = require('node:path');

const appDir = process.env.T2048_APP_DIR
  ? path.resolve(process.env.T2048_APP_DIR)
  : path.resolve(__dirname, '..', 'result');

const port = Number(process.env.T2048_PORT || 8123);
const baseURL = `http://127.0.0.1:${port}`;

// The bundle is served by python's http.server; Windows installs the
// interpreter as `python`, everywhere else it is `python3`.
const python = process.platform === 'win32' ? 'python' : 'python3';

const projects = [
  { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
  { name: 'webkit', use: { ...devices['Desktop Safari'] } },
  { name: 'pixel-7', use: { ...devices['Pixel 7'] } },
  { name: 'iphone-14', use: { ...devices['iPhone 14'] } },
];

// Edge, on Windows only. Nix has no Windows support, so that platform
// cannot take its browsers from nixpkgs the way the five projects above
// do; `channel: 'msedge'` drives the Edge installed on the machine
// instead (on the CI runner, the one its image ships). Hence the guard:
// off Windows the channel points at a browser that is not there.
if (process.platform === 'win32') {
  projects.push({
    name: 'msedge',
    use: { ...devices['Desktop Edge'], channel: 'msedge' },
  });
}

// Every run reports the platform it ran on: the suite exercises real
// browser engines on the host (Wasm tail calls), so this matters. The
// workers load this config too, hence the once-in-the-runner guard.
if (process.env.TEST_WORKER_INDEX === undefined) {
  console.log(
    `T2048 e2e — platform: ${process.platform}/${process.arch}, app: ${appDir}, ` +
      `projects: ${projects.map((p) => p.name).join(', ')}`,
  );
}

module.exports = defineConfig({
  testDir: '.',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'line',
  use: {
    baseURL,
    // run inside the nix build sandbox, without the chromium SUID sandbox
    chromiumSandbox: false,
    trace: 'retain-on-failure',
  },
  projects,
  webServer: {
    command: `${python} -m http.server ${port} --directory ${JSON.stringify(appDir)}`,
    url: baseURL,
    reuseExistingServer: !process.env.CI,
    stdout: 'ignore',
    stderr: 'ignore',                 // keep the server's request log out of the report
  },
});
