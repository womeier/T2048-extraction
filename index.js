// T2048 front-end — drives the Wasm module compiled by CertiRocq from the
// verified T2048 Rocq development (extraction.v).
//
// The module exports:
//   main_function  : sets up the runtime, computes t2048_wasm_api into `result`
//   result         : global holding the value last returned by any call
//   mem_ptr        : global, next free address in linear memory (JS may bump it)
//   out_of_mem     : global, set to 1 when an allocation failed
//   memory         : linear memory
//   ...            : every compiled function, under a mangled name
//
// Value representation (CertiRocq Wasm backend):
//   immediate : (n << 1) | 1            nullary constructors (nil, N0, O, ...)
//   block     : [tag, fields...]        at an even address, i32 each
//   list      : nil = 1, cons = [0, head, tail]
//   nat       : O = 1, S = [0, pred]
//   N         : N0 = 1, Npos p = [0, p]
//   positive  : xH = 1, xI p = [0, p]  (= 2p+1), xO p = [1, p]  (= 2p)
//   pair      : [0, fst, snd]
//   state     : record [tag, seed : N, board : list (list N)]
//   closure   : [tag, fidx, env]       fidx indexes the module's export list
//
// Calling convention (confirmed against CertiRocq 0.9.1):
//   f(env, arg) for a one-argument function; the return value is void,
//   the result is read from the `result` global afterwards.

// Tail-call feature detection, adapted from
// https://github.com/GoogleChromeLabs/wasm-feature-detect (Apache-2.0)
const tailCall = async () =>
  WebAssembly.validate(new Uint8Array([
    0, 97, 115, 109, 1, 0, 0, 0, 1, 4, 1, 96, 0, 0, 3, 2, 1, 0, 10, 6, 1, 4, 0, 18, 0, 11,
  ]));

const fail = (msg) => {
  const el = document.getElementById("err");
  el.textContent = msg;
  el.style.display = "block";
};

let ex;      // module exports
let names;   // export names, in export order (= function index order)
let mem32;   // i32 view of linear memory (refreshed — memory may grow)
let api;     // resolved closures: init, move, dir_of_nat, message_tag, init_with_seed
let statePtr;    // address of the current state block
let gameOver = false;

const refresh = () => { mem32 = new Uint32Array(ex.memory.buffer); };
const ld = (addr, i) => mem32[(addr >>> 2) + (i || 0)];

// --- allocation (shares mem_ptr with the module) ---------------------------
function alloc(words) {
  const addr = ex.mem_ptr.value;
  if (addr === 0 || (addr & 3) !== 0) throw new Error("bad mem_ptr");
  const base = addr >>> 2;
  for (let i = 0; i < words.length; i++) mem32[base + i] = words[i];
  ex.mem_ptr.value = addr + 4 * words.length;
  return addr;
}

// --- builders ---------------------------------------------------------------
const mkNat = (n) => { let v = 1; for (let i = 0; i < n; i++) v = alloc([0, v]); return v; };
const mkPos = (n) =>
  n === 1 ? 1 : n % 2 === 0 ? alloc([1, mkPos(n / 2)]) : alloc([0, mkPos((n - 1) / 2)]);
const mkN = (n) => n === 0 ? 1 : alloc([0, mkPos(n)]);
const mkPair = (a, b) => alloc([0, a, b]);

// --- decoders ---------------------------------------------------------------
const posVal = (v) =>
  (v & 1) ? 1 : (ld(v, 0) === 0 ? 2 * posVal(ld(v, 1)) + 1 : 2 * posVal(ld(v, 1)));
const nVal = (v) => (v & 1) ? 0 : posVal(ld(v, 1));
const natVal = (v) => { let n = 0; while (!(v & 1)) { v = ld(v, 1); n++; } return n; };

function readState(sp) {
  const seed = nVal(ld(sp, 1));
  const rows = [];
  let p = ld(sp, 2);
  while (!(p & 1)) {                       // list of rows
    const row = [];
    let q = ld(p, 1);
    while (!(q & 1)) { row.push(nVal(ld(q, 1))); q = ld(q, 2); }
    rows.push(row);
    p = ld(p, 2);
  }
  return { seed, rows };
}

// --- calling into the module ------------------------------------------------
function callApi(clos, ...args) {
  const f = ex[names[clos.fidx]];
  if (typeof f !== "function") throw new Error("closure did not resolve to a function");
  // one-argument functions have signature (env, arg); adapt if ever env-less
  if (f.length === args.length) f(...args);
  else f(clos.env, ...args);
  refresh();                               // memory may have grown
  if (ex.out_of_mem.value === 1) throw new Error("the Wasm module ran out of memory");
  return ex.result.value;
}

// t2048_wasm_api = record [tag, move, dir_of_nat, message_tag, init_with_seed]
function readApi() {
  const rec = ex.result.value;
  const clos = (i) => {
    const c = ld(rec, i);
    return { fidx: ld(c, 1), env: ld(c, 2) };
  };
  return {
    move: clos(1),
    dir_of_nat: clos(2),
    message_tag: clos(3),
    init_with_seed: clos(4),
  };
}

// --- game -------------------------------------------------------------------
const MESSAGES = ["Invalid move", "Game over — you lost", "You win! — 2048 reached", ""];

function render(tag = 3) {
  const st = readState(statePtr);
  const boardEl = document.getElementById("board");
  boardEl.innerHTML = "";
  for (const row of st.rows) {
    for (const v of row) {
      const cell = document.createElement("div");
      cell.className = "cell";
      if (v !== 0) { cell.dataset.v = v; cell.textContent = v; }
      boardEl.appendChild(cell);
    }
  }
  const statusEl = document.getElementById("status");
  statusEl.textContent = MESSAGES[tag] ?? "";
  statusEl.className = tag === 2 ? "won" : tag === 1 ? "lost" : "";
}

function newGame() {
  const seed = new Uint32Array(1);
  crypto.getRandomValues(seed);
  statePtr = callApi(api.init_with_seed, mkN(seed[0] || 1));
  gameOver = false;
  render();
}

function play(dir) {
  if (gameOver || statePtr === undefined) return;
  const dirVal = callApi(api.dir_of_nat, mkNat(dir));
  const resPtr = callApi(api.move, mkPair(dirVal, statePtr));
  statePtr = ld(resPtr, 1);
  const tag = natVal(callApi(api.message_tag, ld(resPtr, 2)));
  if (tag === 1 || tag === 2) gameOver = true;
  render(tag);
}

async function boot() {
  if (!await tailCall()) {
    return fail("This browser does not support Wasm tail calls, which the " +
      "CertiRocq-compiled module needs. Please use a recent Firefox, Chrome " +
      "or Safari (see webassembly.org/features).");
  }
  try {
    const buffer = await (await fetch("t2048.wasm")).arrayBuffer();
    const { instance } = await WebAssembly.instantiate(buffer, { env: {} });
    ex = instance.exports;
    names = Object.keys(ex);
    refresh();
    ex.main_function();
    refresh();
    if (ex.out_of_mem.value === 1) return fail("Wasm setup ran out of memory.");
    api = readApi();
    newGame();
  } catch (e) {
    fail("Failed to start the game: " + e);
  }
}

for (const b of document.querySelectorAll("#controls button")) {
  b.addEventListener("click", () => play(Number(b.dataset.dir)));
}
document.getElementById("btn-new").addEventListener("click", newGame);
addEventListener("keydown", (e) => {
  const dir = { ArrowUp: 0, ArrowDown: 1, ArrowLeft: 2, ArrowRight: 3 }[e.key];
  if (dir !== undefined) { e.preventDefault(); play(dir); }
});

boot();
