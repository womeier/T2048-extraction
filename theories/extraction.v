(******************************************************************************)
(*  T2048 — Wasm extraction via CertiRocq                                     *)
(*                                                                            *)
(*    init_with_seed : uint63 -> state                                        *)
(*    next : T2048.move * state -> state * message                            *)
(*                                                                            *)
(*  The state and the messages are lists of bytes; the state encoding         *)
(*  ("seed#c0,...,c15", the seed, then the 16 cells row by row) and its       *)
(*  round-trip statement serialize_deserialize live in serialization.v.      *)
(*  The message is one of "invalid", "lost", "won", "continue".               *)
(*                                                                            *)
(*  The initial board is empty except for a single tile (2 or 4) placed        *)
(*  by add_val from the seed. "lost" is returned when the requested move      *)
(*  was invalid and the board is stuck — no direction changes it — since      *)
(*  next_board itself never reports a loss (every valid move leaves an        *)
(*  empty cell for add_val).                                                  *)
(*                                                                            *)
(*  The top-level record T2048_wasm_api bundles the entry points so that a    *)
(*  single Wasm module contains the whole game (one shared linear memory).    *)
(******************************************************************************)

From Stdlib Require Import NArith List Uint63 Strings.Byte.
From Top Require Import T2048.
From T2048Web Require Import serialization.
From CertiRocq.Plugin Require Import CertiRocq.

Import ListNotations.

(* Messages reported by next, one byte per character *)
Definition message := list byte.

Definition m_invalid  : message := ["i"%byte; "n"%byte; "v"%byte; "a"%byte; "l"%byte; "i"%byte; "d"%byte].
Definition m_lost     : message := ["l"%byte; "o"%byte; "s"%byte; "t"%byte].
Definition m_won      : message := ["w"%byte; "o"%byte; "n"%byte].
Definition m_continue : message := ["c"%byte; "o"%byte; "n"%byte; "t"%byte; "i"%byte; "n"%byte; "u"%byte; "e"%byte].

Definition gen_values := 2 :: 4 :: nil.
Definition target := 2048.

(* ---- The seed: a primitive 63-bit integer ---- *)

(* The primitive 63-bit integer operations are realized by CertiRocq's
   default FFI; there is no registered conversion to N, so the seed is
   read out bit by bit, low to high. *)
Fixpoint seed_bits (s : Uint63.int) (i : nat) (mask : Uint63.int) (weight : N) (acc : N) : N :=
  match i with
  | O => acc
  | S i' =>
      seed_bits s i' (Uint63.add mask mask) (weight * 2)
        (acc + (if negb (Uint63.eqb (Uint63.land s mask) 0%uint63) then weight else 0))
  end.

Definition seed_N (s : Uint63.int) : N := seed_bits s 63 1%uint63 1 0.

(* ---- The game ---- *)

(* T2048's next_board never returns "loss" on its own in practice: it just says "invalid move". *)
Definition stuck (b : list (list N)) : bool :=
  andb (eq_board (make_move size Rm b) b)
    (andb (eq_board (make_move size Lm b) b)
      (andb (eq_board (make_move size Um b) b)
        (eq_board (make_move size Dm b) b))).

Definition init_with_seed (s : Uint63.int) : state :=
  match add_val (seed_N s) gen_values (make_board size) with
  | Some (s1, b1) => state_of_game s1 b1
  | None => state_of_game (seed_N s) (make_board size)
  end.

Definition next (p : T2048.move * state) : state * message :=
  let '(m, st) := p in
  let '(s, b) := game_of_state st in
  match next_board size s gen_values target m b with
  | iresult   => (st, if stuck b then m_lost else m_invalid)
  | lresult   => (st, m_lost)
  | wresult b1 => (state_of_game s b1, m_won)
  | vresult s1 b1 => (state_of_game s1 b1, m_continue)
  end.

(* A full board with no adjacent equal tiles: every direction leaves it
   unchanged, so it is stuck. *)
Definition dead_board : list (list N) :=
  (2 :: 4 :: 2 :: 4 :: nil) ::
  (4 :: 2 :: 4 :: 2 :: nil) ::
  (2 :: 4 :: 2 :: 4 :: nil) ::
  (4 :: 2 :: 4 :: 2 :: nil) :: nil.

Eval vm_compute in (game_of_state (init_with_seed 12345%uint63)).
Eval vm_compute in (next (Rm, init_with_seed 12345%uint63)).   (* continue *)
Eval vm_compute in (next (Um, init_with_seed 12345%uint63)).   (* continue *)
Eval vm_compute in (next (Rm, state_of_game 42 dead_board)).  (* lost *)

(************************* EXTRACTION ****************************************************)

(* Single entry point: everything ends up in one Wasm module.
   The record gives the JavaScript side a single block holding one
   closure per field, in field order. *)
Record wasm_api := MkWasmApi {
  api_next           : T2048.move * state -> state * message;
  api_init_with_seed : Uint63.int -> state
}.

Definition T2048_wasm_api : wasm_api :=
  {| api_next := next;
     api_init_with_seed := init_with_seed |}.

CertiRocq Compile Wasm T2048_wasm_api.
