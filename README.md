# Verified implementation of 2048

### Build and run
```
nix build
cd result && python3 -m http.server
# then open localhost:8000 in the browser
```

### State representation
The game state is a string of numbers: the seed, then a `#`, then the 16
cells of the board separated by commas, row by row (`0` is an empty cell):
```
seed#c0,c1,...,c15
```
The state is saved to the browser's localStorage after every move so the game survives a reload.
