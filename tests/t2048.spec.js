// End-to-end tests for the final application: the t2048-web bundle of
// index.html, index.js and the Wasm module compiled from the verified T2048
// Rocq development by CertiRocq.
//
// The board is deterministic via the state format
//   "seed#c0,c1,...,c15"   (the 16 cells row by row, 0 = empty)
// set up with the window.setStateWin helper or localStorage, both provided
// by index.js. Game facts under test (from extraction.v):
//   - a fresh game has a single tile, 2 or 4 (gen_values)
//   - a move that neither shifts nor merges is "invalid"
//   - an invalid move on a board no direction can change is "lost"
//   - creating a 2048 tile (target) is "won", and the win board keeps all
//     tiles but gets no new one
// Plus the three browsers that cannot run the game at all (no JavaScript, no
// WebAssembly, or no tail calls): the page has to say so instead of sitting
// there dead.
const { test, expect } = require('@playwright/test');

// The 16 cell values, row by row, 0 for an empty cell.
const board = (page) =>
  page.locator('#board .cell').evaluateAll((cells) =>
    cells.map((c) => (c.dataset.v ? Number(c.dataset.v) : 0)),
  );

const tiles = (values) => values.filter((v) => v !== 0);

// Every tile of a fresh game (init_with_seed) is 2 or 4.
const checkFreshTiles = (values) => {
  for (const v of tiles(values)) expect([2, 4]).toContain(v);
};

// Wait until boot() finished: the async Wasm setup ends with the first
// render of a fresh game — one tile in 16 cells, no error banner.
async function bootFresh(page) {
  await page.goto('/');
  await expect(page).toHaveTitle(/verified 2048/);
  await expect(page.locator('#board .cell')).toHaveCount(16);
  await expect(page.locator('#board .cell[data-v]')).toHaveCount(1);
  await expect(page.locator('#err')).toBeHidden();
  const values = await board(page);
  checkFreshTiles(values);
  return values;
}

// Jump to one winning move away, via the console helper in index.js:
// [1024, 512, 512, 0 / zeros] — the next left move merges 512+512.
async function setWinningBoard(page) {
  await page.evaluate(() => window.setStateWin());
  await expect(page.locator('#board .cell[data-v="1024"]')).toHaveCount(1);
  await expect(page.locator('#board .cell[data-v="512"]')).toHaveCount(2);
}

test('boots and deals a fresh game: one tile, 2 or 4', async ({ page }) => {
  await bootFresh(page);
  await expect(page.locator('#status')).toHaveText('');
});

test('on-screen buttons play moves up to a win', async ({ page }) => {
  await bootFresh(page);
  await setWinningBoard(page);

  // left: 512+512 = 1024, and the game spawns a new tile ("continue")
  await page.click('#btn-left');
  await expect(page.locator('#status')).toHaveText('');
  const afterFirst = await board(page);
  expect(afterFirst.slice(0, 2)).toEqual([1024, 1024]);
  expect(tiles(afterFirst)).toHaveLength(3);

  // left again: 1024+1024 = 2048, the verified game reports the win
  await page.click('#btn-left');
  await expect(page.locator('#board .cell[data-v="2048"]')).toHaveCount(1);
  await expect(page.locator('#status')).toHaveText('You win! — 2048 reached');
  await expect(page.locator('#status')).toHaveClass(/won/);
});

test('keyboard arrows play moves; invalid ones leave the board untouched', async ({ page }) => {
  await bootFresh(page);
  await setWinningBoard(page);

  // up: no column of [1024,512,512,0 / zeros] can shift or merge
  const before = await board(page);
  await page.keyboard.press('ArrowUp');
  await expect(page.locator('#status')).toHaveText('Invalid move');
  expect(await board(page)).toEqual(before);

  // valid moves still work after an invalid one: left left wins
  await page.keyboard.press('ArrowLeft');
  await page.keyboard.press('ArrowLeft');
  await expect(page.locator('#board .cell[data-v="2048"]')).toHaveCount(1);
  await expect(page.locator('#status')).toHaveText('You win! — 2048 reached');
});

test('a full board without adjacent equal tiles is a loss', async ({ page }) => {
  // dead_board from extraction.v: every direction is a no-op, so any
  // move on it reports the loss
  const dead = '42#2,4,2,4,4,2,4,2,2,4,2,4,4,2,4,2';
  await page.addInitScript((s) => localStorage.setItem('t2048', s), dead);

  // the saved game is restored from localStorage on boot
  await page.goto('/');
  await expect(page.locator('#board .cell[data-v]')).toHaveCount(16);
  expect(await board(page)).toEqual([2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2]);

  await page.keyboard.press('ArrowLeft');
  await expect(page.locator('#status')).toHaveText('Game over — you lost');
  await expect(page.locator('#status')).toHaveClass(/lost/);
  expect(await board(page)).toEqual([2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2]);

  // a lost game no longer reacts to input
  await page.keyboard.press('ArrowRight');
  await expect(page.locator('#status')).toHaveText('Game over — you lost');
});

test('the game state survives a page reload', async ({ page }) => {
  await bootFresh(page);
  await setWinningBoard(page);
  await page.keyboard.press('ArrowLeft');
  const before = await board(page);

  await page.reload();
  await expect(page.locator('#board .cell[data-v]')).toHaveCount(3);
  expect(await board(page)).toEqual(before);

  // the restored game is still playable: left merges to the win
  await page.keyboard.press('ArrowLeft');
  await expect(page.locator('#board .cell[data-v="2048"]')).toHaveCount(1);
  await expect(page.locator('#status')).toHaveText('You win! — 2048 reached');
});

test('the New game button deals a fresh board', async ({ page }) => {
  await bootFresh(page);
  await setWinningBoard(page);

  await page.click('#btn-new');
  await expect(page.locator('#board .cell[data-v]')).toHaveCount(1);
  checkFreshTiles(await board(page));
  await expect(page.locator('#status')).toHaveText('');
});

// --- browsers that cannot run the module -------------------------------------
// Simulated rather than hunted down: the suite runs on browsers that all
// support both, and the engines are the real ones — only the one capability
// under test is taken away, before any page script runs.

test('a browser without WebAssembly says so, instead of dying silently', async ({ page }) => {
  // iOS/macOS Lockdown Mode removes the global entirely, so index.js cannot
  // even probe for tail calls — the check for this has to come first
  await page.addInitScript(() => { delete window.WebAssembly; });
  await page.goto('/');

  await expect(page.locator('#err')).toBeVisible();
  await expect(page.locator('#err')).toContainText('WebAssembly disabled');
  // a game that never started shows no board and no controls to press
  await expect(page.locator('#board')).toBeHidden();
  await expect(page.locator('#controls')).toBeHidden();
  await expect(page.locator('#btn-new')).toBeHidden();
});

test('a browser without Wasm tail calls says so', async ({ page }) => {
  // the module CertiRocq emits is built on tail calls; the probe in index.js
  // validates a module that uses one, so failing validation is the whole
  // feature test
  await page.addInitScript(() => { WebAssembly.validate = () => false; });
  await page.goto('/');

  await expect(page.locator('#err')).toBeVisible();
  await expect(page.locator('#err')).toContainText('does not support Wasm tail calls');
  await expect(page.locator('#board')).toBeHidden();
  await expect(page.locator('#controls')).toBeHidden();
});

test.describe('scripting disabled', () => {
  test.use({ javaScriptEnabled: false });

  test('the noscript message replaces the board that cannot work', async ({ page }) => {
    await page.goto('/');

    await expect(page.locator('noscript p.error')).toBeVisible();
    await expect(page.locator('noscript p.error')).toContainText('JavaScript is disabled');
    // the style inside the <noscript> element hides the dead game
    await expect(page.locator('#board')).toBeHidden();
    await expect(page.locator('#controls')).toBeHidden();
    await expect(page.locator('#btn-new')).toBeHidden();
  });
});

test('with scripting on, nothing of the noscript block reaches the page', async ({ page }) => {
  await bootFresh(page);
  await expect(page.locator('p.error')).toHaveCount(0);
  await expect(page.locator('#controls')).toBeVisible();
});
