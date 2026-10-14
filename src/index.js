// T2048 front-end - js bindings for the Wasm module compiled by CertiRocq from the
// verified T2048 Rocq development (extraction.v).
//
// The Wasm module exports:
//   main_function  : sets up the runtime, computes T2048_wasm_api into `result`
//   result         : global holding the value last returned by any call
//   mem_ptr        : global, next free address in linear memory (JS may bump it)
//   out_of_mem     : global, set to 1 when an allocation failed
//   memory         : linear memory
//   ...            : every compiled function, under a mangled name
//
// Value representation (CertiRocq Wasm backend):
//   immediate : (n << 1) | 1        nullary constructors (nil, Rm, ...)
//   block     : [tag, fields...]    at an even address, i32 each
//   list byte : nil = 1, cons b l = [0, byte, l];
//               a byte is the immediate 2 * charCode + 1
//   uint63    : an 8-byte little-endian i64 cell, passed as an i32 pointer
//   pair      : [0, fst, snd]
//   closure   : [tag, fidx, env]    fidx indexes the module's export list
//
// Calling convention (CertiRocq 0.9.1):
//   f(env, arg) for a one-argument function; the return value is void,
//   the result is read from the `result` global afterwards.
//
// T2048 moves are the nullary constructors of
//     Inductive move := Rm | Lm | Um | Dm.   (right, left, up, down)
// encoded in declaration order: Rm = 1, Lm = 3, Um = 5, Dm = 7.
// The seed is a primitive 63-bit integer, the state the byte list
// "seed#c0,...,c15" and the message one of "invalid", "lost", "won",
// "continue".

// Tail-call feature detection, adapted from
// https://github.com/GoogleChromeLabs/wasm-feature-detect (Apache-2.0)
const tailCall = async () =>
  WebAssembly.validate(new Uint8Array([
    0, 97, 115, 109, 1, 0, 0, 0, 1, 4, 1, 96, 0, 0, 3, 2, 1, 0, 10, 6, 1, 4, 0, 18, 0, 11,
  ]));

const MOVES = { up: 5, down: 7, left: 3, right: 1 };
const MESSAGES = {
  invalid: "Invalid move",
  lost: "Game over — you lost",
  won: "You win! — 2048 reached",
  continue: "",
};

// `fatal` is for a game that never started: there is no board worth looking
// at then, so the empty one and its dead controls go away and the message is
// the page. Failures during a game keep theirs — the position is still on
// screen, and out of memory asks for a reload to get it back.
const fail = (msg, fatal = false) => {
  const el = document.getElementById("err");
  el.textContent = msg;
  el.style.display = "block";
  if (fatal) {
    for (const id of ["board", "status", "controls", "btn-new"]) {
      document.getElementById(id).style.display = "none";
    }
  }
};

let ex;           // module exports
let names;        // export names, in export order (= function index order)
let api;          // resolved closures: move, init_with_seed
let memBase;      // mem_ptr watermark taken after main_function: everything
                   // that stays alive (api record, closure envs) is below it
let state;         // the game state as a string "seed#c0,...,c15" (source of
                   // truth; rebuilt in Wasm memory for each call)
let gameOver = false;

// Growing the linear memory detaches its old ArrayBuffer, so a cached
// DataView goes stale after a grow. Check on every access instead of
// refreshing at each call site: the identity test is O(1) and can never
// miss (a stale view's buffer is a different object).
let dataView = null;
const view = () =>
  dataView?.buffer === ex.memory.buffer ? dataView
                                        : (dataView = new DataView(ex.memory.buffer));

// read the i-th 32-bit word of the block at addr, i.e. the i32 at the
// byte address addr + 4 * i: tag = ld(p, 0), first field = ld(p, 1), ...
const ld = (addr, i) => view().getInt32(addr + 4 * i, true);

// --- allocation (shares mem_ptr with the module) ---------------------------
// Reports "out of memory" when mem_ptr cannot be advanced within the linear
// memory, or when the module itself has set out_of_mem.
function outOfMemory() {
  gameOver = true;
  fail("Out of memory: mem_ptr reached the end of the Wasm module's " +
    "linear memory. Reload the page to continue.");
  throw Object.assign(new Error("out of memory"), { oom: true });
}

function alloc(words) {
  const addr = ex.mem_ptr.value;
  if (addr === 0 || addr % 4 !== 0) throw new Error("bad mem_ptr");
  const end = addr + words.length * 4;
  if (end > ex.memory.buffer.byteLength) {
    // grow the linear memory, like the module's own allocator does
    const pages = Math.ceil((end - ex.memory.buffer.byteLength) / 65536);
    try {
      ex.memory.grow(pages);
    } catch {
      outOfMemory();
    }
  }
  for (let i = 0; i < words.length; i++) view().setInt32(addr + 4 * i, words[i], true);
  ex.mem_ptr.value = end;
  return addr;
}

// --- builders ---------------------------------------------------------------
const mkPair = (a, b) => alloc([0, a, b]);

// uint63 seed: an 8-byte little-endian i64 cell (two i32 words: low, high).
// Takes the value as one integer (a BigInt, or a JS number that is an
// exact integer), fails outside the 63-bit unsigned range, and splits it itself.
function mkUint63(n) {
  const v = typeof n === "bigint" ? n : BigInt(n);  // throws on non-integers
  if (v < 0n || 2n ** 63n <= v) {
    throw new Error("mkUint63: not a 63-bit unsigned integer: " + n);
  }
  return alloc([Number(v % 2n ** 32n), Number(v / 2n ** 32n)]);
}

// --- decoder ----------------------------------------------------------------
function bytesToString(p) {
  let s = "";
  while (!(p & 1)) {                    // nil = 1
    s += String.fromCharCode(ld(p, 1) >> 1);
    p = ld(p, 2);
  }
  return s;
}

// byte list from a JavaScript string (to restore a saved game)
function bytesFromString(s) {
  let p = 1;                                     // nil
  for (let i = s.length - 1; i >= 0; i--) {
    p = alloc([0, s.charCodeAt(i) * 2 + 1, p]);  // cons b tail
  }
  return p;
}

// --- calling into the module ------------------------------------------------
function callApi(clos, ...args) {
  const f = ex[names[clos.fidx]];
  if (typeof f !== "function") throw new Error("closure did not resolve to a function");
  // one-argument functions have signature (env, arg); adapt if ever env-less
  if (f.length === args.length) f(...args);
  else f(clos.env, ...args);
  if (ex.out_of_mem.value === 1) outOfMemory();
  return ex.result.value;
}

// T2048_wasm_api = record [tag, move, init_with_seed]
function readApi() {
  const rec = ex.result.value;
  const clos = (i) => {
    const c = ld(rec, i);
    return { fidx: ld(c, 1), env: ld(c, 2) };
  };
  return { move: clos(1), init_with_seed: clos(2) };
}

// Rewind mem_ptr to the watermark taken after main_function
// nothing is ever freed in CertiRocq's Wasm backend, there is no GC
// we just overwrite the data from the previous calls.
// This is save because uninitialized memory is never read.
const rewind = () => { ex.mem_ptr.value = memBase; };

// --- persistence (survive F5) ------------------------------------------------
const SAVE_KEY = "t2048";

function save() {
  console.log(state);
  try {
    localStorage.setItem(SAVE_KEY, state);
  } catch { /* storage unavailable — play on */ }
}

function restore() {
  try {
    const s = localStorage.getItem(SAVE_KEY);
    if (typeof s !== "string" || !s.includes("#")) return null;
    return s;
  } catch {
    return null;
  }
}

// --- game -------------------------------------------------------------------
function render(msg = "continue") {
  const cells = state.split("#")[1].split(",");   // seed, then the 16 cells
  const boardEl = document.getElementById("board");
  boardEl.innerHTML = "";
  for (const v of cells) {
    const cell = document.createElement("div");
    cell.className = "cell";
    const n = Number(v);
    if (n !== 0) { cell.dataset.v = n; cell.textContent = n; }
    boardEl.appendChild(cell);
  }
  const statusEl = document.getElementById("status");
  statusEl.textContent = MESSAGES[msg] ?? msg;
  statusEl.className = msg === "won" ? "won" : msg === "lost" ? "lost" : "";
}

function newGame() {
  const rnd = new BigUint64Array(1);
  crypto.getRandomValues(rnd);
  const seed = (rnd[0] % 2n ** 63n) || 1n;   // 63 random bits, never zero
  try {
    rewind();
    state = bytesToString(callApi(api.init_with_seed, mkUint63(seed)));
    gameOver = false;
    render();
    save();
  } catch (e) {
    if (!e.oom) fail("Failed to start a new game: " + e);
  }
}

function play(dir) {
  if (gameOver || state === undefined) return;
  try {
    rewind();
    const resPtr = callApi(api.move, mkPair(MOVES[dir], bytesFromString(state)));
    state = bytesToString(ld(resPtr, 1));
    const msg = bytesToString(ld(resPtr, 2));
    if (msg === "won" || msg === "lost") gameOver = true;
    render(msg);
    save();
  } catch (e) {
    if (!e.oom) fail("Move failed: " + e);
  }
}

async function boot() {
  // No WebAssembly at all — iOS/macOS Lockdown Mode turns it off, and so can
  // an enterprise policy or an extension. The global is then not merely
  // feature-poor but absent, so this has to come before the tail-call probe:
  // that one reads `WebAssembly` and would throw a ReferenceError out of
  // boot() before anything could be reported.
  if (typeof WebAssembly === "undefined") {
    return fail("This browser has WebAssembly disabled, and the whole game is " +
      "a Wasm module. On iPhone, iPad and Mac that is what Lockdown Mode does; " +
      "otherwise a browser policy or an extension has switched it off.", true);
  }
  if (!await tailCall()) {
    return fail("This browser does not support Wasm tail calls, which the " +
      "CertiRocq-compiled module needs. Please use a recent Firefox, Chrome " +
      "or Safari (see webassembly.org/features).", true);
  }
  try {
    const buffer = await (await fetch("t2048.wasm")).arrayBuffer();
    const { instance } = await WebAssembly.instantiate(buffer, { env: {} });
    ex = instance.exports;
    names = Object.keys(ex);
    ex.main_function();
    if (ex.out_of_mem.value === 1) return fail("Wasm setup ran out of memory.", true);
    api = readApi();
    memBase = ex.mem_ptr.value;
    const saved = restore();
    if (saved) {
      // the outcome is not derived here: the module itself reports "won",
      // "lost" or "invalid" on the next move, and play() sets gameOver from
      // the terminal ones
      state = saved;
      gameOver = false;
      render();
    } else {
      newGame();
    }
  } catch (e) {
    if (!e.oom) fail("Failed to start the game: " + e, true);
  }
}

// console helper: jump to a winning board
window.setStateWin = () => {
  state = "5#1024,512,512,0,0,0,0,0,0,0,0,0,0,0,0,0";
  gameOver = false;
  render();
  save();
};

for (const b of document.querySelectorAll("#controls button")) {
  b.addEventListener("click", () => play(b.dataset.move));
}
document.getElementById("btn-new").addEventListener("click", newGame);
addEventListener("keydown", (e) => {
  const dir = {
    ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right",
  }[e.key];
  if (dir !== undefined) { e.preventDefault(); play(dir); }
});

boot();
