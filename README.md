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

### State representation in Wasm/JavaScript
The game state is a string: the seed, then a `#`, then the 16
cells of the board separated by commas, row by row (`0` is an empty cell):
```
seed#c0,c1,...,c15
```
The state is saved to the browser's localStorage after every move so the game survives a reload.

### Platform tests
The `tests/` folder holds a [Playwright](https://playwright.dev) suite that
tests the final web bundle; browsers and the Playwright runner come from
nixpkgs. Every project runs the whole spec; the device profiles come from
Playwright's device descriptors (the touch devices exercise the on-screen
controls).

| browser profile | engine | x86_64-linux | aarch64-linux | aarch64-darwin | x86_64-darwin | windows |
|---|---|:---:|:---:|:---:|:---:|:---:|
| `chromium` — Desktop Chrome | Chromium | ✓ | ✓ | ✓ | ✓ | — |
| `firefox` — Desktop Firefox | Firefox | ✓ | ✓ | ✓ | ✓ | — |
| `webkit` — Desktop Safari | WebKit | ✓ | ✓ | ✓ | ✓ | — |
| `pixel-7` — Pixel 7 (touch) | Chromium | ✓ | ✓ | ✓ | ✓ | — |
| `iphone-14` — iPhone 14 (touch) | WebKit | ✓ | ✓ | ✓ | ✓ | — |
| `msedge` — Desktop Edge | Edge | — | — | — | — | ✓ |

The versions are the ones the pinned nixpkgs ships, so they move with
`flake.lock`. x86_64-darwin is the exception: it builds from the 26.05
NixOS-darwin branch, the last nixpkgs that supports the system, so it runs
a release behind the rest.

| platform | nixpkgs | Playwright | Chromium | Firefox | WebKit |
|---|---|:---:|:---:|:---:|:---:|
| x86_64-linux | unstable | 1.63.0 | 153.0.8010.12 | 155.0 | 26.6 |
| aarch64-linux | unstable | 1.63.0 | 153.0.8010.12 | 155.0 | 26.6 |
| aarch64-darwin | unstable | 1.63.0 | 153.0.8010.12 | 155.0 | 26.6 |
| x86_64-darwin | 26.05-darwin | 1.59.1 | 147.0.7727.15 | 148.0.2 | 26.4 |
| windows | — | 1.63.0, from npm | Edge, from the machine | — | — |

Windows is outside all of that: nix has no native Windows support, so the
browsers cannot come from nixpkgs there. `msedge` is a Playwright channel —
the Edge installed on the machine — and the config only adds the project on
Windows, where the runner comes from npm instead, pinned to the nixpkgs
version in `tests/package.json`:
```
cd tests && npm install && npx playwright test --project=msedge
```
That project is reproducible only as far as the machine's Edge is.

CI runs the full table on every platform, one runner each
(`.github/workflows/tests.yml`); Intel macOS runs on `macos-15-intel`, and
`windows-latest` runs `msedge` on the Edge of its image.
The bundle itself is built once, on x86_64-linux. 

```
nix build && T2048_APP_DIR=$PWD/result \
  nix develop .#e2e -c sh -c 'cd tests && playwright test'
```

Run a single project by hand, from the dev shell after `nix build`:
```
cd tests && playwright test             # everything
cd tests && playwright test --project=chromium
```
