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
