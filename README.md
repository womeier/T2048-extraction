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

| project | engine | x86_64-linux | aarch64-linux | aarch64-darwin |
|---|---|:---:|:---:|:---:|
| `chromium` — Desktop Chrome | Chromium | ✓ | ✓ | ✓ |
| `firefox` — Desktop Firefox | Firefox | ✓ | ✓ | ✓ |
| `webkit` — Desktop Safari | WebKit | ✓ | ✓ | ✓ |
| `pixel-7` — Pixel 7 (touch) | Chromium | ✓ | ✓ | ✓ |
| `iphone-14` — iPhone 14 (touch) | WebKit | ✓ | ✓ | ✓ |

CI runs the full table on every platform, one runner each
(`.github/workflows/tests.yml`).

Two targets:
- quick — chromium only, what `nix flake check` runs (fast)
- full — every project of the table: `nix build -L .#t2048-e2e-full`, then
  `cat result/report` for the platform, the browsers and the results (CI runs
  the full build)

WebKit's headless EGL renders with nixpkgs mesa, software: its libEGL is
libglvnd, which finds no vendor ICD in a pure nix environment, so the
targets set `__EGL_VENDOR_LIBRARY_DIRS` to mesa's ICD and the surfaceless
platform. (Bridging to host drivers, [nixGL](https://github.com/nix-community/nixGL)-style,
cannot serve the sandboxed check targets: there is no host GL to bridge
to — and the tests need a working EGL display, not the host GPU.)

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
