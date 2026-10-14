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

### Platform support and tests
The extracted Wasm binaries require Wasm 2.0 + the Tail call extension.
All browsers later than the ones listed [here](https://webassembly.org/features/) in the `Tail Call` row should be supported.

The `tests/` folder holds a [Playwright](https://playwright.dev) suite that tests the final web bundle.
The device profiles come from Playwright's device descriptors (the touch devices exercise the on-screen
controls).

| browser profile | engine | x86_64-linux | aarch64-linux | aarch64-darwin | x86_64-darwin | windows |
|---|---|:---:|:---:|:---:|:---:|:---:|
| `chromium` — Desktop Chrome | Chromium | ✓ | ✓ | ✓ | ✓ | — |
| `firefox` — Desktop Firefox | Firefox | ✓ | ✓ | ✓ | ✓ | — |
| `webkit` — Desktop Safari | WebKit | ✓ | ✓ | ✓ | ✓ | — |
| `pixel-7` — Pixel 7 (touch) | Chromium | ✓ | ✓ | ✓ | ✓ | — |
| `iphone-14` — iPhone 14 (touch) | WebKit | ✓ | ✓ | ✓ | ✓ | — |
| `msedge` — Desktop Edge | Edge | — | — | — | — | ✓ |

| platform | nixpkgs | Playwright | Chromium | Firefox | WebKit |
|---|---|:---:|:---:|:---:|:---:|
| x86_64-linux | unstable | 1.63.0 | 153.0.8010.12 | 155.0 | 26.6 |
| aarch64-linux | unstable | 1.63.0 | 153.0.8010.12 | 155.0 | 26.6 |
| aarch64-darwin | unstable | 1.63.0 | 153.0.8010.12 | 155.0 | 26.6 |
| x86_64-darwin | 26.05-darwin | 1.59.1 | 147.0.7727.15 | 148.0.2 | 26.4 |
| windows | — | 1.63.0, from npm | Edge, latest (currently 154.0.4258.53) | — | — |

nix has no native Windows support. So a custom setup is used with the `msedge` Playwright channel on Windows.
```
cd tests && npm install && npx playwright test --project=msedge
```

CI runs the full table on every platform, one runner each
(`.github/workflows/tests.yml`); Intel macOS runs on `macos-15-intel`, and
`windows-latest` runs `msedge` on the Edge of its image.

Run a single project by hand, from the dev shell after `nix build`:
```
cd tests && playwright test             # everything
cd tests && playwright test --project=chromium
```
