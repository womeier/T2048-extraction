# Verified implementation of 2048

### About
This repo contains a demo based on Laurent Théry's [implementation](https://github.com/thery/T2048) of the game 2048.
It is extracted to a Wasm binary using CertiRocq.

One can try it at [https://womeier.github.io/T2048-extraction/](https://womeier.github.io/T2048-extraction/).


### Build and run locally
```
nix build
cd result && python3 -m http.server
# then open localhost:8000 in the browser
```

### End-to-end tests
The `tests/` folder holds a [Playwright](https://playwright.dev) suite that
tests the final web bundle; browsers and the Playwright runner come from
nixpkgs. Every project runs the whole spec; the device profiles come from
Playwright's device descriptors (the touch devices exercise the on-screen
controls).

| project | engine | x86_64-linux | aarch64-linux | aarch64-darwin | x86_64-darwin |
|---|---|:---:|:---:|:---:|:---:|
| `chromium` — Desktop Chrome | Chromium 153.0.8010.12 | ✓ | ✓ | ✓ | ✓ |
| `firefox` — Desktop Firefox | Firefox 155.0 | ✓ | ✓ | ✓ | ✓ |
| `webkit` — Desktop Safari | WebKit 26.6 | ✓ | ✓ | ✓ | ✓ |
| `pixel-7` — Pixel 7 (touch) | Chromium 153.0.8010.12 | ✓ | ✓ | ✓ | ✓ |
| `iphone-14` — iPhone 14 (touch) | WebKit 26.6 | ✓ | ✓ | ✓ | ✓ |

The versions are the ones the pinned nixpkgs ships, so they move with
`flake.lock`: the table is Playwright 1.63.0 from nixpkgs-unstable.
x86_64-darwin is the exception — it builds from the 26.05 darwin branch,
Playwright 1.59.1, which carries Chromium 147.0.7727.15, Firefox 148.0.2
and WebKit 26.4.

CI runs the full table on every platform, one runner each
(`.github/workflows/tests.yml`); Intel macOS runs on `macos-15-intel`. The
bundle itself is built once, on x86_64-linux — the Wasm module is
platform-independent, so the runners differ in their browsers, not in the
code under test: the build job uploads index.html, index.js and t2048.wasm
as an artifact and each e2e job tests that one artifact. Those jobs build
none of the project; they enter the e2e shell (the Playwright runner, its
browsers and python, no Rocq toolchain) and point it at the bundle:
```
nix build && T2048_APP_DIR=$PWD/result \
  nix develop .#e2e -c sh -c 'cd tests && playwright test'
```
compcert and certirocq are never compiled in CI: the build job fetches them
substitute-only (`nix build --max-jobs 0 .#CertiRocq`, which fails instead
of building) from the public Rocq caches, or from the womeier cache, which
that same job pushes to so a nixpkgs bump the public ones have not caught
up with is covered.

Two nix targets build the bundle and run the suite against it in one go,
sandboxed — the local path, where rebuilding the project is the point:
- quick — chromium only, what `nix flake check` runs (fast)
- full — every project of the table: `nix build -L .#t2048-e2e-full`, then
  `cat result/report` for the platform, the browsers and the results

Run a single project by hand, from the dev shell after `nix build`:
```
cd tests && playwright test             # everything
cd tests && playwright test --project=chromium
```

### State representation in Wasm/JavaScript
The game state is a string: the seed, then a `#`, then the 16
cells of the board separated by commas, row by row (`0` is an empty cell):
```
seed#c0,c1,...,c15
```
The state is saved to the browser's localStorage after every move so the game survives a reload.
